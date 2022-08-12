#!<Actinic:Variable Name="PerlPath"/>

require <Actinic:Variable Name="ActinicPackage"/>;
require <Actinic:Variable Name="ActinicOrder"/>;
require <Actinic:Variable Name="SessionPackage"/>;

push (@INC, "cgi-bin");

#?use CGI::Carp qw(fatalsToBrowser);

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

use strict;

$::prog_name = "REFERRER";							# Program Name
$::prog_ver = '$Revision: 20559 $ ';				# program version
$::prog_ver = substr($::prog_ver, 11);			# strip the revision information
$::prog_ver =~ s/ \$//;								# and the trailers


my $sPathToCatalog = '<Actinic:Variable Name="PathFromCGIToWeb"/>';

$sPathToCatalog =~ s/\/?$/\//;

my ($status, $sMessage, $temp);

($status, $sMessage, $::g_OriginalInputData, $temp, %::g_InputHash) = ACTINIC::ReadAndParseInput();
if ($status != $::SUCCESS)
	{
	ACTINIC::TerminalError($sMessage);
	}

my ($sSource, $sDestination, $sCatalogUrl, $sCoupon) = ($::g_InputHash{SOURCE}, $::g_InputHash{DESTINATION}, $::g_InputHash{BASEURL}, $::g_InputHash{COUPON});
$sCatalogUrl =~ s#/?$#/#;

if (!$sSource &&
	 !$sCoupon)
	{
	ACTINIC::TerminalError("The referring source is not defined.");
	}

if (!$sDestination)
	{
	ACTINIC::TerminalError("The destination page is not defined.");
	}

if (length $sCatalogUrl < 2)
	{
	ACTINIC::TerminalError("The BASEURL is not defined.");
	}
#
# We need some tricky way here to make fool the XML parser.
# The BASE HREF determination is based on the refpage which can be
# absolute different then the real catalog URL. So we need ACTINIC_REFERRER
# defined to have correct URLs.
#
$::g_InputHash{'ACTINIC_REFERRER'} = $sCatalogUrl;
#
# Initialize the script
#
Init();
#
# load the file.  Correct the links to refer to the static version of the page
#
my $sURL = $sCatalogUrl . $sDestination;
my @Response = ACTINIC::EncodeText($sURL);
$sURL = $Response[1];
my %vartable;
$vartable{'</FORM>'} = "<INPUT TYPE=HIDDEN NAME=ACTINIC_REFERRER VALUE=$sURL></FORM>";
@Response = ACTINIC::TemplateFile($sPathToCatalog . $sDestination, \%vartable);
if ($Response[0] != $::SUCCESS)
	{
	ACTINIC::TerminalError($Response[1]);
	}
#
# adjust the links
#
@Response = ACTINIC::MakeLinksAbsolute($Response[2], $sCatalogUrl, $sCatalogUrl);
if ($Response[0] != $::SUCCESS)
	{
	ACTINIC::TerminalError($Response[1]);
	}
my $sHTML = $Response[2];
$sHTML =~ s/(\<\s*A\s*HREF[^>?]+\?)/$1ACTINIC_REFERRER=$sURL&/gi;
#
# Save the coupon code if exists
#
if ($sCoupon)
	{
	$::Session->SetCoupon($sCoupon);
	}
#
# Save the referrer code if exists
#
if ($sSource &&
	 ACTINIC::IsPromptHidden(4, 2))					# the User Defined 3 prompt must be hidden
	{
	$::Session->SetReferrer($sSource);
	}

ACTINIC::SaveSessionAndPrintPage($sHTML, $::Session->GetSessionID());

exit;

#######################################################
#
# Init - initialize the script
#
#######################################################

sub Init
	{
	#
	# read the prompts
	#
	($status, $sMessage) = ACTINIC::ReadPromptFile($sPathToCatalog);
	if ($status != $::SUCCESS)
		{
		ACTINIC::TerminalError($sMessage);
		}
	#
	# The setup info is required by the session management
	#
	($status, $sMessage) = ACTINIC::ReadSetupFile($sPathToCatalog);	# read the setup
	if ($status != $::SUCCESS)
		{
		ACTINIC::TerminalError($sMessage);
		}
	#
	# Initialise session
	#
	my ($sCartID, $sContactDetails) = ACTINIC::GetCookies();
	$::Session = new Session($sCartID, $sContactDetails, ACTINIC::GetPath(), $::TRUE);
	}
