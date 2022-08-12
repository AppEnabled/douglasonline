#!perl

###############################################################
#
# $Revision: 18819 $
#
###############################################################

use strict;

package DigitalDownload;
#
# The following are configuration values:
#
$DigitalDownload::CONTENTPATH = '<Actinic:Variable Name="PathFromCGIToWeb"/>' . 'DD/'; # needs to be set to the path to the digital content - requires trailing slash

#
# Determine the download script URL, this will be HTTPS if the BaseHref uses HTTPS
#
<actinic:block if="IsBaseHREFStandard">
	$DigitalDownload::CGIBINURL = '<Actinic:Variable Name="CgiUrl"/>';
</actinic:block>
<actinic:block if="IsBaseHREFSSL">
	$DigitalDownload::CGIBINURL = '<Actinic:Variable Name="SSLCgiUrl"/>';
</actinic:block>

$DigitalDownload::XORKEY = <Actinic:Variable Name="XORKey"/>;			# override this key if you want your own XOR key

$DigitalDownload::SIGKEY = '<Actinic:Variable Name="SigKey"/>';		# override this key if you want your own signature key

$DigitalDownload::PATHINFO_OVERRIDE = 0;			# set this to true to force the use of extra path info on MS IIS

$DigitalDownload::NPH = <Actinic:Variable Name="IsNPH"/>;			# set this to true to have the server use non-parsed headers.  It is more efficient but can present problems on some systems.
																# If this is set to false, the "nph-download.pl" script needs to be renamed to "download.pl".

$DigitalDownload::FAILURE = 0;
$DigitalDownload::SUCCESS = 1;

$DigitalDownload::DOWNLOAD_SCRIPT_NAME = '<Actinic:Variable Name="DownloadScript"/>'; # the name of the download script

###############################################################
#
# GetContentList - Get the list of URLs associated with the
#   supplied list of product references.  Note that this function
#   only returns entries for product references that have associated
#   digital content.
#
# Input:	   0 - time (in hours) allowed for user to download
#               content
#           1 - reference to a list of product references in
#               the order
#
# Returns:  0 - status (0 = failure, 1 = success)
#           1 - error message or undef
#           2 - a reference to a hash
#               keys are product references
#               values are lists of URLs associated with the reference
#               Note that the hash only contains entries for
#               references that have digital content.
#
###############################################################

sub GetContentList
	{
	if (2 != @_)											# validate the call
		{
		return ($DigitalDownload::FAILURE, 'Programming Error: Invalid parameter count', undef);
		}

	my ($status, $sError) = _LoadMD5();				# load the MD5 module
	if ($status != $DigitalDownload::SUCCESS)
		{
		return ($status, $sError, undef);
		}

	my ($nDuration, $plistProductRefs) = @_;
	#
	# Early abort of empty orders
	#
	if (0 == @$plistProductRefs)
		{
		return ($DigitalDownload::SUCCESS, undef, {});
		}
	#
	# Retrieve the list of files in the CONTENTPATH directory.  Note that GLOBing wasn't used because it would
	# requery the directory multiple times (once per product reference) and could therefore be inefficient.
	#
	unless (opendir(DIR, $DigitalDownload::CONTENTPATH))
		{
		return ($DigitalDownload::FAILURE, "System Error: Unable to open content directory. $!", undef);
		}
	my @listFiles = grep									# read the directory and record files - not directories, etc.
		{-f "$DigitalDownload::CONTENTPATH/$_"}	# file test
  	   readdir DIR;
	closedir DIR;
	#
	# Look for files that match the list of supplied product referenes.  First build a regexp of the prod refs that will return a hit if it matches any of them
	#
	my ($sProdRef, $sRegExp);
	foreach $sProdRef (@$plistProductRefs)			# add each product reference in the list
		{
		$sRegExp .= (quotemeta $sProdRef) . "|";	# add it as a alternate regular expression
		}
	chop $sRegExp;											# drop the trailing |
	$sRegExp = "^($sRegExp)_";							# build the complete regexp
	#
	# Build the download limit time stamp
	#
	my $nTime = time + $nDuration * 3600;			# calculate the last second that the download is supported - note duration is in hours and nTime is in epoch seconds

	my $sBaseURL = $DigitalDownload::CGIBINURL . $DigitalDownload::DOWNLOAD_SCRIPT_NAME; # the base URL (can be relative)

	my ($sFile, %mapProdRefToFileList);
	foreach $sFile (@listFiles)						# examine each file in the list
		{
		if ($sFile =~ /$sRegExp/)						# if the file matches one of the product references we are looking to match
			{
			my $sProdRef = $1;
			#
			# Pack the download identifier and encode it
			#
			my $sEncodedString = _PackData($nTime, $sFile);
			#
			# NT IIS doesn't support PATH_INFO by default and it is difficult to make it do so.  So for now let's leave off the file bit for NT.
			#
			my $sURL = $sBaseURL;
			unless ( ($::ENV{SERVER_SOFTWARE} =~ /MICROSOFT/i ||
						 $::ENV{SERVER_SOFTWARE} =~ /IIS/i) &&
						!$DigitalDownload::PATHINFO_OVERRIDE)
				{
				#
				# Find the download name of the file - the file system names for the files are of the format productreference__nnnnnn__filename.xxx
				# where productreference is the product reference of the catalog product, nnnnnn is an arbitrary 6 digit number of the merchant's choice
				# (optionally different per file) to provide some obfuscation, filename is the name of the filename to be presented for download,  and
				# xxx is the natural file extension
				#
				$sFile =~ /$sRegExp\d+_(.*)/;
				my $sPresentationFile = $2;
				$sPresentationFile =~ s/ /+/;
				$sURL .= "/$sPresentationFile";		# add the extra path info to make the browser record the proper file
				}
			#
			# Build the complete file URL
			#
			$sURL .= "?DAT=" . $sEncodedString;
			#
			# Build a complete list of URLs for each product
			#
			if (exists $mapProdRefToFileList{$sProdRef})	# there is already at least one file associated with this product
				{
				push @{$mapProdRefToFileList{$sProdRef}}, $sURL;
				}
			else												# this is the first file for this product
				{
				$mapProdRefToFileList{$sProdRef} = [$sURL];
				}
			}
		}
	#
	# All done - return the results
	#
	return ($DigitalDownload::SUCCESS, undef, \%mapProdRefToFileList);
	}

###############################################################
#
# _LoadMD5 - Load the MD5 module regardless of location or name
#
# Returns:  0 - status (0 = failure, 1 = success)
#           1 - error message or undef
#
###############################################################

sub _LoadMD5
	{
	#
	# Load the MD5 module
	#
	eval
		{
		require Digest::MD5;								# Try loading MD5
		import Digest::MD5 'md5_hex';
		};
	if ($@)
		{
		eval
			{
			require <Actinic:Variable Name="DigestPerlMD5"/>;
			import Digest::Perl::MD5 'md5_hex';		# Use Perl version if not found
			};
		if ($@)												# error loading module
			{
			return ($DigitalDownload::FAILURE, 'Programming Error: No MD5 module found');
			}
		}

	return ($DigitalDownload::SUCCESS, undef);
	}

###############################################################
#
# _PackData - Pack, sign and encrypt the data string
#
# Input:    0 - time
#           1 - file
#
# Returns:  packed string
#
###############################################################

sub _PackData
	{
	my ($nTime, $sFile) = @_;
	#
	# Complete the download identifier and encode it
	#
	my $sDownloadString = $sFile . "\0" . $nTime;	# add the file system filename and the time to build the data string
	$sDownloadString .= "\0" . md5_hex($sDownloadString . $DigitalDownload::SIGKEY);	# calculate the signature and add it to the string

	my @listEncodedCharacters = map					# convert the string to an array of encoded characters
		{
		$_ ^ $DigitalDownload::XORKEY					# encode the character
		}
	   unpack('C*', $sDownloadString);		      # convert the character to an ascii value

	my $sEncodedString = join('',						# convert the numbers to a hex string
									  map {sprintf('%2.2x', $_)} # convert each charact to hex
									  @listEncodedCharacters);

	return $sEncodedString;
	}

###############################################################
#
# _UnpackData - Decrypt the data, unpack it and check the
#   signature.  It returns the data fields if all is OK.
#
# Input:    0 - data string
#
# Returns:  1 - status
#           2 - message
#           3 - time
#           4 - file
#
###############################################################

sub _UnpackData
	{
	my ($sString) = @_;
	#
	# Decrypt and decode the data
	#
	my @listHexSets = $sString =~ m/[0-9a-zA-Z]{2}/g; # break the string into hex duplets
	my @listHexValues = map {hex $_} @listHexSets; # convert the hex duplets to numbers
	my @listDecodedCharacters = map					# decode the string
		{
		$_ ^ $DigitalDownload::XORKEY					# decode the character
		}
	   @listHexValues;
	#
	# Build the decoded string
	#
	$sString = pack('C*', @listDecodedCharacters);
	#
	# Split the string into it's component parts
	#
	my ($sFile, $nTime, $sSignature) = split(/\0/, $sString);
	#
	# Load the MD5 module to verify the signature
	#
	my ($status, $sError) = _LoadMD5();				# load the MD5 module
	if ($status != $DigitalDownload::SUCCESS)
		{
		return ($status, $sError, undef, undef);
		}
	#
	# Verify the signature
	#
	my $sRegeneratedSig = md5_hex($sFile . "\0" . $nTime . $DigitalDownload::SIGKEY);
	if ($sRegeneratedSig ne $sSignature)
		{
		return ($DigitalDownload::FAILURE, "Error: Invalid signature", undef, undef);
		}

	return ($DigitalDownload::SUCCESS, undef, $nTime, $sFile);
	}
