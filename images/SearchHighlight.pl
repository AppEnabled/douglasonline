#!<Actinic:Variable Name="PerlPath"/>

################################################################
#
# SearchHighlight.pl - script to search to highlight strings
#  in an HTML form
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

require <Actinic:Variable Name="ActinicPackage"/>;
require <Actinic:Variable Name="ActinicOrder"/>;
require <Actinic:Variable Name="SessionPackage"/>;

use strict;

$::prog_name = "SearchHighligh";						# Program Name
$::prog_name = $::prog_name;
$::prog_ver = '$Revision: 18819 $ ';						# program version
$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
$::prog_ver =~ s/ \$//;									# and the trailers

#
# Do the main script initialization
#
my $sPath = Init();
#
# Validate the input
#
my $sPageName = $::g_InputHash{PN};
$sPageName =~ /([^\#]*)(.*)/;							# break the page into the file and anchor
my $sAnchor = $2;					                  # store the anchor
$sPageName = $1;											# store the page name
if (!$sPageName)											# the page to display
	{
	SearchError(ACTINIC::GetPhrase(-1, 268), $sPath);
	exit;
	}
#
# Do some sanity check on the file name to be sure our script can not be used
# to compromise the server
#
if ($sPageName =~ /\//i ||								# if the file name has slash
	 $sPageName =~ /\.\./)								# or double dots the do not allow lookup
	{
	SearchError(ACTINIC::GetPhrase(-1, 269), $sPath);
	exit;
	}
ACTINIC::SecurePath($sPageName);					   # make sure there are no hokey characters in the name

if ($sAnchor !~ /^\#[a-zA-Z0-9_]*$/)				# validate the anchor
	{
	SearchError(ACTINIC::GetPhrase(-1, 270), $sPath);
	exit;
	}
my $sWords = $::g_InputHash{WD};						# retrieve the words to highlight
#
# Now process the page
#
my ($status, $sError, $sHTML) = PreparePage($sPath, $sPageName, $sAnchor, $sWords, $::g_sWebSiteUrl, $::g_sContentUrl,
															  $$::g_pSearchSetup{SEARCH_HIGHLIGHT_START}, $$::g_pSearchSetup{SEARCH_HIGHLIGHT_END});
if ($status != $::SUCCESS)
	{
	SearchError($sError, $sPath);
	exit;
	}
ACTINIC::PrintPage($sHTML, undef, $::FALSE);

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
		ACTINIC::TerminalError($sError, $sPath);
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

	return ($sPath);
	}

###############################################################
#
# SearchError - Report an error doing the search operation
#
# Input:	   0 - error message
#           1 - path
#
###############################################################

sub SearchError
	{
#? ACTINIC::ASSERT($#_ == 1, "Incorrect parameter count SearchError(" . join(', ', @_) . ").", __LINE__, __FILE__);
   my ($sMessage, $sPath) = @_;
   #
   # Dup the last entry in the page list to help the bounce
   #
	my ($status, $sError, $sHTML) = ACTINIC::ReturnToLastPage(5, ACTINIC::GetPhrase(-1, 1962) . $sMessage . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2050), ACTINIC::GetPhrase(-1, 141),
																				 $::g_sWebSiteUrl,
																				 $::g_sContentUrl, $::g_pSetupBlob, %::g_InputHash);
	if ($status != $::SUCCESS)
		{
		ACTINIC::ReportError($sMessage, ACTINIC::GetPath());
		}

	ACTINIC::UpdateDisplay($sHTML, $::g_OriginalInputData);
	}

###############################################################
#
# PreparePage - highlight the specified words in the HTML
#   page using the supplied markup.
#
# Input:	   0 - path to directory (already externally verified
#               and made secure)
#           1 - page name
#           2 - anchor (if any)
#           3 - space separated list of words to highlight
#           4 - web site URL
#           5 - content URL
#           6 - highlight start markup
#           7 - highlight end markup
#
# Returns:  0 - status
#           1 - error message
#           2 - modified HTML
#
###############################################################

sub PreparePage
	{
#? ACTINIC::ASSERT($#_ == 7, "Incorrect parameter count PreparePage(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sPath, $sPageName, $sAnchor, $sWords, $sWebSiteUrl, $sContentUrl, $sStart, $sEnd) = @_;
	#
	# Read the file
	#
	unless (open (TFFILE, "<$sPath$sPageName"))
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sPath . $sPageName, $!));
		}

	my ($sHTML);
		{
		local $/;
		$sHTML = <TFFILE>;								# read the entire file
		}
	close (TFFILE);
	#
	# Now, Highlighing words...
	#
	ACTINIC::HighlightWords($sWords, $sStart, $sEnd, \$sHTML);
 	#
   # Now update the relative links
	#
	($status, $sError, $sHTML) = ACTINIC::MakeLinksAbsolute($sHTML, $sWebSiteUrl, $sContentUrl);
	if ($status != $::SUCCESS)
		{
		return ($status, $sError);
		}
	return ($::SUCCESS, undef, $sHTML);
	}
