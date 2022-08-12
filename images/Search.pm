#!perl
################################################################
#
#  Search.pm - provides search functionalities
#
#  Based on 
#    Search functions of searchscript.pl
#
#  Tibor Vajda
#
#  Copyright (c) Actinic Software Plc 2001
#
################################################################
package Search;
require 5.002;

push (@INC, "cgi-bin");
<Actinic:Variable Name="IncludePathAdjustment"/>

require <Actinic:Variable Name="ActinicPackage"/>;

use strict;
#
# Constants definition
#
require <Actinic:Variable Name="ActinicConstantsPackage"/>;
#
# Version
#
$Search::prog_name = 'Search.pm';						# Program Name
$Search::prog_name = $Search::prog_name;				# remove compiler warning
$Search::prog_ver = '$Revision: 18819 $ ';					# program version
$Search::prog_ver = substr($Search::prog_ver, 11); # strip the revision information
$Search::prog_ver =~ s/ \$//;								# and the trailers

$::ANY_PRICE_BAND = -1;

$::MAX_RETRY_COUNT      = 10;
$::RETRY_SLEEP_DURATION = 1;

################################################################
#
# OpenTextIndex - open the text index
#
# Input:	   0 - the path to the data files
# Output:   1 - reference to the file handle
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub OpenTextIndex
	{
#? ACTINIC::ASSERT($#_ == 1, "Incorrect parameter count OpenTextIndex (" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $rFile) = @_;
	#
	# Open the index.  Retry a couple of times on failure just incase an update is in progress.
	#
	my ($status, $sError);
	my $nRetryCount = $::MAX_RETRY_COUNT;
	$status = $::SUCCESS;
	my $sFileName = $sPath . "oldtext.fil";
	my $nExpected = $::g_nSearchTextIndexVersion;		# expected version number
	while ($nRetryCount--)
		{
		unless (open ($rFile, "<$sFileName"))
			{
			$sError = $!;
			sleep $::RETRY_SLEEP_DURATION;			# pause a moment
			$status = $::FAILURE;
			$sError = ACTINIC::GetPhrase(-1, 246, $sFileName, $sError);
			next;
			}
		binmode $rFile;
	   #
	   # Check the file version number
	   #
		my $sBuffer;
		unless (read($rFile, $sBuffer, 4) == 4)		# read the blob version number (a short)
			{
			$sError = $!;
			close ($rFile);
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 252, $sError));
			}

		my ($nVersion) = unpack("n", $sBuffer);	# convert to a number
		if ($nVersion != $nExpected)
			{
			close($rFile);
			sleep $::RETRY_SLEEP_DURATION;			# pause a moment
			$status = $::FAILURE;
			$sError = ACTINIC::GetPhrase(-1, 259, $nExpected, $nVersion);
			next;
			}

		last;
		}
	if ($status != $::SUCCESS)							 # file never loaded
		{
		return($status, $sError);
		}

	return ($::SUCCESS);
	}

###############################################################
#
# WordSearch - search an index for a word.  The results of this
#   recursive function is a hash where the keys are product
#   references.
#
# Input:	   0 - string to look for
#           1 - point to start in the file
#           2 - file handle
# Output:   3 - reference to product reference hash table
#
# Returns:  0 - status
#           1 - error message
#
###############################################################

sub WordSearch
	{
#? ACTINIC::ASSERT($#_ == 3, "Incorrect parameter count WordSearch(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sWord, $nLocation, $rFile, $rhashProdRefs) = @_;

	my ($nDependencies, $nCount, $nRefs, $sRefs, $sBuff, $sFragment, $sAnchor);
	my ($nIndex, $sSeek, $nHere, $nLength, $sNext, $nRead);
	#
   # At the start of the file, we have an (empty) anchor list
   # followed by a list of dependency records
	#
	unless (seek($rFile, $nLocation, 0))			# Seek to node
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 247, $!));
		}
	#
   # Read the anchors (if any)
	#
	unless (read($rFile, $sBuff, 2) == 2)			# Read the count
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
		}

	($nCount) = unpack("n", $sBuff);					# Turn into an integer

	for ($nIndex = 0; $nIndex < $nCount; $nIndex++)
		{
		unless (read($rFile, $sBuff, 2) == 2)		# Get anchor length
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
			}

		($nLength) = unpack("n", $sBuff);			# unpack the anchor length

		unless (read ($rFile, $sAnchor, $nLength) == $nLength) # read the anchor
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
			}

		unless (read($rFile, $sBuff, 1) == 1)		# read the reference count
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
			}
		($nRefs) = unpack("C", $sBuff);				# Unpack it

		$sRefs = "";										# Kill left-over references
		if ($nRefs > 0)
			{
			unless (read($rFile, $sRefs, $nRefs) == $nRefs)	# Read and ignore the actual refs
				{
				return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
				}
			}

		if ($sWord eq "")									# If this is a match
			{
			$$rhashProdRefs{$sAnchor} = $$rhashProdRefs{$sAnchor} . $sRefs;	# Add anchor reference list to hash
			}
		}
	#
   # Now search the dependencies
   #
	unless (read($rFile, $sBuff, 2) == 2)			# Read count
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
		}
	$nDependencies = unpack("n", $sBuff);			# Count of dependencies (network short)

	for ($nIndex = 0; $nIndex < $nDependencies; $nIndex++)
		{
		unless (read($rFile, $sBuff, 1) == 1)		# Read fragment length
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
			}
		$nLength = unpack("C", $sBuff);				# Unpack it

		unless (read($rFile, $sFragment, $nLength) == $nLength) # Read the string fragment
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
			}

		unless (read($rFile, $sSeek, 4) == 4)		# Read the link (convert later, if we need it)
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 248, $!));
			}
		unless ($$::g_pSetupBlob{SEARCH_MATCH_WHOLE_WORDS})
			{
			#
			# We only care about the fragment length as far as
			# the length of the word we're looking for
			#
			$sFragment = substr($sFragment, 0, length($sWord)); # Reduce fragment to useful length
			}
		#
		# Allow special regex characters in $sFragment
		#
		my $sQuotedFragment = quotemeta($sFragment);
		#
		# If the fragment partially matches our word then we
		# continue down the tree. It only needs to match as much
		# of the word as we have - it's perfectly possible for
		# the fragment to be longer than the word
		#
		if ($sWord =~ m/^$sQuotedFragment/i)		# Does it match?
			{
			$sNext = $';									# Get part after match
			$nHere = tell($rFile);						# Save where we are

			my ($status, $sError) = WordSearch($sNext, unpack("N", $sSeek), $rFile, $rhashProdRefs); # Look down tree
			if ($status != $::SUCCESS)
				{
				return ($status, $sError);
				}

			unless (seek($rFile, $nHere, 0))			# Back to where we were
				{
				return ($::FAILURE, ACTINIC::GetPhrase(-1, 247, $!));
				}
			}

		if ($sFragment gt $sWord)						# If we've passed the point in the list
			{
			last;												# Don't look further
			}
		}
	return ($::SUCCESS);
	}

################################################################
#
# SearchText - search the catalog for the specified text
#
# Input:	   0 - the path to the data files
#			   1 - a reference to the space separated search strings
#			   2 - join operation
# Output:   1 - a reference to the modified string - stop words
#               are stripped and non-word characters are replaced
#               by breaks (spaces)
#           3 - reference to a hash to fill
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub SearchText
	{
#? ACTINIC::ASSERT($#_ == 3, "Incorrect parameter count SearchText(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $psSearchString, $bJoin, $rhashResults) = @_;
	# 
	# Split words on the same boundaries as the C++ does
	# 
	my $sWordCharacters = ACTINIC::GetPhrase(-1, 239);
	my $sSplitString = "[^\Q$sWordCharacters\E]";	# form a regular expression for replacing non-word characters with spaces which we split on
	$$psSearchString =~ s/$sSplitString/ /g;		# now break up the search strings the same as the C++ did (here the breaks are represented by spaces)
	
	my $sStopList = ACTINIC::GetPhrase(-1, 238);	# get the stop list from the prompt file
	#
	# Combine any multiple-white-spaces into single space
	#
	$$psSearchString =~ s/\s+/ /go;
	#
	# The index is stored in lower case
	#
	$$psSearchString = lc $$psSearchString;		# lc the search string so it has a chance to match the index
	$sStopList = lc $sStopList;						# lc the stop list so we can skip the stop words
	#
	# And it can be extended character which is not handled by lc
	# so lets convert them here.	- zmagyar - 01 Feb 2001
	#
	$$psSearchString =~ tr/[ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞ]/[àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþ]/; # complete the lc for the search string
	$sStopList =~ tr/[ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞ]/[àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþ]/; # ditto the stop list
	#
	# Retrieve the list of words to look for.  They are space delimited.
	#
	my @listPreliminarySearchWords = split(/ +/, $$psSearchString); # do the actual split
	# 
	# Throw out blank entries (if any - there shouldn't be) and words in the stop list
	# 
	my ($sWord, @listSearchWords);
	foreach $sWord (@listPreliminarySearchWords)
		{
		if ($sWord eq '' ||								# blank entry or
		    $sStopList =~ /\b$sWord\b/)				# this word is in the stop list
			{
			next;												# toss it
			}

		push (@listSearchWords, $sWord);				# this is a good word, add it to the search list
		}
	# 
	# Patch up the search string so highlights work properly - this value is used by the calling function
	# 
	$$psSearchString = join(' ', @listSearchWords);
   #
   # Check for the special case of having nothing to search for
   #
   if (!@listSearchWords)
		{
		return ($::SUCCESS);
		}
	#
	# Open the index.
	#
	my ($status, $sError) = OpenTextIndex($sPath, \*INDEX);
	if ($status != $::SUCCESS)							 # file never loaded
		{
		return($status, $sError);
		}
	#
	# Now loop through the words and retrieve the lists of hits building an array of lists.  The lists
	# are stored as hashes to guarantee uniqueness.
	#
	my (@HitLists, $rhash);
	foreach $sWord (@listSearchWords)
		{
#? ACTINIC::ASSERT($sWord ne '', "Empty search string.", __LINE__, __FILE__);
		$rhash = {};										 # allocate a new hash

		($status, $sError) = WordSearch($sWord, 2, \*INDEX, $rhash); # do the search - the 2 is the number of bytes into the file where the index begins (after the 2 byte version number)
		if ($status != $::SUCCESS)
			{
			close (INDEX);
			return ($status, $sError);
			}

		push (@HitLists, $rhash);						 # add the hash to the list of hits
		}
	close (INDEX);											 # close the index file
	#
	# Now join the results
	#
	my ($rhashCurrent, $rhashNext, $rhashLast);
	$rhashLast = shift @HitLists;
	foreach $rhashCurrent (@HitLists)
		{
		$rhashNext = {};									 # allocate a hash for the results
		ACTINIC::JoinHashes($rhashLast, $rhashCurrent, $bJoin, $rhashNext); # do the join
		$rhashLast = $rhashNext;						 # use the results for the next join
		}

	%$rhashResults = %$rhashLast;						 # copy the results to the output hash
	#
	# Log search words
	#
	LogSearchWords($$psSearchString, scalar keys %$rhashResults);
	return ($::SUCCESS);
	}

################################################################
#
# SearchSection - find all products in the given section
#
# Input:	   0 - the path to the data files
#			   1 - section ID in question - if undef, return immediately
# Output:   2 - reference to a hash to fill
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub SearchSection
	{
#? ACTINIC::ASSERT($#_ == 2, "Incorrect parameter count SearchSection (" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $nSectionID, $rhashResults) = @_;
	undef %$rhashResults;								# clear the results hash
   #
   # Check for the special case of having nothing to search for
   #
   if (!$nSectionID)
		{
		return ($::SUCCESS);
		}
	#
	# Open the index.
	#
	my ($status, $sError) = OpenTextIndex($sPath, \*INDEX);
	if ($status != $::SUCCESS)							 # file never loaded
		{
		return($status, $sError);
		}
	#
	# Look for the products related to this section (and child sections)
	#
	my $sWord = sprintf('!@%8.8x', $nSectionID);
	($status, $sError) = WordSearch($sWord, 2, \*INDEX, $rhashResults); # do the search - the 2 is the number of bytes into the file where the index begins (after the 2 byte version number)
	if ($status != $::SUCCESS)
		{
		close (INDEX);
		return ($status, $sError);
		}

	close (INDEX);											 # close the index file

	return ($::SUCCESS);
	}

################################################################
#
# SearchProperty - find all products with given Property and Value
#
# Input:	   0 - the path to the data files
#			   1 - CGI Property Name in question - if undef, return immediately
#			   2 - Specified Property value - if undef, return immediately
# Output:   3 - reference to a hash to fill
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub SearchProperty
	{
#? ACTINIC::ASSERT($#_ == 3, "Incorrect parameter count SearchProperty (" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $sPropertyName, $sPropertyValue, $rhashResults) = @_;
	#
	# Convert CGI Property Name to Index Property Name
	#
	$sPropertyName =~ s/^S_(.*)_\d+$/$1/;
   #
   # Check for the special case of having nothing to search for
   #
   if ((!$sPropertyName) or
		 ($sPropertyValue eq ''))
		{
		return ($::SUCCESS);
		}
	#
	# Open the index.
	#
	my ($status, $sError) = OpenTextIndex($sPath, \*INDEX);
	if ($status != $::SUCCESS)							 # file never loaded
		{
		return($status, $sError);
		}
	#
	# Look for the products with this value for this property
	#
	my $sWord = "!!$sPropertyName!$sPropertyValue";
	($status, $sError) = WordSearch($sWord, 2, \*INDEX, $rhashResults); # do the search - the 2 is the number of bytes into the file where the index begins (after the 2 byte version number)
	if ($status != $::SUCCESS)
		{
		close (INDEX);
		return ($status, $sError);
		}

	close (INDEX);											 # close the index file

	return ($::SUCCESS);
	}

################################################################
#
# SearchPriceSchedule - find all products with the specified price schedule
#
# Input:	   0 - the path to the data files
#			   1 - price schedule ID in question 
# Output:   2 - reference to a hash to fill
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub SearchPriceSchedule
	{
#? ACTINIC::ASSERT($#_ == 2, "Incorrect parameter count SearchPriceSchedule (" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $nPriceScheduleID, $rhashResults) = @_;
	undef %$rhashResults;								# clear the results hash
	#
	# Open the index.
	#
	my ($status, $sError) = OpenTextIndex($sPath, \*INDEX);
	if ($status != $::SUCCESS)							 # file never loaded
		{
		return($status, $sError);
		}
	#
	# Look for the products related to this price schedule 
	#
	my $sWord = sprintf('!&%s', $nPriceScheduleID);
	($status, $sError) = WordSearch($sWord, 2, \*INDEX, $rhashResults); # do the search - the 2 is the number of bytes into the file where the index begins (after the 2 byte version number)
	if ($status != $::SUCCESS)
		{
		close (INDEX);
		return ($status, $sError);
		}

	close (INDEX);											 # close the index file

	return ($::SUCCESS);
	}

###############################################################
#
# SearchPrice - search an index for the list of products within
#   the given price band.  The result of this function is a
#   hash containing the unique product references.  Note that
#   this function returns immediately if the price band is
#   set to $::ANY_PRICE_BAND.
#
# Input:	   0 - path
#           1 - price band
# Output:   2 - reference to product reference hash table
#
# Returns:  0 - status
#           1 - error message
#
###############################################################

sub SearchPrice
	{
#? ACTINIC::ASSERT($#_ == 2, "Incorrect parameter count SearchPrice(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $nPriceBand, $rhashProdRefs) = @_;
	#
	# Check for the "any" band case.
	#
	if ($nPriceBand == $::ANY_PRICE_BAND)
		{
		return ($::SUCCESS);
		}
	#
	# Load the price band blob.  Use a patient method to load the file and validate it because the web site may be in mid update.
	#
	my $nRetryCount = $::MAX_RETRY_COUNT;
	my ($status, $sError);
	my $nExpectedVersion = 0;
	while ($nRetryCount--)
		{
		($status, $sError) = ACTINIC::ReadConfigurationFile($sPath . "priceband.fil"); # load the file
		if ($status != $::SUCCESS)						# on error,
			{
			sleep $::RETRY_SLEEP_DURATION;			# pause a moment
			$sError .= ACTINIC::GetPhrase(-1, 256);
			next;												# and try again
			}

		if ($nPriceBand >= $#$::g_pPriceBand)		# the price band is out of range
			{
			sleep $::RETRY_SLEEP_DURATION;			# pause a moment
			$status = $::FAILURE;						# record the problem
			$sError = ACTINIC::GetPhrase(-1, 249);
			next;												# and try again
			}

		if ($::gnPriceBandVersion != $nExpectedVersion)	# verify the file format version
			{
			sleep $::RETRY_SLEEP_DURATION;			# pause a moment
			$status = $::FAILURE;						# record the problem
			$sError = ACTINIC::GetPhrase(-1, 257, $nExpectedVersion, $::gnPriceBandVersion);
			next;												# and try again
			}

		last;													# success, exit
		}
	if ($status != $::SUCCESS)							# file never loaded
		{
		return($status, $sError);
		}
	#
	# Now find the bounding regions in the price index
	#
	my $nLowerBound = $$::g_pPriceBand[$nPriceBand];
	my $nUpperBound = $$::g_pPriceBand[$nPriceBand + 1];
	#
	# Open the price index.  Again - be patient.
	#
	$nRetryCount = $::MAX_RETRY_COUNT;
	$status = $::SUCCESS;
	my $sFileName = $sPath . "oldprice.fil";
   my $nExpected = 0;										# the anticipated version number
	while ($nRetryCount--)
		{
		unless (open (INDEX, "<$sFileName"))
			{
			sleep $::RETRY_SLEEP_DURATION;			# pause a moment
			$status = $::FAILURE;
			$sError = ACTINIC::GetPhrase(-1, 250, $sFileName, $!);
			next;
			}
		binmode INDEX;
	   #
	   # Check the file version number
	   #
		my $sBuffer;
		unless (read(INDEX, $sBuffer, 2) == 2)		# read the blob version number
			{
			$sError = $!;
			close (INDEX);
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 252, $sError));
			}

		my ($nVersion) = unpack("N", $sBuffer);	# convert to a number
		if ($nVersion != $nExpected)
			{
			close(INDEX);
			sleep $::RETRY_SLEEP_DURATION;			# pause a moment
			$status = $::FAILURE;
			$sError = ACTINIC::GetPhrase(-1, 258, $nExpected, $nVersion);
			next;
			}

		last;
		}
	if ($status != $::SUCCESS)							# file never loaded
		{
		return($status, $sError);
		}
	#
	# Now read the matching product references
	#
	unless (seek (INDEX, $nLowerBound, 0))			# find the beginning of the matching region
		{
		$sError = $!;
		close (INDEX);
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 251, $sError));
		}

	my $nBytesToRead = $nUpperBound - $nLowerBound;
   my $sBuffer;
	unless (read(INDEX, $sBuffer, $nBytesToRead) == $nBytesToRead)	# read the product references
		{
		$sError = $!;
		close (INDEX);
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 252, $sError));
		}
	close (INDEX);
	#
	# The data read from the index is a list of product references in the range separated by !'s
	#
	%$rhashProdRefs = map {$_ => 0} split(/\|/, $sBuffer);	# parse the product references and dump them to the hash

	return ($::SUCCESS);
	}

################################################################
#
# SearchProductGroup - find all products in the given group
#
# Input:	   0 - the path to the data files
#			   1 - group ID in question - if undef, return immediately
# Output:   2 - reference to a hash to fill
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub SearchProductGroup
	{
#? ACTINIC::ASSERT($#_ == 2, "Incorrect parameter count SearchProductGroup (" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $nGroupID, $rhashResults) = @_;
	undef %$rhashResults;								# clear the results hash
   #
   # Check for the special case of having nothing to search for
   #
   if (!$nGroupID)
		{
		return ($::SUCCESS);
		}
	#
	# Open the index.
	#
	my ($status, $sError) = OpenTextIndex($sPath, \*INDEX);
	if ($status != $::SUCCESS)							 # file never loaded
		{
		return($status, $sError);
		}
	#
	# Look for the products related to this section (and child sections)
	#
	my $sWord = sprintf('!D!%8.8x', $nGroupID);
	($status, $sError) = WordSearch($sWord, 2, \*INDEX, $rhashResults); # do the search - the 2 is the number of bytes into the file where the index begins (after the 2 byte version number)
	if ($status != $::SUCCESS)
		{
		close (INDEX);
		return ($status, $sError);
		}

	close (INDEX);											 # close the index file

	return ($::SUCCESS);
	}
	
###############################################################
#
# LogSearchWords - open the search log file and store the
#   search words alongside some other data
#
# Input:	   0 - the word list
#				1 - the number of hits
#
# Returns:  Nothing - all error recorded to error.err
#           as the logging error shouldn't hold on the process
#
###############################################################

sub LogSearchWords
	{
	my $sWordList = shift;
	my $nHits = shift;
	#
	# If logging is not turned on then bomb out
	#
	if (length $::SEARCH_WORD_LOG_FILE == 0)
		{
		return;
		}
	my $sUserDigest = $ACTINIC::B2B->Get('UserDigest');
	my ($nBuyerID, $nCustomerID) = (0, 0);
	
	if ($sUserDigest)
		{
		my ($status, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sUserDigest, ACTINIC::GetPath());
		if ($status != $::SUCCESS)
			{
			return ($status, $sMessage);
			}
		$nBuyerID = $$pBuyer{ID};
		$nCustomerID = $$pBuyer{AccountID};		
		}
		
	my $sFilename = ACTINIC::GetPath() . $::SEARCH_WORD_LOG_FILE;
	my $bDoHeader = !-e $sFilename;
	#
	# Double up all qoutes
	#
	$sWordList =~ s/"/""/;								# "
	#
	# The log file is a comma separated file which contain the following 
	# items:
	#
	# 	0 - date/time
	# 	1 - browser name or IP address
	# 	3 - customer ID
	#	4 - buyer ID
	#	5 - word list
	#
	open (LOGFILE, ">>" . $sFilename);
	#
	# If the file doesn't exist then create its header
	#
	if ($bDoHeader)	
		{
		print LOGFILE "Version: $::EC_MAJOR_VERSION\nDate, Remote host, Customer ID, Buyer ID, Search words\n";
		}
	print LOGFILE ACTINIC::GetActinicDate();
	print LOGFILE ", ";
	print LOGFILE (length $::ENV{REMOTE_HOST} > 0 ? $::ENV{REMOTE_HOST} : $::ENV{REMOTE_ADDR});
	print LOGFILE ", ";
	print LOGFILE $nCustomerID;
	print LOGFILE ", ";
	print LOGFILE $nBuyerID;
	print LOGFILE ", ";
	print LOGFILE "\"$sWordList\", $nHits";	
	print LOGFILE "\n";
	close LOGFILE;	
	}
	
1;