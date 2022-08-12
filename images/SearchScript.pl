#!<Actinic:Variable Name="PerlPath"/>
################################################################
#
# SearchScript.pl - script to search for specified products
#
################################################################

#?use CGI::Carp qw(fatalsToBrowser);
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

require <Actinic:Variable Name="SearchPackage"/>;
require <Actinic:Variable Name="ActinicOrder"/>;
require <Actinic:Variable Name="SessionPackage"/>;

use strict;

$::prog_name = "SearchScript";						# Program Name
$::prog_name = $::prog_name;
$::prog_ver = '$Revision: 22656 $ ';					# program version
$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
$::prog_ver =~ s/ \$//;									# and the trailers
my $nFILEVERSION = 1;									# validate blob

#
# Do the main script initialization
#
my $sPath = Init();

my ($status, $sError);
#
# result constants for stack
#
my $TRUE_RESULT  =  1;
my $FALSE_RESULT =  0;
my $SKIP_RESULT  = -1;
#
# User interface types from property search specification
#
my $UI_TEXTBOX        = 0;
my $UI_RADIOBUTTON    = 1;
my $UI_CHECKBOX       = 2;
my $UI_DROPDOWNLIST   = 3;
my $UI_LIST           = 4;
#
# default search file number
#
my $nSearchNumber = '';
my $sSearchFile = $sPath . "customsearch";
#
# Check for direct link query
#
if (exists $::g_InputHash{PRODREF})					# jump to product requested
	{
	my $sProdRef = ACTINIC::DecodeText($::g_InputHash{PRODREF}, $ACTINIC::FORM_URL_ENCODED);
	my $sHTML = DirectLinkToProduct($sPath, $sProdRef);
	ACTINIC::SaveSessionAndPrintPage($sHTML, "");
	exit;
	}
elsif (exists $::g_InputHash{SECTIONID})			# jump to section (file) requested
	{
	my $sSection = ACTINIC::DecodeText($::g_InputHash{SECTIONID}, $ACTINIC::FORM_URL_ENCODED);
	my $sHTML = DisplayDirectLinkPage($sSection, $::TRUE );
	#
	# Make fool the XML parser here (see definition of UnregTagHandler)
	#
	$::g_bLoginPage = $::TRUE;
	ACTINIC::SaveSessionAndPrintPage($sHTML, "");
	exit;
	}
elsif ($::g_InputHash{ACTION} eq "LOGIN")   		# jump to last page (file) requested
	{
	my $sURL = $::Session->GetLastShopPage();
	my $sPage = $sURL;
 	$sPage =~ s!.*?/([^/]*)$!$1!img;
 	my $sStorePath = ACTINIC::GetStoreFolderName() . '/' .  $sPage;
 	if ($sURL !~ m!.*$sStorePath$!i)				# store path is not in the URL 
	 	{
 		$sPage = $$::g_pSetupBlob{BROCHURE_MAIN_PAGE};		# this must be the brochure main page
 		}
  	my $sSection = ACTINIC::DecodeText($sPage, $ACTINIC::FORM_URL_ENCODED);
	my $sHTML = DisplayDirectLinkPage($sSection, $::TRUE );
	#
	# Make fool the XML parser here (see definition of UnregTagHandler)
	#
	$::g_bLoginPage = $::TRUE;
	ACTINIC::SaveSessionAndPrintPage($sHTML, "");
	exit;
	}	
#
# compute search file name from SN parameter
#
if (exists $::g_InputHash{SN})
	{
	# $sSearchNnum is a string of digits used to build a filename.
	# It just looks like a number.
	#
	$nSearchNumber = $::g_InputHash{SN};
	unless ($nSearchNumber =~ /^\d*$/)
		{
		my $filelog = ACTINIC::GetPhrase(-1, 325, $nSearchNumber);
		SearchError($filelog);
		exit;
		}

	ACTINIC::LogData("Using custom search $nSearchNumber", $::DC_SEARCH);
	}

$sSearchFile .= "$nSearchNumber.fil";

unless (open SFILE, "<$sSearchFile")
	{
	my $filelog = ACTINIC::GetPhrase(-1, 21, $sSearchFile, $!);
	SearchError($filelog);
	exit;
	}
#
# read the entire file into an array
#
my @SearchCmd = <SFILE>;
close SFILE;
#
# Append extra commands to the read list of commands
# for accomplishing price schedule handling
#
push @SearchCmd, "PriceSchedule\n";
push @SearchCmd, "And\n";
#
# check for supported versions
#
my $nFileVersion = shift (@SearchCmd);
unless ($nFileVersion == $nFILEVERSION)
	{
	my $filelog = ACTINIC::GetPhrase(-1, 326, $nFILEVERSION, $nFileVersion);
	SearchError($filelog);
	exit;
	}

ACTINIC::LogData("Search command file version = $nFileVersion", $::DC_SEARCH);
#
# Check if this is a product group search only
#
if ($::g_InputHash{GROUPONLY})
	{
	@SearchCmd = ();										# override the commands then
	push @SearchCmd, "ProductGroup!PG\n";
	}
#
# A hash of array references for checkbox decoding.
# Only built when at least one Property Search is detected.
#
my %MatchWords;
my %UsedValues;
my @ResultsStack;
my $bValidSearch = 0;
my $bPriceSearch = $::FALSE;
SearchMain(\@SearchCmd, \$bValidSearch, \$bPriceSearch, \%MatchWords, \@ResultsStack);
#
# Convert @ResultsStack to single hash reference (%NullSet by default)
# Theoretically this code should be completely unnecessary. It takes the standard result set and combines any remaining sets into a single set.
# However, the design prohibits multiple results sets from being available at this point.  We could get here if a user defining a custom search
# has hosed the system.  I'm tempted to remove this bit of code, but I don't want to change breaking anything this close to the release just to
# clean up what I don't think is necessary - so it will stay.  George Menyhert (in one of my last modifications ever)
#
my %NullSet;
my $rhashResults = \%NullSet;
if ($#ResultsStack == -1)
	{
	#
	# This should never happen
	#
#? ACTINIC::ASSERT($::FALSE, "Null (not empty) results stack!", __LINE__, __FILE__);
	ACTINIC::LogData("Null (not empty) results stack!", $::DC_SEARCH);
	}
elsif ($#ResultsStack == 0)
	{
	my $rArray = pop @ResultsStack;
	if ($rArray->[0] == $TRUE_RESULT)
		{
		$rhashResults = $rArray->[1];
		ACTINIC::LogData("Search resulted in a single result list (everything worked as expected).", $::DC_SEARCH);
		}
	else
		{
		#
		# Treat both single SKIP or FALSE as FALSE.
		#
		ACTINIC::LogData("Search resulted in an empty result list (everything worked as expected).", $::DC_SEARCH);
		}
	}
else
	{
	ACTINIC::LogData("Search resulted in a set of result lists.  They should have been combined into a single list by now.  We will combine them at this point.", $::DC_SEARCH);
	my $pLine;
	my @ResultHashes;
	foreach $pLine (@ResultsStack)
		{
		my ($nStatus, $rhashtemp) = @{$pLine};
		ACTINIC::LogData("Result status was $nStatus", $::DC_SEARCH);

		if (($nStatus == $FALSE_RESULT) and
			 ($::g_InputHash{GB} eq 'A'))
			{
			#
			# any false will fail when AND is requested
			#
			@ResultHashes = ();
			ACTINIC::LogData("Exiting loop - one of the lists to be combined is empty and the join is an INTERSECTION.  Using an empty set.", $::DC_SEARCH);
			last;
			}
		elsif ($nStatus != $TRUE_RESULT)
			{
			#
			# treat FALSE with OR the same as a SKIP
			#
			ACTINIC::LogData("Skipping set of irrelevant results (SKIP set).", $::DC_SEARCH);
			next;
			}
		else
			{
			# only TRUE should get here
			push @ResultHashes, $rhashtemp;
			ACTINIC::LogData("Found a result set.", $::DC_SEARCH);
			}
		}
	#
	# now match up the result hashes
	#
	if ($#ResultHashes == -1)
		{
		$rhashResults = \%NullSet;
		ACTINIC::LogData("No populated results were found.  Using a null set.", $::DC_SEARCH);
		}
	else
		{
		ACTINIC::LogData("Found multiple results sets.  Combining results with global join operation ($::g_InputHash{GB}).", $::DC_SEARCH);
		$rhashResults = shift @ResultHashes;
		my $bJoin = ($::g_InputHash{GB} eq 'A') ? $::INTERSECT : $::UNION;
		while (@ResultHashes)
			{
			# while nothing should get here, be prepared
			#
			my $rPrevious = $rhashResults;
			my $rCurrent = shift @ResultHashes;
			JoinSearchResults($rPrevious, $rCurrent, $bJoin, $rhashResults);
			}
		}
	}

#
# We need  at least one search string, price band, section, or parameter
# to search.
#
if (!$bValidSearch)
	{
	my $sError;
	my $sStart = ACTINIC::EncodeText2(ACTINIC::GetPhrase(-1, 113), $::FALSE);
	if ($bPriceSearch &&									# check if the message should refer to price range
		 $::g_InputHash{ACTION})
		{
		$sError = ACTINIC::GetPhrase(-1, 245);
		}
	else
		{
		$sError = ACTINIC::GetPhrase(-1, 2085);
		}
	SearchError($sError, $::FALSE);
	exit;
	}
#
# retrieve the page number of the display
#
my $nPageNumber = $::g_InputHash{PN};
#
# words for highlighting found in Text searches
#
my @StringTemp = keys %MatchWords;
my $sWords = join (' ', @StringTemp);
#
# Display the results
#
($status, $sError) = DisplayResults($sPath, $rhashResults, $nPageNumber, $sWords);
if ($status != $::SUCCESS)
	{
	SearchError($sError, $status != $::NOTFOUND);
	exit;
	}

exit;

################################################################
#
# Init - Do the main script initialization.  This function
#   terminates on error.
#
# Returns:	0 - path
#
# Expects:  CGI environment
#
# Affects:  %::g_InputHash   - the CGI input hash
#           $::g_OriginalInputData - original CGI string
#           $::g_sWebSiteUrl - the URL of the catalog web site
#           $::g_sContentUrl - the URL of the image files
#
################################################################

sub Init
	{
	#
   # Read the input strings.  We expect the path, a text boolean flag and some text and/or a price band.
   # In the future, the path will come via a different (more secure) route, but let's leave it for now.
   #
	my ($status, $sError, $unused);
	($status, $sError, $::g_OriginalInputData, $unused, %::g_InputHash) = ACTINIC::ReadAndParseInput();
	if ($::SUCCESS != $status)
		{
		ACTINIC::TerminalError($sError);
		}
   #
   # Validate the input.
   #
	my $sPath = ACTINIC::GetPath();					# retrieve the path
	ACTINIC::SecurePath($sPath);						# make sure there is nothing funny going on
	if (!$sPath)											# if the path is empty or undefined
		{
		ACTINIC::TerminalError("Path not found.");
		}
	if (!-e $sPath ||										# the path does not exist or
		 !-d $sPath)										# the path is not a directory
		{
		ACTINIC::TerminalError("Invalid path.");
		}
   #
   # Read the prompt blob
   #
	($status, $sError) = ACTINIC::ReadPromptFile($sPath);
	if ($status != $::SUCCESS)
		{
		ACTINIC::ReportError($sError, $sPath);
		}
   #
   # Read the setup blob
   #
	($status, $sError) = ACTINIC::ReadSetupFile($sPath);	# read the setup
	if ($status != $::SUCCESS)
		{
		ACTINIC::ReportError($sError, $sPath);
		}
   #
   # Read the search setup blob
   #
	($status, $sError) = ACTINIC::ReadSearchSetupFile($sPath);	# read the search setup
	if ($status != $::SUCCESS)
		{
		ACTINIC::ReportError($sError, $sPath);
		}
   #
   # Read the catalog blob
   #
	($status, $sError) = ACTINIC::ReadCatalogFile($sPath);	# read the catalog blob
	if ($status != $::SUCCESS)
		{
		ACTINIC::ReportError($sError, $sPath);
		}

	#
	# Initialise session
	#
	my ($sCartID, $sContactDetails) = ACTINIC::GetCookies();
	$::Session = new Session($sCartID, $sContactDetails, ACTINIC::GetPath(), $::TRUE);

	#
	# Set the old global variables for compatibility
	#
	$::g_sWebSiteUrl = $::Session->GetBaseUrl();
	$::g_sContentUrl = $::g_sWebSiteUrl;

	#
	# Check the B2B mode
	#
	my ($sUserDigest, $sBaseFile);
	$sUserDigest = $ACTINIC::B2B->Get('UserDigest');
	if (!$sUserDigest)								# No user
		{
		($sUserDigest, $sBaseFile) = ACTINIC::CaccGetCookies(); # See if there is a user cookie after all
		$ACTINIC::B2B->Set('UserDigest',$sUserDigest);
		$ACTINIC::B2B->Set('BaseFile',  $sBaseFile);
		}
	#
	# If someone is logged in with B2B mode, then we need to use the B2B referrer
	#
	if ($sUserDigest)
		{
		$sBaseFile   = $ACTINIC::B2B->Get('BaseFile');
		($::g_sWebSiteUrl, $::g_sContentUrl) = ($sBaseFile, $sBaseFile);
		}
	elsif( $::g_InputHash{BASE} )			# Otherwise check if there isn't a BASE directory passed on
		{
		($::g_sWebSiteUrl, $::g_sContentUrl) = ($::g_InputHash{BASE}, $::g_InputHash{BASE});
		}
	return ($sPath);
	}

#######################################################
#
# ParseSearchInput - re-parse the original input into an hash of arrays that
#                    detects repeated CGI Parameters for MultiSelect
#
# Expects:	$::g_OriginalInputData from ACTINIC::ReadAndParseInput()
#         	Does not repeat all the error checking from that routine.
#
# Output:   0 - reference to a hash to fill
#
# Returns:	0 - status
#           1 - error message if any
#
#######################################################

sub ParseSearchInput
	{
	my ($rhashResults) = @_;
	#
	# parse and decode the input
	#
	my @EncodedInput = split (/[&=]/, $::g_OriginalInputData);		# check the input line
	if ($#EncodedInput % 2 != 1)
		{
		return ($::FAILURE, "Bad input string \"" . $::g_OriginalInputData . "\".  Argument count " . $#EncodedInput . ".\n", '', '', 0, 0);
		}
	my ($key, $value);
	while (@EncodedInput)
		{
		# decode the entry as an array to handle duplicates
		#
		$key = ACTINIC::DecodeText(shift @EncodedInput, $ACTINIC::FORM_URL_ENCODED);
		$value = ACTINIC::DecodeText(shift @EncodedInput, $ACTINIC::FORM_URL_ENCODED);
		#
		if (exists $$rhashResults{$key})
			{
			push @{$$rhashResults{$key}}, $value;
			}
			else
			{
			$$rhashResults{$key} = [$value];
			}
		}

	return ($::SUCCESS, '');
	}

#######################################################
#
# SearchMain - The main search algorithm.  This function
#   loops over the search command file processing the
#   search as specified by the file.
#
# Input:    0 - reference to the search command array
#
# Output:   1 - reference to the flag indicating if any search value was found
#           2 - reference to the flag indicating if any price search was done
#           3 - reference to the hash where the keys contain a list of matching keywords
#           4 - reference to the results stack
#
# Exits on error
#
#######################################################

sub SearchMain
	{
	my ($plistSearchCommands, $pbValidSearch, $pbPriceSearch, $pmapKeywordsFound, $pResultsStack) = @_;
	my $sPath = ACTINIC::GetPath();

	ACTINIC::LogData("Search command: \n" . join("", @$plistSearchCommands), $::DC_SEARCH);
	#
   # The following loop is the main search driving function. It loops over the search command file and processes each command.
	#
	my ($sLine, %mapInputKeyToValueArray);
	foreach $sLine (@$plistSearchCommands)			# examine every command in the list
		{
		chomp $sLine;
		ACTINIC::LogData("\n\nProcessing command: $sLine", $::DC_SEARCH);
		#
		# Parse the command line - format "<COMMAND>!<P1>!<P2>".  Note the existance and meaning of the parameters is specific to the command.
		# ·	Param1 is the name of the associated HTML control representing the search property.
		# ·	Param2 is the name of the second HTML control.  This value is only required for keyword searches where Param2 is the name of the
		#     HTML control that contains the keyword Boolean operation.  It should be set to TB.
		#
		my ($sCmd, $sSearchControlName, $sKeywordBooleanControlName) = split ('!', $sLine);
		ACTINIC::LogData("Command parsed: Command='$sCmd', Search Control Name='$sSearchControlName', Keyword Join Control Name='$sKeywordBooleanControlName'", $::DC_SEARCH);

		my $sSearchValue = '';
		if ($sSearchControlName)						# If the name of the HTML control is supplied
			{
			if (exists $::g_InputHash{$sSearchControlName})	# And the value is defined
				{
				$sSearchValue = $::g_InputHash{$sSearchControlName}; # record the value of the search parameter
				}
			ACTINIC::LogData("Search parameter value ='$sSearchValue'", $::DC_SEARCH);
			}
		#
		# trim excess leading and trailing white space
		#
		$sSearchValue =~ s/^\s*//o;
		$sSearchValue =~ s/\s*$//o;
		#
		my $sKeywordBooleanOperation = '';
		if ($sKeywordBooleanControlName)				# If Param2 is defined, it is the keyword join control name
			{
			if (exists $::g_InputHash{$sKeywordBooleanControlName}) # If the keyword join control has a value
				{
				$sKeywordBooleanOperation = $::g_InputHash{$sKeywordBooleanControlName}; # record it
				}
			ACTINIC::LogData("Keyword join value ='$sKeywordBooleanOperation'", $::DC_SEARCH);
			}
		#
		# Here we begin the command specific processing
		#
		# Handle a keyword search
		#
		if ($sCmd eq 'Text')								# Text means a keyword search
			{
			ACTINIC::LogData("Doing a keyword search.", $::DC_SEARCH);
			my $bText = $::UNION;						# Default to a UNION of the keyword results (e.g. products containing "orange" OR "balloon")
			ACTINIC::LogData("Defaulting to joining keywords with UNION.", $::DC_SEARCH);
			if ($sKeywordBooleanOperation eq 'A')	# if the operation control indicated a interersection, (e.g. products containing "orange" AND "red")
				{
				$bText = $::INTERSECT;					# use an INTERSECT
				ACTINIC::LogData("Overriding join method with INTERSECTION.", $::DC_SEARCH);
				}
			elsif ($sKeywordBooleanOperation ne 'O') # if the operation is not supported
				{
				my $sError = ACTINIC::GetPhrase(-1, 244);	# error out
				SearchError($sError);
				exit;
				}

			if ($sSearchValue eq '')					# No search value
				{
				#
				# Early detection of nothing to do
				#
				ACTINIC::LogData("Searcher doesn't care about keywords.", $::DC_SEARCH);
				next;											# just skip the command (we treat blank values as "not interested in this field")
				}

			$$pbValidSearch = 1;							# note that we found at least one command in the file that made sense
			my $pTextHits = {};
			#
			# Now do the text search.
			#
			($status, $sError) = Search::SearchText($sPath, \$sSearchValue, $bText, $pTextHits);
			if ($status != $::SUCCESS)
				{
				SearchError($sError);
				exit;
				}

			if (scalar (keys %$pTextHits))			# if some items were found
				{
				push @$pResultsStack, [$TRUE_RESULT, $pTextHits];	# record the results
				#
				# Save words that yielded successful search
				#
				my @matches = split (' ', $sSearchValue);
				my $word;
				foreach $word (@matches)
					{
					$$pmapKeywordsFound{$word} = 1;
					}
				#
				# Log the details of the search results
				# Since this could be computationally expensive, only do it if we are logging search information.
				#
				if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
					{
					my @Results = keys %$pTextHits;
					my $nResults = scalar (@Results);
					my $sResults = join (';', @Results);
					ACTINIC::LogData("The keyword search yielded $nResults hits\n    $sResults\n", $::DC_SEARCH);
					}
				}
			else												# no items found
				{
				push @$pResultsStack, [$FALSE_RESULT]; # record the empty set
				ACTINIC::LogData("The keyword search yielded no hits.", $::DC_SEARCH);
				}
			}
		#
		# Do a price based search
		#
		elsif ($sCmd eq 'Price')
			{
			ACTINIC::LogData("Doing a price range search.", $::DC_SEARCH);

			$$pbPriceSearch = $::TRUE;					# note that we had price search
			my $pPriceHits = {};
			#
			# Retrieve the price range and make numeric
			#
			my $nPriceBand = $sSearchValue;
			if (defined $nPriceBand &&					# a price band was selected
				 ($nPriceBand != $::ANY_PRICE_BAND))
				{
				ACTINIC::LogData("Searching price band $nPriceBand.", $::DC_SEARCH);

				$$pbValidSearch = 1;						# note that we found at least one command in the file that made sense
				#
				# Do the price band search
				#
				($status, $sError) = Search::SearchPrice($sPath, $nPriceBand, $pPriceHits);
				if ($status != $::SUCCESS)				# search error
					{
					SearchError($sError);
					exit;
					}

				if (scalar (keys %$pPriceHits))		# some items found
					{
					push @$pResultsStack, [$TRUE_RESULT, $pPriceHits]; # note the match
					#
					# Log the details of the search results
					# Since this could be computationally expensive, only do it if we are logging search information.
					#
					if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
						{
						my @Results = keys %$pPriceHits;
						my $nResults = scalar (@Results);
						my $sResults = join (';', @Results);
						ACTINIC::LogData("The price range search yielded $nResults hits\n    $sResults\n", $::DC_SEARCH);
						}
					}
				else											# no items found
					{
					ACTINIC::LogData("Price band search yielded no hits.", $::DC_SEARCH);
					push @$pResultsStack, [$FALSE_RESULT]; # note the empty set
					}
				}
			else												# no price band was selected (the customer doesn't care about price searching)
				{
				ACTINIC::LogData("Searcher doesn't care about price range.", $::DC_SEARCH);
				push @$pResultsStack, [$SKIP_RESULT];	# note that this search wasn't relevant
				}
			}
		#
		# Product property search
		#
      elsif (($sCmd eq 'Text Property') ||
				 ($sCmd eq 'Integer') ||
				 ($sCmd eq 'Date'))
	      {
			ACTINIC::LogData("Doing arbitrary property search.  Property type='$sCmd'.", $::DC_SEARCH);

			unless (exists $$::g_pSearchSetup{$sSearchControlName}) # the control that defines the search property value is missing from the configuration file
				{
				my $sError = ACTINIC::GetPhrase(-1, 327, $sSearchControlName);	# error out
				SearchError($sError);
				exit;
				}

			my $pBlobParam = $$::g_pSearchSetup{$sSearchControlName}; # retrieve the search property definition from the configuration file
			ACTINIC::LogData("Control UIType = $pBlobParam->{UIType}.", $::DC_SEARCH);
			ACTINIC::LogData("Control Optional = $pBlobParam->{Optional}.", $::DC_SEARCH);
			ACTINIC::LogData("Control MultiSelect = $pBlobParam->{MultiSelect}.", $::DC_SEARCH);
			ACTINIC::LogData("Control Label = $pBlobParam->{Label}.", $::DC_SEARCH);
			#
			# MultiSelect Properties (like lists or sets of check boxes) can repeat a CGI_Parameter
			# but $::g_InputHash can't detect that case, so we do a manual process check here and build the list of values.
			#
			unless (scalar (keys %mapInputKeyToValueArray))
				{
				($status, $sError) = ParseSearchInput(\%mapInputKeyToValueArray);
				if ($status != $::SUCCESS)
					{
					SearchError($sError);
					exit;
					}
				}
			#
			# Multiple hits from MultiSelect Properties will be combined with a UNION
			#
			my $pmapProductReferenceToMatchingProperties = {};
			my %mapFoundProductsToZero;
			#
			# Initialize for the nothing selected case
			#
			my $sCurrentValueOfMultiple = '';
			my @listAllValuesForControl = ();

			if ($mapInputKeyToValueArray{$sSearchControlName})	# if the input control has an entry
				{
				@listAllValuesForControl = @{$mapInputKeyToValueArray{$sSearchControlName}};	# grab the list of matching values
				}
			#
			# Loop over the matching values and build a complete list.  Note that multiple selections within a single control are joined as a UNION.
			#
			while (@listAllValuesForControl)								# while there are any entries in the list of values for this search parameter
				{
				$sCurrentValueOfMultiple = shift @listAllValuesForControl;	# grab the latest value

				ACTINIC::LogData("Searching for property value '$sCurrentValueOfMultiple'.", $::DC_SEARCH);
				#
				# Properties without Values must be Optional
				#
				if (($sCurrentValueOfMultiple eq '') && # if the value is missing and
					 (!$$pBlobParam{Optional}))		# it was not optional
					{
					my $sError = ACTINIC::GetPhrase(-1, 328, $$pBlobParam{Label});	# error out
					SearchError($sError);
					exit;
					}
				#
				# A checked checkbox without selection text generates default 'on' - convert that to "any"
				#
				if (($sCurrentValueOfMultiple eq 'on') &&
					 ($$pBlobParam{UIType} == $UI_CHECKBOX))
					{
					$sCurrentValueOfMultiple = '';
					ACTINIC::LogData("Checkbox converted on to 'any' (searcher doesn't care about value).", $::DC_SEARCH);
					}
				#
				# Properties must have single value unless Multiselect is on for the property
				#
				if (exists $UsedValues{$sSearchControlName})	# if we have already come across this control
					{
					#
					# A Property may be repeated if it specifies the same value
					# Needed for custom searches
					#
					if (($UsedValues{$sSearchControlName} != $sCurrentValueOfMultiple) && # if the property has already been used for a different value
						 (!$$pBlobParam{MultiSelect})) # and the control is not a multi-select
						{
						my $sError = ACTINIC::GetPhrase(-1, 329, $$pBlobParam{Label});	# error out
						SearchError($sError);
						exit;
						}
					}

				$UsedValues{$sSearchControlName} = $sCurrentValueOfMultiple; # note that we have searched this control for this value
				#
				# Now we branch on search type and validate the input
				#
				if (($sCmd eq 'Integer') &&			# data type is Integer
					 ($sCurrentValueOfMultiple ne '')) # and the value is not blank (i.e. not ignored)
					{
					#
					# Validate non-optional integers, treat "Any" as optional, zero is ok.
					#
					unless ($sCurrentValueOfMultiple =~ /^[-+]?\d+$/o)	# we can accept digits only (with optional possitive/negative sign indicators)
						{
						my $sError = ACTINIC::GetPhrase(-1, 330, $sCurrentValueOfMultiple, $$pBlobParam{Label}); # error out
						SearchError($sError);
						exit;
						}
					}
				#
				# Validate the dates - dates are stored as integers of the format YYYYMMDD so they are readily sortable chronologically as integers
				#
				elsif (($sCmd eq 'Date') &&			# data type is date
						 $sCurrentValueOfMultiple)		# and it is not blank (i.e. not ignored)
					{
					#
					# validate non-optional dates, treat "Any" as optional
					#
					unless ($sCurrentValueOfMultiple =~ /\d{8}/o) # must be of the format YYYYMMDD (i.e. 8 digits)
						{
						my $sError = ACTINIC::GetPhrase(-1, 331, $sCurrentValueOfMultiple, $$pBlobParam{Label}); # if not error out
						SearchError($sError);
						exit;
						}
					}
				else											# text properties currently have no validation
					{
					#
					# Text Property, reserve for future use
					#
					}

				if ($sCurrentValueOfMultiple ne '')	# if there is a meaningful value to search on
					{
					$$pbValidSearch = 1;					# note that we found at least one thing to search on
					#
					# Do the Property search
					#
					undef %mapFoundProductsToZero;
					($status, $sError) = Search::SearchProperty($sPath, $sSearchControlName, $sCurrentValueOfMultiple, \%mapFoundProductsToZero);
					if ($status != $::SUCCESS)
						{
						SearchError($sError);
						exit;
						}
					ACTINIC::LogData("Property search '$sSearchControlName' = '$sCurrentValueOfMultiple'.", $::DC_SEARCH);
					#
					# Add this property to the list of properties that match for this product
					#
					my $sProductReference;
					my $sLabel = ACTINIC::EncodeText2($pBlobParam->{Label}) . ": " . ACTINIC::EncodeText2($sCurrentValueOfMultiple) . "<BR>";	# build the formatted string for output
					foreach $sProductReference (keys %mapFoundProductsToZero)
						{
						unless (exists $pmapProductReferenceToMatchingProperties->{$sProductReference}) # if this is a new entry
							{
							$pmapProductReferenceToMatchingProperties->{$sProductReference} = []; # allocate a list for it
							}

						push @{$pmapProductReferenceToMatchingProperties->{$sProductReference}}, $sLabel; # copy the product property to the list
						}
					#
					# Log the details of the search results
					# Since this could be computationally expensive, only do it if we are logging search information.
					#
					if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
						{
						my @Results = keys %mapFoundProductsToZero;
						my $nResults = scalar (@Results);
						my $sResults = join (';', @Results);
						ACTINIC::LogData("The property search yielded $nResults hits for '$sSearchControlName' = '$sCurrentValueOfMultiple'\n    $sResults\n", $::DC_SEARCH);
						}
					}
				else											# ignore this value (i.e. the customer didn't request this as a search parameter)
					{
					#
					# "Any" exits "while" with $sCurrentValueOfMultiple eq ''
					#
					@listAllValuesForControl = ();
					ACTINIC::LogData("Property search for '$sSearchControlName' being ignored (searcher doesn't care about value).", $::DC_SEARCH);
					}
				}
			#
			# end of MultiSelect while loop
			#
			if ($sCurrentValueOfMultiple eq '')		# if no search value was found
				{
				ACTINIC::LogData("Property search for '$sSearchControlName' being ignored (searcher doesn't care about value).", $::DC_SEARCH);
				push @$pResultsStack, [$SKIP_RESULT];	# we have an empty result set that is to be ignored
				}
			elsif (scalar (keys %$pmapProductReferenceToMatchingProperties))	# if the result set contains values
				{
				#
				# Log the details of the search results
				# Since this could be computationally expensive, only do it if we are logging search information.
				#
				if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
					{
					my @Results = keys %$pmapProductReferenceToMatchingProperties;
					my $nResults = scalar (@Results);
					my $sResults = join (';', @Results);
					ACTINIC::LogData("The property search yielded $nResults total hits\n    $sResults\n", $::DC_SEARCH);
					}
				push @$pResultsStack, [$TRUE_RESULT, $pmapProductReferenceToMatchingProperties]; # add them to the result list
				}
			else												# the result set is empty
				{
				ACTINIC::LogData("Property search for '$sSearchControlName' resulted in no hits.", $::DC_SEARCH);
				push @$pResultsStack, [$FALSE_RESULT]; # add an empty set to the list
				}
			}
		#
		# Section based searches (i.e. products in a specific section)
		#
      elsif ($sCmd eq 'Section')
	      {
			ACTINIC::LogData("Doing section search.", $::DC_SEARCH);
			my $pSectionHits = {};
			#
			if ($sSearchValue)							# if any value was supplied, the customer was interested in this search
				{
				$$pbValidSearch = 1;						# note we found a valid command
				#
				# Do the section search
				#
				($status, $sError) = Search::SearchSection($sPath, $sSearchValue, $pSectionHits);
				if ($status != $::SUCCESS)
					{
					SearchError($sError);
					exit;
					}

				if (scalar (keys %$pSectionHits))	# if any results were found
					{
					#
					# Log the details of the search results
					# Since this could be computationally expensive, only do it if we are logging search information.
					#
					if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
						{
						my @Results = keys %$pSectionHits;
						my $nResults = scalar (@Results);
						my $sResults = join (';', @Results);
						ACTINIC::LogData("The section search for '$sSearchValue' yielded $nResults total hits\n    $sResults\n", $::DC_SEARCH);
						}
					push @$pResultsStack, [$TRUE_RESULT, $pSectionHits];	# add them to the results set list
					}
				else											# search returned no hits
					{
					ACTINIC::LogData("Section search for '$sSearchValue' resulted in no hits.", $::DC_SEARCH);
					push @$pResultsStack, [$FALSE_RESULT]; # add an empty list to the results set
					}
				}
			else												# no search value was supplied - the customer doesn't care about this search attribute
				{
				ACTINIC::LogData("Section search being ignored (searcher doesn't care about value).", $::DC_SEARCH);
				push @$pResultsStack, [$SKIP_RESULT];	# note that this result is irrelevant
				}
			}
		#
		# Check if product group search
		#
		elsif ($sCmd eq 'ProductGroup')
			{
			ACTINIC::LogData("Doing product group search.", $::DC_SEARCH);
			my $pGroupHits = {};
			#
			if ($sSearchValue)							# if any value was supplied, the customer was interested in this search
				{
				$$pbValidSearch = 1;						# note we found a valid command
				#
				# Do the section search
				#
				($status, $sError) = Search::SearchProductGroup($sPath, $sSearchValue, $pGroupHits);
				if ($status != $::SUCCESS)
					{
					SearchError($sError);
					exit;
					}

				if (scalar (keys %$pGroupHits))		# if any results were found
					{
					#
					# Log the details of the search results
					# Since this could be computationally expensive, only do it if we are logging search information.
					#
					if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
						{
						my @Results = keys %$pGroupHits;
						my $nResults = scalar (@Results);
						my $sResults = join (';', @Results);
						ACTINIC::LogData("The product group search for '$sSearchValue' yielded $nResults total hits\n    $sResults\n", $::DC_SEARCH);
						}
					push @$pResultsStack, [$TRUE_RESULT, $pGroupHits];	# add them to the results set list
					}
				else											# search returned no hits
					{
					ACTINIC::LogData("Product Group search for '$sSearchValue' resulted in no hits.", $::DC_SEARCH);
					push @$pResultsStack, [$FALSE_RESULT]; # add an empty list to the results set
					}
				}
			else												# no search value was supplied - the customer doesn't care about this search attribute
				{
				ACTINIC::LogData("Product group search being ignored (searcher doesn't care about value).", $::DC_SEARCH);
				push @$pResultsStack, [$SKIP_RESULT];	# note that this result is irrelevant
				}
			}
		#
		# See what products are in the current price schedule (so we don't list products not visible to the current customer)
		#
      elsif ($sCmd eq 'PriceSchedule')
	      {
			ACTINIC::LogData("Doing price schedule search.", $::DC_SEARCH);
			my $nScheduleID;
			($status, $sError, $nScheduleID) = ACTINIC::GetCurrentScheduleID(); # retrieve the active price schedule
			if ($status != $::SUCCESS)
				{
				SearchError($sError);			# error out
				exit;
				}
			ACTINIC::LogData("Searching for products hidden for price schedule $nScheduleID.", $::DC_SEARCH);
			#
			# It is worth to process the price schedules
			# only if there is any products hidden for this schedule
			#
			if (ACTINIC::IsPriceScheduleConstrained($nScheduleID)) # the schedule has some hidden products
				{
				#
				# Do the price schedule search
				#
				my $pPriceScheduleHits = {};
				($status, $sError) = Search::SearchPriceSchedule($sPath, $nScheduleID, $pPriceScheduleHits);
				if ($status != $::SUCCESS)
					{
					SearchError($sError);
					exit;
					}
				push @$pResultsStack, [$TRUE_RESULT, $pPriceScheduleHits]; # push the filtering list on the stack
				#
				# (Will be continued by an And filtering operation in the next loop)
				#
				#
				# Log the details of the search results
				# Since this could be computationally expensive, only do it if we are logging search information.
				#
				if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
					{
					my @Results = keys %$pPriceScheduleHits;
					my $nResults = scalar (@Results);
					my $sResults = join (';', @Results);
					ACTINIC::LogData("The price schedule search for '$nScheduleID' yielded $nResults hits\n    $sResults\n", $::DC_SEARCH);
					}
				}
			else												# there is no hidden items for this schedule, skip the constraint checking
				{
				ACTINIC::LogData("There are no price schedule based restraints on the product set.", $::DC_SEARCH);
				push @$pResultsStack, [$SKIP_RESULT];
				}
			}
		#
		# The command was a boolean operation (join the previous two search result sets)
		#
		elsif ($sCmd eq 'And')							# INTERSECT
			{
			ACTINIC::LogData("Doing an intersection combine of search results (and).", $::DC_SEARCH);
			if ($#$pResultsStack < 1)					# there are not two sets of results to combine
				{
				#
				# treat empty stack or single result as no operation
				#
				ACTINIC::LogData("There are no sets to combine.", $::DC_SEARCH);
				}
			else												# there are at least two sets of results to combine
				{
				#
				# Get the two list of found products to combine
				#
				my $pArray1 = pop @$pResultsStack;
				my $pArray2 = pop @$pResultsStack;

				if ($pArray1->[0] == $SKIP_RESULT)	# SKIP_RESULT means the search field was not considered important by the customer, so (e.g. no keyword was entered or no price band selected)
					{
					ACTINIC::LogData("List 1 contains the results of a search that was ignored by the searcher.  Using list 2.", $::DC_SEARCH);
					push @$pResultsStack, $pArray2;		# just take the second result as the entire combined result
					}
			   elsif ($pArray2->[0] == $SKIP_RESULT)	# the second array was unimportant
				   {
					ACTINIC::LogData("List 2 contains the results of a search that was ignored by the searcher.  Using list 1.", $::DC_SEARCH);
					push @$pResultsStack, $pArray1;		# just take the first result set
					}
		      elsif ( ( $pArray1->[0] == $FALSE_RESULT) || # both result sets are empty
				        ( $pArray2->[0] == $FALSE_RESULT))
			      {
					ACTINIC::LogData("Both lists are empty sets.  The combined list is an empty set", $::DC_SEARCH);
					push @$pResultsStack, [$FALSE_RESULT]; # the combined list is empty
					}
            else											# at least one of the result sets has something meaningful
	            {
					ACTINIC::LogData("Both lists are populated with results.  Combining the list.  Length of list 1 = "
										  . (scalar keys %{$pArray1->[1]}) . ".  Length of list 2 = " . (scalar keys %{$pArray2->[1]}) . ".", $::DC_SEARCH);

					my $pJoins = {};
					JoinSearchResults( $pArray1->[1], $pArray2->[1], $::INTERSECT, $pJoins); # join the lists
               if (scalar (keys %$pJoins))		# if the combined list contain results
	               {
						#
						# Log the details of the search results
						# Since this could be computationally expensive, only do it if we are logging search information.
						#
						if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
							{
							my @Results = keys %$pJoins;
							my $nResults = scalar (@Results);
							my $sResults = join (';', @Results);
							ACTINIC::LogData("The combined list yielded $nResults hits\n    $sResults\n", $::DC_SEARCH);
							}

	               push @$pResultsStack, [$TRUE_RESULT, $pJoins]; # record the combined results
                  }
               else                             # the combined list is empty
	               {
						ACTINIC::LogData("The combined list is empty.", $::DC_SEARCH);
 	               push @$pResultsStack, [$FALSE_RESULT]; # record the empty set
                  }
               }
            }
         }
      #
      # The command was a boolean UNION
      #
      elsif ($sCmd eq 'Or')
	      {
			ACTINIC::LogData("Doing a union combine of search results (or).", $::DC_SEARCH);
			if ($#$pResultsStack < 1)						# there are not two sets of results to join
				{
				#
				# treat empty stack or single result as no operation
				#
				ACTINIC::LogData("There are no sets to combine.", $::DC_SEARCH);
				}
			else												# there are two sets of results to join
				{
				#
				# Grab the results to do the join
				#
				my $pArray1 = pop @$pResultsStack;
				my $pArray2 = pop @$pResultsStack;

				if ($pArray1->[0] == $FALSE_RESULT) # the first result set is empty
					{
					ACTINIC::LogData("List 1 is empty.  Using list 2.", $::DC_SEARCH);
					push @$pResultsStack, $pArray2;		# use the second set ([] OR [a, b, c] = [a, b, c])
					}

				elsif ($pArray2->[0] == $FALSE_RESULT)	# the second set is empty
	            {
					ACTINIC::LogData("List 2 is empty.  Using list 1.", $::DC_SEARCH);
					push @$pResultsStack, $pArray1;		# use the first ([a, b, c] OR [] = [a, b, c])
	            }

            elsif ($pArray1->[0] == $SKIP_RESULT) # the first result set in ignored (no search criteria selected by the customer)
	            {
            	if ($pArray2->[0] == $SKIP_RESULT) # AND the second is ignored
	               {
						ACTINIC::LogData("Both list 1 and list 2 contain results of a search that is being ignored by the searcher.  The combined list is ignored as well.", $::DC_SEARCH);
						push @$pResultsStack, [$SKIP_RESULT];	# the result is a set that can be ignored
						}
               else										# BUT the second set is meaningful
	               {
						ACTINIC::LogData("List 1 contains results of a search that is being ignored by the searcher.  Using list 2.", $::DC_SEARCH);
						push @$pResultsStack, $pArray2;	# use the second set
	               }
               }

            elsif ($pArray2->[0] == $SKIP_RESULT) # the second set is ignored (but if we are here, the first set is meaningful)
	            {
					ACTINIC::LogData("List 2 contains results of a search that is being ignored by the searcher.  Using list 1.", $::DC_SEARCH);
					push @$pResultsStack, $pArray1;		# use the first set
	            }

            else											# both sets are meaningful
	            {
					ACTINIC::LogData("Both lists are populated with results.  Combining the list.  Length of list 1 = "
										  . (scalar keys %{$pArray1->[1]}) . ".  Length of list 2 = " . (scalar keys %{$pArray2->[1]}) . ".", $::DC_SEARCH);

					my $pJoins = {};
					JoinSearchResults($pArray1->[1], $pArray2->[1], $::UNION, $pJoins); # combine the sets
               if (scalar (keys %$pJoins))		# the resulting set contains items
	               {
						#
						# Log the details of the search results
						# Since this could be computationally expensive, only do it if we are logging search information.
						#
						if ($::DEBUG_CLASS_FILTER & $::DC_SEARCH)	# we are logging search information
							{
							my @Results = keys %$pJoins;
							my $nResults = scalar (@Results);
							my $sResults = join (';', @Results);
							ACTINIC::LogData("The combined list yielded $nResults hits\n    $sResults\n", $::DC_SEARCH);
							}

						push @$pResultsStack, [$TRUE_RESULT, $pJoins];	# add the combined list to the results
						}
               else										# the resulting set is empty (never here in reality)
	               {
						ACTINIC::LogData("The combined list is empty.", $::DC_SEARCH);
						push @$pResultsStack, [$FALSE_RESULT]; # empty results set to list
	               }
               }
            }
         }
		#
		# Unknown command
		#
      else													# unknown command
	      {
			ACTINIC::LogData("Unknown search command.", $::DC_SEARCH);
			my $sError = ACTINIC::GetPhrase(-1, 332, $sCmd, $sSearchFile);
			SearchError($sError);				# error out
			exit;
			}
      }
   }

###############################################################
#
# SearchError - Report an error doing the search operation
#
# Input:	   	0 - error message
#				1 - $::TRUE if the message should be logged into error.err (optional - default: $::TRUE)
#
###############################################################

sub SearchError
	{
#? ACTINIC::ASSERT($#_ == 0 || $#_ == 1, "Incorrect parameter count SearchError(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sMessage, $bWriteIntoLog) = @_;
   	#
   	# Adjust the default parameter alue if not defined
   	#
	if (!defined($bWriteIntoLog))
		{
		$bWriteIntoLog = $::TRUE;
		}

	my ($status, $sError, $sHTML) = ACTINIC::BounceToPageEnhanced(5, ACTINIC::GetPhrase(-1, 1962) . $sMessage . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2047),
																					  '',
																					  $::g_sWebSiteUrl,
																					  $::g_sContentUrl, $::g_pSetupBlob, $::Session->GetLastShopPage(), \%::g_InputHash,
																					  $::FALSE);
	if ($bWriteIntoLog)
		{
		ACTINIC::RecordErrors($sMessage, ACTINIC::GetPath());	# write into the log always
		}
	else
		{
		ACTINIC::LogData($sMessage, $::DC_SEARCH);				# write into log only if explicitly stated
		}

	ACTINIC::UpdateDisplay($sHTML, $::g_OriginalInputData);
	}

###############################################################
#
# DisplayResults - output the search results
#
# Input:	   0 - path
#           1 - reference to hash containing matching product
#               references
#           2 - the page number for the display
#           3 - search strings
#
# Returns:  0 - status
#           1 - error message if any
#
###############################################################

sub DisplayResults
	{
#? ACTINIC::ASSERT($#_ == 3, "Incorrect parameter count DisplayResults(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $rhashResults, $nPageNumber, $sSearchStrings) = @_;

   my @Results = sort keys %$rhashResults;		# get the product references in a fixed order
	#
	# Check for the "no matches" case
	#
	if ($#Results == -1)
		{
		return ($::NOTFOUND, ACTINIC::GetPhrase(-1, 267));
		}
	#
	# Now read the template
	#
	my $sFilename = $sPath . "results.html";
	unless (open (TFFILE, "<$sFilename"))
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sFilename, $!));
		}

	my ($sHTML);
	{
	local $/;
	$sHTML = <TFFILE>;									# read the entire file
	}
	close (TFFILE);

	#
	# Add location of catalog to checkout URL - this helps bounce pages to locate images
	#
	my $sUrl = $::Session->GetBaseUrl();						# Catalog directory
	if( $sUrl )
		{
		my $sReferer = $sUrl;
		$sUrl =~ s/\/[^\/]*$/\//;							# Keep only directory
		my $sStart = ACTINIC::EncodeText2(ACTINIC::GetPhrase(-1, 113), $::FALSE);		# Get encoded ACTION name for checkout
		$sHTML =~ s/\?ACTION\=$sStart/\?ACTION\=$sStart\&BASE\=$sUrl/g;					# Insert it into checkout link
		#######################################################
		#  eliminate PrepareRefPageData
		#######################################################
		my ($status, $sMessage, $sPageHistory);
		$sPageHistory =$::Session->GetLastPage();
		my $sReplace = "<INPUT TYPE=HIDDEN NAME=REFPAGE VALUE=\"$sPageHistory\">\n";
		$sHTML =~ s/(<FORM\s[^>]*>)/$1$sReplace/gi;
		}
	unless ($sHTML =~ /<Actinic:SEARCH_RESULTS>(.*?)<\/Actinic:SEARCH_RESULTS>/si) # extract the repeated section of markup
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 262));
		}
	my $sRepeatXML = $1;									# record the repeating portion
	#
	# Now flesh out the results sections
	#
	my ($nMin, $nMax);
	my $nResultsLimit = $$::g_pSearchSetup{SEARCH_RESULTS_PER_PAGE};
	my $bResultsLimited = (0 != $nResultsLimit);
	if (!$bResultsLimited)								# There is no limit on the number of items displayed on a page
		{
		$nMin = 0;											# display all of the results
		$nMax = $#Results + 1;
		}
	else
		{
		$nMin = $nPageNumber * $nResultsLimit;		# display all of the results
		$nMax = ($nPageNumber + 1) * $nResultsLimit;
		}
	if ($nMax > $#Results + 1)							# ensure that we don't overflow
		{
		$nMax = $#Results + 1;
		}
	my ($status, $sError, $sResults) = SearchResultsParser($sPath, $sRepeatXML, \@Results, $nMin, $nMax, $sSearchStrings, $rhashResults);
   if ($status != $::SUCCESS)
		{
		return ($status, $sError);
		}
   #
   # Now stick the results into the HTML
   #
   $sHTML =~ s/<Actinic:SEARCH_RESULTS>.*?<\/Actinic:SEARCH_RESULTS>/$sResults/si;
	#
	# Now handle the results summary
	#
	my $sSummary = ACTINIC::GetPhrase(-1, 264, $nMin + 1, $nMax, ($#Results + 1));
	#
	# Finally build the list of continuation links
	#
	my $sContinue;
	if ($bResultsLimited)								# if the results are limited
		{
		# Pass on customsearch file used
		#
		my $sCustomNumber = '';
		if (exists $::g_InputHash{SN})
			{
			$sCustomNumber = "&SN=$::g_InputHash{SN}";
			}
		#
		# Pass on section selected
		#
		my $sCustomSection = '';
		if (exists $::g_InputHash{SX})
			{
			$sCustomSection = "&SX=$::g_InputHash{SX}";
			}
		#
		# Build the basic search script URL
		#
		my $sScript = sprintf('%s?TB=%s&GB=%s&SS=%s%s%s&PR=%s&PG=%s',
									 $::g_sSearchScript,
									 $::g_InputHash{TB},
									 $::g_InputHash{GB},
									 ACTINIC::EncodeText2($::g_InputHash{SS}, $::FALSE),
									 $sCustomNumber,
									 $sCustomSection,
									 $::g_InputHash{PR},
									 $::g_InputHash{PG});
		#
		# Check if product group only search and add the appropriate tag
		#
		if (defined $::g_InputHash{GROUPONLY})
			{
			$sScript .= "&GROUPONLY=1";
			}
		#
		# Now add all of the search property parameters (if any) - note that rather than use InputHash, we reparse the input list because
		# InputHash does not properly handle multiple entries for a CGI parameter.
		#
		my %mapInputKeyToValueArray;
		($status, $sError) = ParseSearchInput(\%mapInputKeyToValueArray);
		if ($status != $::SUCCESS)
			{
			return ($status, $sError);
			}
		my ($sCgiParam, $plistValues);
		while (($sCgiParam, $plistValues) = each %mapInputKeyToValueArray) # examine every CGI parameter
			{
			if ($sCgiParam =~ /S_.+\d+_\d+/)			# if this is a search property form field (see SpecArbitrarySearching.doc for format details)
				{
				my $sValue;
				foreach $sValue (@$plistValues)		# take each value for the cgi parameter
					{
					$sScript .= "&" . ACTINIC::EncodeText2($sCgiParam, $::FALSE) . "=" . ACTINIC::EncodeText2($sValue, $::FALSE);	# add the value to the "next" link
					}
				}
			}
		#
		# Track the history and shop properly
		#
		my $sPathAndHistory = "&REFPAGE=" . ACTINIC::EncodeText2($::Session->GetLastShopPage(), $::FALSE) .
			($::g_InputHash{SHOP} ? "&SHOP=" . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : "");

		$sScript .= $sPathAndHistory;

		my $sLinkFormat = '<A HREF="%s">';
		my $sLink;

		if (0 != $nPageNumber)							# we are not on page 0
			{
			$sLink = $sScript . "&PN=" . ($nPageNumber - 1);
			$sLink = sprintf($sLinkFormat, $sLink);
			$sContinue .= $sLink . ACTINIC::GetPhrase(-1, 265, $nResultsLimit) . "</A>"; # add the "Last 20" link
			}

		my $nPage;
		my $nMaxPageCount = ActinicOrder::RoundTax(($#Results + 1) / $nResultsLimit, $ActinicOrder::CEILING);
		my $sPageLabel;

		for ($nPage = 0; $nPage < $nMaxPageCount; $nPage++) # enumerate the result pages
			{
			$sPageLabel = ($nPage * $nResultsLimit + 1) . '-' . ((($nPage + 1) * $nResultsLimit) > ($#Results + 1) ? $#Results + 1 : ($nPage + 1) * $nResultsLimit);
			$sLink = $sScript . "&PN=" . $nPage;
			$sLink = sprintf($sLinkFormat, $sLink);
			if ($nPage == $nPageNumber)				# the current page
				{
				$sContinue .= " " . $sPageLabel;		# add the page number (no link)
				}
			else												# anything other than the current page
				{
				$sContinue .= " " . $sLink . $sPageLabel . "</A>"; # add the page link
				}
			}

      if ($nMaxPageCount != $nPageNumber + 1)	# we are not on page MAX (the + 1 is because the page number index is from 0 -> max - 1)
			{
			$sLink = $sScript . "&PN=" . ($nPageNumber + 1);
			$sLink = sprintf($sLinkFormat, $sLink);
			$sContinue .= " " . $sLink . ACTINIC::GetPhrase(-1, 266, $nResultsLimit) . "</A>"; # add the "Next 20" link
			}

		if (1 == $nMaxPageCount)						# if there is only one page
			{
			undef $sContinue;								# don't post any message - it is just ugly
			}
		}
	#
	# Now stich it all together
	#
	$ACTINIC::B2B->ClearXML();									# clear the tag hash
	$ACTINIC::B2B->SetXML('S_SUMMARY',$sSummary);
	$ACTINIC::B2B->SetXML('S_CONTINUE',$sContinue);
	$sHTML = ACTINIC::ParseXML($sHTML);					# do the insert
	#######
	# make the file references point to the correct directory
	#######
	if( !$ACTINIC::B2B->Get('UserDigest') )
		{
		($status, $sError, $sHTML) = ACTINIC::MakeLinksAbsolute($sHTML, $::g_sWebSiteUrl, $::g_sContentUrl);
		}
	else
		{
		#
		# Build the correct referer link
		#
		my $sBaseFile = $ACTINIC::B2B->Get('BaseFile');
		my $smPath = ($sBaseFile) ? $sBaseFile : $::g_sContentUrl;
		my $sCgiUrl = $::g_sAccountScript;
		$sCgiUrl   .= ($::g_InputHash{SHOP} ? '?SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) . '&' : '?');
		$sCgiUrl   .= 'PRODUCTPAGE=';

		($status, $sError, $sHTML) = ACTINIC::MakeLinksAbsolute($sHTML, $sCgiUrl, $smPath);
		}

	if ($status != $::SUCCESS)
		{
		return ($status, $sError);
		}
	ACTINIC::SaveSessionAndPrintPage($sHTML, undef, $::FALSE);

	return ($::SUCCESS);
	}

###############################################################
#
# SearchResultsParser - function to handle the parsing of the
#   search results
#
# Input:	   0 - path
#           1 - results markup string
#           2 - results array (array of ordered prod refs)
#           3 - minimum count to display
#           4 - maximum count to display
#           5 - list of search words separated by spaces (used
#               for highlighting)
#           6 - pointer to results hash (keys are same as
#               results array, but hash values are 0 or list
#               of matching product properties)
#
# Returns:  0 - status
#           1 - error message
#           2 - markup for all results
#
###############################################################

sub SearchResultsParser
	{
#? ACTINIC::ASSERT($#_ == 6, "Incorrect parameter count SearchResultsParser(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $sResultMarkup, $rarrResults, $nMin, $nMax, $sSearchStrings, $pmapResultProdRefToMatchingProperties) = @_;
#? ACTINIC::ASSERT($#$rarrResults + 1 >= $nMax, "Max is greater than results size (" . ($#$rarrResults + 1) . " >= $nMax)", __LINE__, __FILE__);
#? ACTINIC::ASSERT(-1 < $nMin, "Min < 0.", __LINE__, __FILE__);
	#
	# Prepare the product index
	#
	my $rFile = \*PRODUCTINDEX;
	my $sFilename = $sPath . "oldprod.fil";
	my ($status, $sError) = ACTINIC::InitIndex($sFilename, $rFile, $::g_nSearchIndexVersion);
	if ($status != $::SUCCESS)
		{
		return($status, $sError);
		}
	#
	# Build the basic highlight script URL
	#
	my $sScript;
	if ($$::g_pSearchSetup{SEARCH_SHOW_HIGHLIGHT})
		{
		#
		#  Eliminate PrepareRefPageData
		#
		if ($ACTINIC::B2B->Get('UserDigest'))							# B2B mode
			{
			$sScript = sprintf('%s?REFPAGE=%s&WD=%s%s&PRODUCTPAGE=',
									 $::g_sAccountScript,
									 ACTINIC::EncodeText2($::Session->GetLastPage(), $::FALSE),
									 ACTINIC::EncodeText2($sSearchStrings, $::FALSE),
									 ($::g_InputHash{SHOP} ? "&SHOP=" . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : ""));
			}
		else													# standard mode (or B2B with no login)
			{
			$sScript = sprintf('%s?REFPAGE=%s&WD=%s%s&PN=',
									 $::g_sSearchHighLightScript,
									 ACTINIC::EncodeText2($::Session->GetLastPage(), $::FALSE),
									 ACTINIC::EncodeText2($sSearchStrings, $::FALSE),
									 ($::g_InputHash{SHOP} ? "&SHOP=" . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : ""));
			}
		}
	else														# no highlighting
		{
		if ($ACTINIC::B2B->Get('UserDigest'))							# B2B mode
			{
			$sScript = sprintf('%s?REFPAGE=%s&WD=%s%s&PRODUCTPAGE=',
									 $::g_sAccountScript,
									 ACTINIC::EncodeText2($::Session->GetLastPage(), $::FALSE),
									 ACTINIC::EncodeText2($sSearchStrings, $::FALSE),
									 ($::g_InputHash{SHOP} ? "&SHOP=" . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : ""));
			}
		}
	#
	# Load Image template
	#
	my ($sDummy, $pTree) = ACTINIC::PreProcessXMLTemplateString($sResultMarkup);
	my $pXML = new Element({"_CONTENT" => $pTree});	# bless the result to have Element structure
	my $sImageLineHTML 	= ACTINIC_PXML::GetTemplateFragment($pXML, "ImageLine");
	#
	# Now loop over the results and build an HTML fragment for each result
	#
	my $nCount;
	my $sHTML;
	my $sTemp;
	my %Product;
	for ($nCount = $nMin; $nCount < $nMax; $nCount++) # process the range of product references in the results set
		{
		#
		# Do the product lookup
		#
		($status, $sError) = ACTINIC::ProductSearch($$rarrResults[$nCount], $rFile, $sFilename, \%Product);
		if ($status == $::FAILURE)
			{
			ACTINIC::CleanupIndex($rFile);
			return($status, $sError);
			}
		if ($status == $::NOTFOUND)
			{
			ACTINIC::CleanupIndex($rFile);
			return($status, ACTINIC::GetPhrase(-1, 263));
			}
		#
		# Build the replacement tags
		#
		$ACTINIC::B2B->SetXML('S_ITEM', ($nCount + 1));

		my $sImage;
		if ($$::g_pSearchSetup{SEARCH_DISPLAYS_IMAGE} &&
			(length $Product{IMAGE} > 0))
			{
			my %hVarTable;
			$hVarTable{"NETQUOTEVAR:THUMBNAIL"} = $Product{IMAGE};
			if ($$::g_pSetupBlob{SEARCH_USE_THUMBNAIL})
				{
				my $sWidth  = $$::g_pSetupBlob{SEARCH_THUMBNAIL_WIDTH}  == 0 ? "" : sprintf("width=%d ",  $$::g_pSetupBlob{SEARCH_THUMBNAIL_WIDTH});
				my $sHeight = $$::g_pSetupBlob{SEARCH_THUMBNAIL_HEIGHT} == 0 ? "" : sprintf("height=%d ", $$::g_pSetupBlob{SEARCH_THUMBNAIL_HEIGHT});
				$hVarTable{"NETQUOTEVAR:THUMBNAILSIZE"} = $sWidth . $sHeight;
				}
			($status, $sError, $sImage) = ACTINIC::TemplateString($sImageLineHTML, \%hVarTable);
			if ($status != $::SUCCESS)
				{
				ACTINIC::CleanupIndex($rFile);
				return($status, $sTemp);
				}
			}
		$ACTINIC::B2B->SetXML('ImageLine', $sImage);

		if ($$::g_pSearchSetup{SEARCH_SHOW_HIGHLIGHT} &&	# the words are to be highlighted
			 $sSearchStrings)								# and there are some words
			{
			$Product{ANCHOR} =~ /([^\#]*)(.*)/;		# break the page into the file and anchor
			my $sAnchor = $2;
			$ACTINIC::B2B->SetXML('S_LINK', sprintf('<A HREF="%s">', $sScript . ACTINIC::EncodeText2($Product{ANCHOR}, $::FALSE) . $sAnchor));
			}
		else													# the links to the products are direct (no highlighting)
			{
			$ACTINIC::B2B->SetXML('S_LINK', sprintf('<A HREF="%s">', $Product{ANCHOR}));
			}
		$sTemp = "";
		if ($$::g_pSearchSetup{SEARCH_SHOW_NAME})	# only display the name if it is on
			{
			($status, $sTemp) = ACTINIC::ProcessEscapableText($Product{NAME}); # properly encode the text
			if ($status != $::SUCCESS)
				{
				ACTINIC::CleanupIndex($rFile);
				return($status, $sTemp);
				}
			}
		else													# otherwise, use the default text
			{
			$sTemp = ACTINIC::GetPhrase(-1, 278);
			}
		$ACTINIC::B2B->SetXML('S_PNAME', $sTemp);

		$sTemp = "";
		if ($$::g_pSearchSetup{SEARCH_SHOW_SECTION}) # only display the section name if it is on
			{
			($status, $sTemp) = ACTINIC::ProcessEscapableText($Product{SECTION}); # properly encode the text
			if ($status != $::SUCCESS)
				{
				ACTINIC::CleanupIndex($rFile);
				return($status, $sTemp);
				}
			$sTemp = "($sTemp)";
			}
		$ACTINIC::B2B->SetXML('S_SNAME', $sTemp);

		$sTemp = "";
		if ($$::g_pSearchSetup{SEARCH_SHOW_DESCRIPTION})	# only display the DESCRIPTION if it is on
			{
			($status, $sTemp) = ACTINIC::ProcessEscapableText($Product{DESCRIPTION}); # properly encode the text
			if ($status != $::SUCCESS)
				{
				ACTINIC::CleanupIndex($rFile);
				return($status, $sTemp);
				}
			}
		$ACTINIC::B2B->SetXML('S_DESCR', $sTemp);
		#
		# The price formatting is a little more complex
		#
		$sTemp = "";
		if ($$::g_pSearchSetup{SEARCH_SHOW_PRICE} &&	# only display the price if it is on and prices are displayed
			 $$::g_pSetupBlob{PRICES_DISPLAYED} &&
			 $Product{PRICE} != 0)
			{
			($status, $sError, $sTemp) = ActinicOrder::FormatPrice($Product{PRICE}, $::TRUE, $::g_pCatalogBlob);
			if ($status != $::SUCCESS)
				{
				ACTINIC::CleanupIndex($rFile);
				return($status, $sError);
				}
			}
		$ACTINIC::B2B->SetXML('S_PRICE', $sTemp);
		#
		# Display the searchable properties when requested.
		#
		$sTemp = "";
		if ($$::g_pSearchSetup{SEARCH_SHOW_PROPERTY} && # does the user want it? and
			 ref($pmapResultProdRefToMatchingProperties->{$rarrResults->[$nCount]}) eq "ARRAY")	# the properties exist
			{
			my $sLine;
			foreach $sLine (@{$pmapResultProdRefToMatchingProperties->{$rarrResults->[$nCount]}}) # get the list of matching properties for this product
				{
				$sTemp .= $sLine;							# add to display
				}
			}
		$ACTINIC::B2B->SetXML('S_PROP', $sTemp);	# make XML substitution

		$sHTML .= ACTINIC::ParseXML($sResultMarkup); # parse the XML
		}

	ACTINIC::CleanupIndex($rFile);

	return ($::SUCCESS, undef, $sHTML);
	}

###############################################################
#
# DirectLinkToProduct - look up the product for a given product
#   reference and display it directly
#
# Input:	   0 - path
#				1 - product reference to look for
#
# Returns:  0 - result HTML (the page or error message)
#
# Author: Zoltan Magyar
#
###############################################################

sub DirectLinkToProduct
	{
	my ($sPath, $sProdRef) = @_;
	my %Product;
	my $rFile = \*PRODUCTINDEX;
	my $sFilename = $sPath . "oldprod.fil";
	my ($status, $sError) = ACTINIC::InitIndex($sFilename, $rFile, $::g_nSearchIndexVersion);
	if ($status != $::SUCCESS)
		{
		ACTINIC::TerminalError($sError);
		}
	#
	# Do the product lookup
	#
	($status, $sError) = ACTINIC::ProductSearch($sProdRef, $rFile, $sFilename, \%Product);
	if ($status == $::FAILURE)							# search engine error
		{
		ACTINIC::CleanupIndex($rFile);
		SearchError($sError);							# report it
		}
	if ($status == $::NOTFOUND)						# there wasn't any match
		{
		ACTINIC::CleanupIndex($rFile);				# bounce back
		my ($status, $sError, $sHTML) = ACTINIC::BounceToPageEnhanced(5, ACTINIC::GetPhrase(-1, 1962) . ACTINIC::GetPhrase(-1, 1965, $sProdRef) . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2048),
											  '', $::g_sWebSiteUrl, $::g_sContentUrl,
											  $::g_pSetupBlob, ACTINIC::GetReferrer(), \%::g_InputHash, $::FALSE);
		return($sHTML);
		}
	#
	# Determine the product link to be used
	#
	my $sLink = $Product{ANCHOR};
	ACTINIC::CleanupIndex($rFile);
	return(DisplayDirectLinkPage($sLink, $::FALSE, $sProdRef));
	}

###############################################################
#
# DisplayDirectLinkPage - Display the direct link page
#
# Input:	   0 - URL to display
#				1 - Clear frames (Boolean)
#				2 - product reference (optional)
#
# Returns:  0 - result HTML (the page or error message)
#
# Author: Zoltan Magyar
#
###############################################################

sub DisplayDirectLinkPage
	{
	my $sLink		= shift;
	my $bClearFrames = shift;
	my $sProdRef	= shift;								# optional
	#
	# Build the correct referer link
	#
	my $sBaseFile = $ACTINIC::B2B->Get('BaseFile');
	my $sReferrer = ACTINIC::GetReferrer();
	my $sCgiUrl = $::g_sAccountScript;
	$sCgiUrl   .= ($::g_InputHash{SHOP} ? '?SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) . '&' : '?');
	#
	$sReferrer = $::Session->GetBaseUrl();
	#
	# See if there is a logged in customer
	#
	if ($ACTINIC::B2B->Get('UserDigest'))			# is there logged in business customer?
		{														# if so then make the link to point bb script
		$sLink =~ /([^\#]*)(.*)/;		# break the page into the file and anchor
		my $sAnchor = $2;
		$sLink = !$bClearFrames || $::g_InputHash{NOCLEARFRAMES} ||
					!$$::g_pSetupBlob{USE_FRAMES} ?
		$sCgiUrl . "PRODUCTPAGE=" . ACTINIC::EncodeText2($sLink, $::FALSE) :
		$sCgiUrl . "MAINFRAMEURL=" . ACTINIC::EncodeText2($sLink, $::FALSE);
		#
		# Add the product ref to the link
		# so that the warning bounce page
		# can be displayed by the AccountsScript
		# in case of unvisible product price schedule
		#
		if ($sProdRef)										# if product ref parameter is passed
			{
			$sLink .= "&PRODUCTREF=" . $sProdRef;
			}
		#
		# add the anchor if required
		#
		if ($sAnchor)
			{
			$sLink .= $sAnchor;
			}
		}
	else														# there isn't business customer logged in?
		{
		if ($$::g_pSetupBlob{B2B_MODE} &&			# but it is B2B version
			 !$::g_InputHash{NOLOGIN})					# and login is not disallowed
			{
			#
			# Then create a special login page which takes to the specified product taking into account the bounce to SSL
			#
			my @Response = ACTINIC::TemplateFile(ACTINIC::GetPath() . $$::g_pSetupBlob{B2B_LOGONPAGE});	# make the substitutions
			if ($Response[0] != $::SUCCESS)
				{
				ACTINIC::TerminalError($Response[1]);
				}
			$sLink =~ /([^\#]*)(.*)/;		# break the page into the file and anchor
			my $sAnchor = $2;
			#
			# Replace links to the specific product
			#
			my $sReplace = $$::g_pSetupBlob{USE_FRAMES} ? "<INPUT TYPE=HIDDEN NAME=MAINFRAMEURL VALUE=\"".  $sLink . "\">" :
																		 "<INPUT TYPE=HIDDEN NAME=PRODUCTPAGE VALUE=\"". $sLink . "\">";
			if ($::g_InputHash{TARGET} eq "BROCHURE")
				{
				$sReplace = "<INPUT TYPE=HIDDEN NAME=BROCHUREMAINFRAMEURL VALUE=\"".  $sLink . "\">";
				}
			#
			# Add the PRODUCTREF information to the form
			#
			if ($sProdRef)									# if product ref parameter is passed
				{
				$sReplace .= "<INPUT TYPE=HIDDEN NAME=PRODUCTREF VALUE=\"". $sProdRef . "\">"; # add the product ref as hidden parameter
				}
			#
			# Replace ACTINIC_REFERRER tag to point to the right URL
			#
			$sReplace .= "<INPUT TYPE=HIDDEN NAME=\"ACTINIC_REFERRER\" VALUE=\"$sReferrer\">";
			$Response[2] =~ s/<FORM([^>]+ACTION\s*?=\s*?["'])\s*?(.*?$::g_sAccountScriptName)\s*?(["'][^>]*?>)/<FORM$1$2$sAnchor$3$sReplace/gi; #'#
			#
			# Display warning message for retail,
			# if the product is not available for them
			#
			if ($sProdRef)									# if product ref parameter is passed
				{
					if (ACTINIC::IsPriceScheduleConstrained($ActinicOrder::RETAILID) &&			# there is any visibility constraint on retail
					!ACTINIC::IsProductVisible($sProdRef, $ActinicOrder::RETAILID))				# the product is not visible for retail
					{
					$ACTINIC::B2B->SetXML('PRODUCTNOTAVAILABLE', ACTINIC::GetPhrase(-1, 2176));# add the 'Product is not available for retail' warning to the page
					}
				}
			#
			# Replace static link for unregistered customers
			#
			my $sSearch = $$::g_pSetupBlob{USE_FRAMES} ? $$::g_pSetupBlob{FRAMESET_PAGE} : $$::g_pSetupBlob{CATALOG_PAGE};
			$sReplace = !$$::g_pSetupBlob{USE_FRAMES} || $::g_InputHash{TARGET} eq "BROCHURE" ? $sLink :
								$sCgiUrl . "ACTION=DIRECTLINK&MAINFRAMEURL=" . ACTINIC::EncodeText2($::g_sContentUrl . $sLink, $::FALSE) .
								"&ACTINIC_REFERRER=" . ACTINIC::EncodeText2($sReferrer , $::FALSE);
			$Response[2] =~ s/(<A[^>]*?HREF\s?=\s?["'][^"']*?SECTIONID=)$sSearch([^"']*?["']\s?>)/$1$sReplace$2/gi; #' #
			#
			# For mixed http and https we need to adjust the SSLREDIRECT javascript parameter
			#
			if ($$::g_pSetupBlob{USE_SSL} &&
				($$::g_pSetupBlob{SSL_USEAGE} == 1))
				{
				#
				# Build parameters for passing cookies from non-SSL to SSL
				#
				my $sParams = sprintf("&SESSIONID=%s&DIGEST=%s",
													ACTINIC::EncodeText2($::Session->GetSessionID(), $::FALSE),
													ACTINIC::CAccBusinessCookie());
				if ($sProdRef)
					{
					$sReplace = sprintf("%s?PRODREF=%s%s", $::g_sSSLSearchScript, $sProdRef, $sParams);
					}
				else
					{
					$sReplace = sprintf("%s?SECTIONID=%s%s", $::g_sSSLSearchScript, $sLink, $sParams);
					}
				$Response[2] =~ s/NETQUOTEVAR:SSLREDIRECT/$sReplace/;
				}
			return($Response[2]);						# return the login page (don't generate redirect page here)
			}
		else													# it is a plain catalog version
			{
			if (($sLink eq $$::g_pSetupBlob{CATALOG_PAGE}) &&
			($$::g_pSetupBlob{USE_FRAMES}))
				{
				$sLink = $$::g_pSetupBlob{FRAMESET_PAGE};
				}
			$sLink = $::g_sContentUrl . $sLink;		# then use the link what was determined before
			}
		}
	#
	# Generate the redirect page
	#
	my @Response = ACTINIC::BounceToPagePlain(0, undef, undef, $::g_sWebSiteUrl,
		$::g_sContentUrl, $::g_pSetupBlob, $sLink, \%::g_InputHash);
	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
		}
	return($Response[2]);
	}

###############################################################
#
# JoinSearchResults - This function is similar to
#   ACTINIC::JoinHashes but it preserves the values of the
#   hashes. The search script uses hashes for lists to
#   automatically eliminate duplicate entries.  The values are
#   set to "0" for most entries and an array of matching
#   properties for property searches.  This function combines
#   the lists as requested and maintains the list of matching
#   properties (if any) during the join.
#
# Input:	   0 - reference to hash1
#           1 - reference to hash2
#			   2 - join operation
# Output:   3 - reference to output hash
#
###############################################################

sub JoinSearchResults
	{
#? ACTINIC::ASSERT($#_ == 3, "Incorrect parameter count JoinSearchResults(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($phash1, $phash2, $bOperation, $phashOutput) = @_;

	undef %$phashOutput;									# clear the output list
	#
	# Now do the appropriate join operation on the hashes.  (See Perl Cookbook p 147 (first edition))
	#
	my $sProductReference;
	if ($bOperation == $::INTERSECT)					# AND join (INTERSECTION)
		{
		foreach $sProductReference (keys %$phash1)                                             # check each product in list 1
			{
			if (exists $phash2->{$sProductReference})					                              # the product exists in both lists
				{
				$phashOutput->{$sProductReference} = [];				                              # add this product to the output list

				if (ref($phash1->{$sProductReference}) eq "ARRAY")	                              # list one contains matching properties for this product
					{
					push @{$phashOutput->{$sProductReference}}, @{$phash1->{$sProductReference}}; # add the properties to the output list
					}

				if (ref($phash2->{$sProductReference}) eq "ARRAY")	                              # list two contains matching properties for this product
					{
					push @{$phashOutput->{$sProductReference}}, @{$phash2->{$sProductReference}}; # add the properties to the output list
					}
				}
			}
		}
	else														# OR join (UNION)
		{
		%$phashOutput = %$phash1;						# copy all of the products from list one to the output list
		foreach $sProductReference (keys %$phash2)                     # check each product in list two
			{
			unless (exists $phashOutput->{$sProductReference} &&	      # if this is a new entry
					  ref($phashOutput->{$sProductReference}) eq "ARRAY") # or it did not contain a list
				{
				$phashOutput->{$sProductReference} = [];				      # allocate a list for it
				}

			if (ref($phash2->{$sProductReference}) eq "ARRAY")		      # if list two contains a list of matching product properties,
				{
				push @{$phashOutput->{$sProductReference}}, @{$phash2->{$sProductReference}}; # copy the product properties
				}
			}
		}
	}
