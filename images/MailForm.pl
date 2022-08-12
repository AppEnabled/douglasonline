#!<Actinic:Variable Name="PerlPath"/>
#######################################################
#																		#
# MailForm.pl - provides mail support for Catalog	   #
#																		#
# Copyright (c) 2004 ACTINIC SOFTWARE Plc					#
#																		#
# Written by Zoltan Magyar 									#
# Wednesday, March 03, 2004									#
#																		#
#######################################################

#######################################################
#                                                     #
# The above is the Path to Perl on the ISP's server   #
#                                                     #
# Requires Perl version 5.004 or later               	#
#                                                     #
#######################################################


#?use CGI::Carp qw(fatalsToBrowser);
use strict;
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
#
# As the mail script is used only for bulk e-mail support
# so we can assume that the ACTINIC package is available
#
require <Actinic:Variable Name="ActinicPackage"/>;
require <Actinic:Variable Name="SessionPackage"/>;
require <Actinic:Variable Name="ActinicOrder"/>;

$::g_sSmtpServer = "<Actinic:Variable Name="SmtpServer"/>";

Init();
DispatchCommands();
exit;

#######################################################################################
######################### THIS IS THE END OF THE MAIN #################################
#######################################################################################

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
	my (@Response, $Status, $Message, $sHTML, $sAction, $pFailures, $sCartID);

	$sAction = $::g_InputHash{"ACTION"};			# check the page action
	#
	# Handle sending custom emails from the site
	#
	if ($sAction =~ m/$::g_sSendMailLabel/i )
		{
		@Response = SendMailToMerchant();
		}
	elsif ($sAction =~ m/SHOWFORM/i)
		{
		#
		# Note: this call will never return here
		#
		DisplayMailPage($::g_BillContact{'NAME'}, "", $::g_BillContact{'EMAIL'}, "");
		}
	#
	# Unsupported ACTION???
	# Bomb out with an error message
	#
	else														# there is no ACTION specified
		{
		ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 1284), ACTINIC::GetPath());
		exit;
		}
	#
	# Parse the response
	#
	($Status, $Message, $pFailures) = @Response; 	# parse the response
	if ($Status == $::FAILURE)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		}
	exit;
	}

#######################################################
#
# SendMailToMerchant - send a mail to the merchant's
#	email address with the details from input hash
#
# Returns:	0 - HTML of the page to be displayed
#
# Author: Zoltan Magyar - Wednesday, December 03, 2003
#
#######################################################

sub SendMailToMerchant
	{
	#
	# Receive parameters from input hash
	#
	my ($sEmailRecpt, $sSubject, $sTextMailBody, $sName, $sMessage, $sHTML);
	$sEmailRecpt 	= $::g_InputHash{'EmailAddress'};
	$sSubject 		= $::g_InputHash{'Subject'};
	$sName 			= $::g_InputHash{'Name'};
	$sMessage 		= $::g_InputHash{'Message'};
	#
	# Validate the content of the fields
	#
	my $sError;
	if ($sName eq "")
		{
		$sError .= ACTINIC::GetRequiredMessage(-1, 2370);
		}
	if ($sSubject eq "")
		{
		$sError .= ACTINIC::GetRequiredMessage(-1, 2372);
		}
	if ($sEmailRecpt eq "")
		{
		$sError .= ACTINIC::GetRequiredMessage(-1, 2371);
		}
	elsif ($sEmailRecpt !~ /.+\@.+\..+/)
		{
		$sError .= ACTINIC::GetPhrase(-1, 2378) . "\r\n";
		}
	if ($sMessage eq "")
		{
		$sError .= ACTINIC::GetRequiredMessage(-1, 2373);
		}

	if ($sError ne "")
		{
		$sError = ACTINIC::GroomError($sError);	# make the error look nice for the HTML
		$ACTINIC::B2B->SetXML('VALIDATIONERROR', $sError);
		#
		# Redisplay the mail page with error messages
		#
		DisplayMailPage($sName, $sSubject, $sEmailRecpt, $sMessage);
		#
		# Note: the above call will never return here
		#
		}
	else
		{
		#
		# Construct the mail text and send it to the merchant
		#
		$sError = ACTINIC::GetPhrase(-1, 2377);
		$sTextMailBody .= ACTINIC::GetPhrase(-1, 2370) . $sName . "\r\n";
		$sTextMailBody .= ACTINIC::GetPhrase(-1, 2371) . $sEmailRecpt . "\r\n";
		$sTextMailBody .= ACTINIC::GetPhrase(-1, 2373) . "\r\n" . $sMessage . "\r\n\r\n";
		my @Response = ACTINIC::SendMail($::g_sSmtpServer, $$::g_pSetupBlob{EMAIL}, $sSubject, $sTextMailBody, $sEmailRecpt);
		if ($Response[0] != $::SUCCESS)
			{
			ACTINIC::RecordErrors($Response[1], ACTINIC::GetPath());
			$sError = $Response[1];
			}
		#
		# Now bounce back to the mail page
		#
		@Response = ACTINIC::BounceToPageEnhanced(5, ACTINIC::GetPhrase(-1, 1962) . $sError . ACTINIC::GetPhrase(-1, 1970),
															$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
															$::g_sWebSiteUrl,
															$::g_sContentUrl, $::g_pSetupBlob, $::Session->GetLastShopPage(), \%::g_InputHash,
															$::FALSE);
		$sHTML = $Response[2];
		#
		# We need to manually remove the <Actinic:UNREG> tags from the bounce page
		#
		$sHTML =~ s/<Actinic:UNREG>.*?\/Actinic:UNREG>//isg;
		}
	ACTINIC::SaveSessionAndPrintPage($sHTML, undef);
	exit;
	}

#######################################################
#
# DisplayMailPage - load the mail form
#
# Input: $sName	- the name of the recepient
#			$sSubject- the subject of the mail
#			$sEmail	- email address of the sender
#			$sText	- the mail text
#
# Output:	Nothing. This function prints the page and
#	terminates. In case of error the error is reported
#	and the script is terminated.
#
#######################################################

sub DisplayMailPage
	{
	my ($sName, $sSubject, $sEmail, $sText) = @_;
	#
	# Display the mail page
	#
	my %VarTable;
	$VarTable{'NETQUOTEVAR:NAMEVALUE'} 		= $sName;
	$VarTable{'NETQUOTEVAR:EMAILVALUE'} 	= $sEmail;
	$VarTable{'NETQUOTEVAR:SUBJECTVALUE'} 	= $sSubject;
	$VarTable{'NETQUOTEVAR:MESSAGEVALUE'}	= $sText;
	my @Response = ACTINIC::TemplateFile(ACTINIC::GetPath() . "mail_form.html", \%VarTable); # make the substitutions
	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
		}
	#
	# clean up the links
	#
	my ($sDigest,$sBaseFile) = ACTINIC::CaccGetCookies();
	my $sPath = ($sBaseFile) ? $sBaseFile : $::g_sContentUrl;
	if( !$ACTINIC::B2B->Get('UserDigest') )
		{
		@Response = ACTINIC::MakeLinksAbsolute($Response[2], $::g_sWebSiteUrl, $::sPath);
		}
	else
		{		
		my $sCgiUrl = $::g_sAccountScript;
		$sCgiUrl   .= ($::g_InputHash{SHOP} ? '?SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) . '&': '?');
		$sCgiUrl   .= 'PRODUCTPAGE=';
		@Response = ACTINIC::MakeLinksAbsolute($Response[2], $sCgiUrl, $sPath);
		}
	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
		}
	my $sHTML = $Response[2];
	PrintPage($sHTML);
	exit;
	}

#######################################################
#
# Init - script initialisation
#
#######################################################

sub Init
	{
	$::prog_name = "MailForm";								# Program Name (8 characters)
	$::prog_ver = '$Revision: 22784 $';						# program version (6 characters)
	$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
	$::prog_ver =~ s/ \$//;									# and the trailers

	#
	# Set the calling context
	#
	$ActinicOrder::s_nContext = $ActinicOrder::FROM_CART;

	my (@Response, $Status, $Message);

	@Response = ReadAndParseInput();					# read the input from the CGI call
	($Status, $Message) = @Response;					# parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::TerminalError($Message);			# can't be report error because problem could be path error
		}

	@Response = ReadAndParseBlobs();					# read the catalog blobs
	($Status, $Message) = @Response;					# parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		}
	#
	# Set the old global variables for compatibility
	#
	$::g_sWebSiteUrl = $::Session->GetBaseUrl();
	$::g_sContentUrl = $::g_sWebSiteUrl;

	$ACTINIC::B2B->Set('UserDigest',ACTINIC::CAccFindUser());
	#
	# Initialize some global hashes (must come after prompt file)
	#
	ACTINIC::InitMonthMap();
	#
	# Graphical buttons
	#
	if(!defined $::g_InputHash{"ACTION"})
		{
		if(defined $::g_InputHash{"ACTION_SENDMAIL.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sSendMailLabel;
			}
		}
	}

#######################################################
#
# ReadAndParseInput - read the input and parse it
#
# Expects:	$ENV to be defined
#
#
# Output:	($ReturnCode, $Error)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#
#######################################################

sub ReadAndParseInput
	{
	my ($status, $message, $temp);
	($status, $message, $::g_OriginalInputData, $temp, %::g_InputHash) = ACTINIC::ReadAndParseInput();
	if ($status != $::SUCCESS)
		{
		return ($status, $message, 0, 0);
		}

	return ($::SUCCESS, "", 0, 0);
	}


#######################################################
#
# ReadAndParseBlobs - read the blobs and store them
#	in global data structures
#
# Expects:	%::g_InputHash - the input hash table should
#					be defined
#
# Affects:	%::g_BillContact - the invoice contact info
#				%::g_ShipContact - the delivery contact info
#				%::g_ShipInfo - the shipping info
#				%::g_TaxInfo - the tax exemption info
#				%::g_GeneralInfo - the general info page info
#				%g_PaymentInfo - the payment details
#
# Output:	($ReturnCode, $Error)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#
#######################################################

sub ReadAndParseBlobs
	{
	my ($Status, $Message, @Response, $sPath);

	$sPath = ACTINIC::GetPath();						# get the path to the web site

	@Response = ACTINIC::ReadPromptFile($sPath);	# read the prompt blob
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
		}

	@Response = ACTINIC::ReadCatalogFile($sPath); # read the catalog blob
	($Status, $Message) = @Response; 				# parse the response
	if ($Status != $::SUCCESS)							# on error, bail
		{
		return (@Response);
		}

	@Response = ACTINIC::ReadSetupFile($sPath);	# read the setup
	($Status, $Message) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}
	#
	# Initialise session
	#
	my ($sCartID, $sContactDetails) = ACTINIC::GetCookies();
	$::Session = new Session($sCartID, $sContactDetails, ACTINIC::GetPath(), $::TRUE);
	#
	# read the checkout status
	#
	my ($pBillContact, $pShipContact, $pShipInfo, $pTaxInfo, $pGeneralInfo, $pPaymentInfo, $pLocationInfo);
	@Response = $::Session->RestoreCheckoutInfo();
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	no strict 'refs';										# don't care empty string as hash
	($Status, $Message, $pBillContact, $pShipContact, $pShipInfo, $pTaxInfo, $pGeneralInfo, $pPaymentInfo, $pLocationInfo) = @Response;
	%::g_BillContact	= %$pBillContact;				# copy the hashes to global tables
	%::g_ShipContact 	= %$pShipContact;
	%::g_ShipInfo	 	= %$pShipInfo;
	%::g_TaxInfo		= %$pTaxInfo;
	%::g_GeneralInfo 	= %$pGeneralInfo;
	%::g_PaymentInfo  = %$pPaymentInfo;
	%::g_LocationInfo = %$pLocationInfo;

	return ($::SUCCESS, "");
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
	return (
			  ACTINIC::UpdateDisplay($_[0], $::g_OriginalInputData,
											$_[1], $_[2], '', '')
			 );
	}
