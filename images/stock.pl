#!<Actinic:Variable Name="PerlPath"/> 
#-d:ptkdb
#######################################################
#																				#
# Stock.pl - real time stock management script											#
#																				#
# Copyright (c) 2009 ACTINIC SOFTWARE Plc											#
#																				#
# Written by Zoltan Magyar 														#
#																				#
#######################################################

#
# Make sure "." is included in the @INC directory list so we can find our packages
#
my $bFound = 0;
my $sDir;
foreach $sDir (@INC)
	{
	if ($sDir eq ".")
		{
		$bFound = 1;
		last;
		}
	}
if (!$bFound)
	{
	push (@INC, ".");
	}
#
# NT systems rarely execute the CGI scripts in the cgi-bin, so attempt to locate
# the packages in that case.  This may still fail if the cgi-bin folder is named
# something else, but at least we will catch 80% of the cases.  The INCLUDEPATHADJUSMENT
# covers the remaining cases.
#
push (@INC, "cgi-bin");
<Actinic:Variable Name="IncludePathAdjustment"/>

require <Actinic:Variable Name="ActinicConstantsPackage"/>;
require <Actinic:Variable Name="StockManagerPackage"/>;

umask (0177);

use strict;
use Socket;
#?use CGI::Carp qw(fatalsToBrowser);
#
# Version information
#
$::prog_name = "STOCK";								# Program Name (8 characters)
$::prog_ver = '$Revision: 18819 $';						# program version (6 characters)
$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
$::prog_ver =~ s/ \$//;									# and the trailers
#
# Main section
#
DispatchCommands();										# process the commands

exit;

##############################################################################################################
#
# Command Processing - Begin
#
##############################################################################################################

#######################################################
#
# DispatchCommands - parse the command input and
#	call the command processing function
#
# Expects:	%g_InputHash, and %g_SetupBlob
#					should be defined
#
#######################################################

sub DispatchCommands
	{
	my (@Response, $Status, $Message, $sHTML, $sAction, $temp);
	
	($Status, $Message, $::g_OriginalInputData, $temp, %::g_InputHash) = ReadAndParseInput();
	my $StockManager = new StockManager($::s_sPath);
	if ($Status != $::SUCCESS)
		{
		$StockManager->TerminalError($Message);
		}
	
	$sAction = $::g_InputHash{"ACTION"};			# check the page action
	if ($sAction eq "GETSTOCK")	
		{
		($Status, $Message, $sHTML) = $StockManager->GetStock($::g_InputHash{"REF"});
		}
	elsif ($sAction eq "GETSECTIONSTOCK")	
		{
		($Status, $Message, $sHTML) = $StockManager->GetStockForSection($::g_InputHash{"SID"});
		}
	elsif ($sAction eq "SETSTOCK")	
		{
		($Status, $Message, $sHTML) = $StockManager->SetStock([split /\|/, $::g_InputHash{"REF"}], [split /\|/, $::g_InputHash{"VAL"}]);
		}
	elsif ($sAction eq "ALLOCATESTOCK")	
		{
		($Status, $Message, $sHTML) = $StockManager->AllocateStock([split /\|/, $::g_InputHash{"REF"}], [split /\|/, $::g_InputHash{"VAL"}]);
		}
	#
	# Unsupported ACTION???
	# Bomb out with an error message
	#
	else														# there is no ACTION specified
		{
		$StockManager->TerminalError("Unsupported action");
		exit;
		}
		
	if ($Status != $::SUCCESS)							# search engine error
		{
		$sHTML = $Message;
		}
	PrintPage($sHTML, 'text/html');		
	}

#######################################################
#
# ReadAndParseInput - read the input and parse it
#
# Expects:	$::ENV to be defined
#
# Returns:	0 - status
#				1 - error message
#				2 - the input string
#				3 - spacer to keep output even
#				4+ - input hash table
#
#######################################################

sub ReadAndParseInput
	{
	my ($InputData, $nInputLength);

	#
	# !!!!!! This is a function commonly used by many utilities.  Any changes to its interface will
	# !!!!!! need to be verified with the various utility scripts.
	#

	if ( (length $::ENV{'QUERY_STRING'}) > 0)		# if there is query string data (GET)
		{
		$InputData = $::ENV{'QUERY_STRING'};		# read it
		$nInputLength = length $InputData;
		}
	else														# otherwise, there must be a POST
		{
		my ($nStep, $InputBuffer);
		$nInputLength = 0;
		$nStep = 0;
		while ($nInputLength != $ENV{'CONTENT_LENGTH'})	# read until you have the entire chunk of data
			{
			#
			# read the input
			#
			binmode STDIN;
			$nStep = read(STDIN, $InputBuffer, $ENV{'CONTENT_LENGTH'});  # Set $::g_InputData equal to user input
			$nInputLength += $nStep;					# keep track of the total data length
			$InputData .= $InputBuffer;				# append the latest chunk to the total data buffer
			if (0 == $nStep)								# EOF
				{
				last;											# stop read
				}
			}

		if ($nInputLength != $ENV{'CONTENT_LENGTH'})
			{
			return ($::FAILURE, "Bad input.  The data length actually read ($nInputLength) does not match the length specified " . $ENV{'CONTENT_LENGTH'} . "\n", '', '', 0, 0);
			}
		}
	$InputData =~ s/&$//;								# loose any bogus trailing &'s
	$InputData =~ s/=$/= /;								# make sure trailing ='s have a value
	my ($OriginalInputData);
	$OriginalInputData = $InputData;					# copy the input string for use later

	if ($nInputLength == 0)								# error if there was no input
		{
		return ($::FAILURE, "The input is NULL", '', '', 0, 0);
		}
	#
	# parse and decode the input
	#
	my (@CheckData, %DecodedInput);
	@CheckData = split (/[&=]/, $InputData);		# check the input line
	if ($#CheckData % 2 != 1)
		{
		return ($::FAILURE, "Bad input string \"" . $InputData . "\".  Argument count " . $#CheckData . ".\n", '', '', 0, 0);
		}
	my %EncodedInput = split(/[&=]/, $InputData);	# parse the input hash
	my ($key, $value);
	while (($key, $value) = each %EncodedInput)
		{
		if ($key !~ /BLOB/i)								# do not censor the order BLOB
			{
			if (($value =~ /[\(\)]/) ||				# reject ( and ) before decoding
			  ($value =~ /[<>]/))						# reject < and > before decoding
				{
				return ($::FAILURE, "Input contains invalid characters.", undef, undef, undef, undef);
				}
			}
		$key = DecodeText($key);	# decode the hash entry
		$value = DecodeText($value);
		if ($key =~ /\0/)									# check for poison NULLs in key
			{
			return ($::FAILURE, "Input contains invalid characters.", undef, undef, undef, undef);
			}
		if ($key !~ /BLOB/i)								# do not censor the order BLOB value
			{
			if ($value =~ /\0/)							# check for poison NULLs in value
				{
				return ($::FAILURE, "Input contains invalid characters.", undef, undef, undef, undef);
				}
			#
			# Restrict the length of data between <> brackets
			#
			if ($key !~ /TEXTDATA/i)
				{
				if (($value =~ /.*?\<(.*)\>/s) &&	# if there is text between the outer bracket pair
					 ($::eABDataLimit < length $1))	# and the length of the text is greater than the allowed length
					{
					while($value =~ s/(\<)(.*?)(\>)/\[$2\]/gs) {}
					}
				}
			}
		$DecodedInput{$key} = $value;
		}
	#
	# Now process the path to the catalog directory.  In stand alone mode, the path is hard coded in the script.
	# In Actinic Host mode, the path is derived from the SHOPID and the shop data file.
	#
	my ($status, $sError) = ProcessPath($DecodedInput{SHOP}, \%DecodedInput);
	if ($status != $::SUCCESS)
		{
		return ($status, $sError);
		}

	return ($::SUCCESS, '', $OriginalInputData, '', %DecodedInput);
	}

#######################################################
#
# ProcessPath - process the input to derive a path
#   to the catalog directory
#
# Params:	0 - shop ID if in Actinic Host Mode
#               or undef if stand alone
#
# Returns:	0 - status
#				1 - error message
#
#######################################################

sub ProcessPath
	{
	my ($sShopID, $rhInput) = @_;
	my ($status, $sError);
	#
	# Now process the path to the catalog directory.  In stand alone mode, the path is hard coded in the script.
	# In Actinic Host mode, the path is derived from the SHOPID and the shop data file.
	#
	my $sInitialPath = '<Actinic:Variable Name="PathFromCGIToWeb"/>';
	if (!<Actinic:Variable Name="ActinicHostMode"/>)				# stand alone mode
		{
		$::s_sPath = $sInitialPath;
		}
	else
		{
		#
		# Load the module for access to the configuration files
		#
		eval
			{
			require AHDClient;
			};
		if ($@)												# the interface module does not exist
			{
			return ($::FAILURE, 'An error occurred loading the AHDClient module.  ' . $@);
			}
		my ($nStatus, $pClient);
		($nStatus, $sError, $pClient) = new_readonly AHDClient($sInitialPath);
		if ($nStatus!= $::SUCCESS)
			{
			return($nStatus, $sError);
			}
		#
		# Retrieve the appropriate record
		#
		($status, $sError, my $pShop) = $pClient->GetShopDetails($sShopID);
		if ($status != $::SUCCESS)		 				# error during the query
			{
			return ($status, $sError);
			}
		if (!defined($pShop))							# no shop with this ID
			{
			return ($::BADDATA, $sError);
			}
		#
		# Retrieve the specific path
		#
		$::s_sPath = $pShop->{Path};
		}

	return ($::SUCCESS, undef);
	}
	
#######################################################
#
# DecodeText - standard URL decode
#
# Params:	0 - the string to convert
#
# Returns:	($sString) - the converted string
#
#######################################################

sub DecodeText
	{
	my ($sString) = @_;

	$sString =~ s/\+/ /g;							# replace + signs with the spaces they represent
	$sString =~ s/%([A-Fa-f0-9]{2})/pack('c',hex($1))/ge;	# Convert %XX from hex numbers to character equivalent

	return ($sString);
	}
	
#######################################################
#
# PrintPage - Print the HTML to the browser.  NOTE:
#	this is just a wrapper for the ACTINIC package
#	function.
#
# Params:	[0] - HTML
#				[1] - Cookie (optional)
#				[2] - cache flag (optional - default no-cache)
#
#######################################################

sub PrintPage
	{
	my ($sHTML, $sType) = @_;
			 
	binmode STDOUT;										# dump in binary mode since Netscape likes it

	my $nLength = length $sHTML;
	if($ENV{'PerlXS'} eq 'PerlIS')					# Windows IIS6 may be using PerIS.dll insteasd of perl.exe
		{
		print "HTTP/1.0 200 OK\n";						# so we must insert the protocol and return status
		}
	print "Content-type: $sType\r\n";
	print "Content-length: $nLength\r\n";
	print "\r\n";
	
	print $sHTML;
	}
