#!<Actinic:Variable Name="PerlPath"/> 
#&BEGIN
#&   {
#&   use ActinicProfiler;
#&   ActinicProfiler::Init("OrderScript");
#&   }
#&ActinicProfiler::EndInit();

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

#&ActinicProfiler::StartLoadRuntime('ACTINIC');
require <Actinic:Variable Name="ActinicPackage"/>;
#&ActinicProfiler::EndLoadRuntime('ACTINIC');
#&ActinicProfiler::StartLoadRuntime('ActinicSafer');
require <Actinic:Variable Name="ActinicSafer"/>;
#&ActinicProfiler::EndLoadRuntime('ActinicSafer');
#&ActinicProfiler::StartLoadRuntime('ActinicDiffie');
require <Actinic:Variable Name="ActinicDiffie"/>;
#&ActinicProfiler::EndLoadRuntime('ActinicDiffie');
#&ActinicProfiler::StartLoadRuntime('ActinicEncrypt');
require <Actinic:Variable Name="ActinicEncrypt"/>;
#&ActinicProfiler::EndLoadRuntime('ActinicEncrypt');
#&ActinicProfiler::StartLoadRuntime('ActinicOrder');
require <Actinic:Variable Name="ActinicOrder"/>;
#&ActinicProfiler::EndLoadRuntime('ActinicOrder');
#&ActinicProfiler::StartLoadRuntime('Session');
require <Actinic:Variable Name="SessionPackage"/>;
#&ActinicProfiler::EndLoadRuntime('Session');

#&BEGIN
#&   {
#&   ActinicProfiler::StartLoadStartup('Socket');
#&   }
use Socket;
#&BEGIN
#&   {
#&   ActinicProfiler::EndLoadStartup('Socket');
#&   }
#&BEGIN
#&   {
#&   ActinicProfiler::StartLoadStartup('strict');
#&   }
use strict;
#&BEGIN
#&   {
#&   ActinicProfiler::EndLoadStartup('strict');
#&   }


#######################################################
#                                                     #
# The above is the Path to Perl on the ISP's server   #
#                                                     #
# Requires Perl version 5.002 or later                #
#                                                     #
#######################################################

#######################################################
#                                                     #
# CATALOG SHOPPING CART CGI/PERL SCRIPT               #
#                                                     #
# Copyright (c) 1998 ACTINIC SOFTWARE LIMITED         #
#                                                     #
# written by George Menyhert                          #
#                                                     #
#######################################################

#
# Some global constants
#
$::prog_name = "ORDERSCR";								# Program Name
$::prog_name = $::prog_name;
$::prog_ver = '$Revision: 24119 $ ';					# program version
$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
$::prog_ver =~ s/ \$//;									# and the trailers

$::FORWARD	= 0;											# the direction of the order progress
$::BACKWARD	= 1;

$::eApplet 		= 0;										# display the applet page
$::eSharedSSL	= 1;										# display the shared SSL page

$::eDelivery	= 0;										# create combo for delivery address
$::eInvoice		= 1;										# create combo for invoice address

$::ORDER_BLOB_VERSION = 22;
$::ORDER_DETAIL_BLOB_VERSION = 13;

$::g_sSmtpServer = "<Actinic:Variable Name="SmtpServer"/>";
$::g_sUserKey = "<Actinic:Variable Name="PaypalProSaferKey"/>";
#
# Global variables
#
$::g_nCurrentSequenceNumber = -1;
$::g_nNextSequenceNumber = -1;

$::g_bSpitSSLChange = $::FALSE;

my $nDebugLogLevel = 0;									# Record process data
#
# Field sizes
#
$::g_pFieldSizes =
	{
	'NAME'			=> 40,
	'FIRSTNAME'		=> 40,
	'LASTNAME' 		=> 40,
	'SALUTATION'	=> 15,
	'JOBTITLE'		=> 50,
	'COMPANY'		=> 100,
	'PHONE'			=> 25,
	'MOBILE'		=> 25,
	'FAX'			=> 25,
	'EMAIL'			=> 255,
	'ADDRESS1'		=> 200,
	'ADDRESS2'		=> 200,
	'ADDRESS3'		=> 200,
	'ADDRESS4'		=> 200,
	'POSTALCODE'	=> 50,
	'COUNTRY'		=> 75,
	'USERDEFINED'	=> 255,
	'HOWFOUND'		=> 255,
	'WHYBUY'		=> 255,
	'PONO'			=> 50,
	};

Init();														# initialize the script

ProcessInput();											# execute the input commands

exit;

#&sub END
#&   {
#&   ActinicProfiler::WrapUp();
#&   }

#######################################################
#
# Init - initialize the script
#
#######################################################

sub Init
	{
	$::g_bFirstError = $::TRUE;						# this flag indicates that the display page method has entered recursion
																# due to errors - it prevents infinite recursion
	my (@Response, $Status, $Message, $sAction, $sSendMailButton);

	@Response = ReadAndParseInput();					# read the input from the CGI call
	($Status, $Message) = @Response;	# parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::TerminalError($Message);			# can't be report error because problem could be path error
		}
	#
	# Handle VCS PSP Callbacks as in this case there is no ACTION parameter
	#
	if ((not defined $::g_InputHash{'ACTION'}) &&
		($::g_InputHash{'m_6'} eq 'VCSCALL'))
		{
		#
		# put proper parameters into the InputHash, so OrderScript will call VCS PostProcess Script
		#
		my $sAuthCallURL = ACTINIC::DecodeText($::g_InputHash{'m_3'}, $ACTINIC::FORM_URL_ENCODED);
		$sAuthCallURL =~ /.*?PATH=(.*?)\&/;
		$::g_InputHash{'PATH'} = $1;
		$sAuthCallURL =~ /.*?SEQUENCE=(.*?)\&/;
		$::g_InputHash{'SEQUENCE'} = $1;
		$sAuthCallURL =~ /.*?ACTION=(.*?)\&/;
		$::g_InputHash{'ACTION'} = $1;
		$sAuthCallURL =~ /.*?CARTID=(.*?)\&/;
		$::g_InputHash{'CARTID'} = $1;
		$::g_InputHash{'ACT_POSTPROCESS'} = 1;
		$::g_InputHash{ON} = $::g_InputHash{m_1};
		$::g_InputHash{AM} = $::g_InputHash{p6} * $::g_InputHash{m_8};
		}
	#
	#
	# Handle ssp tracking calls separately
	#
	if ($::g_InputHash{'ACTION'} =~ m/SSP_TRACK/i)					# this is not a tracking request
		{
		my $sPath = ACTINIC::GetPath();				# get the path to the web site
		#
		# read the prompt blob
		#
		@Response = ACTINIC::ReadPromptFile($sPath);
		($Status, $Message) = @Response;				# parse the response
		if ($Status != $::SUCCESS)
			{
			ACTINIC::ReportError($Message, ACTINIC::GetPath());
			}
		#
		# read the SSP setup blob
		#
		@Response = ACTINIC::ReadSSPSetupFile($sPath);
		($Status, $Message) = @Response;				# parse the response
		if ($Status != $::SUCCESS)
			{
			ACTINIC::ReportError($Message, ACTINIC::GetPath());
			}
		@Response = FormatTrackingPage();
		($Status, $Message) = @Response;				# parse the response
		if ($Status != $::SUCCESS)
			{
			ACTINIC::ReportError($Message, ACTINIC::GetPath());
			}
		my $sHTML = $Response[2];
		ACTINIC::PrintPage($sHTML, undef);
		exit;
		}
	#
	# As the header comment says for address book:
	#
	# CreateAddressBook must be called after reading and parsing input and before
	# reading blobs.
	#
	if ($::g_InputHash{'SEQUENCE'} <= 3)
		{
		CreateAddressBook();		# Create Address Book
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
	#
	# Check offline authorization
	#
	if ($::g_InputHash{"ACTION"} =~ /^OFFLINE_AUTHORIZE/i)
		{
		DoOfflineAuthorization();
		exit;
		}
	#
	# Don't try get a buyer from the cookie for the OCC validation
	# callback but check if payment info contains a hash
	#
	if($::g_InputHash{"ACTION"} eq "OCC_VALIDATE" ||
		($::g_InputHash{ACTION} =~ /^AUTHORIZE/i) ||
		($::g_InputHash{"ACTION"} eq "RECORDORDER" && $$::g_pSetupBlob{USE_SHARED_SSL}))
		{
		$::Session->SetCallBack($::TRUE);

		if(defined $::g_PaymentInfo{BUYERHASH})
			{
			$ACTINIC::B2B->Set('UserDigest', $::g_PaymentInfo{BUYERHASH});
			$ACTINIC::B2B->Set('UserName', $::g_PaymentInfo{BUYERNAME});
			$ACTINIC::B2B->Set('BaseFile', $::g_PaymentInfo{BASEFILE});
			}
		}
	else
		{
		$ACTINIC::B2B->Set('UserDigest',ACTINIC::CAccFindUser());
		}
	#
	# initialize some global hashes (must come after prompt file)
	#
	ACTINIC::InitMonthMap();

	if( $::g_InputHash{'BASE'} )
		{
		$::g_sContentUrl = $::g_InputHash{'BASE'};
		}
	}

#######################################################
#
# ReadAndParseInput - read the input and parse it
#
# Expects:	$ENV to be defined
#
#
# Returns:	($ReturnCode, $Error)
#				if $ReturnCode = $FAILURE, the operation failed
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
	#
	# Check if COOKIE parameter defined is now done in ACTINIC::ReadAndParseInput()
	#
	# If "Select This Address' is choosen, empty fileds of "New delivery Address' form,
	# as dummy values that may be there by mistake cause problems.
	# For example, if user fills in delivery postal code of new address but chooses existing address,
	# shipping script thinks that new delivery postal code is valid and uses that
	#
	if( $::g_InputHash{INVOICEADDRESSSELECT} )				# B2B - address selected from address list, so empty dummy fields
		{
		undef $::g_InputHash{'INVOICESALUTATION'};
		undef $::g_InputHash{'INVOICENAME'};
		undef $::g_InputHash{'INVOICEFIRSTNAME'};
		undef $::g_InputHash{'INVOICELASTNAME'};
		undef $::g_InputHash{'INVOICEJOBTITLE'};
		undef $::g_InputHash{'INVOICECOMPANY'};
		undef $::g_InputHash{'INVOICEADDRESS1'};
		undef $::g_InputHash{'INVOICEADDRESS2'};
		undef $::g_InputHash{'INVOICEADDRESS3'};
		undef $::g_InputHash{'INVOICEADDRESS4'};
		undef $::g_InputHash{'INVOICEPOSTALCODE'};
		undef $::g_InputHash{'INVOICECOUNTRY'};
		undef $::g_InputHash{'INVOICEPHONE'};
		undef $::g_InputHash{'INVOICEMOBILE'};
		undef $::g_InputHash{'INVOICEFAX'};
		undef $::g_InputHash{'INVOICEEMAIL'};
		};
	if( $::g_InputHash{DELIVERADDRESSSELECT} )				# B2B - address selected from address list, so empty dummy fields
		{
		undef $::g_InputHash{'DELIVERSALUTATION'};
		undef $::g_InputHash{'DELIVERNAME'};
		undef $::g_InputHash{'DELIVERFIRSTNAME'};
		undef $::g_InputHash{'DELIVERLASTNAME'};
		undef $::g_InputHash{'DELIVERJOBTITLE'};
		undef $::g_InputHash{'DELIVERCOMPANY'};
		undef $::g_InputHash{'DELIVERADDRESS1'};
		undef $::g_InputHash{'DELIVERADDRESS2'};
		undef $::g_InputHash{'DELIVERADDRESS3'};
		undef $::g_InputHash{'DELIVERADDRESS4'};
		undef $::g_InputHash{'DELIVERPOSTALCODE'};
		undef $::g_InputHash{'DELIVERCOUNTRY'};
		undef $::g_InputHash{'DELIVERPHONE'};
		undef $::g_InputHash{'DELIVERMOBILE'};
		undef $::g_InputHash{'DELIVERFAX'};
		undef $::g_InputHash{'DELIVEREMAIL'};
		undef $::g_InputHash{'DELIVERUSERDEFINED'};
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
# Affects:	$g_sCartId - the cart ID for this customer
#				%g_BillContact - the invoice contact information
#				%g_ShipContact - the delivery contact information
#				%g_ShipInfo - the shipping information
#				%g_TaxInfo - the tax information
#				%g_GeneralInfo - general information
#				%g_PaymentInfo - payment information
#
# Returns:	($ReturnCode, $Error)
#				if $ReturnCode = $FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#
#######################################################

sub ReadAndParseBlobs
	{
	my ($Status, $Message, @Response, $sPath);

	$sPath = ACTINIC::GetPath();						# get the path to the web site
	#
	# Set up array of functions to read blobs
	#
	my @arrFuncns =
		(
		\&ACTINIC::ReadCatalogFile,					# A000.cat
		\&ACTINIC::ReadSetupFile,						# nqset00.fil
		\&ACTINIC::ReadLocationsFile,					# locations.fil
		\&ACTINIC::ReadPaymentFile,					# payment.fil
		\&ACTINIC::ReadPhaseFile,						# phase.fil
		\&ACTINIC::ReadPromptFile,						# prompt.fil
		\&ACTINIC::ReadTaxSetupFile,					# taxsetup.fil
		\&ACTINIC::ReadSSPSetupFile,					# sspsetup.fil
		\&ACTINIC::ReadDiscountBlob,					# discounts.fil
		);
		
	my $pfunRead;
	foreach $pfunRead (@arrFuncns)					# for each function in the array
		{
		@Response = &$pfunRead($sPath);				# call this function
		if ($Response[0] != $::SUCCESS)				# on error, bail
			{
			return (@Response);
			}
		}

	#
	# read the cart ID from the cookie or the input hash
	#
	my ($sContactDetails);
	($::g_sCartId, $sContactDetails) = ACTINIC::GetCookies();;
	#
	# Some of the PSP installations uses CARTID for this parameter some of
	# them uses CART. To be sure that the cart ID is received correctly
	# on callbacks we try to restore both formats.
	#
	if ($::g_InputHash{CARTID} &&						# if the cart ID is being handed in and
		 $::g_InputHash{CARTID} =~ /^[a-zA-Z0-9]+$/) # the cart id appears to be valid
		{
		$::g_sCartId = $::g_InputHash{CARTID};		# use the cart Id passed in
		}

	#
	# If the cart ID is not defined at this point, use the one passed in.  This helps us hack around an Internet Explorer bug on the Mac
	#
	if ($::g_InputHash{CART} &&						# if the cart ID is being handed in and
		 $::g_InputHash{CART} =~ /^[a-zA-Z0-9]+$/) # the cart id appears to be valid
		{
		$::g_sCartId = $::g_InputHash{CART};		# use the cart Id passed in
		}
	#
	# detect if it is a callback, because in this case there will be no cookies, so we have to
	# inform the Session object, don't crear itself in the new fuction by absence of the cookie
	#
	my $sCallbackFlag;
	if(($::g_InputHash{"ACTION"} eq "OCC_VALIDATE") ||
		($::g_InputHash{"ACTION"} eq "GCCB") ||
		($::g_InputHash{"ACTION"} eq "GCRECALC") ||
		($::g_InputHash{"ACTION"} =~ /^AUTHORIZE/i) ||
		($::g_InputHash{"ACTION"} =~ /^OFFLINE_AUTHORIZE/i) ||
		($::g_InputHash{"ACTION"} eq "RECORDORDER" && $$::g_pSetupBlob{USE_SHARED_SSL}))
		{
		$sCallbackFlag = $::TRUE;
		}
	else
		{
		$sCallbackFlag = $::FALSE;
		}
	#
	# We need the session ID from the callback XML
	#
	if ($::g_InputHash{"ACTION"} eq "GCCB")
		{
		IncludeGoogleScript();
		$::g_sCartId = GetSessionFromGoogle();
		}
	#
	# Initialise session
	#
	$::Session = new Session($::g_sCartId, $sContactDetails, ACTINIC::GetPath(), $::FALSE, $sCallbackFlag);
	#
	# The session file checkout info part is read on the first script call. If this is a split SSL
	# configuration then the first script call is most likely uses the non secure server where the
	# remember me cookie is not set correctly. Therefore if this os call is the first one after the
	# http->https transition then the remember me cookies should be updated.
	#
	if ($::g_bSpitSSLChange &&      					# http->https transition
	    $sContactDetails ne "")     					# we have contact details cookie
		{                       						# update remember me
		$::Session->CookieStringToContactDetails();
		}
	#
	# Read the checkout status now
	#
	my ($pBillContact, $pShipContact, $pShipInfo, $pTaxInfo, $pGeneralInfo, $pPaymentInfo, $pLocationInfo);
	@Response = $::Session->RestoreCheckoutInfo();
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	no strict 'refs';
	($Status, $Message, $pBillContact, $pShipContact, $pShipInfo, $pTaxInfo, $pGeneralInfo, $pPaymentInfo, $pLocationInfo) = @Response;
	%::g_BillContact = %$pBillContact;					# copy the hashes to global tables
	%::g_ShipContact = %$pShipContact;
	%::g_ShipInfo		= %$pShipInfo;
	%::g_TaxInfo		= %$pTaxInfo;
	%::g_GeneralInfo = %$pGeneralInfo;
	%::g_PaymentInfo = %$pPaymentInfo;
	%::g_LocationInfo = %$pLocationInfo;
	#
	# Dump the original tax info to allow easy detection of changes
	#
	$::g_sTaxDump = (join "|", keys %::g_TaxInfo) . (join "|", values %::g_TaxInfo);
	$::g_sShippingDump = (join "|", keys %::g_ShipInfo) . (join "|", values %::g_ShipInfo);

	return ($::SUCCESS, "", 0, 0);
	}

#######################################################
#
# ProcessInput - read the input parameters and
#	call the appropriate function in response
#
#######################################################

sub ProcessInput
	{
	my (@Response, $sDetailCookie);
	#
	# Find out where we are
	#
	$::g_nCurrentSequenceNumber = $::g_InputHash{'SEQUENCE'}; # determine the sequence number of the calling page
	if (!defined $::g_nCurrentSequenceNumber) 		# if we are at the beginning
		{
		$::g_nCurrentSequenceNumber = $::STARTSEQUENCE;
		}
	#
	# Get the button names
	#
	my ($sConfirmButton, $sStartButton, $sDoneButton, $sNextButton, $sFinishButton, $sBackButton, $sCancelButton, $sChangeLocationButton);
	$sConfirmButton = ACTINIC::GetPhrase(-1, 153);
	$sStartButton = ACTINIC::GetPhrase(-1, 113);
	$sDoneButton = ACTINIC::GetPhrase(-1, 114);
	$sNextButton = ACTINIC::GetPhrase(-1, 502);
	$sBackButton = ACTINIC::GetPhrase(-1, 503);
	$sFinishButton = ACTINIC::GetPhrase(-1, 504);
	$sCancelButton = ACTINIC::GetPhrase(-1, 505);
	$sChangeLocationButton = ACTINIC::GetPhrase(0, 18);
	my $sConfirmOrderButton = ACTINIC::GetPhrase(-1, 2602);
	#
	# If the progress is forward
	#
	my ($sHTML, $sAction, $eDirection);
	if (defined $::g_InputHash{'ACTION_CONFIRM'})
		{
		$::g_InputHash{'ACTION'} = $sConfirmOrderButton;
		undef $::g_InputHash{'ACTION_CONFIRM'};
		}
	$sAction = $::g_InputHash{'ACTION'};
	#
	# Check the checkout started flag
	#
	if ($sAction =~ m/$sStartButton/i)
		{
		$::Session->SetCheckoutStarted();
		}
	elsif (!$::Session->IsCheckoutStarted())
		{
		@Response = ACTINIC::BounceToPageEnhanced(undef, ACTINIC::GetPhrase(-1, 2300),
																$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
																$::g_sWebSiteUrl,
																$::g_sContentUrl, $::g_pSetupBlob, $::Session->GetLastShopPage(), \%::g_InputHash,
																$::FALSE);
		$sHTML = $Response[2];
		goto THEEND;
		}
	#
	# Check for paypal pro specific actions
	#
	if ($sAction eq "PPSTARTCHECKOUT")
		{
		IncludePaypalScript();								# Make sure we got the paypal stuff
		@Response = StartPaypalProCheckout();
		if ($Response[0] == $::BADDATA)
			{
			$sHTML = $Response[1];
			$sDetailCookie = $Response[2];
			goto THEEND;
			}
		elsif ($Response[0] != $::SUCCESS)
			{
			ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
			return;
			}
		$sHTML = $Response[1];
		goto THEEND;
		}
	elsif ($sAction eq "PPCOMPLETECHECKOUT")
		{
		IncludePaypalScript();								# Make sure we got the paypal stuff
		CompletePaypalProCheckout();
		exit;
		}
	#
	# Check for google checkout specific actions
	#
	elsif ($sAction eq "GCSTART")
		{
		@Response = ValidateStart($::TRUE);
		if ($Response[0] != $::SUCCESS)
			{
			$sHTML = $Response[1];
			$sDetailCookie = $Response[2];
			goto THEEND;
			}
		IncludeGoogleScript();
		@Response = GCStart();
		if ($Response[0] != $::SUCCESS)
			{
			ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
			return;
			}
		$sHTML = $Response[2];
		goto THEEND;
		}
	elsif ($sAction eq "GCRECALC")
		{
		IncludeGoogleScript();
		@Response = MerchantCalc();
		if ($Response[0] != $::SUCCESS)
			{
			ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
			return;
			}
		$sHTML = $Response[2];
		goto THEEND;
		}
	elsif ($sAction eq "GCCB")
		{
		@Response = HandleCallback();
		binmode STDOUT;										# dump in binary mode since Netscape likes it
		if ($Response[0] != $::SUCCESS)
			{
			ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
			print "HTTP/1.0 400 OK\n";	
			return;
			}
		my $sNow = ACTINIC::GenerateCookieDate();					# generate today's formatted date string
		if($ENV{'PerlXS'} eq 'PerlIS')					# Windows IIS6 may be using PerIS.dll insteasd of perl.exe
			{
			print "HTTP/1.0 200 OK\n";						# so we must insert the protocol and return status
			}					# so we must insert the protocol and return status
		print "Content-type: text/xml\r\n";
		print "Content-length: " . length($Response[2]) . "\r\n";
		print "Date: $sNow\r\n";							# print the date to allow the browser to compensate between server and client differences
		print "\r\n";
		print $Response[2];
		return;
		}
	elsif ($sAction eq $sConfirmButton)
		{
		IncludePaypalScript();								# Make sure we got the paypal stuff
		my $sError = ValidateOrderConfirmPhase();
		if ($sError ne "")
			{
			$sHTML = DisplayOrderConfirmPhase($sError);
			goto THEEND;
			}
		else
			{
			#
			# The paypal object is defined in the plugin script so it
			# should be available by now.
			# Create an instance here and try to invoke direct payment
			#
			my $oPaypal = new ActinicPaypalConnection();
			my $nAmount = ActinicOrder::GetOrderTotal();
			my @Response = $oPaypal->DoExpressCheckoutPayment($nAmount);
			if ($Response[0] != $::SUCCESS)					# paypal request failed
				{
				ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
				return;
				}
			@Response = RecordPaypalOrder($oPaypal);
			if ($Response[0] != $::SUCCESS)
				{
				ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
				return;
				}
			$::g_nCurrentSequenceNumber = 3;
			$sAction = $sNextButton;
			}
		}
	elsif ($sAction eq 'GETPSPFORM')
		{
		my ($nStatus, $sError, $sHTML);
		$sError = ValidatePayment($::TRUE, 'text');
		if ($sError eq '')
			{
			my $sFileName = 'PSPForm.html';
			$::g_pPaymentList->{ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'})}{BOUNCE_HTML} = $sFileName;
			($nStatus, $sError, $sHTML) = CallOCCPlugIn();
			if (!$sError)
				{
				@Response = CompleteOrder();		# record the order
				if ($Response[0] != $::SUCCESS)
					{
					$sError = $Response[1];
					}
				}
			}
		if ($sError)
			{
			$sHTML = "Error: $sError";
			}
		$::Session->SaveSession();
		ACTINIC::PrintText($sHTML);
		return;
		}
	#
	# Processs the possible actions
	#
	my $sChangeRequest = GetChangeRequest();
	if ($sAction eq "" &&
		 $::g_InputHash{ACTIONOVERRIDE})
		{
		$sAction = $::g_InputHash{ACTIONOVERRIDE};
		}
	elsif ($sAction =~ m/$sStartButton/i ||
		 $sAction =~ m/$sNextButton/i ||
		 $sAction =~ m/$sFinishButton/i ||
		 $sAction =~ m/$sConfirmOrderButton/i ||
		 $sAction =~ m/^AUTHORIZE/i ||
		 $sAction =~ m/RECORDORDER/i ||
		 exists $::g_InputHash{$sNextButton . ".x"} ||
		 exists $::g_InputHash{$sConfirmOrderButton . ".x"} ||
		 exists $::g_InputHash{$sFinishButton . ".x"})
		{
		$eDirection = $::FORWARD;
		}
	elsif ($sChangeRequest ne '' ||
			$sAction =~ m/$sBackButton/i ||
		    $sAction =~ m/$sChangeLocationButton/i ||
			 exists $::g_InputHash{$sBackButton . ".x"} ||
			$sAction eq 'RESUME_CHECKOUT')				# move backwards
		{
		$eDirection = $::BACKWARD;
		}
	elsif ($sAction =~ m/$sDoneButton/i ||
			 exists $::g_InputHash{$sDoneButton . ".x"})
		{
		#
		# Go to the catalog main entry page
		#
		my $sRefPage = $::Session->GetLastShopPage();
		#
		# If the unframed checkout URL is specified use this value whatever is this
		#
		if (defined $$::g_pSetupBlob{'UNFRAMED_CHECKOUT_URL'} &&
			 $$::g_pSetupBlob{'UNFRAMED_CHECKOUT_URL'} ne "")
			{
			$sRefPage = $$::g_pSetupBlob{'UNFRAMED_CHECKOUT_URL'};
			}
		if( !$ACTINIC::B2B->Get('UserDigest') )	 # See if there is a LOGIN cookie
			{
			#
			# Redirection to Mall Front Door requested by The Golf Network
			#
			if (defined $::g_InputHash{'ALTERNATEMALLHOME'})
				{
				$sRefPage = $::g_InputHash{'ALTERNATEMALLHOME'};
				}
			}
		@Response = ACTINIC::BounceToPagePlain(0, undef, undef, $::g_sWebSiteUrl,
			$::g_sContentUrl, $::g_pSetupBlob, $sRefPage, \%::g_InputHash);
		if ($Response[0] != $::SUCCESS)
			{
			ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
			return;
			}
		$sHTML = $Response[2];
		#
		# Remove ACTINIC_REFERRER form the bounce page if user logged in
		#
		if ($ACTINIC::B2B->Get('UserDigest'))
			{
			$sHTML =~ s/([\?|\&]ACTINIC_REFERRER[^\&|"|']*)//gi;	#"
			#
			# there is a possibility of the ACTINIC_REFERRER is the first  CGI parameter,
			# so if we cut the ?ACTINIC_REFERRER=... then the URL will look like this
			# http://server/cgi-bin/bb000000.pl&PRODUCTPAGE=Something.html.
			# this would cause a page not found error, so we have to change the & to ?
			#
			$sHTML =~ s/($::g_sAccountScriptName)(\&)/$1\?/gi;
			}
		goto THEEND;
		}
	elsif ($sAction =~ m/OCC_VALIDATE/i)			# occ validation
		{
		@Response = GetOCCValidationData();
		if ($Response[0] != $::SUCCESS)
			{
			ACTINIC::RecordErrors($Response[1], ACTINIC::GetPath());
			$sHTML = '0';
			}
		else
			{
			$sHTML = $Response[2];
			}
		ACTINIC::PrintText($sHTML);
		return;
		}
	else														# cancel
		{
		ValidateInput($::BACKWARD);
		$sHTML = GetCancelPage();
		goto THEEND;
		}
	#
	# Validate and store the current page information
	# Note that the validation is not done for address bokk usethis call
	#
	@Response = ValidateInput($eDirection);
	if ($Response[0] == $::BADDATA)
		{
		$sHTML = $Response[1];
		$sDetailCookie = $Response[2];
		goto THEEND;
		}
	elsif ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
		return;
		}
	#
	# If we're changing locations, we want to go forward now
	#
	if($sAction =~ m/$sChangeLocationButton/i)
		{
		$::g_nCurrentSequenceNumber = $::STARTSEQUENCE;
		$eDirection = $::FORWARD;
		}
		
	if ($sChangeRequest ne '')							# if the user wants to change something
		{
		if ($sChangeRequest eq 'CHANGE_CART')		# if they want to change the cart, we need a redirect
			{
			my $sCartURL = GetCGIScriptURL('ca') . 					# the cart script URL
				"?ACTION=SHOWCART&FROM=CHECKOUT_$::g_nCurrentSequenceNumber";
			
			binmode STDOUT;
			print "Location: $sCartURL\r\n\r\n";
			exit;
			}
		my %hashNextSequence = (
			'CHANGE_ADDRESS' => 0,
			'CHANGE_SHIPPING' => 1,
			'CHANGE_TAX_EXEMPTION' => 1,
			'CHANGE_COUPON' => 1,
			);
		$::g_nNextSequenceNumber = $hashNextSequence{$sChangeRequest};
		}
	elsif ($sAction eq 'RESUME_CHECKOUT')
		{
		$::g_nNextSequenceNumber = $::g_nCurrentSequenceNumber;
		}
	elsif ($eDirection == $::FORWARD)
		{
		$::g_nNextSequenceNumber = $::g_nCurrentSequenceNumber + 1;
		}
	else
		{
		$::g_nNextSequenceNumber = $::g_nCurrentSequenceNumber - 1;
		}
	#
	# Display the next page
	#
	ActinicOrder::ParseAdvancedTax();
	@Response = DisplayPage("", $::g_nNextSequenceNumber, $eDirection);
	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
		return;
		}
	$sHTML = $Response[2];
	$sDetailCookie = $Response[3];

 THEEND:

	ACTINIC::UpdateDisplay($sHTML, $::g_OriginalInputData, undef, undef, $sDetailCookie, ActinicOrder::GenerateCartCookie());
	}

#######################################################
#
# GetChangeRequest - Get the type of change request.
#
# Returns:	0	- name of the button pressed if the user wants to change anything, the name of request or empty string
#
#######################################################

sub GetChangeRequest
	{
	my @arrChangeRequests = qw(CART ADDRESS SHIPPING TAX_EXEMPTION COUPON);
	my $sRequest;
	foreach $sRequest (@arrChangeRequests)					# handle our supported change requests
		{
		my $sRequestKey = 'CHANGE_' . $sRequest;
		if (exists $::g_InputHash{$sRequestKey} ||		# if they pressed a button
			exists $::g_InputHash{$sRequestKey . ".x"})	# or an image
			{
			return $sRequestKey;									# they want to change something
			}
		}
	return '';
	}
	
#######################################################
#
# GetCGIScriptURL - Format a script URL.
#
# Returns:	0	- formatted script URL
#
#######################################################

sub GetCGIScriptURL
	{
	my ($sScriptPrefix) = @_;
	return sprintf('%s%s%6.6d%s', 
		$$::g_pSetupBlob{'CGI_URL'}, $sScriptPrefix, 
		$$::g_pSetupBlob{'CGI_ID'}, $$::g_pSetupBlob{'CGI_EXT'});
	}
	
#######################################################
#
# ValidateInput - validate and save any input from the
#	current page.  If the input parameter is false,
#	the validation is skipped.  This occurs when we are
#	moving backwards.
#
# Params:	0 - the direction
#
# Returns:	0 - status ($::BADDATA if the validation
#					fails)
#				1 - error message (HTML of error page
#					if status is $::BADDATA)
#				2 - if status is $::BADDATA, the detail
#					cookie information
#
#######################################################

sub ValidateInput
	{
	my ($eDirection);
	if ($#_ != 0)
		{
		$eDirection = $::FORWARD;
		}
	($eDirection) = @_;
	my ($bActuallyValidate) = ($eDirection == $::FORWARD);	# only validate text when moving forward
	my (@Response);

	#
	# special case - startup
	#
	if ($::g_nCurrentSequenceNumber == $::STARTSEQUENCE) # if this is startup
		{
		@Response = ValidateStart($bActuallyValidate); # validate the input/cart settings
		return (@Response);
		}
	else
		{
		#
		# Get the phase list for this page
		#
		my $parrInputPhases = GetPhaseListFromInput();
#		die join(" ", @$parrInputPhases);
		#
		# Validate each phase in the current block
		#
		my ($nPhase, $sError);
		foreach $nPhase (@$parrInputPhases)
			{
			#
			# dispatch the page-specific data
			#
			if ($nPhase == $::BILLCONTACTPHASE)
				{
				$sError .= ValidateBill($bActuallyValidate);
				}
			elsif ($nPhase == $::SHIPCONTACTPHASE)
				{
				$sError .= ValidateShipContact($bActuallyValidate);
				}
			elsif ($nPhase == $::SHIPCHARGEPHASE)
				{
				$sError .= ValidateShipCharge($bActuallyValidate);
				}
			elsif ($nPhase == $::TAXCHARGEPHASE)
				{
				$sError .= ActinicOrder::ValidateTax($bActuallyValidate);
				}
			elsif ($nPhase == $::GENERALPHASE)
				{
				$sError .= ValidateGeneral($bActuallyValidate);
				}
			elsif ($nPhase == $::PAYMENTPHASE || $nPhase == $::PAYSELECTPHASE)
				{
				$sError .= ValidatePayment($bActuallyValidate);
				}
			elsif ($nPhase == $::TANDCPHASE)
				{
				$sError .= ValidateTermsAndConditions($bActuallyValidate);
				}
			elsif ($nPhase == $::COUPONPHASE)
				{
				$sError .= ValidateCoupon($bActuallyValidate);
				}
			elsif ($nPhase == $::COMPLETEPHASE)
				{
				# PSP passes method with callback
				#
				if($::g_InputHash{'ACTION'} =~ m/^AUTHORIZE_(\d+)$/i)
					{
					$::g_PaymentInfo{'METHOD'} = $1;
					}
				#
				# Check that the cart is exist. Otherwise report the error
				# and stop processing
				#
				if (!defined $::g_PaymentInfo{'METHOD'})
					{
					if ($$::g_pSetupBlob{USE_DH})				# is it the JAVA applet?
						{												# pass plain text message
						$sError .=  ACTINIC::GetPhrase(-1, 2040);
						}
					else												# is it SharedSSL
						{												# send HTML formatted message
						$sError .= ACTINIC::GetPhrase(-1, 1282);
						}
					next;
					}
				#
				# here when returning from a remote OCC site (SEQUENCE number is 3), recording an applet order,
				# recording a shared SSL order, or verifying
				# a logged in registered customer password
				#
				# nothing to validate.  Password validation is done by JavaScript.
				# But we still call a function to store the signature.
				#
				if (length $::g_PaymentInfo{'METHOD'} == 0) # if the payment method is undefined at this point
					{													# it is because the payment information was hidden
					EnsurePaymentSelection();
					}

				my ($ePaymentMethod) = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"
				if ($ACTINIC::B2B->Get('UserDigest') && # if a user is logged in and
					 ($ePaymentMethod == $::PAYMENT_ON_ACCOUNT || # the payment method is pay on account or
					  $ePaymentMethod == $::PAYMENT_INVOICE))	# the payment method is invoice
					{
					$sError .= ValidateSignature($bActuallyValidate); # record the details
					}

				}
			elsif ($nPhase == $::RECEIPTPHASE)					# receipt page
				{
				# no-op
				}
			elsif ($nPhase == $::PRELIMINARYINFOPHASE)
				{
				if ($sError eq '')
					{
					$sError .= ActinicOrder::ValidatePreliminaryInfo($bActuallyValidate, $::FALSE);
					}
				}
			}

		if ($sError ne '')										# if an error occured
			{
			@Response = DisplayPage($sError, $::g_nCurrentSequenceNumber, $eDirection);	# redisplay this page with the error messages
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
				}
			$Response[0] = $::BADDATA;
			$Response[1] = $Response[2];
			$Response[2] = $Response[3];
			return (@Response);
			}
		}

	return (UpdateCheckoutRecord());
	}

#######################################################
#
# ValidateStart - validate the beginning of the order
#	process
#
# Params:	0 - $::TRUE if the data should be validated
#
# Returns:	0 - status ($::BADDATA if the validation
#					fails)
#				1 - error message (HTML of error page
#					if status is $::BADDATA)
#
#######################################################

sub ValidateStart
	{
	if ($#_ != 0)
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'ValidateStart'), 0, 0);
		}
	my ($bActuallyValidate) = @_;

	#
	# validate the input (if necessary)
	#
	if (!$bActuallyValidate)
		{
		return ($::SUCCESS, "", 0, 0);
		}

	my ($nLineCount, @Response, $Status, $Message);
	my $pCartObject;
	@Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# closed cart
		{
		$nLineCount = 0;									# if so then the order line count is zero
		}
	else														# otherwise
		{
		$pCartObject = $Response[2];				# get the cart
		$nLineCount = $pCartObject->CountItems(); # and count the items in the cart
		}

	my ($sLocalPage, $sBaseUrl, $sHTML);

	if ($nLineCount <= 0)								# if the cart is empty
		{
		$sLocalPage = $::Session->GetLastShopPage();	# get the last shop page
		#
		# At this point we may well be in a frameset, but if unframed checkout then we are about to remove the frames
		# so we need to create a bounce URL to restore the frames
		#
		if (ACTINIC::IsCatalogFramed() ||			# Catalog is framed
			 ($$::g_pSetupBlob{CLEAR_ALL_FRAMES} &&# or custom frames
			 $$::g_pSetupBlob{UNFRAMED_CHECKOUT}))	# and unframed checkout
			{
			$sLocalPage = ACTINIC::RestoreFrameURL($sLocalPage);	# change the URL to restore the frameset
			}
		@Response = ACTINIC::BounceToPageEnhanced(5, ACTINIC::GetPhrase(-1, 1962) . ACTINIC::GetPhrase(-1, 44, $::g_sCart, $::g_sCart) . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2049),
																$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
																$::g_sWebSiteUrl,
																$::g_sContentUrl, $::g_pSetupBlob, $sLocalPage, \%::g_InputHash,
																$::FALSE);
		($Status, $Message, $sHTML) = @Response;	# parse the response
		if ($Status != $::SUCCESS)						# error out
			{
			return (@Response);
			}
		return ($::BADDATA, $sHTML, 0, 0);				# return the goods
		}
	#
	# Check that the cart is valid
	#
	my $pCartList = $pCartObject->GetCartList();
	my $nIndex;
	foreach ($nIndex = $#$pCartList; $nIndex >= 0; $nIndex--)
		{
		my $pFailure;
		($Status, $Message, $pFailure) = ActinicOrder::ValidateOrderDetails($pCartList->[$nIndex], $nIndex);
		if ($Status != $::SUCCESS)						# if the validation failed for any item
			{													# then bounce back to the cart display
			my $sURL = $::g_sCartScript . "?ACTION=SHOWCART";
			$sURL .= $::g_InputHash{SHOP} ? '&SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : '';
			@Response = ACTINIC::BounceToPageEnhanced(5, ACTINIC::GetPhrase(-1, 1962) . ACTINIC::GetPhrase(-1, 2167) . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2049),
																$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
																$::g_sWebSiteUrl,
																$::g_sContentUrl, $::g_pSetupBlob, $sURL , \%::g_InputHash,
																$::FALSE);
			($Status, $Message, $sHTML) = @Response;	# parse the response
			if ($Status != $::SUCCESS)						# error out
				{
				return (@Response);
				}
			return ($::BADDATA, $sHTML, 0, 0);				# return the goods
			}
		}
	#
	# For B2B check shopping cart total against buyers limit
	#
	($Status, $sHTML) = ActinicOrder::CheckBuyerLimit($::g_sCartId,'',$::TRUE);	# Check buyer cash limit
	if ($Status != $::SUCCESS)						# error out
		{
		return ($::BADDATA,$sHTML);
		}
	return ($::SUCCESS, "", 0, 0);
	}

#######################################################
#
# ValidateBill - validate the billing contact data
#
# Params:	0 - $::TRUE if the data should be validated
#
# Returns:	0 - error message
#
#######################################################

sub ValidateBill
	{
	if ($#_ != 0)
		{
		ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 12, 'ValidateBill'), ACTINIC::GetPath());
		}
	my ($bActuallyValidate) = @_;
	#
	# Do not validate the billing address if address book is used
	#
	if( $::g_InputHash{ADBACTION} )
		{
		return('');
		}
	#
	# gather the data
	#
	undef $::g_BillContact{'ADDRESSSELECT'};
	if ($::g_InputHash{INVOICEADDRESSSELECT} )		# B2B - address selected from address list, use account blob
		{
		$::g_BillContact{'ADDRESSSELECT'} = $::g_InputHash{INVOICEADDRESSSELECT};
		my $sUserDigest = $ACTINIC::B2B->Get('UserDigest');
		my ($status, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sUserDigest, ACTINIC::GetPath());
		if ($status != $::SUCCESS)
			{
			return ($sMessage);
			}

		my $pAccount;
		($status, $sMessage, $pAccount) = ACTINIC::GetCustomerAccount($$pBuyer{AccountID}, ACTINIC::GetPath());
		if ($status != $::SUCCESS)
			{
			return ($sMessage);
			}

		my $pAddress;
		($status, $sMessage, $pAddress) = ACTINIC::GetCustomerAddress($$pBuyer{AccountID}, $::g_InputHash{INVOICEADDRESSSELECT}, ACTINIC::GetPath());
		ACTINIC::CloseCustomerAddressIndex();		# The customer index is left open for multiple access, so clean it up here
		if ($status != $::SUCCESS)
			{
			return ($sMessage);
			}
		#
		# For B2B and fixed addresses use buyer name and not address name
		#
		if ($pAccount->{InvoiceAddressRule} != 1 &&
			$pBuyer->{InvoiceAddressRule} != 0 )	# Invoice address rule
			{
			$::g_BillContact{'NAME'}		= $pBuyer->{'Name'};
			$::g_BillContact{'FIRSTNAME'}	= $pBuyer->{'FirstName'};
			$::g_BillContact{'LASTNAME'}	= $pBuyer->{'LastName'};
			$::g_BillContact{'SALUTATION'}	= $pBuyer->{'Salutation'};
			$::g_BillContact{'JOBTITLE'}	= $pBuyer->{'Title'};
			}
		else
			{
			$::g_BillContact{'NAME'}		= $pAccount->{'Name'};
			$::g_BillContact{'FIRSTNAME'}	= $pAccount->{'FirstName'};
			$::g_BillContact{'LASTNAME'}	= $pAccount->{'LastName'};
			$::g_BillContact{'SALUTATION'}	= $pAccount->{'Salutation'};
			$::g_BillContact{'JOBTITLE'}	= $pAccount->{'Title'};
			}
		#
		# Contact details from Main account
		#
		$::g_BillContact{'PHONE'} 		= $pAccount->{'TelephoneNumber'};
		$::g_BillContact{'MOBILE'} 		= $pAccount->{'MobileNumber'};
		$::g_BillContact{'FAX'} 		= $pAccount->{'FaxNumber'};
		if (length $::g_BillContact{'PHONE'} > $::g_pFieldSizes->{'PHONE'})	# phone length is too long
			{
			#
			# Perhaps this came from Sage with format phone1 / phone2
			#
			$::g_BillContact{'PHONE'}	=~ s/(.*?)(\/.*|$)/$1/;	# truncate at '/' if present
			}
		$::g_BillContact{'PHONE'}		=~ s/(.{0,$::g_pFieldSizes->{'PHONE'}}).*/$1/;	# trim to max field size
		$::g_BillContact{'MOBILE'}		=~ s/(.{0,$::g_pFieldSizes->{'MOBILE'}}).*/$1/;	# trim to max field size
		$::g_BillContact{'FAX'}			=~ s/(.{0,$::g_pFieldSizes->{'FAX'}}).*/$1/;	# trim to max field size
		$::g_BillContact{'EMAIL'} 		= $pAccount->{'EmailAddress'};
		$::g_BillContact{'EMAIL_CONFIRM'} 		= $pAccount->{'EmailAddress'};
		#
		# Use selected address as invoice address
		#
		$::g_BillContact{'ADDRESS1'} 		= $pAddress->{'Line1'};
		$::g_BillContact{'ADDRESS2'} 		= $pAddress->{'Line2'};
		$::g_BillContact{'ADDRESS3'} 		= $pAddress->{'Line3'};
		$::g_BillContact{'ADDRESS4'} 		= $pAddress->{'Line4'};
		$::g_BillContact{'POSTALCODE'} 	= $pAddress->{'PostCode'};
		$::g_BillContact{'COUNTRY'} 		= ACTINIC::GetCountryName($pAddress->{'CountryCode'});
		$::g_BillContact{'SEPARATE'}		= $::TRUE;
		#
		# Update location info
		#
		$::g_LocationInfo{INVOICE_COUNTRY_CODE} = $pAddress->{'CountryCode'};
		$::g_LocationInfo{INVOICE_REGION_CODE} = $pAddress->{'StateCode'};
		#
		# Handle tax exemption for this address
		#
		ActinicOrder::ParseAdvancedTax();
		if($$::g_pTaxSetupBlob{TAX_BY} == $::eTaxByInvoice)
			{
			if(defined $$::g_pTaxSetupBlob{TAX_1} &&
				$$::g_pTaxSetupBlob{TAX_1}{ID} == $pAddress->{'Tax1ID'})
				{
				$::g_TaxInfo{'EXEMPT1'} = $pAddress->{'ExemptTax1'} ? 1 : 0;
				$::g_TaxInfo{'EXEMPT1DATA'} = $pAddress->{'Tax1ExemptData'};
				}
			if(defined $$::g_pTaxSetupBlob{TAX_2} &&
				$$::g_pTaxSetupBlob{TAX_2}{ID} == $pAddress->{'Tax2ID'})
				{
				$::g_TaxInfo{'EXEMPT2'} = $pAddress->{'ExemptTax2'} ? 1 : 0;
				$::g_TaxInfo{'EXEMPT2DATA'} = $pAddress->{'Tax2ExemptData'};
				}
			}
		#
		# For safety's sake, let's define the unspecified flags here
		#
		$::g_BillContact{'MOVING'} 		= $::FALSE;
		$::g_BillContact{'PRIVACY'} 		= $::TRUE;
		$::g_BillContact{'REMEMBERME'}	= $::FALSE; 
		ACTINIC::CopyHash(\%::g_BillContact, \%::g_InputHash, '', 'INVOICE');
		}
	else
		{
		#
		# Get the user input
		#
		GetContactFromInput('INVOICE', \%::g_BillContact);
		#
		# Handle other checkbox values
		#
		$::g_BillContact{'SEPARATE'}	= ($::g_InputHash{'SEPARATESHIP'} ne "") ? $::TRUE : $::FALSE;
		$::g_BillContact{'REMEMBERME'}	= (defined $::g_InputHash{'REMEMBERME'} && $::g_InputHash{'REMEMBERME'} ne "") ?
		  $::TRUE : $::FALSE;
		#
		# Handle location input
		#
		$::g_LocationInfo{INVOICE_COUNTRY_CODE} = $::g_InputHash{'LocationInvoiceCountry'};
		$::g_LocationInfo{INVOICE_REGION_CODE} = $::g_InputHash{'LocationInvoiceRegion'};
		if (!$::g_BillContact{'SEPARATE'})
			{
			$::g_LocationInfo{DELIVERY_COUNTRY_CODE} = $::g_InputHash{'LocationInvoiceCountry'};
			$::g_LocationInfo{DELIVERY_REGION_CODE} = $::g_InputHash{'LocationInvoiceRegion'};
			}
		ActinicOrder::NormaliseAddressLocation('Invoice', $bActuallyValidate);
		}

	if ($$::g_pSetupBlob{SHOPPER_NAME_HANDLING_MODE} eq 1)	# first name/ last name handling
		{
		$::g_BillContact{'NAME'}	=  $::g_BillContact{'FIRSTNAME'}.' '.$::g_BillContact{'LASTNAME'};
		$::g_BillContact{'NAME'}	=~ s/(.{0,$::g_pFieldSizes->{'NAME'}}).*/$1/;	# trim to max field size
		}
	#
	# Make sure the address fields are in sync with the location codes
	#
	ActinicOrder::SetAddressFieldsFromLocationCodes('Invoice');
	#
	# If we using same shipping and delivery addresses, copy hashes
	#
	if (!$::g_BillContact{'SEPARATE'})
		{
		ACTINIC::CopyHash(\%::g_BillContact, \%::g_ShipContact, '',  '');
		}
	#
	# clean up the input
	#
	ACTINIC::TrimHashEntries(\%::g_BillContact);
	#
	# validate field input
	#
	my ($sError);
	if (!$bActuallyValidate)
		{
		return ($sError);
		}
	#
	# Validate field requirement status
	#
	$sError .= CheckInputField(0, GetAddressMapping(), \%::g_BillContact);
	#
	# User defined requires special validation
	#
	if (ACTINIC::IsPromptRequired(0, 14) &&
		$::g_BillContact{'USERDEFINED'} eq "" &&
		!$ACTINIC::B2B->Get('UserDigest'))
		{
		$sError .= ACTINIC::GetRequiredMessage(0, 14);
		}
	if (length $::g_BillContact{'USERDEFINED'} > $::g_pFieldSizes->{'USERDEFINED'})
		{
		$sError .= ACTINIC::GetLengthFailureMessage(0, 14, $::g_pFieldSizes->{'USERDEFINED'});
		}
	#
	# Validate the shipping info for AVS
	#
	if($sError eq '')
		{
#		$sError .= ActinicOrder::ValidatePreliminaryInfo($bActuallyValidate);
		}
	return ActinicOrder::FormatCheckoutInputError(ACTINIC::GetPhrase(-1, 147), $sError);
	}

#######################################################
#
# GetContactFromInput - Get the contact details from input hash
#
# Input:	$sKeyPrefix		- prefix of keys in input hash 'INVOICE' or 'DELIVER'
#			$rhashContact	- ref to contact hash
#
# Author:	Mike Purnell
#
#######################################################

sub GetContactFromInput
	{
	my ($sKeyPrefix, $rhashContact) = @_;
	
	$rhashContact->{'MOVING'}	= $::FALSE;
	$rhashContact->{'PRIVACY'}	= $::FALSE;
	my $sKey;
	foreach $sKey (@ActinicOrder::arrAddressKeys)
		{
		$rhashContact->{$sKey} = '';
		}
	ACTINIC::CopyHash(\%::g_InputHash, $rhashContact, $sKeyPrefix, '', $::FALSE);
	#
	# Convert checkbox values to numeric
	#
	$rhashContact->{'MOVING'}	= ($rhashContact->{'MOVING'}) ? $::TRUE : $::FALSE;
	$rhashContact->{'PRIVACY'}	= ($rhashContact->{'PRIVACY'}) ? $::TRUE : $::FALSE;
	}
	
#######################################################
#
# GetAddressMapping - Get the map of CGI identifiers to address prompt IDs
#
# Returns:	0 - ref to map
#
# Author:	Mike Purnell
#
#######################################################

sub GetAddressMapping
	{
	my $rhashFields =
		{
		'SALUTATION' 		=> 0,
		'NAME'				=> 1,
		'JOBTITLE'			=> 2,
		'COMPANY'			=> 3,
		'ADDRESS1'			=> 4,
		'ADDRESS2'			=> 5,
		'ADDRESS3'			=> 6,
		'ADDRESS4'			=> 7,
		'POSTALCODE'		=> 8,
		'COUNTRY'			=> 9,
		'PHONE'				=> 10,
		'FAX'					=> 11,
		'EMAIL'				=> 12,
		'MOBILE'				=> 20,
		'FIRSTNAME'			=> 21,
		'LASTNAME'			=> 22,
		'EMAIL_CONFIRM'	=> 23,
		};
	#
	# Remove the name handling fields which are not required for validation
	#
	if ($$::g_pSetupBlob{SHOPPER_NAME_HANDLING_MODE} eq 1) # first name/ last name handling
		{
		delete $rhashFields->{'NAME'};
		}
	else
		{
		delete  $rhashFields->{'FIRSTNAME'};
		delete  $rhashFields->{'LASTNAME'};
		}
	return $rhashFields;
	}
	
#######################################################
#
# ValidateCoupon - Validate the terms and conditions
#
# Input:	$bActuallyValidate - $::TRUE if the data should be validated
#
# Returns:	0 - error message or empty string
#
#######################################################

sub ValidateCoupon
	{
	my ($bActuallyValidate) = @_;
	if (exists $::g_InputHash{'COUPONCODE'})
		{
		$::g_PaymentInfo{'COUPONCODE'} = $::g_InputHash{'COUPONCODE'};
		}
	if ($::g_InputHash{'COUPONCODE'} ne "" &&			# if we got coupon code
		 $$::g_pDiscountBlob{'COUPON_ON_CHECKOUT'})	# and it is allowed during checkout
		{
		if ($bActuallyValidate)
			{
			$::Session->GetCartObject();						# be sure discounting package is loaded
			my @Response = ActinicDiscounts::ValidateCoupon($::g_PaymentInfo{'COUPONCODE'});
			if ($Response[0] == $::FAILURE)
				{
				return ActinicOrder::FormatCheckoutInputError(ACTINIC::GetPhrase(-1, 2353), $Response[1]);
				}
			}
		}
	return '';
	}

#######################################################
#
# ValidateTermsAndConditions - Validate the terms and conditions
#
# Input:	$bActuallyValidate - $::TRUE if the data should be validated
#
# Returns:	0 - error message or empty string
#
#######################################################

sub ValidateTermsAndConditions
	{
	my ($bActuallyValidate) = @_;
	
	$::g_BillContact{'AGREEDTANDC'}	= (defined $::g_InputHash{'AGREETERMSCONDITIONS'} && $::g_InputHash{'AGREETERMSCONDITIONS'} ne "") ? $::TRUE : $::FALSE;
	my $sError = '';
	if ($bActuallyValidate)
		{
		if (defined $$::g_pSetupBlob{'CHECKOUT_NEEDS_TERMS_AGREED'} &&	# T&C flag is used
			!$::g_BillContact{'AGREEDTANDC'})			# but it is not checked
			{
			$sError = ACTINIC::GetPhrase(-1, 2385);	# get the appropriate message
			}
		}
	return ActinicOrder::FormatCheckoutInputError(ACTINIC::GetPhrase(-1, 2386), $sError);
	}
	
#######################################################
#
# ValidateShipContact - validate the shipping contact data
#
# Params:	0 - $::TRUE if the data should be validated
#
# Returns:	0 - error message
#
#######################################################

sub ValidateShipContact
	{
	if ($#_ != 0)
		{
		ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 12, 'ValidateShipContact'), ACTINIC::GetPath());
		}
	my ($bActuallyValidate) = @_;
	#
	# Make Address Book
	#
	if ($::ACT_ADB)
		{
		ConfigureAddressBook();
		$::ACT_ADB->ToForm();
		$::s_VariableTable{$::VARPREFIX.'ADDRESSBOOK'}	= $::ACT_ADB->Show();
		}
	else
		{
		$::s_VariableTable{$::VARPREFIX.'ADDRESSBOOK'}	= "";
		}
	#
	# gather the data
	#
	#
	# if they indicated that they are shipping to the same address, set the shipping address to the billing address
	# and mark it as finished.  Otherwise mark it as unfinished
	#
	# Presnet: handle reversal of check box action - start of un-comment
	#
	my $bCheckReversed = (defined $$::g_pSetupBlob{'REVERSE_ADDRESS_CHECK'} &&
		$$::g_pSetupBlob{'REVERSE_ADDRESS_CHECK'});
	undef $::g_ShipContact{ADDRESSSELECT};
	if( $::g_InputHash{DELIVERADDRESSSELECT} )		# B2B - address selected from address list, use account blob
		{
		$::g_ShipContact{ADDRESSSELECT} = $::g_InputHash{DELIVERADDRESSSELECT};
		my $sUserDigest = $ACTINIC::B2B->Get('UserDigest');
		my ($status, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sUserDigest, ACTINIC::GetPath());
		if ($status != $::SUCCESS)
			{
			return ($sMessage);
			}

		my $pAccount;
		($status, $sMessage, $pAccount) = ACTINIC::GetCustomerAccount($$pBuyer{AccountID}, ACTINIC::GetPath());
		if ($status != $::SUCCESS)
			{
			return ($sMessage);
			}

		my $pAddress;
		($status, $sMessage, $pAddress) = ACTINIC::GetCustomerAddress($$pBuyer{AccountID}, $::g_InputHash{DELIVERADDRESSSELECT}, ACTINIC::GetPath());
		ACTINIC::CloseCustomerAddressIndex();		# The customer index is left open for multiple access, so clean it up here
		if ($status != $::SUCCESS)
			{
			return ($sMessage);
			}

		#
		# Set the company name
		#
		if ($pAccount->{CompanyName} ne '')
			{
			$::g_ShipContact{'COMPANY'}	= $pAccount->{CompanyName};
			}
		else
			{
			$::g_ShipContact{'COMPANY'}	= $pAccount->{AccountName};
			}		
		#
		# For B2B and fixed addresses use buyer name and not address name
		#
		$::g_ShipContact{'NAME'}		= $pBuyer->{Name};
		$::g_ShipContact{'FIRSTNAME'}	= $pBuyer->{'FirstName'};
		$::g_ShipContact{'LASTNAME'}	= $pBuyer->{'LastName'};
		$::g_ShipContact{'SALUTATION'}	= $pBuyer->{Salutation};
		$::g_ShipContact{'JOBTITLE'}	= $pBuyer->{Title};
		$::g_ShipContact{'PHONE'} 		= $pBuyer->{'TelephoneNumber'};
		$::g_ShipContact{'MOBILE'} 		= $pBuyer->{'MobileNumber'};
		$::g_ShipContact{'FAX'} 		= $pBuyer->{'FaxNumber'};
		if (length $::g_ShipContact{'PHONE'} > $::g_pFieldSizes->{'PHONE'})	# phone length is too long
			{
			#
			# Perhaps this came from Sage with format phone1 / phone2
			#
			$::g_ShipContact{'PHONE'}	=~ s/(.*?)(\/.*|$)/$1/;	# truncate at '/' if present
			}
		$::g_ShipContact{'PHONE'}		=~ s/(.{0,$::g_pFieldSizes->{'PHONE'}}).*/$1/;	# trim to max field size
		$::g_ShipContact{'MOBILE'}		=~ s/(.{0,$::g_pFieldSizes->{'MOBILE'}}).*/$1/;	# trim to max field size
		$::g_ShipContact{'FAX'}			=~ s/(.{0,$::g_pFieldSizes->{'FAX'}}).*/$1/;	# trim to max field size
		$::g_ShipContact{'EMAIL'} 		= $pBuyer->{'EmailAddress'};
		$::g_ShipContact{'EMAIL_CONFIRM'} 		= $pBuyer->{'EmailAddress'};

		$::g_ShipContact{'ADDRESS1'}	= $pAddress->{'Line1'};
		$::g_ShipContact{'ADDRESS2'}	= $pAddress->{'Line2'};
		$::g_ShipContact{'ADDRESS3'}	= $pAddress->{'Line3'};
		$::g_ShipContact{'ADDRESS4'}	= $pAddress->{'Line4'};
		$::g_ShipContact{'POSTALCODE'} 	= $pAddress->{'PostCode'};
		$::g_ShipContact{'COUNTRY'} 	= ACTINIC::GetCountryName($pAddress->{'CountryCode'});
		#
		# Copy the country/state codes to location info
		#
		$::g_LocationInfo{DELIVERY_COUNTRY_CODE} = $pAddress->{'CountryCode'};
		$::g_LocationInfo{DELIVERY_REGION_CODE} = $pAddress->{'StateCode'};
		#
		# For safety's sake, let's define the unspecified flags here
		#
		$::g_ShipContact{PRIVACY} 		  = $::TRUE;
		}
	else
		{
		if (((!$bCheckReversed && !$::g_BillContact{'SEPARATE'}) ||
			  ($bCheckReversed && $::g_BillContact{'SEPARATE'})) )			# ship address = bill address
		  #
		  # Presnet: end of un-comment / start of comment-out
		  #
		  #	if (!$::g_BillContact{'SEPARATE'}) ||
		  #		 !$bDeliverAddressRequired)
		  #
		  # Presnet: end of comment-out
		  #
			{
			$::g_ShipContact{'SALUTATION'} 	= $::g_BillContact{'SALUTATION'};
			$::g_ShipContact{'NAME'}		= $::g_BillContact{'NAME'};
			$::g_ShipContact{'FIRSTNAME'}	= $::g_BillContact{'FIRSTNAME'};
			$::g_ShipContact{'LASTNAME'} 	= $::g_BillContact{'LASTNAME'};
			$::g_ShipContact{'JOBTITLE'}	= $::g_BillContact{'JOBTITLE'};
			$::g_ShipContact{'COMPANY'} 	= $::g_BillContact{'COMPANY'};
			$::g_ShipContact{'ADDRESS1'}	= $::g_BillContact{'ADDRESS1'};
			$::g_ShipContact{'ADDRESS2'}	= $::g_BillContact{'ADDRESS2'};
			$::g_ShipContact{'ADDRESS3'}	= $::g_BillContact{'ADDRESS3'};
			$::g_ShipContact{'ADDRESS4'}	= $::g_BillContact{'ADDRESS4'};
			$::g_ShipContact{'POSTALCODE'} 	= $::g_BillContact{'POSTALCODE'};
			$::g_ShipContact{'COUNTRY'} 	= $::g_BillContact{'COUNTRY'};
			my $sUserDigest = $ACTINIC::B2B->Get('UserDigest');	# get the B2B user digest, if any
			if ($sUserDigest)								# if this is a registered user
				{
				#
				# B2B - use buyer contact details instead of main account details
				#
				my ($status, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sUserDigest, ACTINIC::GetPath());
				if ($status != $::SUCCESS)
					{
					return ($sMessage);					# return error if buyer not found
					}
				$::g_ShipContact{'PHONE'} 		= $pBuyer->{'TelephoneNumber'};
				$::g_ShipContact{'MOBILE'}	 	= $pBuyer->{'MobileNumber'};
				$::g_ShipContact{'FAX'} 		= $pBuyer->{'FaxNumber'};
				if (length $::g_ShipContact{'PHONE'} > $::g_pFieldSizes->{'PHONE'})	# phone length is too long
					{
					#
					# Perhaps this came from Sage with format phone1 / phone2
					#
					$::g_ShipContact{'PHONE'}	=~ s/(.*?)(\/.*|$)/$1/;	# truncate at '/' if present
					}
				$::g_ShipContact{'PHONE'}		=~ s/(.{0,$::g_pFieldSizes->{'PHONE'}}).*/$1/;	# trim to max field size
				$::g_ShipContact{'MOBILE'}		=~ s/(.{0,$::g_pFieldSizes->{'MOBILE'}}).*/$1/;	# trim to max field size						$::g_ShipContact{'FAX'}			=~ s/(.{0,$::g_pFieldSizes->{'FAX'}}).*/$1/;	# trim to max field size
				$::g_ShipContact{'EMAIL'} 		= $pBuyer->{'EmailAddress'};
				}
			else
				{
				#
				# Not B2B - use same contact details as for invoice address
				#
				$::g_ShipContact{'PHONE'} 		= $::g_BillContact{'PHONE'};
				$::g_ShipContact{'MOBILE'} 		= $::g_BillContact{'MOBILE'};
				$::g_ShipContact{'FAX'} 		= $::g_BillContact{'FAX'};
				$::g_ShipContact{'EMAIL'} 		= $::g_BillContact{'EMAIL'};
				$::g_ShipContact{'EMAIL_CONFIRM'} 		= $::g_BillContact{'EMAIL_CONFIRM'};
				}
			#
			# If we don't have separate shipping address then the user defined
			# delivery field should be cleared (cix:act_shop_scrpt/bug_details:655)
			#
			$::g_ShipContact{'USERDEFINED'} 	= "";
			}
		else
			{
			#
			# Get the user input
			#
			GetContactFromInput('DELIVER', \%::g_ShipContact);
			if ($::g_BillContact{'SEPARATE'})
				{
				$::g_LocationInfo{DELIVERY_COUNTRY_CODE} = $::g_InputHash{'LocationDeliveryCountry'};
				$::g_LocationInfo{DELIVERY_REGION_CODE} = $::g_InputHash{'LocationDeliveryRegion'};
				}
			}
		$::g_ShipContact{'PRIVACY'} = $::g_BillContact{'PRIVACY'}; # the privacy setting is always the same for delivery and invoice contacts
		ActinicOrder::NormaliseAddressLocation('Delivery');
		}
	if ($$::g_pSetupBlob{SHOPPER_NAME_HANDLING_MODE} eq 1)	# first name/ last name handling
		{
		$::g_ShipContact{'NAME'} =  $::g_ShipContact{'FIRSTNAME'} .' '.	$::g_ShipContact{'LASTNAME'};
		$::g_ShipContact{'NAME'} =~ s/(.{0,$::g_pFieldSizes->{'NAME'}}).*/$1/;	# trim to max field size
		}
	#
	# Make sure the address fields are in sync with the location codes
	#
	ActinicOrder::SetAddressFieldsFromLocationCodes('Delivery');
	#
	#
	# clean up the input
	#
	ACTINIC::TrimHashEntries(\%::g_ShipContact);
	my ($sError);
	#
	# Skip validation if requested
	#
	if (!$bActuallyValidate ||							# if we are not validating, or
		(!$bCheckReversed && !$::g_BillContact{'SEPARATE'}) ||
		($bCheckReversed && $::g_BillContact{'SEPARATE'}))				# if the delivery address is ignored
		{
		return ($sError);									# don't do the validation
		}
	#
	# Validate field input
	#
	$sError .= CheckInputField(1, GetAddressMapping(), \%::g_ShipContact);
	#
	# User defined requires special validation
	#
	if (ACTINIC::IsPromptRequired(1, 13) &&
		$::g_ShipContact{'USERDEFINED'} eq "" &&
		!$ACTINIC::B2B->Get('UserDigest'))
		{
		$sError .= ACTINIC::GetRequiredMessage(1, 13);
		}
	if (length $::g_ShipContact{'USERDEFINED'} > $::g_pFieldSizes->{'USERDEFINED'})
		{
		$sError .= ACTINIC::GetLengthFailureMessage(1, 13, $::g_pFieldSizes->{'USERDEFINED'});
		}
	#
	# Validate the shipping info for AVS
	#
	if($sError eq '')
		{
#		$sError .= ActinicOrder::ValidatePreliminaryInfo($bActuallyValidate);
		}
	return ActinicOrder::FormatCheckoutInputError(ACTINIC::GetPhrase(-1, 148), $sError);
	}

#######################################################
#
# CheckInputField - validate the user input. Check if the
# 	required fields are specified and the length is ok.
#
# Params:	0 - checkout phase ID
#				1 - field mappings
#				2 - hash to be validated
#				3 - 'text' if the error message should be formatted as text (to display an error in a message box)
#
# Returns:	0 - error message
#
# Author: Zoltan Magyar
#
#######################################################

sub CheckInputField
	{
	my ($nPhase, $pMapping, $pHash, $sFormat) = @_;

	my ($sKey, $sError);
	my ($parrInputKeys) = GetInputHashKeysInSourceOrder($nPhase);
	#
	# Check if the field is required but not supplied in the hash
	#
	my $sAddressPrefix = $nPhase == 0 ? 'INVOICE' : 'DELIVER';
	my %hashInputKey;
	if (!$::g_InputHash{$sAddressPrefix . 'ADDRESSSELECT'})
		{
		foreach $sKey (@$parrInputKeys)
			{
			$hashInputKey{$sKey} = 1;
			}
		foreach $sKey (keys %{$pMapping})
			{
			if (ACTINIC::IsPromptRequired($nPhase, $pMapping->{$sKey}) &&
				!exists $hashInputKey{$sKey})
				{
				$sError .= ACTINIC::GetRequiredMessage($nPhase, $pMapping->{$sKey}, "This is a required field but there is no way to input it");
				}
			}
		}
	#
	# Check if the field is required but user has entered missing or invalid data
	#
	foreach $sKey (@$parrInputKeys)
		{
		if (ACTINIC::IsPromptRequired($nPhase, $pMapping->{$sKey}) &&
			$$pHash{$sKey} eq "")
			{
			if ($sFormat ne 'text')
				{
				$sError .= ACTINIC::GetRequiredMessage($nPhase, $pMapping->{$sKey});
				}
			else
				{
				$sError .= ACTINIC::GetRequiredMessageAsText($nPhase, $pMapping->{$sKey});
				}
			}
		if ($sKey eq 'EMAIL_CONFIRM')
			{
			if ($$pHash{$sKey} ne $$pHash{'EMAIL'})
				{
				$sError .= ACTINIC::GetRequiredMessage($nPhase, $pMapping->{'EMAIL'}, "Email doesn't match");
				}
			}
		elsif ($sKey eq 'EMAIL' &&							# if this is an email
			$$pHash{$sKey} ne ''	&&						# and they supplied something
			$$pHash{$sKey} !~ /\@/)						# and it is not in the expected format
			{
			$sError .= ACTINIC::GetRequiredMessage($nPhase, $pMapping->{$sKey}, ACTINIC::GetPhrase(-1, 2378));
			}
		#
		# Check if field length is ok
		#
		if (exists $::g_pFieldSizes->{$sKey} &&
			(length $$pHash{$sKey} > $::g_pFieldSizes->{$sKey}))
			{
			if ($sFormat ne 'text')
				{
				$sError .= ACTINIC::GetLengthFailureMessage($nPhase, $pMapping->{$sKey}, $::g_pFieldSizes->{$sKey});
				}
			else
				{
				$sError .= ACTINIC::GetLengthFailureMessageAsText($nPhase, $pMapping->{$sKey}, $::g_pFieldSizes->{$sKey});
				}
			}
		}
	return $sError;
	}

#######################################################
#
# GetInputHashKeysInSourceOrder - Get input parameters
#	with supplied phase prefix in the order cgi received them 
#
# Input:	$nPhase	- phase
#
# Returns:	0 - ref to array of keys with prefix stripped off
#				1 - prefix to signify field
#
# Author: Mike Purnell
#
#######################################################

sub GetInputHashKeysInSourceOrder
	{
	my ($nPhase) = @_;
	
	#
	# Set up hash of key prefixes and option prefix for fields
	#
	my %hashPrefixes =
		(
		0 => 'INVOICE',
		1 => 'DELIVER',
		4 => 'GENERAL',
		5 => 'PAYMENT',
		);
	my ($sPrefix);
	if (defined $hashPrefixes{$nPhase})				# get prefixes from hash
		{
		$sPrefix = $hashPrefixes{$nPhase};
		}
	my $sLocationPrefix = 
		$nPhase == 0 ? 'LocationInvoice' :
		$nPhase == 1 ? 'LocationDelivery' : 
		'';
	#
	# Get the fields in order they were supplied to script
	#
	my @arrKeyValues = split /[&=]/, $::g_OriginalInputData;	# split into key value pairs
	my @arrKeys;
	my %hashKeysAdded = ();
	my $i;
	for ($i = 0; $i < scalar(@arrKeyValues); $i += 2)
		{
		my $sKey = $arrKeyValues[$i];
		if ($sKey =~ /^$sPrefix(.*)$/)
			{
			AddValueToArrayIfUnique(\@arrKeys, \%hashKeysAdded, $1);
			}
		elsif ($sLocationPrefix ne '' &&
			$sKey =~ /^$sLocationPrefix(.*)$/)
			{
			if ($1 eq 'Country')
				{
				AddValueToArrayIfUnique(\@arrKeys, \%hashKeysAdded, 'COUNTRY');
				}
			elsif ($1 eq 'Region')
				{
				AddValueToArrayIfUnique(\@arrKeys, \%hashKeysAdded, 'ADDRESS4');
				}
			}
		}
	return (\@arrKeys);
	}

#######################################################
#
# AddValueToArrayIfUnique - Add a value to an array if it hasn't been added before
#
# Input:	$parrTarget		- ref to array
#			$phashValues	- ref to hash of existing values
#			$sValue			- value to add
#
#######################################################

sub AddValueToArrayIfUnique
	{
	my ($parrTarget, $phashValues, $sValue) = @_;
	if (!exists $phashValues->{$sValue})
		{
		push @$parrTarget, $sValue;
		$phashValues->{$sValue} = 1;
		}
	}
	
#######################################################
#
# GetPhaseListFromInput - Get a list of phases from input
#
# Returns:	0 - ref to list of phases
#
#######################################################

sub GetPhaseListFromInput
	{
	my $rhashPhases = {
		'INVOICE'			=> $::BILLCONTACTPHASE,
		'DELIVER'			=> $::SHIPCONTACTPHASE,
		'SHIPPING'			=> $::SHIPCHARGEPHASE,
		'TAX'					=> $::TAXCHARGEPHASE,
		'GENERAL'			=> $::GENERALPHASE,
		'PAYMENT'			=> $::PAYMENTPHASE,
		'COMPLETE'			=> $::COMPLETEPHASE,
		'RECEIPT'			=> $::RECEIPTPHASE,
		'PRELIM'				=> $::PRELIMINARYINFOPHASE,
		'PAYMENTSELECT'	=> $::PAYSELECTPHASE,
		'COUPON'				=> $::COUPONPHASE,
		'TANDC'				=> $::TANDCPHASE,
		};
	
	my @arrKeyValues = split /[&=]/, $::g_OriginalInputData;	# split into key value pairs
	my @arrKeys;
	my $i;
	for ($i = 0; $i < scalar(@arrKeyValues); $i += 2)
		{
		my $sKey = $arrKeyValues[$i];
		if ($arrKeyValues[$i] eq 'ActCheckoutPhase')
			{
			my $sPhaseLabel = $arrKeyValues[$i + 1];
			push @arrKeys, $rhashPhases->{$sPhaseLabel};
			}
		}
	if ($::g_nCurrentSequenceNumber == 3)
		{
		push @arrKeys, $::COMPLETEPHASE;
		}
	return (\@arrKeys);
	}
	
#######################################################
#
# ValidateShipCharge - validate the shipping charge data
#
# Params:	0 - $::TRUE if the data should be validated
#
# Returns:	0 - error message
#
# Expects:	$::g_ShipInfo to be defined
#
#######################################################

sub ValidateShipCharge
	{
	if ($#_ != 0)
		{
		ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 12, 'ValidateShipCharge'), ACTINIC::GetPath());
		}
	my ($bActuallyValidate) = @_;
	#
	# retrieve and validate the shipping values
	#
	my ($sError);
	if ($$::g_pSetupBlob{MAKE_SHIPPING_CHARGE} &&	# shipping is enabled and
		 !ActinicOrder::IsPhaseHidden($::SHIPCHARGEPHASE)) # it is not hidden
		{
		#
		# do advanced shipping validation - only report validation problems if we are actually validating
		#
		my @Response = ActinicOrder::CallShippingPlugIn();
		if ($bActuallyValidate)								# if we are actually validating the input and
			{
			if ($Response[0] != $::SUCCESS)				# the script failed
				{
				$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) .
								ACTINIC::GetPhrase(-1, 102) . ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) . " - ". $Response[1] . "<BR>\n";
				}
			elsif (${$Response[2]}{ValidateFinalInput} != $::SUCCESS) # the validation failed
				{													# return the error
				$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) .
								ACTINIC::GetPhrase(-1, 102) . ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) . " - ". ${$Response[3]}{ValidateFinalInput} . "<BR>\n";
				}
			}
		}
	#
	# retrieve and validate the user defined shipping
	#
	$::g_ShipInfo{'USERDEFINED'}	= $::g_InputHash{'SHIPUSERDEFINED'};
	#
	# clean up the input
	#
	ACTINIC::TrimHashEntries(\%::g_ShipInfo);

	if (defined $::g_InputHash{'SHIPUSERDEFINED'})	# May not be present if only DD products in cart
		{
		if ($bActuallyValidate &&
			ACTINIC::IsPromptRequired(2, 1) &&
			$::g_ShipInfo{'USERDEFINED'} eq "")
			{
			$sError .= ACTINIC::GetRequiredMessage(2, 1);
			}
		if (length $::g_ShipInfo{'USERDEFINED'} > $::g_pFieldSizes->{'USERDEFINED'})
			{
			$sError .= ACTINIC::GetLengthFailureMessage(2, 1, $::g_pFieldSizes->{'USERDEFINED'});
			}

		if ($sError ne "")										# if there are any errors
			{															# indicate the problem phase
			$sError = ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 149) . ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1961, $sError);
			}
		}

	return ($sError);
	}

#######################################################
#
# ValidateGeneral - validate the general info data
#
# Params:	0 - $::TRUE if the data should be validated
#
# Returns:	0 - error message
#
#######################################################

sub ValidateGeneral
	{
	if ($#_ != 0)
		{
		ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 12, 'ValidateGeneral'), ACTINIC::GetPath());
		}
	my ($bActuallyValidate) = @_;
	#
	# gather the data
	#
	$::g_GeneralInfo{'HOWFOUND'} 	= $::g_InputHash{'GENERALHOWFOUND'};
	$::g_GeneralInfo{'WHYBUY'} 		= $::g_InputHash{'GENERALWHYBUY'};
	$::g_GeneralInfo{'USERDEFINED'} = $::g_InputHash{'GENERALUSERDEFINED'};
	#
	# clean up the input
	#
	ACTINIC::TrimHashEntries(\%::g_GeneralInfo);
	#
	# validate field input
	#
	my ($sError);
	if (!$bActuallyValidate)
		{
		return ($sError);
		}
	#
	# validate field requirement status
	#
	my $pMapping =
		{
		'HOWFOUND' 		=> 0,
		'WHYBUY'			=> 1,
		'USERDEFINED'	=> 2,
		};
	$sError .= CheckInputField(4, $pMapping, \%::g_GeneralInfo);

	return ActinicOrder::FormatCheckoutInputError(ACTINIC::GetPhrase(-1, 151), $sError);
	}

#######################################################
#
# ValidatePayment - validate the payment info data
#
# Params:	0 - $::TRUE if the data should be validated
#
# Returns:	0 - error message
#
#######################################################

sub ValidatePayment
	{
	if ($#_ != 0 && $#_ != 1)
		{
		ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 12, 'ValidatePayment'), ACTINIC::GetPath());
		}
	my ($bActuallyValidate, $sFormat) = @_;
	#
	# gather the data
	#
	$::g_PaymentInfo{'METHOD'}			= $::g_InputHash{'PAYMENTMETHOD'};
	$::g_PaymentInfo{'USERDEFINED'}	= $::g_InputHash{'PAYMENTUSERDEFINED'};
	$::g_PaymentInfo{'PONO'}			= $::g_InputHash{'PAYMENTPONO'};
	$::g_PaymentInfo{'CARDTYPE'}		= $::g_InputHash{'PAYMENTCARDTYPE'};
	$::g_PaymentInfo{'CARDNUMBER'}	= $::g_InputHash{'PAYMENTCARDNUMBER'};
	$::g_PaymentInfo{'CARDISSUE'}		= $::g_InputHash{'PAYMENTCARDISSUE'};
	$::g_PaymentInfo{'CARDVV2'}		= $::g_InputHash{'PAYMENTCARDVV2'};
	$::g_PaymentInfo{'EXPMONTH'}		= $::g_InputHash{'PAYMENTEXPMONTH'};
	$::g_PaymentInfo{'EXPYEAR'}		= $::g_InputHash{'PAYMENTEXPYEAR'};
	$::g_PaymentInfo{'STARTMONTH'}	= $::g_InputHash{'PAYMENTSTARTMONTH'};
	$::g_PaymentInfo{'STARTYEAR'}		= $::g_InputHash{'PAYMENTSTARTYEAR'};
	#
	# clean up the input
	#
	ACTINIC::TrimHashEntries(\%::g_PaymentInfo);
	#
	# validate field input
	#
	my ($sError);
	if (!$bActuallyValidate)
		{
		return ($sError);
		}
	#
	# if the cart total is not zero then there must be a valid payment method defined
	# Read the Cart
	#
	my @Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return ($Response[1]);							# error so return error message
		}
	my $pCartObject = $Response[2];
	my $pCartList = $pCartObject->GetCartList();
	#
	# Check the order value
	#
	my (@SummaryResponse) = $pCartObject->SummarizeOrder($::FALSE);	# get the real order total
	if (($SummaryResponse[6] == 0) ||				# zero cart or
		 (!$$::g_pSetupBlob{'PRICES_DISPLAYED'}))	# no prices displayed so no payment is required
		{
		EnsurePaymentSelection();						# this will make sure a payment method is set
		}
	else
		{
		if (0 == length $::g_PaymentInfo{'METHOD'})	# we must have a payment method
			{
			return(ACTINIC::GetPhrase(-1, 55, ACTINIC::GetPhrase(-1, 152)));
			}
		#
		# Check for valid payment method
		#
		my (@arrMethods, $nMethodID);
		ActinicOrder::GenerateValidPayments(\@arrMethods);			# get valid payments
		#
		# Check if requested method is in the list of valid payment methods
		#
		my ($bFound) = $::FALSE;
		foreach $nMethodID (@arrMethods)
			{														# then record error
			if ($nMethodID == $::g_PaymentInfo{'METHOD'})
				{
				$bFound = $::TRUE;
				last;
				}
			}
		if (!$bFound)
			{
			return (ACTINIC::GetPhrase(-1, 2448, $::g_PaymentInfo{'METHOD'}));
			}
		}
	#
	# validate field requirement status
	#
	my $pMapping =
		{
		'PONO' 			=> 6,
		'USERDEFINED'	=> 7,
		};
	$sError .= CheckInputField(5, $pMapping, \%::g_PaymentInfo, $sFormat);
	#
	# validate credit card fields if they exist
	#
	my ($ePaymentMethod) = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"

	if (defined $::g_InputHash{'PAYMENTCARDTYPE'} &&	# if we have user input for credit card fields
		$ePaymentMethod == $::PAYMENT_CREDIT_CARD &&		# and they paid with a CC and
		!$$::g_pSetupBlob{USE_SHARED_SSL} &&				# but SharedSSL and
		!$$::g_pSetupBlob{USE_DH} )							# java is not used
		{
		#
		# validation rules
		#
		# CARDTYPE - required
		# CARDNUMBER - required and checksum
		# CARDISSUE - required? (depends are card type) and 1-255
		# EXPMONTH - required and combined with EXPYEAR must be > this month
		# EXPYEAR - required
		# STARTMONTH - required? (depends are card type) and combined with STARTYEAR must be <= this month
		# STARTYEAR - required? (depends are card type)
		#

		if ($::g_PaymentInfo{'CARDTYPE'} eq "")		# the card type is required
			{
			$sError .= ACTINIC::GetRequiredMessage(5, 1);
			}
		#
		# locate the information for the card in question
		#
		my ($nIndex, $sCCID, $bFound);
		$bFound = $::FALSE;
		for ($nIndex = 0; $nIndex < 12; $nIndex++) # search for the selected card in the stack
			{
			$sCCID = sprintf('CC%d', $nIndex);		# format the card key name

			if ($$::g_pSetupBlob{$sCCID} eq
				 $::g_PaymentInfo{'CARDTYPE'})			# if this was the card of interest, use it
				{
				$bFound = $::TRUE;							# note that the card was found
				last;											# break out
				}
			}
		if (!$bFound)										# if the matching card was found, report the error
			{
			$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(5, 1) .
				ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) .
				ACTINIC::GetPhrase(-1, 107, $::g_PaymentInfo{'CARDTYPE'}) . "<BR>\n"
			}

		#
		# check the credit card number
		#
		my ($nNumber) = $::g_PaymentInfo{'CARDNUMBER'};
		$nNumber =~ s/\s//g;								# remove any white space
		$nNumber =~ s/-//g;								# remove any dashes
		if ($nNumber eq "")								# the card number is required
			{
			$sError .= ACTINIC::GetRequiredMessage(5, 2);
			}
		if ($nNumber =~ /[^0-9]/)						# the card number should only contain numbers
			{
			$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(5, 2) .
				ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) .
				ACTINIC::GetPhrase(-1, 108) . "<BR>\n"
			}

		my ($nCheckSum, $nDigitCount) = (0, 0);
		my ($nDigit, $nCheck);
	   for($nIndex = (length $nNumber) - 1; $nIndex >= 0; $nIndex--)
	      {
	      $nDigit = substr($nNumber, $nIndex, 1); # get this digit

	      $nCheck = (1 + $nDigitCount++ % 2) *	# calculate the checksum
				$nDigit;

	      if ( $nCheck >= 10)
	      	{
	      	$nCheck++;
	      	}

	      $nCheckSum += $nCheck;
	      }

		if (($nCheckSum % 10) != 0)					# if the checksum failed
			{
			$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(5, 2) .
				ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) .
				ACTINIC::GetPhrase(-1, 109) . "<BR>\n"
			}

		#
		# validate the issue number
		#
		if ($$::g_pSetupBlob{$sCCID . '_ISSUENUMBERFLAG'})	# this credit card requires an issue number
			{
			if ($::g_PaymentInfo{'CARDISSUE'} eq "" ||	# the issue number must exist and be between 1-255
				 $::g_PaymentInfo{'CARDISSUE'} < 0 ||
				 $::g_PaymentInfo{'CARDISSUE'} > 255)
				{
				$sError .= ACTINIC::GetPhrase(-1, 110, ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) .
							  ACTINIC::GetPhrase(5, 5) . ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970), $::g_PaymentInfo{'CARDTYPE'}) . "<BR>\n"
				}
			}
		else													# the issue number is not required, make sure it is blank
			{
			$::g_PaymentInfo{'CARDISSUE'} = "";
			}
		#
		# validate the CVV2 number
		#
		if ($$::g_pSetupBlob{$sCCID . '_CVV2FLAG'})	# this credit card requires a CVV2 number
			{
			#
			# Check the length and content of CVV2 data
			# It must only contain the digits 0 to 9 and
			# must be exactly n characters long where n is the number
			# of digits required for the CVV2 for the selected card type
			#
			my $nLength = $$::g_pSetupBlob{$sCCID . '_CVV2DIGITS'};
			if ($::g_PaymentInfo{'CARDVV2'} !~ /^[0-9]{$nLength,$nLength}$/)
				{
				$sError .= ACTINIC::GetPhrase(-1, 560) . "<BR>\n"
				}
			}
		else													# the issue number is not required, make sure it is blank
			{
			$::g_PaymentInfo{'CARDVV2'} = "";
			}
		#
		# validate the start date
		#
		my @listCurrentTime = localtime(time);		# platform independent time
		my $nMonth = $listCurrentTime[$::TIME_MONTH];
		my $nYear = $listCurrentTime[$::TIME_YEAR];
		$nMonth++;											# make month 1 based
		$nYear += 1900;									# make year AD based
		if ($$::g_pSetupBlob{$sCCID . '_STARTDATEFLAG'})	# this credit card requires a start date
			{
			if (($::g_PaymentInfo{'STARTMONTH'} !~ /^\d{2}$/) ||	# if the start month is not 2 digits
				 ($::g_PaymentInfo{'STARTYEAR'} !~ /^\d{4}$/))	# or the start year is not 4 digits
				{
				$sError .= ACTINIC::GetRequiredMessage(5, 3); # point out that they are required
				$::g_PaymentInfo{'STARTMONTH'} = "";# clear the month
				$::g_PaymentInfo{'STARTYEAR'} = "";	# and year to ensure correct redisplay
				}

			if ($::g_PaymentInfo{'STARTYEAR'} == $nYear && # if the card has not started yet
				 $::g_PaymentInfo{'STARTMONTH'} > $nMonth)
				{
				$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(5, 3) .
					ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) .
					ACTINIC::GetPhrase(-1, 111) . "<BR>\n"
				}
			}
		else													# the start date is not required, make sure it is blank
			{
			$::g_PaymentInfo{'STARTMONTH'} = "";
			$::g_PaymentInfo{'STARTYEAR'} = "";
			}
		#
		# validate the expiration date
		#
		if (($::g_PaymentInfo{'EXPMONTH'} !~ /^\d{2}$/) ||	# if the expiration month is not 2 digits
			 ($::g_PaymentInfo{'EXPYEAR'} !~ /^\d{4}$/))	# or the expiration year is not 4 digits
			{
			$sError .= ACTINIC::GetRequiredMessage(5, 4); 	# point out that they are required
			$::g_PaymentInfo{'EXPMONTH'} = "";		# clear the month
			$::g_PaymentInfo{'EXPYEAR'} = "";		# and year to ensure correct redisplay
			}

		if ($::g_PaymentInfo{'EXPYEAR'} == $nYear && # if the card has expired
			 $::g_PaymentInfo{'EXPMONTH'} < $nMonth)
			{
			$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(5, 4) .
				ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) .
				ACTINIC::GetPhrase(-1, 112) . "<BR>\n"
			}
		#
		# If the start date is used, make sure it is before the expiration date.  This is in-line with the desktop app.
		# Note that the prompt is EC v6+, so we need to fall back to a default English prompt if it is not defined in
		# the prompt table.
		#
		if ($$::g_pSetupBlob{$sCCID . '_STARTDATEFLAG'})	# this credit card requires a start date
			{
			if ($::g_PaymentInfo{'EXPYEAR'} < $::g_PaymentInfo{'STARTYEAR'} ||    # the card expires in the year before it starts or
				 ($::g_PaymentInfo{'EXPYEAR'} == $::g_PaymentInfo{'STARTYEAR'} &&  # the card expires in the same year as it starts and
				  $::g_PaymentInfo{'EXPMONTH'} <= $::g_PaymentInfo{'STARTMONTH'})) # the card expires in the same month it starts or before
				{
				$sError .= ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(5, 4) .
					ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970) .
						ACTINIC::GetPhrase(-1, 561) . "<BR>\n"	# error out
				}
			}
		}
	else
		{
		$::g_PaymentInfo{'CARDTYPE'}		= "";
		$::g_PaymentInfo{'CARDNUMBER'}	= "";
		$::g_PaymentInfo{'CARDISSUE'}		= "";
		$::g_PaymentInfo{'CARDVV2'}		= "";
		$::g_PaymentInfo{'EXPMONTH'}		= "";
		$::g_PaymentInfo{'EXPYEAR'}		= "";
		$::g_PaymentInfo{'STARTMONTH'}	= "";
		$::g_PaymentInfo{'STARTYEAR'}		= "";
		}
	if ($sFormat ne 'text')
		{
		return ActinicOrder::FormatCheckoutInputError(ACTINIC::GetPhrase(-1, 152), $sError);
		}
	elsif ($sError ne '')
		{
		return sprintf("\n%s\n%s", ACTINIC::GetPhrase(-1, 152), $sError);
		}
	return '';
	}

#######################################################
#
# ValidateSignature - validate the B2B order signature
#
# Params:	0 - $::TRUE if the data should be validated
#
# Returns:	0 - error message if any
#
# Affectes: $::g_sSignature
#
#######################################################

sub ValidateSignature
	{
	$::g_sSignature = $::g_InputHash{SIGNATURE};

	if ($::g_sSignature ne '')							# if the signature exists
		{
		$::g_sSignature =~ /^([a-fA-F0-9]{32})$/;	# validate the input
		$::g_sSignature = $1;							# untaint it
		}

	return (undef);
	}

#######################################################
#
# DisplayPage - display the specified page with the
#	optional error message
#
# Params:	0 - error message if any
#				1 - page number to display
#				2 - advance direction ($::FORWARD, $::BACKWARD)
#
# Returns:	0 - status
#				1 - error message
#				2 - HTML
#				3 - contact details cookie
#
#######################################################

sub DisplayPage
	{
	if ($#_ != 2)
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'DisplayPage'), 0, 0);
		}
	my (%VariableTable, $sDetailCookie);
	my ($sError, $nPageNumber, $eDirection) = @_;
	my (@Response, $sPath);
	$sPath = ACTINIC::GetPath();						# get the path to the web site
	#
	# Read the shopping cart - this has to be done before the call to ProcessPage since
	# process page kills the cart when receipt is called.
	#
	my ($pCartList);
	my $sMessage;
	my $bReDisplayReceipt = $::FALSE;
	if($::g_InputHash{'ACTION'} !~ m/^AUTHORIZE_(\d+)$/i)
		{
		@Response = $::Session->GetCartObject();
		#
		# Give an user friendly message when the cart is empty
		#
		if ($Response[0] == $::EOF)
			{
			#
			# If it is a recordorder from SharedSSL or JAVA page
			# then return the plain error message and exit
			# Otherwise put up a bounce page.
			#
			if ($::g_InputHash{'ACTION'} =~ m/RECORDORDER/i)
				{
				if ($$::g_pSetupBlob{USE_DH})				# is it the JAVA applet?
					{												# pass plain text message
					ACTINIC::PrintText("0" . ACTINIC::GetPhrase(-1, 2040));
					}
				else												# is it SharedSSL
					{												# send HTML formatted message
					ACTINIC::PrintText("0" . ACTINIC::GetPhrase(-1, 1282));
					}
				#
				# processing is complete at this point
				#
				exit;
				}
			#
			# The old implementation didn't allow the refresh on the receipt page.
			# It was requested by several reasons (mostly related to NN)
			# See: cix:actinic_catlog/bugs_details5:2881
			#
			# We have applied a hack here to allow receipt redisplay. The cart
			# and checkout files are not removed when the receipt is displayed
			# but renamed to *.cart.done (or *.chk.done) files. These files will
			# be removed after 2 hours by the garbage collector.
			# (See: related ActinicOrder functions as ClearFiles and ClearOldFiles)
			#
			# We try to detect the receipt redisplay situation here and restore
			# the cart and the checkout file content from the .done files.
			# It is only done when the Phase and Pagenumbers indicate that
			# the receipt is being redisplayed.
			#
			# Monday, October 08, 2001 - ZMagyar
			#
			my ($sPhaseList) = $$::g_pPhaseList{$nPageNumber};
			my (@Phases) = split (//, $sPhaseList);
			#
			# Check if it is the receipt phase and try to display
			# the receipt again
			#
			if (($nPageNumber == 3 && $Phases[0] == $::COMPLETEPHASE) ||
				 ($nPageNumber == 4 && $Phases[0] == $::RECEIPTPHASE))
				{
				#
				# Use the old checkout info
				#
				@Response = $::Session->RestoreCheckoutInfo();
				if ($Response[0] != $::SUCCESS)
					{
					return (@Response);
					}
				my ($Status, $Message, $pBillContact, $pShipContact, $pShipInfo, $pTaxInfo, $pGeneralInfo, $pPaymentInfo, $pLocationInfo) = @Response;
				%::g_BillContact = %$pBillContact;					# copy the hashes to global tables
				%::g_ShipContact = %$pShipContact;
				%::g_ShipInfo		= %$pShipInfo;
				%::g_TaxInfo		= %$pTaxInfo;
				%::g_GeneralInfo = %$pGeneralInfo;
				%::g_PaymentInfo = %$pPaymentInfo;
				%::g_LocationInfo = %$pLocationInfo;
				#
				# Try to read the cart again
				#
				@Response = $::Session->GetCartObject($::TRUE); # read the shopping cart again
				if ($Response[0] == $::SUCCESS)
					{
					$bReDisplayReceipt = $::TRUE;
					}
				}
			#
			# If we are here and it is not a receipt page redisplay then put up
			# an user friendly message about the empty cart
			#
			if (!$bReDisplayReceipt)
				{
				@Response = ACTINIC::BounceToPageEnhanced(7, ACTINIC::GetPhrase(-1, 1282),
																	$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
																	$::g_sWebSiteUrl,
																	$::g_sContentUrl, $::g_pSetupBlob,
																	$::Session->GetLastShopPage(),
																	\%::g_InputHash,
																	$::FALSE);
				return (@Response);
				}
			}
		my $pCartObject = $Response[2];
		$pCartList = $pCartObject->GetCartList();	 	# read the shopping cart
		#
		# make sure there are no "deleted" items in the cart
		#
		my $nLineCount = CountValidCartItems($pCartList);
		if ($nLineCount != scalar @$pCartList &&
			$::g_bFirstError)
			{
			$::g_bFirstError = $::FALSE;
			$sMessage = "<P>" . ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(-1, 175) . ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970);
			return(DisplayPage($sMessage, $::g_nCurrentSequenceNumber, $eDirection));	# redisplay the incoming page with the error messages
			}
		}
	#
	# Process the phases in this page
	#
	my (@DeleteDelimiters, @KeepDelimiters, $nInc, $status);
	my ($pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $nKeyCount, $pSelectTable);
	if ($bReDisplayReceipt)
		{
		($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters) = DisplayReceiptPhase($::g_PaymentInfo{'ORDERNUMBER'}, $::g_PaymentInfo{METHOD}, $bReDisplayReceipt);
		$nPageNumber = 4;
		}
	else
		{
		$nInc = ($eDirection == $::FORWARD) ? 1 : -1;
		$nKeyCount = 0;
		while ($nKeyCount == 0 &&								# as long as the page is not used
				 $nPageNumber >= 0)							# and the page is a valid number
			{
			my $sTempCookie;
			($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sTempCookie) =
				ProcessPage($nPageNumber);					# process the current page

			$sDetailCookie .= $sTempCookie;				# accumulate the contact detail cookie (just makes sure it isn't overwritten)

			if ($status != $::SUCCESS)						# if an error occured creating the pages, display the previous page
				{													# with the error message
				if ($::g_bFirstError)						# make sure we don't run into recursion problems
					{
					$::g_bFirstError = $::FALSE;
					$sMessage = "<P>" . ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . $sMessage . ACTINIC::GetPhrase(-1, 1975) . ACTINIC::GetPhrase(-1, 1970);
					return(DisplayPage($sMessage, $::g_nCurrentSequenceNumber, $eDirection));	# redisplay the incoming page with the error messages
					}
				else												# unfortunate error that can be recovered
					{
					return($status, $sMessage, 0, undef);
					}
				}
			if ($nPageNumber != 2)
				{
				$nKeyCount = (keys %$pVarTable) + (keys %$pSelectTable);
				}
			else
				{
				$nKeyCount = 1;
				$pVarTable = {};
				}
			$nPageNumber += $nInc;							# try the next/previous page
			}
		$nPageNumber -= $nInc;								# roll back the page number since it was unnecessarily incremented
		#
		# Handle the special case when the back button takes us back to the catalog rather than a previous order page
		#
		if ($nKeyCount == 0)									# we wound back too far (never found a valid page)
			{
			if (length $sError > 0)							# if an error message exists, we still need to display it
				{
				my ($sRefPage) = $::Session->GetLastShopPage();			# find the original referencing page
				#
				# If the vendor requested an unframed checkout and specified a URL, use the given URL for the return
				#
				if ($$::g_pSetupBlob{UNFRAMED_CHECKOUT} &&	# unframed checkout
					 $$::g_pSetupBlob{UNFRAMED_CHECKOUT_URL})	# a URL was supplied
					{
					$sRefPage = $$::g_pSetupBlob{UNFRAMED_CHECKOUT_URL}; # use the given URL
					}

				my @Response = ACTINIC::BounceToPageEnhanced(-1, $sError, ACTINIC::GetPhrase(-1, 25),
					$::g_sWebSiteUrl, $::g_sContentUrl, $::g_pSetupBlob, $sRefPage, \%::g_InputHash);
				if ($Response[0] != $::SUCCESS)
					{
					ACTINIC::ReportError($sError, ACTINIC::GetPath());
					}
				return ($::SUCCESS, '', $Response[2], undef);
				}
			else
				{
				return ($::SUCCESS, "", GetCancelPage(), undef);	# go back to the catalog
				}
			}
		}
	#
	# combine the variable tables - build the total page
	#
	my (@a1, @a2);
	@a1 = %VariableTable;
	@a2 = %$pVarTable;
	push (@a1, @a2);
	%VariableTable = @a1;								# get easier-to-handle copies
	@DeleteDelimiters = @$pDeleteDelimiters;
	@KeepDelimiters = @$pKeepDelimiters;
	#
	# By here, we have all of the phase specific values.  Now generate the generic values.
	#
	if (length $VariableTable{$::VARPREFIX.'ERROR'})
		{
		$sError .= ' ' . $VariableTable{$::VARPREFIX.'ERROR'};	# if it has value already, then append this value to the new one.
		}
	$sError = ACTINIC::GroomError($sError);			# make the error look nice for the HTML
	$VariableTable{$::VARPREFIX.'ERROR'} = $sError; # add the error message to the var list
	$VariableTable{$::VARPREFIX.'SEQUENCE'} = $nPageNumber; # add the sequence number to the var list
	#
	# build the file
	#
	my ($sFileName);
	$sFileName = sprintf('order%2.2d.html', $nPageNumber);
	if ($::g_sOverrideCheckoutFileName)				# this is a hack - allow the special login confirmation page to be displayed.  We are too late in the release cycle to
		{														# think about a proper solution
		$sFileName = $::g_sOverrideCheckoutFileName;	# take the hacked name
		}
	#
	# Now display a summary of the shopping cart - this must be post page-specific formatting
	# since the hidden status of the shipping phases may update the data
	#
	@Response = ActinicOrder::GenerateShoppingCartLines($pCartList, $::FALSE, [], $sFileName);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	@Response = ACTINIC::TemplateFile($sPath.$sFileName, \%VariableTable); # make the substitutions
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	#
	# clean up the links
	#
	my ($sDigest,$sBaseFile) = ACTINIC::CaccGetCookies();
	$sPath = ($sBaseFile) ? $sBaseFile : $::g_sContentUrl;
	@Response = ACTINIC::MakeLinksAbsolute($Response[2], $::g_sWebSiteUrl, $sPath);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my ($sHTML) = $Response[2];
	#
	# remove unused form blocks
	#
	my ($sDelimiter);
	foreach $sDelimiter (@DeleteDelimiters)			# for each delimited section that is to be deleted
		{
		$sHTML =~ s/$::DELPREFIX$sDelimiter(.*?)$::DELPREFIX$sDelimiter//gs;	# delete it (/s removes the \n limitation of .)
		}
	#
	# remove unused delimiters
	#
	foreach $sDelimiter (@KeepDelimiters)				# for each delimiter that is not used
		{
		$sHTML =~ s/$::DELPREFIX$sDelimiter//gs;			# delete it
		}
	#
	# perform special handling of <SELECT> form field defaults since it is too difficult
	#	to do with the standard TemplateFile architecture
	#
	my ($sSelectName, $sDefaultOption);
	while ( ($sSelectName, $sDefaultOption) = each %$pSelectTable)
		{
		$sHTML =~ s/(<\s*SELECT[^>]+?NAME\s*=\s*("|')?$sSelectName.+?)<OPTION\s+VALUE\s*=\s*("|')?$sDefaultOption("|')?\s*>/$1<OPTION SELECTED VALUE="$sDefaultOption">/is;
		if ($1 eq "")										# if the defailt option was not found
			{
			$sDefaultOption = "---";					# try 'none of the above'
			$sHTML =~ s/(<\s*SELECT[^>]+?NAME\s*=\s*("|')?$sSelectName.+?)<OPTION\s+VALUE\s*=\s*("|')?$sDefaultOption("|')?\s*>/$1<OPTION SELECTED VALUE="$sDefaultOption">/is;
			}
		}
	return ($::SUCCESS, "", $sHTML, $sDetailCookie);
	}

#######################################################
#
# ProcessPage - process the page specific variable
#	lists
#
# Params:	0 - page number
#
# Returns:	0 - status
#				1 - error message if any
#				2 - a pointer to the substitution variable table
#				3 - a pointer to the list of delimiters of areas to delete
#				4 - a pointer to the list of delimiters of areas to keep
#				5 - a pointer to the list of special "SELECT" variable table
#				6 - the contact detail cookie if any
#
# Affects:	%s_LargeVariableTable, @s_LargeDeleteDelimiters,
#				@s_LargeKeepDelimiters, %s_LargeSelectTable
#
#######################################################

sub ProcessPage
	{
	if ($#_ != 0)
		{
		return($::SUCCESS, ACTINIC::GetPhrase(-1, 12, 'ProcessPage'), undef, undef, undef, undef, undef);
		}
	my ($nPageNumber) = $_[0];
	my @scratch = keys %$::g_pPhaseList;
	my $nPhaseCount = $#scratch - 1;
	my $sDetailCookie;
	if ($nPageNumber > $nPhaseCount)
		{
		return($::SUCCESS, ACTINIC::GetPhrase(-1, 146, $nPageNumber, $nPhaseCount), undef, undef, undef, undef, $sDetailCookie);
		}
	undef %::s_LargeVariableTable;
	@::s_LargeDeleteDelimiters = ();
	@::s_LargeKeepDelimiters = ();
	undef %::s_LargeSelectTable;
	#
	# get the phase list for this page
	#
	my ($sPhaseList) = $$::g_pPhaseList{$nPageNumber};
	#
	# process each phase in the current block
	#
	my ($pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable);
	$pVarTable = {};
	my (@Phases) = split (//, $sPhaseList);
	my ($nPhase, $status, $sMessage);
	foreach $nPhase (@Phases)
		{
		if ($nPhase == $::BILLCONTACTPHASE)
			{
			($pVarTable, $pDeleteDelimiters, $pKeepDelimiters) = DisplayBillContactPhase();
			if (!defined $pSelectTable)
				{
				$pSelectTable = {};
				}
			ActinicOrder::MapLocationSelections($pSelectTable);
			}
		elsif ($nPhase == $::SHIPCONTACTPHASE)
			{
			($pVarTable, $pDeleteDelimiters, $pKeepDelimiters) = DisplayShipContactPhase();
			}
		elsif ($nPhase == $::SHIPCHARGEPHASE)
			{
			($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters) =
				ActinicOrder::DisplayShipChargePhase();
			if ($status != $::SUCCESS)						# on error - bail
				{
				#
				# since displaying the shipping charge phase failed, unselect the default
				# country since it may change.  It may have been erroneously entered.
				#
				my $sDeliveryCountry = ACTINIC::GetCountryName($::g_LocationInfo{DELIVERY_COUNTRY_CODE});
				if ($::g_BillContact{COUNTRY} eq $sDeliveryCountry && # if the bill contact country had been defaulted to the one selected in the preliminary phase
					 !$$::g_pLocationList{EXPECT_INVOICE})		 # and the invoice address is guessed to be in the same location as the delivery address
					{
					undef $::g_BillContact{COUNTRY};	# unselect it
					}
				if ($::g_ShipContact{COUNTRY} eq $sDeliveryCountry) # same for the destination country
					{
					undef $::g_ShipContact{COUNTRY};
					}
				return ($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
				}
			UpdateCheckoutRecord();						# update the checkout record since the plugin is free to change it
			}
		elsif ($nPhase == $::TAXCHARGEPHASE)
			{
			($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters) = ActinicOrder::DisplayTaxPhase();
			if ($status != $::SUCCESS)						# on error - bail
				{
				#
				# since displaying the tax charge phase failed, unselect the default
				# country since it may change.  It may have been erroneously entered.
				#
				my $sInvoiceCountry = ACTINIC::GetCountryName($::g_LocationInfo{INVOICE_COUNTRY_CODE});
				if ($::g_BillContact{COUNTRY} eq $sInvoiceCountry) # if the bill contact country had been defaulted to the one selected in the preliminary phase
					{
					undef $::g_BillContact{COUNTRY};	# unselect it
					}
				if ($::g_ShipContact{COUNTRY} eq $sInvoiceCountry && # same for the destination country
					 !$$::g_pLocationList{EXPECT_DELIVERY})			# but only process if the shipping address is guessed based on the invoice address
					{
					undef $::g_ShipContact{COUNTRY};
					}
				#
				# taxes can be based on either address, so check the delivery address as well (just in case)
				#
				my $sDeliveryCountry = ACTINIC::GetCountryName($::g_LocationInfo{DELIVERY_COUNTRY_CODE});
				if ($::g_BillContact{COUNTRY} eq $sDeliveryCountry && # if the bill contact country had been defaulted to the one selected in the preliminary phase
					 !$$::g_pLocationList{EXPECT_INVOICE})		 # and the invoice address is guessed to be in the same location as the delivery address
					{
					undef $::g_BillContact{COUNTRY};	# unselect it
					}
				if ($::g_ShipContact{COUNTRY} eq $sDeliveryCountry) # same for the destination country
					{
					undef $::g_ShipContact{COUNTRY};
					}
				return ($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
				}
			UpdateCheckoutRecord();						# update the checkout record since the plugin is free to change it
			}
		elsif ($nPhase == $::COMPLETEPHASE)
			{
			if (length $::g_PaymentInfo{'METHOD'} == 0) # if the payment method is undefined at this point
				{													# it is because the payment information was hidden
				EnsurePaymentSelection();
				}
			#
			# Read the Cart
			#
			my @Response = $::Session->GetCartObject();
			if ($Response[0] != $::SUCCESS)					# general error
				{
				return (@Response);								# error so return empty string
				}
			my $pCartObject = $Response[2];
			my $pCartList = $pCartObject->GetCartList();
			#
			# Check the order value
			#
			my (@SummaryResponse) = $pCartObject->SummarizeOrder($::FALSE);	# get the real order total
			my ($ePaymentMethod);

			if ($SummaryResponse[6] == 0)								# the order summary is zero
				{
				$ePaymentMethod = -1;									# set it to skip the CC validation
				}
			else																# the order value is not zero
				{																# so check CC if necessary
				$ePaymentMethod= ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"
				}
			#
			# complete the order based on the payment method
			#
			if ($ePaymentMethod == $::PAYMENT_CREDIT_CARD &&	# if they are paying with a credit card and
				 $$::g_pSetupBlob{USE_DH})								# Java encryption is enabled
				{																# use java encryption
				($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters) = DisplayPageWithOrderDetails($::eApplet);
				if ($status != $::SUCCESS)						# on error - bail
					{
					return ($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
					}
				}
			#
			# this is an on-line credit card transaction
			#
			elsif ($$::g_pPaymentList{$ePaymentMethod}{PAYMENT_TYPE})						# we are in on-line mode
				{
				#
				# call the plug in
				#
				my (@Response) = CallOCCPlugIn();
				#
				# of the CC was accepted, there is no UI to display, so continue to the receipt
				#
				if ($Response[0] == $::ACCEPTED)		# card was accepted

					{
					@Response = CompleteOrder();		# record the order
					if ($Response[0] != $::SUCCESS)
						{
						return(@Response);
						}
					#
					# this call does not return any variables.  this causes the next page to be loaded (the receipt)
					#
					undef %::s_VariableTable;
					undef @::s_DeleteDelimiters;
					undef @::s_KeepDelimiters;
					($pVarTable, $pDeleteDelimiters, $pKeepDelimiters) =
						(\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
					}
				#
				# the credit card acceptance is pending, record the order and display the plug-in UI so
				#	it can complete the transaction
				#
				elsif ($Response[0] == $::PENDING)
					{
					my ($sHTML) = $Response[2];
					@Response = CompleteOrder();		# record the order
					if ($Response[0] != $::SUCCESS)
						{
						return (@Response);
						}
					#
					# display the plug-in UI to complete the transaction
					#
					ACTINIC::SaveSessionAndPrintPage($sHTML, undef, $::FALSE);
					exit;
					}
				#
				# credit card rejected
				#
				elsif ($Response[0] == $::REJECTED)
					{
					#
					# display the plug-in error page
					#
					ACTINIC::SaveSessionAndPrintPage($Response[2], undef, $::FALSE);
					exit;
					}
				else
					{
					return (@Response);
					}
				}
			elsif ($ePaymentMethod == $::PAYMENT_CREDIT_CARD &&	# if they are paying with a credit card and
					 $$::g_pSetupBlob{USE_SHARED_SSL})		# shared ssl mode
				{
				#
				# generate the page to forward all of the order information to the remote site
				#
				($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters) = DisplayPageWithOrderDetails($::eSharedSSL);
				if ($status != $::SUCCESS)						# on error - bail
					{
					return ($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
					}
				#
				# This is a hack, but build the HTML, print and exit - don't return
				#
				my @Response = ACTINIC::TemplateFile(ACTINIC::GetPath() . 'sharedssllink.html', $pVarTable); # make the substitutions
				if ($Response[0] != $::SUCCESS)
					{
					return (@Response);
					}
				#
				# clean up the links
				#
				my ($sDigest,$sBaseFile) = ACTINIC::CaccGetCookies();
				my $sPath = ($sBaseFile) ? $sBaseFile : $::g_sContentUrl;
				@Response = ACTINIC::MakeLinksAbsolute($Response[2], $::g_sWebSiteUrl, $sPath);
				if ($Response[0] != $::SUCCESS)
					{
					return (@Response);
					}
				my ($sHTML) = $Response[2];
				#
				# remove unused form blocks
				#
				my ($sDelimiter);
				foreach $sDelimiter (@$pDeleteDelimiters)			# for each delimited section that is to be deleted
					{
					$sHTML =~ s/$::DELPREFIX$sDelimiter(.*?)$::DELPREFIX$sDelimiter//gs;	# delete it (/s removes the \n limitation of .)
					}
				#
				# remove unused delimiters
				#
				foreach $sDelimiter (@$pKeepDelimiters)				# for each delimiter that is not used
					{
					$sHTML =~ s/$::DELPREFIX$sDelimiter//gs;			# delete it
					}
				#
				# display the plug-in UI to complete the transaction
				#
				ACTINIC::SaveSessionAndPrintPage($sHTML, undef, $::FALSE);
				exit;
				}
			#
			# If this is a B2B customer using pay on account or invoice - present the signature page
			#
			elsif ($ACTINIC::B2B->Get('UserDigest') && # if a user is logged in and
					 ($ePaymentMethod == $::PAYMENT_ON_ACCOUNT || # the payment method is pay on account or
					  $ePaymentMethod == $::PAYMENT_INVOICE))	# the payment method is invoice
				{
				#
				# First we have to calculate the MD5 of the vital order details.  The vital order details are the following fields as strings concatenated together:
				#
				#  Invoice Name
				#  Invoice First Name
				#  Invoice Last Name
				#  Invoice Company
				#  Invoice Address Line 1
				#  Invoice Address Line 2
				#  Invoice Address Line 3
				#  Invoice Address Line 4
				#  Invoice Postal Code
				#	Invoice Country
				#  Invoice Phone
				#  Invoice Mobile
				#  Invoice Email
				#  Delivery Name
				#  Delivery First Name
				#  Delivery Last Name
				#  Delivery Company
				#  Delivery Address Line 1
				#  Delivery Address Line 2
				#  Delivery Address Line 3
				#  Delivery Address Line 4
				#  Delivery Postal Code
				#	Delivery Country
				#  Delivery Phone
				#  Delivery Mobile
				#  Delivery Email
				#  Order total (in Actinic internal format printed to a string)
				#  Line item 1 product reference
				#  Line item 1 quantity (printed to a string)
				#  Line item 2 product reference
				#  Line item 2 quantity (printed to a string)
				#
				# First read the cart and get an order summary
				#
				my ($Status, $Message, @Response);
				@Response = $::Session->GetCartObject();
				if ($Response[0] != $::SUCCESS)					# general error
					{
					return (@Response);								# error so return empty string
					}
				my $pCartObject = $Response[2];
				my $pCartList = $pCartObject->GetCartList();

				my (@SummaryResponse, $nTotal);
				@SummaryResponse = $pCartObject->SummarizeOrder($::FALSE);	# get the real order total
				if ($SummaryResponse[0] != $::SUCCESS)			# if we were successful
					{
					return (@SummaryResponse);
					}
				$nTotal = $SummaryResponse[6];
				#
				# Get the basic order detail.  Then add the line items
				#
				my $sVitalOrderDetails =
					$::g_BillContact{NAME} .
					$::g_BillContact{FIRSTNAME} .
					$::g_BillContact{LASTNAME} .
					$::g_BillContact{COMPANY} .
					$::g_BillContact{ADDRESS1} .
					$::g_BillContact{ADDRESS2} .
					$::g_BillContact{ADDRESS3} .
					$::g_BillContact{ADDRESS4} .
					$::g_BillContact{POSTALCODE} .
					$::g_BillContact{COUNTRY} .
					$::g_BillContact{PHONE} .
					$::g_BillContact{MOBILE} .
					$::g_BillContact{EMAIL} .
					$::g_ShipContact{NAME} .
					$::g_ShipContact{FIRSTNAME} .
					$::g_ShipContact{LASTNAME} .
					$::g_ShipContact{COMPANY} .
					$::g_ShipContact{ADDRESS1} .
					$::g_ShipContact{ADDRESS2} .
					$::g_ShipContact{ADDRESS3} .
					$::g_ShipContact{ADDRESS4} .
					$::g_ShipContact{POSTALCODE} .
					$::g_ShipContact{COUNTRY} .
					$::g_ShipContact{PHONE} .
					$::g_ShipContact{MOBILE} .
					$::g_ShipContact{EMAIL} .
					$nTotal;
				#
				# Do the line item work
				#
				my $pCartItem;
				foreach $pCartItem (@$pCartList)		# for each item in the cart
					{
					$sVitalOrderDetails .= $pCartItem->{PRODUCT_REFERENCE} . $pCartItem->{QUANTITY};
					#
					# Locate the section blob
					#
					my ($sSectionBlobName);
					($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($pCartItem->{SID}); # retrieve the blob name
					if ($Status == $::FAILURE)
						{
						return ($Status, $Message);
						}
					#
					# locate this product's object
					#
					@Response = ACTINIC::GetProduct($pCartItem->{PRODUCT_REFERENCE},  $sSectionBlobName,
															  ACTINIC::GetPath());											# get this product object
					my $pProduct;
					($Status, $Message, $pProduct) = @Response;
					if ($Status == $::NOTFOUND)					# the item has been removed from the catalog
						{
						next;
						}
					if ($Status != $::SUCCESS)
						{
						return (@Response);
						}
					#
					# Check if there are any variants
					#
					my $VariantList;
					if( $pProduct->{COMPONENTS} )		# If the product has components (or attributes)
						{
						my $sKey;
						foreach $sKey (keys %$pCartItem)	# Search for component information in current item
							{
							if( $sKey =~ /^COMPONENT\_/ )	# Component info key is 'COMPONENT_index'
								{
								$VariantList->[$'] = $pCartItem->{$sKey};	# Use index for VariantList and store info
								}
							}
						}

					my %Component;							  # Add one line for each component
					my $pComponent;
					foreach $pComponent (@{$pProduct->{COMPONENTS}})
						{
						@Response = ActinicOrder::FindComponent($pComponent,$VariantList);	# Find selected variants
						($Status, %Component) = @Response;
						if ($Status == $::SUCCESS and $Component{quantity} > 0 )	# Only if this component was selected
							{
							my $sProdName;
							if( !$pComponent->[0] && # No component name
								 $Component{text} ) # Just attributes
								{
								$Component{quantity} = 0; # Quantity=0 for attributes
								}
							#
							# Add the component to the signature
							#
							$sVitalOrderDetails .= $Component{code} . ($pCartItem->{QUANTITY} * $Component{quantity});
							}
						}
					}
				#
				# Now hash the order details
				#
				eval
					{
#&					ActinicProfiler::StartLoadRuntime('Digest::MD5');
					require Digest::MD5;								# Try loading MD5
#&					ActinicProfiler::EndLoadRuntime('Digest::MD5');
					import Digest::MD5 'md5_hex';
					};
				if ($@)
					{
#&					ActinicProfiler::StartLoadRuntime('DigestPerlMD5');
					require <Actinic:Variable Name="DigestPerlMD5"/>;
#&					ActinicProfiler::EndLoadRuntime('DigestPerlMD5');
					import Digest::Perl::MD5 'md5_hex';			# Use Perl version if not found
					}
				my $sMD5Vitals = md5_hex($sVitalOrderDetails);
				#
				# Get the username
				#
				my $sUser = $ACTINIC::B2B->Get('UserName');
				#
				# Create the user identifier
				#
				my $sMD5User = md5_hex($ACTINIC::B2B->Get('UserName') . $ACTINIC::B2B->Get('UserDigest'));
				#
				# Clear out our scratch space
				#
				undef %::s_VariableTable;
				undef @::s_DeleteDelimiters;
				undef @::s_KeepDelimiters;
				#
				# Create the appropriate variables for the HTML substitution
				#
				$::s_VariableTable{$::VARPREFIX.'USER'} = $sUser;
				$::s_VariableTable{$::VARPREFIX.'VITAL'} = $sMD5Vitals;
				$::s_VariableTable{$::VARPREFIX.'ID'} = $sMD5User;

				($pVarTable, $pDeleteDelimiters, $pKeepDelimiters) =
					(\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
				#
				# Note the special checkout page filename.  This is a hack, but setting this value overrides the order%d.html filename
				# in the function that does the actual HTML generation.
				#
				$::g_sOverrideCheckoutFileName = 'signature.html';
				}
			else												# SSL encryption or non-CC order
				{
				#
				# Check if paypalpro is used and do the call for that if so
				#
				if ($ePaymentMethod == $::PAYMENT_CREDIT_CARD &&
					defined $$::g_pPaymentList{$::PAYMENT_PAYPAL_PRO})
					{
					#
					# Make sure we got the paypal stuff
					#
					EvaluatePaypalPro();
					#
					# The paypal object is defined in the plugin script so it
					# should be available by now.
					# Create an instance here and try to invoke direct payment
					#
					my $oPaypal = new ActinicPaypalConnection();
					my $nAmount = ActinicOrder::GetOrderTotal();
					my @Response = $oPaypal->DoDirectPayment(
						$nAmount,
						$$::g_pCatalogBlob{'SINTLSYMBOLS'},
						$::g_PaymentInfo{'CARDNUMBER'},
						$::g_PaymentInfo{'CARDVV2'},
						$::g_PaymentInfo{'CARDISSUE'},
						$::g_PaymentInfo{'STARTYEAR'},
						$::g_PaymentInfo{'STARTMONTH'},
						$::g_PaymentInfo{'EXPYEAR'},
						$::g_PaymentInfo{'EXPMONTH'},
						GetPPAddressDetails()
						);
					if ($Response[0] != $::SUCCESS)					# paypal request failed
						{
						return ($Response[0], ACTINIC::GetPhrase(-1, 2450, $Response[1]), $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
						}
					#
					# Now record the payment
					#
					@Response = RecordPaypalOrder($oPaypal);
					if ($Response[0] != $::SUCCESS)
						{
						return ($Response[0], $Response[1], $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
						}
					}
				else
					{
					my (@Response) = CompleteOrder();
					if ($Response[0] != $::SUCCESS)
						{
						return (@Response);
						}
					}
				#
				# this call does not return any variables.  this causes the next page to be loaded (the receipt)
				#
				undef %::s_VariableTable;
				undef @::s_DeleteDelimiters;
				undef @::s_KeepDelimiters;
				($pVarTable, $pDeleteDelimiters, $pKeepDelimiters) =
					(\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
				#
				# set the payment flag, so the DD link can be displayed
				#
				$::Session->PaymentMade();
				}
			}
		elsif ($nPhase == $::RECEIPTPHASE)					# here when order is done
			{
			#
			# Get the payment method
			#
			my ($ePaymentMethod);
			#
			# with Java encryption, this field is undefined - For PSPs that
			# use an authorization callback the ACTION is AUTHORIZE_<PSP ID>
			#
			if($::g_InputHash{'ACTION'} =~ m/^AUTHORIZE_(\d+)$/i)
				{
				$ePaymentMethod = $1; # the : is to help parsing
				}
			elsif (length $::g_PaymentInfo{METHOD} == 0)
				{
				$ePaymentMethod = $::PAYMENT_CREDIT_CARD; # the : is to help parsing
				}
			else
				{
				($ePaymentMethod) = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{METHOD}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"
				}
			#
			# Signed orders from buyers are not saved until this point
			#
			if ($ACTINIC::B2B->Get('UserDigest') && # if a user is logged in and
				 ($ePaymentMethod == $::PAYMENT_ON_ACCOUNT || # the payment method is pay on account or
				  $ePaymentMethod == $::PAYMENT_INVOICE))	# the payment method is invoice
				{
				my (@Response) = CompleteOrder();
				if ($Response[0] != $::SUCCESS)
					{
					return (@Response);
					}
				}
			#
			# If this is a OCC response, record the authorization - we no longer display the reciept at this point
			#
			if ($$::g_pPaymentList{$ePaymentMethod}{PAYMENT_TYPE} &&
				 $::g_InputHash{'ACTION'} =~ m/^AUTHORIZE/i)
				{
	 			LogData("AUTHORIZE:\n$::g_OriginalInputData");
				#
				# Check if the PSP requires post processing
				#
				if (defined $::g_InputHash{'ACT_POSTPROCESS'})
					{
					#
					# Let the post processor do all the processing
					#
					# Get the PSP payment method details
					#
					my ($sFilename, $pPaymentMethodHash);
					#
					# Get the payment method hash
					#
					$pPaymentMethodHash = $$::g_pPaymentList{$ePaymentMethod};
					#
					# Get the bounce script name
					#
					$sFilename = $$pPaymentMethodHash{POST_PROCESS};
					#
					# Call bounce script and process its result
					#
					my (@Response) = CallPlugInScript($sFilename);
					my $sText = "1";
					if ($Response[0] != $::SUCCESS)
						{
						$sText = "0" . ACTINIC::GetPhrase(-1, 1964);
						}
					else
						{
						#
						# Check if we have mail to send to the PayPalor Nochex customer, as we have the authorisation now
						#
						my $sMailFile;
						$sMailFile = $::Session->GetSessionFileFolder() . $::g_InputHash{ON} . ".mail";	# create the mail file name
						if (-e $sMailFile &&										# yes, we have, so send it.
							(($ePaymentMethod == $::PAYMENT_PAYPAL) ||	# and it is an auth callback from PayPal
							 ($ePaymentMethod == $::PAYMENT_NOCHEX)))		# or it is an auth callback from Nochex
							{
							if (open (MFILE, "<$sMailFile"))	# open the file
								{
								my $sRecipients = <MFILE>;	# the first line is the list of recipients
								chomp($sRecipients);
								my $sSubject = <MFILE>;	# second line is the subject
								my $sMailBody;
								chomp($sSubject);
									{
									local $/;				# the rest is the e-mail text
									$sMailBody = <MFILE>;
									}
								close MFILE;
								my @lRecipientlist = split(/,/, $sRecipients);
								my $sRecipient;
								foreach $sRecipient (@lRecipientlist)
									{
									$sRecipient =~ s/\s*//;
									if (length $sRecipient == 0)	# the recipient can not be empty string
										{
										next;
										}
									my ($Status, $Message) = ACTINIC::SendMail($::g_sSmtpServer,
																$sRecipient,
																$sSubject,
																$sMailBody,
																$$::g_pSetupBlob{EMAIL});
									if($Status != $::SUCCESS)
										{
										LogData("SendMail error:\n$Message");
										ACTINIC::RecordErrors("SendMail error:\n$Message", ACTINIC::GetPath());
										}
									}
								unlink $sMailFile;
								}
							else
								{
								LogData("SendMail error:\n" . ACTINIC::GetPhrase(-1, 21, $sMailFile, $!));
								}
							#
							# As we don't know the time when the authorisation callback will arrive from PayPal or Nochex
							# it is possible the Auth callback and the Finish callback arrive at the same time
							# in this case both script will load the unclosed session file and if the Finish callback
							# is done earlier, then the instance of session file in the auth callback contains the unclosed
							# state. So, at the time the session is rewritten it remains open, so the product(s) will remain in the cart.
							#
							}
						}
					$::g_PaymentInfo{'AUTHORIZERESULT'} = $sText;
	 				LogData("AUTHORIZERESULT:\n$sText");
					}
				else
					{
					my $sText;
	 				LogData ("RecordAuthorization:\n");
					my $sError = RecordAuthorization();
					if (length $sError != 0)
						{
						# record any error to error.err
						#
						ACTINIC::RecordErrors($sError, ACTINIC::GetPath());
						$sText = "0" . ACTINIC::GetPhrase(-1, 1964);
						}
					else
						{
						$sText = "1";
						}
					#
					# Record the result of authorize
					#
					$::g_PaymentInfo{'AUTHORIZERESULT'} = $sText;
					ACTINIC::PrintText($sText);
					}
				#
				# processing is complete at this point
				#
				my ($UpdateStatus, $UpdateMsg) = UpdateCheckoutRecord();
	 			LogData ("processing is complete: $UpdateStatus, $UpdateMsg\n");
				exit;
				}
			#
			# if this is a request from the applet or remote SHARED SSL connection to record the order, then do it.
			#
			elsif (($ePaymentMethod == $::PAYMENT_CREDIT_CARD ||
					  $ePaymentMethod == $::PAYMENT_PAYPAL_PRO) &&
				 	  $::g_InputHash{'ACTION'} =~ m/RECORDORDER/i &&
					  defined $::g_InputHash{BLOB})
				{
				my $sText;
				#
				# If the order blob is very big, it is probably a DOS attack.  Don't record the order.
				# Note that this feature has been effectively disabled by ChrisB.  He requested that I raise the limit to something absurdly high
				# to avoid conflicts with customer demands.
				#
				my $nOrderLength = length $::g_InputHash{BLOB};
				if ($nOrderLength > 1024 * 250)		# tolerate order blobs up to 250 K.  Over that they need to try a different method to submit the order.  Note that the limit is arbitrary.
					{
					$sText = "0" . ACTINIC::GetPhrase(-1, 300);
					}
				else
					{
					#
					# Record the order if the lightly encrypted data hasn't been tampered with
					#
					my $sError = RecordOrder($::g_InputHash{ORDERNUMBER}, \$::g_InputHash{BLOB}, $::TRUE);
					if (length $sError != 0)				# if there were any errors,
						{
						my $bOmitMailDump = $::FALSE;
						my $sErrorMessage = $sError;
						if($sError =~ /^000/)
							{
							$bOmitMailDump = $::TRUE;
							$sErrorMessage =~ s/^0+//;	# strip the 0's from the displayed error
							}

						NotifyOfError($sErrorMessage, $bOmitMailDump);
						ACTINIC::RecordErrors($sErrorMessage, ACTINIC::GetPath()); # record the error to error.err
						$sText = "0" . $sError;
						}
					else
						{
						$sText = "1";
						#
						# set the payment flag, so the DD link can be displayed
						# and save session as it is not saved when PrintText is the last line
						#
						$::Session->PaymentMade();
						$::Session->SaveSession();
						}
					}
				ACTINIC::PrintText($sText);
				#
				# processing is complete at this point
				#
				exit;
				}
			else
				{
				#
				# Display the receipt
				#
				($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters) = DisplayReceiptPhase($::g_InputHash{ORDERNUMBER}, $ePaymentMethod);
				if ($status != $::SUCCESS)				# on error - bail
					{
					return ($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
					}
				#
				# Notify the monitor that a new order has come in
				#
				#($status, $sMessage) = NotifyMallAdministratorOfNewOrder();
				#if ($status != $::SUCCESS)				# on error - bail
				#	{
				#	return ($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $sDetailCookie);
				#	}
				#
				# if requested, record the contact information in a cookie for future use
				#
				UpdateCheckoutRecord();
				$sDetailCookie = $::Session->ContactDetailsToCookieString();
				#
				# clean up the cart and checkout file
				#
				$::Session->MarkAsClosed();			# close session
				$::Session->SaveSession();
				}
			}
		elsif ($nPhase == $::PRELIMINARYINFOPHASE)
			{
			($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable) = ActinicOrder::DisplayPreliminaryInfoPhase();
			if ($status != $::SUCCESS)					# on error - bail
				{
				return ($status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable, $sDetailCookie);
				}
			UpdateCheckoutRecord();						# update the checkout record since the plugin is free to change it
			}
		my (@Array1, @Array2);
		@Array1 = %$pVarTable;
		@Array2 = %::s_LargeVariableTable;
		push (@Array1, @Array2);
		%::s_LargeVariableTable = @Array1;
		if (defined $pDeleteDelimiters)
			{
			push (@::s_LargeDeleteDelimiters, @$pDeleteDelimiters);
			}
		if (defined $pKeepDelimiters)
			{
			push (@::s_LargeKeepDelimiters, @$pKeepDelimiters);
			}
		#
		# process the select table only if it is actually defined
		#
		if (defined $pSelectTable)
			{
			@Array1 = %$pSelectTable;
			@Array2 = %::s_LargeSelectTable;
			push (@Array1, @Array2);
			%::s_LargeSelectTable = @Array1;
			undef $pSelectTable;
			}
		#
		# now find the bulk of the delimit stats
		#
		($pDeleteDelimiters, $pKeepDelimiters) = ActinicOrder::ParseDelimiterStatus($nPhase);
		push (@::s_LargeDeleteDelimiters, @$pDeleteDelimiters);
		push (@::s_LargeKeepDelimiters, @$pKeepDelimiters);
		}
	return ($::SUCCESS, '', \%::s_LargeVariableTable, \@::s_LargeDeleteDelimiters, \@::s_LargeKeepDelimiters,
		\%::s_LargeSelectTable, $sDetailCookie);
	}

#######################################################
#
# DisplayBillContactPhase - display the bill contact
#	 page
#
# Returns:	0 - pointer to variable table
#				1 - pointer to list of delimited regions
#						to remove
#				2 - pointer to list of unused delimiters
#
# Affects:	%::s_VariableTable, @::s_DeleteDelimiters,
#				@::s_KeepDelimiters
#
#######################################################

sub DisplayBillContactPhase
	{
	undef %::s_VariableTable;
	undef @::s_DeleteDelimiters;
	undef @::s_KeepDelimiters;
	#
	# if the phase is done, don't display it
	#
	if (ActinicOrder::IsPhaseComplete($::BILLCONTACTPHASE) ||
		 ActinicOrder::IsPhaseHidden($::BILLCONTACTPHASE))
		{
		push (@::s_DeleteDelimiters, 'INVOICEPHASE');
		return (\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
		}
	else
		{
		push (@::s_KeepDelimiters, 'INVOICEPHASE');
		}
	#
	# if the country is not defined, but a country has been selected, default
	#	to the selected country.
	#
	if (0 == length $::g_BillContact{'COUNTRY'})
		{
		if ($$::g_pLocationList{EXPECT_INVOICE} &&
			$::g_LocationInfo{INVOICE_COUNTRY_CODE} ne $ActinicOrder::REGION_NOT_SUPPLIED)
			{
			$::g_BillContact{'COUNTRY'} = ACTINIC::GetCountryName($::g_LocationInfo{INVOICE_COUNTRY_CODE});
			}
		elsif ($$::g_pLocationList{EXPECT_DELIVERY} &&
			$::g_LocationInfo{DELIVERY_COUNTRY_CODE} ne $ActinicOrder::REGION_NOT_SUPPLIED)
			{
			$::g_BillContact{'COUNTRY'} = ACTINIC::GetCountryName($::g_LocationInfo{DELIVERY_COUNTRY_CODE});
			}
		}
	#
	# Restore the default values from the invoice contact hash
	#
#	ACTINIC::CopyHash(\%::g_BillContact, \%::s_VariableTable, '', $::VARPREFIX.'INVOICE',  $::TRUE);

	$::s_VariableTable{$::VARPREFIX.'COUPONCODE'}		= ACTINIC::EncodeText2($::g_PaymentInfo{'COUPONCODE'});

	if (!$::g_BillContact{'SEPARATE'})					# if using same address, copy bill contact to shipping contact
		{
#		ACTINIC::CopyHash(\%::g_BillContact, \%::g_ShipContact, '',  '');
		ACTINIC::CopyHash(\%::s_VariableTable, \%::s_VariableTable, $::VARPREFIX.'INVOICE',  $::VARPREFIX.'DELIVER', 0);
		}
	$::s_VariableTable{$::VARPREFIX.'INVOICETITLE'}		= ACTINIC::GetPhrase(-1, 147);
	$::s_VariableTable{$::VARPREFIX.'DELIVERTITLE'}		= ACTINIC::GetPhrase(-1, 148);
	#
	# Handle check boxes
	#
	ACTINIC::SetCheckStatusNQV(\%::g_BillContact, \%::s_VariableTable, 'MOVING',			'INVOICEMOVINGCHECKSTATUS');
	ACTINIC::SetCheckStatusNQV(\%::g_BillContact, \%::s_VariableTable, 'PRIVACY',			'INVOICEPRIVACYCHECKSTATUS');
	ACTINIC::SetCheckStatusNQV(\%::g_BillContact, \%::s_VariableTable, 'SEPARATE',		'INVOICESEPARATECHECKSTATUS');
	ACTINIC::SetCheckStatusNQV(\%::g_BillContact, \%::s_VariableTable, 'REMEMBERME',		'INVOICEREMEMBERME',	'CHECKED');
	
	return (\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
	}

#######################################################
#
# DisplayShipContactPhase - display the ship contact
#	 page
#
# Returns:	0 - pointer to variable table
#				1 - pointer to list of delimited regions
#						to remove
#				2 - pointer to list of unused delimiters
#
# Affects:	%::s_VariableTable, @::s_DeleteDelimiters,
#				@::s_KeepDelimiters
#
#######################################################

sub DisplayShipContactPhase
	{
	undef %::s_VariableTable;
	undef @::s_DeleteDelimiters;
	undef @::s_KeepDelimiters;
	#
	# if the phase is done, don't display it
	#
	if (ActinicOrder::IsPhaseComplete($::SHIPCONTACTPHASE) ||
		 ActinicOrder::IsPhaseHidden($::SHIPCONTACTPHASE) )
		{
		push (@::s_DeleteDelimiters, 'DELIVERPHASE');
		return (\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
		}
	#
	# Presnet: start of un-comment
	#
	elsif (defined $$::g_pSetupBlob{'REVERSE_ADDRESS_CHECK'} && $$::g_pSetupBlob{'REVERSE_ADDRESS_CHECK'})
		{
		#
		# Presnet: handle reversing the meaning of the check box
		#
		if ($::g_BillContact{'SEPARATE'})
			{
			push (@::s_DeleteDelimiters, 'DELIVERPHASE');
			return (\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
			}
		else
			{
			push (@::s_KeepDelimiters, 'DELIVERPHASE');
			}
		}
	#
	# Presnet: end of un-comment
	#
	else
		{
		if (!$::g_BillContact{'SEPARATE'})
			{
			push (@::s_DeleteDelimiters, 'DELIVERPHASE');
			return (\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
			}
		else
			{
			push (@::s_KeepDelimiters, 'DELIVERPHASE');
			}
		}
	#
	# Make Address Book
	#
	if ($::ACT_ADB)
		{
		ConfigureAddressBook();
		$::ACT_ADB->ToForm();
		$::s_VariableTable{$::VARPREFIX.'ADDRESSBOOK'}	= $::ACT_ADB->Show();
		}
	else
		{
		$::s_VariableTable{$::VARPREFIX.'ADDRESSBOOK'}	= "";
		}
	#
	# if the country is not defined, but the shipping country has been selected, default
	#	to the shipping country.
	#
	if (0 == length $::g_ShipContact{'COUNTRY'})
		{
		if ($$::g_pLocationList{EXPECT_DELIVERY} &&
			$::g_LocationInfo{DELIVERY_COUNTRY_CODE} ne $ActinicOrder::REGION_NOT_SUPPLIED)
			{
			$::g_ShipContact{'COUNTRY'} = ACTINIC::GetCountryName($::g_LocationInfo{DELIVERY_COUNTRY_CODE});
			}
		elsif ($$::g_pLocationList{EXPECT_INVOICE} &&
			$::g_LocationInfo{INVOICE_COUNTRY_CODE} ne $ActinicOrder::REGION_NOT_SUPPLIED)
			{
			$::g_ShipContact{'COUNTRY'} = ACTINIC::GetCountryName($::g_LocationInfo{INVOICE_COUNTRY_CODE});
			}
		}
	#
	# Save location info as HTML
	#
	my $sFormat = "<INPUT TYPE=HIDDEN NAME=%s VALUE='%s'>\n";
	my $sParam;
	foreach (keys %::g_LocationInfo)
		{
		$sParam .= sprintf($sFormat, $_, $::g_LocationInfo{$_});
		}
	$::s_VariableTable{$::VARPREFIX.'LOCATIONINFO'} = $sParam;
	#
	# restore the default values from the table
	#

	$::s_VariableTable{$::VARPREFIX.'DELIVERTITLE'} 		= ACTINIC::GetPhrase(-1, 148);

	return (\%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
	}

#######################################################
#
# DisplayPageWithOrderDetails - display the next order
#	page will all of the order details embedded in the
#	HTML.
#
# Params:	0 - eApplet or eSharedSSL - page type
#					to display
#
# Returns:	0 - status
#				1 - error if any
#				2 - pointer to variable table
#				3 - pointer to list of delimited regions
#						to remove
#				4 - pointer to list of unused delimiters
#
# Affects:	%::s_VariableTable, @::s_DeleteDelimiters,
#				@::s_KeepDelimiters
#
#######################################################

sub DisplayPageWithOrderDetails
	{
	undef %::s_VariableTable;
	undef @::s_DeleteDelimiters;
	undef @::s_KeepDelimiters;

#? ACTINIC::ASSERT($#_ == 0, "Incorrect parameter count DisplayPageWithOrderDetails(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my $eMode = $_[0];

	my ($ePaymentMethod) = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"

	my (@ParamList, $sParamFormat, $bEncoding);
	if ($eMode == $::eApplet)
		{
		$sParamFormat = '<PARAM NAME="%s" VALUE="%s">';	# the param line
		$bEncoding = $::FALSE;
		}
	else
		{
		$sParamFormat = '<INPUT TYPE="HIDDEN" NAME="%s" VALUE="%s">';	# the param line
		$bEncoding = $::TRUE;
		}
	#
	# Dump all of the required information to the param list for the Java applet
	#
	#	setup blob
	#	required color
	#	prompt strings
	#	order details
	#	transaction ID
	#

	#######################################################
	#  eliminate PrepareRefPageData
	#######################################################
	my ($status, $sMessage, $sPageHistory);
	($sPageHistory) = split(/\?/, $::Session->GetLastPage());

	my ($sParam, @Response);
	if ($::g_InputHash{SHOP})
		{
		$sParam = sprintf($sParamFormat, 'SHOP', ACTINIC::EncodeText2($::g_InputHash{SHOP}, $bEncoding));
		push (@ParamList, $sParam);
		}
	#
	# Strip the trailing terminator then remove everything from the page history
	# except the first and the last entry to avoid parameter length overflow on IE6
	#
	$sPageHistory =~ s/\|\|\|$//;							# strip the trailing terminator
	$sParam = sprintf($sParamFormat, 'REFPAGE', ACTINIC::EncodeText2($sPageHistory, $bEncoding));
	push (@ParamList, $sParam);
	#
	# Passing the true sequence number can cause problems in extreme cases, so hard code 3 here
	# $sParam = sprintf($sParamFormat, 'SEQUENCE', $::g_nNextSequenceNumber);
	#
	$sParam = sprintf($sParamFormat, 'SEQUENCE', 3);
	push (@ParamList, $sParam);
	#
	# Pass some color variable
	#
	$sParam = sprintf($sParamFormat, 'REQUIRED_COLOR', $::g_sRequiredColor);
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'FORM_BACKGROUND_COLOR', $$::g_pSetupBlob{'FORM_BACKGROUND_COLOR'});
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'FORM_EMPHASIS_COLOR', $$::g_pSetupBlob{'FORM_EMPHASIS_COLOR'});
	push (@ParamList, $sParam);
	my ($bBgIsImage, $sBgImageFileName, $sBgColor) = ACTINIC::GetPageBackgroundInfo();
	$sParam = sprintf($sParamFormat, 'BACKGROUND_COLOR', $sBgColor);
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'FOREGROUND_COLOR', $$::g_pSetupBlob{'FOREGROUND_COLOR'});
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'LINK_COLOR', $$::g_pSetupBlob{'LINK_COLOR'});
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'ALINK_COLOR', $$::g_pSetupBlob{'ALINK_COLOR'});
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'VLINK_COLOR', $$::g_pSetupBlob{'VLINK_COLOR'});
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'COMPANY_NAME', $$::g_pSetupBlob{'COMPANY_NAME'});
	push (@ParamList, $sParam);
	#
	# Pass shopping cart ID along to help hack around an Internet Explorer bug on Mac
	#
	$sParam = sprintf($sParamFormat, 'CARTID', $::g_sCartId);
	push (@ParamList, $sParam);
	#
	# Pass a protocol version to make it easier to switch to a proper protocol at a later date.
	#
	$sParam = sprintf($sParamFormat, 'PROTOCOL_VERSION', $::SSSL_Protocol_Version);
	push (@ParamList, $sParam);

	#######################################################
	#  Add the important setup blob fields to the param list
	#######################################################
	#
	# Basic web communications information
	#
	my		$sCgiUrl;
	#
	# SSL_USAGE 0 = not used, 1 = essential pages, 2 = whole site
	#
	if ($$::g_pSetupBlob{'SSL_USEAGE'} == "0")
		{
		$sCgiUrl = $$::g_pSetupBlob{CGI_URL};
		}
	else
		{
		$sCgiUrl = $$::g_pSetupBlob{SSL_CGI_URL};
		}
	# Full HTTP path to cgi-bin
	#
	# Make CGI URL relative (by stripping server part) when
	# the 'Use Relative CGI URLs' option is selected
	# and make it absoulte then using the actual server
	#
	if ($$::g_pSetupBlob{'USE_RELATIVE_CGI_URLS'})
		{
		my $sServer = $::Session->GetLastShopPage();	# Get the used server name
		if ($sServer =~ /(http(s?):\/\/[^\/]*\/)/)					# strip server part
			{
			$sServer = $1;
			$sCgiUrl =~ s/http(s?):\/\/[^\/]*\//$sServer/;			# then replace it
			}
		}
	$sParam = sprintf($sParamFormat, 'CGI_URL', ACTINIC::EncodeText2($sCgiUrl, $bEncoding));
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'CGI_ID', $$::g_pSetupBlob{'CGI_ID'});
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'CGI_EXT', $$::g_pSetupBlob{'CGI_EXT'});
	push (@ParamList, $sParam);
	#
	# encryption information
	#
	#
	# write the maximum encryption key length
	#
	my $sKeyLength = $$::g_pSetupBlob{'KEY_LENGTH'};
	$sParam = sprintf($sParamFormat, 'KEY_LENGTH', $sKeyLength);
	push (@ParamList, $sParam);
	#
	# write the public encryption key
	#
	my ($nCount);
	my ($pKey) = $$::g_pSetupBlob{'PUBLIC_KEY_' . $sKeyLength . 'BIT'};
	for ($nCount = 0; $nCount <= $#$pKey; $nCount++)
		{
		$sParam = sprintf($sParamFormat, 'PUBLIC_KEY_' . $nCount, sprintf('%2.2x', $$pKey[$nCount]));
		push (@ParamList, $sParam);
		}
	#
	# Credit card options
	#
	if ($ePaymentMethod == $::PAYMENT_CREDIT_CARD)	# only send the cc info if they paid with a CC
		{
		#
		# credit cards
		#
		my ($nIndex, $sCCID, $sTemp);
		for ($nIndex = 0; $nIndex < 12; $nIndex++)
			{
			$sCCID = sprintf('CC%d', $nIndex);

			$sParam = sprintf($sParamFormat, $sCCID, $$::g_pSetupBlob{$sCCID});
			push (@ParamList, $sParam);				# the credit card name

			$sTemp = $sCCID."_STARTDATEFLAG";
			$sParam = sprintf($sParamFormat, $sTemp, $$::g_pSetupBlob{$sTemp});
			push (@ParamList, $sParam);				# whether or not it requires a start date

			$sTemp = $sCCID."_ISSUENUMBERFLAG";
			$sParam = sprintf($sParamFormat, $sTemp, $$::g_pSetupBlob{$sTemp});
			push (@ParamList, $sParam);				# whether or not it requires an issue number

			$sTemp = $sCCID."_CVV2FLAG";
			$sParam = sprintf($sParamFormat, $sTemp, $$::g_pSetupBlob{$sTemp});
			push (@ParamList, $sParam);				# whether or not it requires a CVV2

			$sTemp = $sCCID."_CVV2DIGITS";
			$sParam = sprintf($sParamFormat, $sTemp, $$::g_pSetupBlob{$sTemp});
			push (@ParamList, $sParam);				# whether or not it requires a CVV2
			}
		}
	#######################################################
	#  Add the order information
	#######################################################
	#
	# Generate the order number
	#
	my $sOrderNumber;
	($status, $sMessage, $sOrderNumber) = GetOrderNumber();
	if ($status != $::SUCCESS)
		{
		return ($status, $sMessage, undef, undef, undef);
		}

	$sParam = sprintf($sParamFormat, 'ORDERNUMBER', $sOrderNumber);
	push (@ParamList, $sParam);						# whether or not it requires an issue number

	#
	# Get the current date/time on the server
	#
	my ($sDate) = ACTINIC::GetActinicDate();
	$::g_PaymentInfo{ORDERDATE} = $sDate;
	#
	# Misc info
	#
	UpdateCheckoutRecord();
	$sParam = sprintf($sParamFormat, 'ORDER_DATE', $sDate); # the order date
	push (@ParamList, $sParam);
	#
	# Get the lightly encrypted data
	#
	@Response = GetSaferBlob($sOrderNumber, ACTINIC::GetPath(), $sDate);
	if($Response[0] != $::SUCCESS)
		{
		return(@Response);
		}
	#
	# Supply the length of the Safer blob data
	#
	$sParam = sprintf($sParamFormat, 'ORDER_DETAILS_LEN', length $Response[2], $bEncoding);
	push (@ParamList, $sParam);
	#
	# UUEncode the lightly encrypted data
	#
	my ($UUSaferBlob) = ACTINIC::UUEncode($Response[2]);

	$sParam = sprintf($sParamFormat, 'ORDER_DETAILS', $UUSaferBlob, $bEncoding);
	push (@ParamList, $sParam);

	#
	# some setup flags
	#
	$sParam = sprintf($sParamFormat, 'ORDER_BLOB_VERSION', $::ORDER_BLOB_VERSION);
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'ORDER_DETAIL_BLOB_VERSION', $::ORDER_DETAIL_BLOB_VERSION);
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'SHARED_SSL_TEST_MODE', $$::g_pSetupBlob{SHARED_SSL_TEST_MODE});
	push (@ParamList, $sParam);
	$sParam = sprintf($sParamFormat, 'SHARED_SSL_USER_ID', $$::g_pSetupBlob{SHARED_SSL_USER_ID});
	push (@ParamList, $sParam);

	#
	# add the details to the page (page specific)
	#
	if ($eMode == $::eApplet)
		{
		#
		# add the applet phrases to the list
		#
		my ($nPhraseId, $sPhrase);
		for ($nPhraseId = 500; $nPhraseId < 600; $nPhraseId++)
			{
			$sPhrase = ACTINIC::GetPhrase(-1, $nPhraseId);
			$sParam = sprintf($sParamFormat, 'PHRASE' . $nPhraseId, ACTINIC::EncodeText2($sPhrase, $bEncoding));
			push (@ParamList, $sParam);
			}
		$::s_VariableTable{$::VARPREFIX.'APPLETPARAMS'} = join("\n", @ParamList);
		}
	else														# Shared SSL
		{
		#
		# Add account details when there is a logged in customer
		#
		my $sUserDigest = $ACTINIC::B2B->Get('UserDigest');
		if ($sUserDigest)
			{
			my ($status, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sUserDigest, ACTINIC::GetPath());
			if ($status != $::SUCCESS)
				{
				return ($status, $sMessage);
				}
			my $nBuyerID = $$pBuyer{ID};
			my $nCustomerID = $$pBuyer{AccountID};
			$sParam = sprintf($sParamFormat, 'BUYERID', $nBuyerID);
			push (@ParamList, $sParam);
			$sParam = sprintf($sParamFormat, 'CUSTOMERID', $nCustomerID);
			push (@ParamList, $sParam);
			}
		#
		# Add paypal params if they are used
		#
		my ($ePaymentMethod) = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"
		if (defined $$::g_pPaymentList{$::PAYMENT_PAYPAL_PRO} &&
			 ($ePaymentMethod == $::PAYMENT_CREDIT_CARD ||
			  $ePaymentMethod == $::PAYMENT_PAYPAL_PRO))
			{
			#
			# Make sure we got the paypal stuff
			#
			EvaluatePaypalPro();
			$sParam = sprintf($sParamFormat, 'USEPP', $::TRUE);
			push (@ParamList, $sParam);
			$sParam = sprintf($sParamFormat, 'PPPARAMS', $::PAYPAL_ENC_PARAM);
			push (@ParamList, $sParam);
			my ($sFirstName, $sLastName, $sEmail, $sCountry, $sState, $sZipCode, $sCity, $sStreet) = GetPPAddressDetails();
			push (@ParamList, sprintf($sParamFormat, 'PPFIRSTNAME', 	$sFirstName));
			push (@ParamList, sprintf($sParamFormat, 'PPLASTNAME', 	$sLastName));
			push (@ParamList, sprintf($sParamFormat, 'PPEMAIL', 		$sEmail));
			push (@ParamList, sprintf($sParamFormat, 'PPCOUNTRY', 	$sCountry));
			push (@ParamList, sprintf($sParamFormat, 'PPSTATE', 		$sState));
			push (@ParamList, sprintf($sParamFormat, 'PPZIPCODE', 	$sZipCode));
			push (@ParamList, sprintf($sParamFormat, 'PPCITY', 		$sCity));
			push (@ParamList, sprintf($sParamFormat, 'PPSTREET', 		$sStreet));
			}
		#
		# Get the transaction total and the currency and pass it
		# as they are logged on the SharedSSL site
		#
		my ($Status, $Message);
		@Response = $::Session->GetCartObject();
		if ($Response[0] != $::SUCCESS)					# general error
			{
			return (@Response);								# error so return empty string
			}
		my $pCartObject = $Response[2];
		my $pCartList = $pCartObject->GetCartList();
		@Response = $pCartObject->SummarizeOrder($::FALSE);		# calculate the order total
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}
		my $nAmount = ActinicOrder::GetOrderTotal();
		$sParam = sprintf($sParamFormat, 'ORDERTOTAL', $nAmount);
		push (@ParamList, $sParam);
		$sParam = sprintf($sParamFormat, 'CURRENCY', $$::g_pCatalogBlob{'SINTLSYMBOLS'});
		push (@ParamList, $sParam);
		#
		# add just the phrases used by Shared SSL to the list
		#
		my @PromptList = ('-1,107', '-1,108', '-1,109', '-1,110', '-1,111', '-1,112', '-1,152', '-1,187',
								'-1,188', '-1,189', '-1,1970', '-1,1971', '-1,2074', '-1,2075', '-1,2076',
								'-1,2078', '-1,2086', '-1,21', '-1,2171', '-1,2172', '-1,23', '-1,24',
								'-1,25', '-1,26', '-1,319', '-1,320', '-1,502', '-1,503', '-1,505', '-1,55',
								'-1,560', '-1,561', '-1,2450', '-1,94', '-1,962', '5,1', '5,2', '5,3', '5,4', '5,5', '5,8');
		my ($nPhraseIdentifier, $sPhrase);
		foreach $nPhraseIdentifier (@PromptList) # transfer each prompt in the list
			{
			$nPhraseIdentifier =~ /,/;
			$sPhrase = ACTINIC::GetPhrase($`, $');
			$sParam = sprintf($sParamFormat, 'PHRASE' . $nPhraseIdentifier, ACTINIC::EncodeText2($sPhrase, $bEncoding));
			push (@ParamList, $sParam);
			}
		$::s_VariableTable{$::VARPREFIX.'SSL_VALUES'} = join("\n", @ParamList);
		#
		# Get rid of the test mode delimiters one way or another
		#
		if ($$::g_pSetupBlob{SHARED_SSL_TEST_MODE})
			{
			push (@::s_KeepDelimiters, 'TESTMODE');
			}
		else
			{
			push (@::s_DeleteDelimiters, 'TESTMODE');
			}
		}

	return ($::SUCCESS, '', \%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
	}

#######################################################
#
# DisplayReceiptPhase - display the ship charge
#	 page
#
# Params:	0 - the order number
#				1 - the payment method
#				2 - redisplay indicator - optional
#
# Returns:	0 - status
#				1 - error if any
#				2 - pointer to variable table
#				3 - pointer to list of delimited regions
#						to remove
#				4 - pointer to list of unused delimiters
#
# Affects:	%::s_VariableTable, @::s_DeleteDelimiters,
#				@::s_KeepDelimiters
#
#######################################################

sub DisplayReceiptPhase
	{
	undef %::s_VariableTable;
	undef @::s_DeleteDelimiters;
	undef @::s_KeepDelimiters;
	if ($#_ < 1)
		{
		return($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'DisplayReceiptPhase'), undef, undef, undef);
		}
	my ($Message, $Status);
	my ($sOrderNumber, $ePaymentMethod, $bRedisplay) = @_;
	#
	# will be set to TRUE if the authorisation callback is delayed, so the DD link can not be
	# displayed on the receit. In this case the link will be send by e-mail
	#
	my $bMailDelayed = $::FALSE;
	#
	# Check if the IP_CHECk has failed
	#
	if ($::Session->IsIPCheckFailed())
		{
		#
		# Display error message on the receipt page
		#
		$::s_VariableTable{$::VARPREFIX.'ERROR'} = ACTINIC::GetPhrase(-1, 2308);
		}
	#
	# Allow digital download content
	#
	$::ReceiptPhase = $::TRUE;
	#
	# Adjust the invoice state for the address if it is mandatory
	#
	my $bInvoiceUsesRegion = $::FALSE;
	my $bShipSeparately = ($::g_LocationInfo{SEPARATESHIP} ne '');
	if(defined $$::g_pLocationList{INVOICEADDRESS4} &&
					$$::g_pLocationList{INVOICEADDRESS4})
		{
		$bInvoiceUsesRegion = $::TRUE;
		$::g_BillContact{ADDRESS4} = ActinicLocations::GetInvoiceAddressRegionName($::g_BillContact{ADDRESS4});
		}
	#
	# Adjust the delivery state for the address if it is mandatory
	#
	if(defined $$::g_pLocationList{DELIVERADDRESS4} &&
					$$::g_pLocationList{DELIVERADDRESS4})
		{
		$::g_ShipContact{ADDRESS4} = ActinicLocations::GetDeliveryAddressRegionName($::g_ShipContact{ADDRESS4});
		#
		# Also adjust the state for the invoice address if
		# invoice doesn't use region and is not ship separately
		#
		if (!$bInvoiceUsesRegion &&					# invoice doesn't use region
			 !$bShipSeparately)							# not ship separately
			{
			$::g_BillContact{ADDRESS4} = ActinicLocations::GetInvoiceAddressRegionName($::g_BillContact{ADDRESS4});
			}
		}
	else
		{
		#
		# Also adjust the state for the delivery address if
		# invoice doesn't use region and is not ship separately
		#
		if ($bInvoiceUsesRegion &&						# invoice doesn't use region
			 !$bShipSeparately)							# not ship separately
			{
			$::g_ShipContact{ADDRESS4} = ActinicLocations::GetDeliveryAddressRegionName($::g_ShipContact{ADDRESS4});
			}
		}
	#
	# Email the receipt to the customer/buyer
	#
	my $sUserDigest = $ACTINIC::B2B->Get('UserDigest');
	my ($BuyerStatus, $sMessage, $pBuyer, $pAccount);
	if ($sUserDigest && !$bRedisplay)				# B2B mode
		{
		($BuyerStatus, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sUserDigest, ACTINIC::GetPath());
		if ($BuyerStatus != $::SUCCESS &&
			 $BuyerStatus != $::NOTFOUND)
			{
			return ($BuyerStatus, $sMessage);
			}

		if ($BuyerStatus != $::NOTFOUND)				# if the buyer was found, find the account
			{
			($Status, $sMessage, $pAccount) = ACTINIC::GetCustomerAccount($$pBuyer{AccountID}, ACTINIC::GetPath());
			if ($Status != $::SUCCESS)
				{
				return ($Status, $sMessage);
				}
			}
		}
	#
	# Send e-mail notifications about the order
	#
	my @aRecipients;
	if (!$bRedisplay)
		{
		my $sName = '';									# salutation in mail header
		my $sTemplateFile = '';							# mail template
		#
		# Compose a list of recipients
		#
		my $sEmailCopyAddresses = $::g_pSetupBlob->{'EMAIL_COPY_ADDRESSES'}; # get the list of addresses specified in catalog
		@aRecipients = split(/ /, $sEmailCopyAddresses);	# split the space-separated list
		#
		# Distinguish b2b and non-b2b users
		#
		if ($sUserDigest &&								# this is a B2B buyer
			 $BuyerStatus != $::NOTFOUND)				# and a valid buyer record exists
			{
			#
			# Get the name and email addresses
			#
			$sName = $$pBuyer{Salutation} ? $$pBuyer{Salutation} . ' ' : '';
			$sName .= $$pBuyer{Name};
			if ($$pBuyer{EmailOnOrder})				# this buyer has email enabled, thus add his address to the recipients
				{
				if (!$$pBuyer{EmailAddress})			# check whether the e-mail address exists
					 {
					 ACTINIC::RecordErrors(ACTINIC::GetPhrase(-1, 280), ACTINIC::GetPath());
					 }
				push(@aRecipients, $$pBuyer{EmailAddress});	# add the buyer's email address to the list of recipients
				}
			$sTemplateFile = 'Act_BuyerEmail.txt';	# send buyer mail
			}
		else
			{
			$sName = $::g_BillContact{'SALUTATION'} ? $::g_BillContact{'SALUTATION'} . ' ' : '';
			$sName .= $::g_BillContact{'NAME'};
			if ($$::g_pSetupBlob{EMAIL_CUSTOMER_RECEIPT}) # an e-mail should be sent to the customer, thus add his address to the recipients
				{
				if (!$::g_BillContact{EMAIL})			# check whether the e-mail address exists
					 {
					 ACTINIC::RecordErrors(ACTINIC::GetPhrase(-1, 280), ACTINIC::GetPath());
					 }
				push(@aRecipients, $::g_BillContact{EMAIL});
				}
			$sTemplateFile = 'Act_CustomerEmail.txt';	# send standard customer email
			}
		#
		# Send the mail to the recipients
		#
		if (scalar(@aRecipients) > 0)					# is there any recipient?
			{
			if ((($ePaymentMethod == $::PAYMENT_PAYPAL) ||	# if it is PayPal
				  ($ePaymentMethod == $::PAYMENT_NOCHEX)) &&	# or it is Nochex
				!$::Session->IsPaymentMade()) 		# and the Auth callback not arrived yet
				{
				my $sMailFile;
				$sMailFile = $::Session->GetSessionFileFolder() . $::g_PaymentInfo{ORDERNUMBER} . ".mail";	# create the mail file name
				$::Session->PaymentMade();				# simulate a successful authorisation
				($Status, $Message) = GenerateCustomerMail($sTemplateFile, \@aRecipients, $sName, $sMailFile);
				$::Session->ClearPaymentMade();		# clear the simulated authorisation flag
				$bMailDelayed = $::TRUE;				# indicate the DD message should explain, the link will be available by e-mail
				}
			else
				{
				($Status, $Message) = GenerateCustomerMail($sTemplateFile, \@aRecipients, $sName);
				}
			if ($Status != $::SUCCESS)
				{
				ACTINIC::RecordErrors($Message, ACTINIC::GetPath());
				}
			}
		}
	#
	# Email the order notification to the admin if necessary
	#
	if ($sUserDigest &&									# this is a B2B buyer
		 $BuyerStatus != $::NOTFOUND &&				# and a valid buyer record exists
		 $$pAccount{EmailOnOrder} &&					# this account has admin email enabled
		 $$pAccount{EmailAddress})						# the email address exists
		{
		my $sName = $$pAccount{Salutation} ? $$pAccount{Salutation} . ' ' : '';
		$sName .= $$pAccount{Name};
		@aRecipients = ($$pAccount{EmailAddress});
		($Status, $Message) = GenerateCustomerMail('Act_AdminEmail.txt',
																 \@aRecipients,
																 $sName); # send admin email
		if ($Status != $::SUCCESS)
			{
			ACTINIC::RecordErrors($Message, ACTINIC::GetPath());
			}
		}
	#
	# Presnet: email the merchant with the order details - start of un-comment
	#
	if (defined $$::g_pSetupBlob{'EMAIL_ORDER'} && $$::g_pSetupBlob{'EMAIL_ORDER'} && !$bRedisplay)
		{
		($Status, $Message) = GeneratePresnetMail();
		if ($Status != $::SUCCESS)
			{
			ACTINIC::RecordErrors($Message, ACTINIC::GetPath());
			}
		}

	################
	# Build the receipt
	################
	#
	# The date (dd Month Year)
	#
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst, $sDate);
	($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);	# platform independent time
	$mon++;													# make month 1 based
	$year += 1900;											# make year AD based
	$sDate = sprintf('%d %s %d', $mday, $::g_InverseMonthMap{$mon}, $year); # format the date "day Month Year" eg. "1 April 1998"
	$::s_VariableTable{$::VARPREFIX.'CURRENTDATE'} = $sDate;

	#
	# The order number
	#
	$::s_VariableTable{$::VARPREFIX.'THEORDERNUMBER'} = $sOrderNumber;

	#
	# The information for sending CC details separately.  This gives the user directions on how to submit the order.
	#
	my ($sDirections, $sTemp, @Response);
	if ($ePaymentMethod == $::PAYMENT_CREDIT_CARD_SEPARATE)	# send cc details separately
		{
		$sDirections = ACTINIC::GetPhrase(-1, 73);
		}
	$::s_VariableTable{$::VARPREFIX.'SENDSEPARATELY'} = $sDirections;	# add it to the receipt
	#
	# print the contact information
	#
	{
	my %HashID = (
		'CONTACT_JOB_TITLE' => 'COMPANYCONTACTTITLE',
		'COMPANY_NAME' => 'COMPANYNAME',
		'ADDRESS_1' => 'COMPANYSTREETADDRESS1',
		'ADDRESS_2' => 'COMPANYSTREETADDRESS2',
		'ADDRESS_3' => 'COMPANYSTREETADDRESS3',
		'ADDRESS_4' => 'COMPANYSTREETADDRESS4',
		'POSTAL_CODE' => 'COMPANYPOSTCODE',
		'COUNTRY' => 'COMPANYCOUNTRY',
		'PHONE' => 'COMPANYPHONE|-1|74',
		'FAX' => 'COMPANYFAX|-1|75'
		);
	ActinicOrder::HashToVarTable(\%HashID, \%$::g_pSetupBlob, \%::s_VariableTable);
	}
	undef $sTemp;
	if ((length $$::g_pSetupBlob{'CONTACT_NAME'}) > 0) # if the contact name exists
		{
		if ((length $$::g_pSetupBlob{'CONTACT_SALUTATION'}) > 0) # if the contact salutation exist
			{
			$sTemp = $$::g_pSetupBlob{'CONTACT_SALUTATION'} . " " . $$::g_pSetupBlob{'CONTACT_NAME'};
			}
		else
			{
			$sTemp = $$::g_pSetupBlob{'CONTACT_NAME'};
			}
		@Response = ACTINIC::EncodeText($sTemp,$::TRUE,$::TRUE);
		$sTemp = $Response[1] . "<BR>";	 			# add the line feed
		}
	$::s_VariableTable{$::VARPREFIX.'COMPANYCONTACTNAME'} = $sTemp;	# add it to the receipt
	undef $sTemp;
	if ((length $$::g_pSetupBlob{'EMAIL'}) > 0)
		{
		$sTemp .= ACTINIC::GetPhrase(-1, 76) . ": <A HREF=\"MAILTO:" . $$::g_pSetupBlob{'EMAIL'} . "\">" .
		   $$::g_pSetupBlob{'EMAIL'} . "</A><BR>";
		}
	$::s_VariableTable{$::VARPREFIX.'COMPANYEMAIL'} = $sTemp;	# add it to the receipt
	undef $sTemp;
	if ((length $$::g_pSetupBlob{'WEB_SITE_URL'}) > 0)
		{
		my $sService = ($$::g_pSetupBlob{WEB_SITE_URL} =~ /^http(s)?:\/\//) ? '' : 'http://';
		$sTemp = ACTINIC::GetPhrase(-1, 77) . ": <A HREF=\"" . $sService . $$::g_pSetupBlob{'WEB_SITE_URL'} . "\">" .
		   $$::g_pSetupBlob{'WEB_SITE_URL'} . "</A><BR>";
		}
	$::s_VariableTable{$::VARPREFIX.'COMPANYURL'} = $sTemp;	# add it to the receipt

	#
	# Add other prompts
	#
	$::s_VariableTable{$::VARPREFIX.'YOURRECEIPT'} 		= ACTINIC::GetPhrase(-1, 336);	# This is your receipt.
	$::s_VariableTable{$::VARPREFIX.'PRINTTHISPAGE'} 	= ACTINIC::GetPhrase(-1, 337);	# Print this page and keep it for your records.
	$::s_VariableTable{$::VARPREFIX.'NEEDTOCONTACT'} 	= ACTINIC::GetPhrase(-1, 338);	# If you need to contact us, refer to the
	$::s_VariableTable{$::VARPREFIX.'INVOICETO'} 		= ACTINIC::GetPhrase(-1, 339);	# Invoice To:
	$::s_VariableTable{$::VARPREFIX.'DELIVERTO'} 		= ACTINIC::GetPhrase(-1, 340);	# Deliver To:
	$::s_VariableTable{$::VARPREFIX.'DATETEXT'} 			= ACTINIC::GetPhrase(-1, 342);	# Date:
	$::s_VariableTable{$::VARPREFIX.'ORDERNUMBERTEXT'}	= ACTINIC::GetPhrase(-1, 343);	# Order Number:

	#
	# Do the addresses
	#
	$::s_VariableTable{$::VARPREFIX.'MOVING'} = $::g_BillContact{'MOVING'} ? ACTINIC::GetPhrase(-1, 1914) : ACTINIC::GetPhrase(-1, 1915);	# set the moving text
	#
	# Invoice first
	#
	my ($sInvoiceName);
	undef $sTemp;
	if ((length $::g_BillContact{'NAME'}) > 0)		# if the contact name exists
		{
		$sTemp = $::g_BillContact{'SALUTATION'} . " " . $::g_BillContact{'NAME'};
		@Response = ACTINIC::EncodeText($sTemp);
		$sInvoiceName .= $Response[1] . "<BR>\n";	# add it to the message display
		}
   $::s_VariableTable{$::VARPREFIX.'INVOICENAME'} = $sInvoiceName; # add the invoice address to the reciept
	{
	my %HashID = (
		'JOBTITLE' => 'INVOICEJOBTITLE',
		'COMPANY'  => 'INVOICECOMPANY',
		'ADDRESS1' => 'INVOICEADDRESS1',
		'ADDRESS2' => 'INVOICEADDRESS2',
		'ADDRESS3' => 'INVOICEADDRESS3',
		'ADDRESS4' => 'INVOICEADDRESS4',
		'POSTALCODE' => 'INVOICEPOSTALCODE',
		'COUNTRY'  => 'INVOICECOUNTRY',
		'PHONE'    => 'INVOICEPHONE|-1|348',
		'MOBILE'    => 'INVOICEMOBILE|0|2453',
		'FAX'      => 'INVOICEFAX|-1|349',
		'EMAIL'    => 'INVOICEEMAIL|-1|350',
		'USERDEFINED' => 'INVOICEUSERDEFINED|0|14'
		);
	ActinicOrder::HashToVarTable(\%HashID, \%::g_BillContact, \%::s_VariableTable);
	}
	#
	# Delivery next
	#
	my ($sDeliveryName);
		if ((length $::g_ShipContact{'NAME'}) > 0)		# if the contact name exists
			{
			$sTemp = $::g_ShipContact{'SALUTATION'} . " " . $::g_ShipContact{'NAME'};
			@Response = ACTINIC::EncodeText($sTemp);
			$sDeliveryName .= $Response[1] . "<BR>\n";	# add it to the message display
			}
		$::s_VariableTable{$::VARPREFIX.'DELIVERNAME'} = $sDeliveryName; # add the invoice address to the reciept
		{
		my %HashID = (
			'JOBTITLE' 	=> 'DELIVERJOBTITLE',
			'COMPANY'  	=> 'DELIVERCOMPANY',
			'ADDRESS1' => 'DELIVERADDRESS1',
			'ADDRESS2' => 'DELIVERADDRESS2',
			'ADDRESS3' => 'DELIVERADDRESS3',
			'ADDRESS4' => 'DELIVERADDRESS4',
			'POSTALCODE' => 'DELIVERPOSTALCODE',
			'COUNTRY'  	=> 'DELIVERCOUNTRY',
			'PHONE'    	=> 'DELIVERPHONE|-1|348',
         'MOBILE'    	=> 'DELIVERMOBILE|1|2454',
			'FAX'      	=> 'DELIVERFAX|-1|349',
			'EMAIL'    	=> 'DELIVEREMAIL|-1|350',
			'USERDEFINED' => 'DELIVERUSERDEFINED|1|13'
			);
		ActinicOrder::HashToVarTable(\%HashID, \%::g_ShipContact, \%::s_VariableTable);
		}
	#
	# Calculate the order total since it is used in a couple of places
	#
	@Response = $::Session->GetCartObject($bRedisplay);
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# error so return empty string
		}
	my $pCartObject = $Response[2];
	my $pCartList = $pCartObject->GetCartList();

	@Response = $pCartObject->SummarizeOrder($::FALSE);		# calculate the order total
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my ($Ignore0, $Ignore1, $nSubTotal, $nShipping, $nTax1, $nTax2, $nTotal, $nShippingTax1, $nShippingTax2,
		$nHandling, $nHandlingTax1, $nHandlingTax2) = @Response;
	#
	# expose the order total in various formats for affiliate tracking links
	#
	@Response = ActinicOrder::FormatPrice($nTotal, $::TRUE, $::g_pCatalogBlob);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my $sTotal = $Response[4];							# formatted primary price with currency symbol
	#
	# send the total as an integer in the currency base unit
	#    e.g. "512834"
	#
	$::s_VariableTable{$::VARPREFIX.'ACTINICORDERTOTAL'} = $nTotal;
	#
	# send the total as a formatted string
	#    e.g. "$5,128.34"
	#
	$::s_VariableTable{$::VARPREFIX.'TEXTORDERTOTAL'} = $sTotal;
	$::s_VariableTable{$::VARPREFIX.'FORMATTEDORDERTOTALCGI'} = ACTINIC::EncodeText2($sTotal, $::FALSE);
	$::s_VariableTable{$::VARPREFIX.'FORMATTEDORDERTOTALHTML'} = ACTINIC::EncodeText2($sTotal);
	#
	# send the total as a partially formatted string
	# the value will include a decimal place and any thousand
	# separators, but not the currency symbol
	#    e.g. "5,128.34"
	#
	@Response = ActinicOrder::FormatPrice($nTotal, $::FALSE, $::g_pCatalogBlob);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	$sTotal = $Response[4];							# formatted primary price without currency symbol
	$::s_VariableTable{$::VARPREFIX.'NUMERICORDERTOTALCGI'} = ACTINIC::EncodeText2($sTotal, $::FALSE);
	$::s_VariableTable{$::VARPREFIX.'NUMERICORDERTOTAL'} = $sTotal;
	#
	# Add digital download info if required
	#
	@Response = ACTINIC::GetDigitalContent($pCartList);
	if ($Response[0] == $::FAILURE)
		{
		return (@Response);
		}
	my %hDDLinks = %{$Response[2]};
	my $sDownloadMessage;
	if (keys %hDDLinks > 0)
		{
		$sDownloadMessage = ACTINIC::GetPhrase(-1, 2250, $$::g_pSetupBlob{'DD_EXPIRY_TIME'});
		}
	elsif ($bMailDelayed == $::TRUE)					# will be send by e-mail
		{
		$sDownloadMessage = ACTINIC::GetPhrase(-1, 2309);
		}
	$::s_VariableTable{$::VARPREFIX.'DOWNLOADINSTRUCTION'} = $sDownloadMessage;	# add it to the receipt
	#
	# The payment panel (the details about the payment method)
	#
	my ($sPaymentPanel);
	if ($nTotal > 0 && $$::g_pSetupBlob{'PRICES_DISPLAYED'}) # if their is money involed, display the payment panel
		{
		$::s_VariableTable{$::VARPREFIX.'PAYMENTMETHODTITLE'} = ACTINIC::GetPhrase(-1, 79); # "Payment Method"

		undef $sPaymentPanel;
		if (length $::g_PaymentInfo{'PONO'} > 0)	# if there is a po number
			{												# print it
			$sPaymentPanel = "<TR>\n";
			@Response = ACTINIC::EncodeText($::g_PaymentInfo{'PONO'});
			$sPaymentPanel .= "<TD BGCOLOR=\"$$::g_pSetupBlob{FORM_EMPHASIS_COLOR}\"><FONT FACE=\"ARIAL\" SIZE=\"2\"><B>" .
				ACTINIC::GetPhrase(-1, 81) . ":</B></FONT></TD><TD COLSPAN=2><FONT FACE=\"ARIAL\" SIZE=\"2\">";
			$sPaymentPanel .= $Response[1] . "</FONT></TD>";
			$sPaymentPanel .= "</TR>\n";
			}
		$::s_VariableTable{$::VARPREFIX.'PURCHASEORDERNUMBER'} = $sPaymentPanel; # the po number

		#
		# if the details need to be mailed in, the panel needs to be formatted like a form to be manually
		# completed
		#
		if ($ePaymentMethod == $::PAYMENT_CREDIT_CARD_SEPARATE)
			{
			push (@::s_KeepDelimiters, 'PAYMENTSENTSEPARATE'); # keep the payment sent separately panel
			push (@::s_DeleteDelimiters, 'PAYMENTOTHER');		# delete the other payment panel

			$::s_VariableTable{$::VARPREFIX.'PAYMENTMETHODNAME'} = ACTINIC::GetPhrase(-1, 80); # the actual method text

			$::s_VariableTable{$::VARPREFIX.'CREDITCARDTYPETITLE'} = ACTINIC::GetPhrase(-1, 82); # "Acceptable CC's"

			my ($nCount, $sCCID, $sCCList);
			for ($nCount = 0; $nCount < 12; $nCount++)
				{
				$sCCID = sprintf('CC%d', $nCount);
				if (length $$::g_pSetupBlob{$sCCID} > 0)
					{
					$sCCList .= $$::g_pSetupBlob{$sCCID} . ", ";
					}
				}
			$sCCList = substr($sCCList, 0, (length $sCCList) - 2); # trim off the trailing comma and space
			@Response = ACTINIC::EncodeText($sCCList);

			$::s_VariableTable{$::VARPREFIX.'CREDITCARDOPTIONS'} = $Response[1]; # list of acceptable CC's
			$::s_VariableTable{$::VARPREFIX.'SELECTONE'} = ACTINIC::GetPhrase(-1, 83); # "Select One"

			$::s_VariableTable{$::VARPREFIX.'CREDITCARDNUMBERTITLE'} = ACTINIC::GetPhrase(-1, 84); # "card number"
			$::s_VariableTable{$::VARPREFIX.'CREDITCARDISSUENUMBERTITLE'} = ACTINIC::GetPhrase(-1, 85); # "card issue number"
			$::s_VariableTable{$::VARPREFIX.'CREDITCARDCCV2TITLE'} = ACTINIC::GetPhrase(5, 8); # "card CCV2 number"
			$::s_VariableTable{$::VARPREFIX.'CREDITCARDSTARTDATETITLE'} = ACTINIC::GetPhrase(-1, 86); # "card start date"
			$::s_VariableTable{$::VARPREFIX.'CREDITCARDEXPDATETITLE'} = ACTINIC::GetPhrase(-1, 87); # "card exp date"
			$::s_VariableTable{$::VARPREFIX.'SIGNATURETITLE'} = ACTINIC::GetPhrase(-1, 88); # "card signature"
			}
		#
		# Nothing for the customer to complete here, just display the information
		#
		else
			{
			push (@::s_DeleteDelimiters, 'PAYMENTSENTSEPARATE');
			push (@::s_KeepDelimiters, 'PAYMENTOTHER');

			#
			# Display the payment method first
			#
			undef $sPaymentPanel;
			$sPaymentPanel .= ActinicOrder::EnumToPaymentString($ePaymentMethod);
			#
			# Check for failed PSP authorization and report it
			#
			if (defined $::g_PaymentInfo{'AUTHORIZERESULT'} &&
				 $::g_PaymentInfo{'AUTHORIZERESULT'} =~ /^0(.+)/)
				{
				$sPaymentPanel .= "<BR>" . ACTINIC::GetPhrase(-1, 1974) . ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor) . ACTINIC::GetPhrase(-1, 1969) .
													ACTINIC::GetPhrase(-1, 1964) .
												 	ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 1975);
				}
			$::s_VariableTable{$::VARPREFIX.'PAYMENTMETHODNAME'} = $sPaymentPanel; # actual method

			if ($ePaymentMethod == $::PAYMENT_CREDIT_CARD)	# print the credit card information if there is any
				{
				push (@::s_KeepDelimiters, 'PAYMENTCREDITCARD');
				$::s_VariableTable{$::VARPREFIX.'CREDITCARDTITLE'} = ACTINIC::GetPhrase(-1, 94); # "Credit Card"
				if (length $::g_PaymentInfo{'CARDTYPE'} > 0) # if a credit card type exists, display it
					{
					$sPaymentPanel = $::g_PaymentInfo{'CARDTYPE'};
					}
				else											 # the credit card type is blank (applet does not return it)
					{
					$sPaymentPanel = "(" . ACTINIC::GetPhrase(-1, 95) . ")"; # act like we are hiding it for safety
					}
				$::s_VariableTable{$::VARPREFIX.'CREDITCARDTYPE'} = $sPaymentPanel; # actual method
				}
			else												# no credit cards
				{
				push (@::s_DeleteDelimiters, 'PAYMENTCREDITCARD');
				}
			}
		push (@::s_KeepDelimiters, 'PAYMENTPANEL');
		}
	else														# no payment panel
		{
		push (@::s_DeleteDelimiters, 'PAYMENTPANEL');
		}
	#
	# hide the moving status if it was not asked
	#
	if (ACTINIC::IsPromptHidden(0, 13))				# no moving prompt
		{
		push (@::s_DeleteDelimiters, 'MOVINGSTATUS');
		}
	else
		{
		push (@::s_KeepDelimiters, 'MOVINGSTATUS');
		}
	#
	# Display deliver message if entered
	#
	if (!$::g_ShipInfo{'USERDEFINED'})				# no special instruction
		{
		push (@::s_DeleteDelimiters, 'DELIVERYINSTRUCTION');
		}
	else
		{
		$::s_VariableTable{$::VARPREFIX.'DELIVERINSTRUCTION_LABEL'} = ACTINIC::GetPhrase(-1, 2044);
		$::s_VariableTable{$::VARPREFIX.'DELIVERINSTRUCTION_TEXT'} = $::g_ShipInfo{'USERDEFINED'};
		push (@::s_KeepDelimiters, 'DELIVERYINSTRUCTION');
		}

	return ($::SUCCESS, '', \%::s_VariableTable, \@::s_DeleteDelimiters, \@::s_KeepDelimiters);
	}

#######################################################
#
# GetSaferBlob - Get the data for light encryption
#
# Params:	$sOrderNumber	- the order number
#				$sPath			- path to catalog directory
#				$sJavaDateTime	- date and time as supplied by Java applet (may be undef)
#									  if undefined, the current server date and time are used
#
# Returns:	0 - status
#				1 - error message
#				2 - data for light encryption
#
#######################################################

sub GetSaferBlob
	{
#? ACTINIC::ASSERT(($#_ == 1) || ($#_ == 2), "Incorrect parameter count GetSaferBlob(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sOrderNumber, $sPath, $sJavaDateTime) = @_;

	my $bUseExternalSuppliedData = ($#_ == 2);

	my ($Status, $Message);
	$::g_InputHash{'ORDERNUMBER'} = $sOrderNumber;

	my (@FieldList, @FieldType);
	#
	# Create the wrapper for the arrays
	#
	my $objOrderBlob = new OrderBlob(\@FieldType, \@FieldList);

	$objOrderBlob->AddWord($ACTINIC::ORDER_BLOB_MAGIC);# the magic number
	$objOrderBlob->AddByte($::ORDER_BLOB_VERSION);		# the version

	$objOrderBlob->AddString($sOrderNumber);				# the order number
	#
	# The Invoice Contact
	#
	$::g_BillContact{'REGION'} = ActinicLocations::GetInvoiceAddressRegionName($::g_BillContact{'ADDRESS4'});
	$objOrderBlob->AddContact(\%::g_BillContact);
	#
	# The Delivery Contact
	#
	$::g_ShipContact{'REGION'} = ActinicLocations::GetDeliveryAddressRegionName($::g_ShipContact{'ADDRESS4'});
	$objOrderBlob->AddContact(\%::g_ShipContact);
	#
	# The Payment Information
	#
	my ($ePaymentMethod) = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"
	if (defined $$::g_pPaymentList{$::PAYMENT_PAYPAL_PRO} &&
		 $ePaymentMethod == $::PAYMENT_CREDIT_CARD)
		{
		$ePaymentMethod = $::PAYMENT_PAYPAL_PRO
		}
	$objOrderBlob->AddString($$::g_pCatalogBlob{'SINTLSYMBOLS'});	# the 3 digit international currency symbol
	$objOrderBlob->AddWord($ePaymentMethod);				# the payment method enumerated id
	$objOrderBlob->AddString($::g_PaymentInfo{'USERDEFINED'});	# the generic payment user defined field
	#
	# Do a safety check on the possibly undefined MOVING value
	#
	if (! defined $::g_BillContact{MOVING} ||
		 $::g_BillContact{MOVING} eq '')
		{
		$::g_BillContact{MOVING} = $::FALSE;
		}
	$objOrderBlob->AddByte($::g_BillContact{'MOVING'});	# the moving in next month flag
	#
	# the general marketing questions
	#
	$objOrderBlob->AddString($::g_GeneralInfo{'WHYBUY'});	# the Why Did You Purchase field
	$objOrderBlob->AddString($::g_GeneralInfo{'HOWFOUND'}); # the How Did You Find field
	$objOrderBlob->AddString(GetGeneralUD3());	# the generic user defined field
	#
	# get the shopping cart information
	#
	my @Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# error so return empty string
		}
	my $pCartObject = $Response[2];
	my $pCartList = $pCartObject->GetCartList();
	#
	# Preprocess the cart data
	#
	my @aCartData;
	($Status, $Message, @aCartData) = ActinicOrder::PreprocessCartToDisplay($pCartList);
	my ($pOrderDetail);
	#
	# Count shiped lines (DD only)
	#
	my $nShipped = 0;
	if ($$::g_pSetupBlob{"DD_AUTO_SHIP"})			# auto ship of DD products?
		{
		foreach $pOrderDetail (@aCartData)			# check each product
			{
			if ($$pOrderDetail{"SHIPPED"})			# auto ship?
				{
				$nShipped++;								# count
				}
			#
			# Count auto shipped component lines
			#
			my $pComponent;
			foreach $pComponent (@{$$pOrderDetail{'COMPONENTS'}})
				{
				if ($$pComponent{"SHIPPED"})			# auto shipped?
					{
					$nShipped++;							# count
					}
				}
			}
		}
	#
	#
	# the numbers
	#
	@Response = $pCartObject->SummarizeOrder($::FALSE);	# total the order
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	#
	#				2 - sub total
	#				3 - shipping
	#				4 - tax 1
	#				5 - tax 2
	#				6 - total
	#				7 - tax 1 on shipping (fraction of 4 that is
	#					due to shipping)
	#				8 - tax 2 on shipping (fraction of 5 that is
	#					due to shipping)
	#				9 - handling
	#				10 - tax 1 on handling (fraction of 4 that is
	#					due to handling)
	#				11 - tax 2 on handling (fraction of 5 that is
	#					due to handling)
	#
	my ($Ignore, $Ignore2, $nSubTotal, $nShipping, $nTax1, $nTax2, $nTotal, $nShippingTax1, $nShippingTax2,
		$nHandling, $nHandlingTax1, $nHandlingTax2) = @Response;

	$objOrderBlob->AddQWord($nSubTotal);			# product total
	$objOrderBlob->AddDWord(0);						# discount percent
	$objOrderBlob->AddQWord(0);						# discount total
	$objOrderBlob->AddQWord($nSubTotal);			# sub-total (product total - discount)
	#
	# The shipping information
	#
	$objOrderBlob->AddQWord($nShipping);			# shipping
	$objOrderBlob->AddQWord($nShippingTax1);
	$objOrderBlob->AddQWord($nShippingTax2);
	$objOrderBlob->AddString($::g_ShipInfo{'USERDEFINED'}); # the generic user defined field
	#
	# Tax information
	#
	$objOrderBlob->AddByte($$::g_pTaxSetupBlob{'TAX_INCLUSIVE_PRICING'});	# tax inclusive pricing flag
	#
	# Set whether the taxes apply for the current tax zone
	#
	$objOrderBlob->AddByte($ActinicOrder::g_pCurrentTaxZone->{'TAX_1'} != -1);				# Zone tax 1 applies
	$objOrderBlob->AddByte($ActinicOrder::g_pCurrentTaxZone->{'TAX_2'} != -1);				# Zone tax 2 applies
	
	@Response = ActinicOrder::GetTaxModelOpaqueData();
	if($Response[0] != $::SUCCESS)
		{
		return(@Response);
		}
	$objOrderBlob->AddString($Response[2]); 		# model opaque data
	my $sTaxKey;
	foreach $sTaxKey (('TAX_1', 'TAX_2'))
		{
		$objOrderBlob->AddString(ActinicOrder::GetTaxOpaqueData($sTaxKey));
		}
	#
	# tax 1 exemption data
	#
	$objOrderBlob->AddByte($::g_TaxInfo{'EXEMPT1'}); # tax 1 user exempt flag
	$objOrderBlob->AddString($::g_TaxInfo{'EXEMPT1DATA'}); # tax 1 user exempt data
	#
	# tax 2 exemption data
	#
	$objOrderBlob->AddByte($::g_TaxInfo{'EXEMPT2'}); # tax 2 user exempt flag
	$objOrderBlob->AddString($::g_TaxInfo{'EXEMPT2DATA'}); # tax 2 user exempt data

	$objOrderBlob->AddQWord($nTax1);					# tax 1
	$objOrderBlob->AddQWord($nTax2);					# tax 1

	$objOrderBlob->AddString($::g_TaxInfo{'USERDEFINED'}); # the generic user defined field
	#
	# complete the order information
	#
	$objOrderBlob->AddQWord($nTotal);				# the order total
	#
	# the order detail summary  - make sure the line count is accurate
	#
	my ($nLineCount) = CountValidCartItems($pCartList);
	#
	# Increment by number of adjustments
	#
	$nLineCount += $pCartObject->GetAdjustmentCount();
	push (@FieldList, $nLineCount);					# the total lines
	my $nLineCountIndex = $#FieldList;				# Remember where it is - we may change it
	push (@FieldType, $::RBDWORD);

	$objOrderBlob->AddDWord($nShipped);				# the lines shipped
	$objOrderBlob->AddDWord(0);						# the lines cancelled
	#
	# Get the current date/time on the server or the java date time
	#
	if($bUseExternalSuppliedData)
		{
		$objOrderBlob->AddString($sJavaDateTime);	# the java date/time
		}
	else
		{
		my ($sDate) = ACTINIC::GetActinicDate();
		$objOrderBlob->AddString($sDate);			# the current date
		#
		# Save the data to the checkout file for checking
		# java data returned
		#
		$::g_PaymentInfo{ORDERDATE} = $sDate;
		#
		# Misc info
		#
		UpdateCheckoutRecord();
		}
	#
	# Misc info
	#
	$objOrderBlob->AddString($::g_PaymentInfo{'PONO'});		# the purchase order number
	$objOrderBlob->AddString("");						# the order reference number

	if ($::g_ShipInfo{'ADVANCED'} eq "" &&
		 $nShipping == 0)
		{
		$objOrderBlob->AddString("ShippingClass;-1;ShippingZone;-1;BasisTotal;1.000000;Simple;0;");  	# the advanced shipping data
		}
	else
		{
		$objOrderBlob->AddString($::g_ShipInfo{'ADVANCED'});  	# the advanced shipping data
		}
	$objOrderBlob->AddString($$::g_pSetupBlob{'AUTH_KEY'});	# the catalog authorization key
	$objOrderBlob->AddString($::g_LocationInfo{DELIVERY_COUNTRY_CODE});  # the location data
	$objOrderBlob->AddString($::g_LocationInfo{DELIVERY_REGION_CODE});  	# the location data
	$objOrderBlob->AddString($::g_LocationInfo{INVOICE_COUNTRY_CODE});  	# the location data
	$objOrderBlob->AddString($::g_LocationInfo{INVOICE_REGION_CODE});  	# the location data

	if ($$::g_pSetupBlob{MAKE_SHIPPING_CHARGE})	# shipping is enabled
		{
		@Response = ActinicOrder::CallShippingPlugIn(); # get the shipping description
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}
		elsif (${$Response[2]}{GetShippingDescription} != $::SUCCESS)
			{
			return(${$Response[2]}{GetShippingDescription}, ${$Response[3]}{GetShippingDescription});
			}
		$objOrderBlob->AddString($Response[5]);	# the plug-in description
		}
	else														# shipping is disabled
		{
		$objOrderBlob->AddString('');  				# empty plug-in description
		}
	#
	# add the (unused here) shared SSL test mode flag
	#
	$objOrderBlob->AddByte($$::g_pSetupBlob{SHARED_SSL_TEST_MODE});
	#
	# The handling information
	#
	$objOrderBlob->AddQWord($nHandling);			# handling
	$objOrderBlob->AddQWord($nHandlingTax1);
	$objOrderBlob->AddQWord($nHandlingTax2);
	$objOrderBlob->AddString($::g_ShipInfo{HANDLING});

	if ($$::g_pSetupBlob{MAKE_HANDLING_CHARGE})	# handling is enabled
		{
		@Response = ActinicOrder::CallShippingPlugIn(); # get the handling description
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}
		elsif (${$Response[2]}{GetHandlingDescription} != $::SUCCESS)
			{
			return(${$Response[2]}{GetHandlingDescription}, ${$Response[3]}{GetHandlingDescription});
			}
		$objOrderBlob->AddString($Response[9]);	# the plug-in description
		}
	else														# handling is disabled
		{
		$objOrderBlob->AddString('');					# the plug-in description
		}
	#
	# add the customer account info
	#
	my $sUserDigest = $ACTINIC::B2B->Get('UserDigest');

	if ($::g_InputHash{BUYERID} && $::g_InputHash{CUSTOMERID})
		{
		#
		# Restore buyer and customer IDs for SharedSSL
		#
		$objOrderBlob->AddDWord($::g_InputHash{BUYERID});		# buyer ID from input hash
		$objOrderBlob->AddDWord($::g_InputHash{CUSTOMERID});	# customer ID from input hash
		}
	elsif( $sUserDigest )								# B2B mode
		{
		my ($status, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sUserDigest, ACTINIC::GetPath());
		if ($status != $::SUCCESS)
			{
			return ($status, $sMessage);
			}
		my $nBuyerID = $$pBuyer{ID};
		my $nCustomerID = $$pBuyer{AccountID};

		$objOrderBlob->AddDWord($nBuyerID);			# the buyer ID
		$objOrderBlob->AddDWord($nCustomerID);		# the customer ID
		}
	else
		{
		$objOrderBlob->AddDWord(-1);					# no buyer ID
		$objOrderBlob->AddDWord(-1);					# no customer ID
		}
   #
   # Return the signature
   #
	$objOrderBlob->AddString($::g_sSignature);
	#
	# Set up the tax opaque data
	#
	my (@aPrefixes) = ('', 'SHIP_', 'HAND_');
	my ($sPrefix);
	foreach $sPrefix (@aPrefixes)
		{
		@Response = PrepareOrderTaxOpaqueData($sPrefix);
		if($Response[0] != $::SUCCESS)
			{
			return(@Response);
			}
		$objOrderBlob->AddString($Response[2]);
		}
	#
	# Handle SSP data
	#
	# Start with provider ID then the advanced opaque data
	#
	if($::g_ShipInfo{SSP} =~ /^SSPID=(\d+);/)
		{
		$objOrderBlob->AddDWord($1);
		$objOrderBlob->AddString($::g_ShipInfo{SSP});
		}
	else
		{
		$objOrderBlob->AddDWord(-1);
		$objOrderBlob->AddString('');
		}
	#
	# Add the packaging details
	#
	$objOrderBlob->AddString($::s_Ship_sSeparatePackageDetails);
	$objOrderBlob->AddString($::s_Ship_sMixedPackageDetails);
	#
	# Add the T&C flag
	#
	$objOrderBlob->AddByte($::g_BillContact{'AGREEDTANDC'});

	no strict 'refs';
	#
	# Now process the order detail lines
	#
	my (%CurrentItem, $pProduct);
	my $nSequenceNumber = 0;
	my $nCartIndex = 0;
	#
	# Get the prefix for the tax bands to download
	#
	my $sTaxBandPrefix = '';
	if (ActinicOrder::PricesIncludeTaxes())		# if we're using tax inclusive pricing
		{
		$sTaxBandPrefix = 'DEF';						# use default tax zone bands
		}
	foreach $pOrderDetail (@aCartData)				# for each item in the cart
		{
		%CurrentItem = %$pOrderDetail;				# get the next item
		#
		# locate this product's object.
		#
		my $pProduct = $CurrentItem{'PRODUCT'};
		#
		#  Product price
		#
		my $sPrice = $CurrentItem{'ACTINICPRICE'};
		my $nTotal = $CurrentItem{'ACTINICCOST'};

		$objOrderBlob->AddWord($ACTINIC::ORDER_DETAIL_BLOB_MAGIC);	# the order detail magic number
		$objOrderBlob->AddByte($::ORDER_DETAIL_BLOB_VERSION);			# the version number

		$objOrderBlob->AddString($CurrentItem{"REFERENCE"});			# the product reference
		$objOrderBlob->AddString($$pProduct{"NAME"});					# the product description
		$objOrderBlob->AddDWord($CurrentItem{"QUANTITY"});	# the quantity ordered
		$objOrderBlob->AddQWord($sPrice);			# the item price
		$objOrderBlob->AddQWord($nTotal);			# the line price
		$objOrderBlob->AddQWord($$pProduct{"COST_PRICE"});	# the cost price

		if (defined $CurrentItem{"DATE"})
			{
			$objOrderBlob->AddString($CurrentItem{"DATE"}); # the date field
			}
		else
			{
			$objOrderBlob->AddString("");				# null field
			}

		if (defined $$pProduct{"DATE_PROMPT"})
			{
			$objOrderBlob->AddString($$pProduct{"DATE_PROMPT"}); # the date prompt
			}
		else
			{
			$objOrderBlob->AddString("");				# null field
			}

		if (defined $CurrentItem{"INFO"})
			{
			$objOrderBlob->AddString($CurrentItem{"INFO"}); # the info field
			}
		else
			{
			$objOrderBlob->AddString("");				# null field
			}
		if (defined $$pProduct{"OTHER_INFO_PROMPT"})
			{
			$objOrderBlob->AddString($$pProduct{"OTHER_INFO_PROMPT"}); # the info prompt
			}
		else
			{
			$objOrderBlob->AddString("");				# null field
			}

		if (defined $CurrentItem{"SHIPPED"}) 		# if it is a shipped DD product
			{
			$objOrderBlob->AddDWord($CurrentItem{"SHIPPED"});	# mark all as shiped
			}
		else
			{
			$objOrderBlob->AddDWord(0);				# the quantity already shipped
			}

		$objOrderBlob->AddDWord(0);							# the quantity already cancelled
		
		$objOrderBlob->AddString($CurrentItem{$sTaxBandPrefix . "TAXBAND1"});	# tax 1 data
		$objOrderBlob->AddString($CurrentItem{$sTaxBandPrefix . "TAXBAND2"});	# tax 2 data
		
		$objOrderBlob->AddQWord(GetTaxValueForOrderBlob("1", $CurrentItem{"TAX1"}));	# tax 1									# tax 2
		$objOrderBlob->AddQWord(GetTaxValueForOrderBlob("2", $CurrentItem{"TAX2"}));	# tax 2								# tax 2

		$objOrderBlob->AddString(FormatShippingOpaqueData($pProduct, 0)); 			# advanced shipping data
		my $bParentExcludedFromShipping = $$pProduct{"EXCLUDE_FROM_SHIP"};
		$objOrderBlob->AddQWord(0);					# discount total
		$objOrderBlob->AddDWord(0);					# discount percent
		$objOrderBlob->AddDWord(0);					# Flag=0 for products

		my $sTemp = $$pProduct{'REPORT_DESC'};
		$sTemp =~  s/\\\n/\r\n/gi;
		$objOrderBlob->AddString($sTemp);			# Extra product description

		#
		# Write the product opaque tax data
		#
		@Response = ActinicOrder::PrepareProductTaxOpaqueData($pProduct, $sPrice, $$pProduct{'PRICE'}, $::FALSE);
		if($Response[0] != $::SUCCESS)
			{
			return(@Response);
			}
		$objOrderBlob->AddString($Response[2]);
		#
		# new v6 fields
		#
		$objOrderBlob->AddByte(0);									# Component as separate order line (0 for products)
		$objOrderBlob->AddByte($$pProduct{NO_ORDERLINE});	# No orderline flag
		$objOrderBlob->AddByte($::eOrderLineProduct);		# product line
		$objOrderBlob->AddDWord($nSequenceNumber);			# sequence number
		#
		# Get any product adjustments
		#
		my $parrProductAdjustments = $pCartObject->GetProductAdjustments($nCartIndex);
		my $parrAdjustDetails;
		$nCartIndex++;
		$nSequenceNumber++;								# increment the sequence number

		$objOrderBlob->AddByte(0);						# adjustment tax treatment
		$objOrderBlob->AddString("");					# coupon code
		#
		# Add stock fields
		#
		$objOrderBlob->AddByte($$pProduct{ASSEMBLY_PRODUCT});
		$objOrderBlob->AddString($$pProduct{STOCK_AISLE});
		$objOrderBlob->AddString($$pProduct{STOCK_RACK});
		$objOrderBlob->AddString($$pProduct{STOCK_SUB_RACK});
		$objOrderBlob->AddString($$pProduct{STOCK_BIN});
		$objOrderBlob->AddString($$pProduct{BARCODE});
		#
		# Check if there are any variants
		#
		{														# start of local block
		my $pComponent;
		my $nIndex = 1;
		foreach $pComponent (@{$CurrentItem{'COMPONENTS'}})
			{
			my $sProdName = $$pComponent{'NAME'};
			$FieldList[$nLineCountIndex]++;
			$objOrderBlob->AddWord($ACTINIC::ORDER_DETAIL_BLOB_MAGIC);	# the order detail magic number
			$objOrderBlob->AddByte($::ORDER_DETAIL_BLOB_VERSION); 		# the version number

			$objOrderBlob->AddString($$pComponent{REFERENCE});	# the product reference
			$objOrderBlob->AddString($sProdName);			# the product description

			$objOrderBlob->AddDWord($$pComponent{QUANTITY});	# the quantity ordered
			#
			# See if price should be added (not separate orderline)
			#
			if ($$pComponent{'SEPARATELINE'})
				{
				$objOrderBlob->AddQWord($$pComponent{ACTINICPRICE});	# the item price
				$objOrderBlob->AddQWord($$pComponent{ACTINICCOST});	# the line price
				}
			else
				{
				$objOrderBlob->AddQWord(0);			# the item price
				$objOrderBlob->AddQWord(0);			# the line price
				}
			$objOrderBlob->AddQWord($$pComponent{COST_PRICE});
			$objOrderBlob->AddString("");				# date prompt vlaue (empty for components)
			$objOrderBlob->AddString("");				# date prompt
			$objOrderBlob->AddString("");				# info prompt value (empty for components)
			$objOrderBlob->AddString("");				# info prompt

			if (defined $CurrentItem{"SHIPPED"}) 		# if it is a shipped DD product
				{
				$objOrderBlob->AddDWord($$pComponent{QUANTITY});	# mark all as shiped
				}
			else
				{
				$objOrderBlob->AddDWord(0);				# the quantity already shipped
				}

			$objOrderBlob->AddDWord(0);				# the quantity already cancelled

			$objOrderBlob->AddString($$pComponent{$sTaxBandPrefix . "TAXBAND1"});	# tax 1 data
			$objOrderBlob->AddString($$pComponent{$sTaxBandPrefix . "TAXBAND2"});	# tax 2 data

			$objOrderBlob->AddQWord(GetTaxValueForOrderBlob("1", $$pComponent{'TAX1'}));			# tax 1
			$objOrderBlob->AddQWord(GetTaxValueForOrderBlob("2", $$pComponent{'TAX2'}));			# tax 2
			#
			# Components with associated products should have the same opaque data as if the
			# associated product was ordered
			#
			if ($$pComponent{REFERENCE} ne '')
				{
				$objOrderBlob->AddString(FormatShippingOpaqueData($pComponent,
					$bParentExcludedFromShipping)); 			# advanced shipping data
				}
			else
				{
				$objOrderBlob->AddString(''); 			# advanced shipping data
				}
			$objOrderBlob->AddQWord(0);				# discount total
			$objOrderBlob->AddDWord(0);				# discount percent
			$objOrderBlob->AddDWord(1);				# Flag=1 for components
			$objOrderBlob->AddString("");				# Extra product description
			$objOrderBlob->AddString($$pComponent{'TAX_OPAQUE_DATA'});				# tax opaque data
			#
			# new v6 fields
			#
			$objOrderBlob->AddByte($$pComponent{'SEPARATELINE'});	# Component as separate order line (0 for products)
			$objOrderBlob->AddByte($$pProduct{NO_ORDERLINE});		# No orderline flag (should be zero for components)
			$objOrderBlob->AddByte($::eOrderLineComponent);	# component line
			$objOrderBlob->AddDWord($nSequenceNumber);		# sequence number
			$objOrderBlob->AddByte(0);				# adjustment tax treatment
			$objOrderBlob->AddString("");			# coupon code
			#
			# Stock fields
			#
			$objOrderBlob->AddByte($$pComponent{'ASSEMBLY_PRODUCT'});
			$objOrderBlob->AddString($$pComponent{'STOCK_AISLE'});
			$objOrderBlob->AddString($$pComponent{'STOCK_RACK'});
			$objOrderBlob->AddString($$pComponent{'STOCK_SUB_RACK'});
			$objOrderBlob->AddString($$pComponent{'STOCK_BIN'});
			$objOrderBlob->AddString($$pComponent{'BARCODE'});

			$nSequenceNumber++;						# increment the sequence number
			$nIndex++;
			}
		}														# end of local block
		foreach $parrAdjustDetails (@$parrProductAdjustments)
			{
			my $pApplicableProduct = $pProduct;
			my $sProdRef = $parrAdjustDetails->[$::eAdjIdxTaxProductRef];
			if($sProdRef ne '' &&
				$pProduct->{'REFERENCE'} ne $sProdRef)
				{
				#
				# Get the associated product
				#
				my($nStatus, $sMessage);
				($nStatus, $sMessage, $pApplicableProduct) =
					ActinicOrder::GetComponentAssociatedProduct($pProduct, $sProdRef);
				if($nStatus != $::SUCCESS)
					{
					return($nStatus, $sMessage);
					}
				}
			$objOrderBlob->AddAdjustment($nSequenceNumber, $parrAdjustDetails, $pApplicableProduct);
			$nSequenceNumber++;							# increment the sequence number
			}
		}
	#
	# Add any order adjustments
	#
	my $parrAdjustments = $pCartObject->GetOrderAdjustments();
	my $parrAdjustDetails;
	foreach $parrAdjustDetails (@$parrAdjustments)
		{
		$objOrderBlob->AddAdjustment($nSequenceNumber, $parrAdjustDetails);
		$nSequenceNumber++;							# increment the sequence number
		}
	#
	# Add any final order adjustments
	#
	$parrAdjustments = $pCartObject->GetFinalAdjustments();
	foreach $parrAdjustDetails (@$parrAdjustments)
		{
		$objOrderBlob->AddAdjustment($nSequenceNumber, $parrAdjustDetails);
		$nSequenceNumber++;							# increment the sequence number
		}
	#
	# pack the Safer blob
	#
	@Response = ACTINIC::OpenWriteBlob("memory"); # open the output blob
	($Status, $Message) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}

	@Response = ACTINIC::WriteBlob(\@FieldList, \@FieldType); # write the blob
	($Status, $Message) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}

	@Response = ACTINIC::CloseWriteBlob();			# close up
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	return($::SUCCESS, '', $Response[2]);
	}

#######################################################
#
# GetTaxValueForOrderBlob - Negate the tax if tax is exempt in tax-inclusive mode.
#
# Input:	$sTaxIdentifier	- "1" or "2" for the tax
#			$nTax					- tax amount
#
# Returns:	tax value
#
#######################################################

sub GetTaxValueForOrderBlob
	{
	my ($sTaxIdentifier, $nTax) = @_;
	
	if ($::g_TaxInfo{'EXEMPT' . $sTaxIdentifier} ||									# if they've declared exemption for tax 
		!ActinicOrder::IsTaxApplicableForLocation('TAX_' . $sTaxIdentifier))	# or tax isn't applicable for current location
		{
		if (ActinicOrder::PricesIncludeTaxes())										# if prices include taxes
			{
			$nTax = -$nTax;																	# negate the tax
			}
		}
	return $nTax;
	}
	
#######################################################
#
# CompleteOrder - complete the order process.  This
#	includes saving the order, cleaning up any temporary
#	files and then displaying the reciept.  If a back
#	plug in exists, call it.
#
# Returns:	0 - status
#				1 - error message
#
#######################################################

sub CompleteOrder
	{
	ActinicOrder::ParseAdvancedTax();
	#
	# Dump the order to the nq script
	#
	my $sPath = ACTINIC::GetPath();
	#
	# Generate the order number and save it for the command header
	#
	my ($Status, $Message, $sOrderNumber);
	($Status, $Message, $sOrderNumber) = GetOrderNumber();
	if ($Status != $::SUCCESS)
		{
		return ($Status, $Message);
		}
	#
	# Greg here it is
	# This is a trick to generate multiple orders with one click
	# Uncomment following lines (from DUPLICATE to END DUPLICATE - exclusive) and similar set down below
	# Set $nDuplicateTotal to required number of orders
	# An artificial order number is created for each order
	#

	# DUPLICATE (uncomment from here)
#	my $nDuplicateTotal = 10;
#	my $nDuplicateCurrent;
#	for ($nDuplicateCurrent = 0; $nDuplicateCurrent < $nDuplicateTotal; $nDuplicateCurrent++)
#		{
#	$sOrderNumber = substr($sOrderNumber,0,6) . sprintf("%8.8d",substr($sOrderNumber,6) + 1);
	# END DUPLICATE (end of uncomment) - but see DUPLICATE below

	my @Response = GetSaferBlob($sOrderNumber, $sPath);
	if($Response[0] != $::SUCCESS)
		{
		return(@Response);
		}

	my ($SaferBlob) = $Response[2];
	#
	# now process the DH encrypted data.  If there is no data to encrypt, leave the blob undefed.
	#
	my $DHBlob;
	if (length $::g_PaymentInfo{'CARDNUMBER'} > 0 ||
		 length $::g_PaymentInfo{'CARDTYPE'} > 0 ||
		 length $::g_PaymentInfo{'EXPYEAR'} > 0 ||
		 length $::g_PaymentInfo{'EXPMONTH'} > 0)
		{
		my (@FieldList, @FieldType);
		push (@FieldList, $::g_PaymentInfo{'CARDNUMBER'});# the cc number
		push (@FieldType, $::RBSTRING);
		push (@FieldList, $::g_PaymentInfo{'CARDTYPE'});# the cc card name
		push (@FieldType, $::RBSTRING);
		push (@FieldList, $::g_PaymentInfo{'EXPYEAR'} . '/' . $::g_PaymentInfo{'EXPMONTH'});	# the cc expiration date
		push (@FieldType, $::RBSTRING);
		push (@FieldList, $::g_PaymentInfo{'CARDVV2'});			# the CVV2 field
		push (@FieldType, $::RBSTRING);
		#
		# the v4.0 lightly encrypted credit card information.
		#
		if (ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}) == $::PAYMENT_CREDIT_CARD)	# if paying with CC, send the details
			{
			push (@FieldList, $::g_PaymentInfo{'CARDISSUE'});# the cc issue number
			push (@FieldType, $::RBSTRING);
			push (@FieldList, $::g_PaymentInfo{'STARTYEAR'} .	# the cc start date
				($::g_PaymentInfo{'STARTYEAR'} eq "" ? '' : '/') .	# if the data is NULL, don't enter the /
				$::g_PaymentInfo{'STARTMONTH'});
			push (@FieldType, $::RBSTRING);
			}
		else														# no paying with CC's, enter blank stuff
			{
			push (@FieldList, 0);							# the cc issue number
			push (@FieldType, $::RBSTRING);					#
			push (@FieldList, "");							# the cc start date
			push (@FieldType, $::RBSTRING);				#
			}
		#
		# pack the D-H blob
		#
		@Response = ACTINIC::OpenWriteBlob("memory"); # open the output blob
		($Status, $Message) = @Response;
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}

		@Response = ACTINIC::WriteBlob(\@FieldList, \@FieldType); # write the blob
		($Status, $Message) = @Response;
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}

		@Response = ACTINIC::CloseWriteBlob();		# close up
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}
		$DHBlob = $Response[2];
		}
	#
	# encrypt the portion of the blob that requires encryption
	#
	#
	# encryption information
	#
	my $EncryptedBlob;
#&	ActinicProfiler::StartLoadRuntime('ActEncrypt1024');
	eval 'require ActEncrypt1024;';
#&	ActinicProfiler::EndLoadRuntime('ActEncrypt1024');
	if ($@)												# the encryption module does not exist
		{
		#
		# Use perl encryption
		#
		ActinicEncrypt::InitEncrypt(@{$$::g_pSetupBlob{PUBLIC_KEY_128BIT}}); 	# initialize the data tables
		$EncryptedBlob = ActinicEncrypt::Encrypt($DHBlob, $SaferBlob); # encrypt the data
		}
	else
		{
		#
		# gather the key - .  Also not that the
		# bytes are stored least significant byte first, so the order must be reversed for the ActEncrypt library.
		#
		my $sKey;
		my $sKeyLength = $$::g_pSetupBlob{'KEY_LENGTH'};
		#
		# write the public encryption key
		#
		my ($nCount);
		my ($pKey) = $$::g_pSetupBlob{'PUBLIC_KEY_' . $sKeyLength . 'BIT'};
		for ($nCount = ($sKeyLength / 8) - 1; $nCount >= 0; $nCount--)
			{
			$sKey .= sprintf('%2.2x', $$pKey[$nCount]);
			}
		#
		# encrypt the blob
		#
		my ($nDataLength, $nPhraseID);
		($Status, $nPhraseID, $EncryptedBlob, $nDataLength) =
			ActEncrypt1024::EncryptData($sKey, $SaferBlob, length $SaferBlob, $DHBlob, length $DHBlob);		# initialize the data tables
		if ($Status != $::SUCCESS)
			{
			return ($Status, ACTINIC::GetPhrase(-1, $nPhraseID));
			}
		}

	#
	# save the order
	#
	my $sError = RecordOrder($sOrderNumber, \$EncryptedBlob);

	if ($sError)										# if an error occured
		{
		return($::FAILURE, NotifyOfError($sError));
		}


	#
	# Greg here it is
	#
	# DUPLICATE (uncomment from here)
#		}
	# END DUPLICATE (end of uncomment)


	return ($::SUCCESS, "");
	}

#######################################################
#
# UpdateCheckoutRecord - Update the checkout record
#
# Returns:	0 - status
#				1 - message
#
#######################################################

sub UpdateCheckoutRecord
	{
	#
	# save the modified data.  The payment info only saves the method, purchase order number, and the user
	# defined field.  This prevents security leaks of CC information.
	#
	my (%EmptyPaymentInfo);
	$EmptyPaymentInfo{'METHOD'} 		= $::g_PaymentInfo{'METHOD'};
	$EmptyPaymentInfo{'USERDEFINED'} = $::g_PaymentInfo{'USERDEFINED'};
	$EmptyPaymentInfo{'PONO'}			= $::g_PaymentInfo{'PONO'};
	$EmptyPaymentInfo{'COUPONCODE'}	= $::g_PaymentInfo{'COUPONCODE'};
	#
	# Save order number and Buyer Hash for  OCC_VALIDATE callback
	#
	$EmptyPaymentInfo{'ORDERNUMBER'}	= $::g_PaymentInfo{'ORDERNUMBER'};
	#
	# Save order date for Java check
	#
	$EmptyPaymentInfo{'ORDERDATE'}	= $::g_PaymentInfo{'ORDERDATE'};
	#
	# Save the buyer hash
	#
	$EmptyPaymentInfo{'BUYERHASH'}	= $ACTINIC::B2B->Get('UserDigest');
	#
	# Save the buyer user name
	#
	$EmptyPaymentInfo{'BUYERNAME'}	= $ACTINIC::B2B->Get('UserName');
	#
	# Save the buyer user name
	#
	$EmptyPaymentInfo{'BASEFILE'}	= $ACTINIC::B2B->Get('BaseFile');
	#
	# Save the authorize callback result
	#
	$EmptyPaymentInfo{'AUTHORIZERESULT'}	= $::g_PaymentInfo{'AUTHORIZERESULT'};
	#
	# Save the UD3 field
	#
	$::g_GeneralInfo{'USERDEFINED'} = GetGeneralUD3();
	#
	# If we are in B2B mode, save the account price schedule
	#
	if ($ACTINIC::B2B->Get('UserDigest') ||
		 defined $::g_PaymentInfo{'SCHEDULE'})
		{
		$EmptyPaymentInfo{'SCHEDULE'} 	= $::g_PaymentInfo{'SCHEDULE'};
		}

	return ($::Session->UpdateCheckoutInfo(\%::g_BillContact, \%::g_ShipContact, \%::g_ShipInfo, \%::g_TaxInfo,
										\%::g_GeneralInfo, \%EmptyPaymentInfo, \%::g_LocationInfo));
	}

#######################################################
#
# GetCancelPage - retrieve the cancel page text
#
# Returns:	0 - page HTML
#
#######################################################

sub GetCancelPage
	{
	my ($sRefPage) = $::Session->GetLastShopPage();					# find the original referencing page
	#
	# If the vendor requested an unframed checkout and specified a URL, use the given URL for the return
	#
	if ($$::g_pSetupBlob{UNFRAMED_CHECKOUT} &&	# unframed checkout
		 $$::g_pSetupBlob{UNFRAMED_CHECKOUT_URL})	# a URL was supplied
		{
		$sRefPage = $$::g_pSetupBlob{UNFRAMED_CHECKOUT_URL}; # use the given URL
		}

	my @Response = ACTINIC::BounceToPagePlain(0, undef, undef,
		$::g_sWebSiteUrl, $::g_sContentUrl, $::g_pSetupBlob, $sRefPage, \%::g_InputHash);

	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
		return;
		}

	return ($Response[2]);
	}

#######################################################
#
# DoOfflineAuthorization - deal with authorization of
#	offline payment methods.
#
# This function is only called and used when Orderscript.pl
# is being called by a PSP server during an offline payment 
# transaction
#
#######################################################

sub DoOfflineAuthorization
	{
	my	$sPath = ACTINIC::GetPath();						# get the path to the web site
	#
	# read the payment blob
	#
	my @Response = ACTINIC::ReadPaymentFile($sPath);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	#
	# Let the post processor do all the processing
	#
	# Get the PSP payment method details
	#
	my ($sFilename, $pPaymentMethodHash, $ePaymentMethod);
	if($::g_InputHash{'ACTION'} =~ m/^OFFLINE_AUTHORIZE_(\d+)$/i)
		{
		$ePaymentMethod = $1;
		}
	else
		{
		return;
		}
	#
	# Get the payment method hash
	#
	$pPaymentMethodHash = $$::g_pPaymentList{$ePaymentMethod};
	#
	# Get the bounce script name
	#
	$sFilename = $$pPaymentMethodHash{POST_PROCESS};
	#
	# Call bounce script and process its result
	#
	if (defined $sFilename)
		{
		my (@Response) = CallPlugInScript($sFilename);
		}
	else
		{
		RecordAuthorization();
		ACTINIC::PrintText("OK");
		}
	}
	
#######################################################
#
# RecordAuthorization - record the authorization blob
#	from the OCC server
#
# Input:    0 - a reference to the "original input data"
#               string (the input data as originally defined
#               in $::ENV{QUERY_STRING} or STDIN).
#               Optional.  If not defined,
#               $::g_OriginalInputData is used.
#
# Returns:	0 - Error message (if any)
#
#######################################################

sub RecordAuthorization
	{
	my ($psCgiInput) = @_;
	unless (defined $psCgiInput)
		{
		$psCgiInput = \$::g_OriginalInputData;
		}
	#
	# make sure a reasonable order number exists
	#
	if (length $::g_InputHash{ON} < 5)
		{
		return(ACTINIC::GetPhrase(-1, 185, (length $::g_InputHash{ON}), $::g_InputHash{ON}));
		}
	#
	# Grab the PSP provider ID from the AUTHORIZE action
	#
	my ($ePaymentMethod, $sRemoteIP);
	if($::g_InputHash{'ACTION'} =~ m/^AUTHORIZE_(\d+)$/i)
		{
		$ePaymentMethod = $1;
		}
	elsif ($::g_InputHash{'ACTION'} =~ m/^OFFLINE_AUTHORIZE_(\d+)$/i)
		{
		$ePaymentMethod = $1;
		}
		
	$sRemoteIP = $ENV{REMOTE_ADDR};
	my ($bIPRangeDefined, $sIPRange) = ACTINIC::IsCustomVarDefined("ACT_IPCHECK_" . $ePaymentMethod);
	if ($bIPRangeDefined)								# if we have to check the IP address of PSP gaetway
		{
		if (!ACTINIC::IsValidIP($sRemoteIP, $sIPRange))	# if the senders ip is not in the given range
			{
			$::Session->IPCheckFailed();				# set the IPCHECK variable to 'Failed' in session
			$::Session->SaveSession();					# save session file
			my $sMessage = ACTINIC::GetPhrase(-1, 2307, $sIPRange, $sRemoteIP, $::g_OriginalInputData);
			ACTINIC::RecordErrors($sMessage, ACTINIC::GetPath());
			ACTINIC::SendMail($::g_sSmtpServer,
									$::g_pSetupBlob->{'EMAIL'},
									$$::g_pPaymentList{$ePaymentMethod}{PROMPT}." - IP Address Check Exception for order number ".$::g_InputHash{ON},
									$sMessage);	# send the message to the merchant
			}
		}
	#
	# record the authorization blob
	#
	my (@FieldList, @FieldType);

	push (@FieldList, hex("22"));						# the magic number
	push (@FieldType, $::RBWORD);
	push (@FieldList, 2);								# the version
	push (@FieldType, $::RBBYTE);
	push (@FieldList, $ePaymentMethod);				# the OCC provider ID
	push (@FieldType, $::RBDWORD);
	push (@FieldList, $::g_InputHash{TM} ? 1 : 0); # the test mode
	push (@FieldType, $::RBBYTE);
	push (@FieldList, $$psCgiInput);					# the raw CGI input string
	push (@FieldType, $::RBSTRING);
	#
	# pack the unencrypted portion of the blob
	#
	my $sPath = ACTINIC::GetPath();
	my @Response = ACTINIC::OpenWriteBlob('memory'); # open the output blob
	my ($Status, $Message) = @Response;
	if ($Status != $::SUCCESS)
		{
		my $sError = (0 == length $Response[1]) ? "Error opening the write blob" : $Response[1];
		return(NotifyOfError($sError));
		}

	@Response = ACTINIC::WriteBlob(\@FieldList, \@FieldType); # write the blob
	($Status, $Message) = @Response;
	if ($Status != $::SUCCESS)
		{
		my $sError = (0 == length $Response[1]) ? "Error writing blob" : $Response[1];
		return(NotifyOfError($sError));
		}

	@Response = ACTINIC::CloseWriteBlob();			# close up
	if ($Response[0] != $::SUCCESS)
		{
		my $sError = (0 == length $Response[1]) ? "Error closing the write blob" : $Response[1];
		return(NotifyOfError($sError));
		}
	my ($ClearBlob) = $Response[2];					# grab the unencrypted portion of the blob

	#
	# encrypt the portion of the blob that requires encryption
	#
	#
	# encryption information
	#
	my ($EncryptedBlob);
	ActinicEncrypt::InitEncrypt(@{$$::g_pSetupBlob{PUBLIC_KEY_128BIT}}); # initialize the data tables
	$EncryptedBlob = ActinicEncrypt::Encrypt(undef, $ClearBlob); # encrypt the data

	my ($sTempFilename) = $::Session->GetSessionFileFolder() . $::g_InputHash{ON} . '.occ';
	ACTINIC::SecurePath($sTempFilename);			# make sure only valid filename characters exist in $file to prevent hanky panky
	#
	# Due to Actinic Payment there may be multiple auth blobs per order.
	# Therefore we should make sure there is not one there already
	#
	my $sOCCFileName = $::g_InputHash{ON} . '.occ';
	my ($sOCCFilePath) = $::Session->GetSessionFileFolder() . $sOCCFileName;
	ACTINIC::SecurePath($sOCCFilePath);			# make sure only valid filename characters exist in $file to prevent hanky panky	
	while (-e $sOCCFilePath)
		{
		my $nIncremental;
		($sOCCFileName, $nIncremental) = split /_/, $sOCCFileName;
		$sOCCFileName = $::g_InputHash{ON} . "_" . ++$nIncremental . '.occ';
		$sOCCFilePath = $::Session->GetSessionFileFolder() . $sOCCFileName;
		ACTINIC::SecurePath($sOCCFilePath);			# make sure only valid filename characters exist in $file to prevent hanky panky
		}
	#
	# dump the blob to a temporary file.  if the filename changes from OrderNumber.occ,
	#	the C++ function CFileTransfer::CleanUpCorruptAuthorizationBlobs must be updated since
	#  it relies on deriving the order number from the blob name.
	#
	$sTempFilename = $sOCCFilePath;
	unless ( open (COMPLETEFILE, ">" . $sTempFilename)) # open the file
		{
		return(ACTINIC::GetPhrase(-1, 21, $sTempFilename, $!));
		}
	binmode COMPLETEFILE;
	unless (print COMPLETEFILE $EncryptedBlob)	# write the file
		{
		my ($sError) = $!;
		close COMPLETEFILE;
		unlink $sTempFilename;
		return(ACTINIC::GetPhrase(-1, 28, $sTempFilename, $sError));
		}
	close COMPLETEFILE;
#? ACTINIC::ASSERT($sTempFilename =~ /$::g_InputHash{ON}/, "The authorization blob filename must be derived from the order number.", __LINE__, __FILE__);

	#
	# check if the order amount is equal to the authorised amount and mark the order as paid only in this case
	#
	my $sOCCValidationData = GetOCCValidationData();	# get the OCC validation data generated from the order
	$sOCCValidationData =~ /AMOUNT=(\d+)/;					# get the amount part of it
	my $sOrderAmount =   $1;
	if ($sOrderAmount == $::g_InputHash{'AM'})			# check if it is the same as the authorised one
		{
		#
		# set the payment flag, so the DD link can be displayed
		#
		$::Session->PaymentMade();
		}
	#
	# check if the mail file for this order is exist.
	# if it does, then it means the finish callback arrived earlier,
	# so we don't save the session file, to avoid saving a previous state of session object
	#
	my $sMailFile = $::Session->GetSessionFileFolder() . $::g_InputHash{ON} . ".mail";
	if (! (-e $sMailFile))									# yes, we have, so skip it.
		{
		$::Session->SaveSession();
		}
	#
	# Allocate stock if it isn't allocated yet
	#
	if (!$$::g_pSetupBlob{PSP_PENDING_STOCK_ALLOCATION} &&
		  $$::g_pPaymentList{$ePaymentMethod}{PAYMENT_TYPE})
		{
		#
		# Read the saved stock levels
		#
		my ($sStockFilename) = $::Session->GetSessionFileFolder() . ACTINIC::CleanFileName($::g_InputHash{ON} . '.stk');
		my @Response = ACTINIC::ReadConfigurationFile($sStockFilename);	
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}
		#
		# We can get rid of the stock file now.
		#
		unlink $sStockFilename;
		#
		# Allocate the stock
		#
		@Response = ActinicOrder::AllocateStock($::pStockLevels);
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}
		}
	
	return (undef);
	}

#######################################################
#
# LogData - (currently) wrapper for ACTINIC::RecordErrors
#           writes if $nDebugLogLevel != 0;
#
# Input:		0 - string to write
#
# Author: Bill Birthisel
#
#######################################################

sub LogData
	{
#? ACTINIC::ASSERT($#_ == 0, "Incorrect parameter count LogData", __LINE__, __FILE__);
	if ($nDebugLogLevel)
		{
		my $sLogData = shift;
		ACTINIC::RecordErrors($sLogData, ACTINIC::GetPath());
		}
	}

#######################################################
#
# CallOCCPlugIn - call the online credit card plug-in
#
# Returns:	0 - status
#				1 - error message if any
#				2 - HTML to display (if any)
#
#######################################################

sub CallOCCPlugIn
	{
	#
	# The online credit card plug-in expects the following values:
	#
	#	Expects:		$::sOrderNumber		- the alphanumeric order number for this order
	#					$::nOrderTotal			- the total for this order (stored in based currency format e.g. 1000 = $10.00)
	#					%::PriceFormatBlob   - the price format data
	#					%::InvoiceContact		- customer invoice contact information
	#					%::OCCShipData			- customer invoice shipping information
	#					$::sCallBackURLAuth	- the URL of the authorization callback script
	#					$::sCallBackURLBack	- the URL of the backup script
	#					$::sCallBackURLUser	- the URL of the receipt script
	#					$::sPath					- the path to the Catalog directory
	#					$::sWebSiteUrl			- the referrer URL
	#					$::sContentUrl			- the content URL
	#              $::sCartID           - the cart ID
	#
	local ($::sOrderNumber, $::nOrderTotal, %::PriceFormatBlob, %::InvoiceContact, $::sCallBackURLUser, %::OCCShipData);
	local ($::sCallBackURLAuth, $::sCallBackURLBack, $::pCartList);
	#
	# get the order summary for validation
	#
	my ($Status, $Message);
	my @Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# error so return empty string
		}
	my $pCartObject = $Response[2];

	@Response = $pCartObject->SummarizeOrder($::TRUE);# calculate the order total
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	$::nOrderTotal = $Response[6];					# the order total

	%::PriceFormatBlob = %{$::g_pCatalogBlob};	# the catalog blob can be used for prices since it contains the price fields

	%::InvoiceContact = %::g_BillContact;			# invoice address information
	%::OCCShipData = %::g_ShipContact;				# invoice shipping information

	($Status, $Message, $::sOrderNumber) = GetOrderNumber();
	if ($Status != $::SUCCESS)
		{
		return ($Status, $Message, undef);
		}
	#
	# Build the different callback URLs
	# Note that these should be based on SSL_CGI_URL if http+https
	# configuration is used because the CGI_URL contains the non secure
	# CGI URL in this case.
	#
	my		$sCgiUrl;
	#
	# SSL_USAGE 0 = not used, 1 = essential pages, 2 = whole site
	#
	if ($$::g_pSetupBlob{'SSL_USEAGE'} eq 1)
		{
		$sCgiUrl = $$::g_pSetupBlob{SSL_CGI_URL};
		}
	else
		{
		$sCgiUrl = $$::g_pSetupBlob{CGI_URL};
		}
	#
	# build the record authorization URL
	#
	my	$ePaymentMethod = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"
	$::sCallBackURLAuth = sprintf("%sos%6.6d%s?%s", $sCgiUrl, $$::g_pSetupBlob{CGI_ID}, $$::g_pSetupBlob{CGI_EXT},
		'PATH=' . ACTINIC::EncodeText2(ACTINIC::GetPath(), $::FALSE) . '&');
	$::sCallBackURLAuth .= "SEQUENCE=3&ACTION=AUTHORIZE_$ePaymentMethod&CARTID=$::g_sCartId&";
	#
	# build the base URL for all other actions
	#
	my ($sBaseUrl) = sprintf("%sos%6.6d%s?%s", $sCgiUrl, $$::g_pSetupBlob{CGI_ID}, $$::g_pSetupBlob{CGI_EXT},
		($::g_InputHash{SHOP} ? 'SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) . '&' : ''));
	#
	# build the reciept URL
	#
	@Response = ACTINIC::EncodeText(ACTINIC::GetPhrase(-1, 504), $::FALSE);
	my ($sFinish) = $Response[1];
	@Response = ACTINIC::EncodeText($::Session->GetLastShopPage(), $::FALSE); # the reference page
	my $sRefPage = $Response[1];
	#
	# Passing the true sequence number can cause problems in some cases (no payment page), so hard code 3 here
	# $sParam = sprintf($sParamFormat, 'SEQUENCE', $::g_nNextSequenceNumber);
	#
	$::sCallBackURLUser = $sBaseUrl . "SEQUENCE=3&ACTION=$sFinish" .
		"&ORDERNUMBER=$::sOrderNumber&REFPAGE=" . $sRefPage . "&";
	#
	# build the back url
	#
	@Response = ACTINIC::EncodeText(ACTINIC::GetPhrase(-1, 503), $::FALSE);
	my $sBack = $Response[1];
	#
	# check if the referrer URL has data from a GET.  If it does, we
	# strip the data and build it from scratch
	#
	my $sReferrer = ACTINIC::GetReferrer();
	if ($sReferrer =~ /\?.+/)                    # if a GET request
		{
		($sReferrer) = split /\?/, $sReferrer;
		}
	elsif (length $sReferrer < 3)						# check if the referrer is incorrect
		{														# and use the setup blob if so
		$sReferrer = sprintf("%sos%6.6d%s", $sCgiUrl, $$::g_pSetupBlob{CGI_ID}, $$::g_pSetupBlob{CGI_EXT});
		}
	$::sCallBackURLBack = $sReferrer . "?SEQUENCE=3" .
		"&ACTION=" . $sBack .
		"&REFPAGE=" . $sRefPage .
		($::g_InputHash{SHOP} ? '&SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : '') .
		"&";
	#
	# load the plug-in
	#
	@Response = GetOCCScript(ACTINIC::GetPath());
	if ($Response[0] != $::SUCCESS)					# couldn't load the script
		{
		return (@Response);								# bail out
		}

	my ($sScript) = $Response[2];
	#
	# some utilitarian values
	#
	local $::sPath = ACTINIC::GetPath();
	local $::sWebSiteUrl = $::g_sWebSiteUrl;
	local $::sContentUrl = $::g_sContentUrl;
	local $::sCartID = $::g_sCartId;
	#
	# If we're in B2b, the URLs are wrong so set the correct ones
	#
	if($ACTINIC::B2B->Get('UserDigest'))
		{
		$::sContentUrl = $ACTINIC::B2B->Get('BaseFile');
		$::sContentUrl =~ s#/[^/]*$#/#;
		$::sWebSiteUrl = $::g_sAccountScript;
		$::sWebSiteUrl .= ($::g_InputHash{SHOP} ? '?SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) . '&': '?');
		$::sWebSiteUrl .= 'PRODUCTPAGE=';
		}
	#
	# Try to load MD5
	#
 	eval
		{
		require Digest::MD5;								# Try loading MD5
		import Digest::MD5 'md5_hex';
		};
	if ($@)
		{
		require <Actinic:Variable Name="DigestPerlMD5"/>;
		import Digest::Perl::MD5 'md5_hex';			# Use Perl version if not found
		}
		
	#
	# now execute the plug-in
	#
	if (eval($sScript) != $::SUCCESS)				# execute the script
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 170, $@));
		}
	if ($::sRedirectURL)
		{
		LogData ("CallOCCPlugIn:\n$::sRedirectURL");
		}
	else
		{
		LogData ("CallOCCPlugIn:\n$::sHTML");
		}

	return ($::eStatus, $::sErrorMessage, $::sHTML);
	}

#######################################################
#
# GetOCCScript - read and return the OCC
#		script
#
# Params:	0 - the path
#
# Returns:	0 - status
#				1 - error message (if any)
#				2 - script
#
# Affects:	$::s_sOCCScript - the script
#
#######################################################

sub GetOCCScript
	{
	if (defined $::s_sOCCScript)# if it is already in memory,
		{
		return ($::SUCCESS, "", $::s_sOCCScript); # we are done
		}

	if ($#_ < 0)											# validate params
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'GetOCCScript'), 0, 0);
		}
	my ($sPath) = $_[0];									# grab the path
	#
	# Get the PSP payment method details
	#
	my	$ePaymentMethod = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); # the payment method is stored as "ENUMERATEDID:DESCRIPTION"

	my ($sFilename, $pPaymentMethodHash);
	#
	# Get the payment method hash
	#
	$pPaymentMethodHash = $$::g_pPaymentList{$ePaymentMethod};
	#
	# Get the bounce script name
	#
	$sFilename = $sPath . $$pPaymentMethodHash{BOUNCE_SCRIPT};

	my @Response = ACTINIC::ReadAndVerifyFile($sFilename);
	if ($Response[0] == $::SUCCESS)					# if successful
		{
		$::s_sOCCScript = $Response[2];				# record the script
		}
	return (@Response);
	}

#######################################################
#
# GetOrderNumber - retrieve the order number for this
#	order.  The order number is generated as follows:
#
#       Order Number = FLPPPPIXXXXXXX
#               F - first character of first name
#               L - first character of last name
#               PPPP - last four digits of post code
#               I - last digit of the script ID
#               XXXXXXX - 7 digit incremental number
#
#	The incremented ID is 0 prepadded if necessary.
#	If F or L is blank of PPPP does not consume all
#	four characters, the remaining characters are filled
#	with psuedo random characters.
#
# Returns:	0 - status
#				1 - message
#				2 - order number in a string
#				3 - undef
#
# Affects:	$::s_sOrderNumber
#
#######################################################

sub GetOrderNumber
	{
	if (length $::s_sOrderNumber > 0)
		{
		return ($::SUCCESS, undef, $::s_sOrderNumber, undef);
		}
	my (@CharacterSet) = split(//, "3456789ABCDEFGHJKLMNPQRSTUVWXY");
	#
	# attempt to extract the first characters of the name.  If this fails - use the least significant digits of the
	# process ID.
	#
	my $sInitials;
	my $sName = $::g_BillContact{'NAME'};
	$sName =~ s/[^a-zA-Z0-9 ]//g;						# drop any non-alphanums or non-spaces
	$sName =~ s/^\s*//;									# clear leading and traling spaces
	$sName =~ s/\s*$//;
	if (!$sName)											# if the name DNE, take the last two digits from the process ID
		{
		$sInitials = substr("00" . ACTINIC::Modulus($$, 100), -2);
		}
	elsif (2 >= length $sName)							# the name field only contains 1 or 2 characters - grab them
		{
		$sInitials = substr($sName . ACTINIC::Modulus($$, 10), 0, 2);
		}
	elsif ($sName =~ /([^ \t\r\n]+)\s*([^ \t\r\n]+)\s*([^ \t\r\n]*)/) # two or three names - get the true initials
		{
		my $s = $3 ? $3 : $2;
		$sInitials = substr($1, 0, 1) . substr($s, 0, 1);
		}
	else														# just get the first two characters of the name
		{
		$sInitials = substr($sName, 0, 2);
		}
	$sInitials = uc($sInitials);						# always use upper case
	#
	# now get the postal code
	#
	my $sPostCode = uc($::g_BillContact{POSTALCODE});
	$sPostCode =~ s/[^A-Z0-9]//g; 					# drop any non-alphanums or spaces
	srand(time() ^($$ + ($$ << 15)));				# get a reasonably random seed
	while ( (length $sPostCode) < 4)
		{
		$sPostCode = int(rand(10000)) . $sPostCode; # tack on some pseudo-random numbers
		}
	$sPostCode = substr($sPostCode, -4, 4);		# just take the last 4 digits
	$sPostCode =~ s/\s/_/g;								# Replace spaces by underscores
	#
	# now comes the important part - get a unique order number for this order
	#
	my $nNumberBreakRetries = 1;						# number of times to try to break the lock file if it is dead
	my $sUnLockFile = ACTINIC::GetPath() . 'Order.num'; # name of the lock file in its unlocked state
	my $sBackupFile = ACTINIC::GetPath() . 'Backup.num'; # name of the lock file in its unlocked state
	my $sLockFile = ACTINIC::GetPath() . 'OrderLock.num'; # name of the lock file in its locked state
	ACTINIC::SecurePath($sUnLockFile);				# make sure only valid filename characters exist in $file to prevent hanky panky
	ACTINIC::SecurePath($sBackupFile);				# make sure only valid filename characters exist in $file to prevent hanky panky
	ACTINIC::SecurePath($sLockFile);					# make sure only valid filename characters exist in $file to prevent hanky panky
	#
	# if none of the files exist, create the order file and then sleep for a bit before trying to obtain a lock
	# to it.
	#
START_AGAIN:
	if (!-e $sUnLockFile &&								# none of the files exist
		 !-e $sLockFile &&
		 !-e $sBackupFile)
		{
		#
		# create the unlocked file
		#
		unless (open (LOCK, ">$sUnLockFile"))
			{
			return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 182, $sUnLockFile, $!)), undef, undef);
			}
		binmode LOCK;
		my $nCounter = pack("N", 0);
		unless (print LOCK $nCounter)
			{
			my $sError = $!;
			close (LOCK);
			return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 28, $sUnLockFile, $sError)), undef, undef);
			}
		close (LOCK);

		sleep 2;												# now pause to allow concurrent processes to lock the file
		}
	#
	# if only the backup file exists, copy it to the unlock file
	#
	my $nByteLength = 4;
	if (!-e $sUnLockFile &&								# only the backup file exists
		 !-e $sLockFile &&
		  -e $sBackupFile)
		{
		#
		# create the unlocked file from the backup file
		#
		unless (open (BACK, "<$sBackupFile"))
			{
			my $sError = $!;
			return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 21, $sBackupFile, $sError)), undef, undef);
			}
		binmode BACK;
		my $nCounter;
		unless ($nByteLength == read (BACK, $nCounter, $nByteLength))
			{
			my $sError = $!;
			close (BACK);
			#
			# Backup file failed to contain a valid counter.
			# Try to recover and notify the merchant
			#
			if (!unlink($sBackupFile))			# try to remove
				{										# report if couldn't remove
				return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 201, $!)), undef, undef);
				}
			sleep 2;
			NotifyOfError(ACTINIC::GetPhrase(-1, 2304));
			goto START_AGAIN;						# try again from the beginning
			}
		close (BACK);
		unless (open (LOCK, ">$sUnLockFile"))
			{
			return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 182, $sUnLockFile, $!)), undef, undef);
			}
		binmode LOCK;
		unless (print LOCK $nCounter)
			{
			my $sError = $!;
			close (LOCK);
			return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 28, $sUnLockFile, $sError)), undef, undef);
			}
		close (LOCK);

		sleep 2;												# now pause to allow concurrent processes to lock the file
		}

	my $nDate;												# the date on the lock file
	my $bFileIsLocked = $::FALSE;						# note if we get the file
	my $sRenameError;
RETRY:
	$bFileIsLocked = $::FALSE;
	if ($nNumberBreakRetries < 0)						# we seem to be in an unrecoverable situation
		{
		return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 201, $sRenameError)), undef, undef);
		}

	my $nRetries = 20;									# number of times to retry the lock file
	while ($nRetries > 0)								# repeat the attempt to grab the file until you have it or give up
		{
		if (rename($sUnLockFile, $sLockFile))		# try to lock the file
			{
			#
			# note the success, and get out of the loop
			#
			$bFileIsLocked = $::TRUE;
			last;
			}
		$sRenameError = $!;								# save the error
		#
		# file lock failed - get the lock file time if we have not done it before (to see if it is dead)
		#
		if (!defined $nDate)
			{
			#
			# store the date on the lock file so we can determine whether or not it is dead
			#
			my @tmp = stat $sLockFile;
			$nDate = $tmp[9];
			}

		$nRetries--;										# decrement the retry count

		sleep 2;												# pause before we try again
		}
	#
	# if we don't have a lock file at this point, a process may have died with the file locked.
	# check the mod date on the file.  If it has not changed since we first attempted to lock it,
	# assume the file is dead and unlock it.  Then wait a second and try the lock loop again.
	#
	if (!$bFileIsLocked)
		{
		if (-e $sLockFile)
			{
			my @tmp = stat $sLockFile;
			if (!defined $nDate)							# the lock file must not exist at all but there is some other rename error,
				{												# bail out with an error
				return ($::FAILURE, (ACTINIC::GetPhrase(-1, 201, $sRenameError)), undef, undef);
				}

			if (!defined $tmp[9])						# file was removed just before we got the current date -
				{												# assume it is free and try again
				$nNumberBreakRetries--;					# decrement the counter
				sleep 2;
				goto RETRY;
				}

			if ($nDate == $tmp[9])						# the lock file date has not changed
				{
				#
				# Check the file size. If it seems to be empty (corrupt) then
				# remove the file and go back to the beginning to give a chance for the backup file
				#
				if ($tmp[7] == 0)							# empty?
					{
					if (!unlink($sLockFile))			# try to remove
						{										# report if couldn't remove
						return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 201, $!)), undef, undef);
						}
					sleep 2;
					goto START_AGAIN;						# try again from the beginning
					}
				if (!rename($sLockFile, $sUnLockFile))	# try to unlock the file
					{
					#
					# failure
					#
					return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 201, $!)), undef, undef);
					}
				}
			#
			# OK - try to lock the file again
			#
			$nNumberBreakRetries--;						# decrement the counter
			sleep 2;
			goto RETRY;
			}
		else													# file was removed just before we got here -
			{													# assume it is free and try again
			$nNumberBreakRetries--;						# decrement the counter
			sleep 2;
			goto RETRY;
			}
		}
	#
	# if we are here, we have the lock:
	#
	#		open the file
	#		read the counter
	#		close the file
	#		increment the counter
	#		open the file (removing it)
	#		write the counter
	#		close the file
	#		open the backup file
	#		write the counter
	#		close the file
	#
	unless (open (LOCK, "<$sLockFile"))				# open the file
		{
		return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 182, $sLockFile, $!)), undef, undef);
		}
	binmode LOCK;
	my $nCounterBin;
	unless ($nByteLength == read (LOCK, $nCounterBin, $nByteLength))	# read the counter
		{
		#
		# the lock file failed to contain the counter.  Try the backup file
		#
		my $sError = $!;
		close (LOCK);
		unless (open (LOCK, "<$sBackupFile"))
			{
			return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 182, $sBackupFile, $!)), undef, undef);
			}
		binmode LOCK;
		unless ($nByteLength == read (LOCK, $nCounterBin, $nByteLength))
			{
			#
			# the backup file is dead as well - report the error as if the problem was with the
			# first file
			#
			close (LOCK);
			return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 105, $sLockFile, $sError)), undef, undef);
			}
		}
	close (LOCK);											# close the file
	#
	# increment the counter
	#
	my $nCounter = unpack("N", $nCounterBin);
	$nCounter++;
	if ($nCounter > 9999999)							# manually wrap around at 7 digits since that is all of the space
		{														# we have available in our numbering scheme
		$nCounter = 0;
		}
	$nCounterBin = pack ("N", $nCounter);
	#
	# update the lock file
	#
	unless (open (LOCK, ">$sLockFile"))
		{
		return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 182, $sLockFile, $!)), undef, undef);
		}
	binmode LOCK;
	unless (print LOCK $nCounterBin)
		{
		my $sError = $!;
		close (LOCK);
		return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 28, $sLockFile, $sError)), undef, undef);
		}
	close (LOCK);
	#
	# update the backup file
	#
	unless (open (LOCK, ">$sBackupFile"))
		{
		return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 182, $sBackupFile, $!)), undef, undef);
		}
	binmode LOCK;
	unless (print LOCK $nCounterBin)
		{
		my $sError = $!;
		close (LOCK);
		return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 28, $sBackupFile, $sError)), undef, undef);
		}
	close (LOCK);
	#
	# now we have a unique ID for this order - unlock the file
	#
	if (!rename ($sLockFile, $sUnLockFile))
		{
		return ($::FAILURE, NotifyOfError(ACTINIC::GetPhrase(-1, 202, $!)), undef, undef);
		}
	#
	# now we are ready to construct the order number
	#
	$::s_sOrderNumber = $sInitials . $sPostCode . substr($$::g_pSetupBlob{CGI_ID}, -1) .
		substr("0000000" . $nCounter, -7);

#? ACTINIC::ASSERT(14 == length $::s_sOrderNumber, "Order number is not 14 characters long (" . (length $::s_sOrderNumber) . ", " . $::s_sOrderNumber . ").", __LINE__, __FILE__);

	return ($::SUCCESS, undef, $::s_sOrderNumber, undef);
	}

#######################################################
#
# GetGeneralUD3 - get the General phase USERDEFINED 3
#	prompt value.  The value is either the value
#	entered by the customer, or the value retrieved
#  from the session which is a string indicating the
#  referring marketing entity.
#
# Returns:	the value of the variable
#
#######################################################

sub GetGeneralUD3
	{
	#
	# If the UD3 prompt is is hidden then
	# use the referrer from the session file
	#
	if (ACTINIC::IsPromptHidden(4, 2))
		{
		return ($::Session->GetReferrer());
		}
	#
	# return the UD3 value
	#
	return ($::g_GeneralInfo{'USERDEFINED'});
	}

#######################################################
#
# CountValidCartItems - count the cart items
#	eliminating any items that no longer exist in the
#	catalog
#
# Params:	0 - pointer to the cart list
#
# Returns:	0 - item count
#
#######################################################

sub CountValidCartItems
	{
	if ($#_ != 0)											# validate params
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'CountValidCartItems'), 0, 0);
		}
	my $pCartList = $_[0];
	my ($pOrderDetail, @Response);
	my (%CurrentItem, $pProduct);
	my $nLineCount = 0;
	foreach $pOrderDetail (@$pCartList)				# for each item in the cart
		{
		%CurrentItem = %$pOrderDetail;				# get the next item
		#
		# Locate the section blob
		#
		my ($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($CurrentItem{SID}); # retrieve the blob name
		if ($Status == $::FAILURE)
			{
			ACTINIC::RecordErrors($Message, ACTINIC::GetPath());
			next;
			}
		#
		# locate this product's object
		#
		@Response = ACTINIC::GetProduct($CurrentItem{"PRODUCT_REFERENCE"},  $sSectionBlobName,
			ACTINIC::GetPath());					# get this product object
		if ($Response[0] != $::NOTFOUND)				# the item has been removed from the catalog
			{
			$nLineCount++;									# increment the line count
			}
		}
	return ($nLineCount);
	}

#######################################################
#
# EnsurePaymentSelection - ensure that a valid payment
#	method is selected if there are no options or just
#	one option.
#
# Expects:	g_pSetupBlob - the setup blob to be defined
#
# Affects:	g_PaymentInfo - the payment method
#
#######################################################

sub EnsurePaymentSelection
	{
	#
	# If the payment method is defined
	#
	if (0 < length $::g_PaymentInfo{'METHOD'})
		{
		return;												# there isn't anything to do
		}
	#
	# if there is only one payment option, take it.
	# if there are no payment options, assume pre-pay
	#
	my @arrPayments;
	ActinicOrder::GenerateValidPayments(\@arrPayments);
	my $nPaymentOptions = @arrPayments;				# count the valid methods
	#
	# Failsafe - if the payment method is still undefined, use pre-pay
	#
	if (length $::g_PaymentInfo{'METHOD'} == 0)	# if the payment method is still undefined
		{
		$::g_PaymentInfo{'METHOD'} = $::PAYMENT_INVOICE_PRE_PAY	; # default to prepay
		}
	}

#######################################################
#
# RecordOrder - record the order blob - send mail if
#	the blob
#
# Params:	0 - the order number
#				1 - a reference to the order blob
#				2 - whether to check the light data
#
# Returns:	0 - Error message (if any)
#
#######################################################

sub RecordOrder
	{
	if ($#_ != 1 && $#_ != 2)											# validate params
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'RecordOrder'), 0, 0);
		}
	my ($sOrderNumber, $pBlob, $bCheckLightData) = @_;
	#
	# save the order number to the payment info for an
	# OCC_VALIDATE callback
	#
	$::g_PaymentInfo{'ORDERNUMBER'} = $sOrderNumber;
	UpdateCheckoutRecord();							# update the checkout record
	#
	# see if any orders already exist
	#
	my ($Status, $Message, @FileList) = ACTINIC::ReadTheDir($::Session->GetSessionFileFolder());# read the contents of the directory
	if ($Status != $::SUCCESS)
		{
		@FileList = ();
		}
	my $sFileList = join(' ', @FileList);
	my $bOrderExists = ($sFileList =~ /\.ord( |$)/);
	#
	# Check the light data if required
	#
	if($bCheckLightData)
		{
		my($nReturnCode, $sError) = CheckSaferEncryptedData($sOrderNumber, $pBlob);
		if($nReturnCode != $::TRUE)
			{
			return($sError);
			}
		}
	#
	# dump the blob to a file
	#
	my ($sTempFilename) = $::Session->GetSessionFileFolder() . ACTINIC::CleanFileName($sOrderNumber . '.ord');
	if (-e $sTempFilename)								# if the file exists overwrite it
		{
		$::Session->Unlock($sTempFilename);
		}
	ACTINIC::SecurePath($sTempFilename);			# make sure only valid filename characters exist in $file to prevent hanky panky
	unless ( open (COMPLETEFILE, ">" . $sTempFilename)) # open the file
		{
		return(ACTINIC::GetPhrase(-1, 21, $sTempFilename, $!));
		}
	binmode COMPLETEFILE;
	unless (print COMPLETEFILE $$pBlob)	# write the file
		{
		my ($sError) = $!;
		close COMPLETEFILE;
		unlink $sTempFilename;
		return(ACTINIC::GetPhrase(-1, 28, $sTempFilename, $sError));
		}
	close COMPLETEFILE;
	$::Session->Lock($sTempFilename);
	#
	# if this is the first order, and the vendor requested email, and a valid email address exists,
	#	and a valid SMTP server exists, then send email
	#
	if (!$bOrderExists &&
		 $$::g_pSetupBlob{EMAIL_REQUESTED} &&
		 $$::g_pSetupBlob{EMAIL} ne "" &&
		 $::g_sSmtpServer ne "")
		{
		($Status, $Message) = ACTINIC::SendMail($::g_sSmtpServer, $$::g_pSetupBlob{EMAIL},
			ACTINIC::GetPhrase(-1, 309), ACTINIC::GetPhrase(-1, 310));
		#
		# ignore return code (just record the error)
		#
		if ($Status != $::SUCCESS)
			{
			ACTINIC::RecordErrors($Message, ACTINIC::GetPath());
			}
		}
	#
	# Allocate stock if needed
	# If it is a PSP order and we do not allocate stock for pending PSP orders
	# then save the stock levels and do the allocation at OCC callback
	#
	my ($ePaymentMethod) = ActinicOrder::PaymentStringToEnum($::g_PaymentInfo{'METHOD'}); 
	if (!$$::g_pSetupBlob{PSP_PENDING_STOCK_ALLOCATION} &&
		  $$::g_pPaymentList{$ePaymentMethod}{PAYMENT_TYPE})
		{
		#
		# Generate the stock file
		#
		my @Response = ActinicOrder::CalculateCartQuantities($::TRUE);
		if ($Response[0] != $::SUCCESS)				# general error
			{
			return (@Response);							# error so return
			}
		#
		# Build a parameter list for the stock manager
		#
		my $pStockLevels = $Response[2];
		my ($sVarDump, $key, $value);
		while (($key, $value) = each(%{$pStockLevels}))
			{
			$sVarDump .= sprintf("\t'%s' => '%s',\r\n", $key, $value);
			}
		my $sOut = sprintf("\$::pStockLevels = \r\n\t{\r\n%s\t};\r\nreturn(\$::SUCCESS);", $sVarDump);
		my $uTotal;
			{
			use integer;
			$uTotal = unpack('%32C*', $sOut);
			}
		my $sContent = sprintf("%d;\n%s", $uTotal, $sOut);
		my ($sTempFilename) = $::Session->GetSessionFileFolder() . ACTINIC::CleanFileName($sOrderNumber . '.stk');
		if (-e $sTempFilename)								# if the file exists overwrite it
			{
			$::Session->Unlock($sTempFilename);
			}
		ACTINIC::SecurePath($sTempFilename);			# make sure only valid filename characters exist in $file to prevent hanky panky
		unless ( open (COMPLETEFILE, ">" . $sTempFilename)) # open the file
			{
			return(ACTINIC::GetPhrase(-1, 21, $sTempFilename, $!));
			}

		unless (print COMPLETEFILE $sContent)	# write the file
			{
			my ($sError) = $!;
			close COMPLETEFILE;
			unlink $sTempFilename;
			return(ACTINIC::GetPhrase(-1, 28, $sTempFilename, $sError));
			}
		close COMPLETEFILE;
		}
	else	
		{
		($Status, $Message) = ActinicOrder::AllocateStock();
		}
	#
	# ignore return code (just record the error)
	#
	if ($Status != $::SUCCESS)
		{
		ACTINIC::RecordErrors($Message, ACTINIC::GetPath());
		}
	return (undef);
	}

#######################################################
#
# CheckSaferEncryptedData - Check the Safer encrypted data
#
# Params:   0 - Order number
#           1 - blob reference
#
# Returns:	($nReturnCode, $Error)
#				if $ReturnCode = $::FALSE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#
#######################################################

sub CheckSaferEncryptedData
	{
	my ($sOrderNumber, $pBlob) = @_;
	my (@BlobDetails) = unpack("C4NNC*", $$pBlob);
	my $sError;
#
# debug code
#
#	$sError = 'Blob version: ' . $BlobDetails[0] . "\n";
#	$sError .= 'Safer version: ' . $BlobDetails[1] . "\n";
#	$sError .= 'Prime index: ' . $BlobDetails[2] . "\n";
#	$sError .= 'Prime length: ' . $BlobDetails[3] . "\n";
#	$sError .= 'Heavy lengh: ' . $BlobDetails[4] . "\n";
#	$sError .= 'Light lengh: ' . $BlobDetails[5] . "\n";
	#
	# Format of the blob is 4 bytes followed by 2 4-byte numbers
	# followed by the public key, then heavy and finally light data
	#
	# Calculate the offset to the start of the light data
	#
	my $nLightDataOffset = 4 + 8 + $BlobDetails[3] + $BlobDetails[4];
	#
	# Get the encrypted light data
	#
	my $sBlobLightData = substr($$pBlob, $nLightDataOffset);
	#
	# Get the java date from the input hash if supplied or decrypt
	# the blob light data
	#
	my @bFixedKey = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);

	my @Response = GetSaferBlob($sOrderNumber, ACTINIC::GetPath(),
		$::g_PaymentInfo{ORDERDATE});
	if($Response[0] != $::SUCCESS)
		{
		return($::FALSE, $Response[1]);
		}

	my ($SaferBlob) = $Response[2];
	#
	# encrypt the non-essential data using Safer with our fixed key
	#
	ActinicSafer::InitTables();
	my $sActualLight = ActinicEncrypt::EncryptSafer($SaferBlob, @bFixedKey);
	if($sActualLight ne $sBlobLightData)
		{
		return($::FALSE, '000' . ACTINIC::GetPhrase(-1, 360));
		}

#
# debug code
#
#	my (@aActualBytes) = unpack("C*", $sActualLight);
#	my @aBlobLightData = unpack("C*", $sBlobLightData);
#	my $i;
#	for ($i = 0; $i < (length $sActualLight) ; $i++)
#		{
#		$sError .= 'Byte ' . $i . ': ' . $aBlobLightData[$i] . ' = ' . $aActualBytes[$i]. "\n";
#		}
#	return($::FALSE, $sError);
	return($::TRUE, '');
	}

#######################################################
#
# GenerateCustomerMail - generate the customer email
#
# Params:   0 - template file
#           1 - email address
#           2 - name
#				3 - Mail file name	optional
#					 If present, then the mail goes to file instead of the recepients
#
# Expects:	%::g_InputHash, and %g_SetupBlob
#					should be defined
#
# Returns:	($ReturnCode, $Error)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#
#######################################################

sub GenerateCustomerMail
	{
#? ACTINIC::ASSERT($#_ >= 2, "Incorrect parameter count GenerateCustomerMail(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sTemplateFile, $paRecipients, $sName, $sMailFile) = @_;
#? ACTINIC::ASSERT($sTemplateFile, "Undefined template file.", __LINE__, __FILE__);

	my (@Response, $Status, $Message);
	$ACTINIC::B2B->ClearXML();									# prepare the XML engine
	#
	# If no recipient is specified, then skip the remaining processing
	#
	if (scalar(@{$paRecipients}) == 0)
		 {
		 return ($::SUCCESS, "");
		 }
	#
	# If the required information is not available, skip sending the email
	#
	if (!$$::g_pSetupBlob{EMAIL})
		 {
		 return ($::FAILURE, ACTINIC::GetPhrase(-1, 279));
		 }
	if (!$::g_sSmtpServer)
		 {
		 return ($::FAILURE, ACTINIC::GetPhrase(-1, 281));
		 }
	@Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# error so return empty string
		}
	my $pCartObject = $Response[2];
	#
	# Be sure that correct currency symbols are used in the mail
	#
	if (!$$::g_pSetupBlob{'EMAIL_CURRENCY_SYMBOL'})
		{
		$::USEINTLCURRENCYSYMBOL = $::TRUE;
		}
	#
	# Summarize the order. This will process product and order adjustments
	#
	@Response = $pCartObject->SummarizeOrder($::TRUE); # calculate the order total
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my ($Ignore0, $Ignore1, $nSubTotal, $nShipping, $nTax1, $nTax2, $nTotal, $nShippingTax1, $nShippingTax2, $nHandling, $nHandlingTax1, $nHandlingTax2) = @Response;
	@Response = ActinicOrder::SummarizeOrderPrintable(@Response);	# get the printable versions of the prices
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}

	my ($Ignore2, $Ignore3, $sSubTotal, $sShipping, $sHandling, $sTax1, $sTax2, $sTotal) = @Response;
	my $pCartList = $pCartObject->GetCartList();
	#
	# Customer name
	#
	$ACTINIC::B2B->SetXML('CUSTOMER_NAME',$sName);
	#
	# Order number and date
	#
	$ACTINIC::B2B->SetXML('ORDER_NUMBER',$::g_InputHash{ORDERNUMBER});
	my ($nSec, $nMin, $nHour, $nMday, $nMon, $nYear, $nWday, $nYday, $nIsdst, $sDate);
	($nSec, $nMin, $nHour, $nMday, $nMon, $nYear, $nWday, $nYday, $nIsdst) = gmtime(time);	# platform independent time
	$nMon++;													# make month 1 based
	$nYear += 1900;										# make year AD based
	#
	# Format Date as required
	#
	my ($sMon) = $::g_InverseMonthMap{$nMon};
	my ($sDatePrompt) = ACTINIC::FormatDate($nMday, $sMon, $nYear);
	$sDate = $sDatePrompt . sprintf(" %2.2d:%2.2d GMT", $nHour, $nMin);
	#
	# Check for IPCHECK validation failure
	#
	if ($::Session->IsIPCheckFailed())
		{
		$sDate .= "\r\n" . ACTINIC::GetPhrase(-1, 2308);
		}
	$ACTINIC::B2B->SetXML('ORDER_DATE',$sDate);
	#
	# Print the shipping address
	#
	my %hashShipMap = (
		'SALUTATION'	=> 'SHIP_SALUTATION',
		'NAME'			=> 'SHIP_NAME',
		'JOBTITLE'		=> 'SHIP_TITLE',
		'COMPANY'		=> 'SHIP_COMPANY',
		'ADDRESS1'		=> 'SHIP_ADDRESS1',
		'ADDRESS2'		=> 'SHIP_ADDRESS2',
		'ADDRESS3'		=> 'SHIP_ADDRESS3',
		'ADDRESS4'		=> 'SHIP_ADDRESS4',
		'POSTALCODE'	=> 'SHIP_POSTCODE',
		'COUNTRY'		=> 'SHIP_COUNTRY',
		'PHONE'			=> 'SHIP_PHONE',
		'FAX'				=> 'SHIP_FAX',
		'EMAIL'			=> 'SHIP_EMAIL',
		'USERDEFINED'	=> 'SHIP_USERDEFINED',
		);
	my ($sTempUserDefined) = $::g_ShipContact{'USERDEFINED'};
	if (!$::g_BillContact{'SEPARATE'} &&			# if not separate addresses
		 $::g_BillContact{'USERDEFINED'})			# and a BillContact UserDefined exists
		{
		$::g_ShipContact{'USERDEFINED'} = $::g_BillContact{'USERDEFINED'};	# use the BillContact UserDefined
		}
	SetXMLFromHash(\%hashShipMap, \%::g_ShipContact);
	$::g_ShipContact{'USERDEFINED'} = $sTempUserDefined;	# reset the ShipContact UserDefined
	#
	# Print the billing address if separate
	#
	my %hashBillMap = (
		'SALUTATION'	=> 'BILL_SALUTATION',
		'NAME'			=> 'BILL_NAME',
		'JOBTITLE'		=> 'BILL_TITLE',
		'COMPANY'		=> 'BILL_COMPANY',
		'ADDRESS1'		=> 'BILL_ADDRESS1',
		'ADDRESS2'		=> 'BILL_ADDRESS2',
		'ADDRESS3'		=> 'BILL_ADDRESS3',
		'ADDRESS4'		=> 'BILL_ADDRESS4',
		'POSTALCODE'	=> 'BILL_POSTCODE',
		'COUNTRY'		=> 'BILL_COUNTRY',
		'PHONE'			=> 'BILL_PHONE',
		'FAX'				=> 'BILL_FAX',
		'EMAIL'			=> 'BILL_EMAIL',
		'USERDEFINED'	=> 'BILL_USERDEFINED',
		);

	if ($::g_BillContact{'SEPARATE'})				# if separate billing address
		{														# print it separately
		$ACTINIC::B2B->SetXML('BILL_LABEL', ACTINIC::GetPhrase(-1, 339));

		SetXMLFromHash(\%hashBillMap, \%::g_BillContact);
		}
	else														# otherwise
		{
		$ACTINIC::B2B->SetXML('BILL_LABEL', "");
		my ($sKey, $sValue);
		while (($sKey, $sValue) = each(%hashBillMap))	# clear all related XML
			{
			$ACTINIC::B2B->SetXML($sValue, "");
			$ACTINIC::B2B->SetXML($sValue . "_SEP", "");
			}
		}
	#
	# Print the company contact information
	#
	my %hashCompanyMap = (
		'COMPANY_NAME'			=> 'COMPANY_NAME',
		'CONTACT_SALUTATION'	=> 'COMPANY_SALUTATION',
		'CONTACT_NAME'			=> 'COMPANY_CONTACT_NAME',
		'CONTACT_JOB_TITLE'	=> 'COMPANY_CONTACT_TITLE',
		'ADDRESS_1'				=> 'COMPANY_CONTACT_ADDRESS1',
		'ADDRESS_2'				=> 'COMPANY_CONTACT_ADDRESS2',
		'ADDRESS_3'				=> 'COMPANY_CONTACT_ADDRESS3',
		'ADDRESS_4'				=> 'COMPANY_CONTACT_ADDRESS4',
		'POSTAL_CODE'			=> 'COMPANY_CONTACT_POSTCODE',
		'COUNTRY'				=> 'COMPANY_CONTACT_COUNTRY',
		'PHONE'					=> 'COMPANY_CONTACT_PHONE',
		'FAX'						=> 'COMPANY_CONTACT_FAX',
		'EMAIL'					=> 'COMPANY_CONTACT_EMAIL',
		'WEB_SITE_URL'			=> 'COMPANY_CONTACT_WEBSITE',
		);
	SetXMLFromHash(\%hashCompanyMap, \%$::g_pSetupBlob);
	#
	# Print the shopping cart
	#
	my ($nColumns, $nColumnsToPrice);
	$nColumns = 0;
	$ACTINIC::B2B->SetXML('CART', ACTINIC::GetPhrase(-1, 165));
	if ($$::g_pSetupBlob{PRICES_DISPLAYED})		# if prices are visible
		{														# display the currency
		$ACTINIC::B2B->AppendXML('CART', " (" . ACTINIC::GetPhrase(-1, 96, $$::g_pCatalogBlob{'CURRENCY'}) . ")");
		}
	$ACTINIC::B2B->AppendXML('CART', "\r\n");
	#
	# Now define the order detail table.  First the product reference column if it applies
	#
	my $nProdRefColumnWidth = 0;
	if ($$::g_pSetupBlob{PROD_REF_COUNT} > 0)		# if the references are significant
		{
		$nProdRefColumnWidth = $$::g_pSetupBlob{PROD_REF_COUNT} > (length ACTINIC::GetPhrase(-1, 97)) ?
			$$::g_pSetupBlob{PROD_REF_COUNT} : (length ACTINIC::GetPhrase(-1, 97));
		$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%-%d.%ds ", $nProdRefColumnWidth, $nProdRefColumnWidth),
			ACTINIC::GetPhrase(-1, 97)));				# display them
		$nColumns++;
		}
	#
	# Now the product description column
	#
	my $nDescriptionColumnWidth = 30 > (length ACTINIC::GetPhrase(-1, 98)) ? 30 : (length ACTINIC::GetPhrase(-1, 98));
	$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%-%d.%ds ", $nDescriptionColumnWidth, $nDescriptionColumnWidth),
		ACTINIC::GetPhrase(-1, 98)));					# description
	$nColumns++;
	#
	# Next the quantity column
	#
	my $nQuantityColumnWidth = 6 > (length ACTINIC::GetPhrase(-1, 159)) ? 6 : (length ACTINIC::GetPhrase(-1, 159));
	$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds ", $nQuantityColumnWidth),
		ACTINIC::GetPhrase(-1, 159)));					# quantity
	$nColumns++;
	#
	# Finally the prices if the prices are displayed
	#
	my $nPriceColumnWidth = 0;
	if ($$::g_pSetupBlob{PRICES_DISPLAYED})		# if prices are shown
		{
		#
		# Make the price columns 11 characters minimum but if the price or cost description is larger
		# than 11 characters, use the length of the descriptions.
		#
		$nPriceColumnWidth = 11;
		$nPriceColumnWidth = $nPriceColumnWidth > (length ACTINIC::GetPhrase(-1, 99)) ? $nPriceColumnWidth :
			length ACTINIC::GetPhrase(-1, 99);
		$nPriceColumnWidth = $nPriceColumnWidth > (length ACTINIC::GetPhrase(-1, 100)) ? $nPriceColumnWidth :
			length ACTINIC::GetPhrase(-1, 100);
		$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds ", $nPriceColumnWidth),
			ACTINIC::GetPhrase(-1, 99)));				# unit price
		$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds ", $nPriceColumnWidth),
			ACTINIC::GetPhrase(-1, 100)));				# total price
		$nColumns += 2;
		}
	$ACTINIC::B2B->AppendXML('CART', "\r\n");
	$ACTINIC::B2B->AppendXML('CART', "-" x ($nProdRefColumnWidth + 2 + $nDescriptionColumnWidth + 2 + $nQuantityColumnWidth + 2 + 2 * ($nPriceColumnWidth + 2)));
	#
	# now process the list
	#
	#
	# Setup formats
	#
	my @TableFormat;
	my $nCol = 0;
	if ($$::g_pSetupBlob{PROD_REF_COUNT} > 0)		# if the references are significant
		{
		$TableFormat[$nCol++] = sprintf(" %%-%ds ",$nProdRefColumnWidth);						# Reference
		}
	$TableFormat[$nCol++] = sprintf(" %%-%ds ",$nDescriptionColumnWidth);					# Description
	$TableFormat[$nCol++] = sprintf(" %%%ds ", $nQuantityColumnWidth);						# Quantity
	$TableFormat[$nCol++] = sprintf(" %%%ds ", $nPriceColumnWidth);							# Unit price
	$TableFormat[$nCol++] = sprintf(" %%%ds ", $nPriceColumnWidth);							# Line total
	#
	# Preprocess the cart data
	#
	my @aCartData;
	($Status, $Message, @aCartData) = ActinicOrder::PreprocessCartToDisplay($pCartList, $::TRUE);

	my $nCartIndex = 0;
	my ($pOrderDetail, $pProduct);
	my @aDownloadLinks;
	foreach $pOrderDetail (@aCartData)
		{
		my %CurrentItem = %$pOrderDetail;				# get the next item
		#
		# Preprocess components
		#
		my @aComponentsIncluded;
		my @aComponentsSeparated;
		my $pComponent;
		foreach $pComponent (@{$CurrentItem{'COMPONENTS'}})
			{
			if ($pComponent->{'SEPARATELINE'})		# component displayed in separate order line
				{
				push @aComponentsSeparated, $pComponent;
				}
			else												# component included in product's order line
				{
				push @aComponentsIncluded, $pComponent;
				}
			}
		#
		# locate this product's object.
		#
		$pProduct = $CurrentItem{'PRODUCT'};
		#
		# Check if product doesn't require orderline
		#
		my $bProductSupressed = $$pProduct{NO_ORDERLINE};
		my $pPrintTable;										# We build a table to help formatting
		my $nColumn = 0;
		#
		# Calculate effective quantity taking into account identical items in the cart
		#
		my $nEffectiveQuantity = ActinicOrder::EffectiveCartQuantity($pOrderDetail,$pCartList,\&ActinicOrder::IdenticalCartLines,undef);
		#
		# If the product is not supressed
		#
		my $nCurrentRow = 0;								# Start at the top

		$ACTINIC::B2B->AppendXML('CART', "\r\n");

		if (!$bProductSupressed)
			{
			#
			# Add product line
			#
			MailOrderLine( $$pProduct{REFERENCE},
								$$pProduct{NAME},
								$$pOrderDetail{QUANTITY},
								$CurrentItem{'PRICE'},
								$CurrentItem{'COST'},
								$nDescriptionColumnWidth,
								@TableFormat
								);
			if ($CurrentItem{'DDLINK'} ne "")
				{
				push @aDownloadLinks, MailDownloadLink($$pProduct{REFERENCE}, $$pProduct{NAME}, $CurrentItem{'DDLINK'});
				}
			}
		#
		# Add components included this order line
		#
		foreach $pComponent (@aComponentsIncluded)
			{
			#
			# If there wasn't order line for the product then the prices should be displayed here
			#
			my $sPrice;
			my $sCost;
			if ($bProductSupressed)
				{
				$bProductSupressed = $::FALSE;		# be sure we don't get here again

				if ($$::g_pSetupBlob{'PRICES_DISPLAYED'})	# if prices are shown
					{
					$sPrice = $CurrentItem{'PRICE'} ? $CurrentItem{'PRICE'} : "--";
					$sCost  = $CurrentItem{'COST'}  ? $CurrentItem{'COST'}  : "--";
					}
				}
			#
			# Add component line
			#
			MailOrderLine( $pComponent->{'REFERENCE'},
								$pComponent->{'NAME'},
								$pComponent->{'QUANTITY'},
								$sPrice,
								$sCost,
								$nDescriptionColumnWidth,
								@TableFormat
								);
			#
			# we include the DD link, if the payment was made
			#
			if ($pComponent->{'DDLINK'} ne "")
				{
				push @aDownloadLinks, MailDownloadLink($pComponent->{'REFERENCE'}, $pComponent->{'NAME'}, $pComponent->{'DDLINK'});
				}
			}
		#
		# Add other and date info prompts if defined
		#
		if (length $$pProduct{'OTHER_INFO_PROMPT'} > 0)
			{
			MailOrderLine( "",
								$$pProduct{'OTHER_INFO_PROMPT'} . "\r\n  " . $CurrentItem{'INFO'},
								"",
								"",
								"",
								$nDescriptionColumnWidth,
								@TableFormat
								);
			}
		if (length $$pProduct{'DATE_PROMPT'} > 0)
			{
			my ($nDay, $nMonth, $sMonth, $nYear, $sDate);
			if ($CurrentItem{"DATE"} =~ /(\d{4})\/0?(\d{1,2})\/0?(\d{1,2})/)
				{
				$nYear = $1;
				$nMonth = $2;
				$nDay = $3;
				$sMonth = $::g_InverseMonthMap{$nMonth};
				$sDate = ACTINIC::FormatDate($nDay, $sMonth, $nYear);
				}
			else
				{
				$sDate = $CurrentItem{"DATE"};
				ACTINIC::RecordErrors(sprintf(ACTINIC::GetPhrase(-1, 2158, $$pProduct{'DATE_PROMPT'}) . " [%s]",
					$CurrentItem{"DATE"}), ACTINIC::GetPath());
				}
			MailOrderLine( "",
							$$pProduct{'DATE_PROMPT'} . "\r\n  " . $sDate,
							"",
							"",
							"",
							$nDescriptionColumnWidth,
							@TableFormat
							);
			}
		#
		# Add components excluded
		#
		foreach $pComponent (@aComponentsSeparated)
			{
			#
			# Add component line
			#
			MailOrderLine( $pComponent->{'REFERENCE'},
								$pComponent->{'NAME'},
								$pComponent->{'QUANTITY'},
								$pComponent->{'PRICE'},
								$pComponent->{'COST'},
								$nDescriptionColumnWidth,
								@TableFormat
								);
			#
			# we include the DD link, if the payment was made
			#
			if ($pComponent->{'DDLINK'} ne "")
				{
				push @aDownloadLinks, MailDownloadLink($pComponent->{'REFERENCE'}, $pComponent->{'NAME'}, $pComponent->{'DDLINK'});
				}
			}
		#
		# Handle product adjustments
		#
		my $parrProductAdjustments = $pCartObject->GetConsolidatedProductAdjustments($nCartIndex);
		my $parrAdjustDetails;
		$nCurrentRow = 0;											# Start at the top
		$pPrintTable = [];										# Start again here
		foreach $parrAdjustDetails (@$parrProductAdjustments)
			{
			#
			# Format the price and encode the price
			#
			@Response = ActinicOrder::FormatPrice($parrAdjustDetails->[$::eAdjIdxAmount], $::TRUE, $::g_pCatalogBlob);
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
				}
			MailOrderLine( '',
								$parrAdjustDetails->[$::eAdjIdxProductDescription],
								"",
								"",
								$Response[2],
								$nDescriptionColumnWidth,
								@TableFormat
								);
			}
		$nCartIndex++;										# increment cart index
		}

	if ($$::g_pSetupBlob{PRICES_DISPLAYED} &&		# if prices are displayed
		 $nTotal > 0)	 									# and there is something to show
		{														# display the cost panel
		$ACTINIC::B2B->AppendXML('CART', "=" x ($nProdRefColumnWidth + 2 + $nDescriptionColumnWidth + 2 + $nQuantityColumnWidth + 2 + 2 * ($nPriceColumnWidth + 2)));
		$ACTINIC::B2B->AppendXML('CART', "\r\n");
		#
		# Determine the width of the text column (consumes all but the "total" price column
		#
		my $nTextColumnWidth;
		if ($nProdRefColumnWidth)
			{
			$nTextColumnWidth += $nProdRefColumnWidth + 2;
			}
		$nTextColumnWidth += $nDescriptionColumnWidth + 2;
		$nTextColumnWidth += $nQuantityColumnWidth + 2;
		if ($nPriceColumnWidth)
			{
			$nTextColumnWidth += $nPriceColumnWidth + 2;
			}
		$nTextColumnWidth -= 2;							# leave spaces
		#
		# Sub Total
		#
		$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), ACTINIC::GetPhrase(-1, 101) . ":"));
		$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sSubTotal));
		#
		# Handle order adjustments
		#
		my $parrFinalAdjustments = $pCartObject->GetFinalAdjustments();
		my @arrAdjustments = @{$pCartObject->GetOrderAdjustments()};
		#
		# Combine order and final adjustments
		#
		push @arrAdjustments, @{$pCartObject->GetFinalAdjustments()};
		my $parrAdjustDetails;
		foreach $parrAdjustDetails (@arrAdjustments)
			{
			my $FullDescr = $parrAdjustDetails->[$::eAdjIdxProductDescription];
			my ($parrProductDescription, $nLineCount) =
				ActinicOrder::WrapText($FullDescr, $nTextColumnWidth - 2);	# Word wrap description
			#
			# See if the description wraps onto extra lines
			#
			my $bWrapped = (@$parrProductDescription > 1);
			my $sDescriptionLine = $parrProductDescription->[0];
			if(!$bWrapped)									# add a colon if we didn't wrap the adjustment description
				{
				$sDescriptionLine .= ':';
				}
			$ACTINIC::B2B->AppendXML('CART',
				sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth),
					$sDescriptionLine));
			#
			# Format the price and encode the price
			#
			@Response = ActinicOrder::FormatPrice($parrAdjustDetails->[$::eAdjIdxAmount], $::TRUE, $::g_pCatalogBlob);
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
				}
			$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $Response[2]));
			my $i;
			for($i = 1; $i < @$parrProductDescription; $i++)					# Add rest of description lines
				{
				$sDescriptionLine = $parrProductDescription->[$i];
				if($i == @$parrProductDescription - 1)
					{
					$sDescriptionLine .= ':';
					}
				$ACTINIC::B2B->AppendXML('CART',
					sprintf(sprintf(" %%%d.%ds\r\n", $nTextColumnWidth, $nTextColumnWidth), ' ' . $parrProductDescription->[$i]));
				}
			}
		#
		# Shipping if any
		#
		if ($$::g_pSetupBlob{MAKE_SHIPPING_CHARGE} && $nShipping > 0) # if the shipping exists
			{
			@Response = ActinicOrder::CallShippingPlugIn($pCartList, $nSubTotal); # get the shipping description
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
				}
			elsif (${$Response[2]}{GetShippingDescription} != $::SUCCESS)
				{
				return ( ${$Response[2]}{GetShippingDescription}, ${$Response[3]}{GetShippingDescription});
	         }
   		my $sShipDescription = $Response[5];

		   my $sShippingText = ACTINIC::GetPhrase(-1, 102);
		   if ($sShipDescription ne "")				# if there is a shipping description
			   {
			   $sShippingText .= " ($sShipDescription)"; # add the description to the total line
			   }
         $sShippingText .= ":";
		   $ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), $sShippingText));
		   $ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sShipping));
         }
		#
      # Handling if any
      #
		if ($$::g_pSetupBlob{MAKE_HANDLING_CHARGE} && $nHandling != 0)	# if the handling exists
			{
			$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), ACTINIC::GetPhrase(-1, 199) . ":"));
			$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sHandling));
			}
		#
		# Taxes - we display taxes before the total if prices don't include tax or
		# the user has exemption (and the tax is negative)
		#
      if ($nTax1 != 0)	# if the tax exists
			{													# add the tax
			if (!ActinicOrder::PricesIncludeTaxes() || $nTax1 < 0)
				{
				my $sTaxName = ActinicOrder::GetTaxName('TAX_1');
				if ($nTax1 < 0)
					{
					$sTaxName = 'Exempted ' . $sTaxName;
					}
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), $sTaxName . ":"));
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sTax1));
				}
			}
		if ($nTax2 != 0)	# if the second tax exists
			{													# add the second tax
			if (!ActinicOrder::PricesIncludeTaxes() || $nTax2 < 0)
				{
				my $sTaxName = ActinicOrder::GetTaxName('TAX_2');
					
				if ($nTax2 < 0)
					{
					$sTaxName = 'Exempted ' . $sTaxName;
					}
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), $sTaxName . ":"));
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sTax2));
				}
			}
		#
		# Total
		#
		$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), ACTINIC::GetPhrase(-1, 103) . ":"));
		$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sTotal));
		#
		# Handle taxes applied with price including taxes
		#
		if (ActinicOrder::PricesIncludeTaxes())
			{
			if ($nTax1 > 0)								# if we have a positive tax 1
				{
				my $sTaxName = ActinicOrder::GetTaxName('TAX_1');
				$sTaxName = 'Including ' . $sTaxName;
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), $sTaxName . ":"));
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sTax1));
				}
			if ($nTax2 > 0)								# if we have a positive tax 2
				{
				my $sTaxName = ActinicOrder::GetTaxName('TAX_2');
				$sTaxName = 'Including ' . $sTaxName;
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%d.%ds ", $nTextColumnWidth, $nTextColumnWidth), $sTaxName . ":"));
				$ACTINIC::B2B->AppendXML('CART', sprintf(sprintf(" %%%ds\r\n", $nPriceColumnWidth), $sTax2));
				}
			}		
		#
		# Handle any extra shipping information
		#
		if($::s_Ship_nSSPProviderID != -1 &&
			$$::g_pSSPSetupBlob{$::s_Ship_nSSPProviderID} &&
			$$::g_pSSPSetupBlob{$::s_Ship_nSSPProviderID}{'RATE_DISCLAIMER'})
			{
			$ACTINIC::B2B->AppendXML('CART',
				sprintf("\r\n%s\r\n",
					ACTINIC::SplitString($$::g_pSSPSetupBlob{$::s_Ship_nSSPProviderID}{'RATE_DISCLAIMER'},
					70,
					"\r\n")));
			}
   	}
	if (@aDownloadLinks > 0)
		{
		$ACTINIC::B2B->AppendXML('CART', "\r\n" . ACTINIC::GetPhrase(-1, 2250, $$::g_pSetupBlob{'DD_EXPIRY_TIME'}));
		my $sLine;
		foreach $sLine (@aDownloadLinks)
			{
			$ACTINIC::B2B->AppendXML('CART', "\r\n\r\n" . $sLine);
			}
		}
	#
	# Handle any extra shipping footer information
	#
	if($::s_Ship_bDisplayExtraCartInformation == $::TRUE)
		{
		if($::s_Ship_nSSPProviderID != -1 &&										# If this is an SSP order
			$$::g_pSSPSetupBlob{$::s_Ship_nSSPProviderID} &&					# and the provider is defined
			$$::g_pSSPSetupBlob{$::s_Ship_nSSPProviderID}{'TRADEMARKS'})	# and ther's some trademarks
			{
			$ACTINIC::B2B->AppendXML('EXTRAFOOTER',
				sprintf("\r\n%s\r\n",
					ACTINIC::SplitString($$::g_pSSPSetupBlob{$::s_Ship_nSSPProviderID}{'TRADEMARKS'},
					70,
					"\r\n")));
			}
		}
	else
		{
		$ACTINIC::B2B->AppendXML('EXTRAFOOTER', '');
		}
   #
   # Read the template
   #
   my $sFilename = ACTINIC::GetPath() . $sTemplateFile;
	unless (open (TEMPLATE, "<$sFilename"))		# open the file
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sFilename, $!));
		}

	my $sBody;
	{
	local $/;
   $sBody = <TEMPLATE>;								   # read the entire file
	}
	close (TEMPLATE);									   # close the file
	#
	# Restore currency symbol usage flag
	#
	$::USEINTLCURRENCYSYMBOL = $::FALSE;
	#
   # Make sure the email message lines are properly terminated
   #
   $sBody =~ s/([^\r])\n/$1\r\n/g;
	#
	# Load XML parser
	#
	eval
		{
		require <Actinic:Variable Name="ActinicPXMLPackage"/>;	# load parser library
		};
	if ($@)													# library load failed?
		{
		return $@;											# if so then return the error message
		}
	#
   # Now build the message
   #
	my $Parser = new ACTINIC_PXML();
	my $pDummy;
	($sBody, $pDummy) = $Parser->Parse($sBody);	# do the insert
	#
	# Send email copies to the specified addresses
	# Loop over the third-party addresses and send the composed mail for each of them
	#
	my $sRecipient;
	if (defined $sMailFile &&
		length $sMailFile > 0)							# if we have to save it to file, to send it when the auth call arrives from PayPal or Nochex
		{
		unless (open (MFILE, ">$sMailFile"))		# open the file
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sFilename, $!));
			}
		foreach $sRecipient (@{$paRecipients})		# print hte recepients in to the first line
			{
			print MFILE $sRecipient . ",";
			}
		print MFILE "\n";
		print MFILE ACTINIC::GetPhrase(-1, 234) . " $::g_InputHash{ORDERNUMBER}" . "\n";	# print the subject
		print MFILE $sBody;								# the body of the mail
		close MFILE;
		}
	else
		{
		foreach $sRecipient (@{$paRecipients})
			{
			if ($sRecipient ne "")							# avoid empty email addresses
				{
				($Status, $Message) = ACTINIC::SendMail($::g_sSmtpServer,
											$sRecipient,
											ACTINIC::GetPhrase(-1, 234) . " $::g_InputHash{ORDERNUMBER}",
											$sBody,
											$$::g_pSetupBlob{EMAIL});
				if($Status != $::SUCCESS)
					{
					return ($::FAILURE, $Message);
					}
				}
			}
		}
	return ($::SUCCESS, "");
	}

#######################################################
#
# MailOrderLine - generate the order line for the
#		order confirmation mail
#
# Input:		0 - product reference
#				1 - product description
#				2 - quantity
#				3 - item price
#				4 - cost
#				5 - width of description column
#				6 - array of table format
#
# Expects:	%g_SetupBlob should be defined
#
# Returns:	nothing
#
# Author:	Zoltan Magyar
#
#######################################################

sub MailOrderLine
	{
	my ($sProdRef, $sName, $sQuantity, $sPrice, $sCost, $nDescriptionColumnWidth, @TableFormat) = @_;
	my $pPrintTable;
	my $nColumn = 0;
	my $nCurrentRow = 0;								# Start at the top
	#
	# Product reference
	#
	if ($$::g_pSetupBlob{PROD_REF_COUNT} > 0)		# if the references are significant
		{
		$pPrintTable->[$nColumn++]->[0] = $sProdRef;				# Product reference
		}
	#
	# Product description if the product line is not supressed
	#
	$sName =~ s/(!!\<|\>!!)//g;						# I hope product names don't contain embedded HTML, but if they do, try to just strip the boundary markers
	my ($pProductDescription, $nLineCount) = ActinicOrder::WrapText($sName, $nDescriptionColumnWidth);	# Word wrap description

	foreach (@$pProductDescription)																		# Add all description lines
		{
		$pPrintTable->[$nColumn]->[$nCurrentRow++] = $_;											# Keep counting rows
		}
	$nColumn++;																									# Finished, next column
	#
	# Quantity
	#
	$pPrintTable->[$nColumn++]->[0] = $sQuantity;
	#
	# Now the prices if they are displayed
	#
	if (!$$::g_pSetupBlob{'PRICES_DISPLAYED'})	# if prices are shown
		{
		$sPrice = "";
		$sCost  = "";
		}

	$pPrintTable->[$nColumn++]->[0] = $sPrice;	# unit price
	$pPrintTable->[$nColumn++]->[0] = $sCost;		# line total

	my $nLine;
	for( $nLine=0; $nLine < $nCurrentRow; $nLine++ )				# Store the whole table
		{
		my $nCol;
		for( $nCol=0; $nCol < $nColumn; $nCol++ )
			{
			$ACTINIC::B2B->AppendXML('CART', sprintf($TableFormat[$nCol], $pPrintTable->[$nCol]->[$nLine]));
			}
		$ACTINIC::B2B->AppendXML('CART', "\r\n");					# Terminate the line
		}
	}

#######################################################
#
# MailDownloadLink - generate the download link line for the
#		order confirmation mail
#
# Input:		0 - product reference
#				1 - product description
#				2 - quantity
#
# Expects:	%g_SetupBlob should be defined
#
# Returns:	0 - the formatted line
#
# Author:	Zoltan Magyar
#
#######################################################

sub MailDownloadLink
	{
	my ($sProdRef, $sName, $sLink) = @_;
	#
	# Product reference
	#
	my $sLine;
	if ($$::g_pSetupBlob{PROD_REF_COUNT} > 0)		# if the references are significant
		{
		$sLine = $sProdRef . " ";						# Product reference
		}
	$sLine .= $sName . "\r\n" . $sLink;
	return $sLine;
	}

#######################################################
#
# GeneratePresnetMail - generate the Presnet email
#
# Expects:	%::g_InputHash, and %g_SetupBlob
#					should be defined
#
# Returns:	($ReturnCode, $Error)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#
#######################################################

sub GeneratePresnetMail
	{
	my ($sTextMailBody, @Response, $Status, $Message);
	@Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# error so return empty string
		}
	my $pCartObject = $Response[2];
	my $pCartList = $pCartObject->GetCartList();
	#
	# add order number
	#
	$sTextMailBody = "Order#: $::g_InputHash{ORDERNUMBER}\r\n";
	#
	# add company name
	#
	$sTextMailBody .= "Shop Name: $$::g_pSetupBlob{COMPANY_NAME}\r\n";
	#
	# add company email address
	#
	$sTextMailBody .= "Shop's Email: $$::g_pSetupBlob{EMAIL}\r\n";
	#
	# add sender's email address
	#
	$sTextMailBody .= "Sender's Email: $::g_BillContact{EMAIL}\r\n";
	#
	# add sender's town/city
	#
	$sTextMailBody .= "Sender's Town/City: $::g_BillContact{ADDRESS4}\r\n";
	#
	# add sender's country
	#
	$sTextMailBody .= "Sender's Country: $::g_BillContact{COUNTRY}\r\n";
	#
	# add recipient's town/city
	#
	$sTextMailBody .= "Recipient's Town/City: $::g_ShipContact{ADDRESS4}\r\n";
	#
	# add recipient's country
	#
	$sTextMailBody .= "Recipient's Country: $::g_ShipContact{COUNTRY}\r\n";
	#
	# add the referring source
	#
	$sTextMailBody .= "Referrer: " . GetGeneralUD3() . "\r\n";
	#
	# add currency
	#
	@Response = ACTINIC::EncodeText($$::g_pCatalogBlob{'SINTLSYMBOLS'}); # print the currency
	$sTextMailBody .= "Currency: $Response[1]\r\n";
	#
	# add order value
	#
	@Response = $pCartObject->SummarizeOrder($::FALSE);		# calculate the order total
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my ($Ignore0, $Ignore1, $nSubTotal, $nShipping, $nTax1, $nTax2, $nTotal, $nShippingTax1, $nShippingTax2,
		$nHandling, $nHandlingTax1, $nHandlingTax2) = @Response;
	#
	# convert currency into highest unit
	#
	my ($nIntegral, $nFractional, $nFactor);
	$nFactor = 10 ** $$::g_pCatalogBlob{'ICURRDIGITS'};
	if ($nFactor == 1)									# only one currency denomination
		{
		$sTextMailBody .= "Order Value: $nTotal\r\n";
		}
	else														# format as 9.99 or whatever
		{
		my ($sFormat, $sFormattedTotal);
		$sFormat = sprintf("%%d.%%0%dd", $$::g_pCatalogBlob{'ICURRDIGITS'});
		$sFormattedTotal = sprintf($sFormat,
			$nTotal / $nFactor, ACTINIC::Modulus($nTotal, $nFactor) );
		$sTextMailBody .= "Order Value: $sFormattedTotal\r\n";
		}
	#
	# add the order date and time
	#
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst, $sDate);
	($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime(time);	# platform independent time
	$mon++;													# make month 1 based
	$year += 1900;											# make year AD based
	$sDate = sprintf("%02d/%02d/%4d %2.2d:%2.2d GMT", $mday, $mon, $year, $hour, $min);
	$sTextMailBody .= "Order Date & time: $sDate\r\n";
	#
	# add the latest delivery date
	#
	$sTextMailBody .= "Latest delivery date: $::g_ShipContact{USERDEFINED}\r\n";
	#
	# now process the list
	#
	my ($pOrderDetail, %CurrentItem, $pProduct, $sLine);
	foreach $pOrderDetail (@$pCartList)
		{
		%CurrentItem = %$pOrderDetail;				# get the next item
		#
		# Locate the section blob
		#
		my $sSectionBlobName;
		($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($CurrentItem{SID}); # retrieve the blob name
		if ($Status == $::FAILURE)
			{
			return ($Status, $Message);
			}
		#
		# locate this product's object.
		#
		@Response = ACTINIC::GetProduct($CurrentItem{"PRODUCT_REFERENCE"}, $sSectionBlobName,
												  ACTINIC::GetPath());	# get this product object
		($Status, $Message, $pProduct) = @Response;
		if ($Status == $::NOTFOUND)					# the item has been removed from the catalog
			{
			#no-op - deleted product is OK here
			}
		if ($Status == $::FAILURE)
			{
			return (@Response);
			}
		$sLine = sprintf("Item: %-21s", $$pProduct{'REFERENCE'});
		$sLine .= $$pProduct{'NAME'};
		$sTextMailBody .= "$sLine\r\n";
		}

	my ($sSubject, $sEmailRecpt);
	#
	# build the subject line
	#
	$sSubject = $$::g_pSetupBlob{COMPANY_NAME};
	#
	# set the mail recipient
	#
	$sEmailRecpt .= 'orderorder@pres.net';				# set the recipient

	($Status, $Message) = ACTINIC::SendMail($::g_sSmtpServer,
								$sEmailRecpt,
								$sSubject,
								$sTextMailBody);
	if($Status != $::SUCCESS)
		{
		return ($::FAILURE, $Message);
		}
	return ($::SUCCESS, "");
	}

#######################################################
#
# CallPlugInScript - call a plug-in script
#
# Params:	$sScriptName
#
# Returns:	0 - status
#				1 - error if any
#
#######################################################

sub CallPlugInScript
	{
	if ($#_ != 0)											# validate params
		{
 		ACTINIC::RecordErrors("CallPlugInScript, validate params:\n",
 									 ACTINIC::GetPath());
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'CallPlugInScript'), 0, 0);
		}
	my ($sScriptName) = @_;
	#
	# load the plug-in
	#
	my @Response = GetPlugInScript(ACTINIC::GetPath(), $sScriptName);
	if ($Response[0] != $::SUCCESS)					# couldn't load the script
		{
 		ACTINIC::RecordErrors("CallPlugInScript, could not load script:\n",
 									 ACTINIC::GetPath());
		return (@Response);								# bail out
		}

	my ($sScript) = $Response[2];
	#
	# Supply some basic values to the scripts
	#
	local $::sPath = ACTINIC::GetPath();
	#
	# Global string to return error messages from inside "eval"
	#
	$::sPlugInScriptError = '';
	#
	# load MD5 package as plug-in script may need it.
	#
	eval
		{
#&					ActinicProfiler::StartLoadRuntime('Digest::MD5');
		require Digest::MD5;								# Try loading MD5
#&					ActinicProfiler::EndLoadRuntime('Digest::MD5');
		import Digest::MD5 'md5_hex';
		};
	if ($@)
		{
#&					ActinicProfiler::StartLoadRuntime('DigestPerlMD5');
		require <Actinic:Variable Name="DigestPerlMD5"/>;
#&					ActinicProfiler::EndLoadRuntime('DigestPerlMD5');
		import Digest::Perl::MD5 'md5_hex';			# Use Perl version if not found
		}
	#
	# now execute the plug-in
	#
	eval($sScript);										# execute the script
	if ($@)													# error executing the script
		{
 		ACTINIC::RecordErrors("CallPlugInScript, execute: $@\n",
 									 ACTINIC::GetPath());
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 170, $@));
		}
	if ($::sPlugInScriptError)							# error reported by the script
		{
 		ACTINIC::RecordErrors("CallPlugInScript, report: $::sPlugInScriptError\n",
 									 ACTINIC::GetPath());
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 170, $::sPlugInScriptError));
		}
	return ($::SUCCESS, '');
	}

#######################################################
#
# GetPlugInScript - read and return the Plug-in	script
#
# Params:	0 - the path
#				1 - the script name
#
# Returns:	0 - status
#				1 - error message (if any)
#				2 - script
#
# Affects:	$::s_sOCCScript - the script
#
#######################################################

sub GetPlugInScript
	{
	if ($#_ < 1)											# validate params
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'GetOCCScript'), 0, 0);
		}
	my ($sPath) = $_[0];									# grab the path

	my ($sFilename) = $sPath . $_[1];
	my @Response = ACTINIC::ReadAndVerifyFile($sFilename);
	return (@Response);
	}

#######################################################
#
# AdjustTaxTreatment - adjust the tax treatment
#	according to the current exemption settings.
#
# Params:	0 - tax treatment
#
# Returns:	0 - modified tax treatment
#
#######################################################

sub AdjustTaxTreatment
	{
	my ($eTreatment) = @_;
	#
	# if the customer is exempt from tax 1, remove tax one from the tax treatment
	#
	if ($::g_TaxInfo{EXEMPT1})
		{
		if ($ActinicOrder::TAX1 == $eTreatment)
			{
			$eTreatment = $ActinicOrder::EXEMPT;
			}
		elsif ($ActinicOrder::BOTH == $eTreatment)
			{
			$eTreatment = $ActinicOrder::TAX2;
			}
		}
	#
	# if the customer is exempt from tax 2, remove tax 2 from the tax treatment
	#
	if ($::g_TaxInfo{EXEMPT2})
		{
		if ($ActinicOrder::TAX2 == $eTreatment)
			{
			$eTreatment = $ActinicOrder::EXEMPT;
			}
		elsif ($ActinicOrder::BOTH == $eTreatment)
			{
			$eTreatment = $ActinicOrder::TAX1;
			}
		}
	return ($eTreatment);
	}

#######################################################
#
# GetOCCValidationData - retrieve the OCC validation data
#		for an OCC_VALIDATE call
#
# Returns:	0 - return code
#				1 - error message
#				2 - validation data
#
#######################################################

sub GetOCCValidationData
	{
	my ($sText, @Response);
	#
	# get the cart contents
	#
	@Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# error so return empty string
		}
	my $pCartObject = $Response[2];
	my $pCartList = $pCartObject->GetCartList();
	#
	# Parse the advanced tax using the checkout information
	#
	ActinicOrder::ParseAdvancedTax();
	#
	# get the order total
	#
	@Response = $pCartObject->SummarizeOrder($::FALSE); # total the order
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	#
	#				2 - sub total
	#				3 - shipping
	#				4 - tax 1
	#				5 - tax 2
	#				6 - total
	#				7 - tax 1 on shipping (fraction of 4 that is
	#					due to shipping)
	#				8 - tax 2 on shipping (fraction of 5 that is
	#					due to shipping)
	#
	# return the amount
	#
	$sText = "AMOUNT=$Response[6]";
	#
	# return the currency
	#
	$sText .= "&CURRENCY=$$::g_pCatalogBlob{'SINTLSYMBOLS'}";
	#
	# calculate the conversion factor for the currency
	#
	my $nFactor = 100;
	my $nNumDigits = $::PriceFormatBlob{"ICURRDIGITS"};	# read the currency format values
	if(defined $nNumDigits)
		{
		$nFactor = (10 ** $nNumDigits);
		}
	#
	# return the conversion factor for the currency
	#
	$sText .= "&FACTOR=$nFactor";
	$sText .= "&ORDERNUMBER=$::g_PaymentInfo{'ORDERNUMBER'}";

	LogData("OCC_VALIDATE: $sText");
	return ($::SUCCESS, '', $sText);
	}

#######################################################
#
# NotifyOfError - Send email on serious error
#
# Params:	$sError	- error message
#				$bOmitMailDump	- whether to omit the dump
#
# Returns:	$sError - unchanged
#
# (rz)
#######################################################

sub NotifyOfError
	{
	my ($sError, $bOmitMailDump) = @_;

	if ($$::g_pSetupBlob{EMAIL} ne "" && $::g_sSmtpServer ne "")
		{
		my ($sPrompt1, $sPrompt2, $sPrompt3, $sPrompt4, $sPrompt5);
		#
		# Test if the prompts are defined
		#
		if (defined $$::g_pPromptList{"-1,1957"}{PROMPT})
			{													# and read them if so
			$sPrompt1 = ACTINIC::GetPhrase(-1, 1957);
			$sPrompt2 = ACTINIC::GetPhrase(-1, 1958);
			$sPrompt3 = ACTINIC::GetPhrase(-1, 1959);
			$sPrompt4 = ACTINIC::GetPhrase(-1, 2097);
			$sPrompt5 = ACTINIC::GetPhrase(-1, 2098);
			}
		else													# if the prompts are not defined then fall back to hard coded strings
			{
			$sPrompt1 = "Following error has been displayed to a customer:\n\n";
			$sPrompt2 = "\nDebugging information:\nInput Hash:\n";
			$sPrompt3 = "Error in Catalog order";
			$sPrompt4 = "Calling Address:";
			$sPrompt5 = "Calling Host:";
			}
		#
		# Assemble the basic message
		#
		my $sText;
		$sText .= $sPrompt1;
		$sText .= $sError . "\n\n";
		#
		# Dump the contact details for customer contact
		#
		$sText .= GetContactDetailsString();
		#
		# Note the referrer for later tracking.  It could be important for attacks
		#
		$sText .= $::ENV{REMOTE_HOST} ? "\n" . $sPrompt5 . " " . $::ENV{REMOTE_HOST} . "\n" : '';
		$sText .= $::ENV{REMOTE_ADDR} ? "\n" . $sPrompt4 . " " . $::ENV{REMOTE_ADDR} . "\n" : '';
		#
		# Dump Input Hash - the easiest way of finding out what happened
		#
		if(!$bOmitMailDump)
			{
			$sText .= $sPrompt2;
			my $sKey;
			foreach $sKey (sort keys %::g_InputHash)
				{
				my $sValue = $::g_InputHash{$sKey};
				#
				# Exclude card details from dump if they are there
				# The length of these fields maybe useful so just change
				# all the chars to *
				#
				if ($sKey =~ /^PAYMENTCARD/i)
					{
					$sValue =~ s/[a-z0-9]/\*/gi;
					}
				$sText .= $sKey . ' : "' . $sValue . "\"\n";
				}
			}

		my ($Status, $Message) = ACTINIC::SendMail($::g_sSmtpServer, $$::g_pSetupBlob{EMAIL},
			$sPrompt3, $sText);
		#
		# ignore return code (just record the error)
		#
		if ($Status != $::SUCCESS)
			{
			ACTINIC::RecordErrors($Message, ACTINIC::GetPath());
			}
		}
	return $sError;
	}

##################################################################################
##################################################################################
#
# ACTINIC AddressBook functions
#
##################################################################################
##################################################################################

############################################################
#
# CreateAddressBook - Create Address Book
#
# Must be called after reading and parsing input and before
# reading blobs.
# Only minimal set of arguments must be specified in new() (see below)
# Other parameters may be specified using Set() method after
# blobs have been read (see ConfigureAddressBook() below)
#
############################################################

sub CreateAddressBook
	{
	if( $ACTINIC::B2B->Get('UserDigest') )											# B2B mode
		{
		return;
		}
	#
	# Load Address Book library
	#
	eval 'require <Actinic:Variable Name="AddressBookPackage"/>;';
	#
	# Bomb out if the library load failed
	#
	if ( $@ )												# If there isn't an error message
		{
		ACTINIC::ReportError($@, ACTINIC::GetPath());
		}
	#
	#   End of ADDRESS BOOK eval. Now create Address Book Object
	#
	$::ACT_ADB = ADDRESS_BOOK->new(
											 FormPrefix			=>	'DELIVER',
											 FormNames 			=> [	'NAME', 'FIRSTNAME',
																			'LASTNAME', 'ADDRESS1',
												 							'JOBTITLE',		'COMPANY',
																			'ADDRESS2',		'ADDRESS3',
																			'ADDRESS4',		'POSTALCODE',
																			'COUNTRY',		'PHONE',
																			'FAX',			'EMAIL',
																			'USERDEFINED',	'SALUTATION'	],
											 LocationInfoNames=> [	'DELIVERY_REGION_CODE',
												 							'DELIVERY_COUNTRY_CODE',
												 							'DELIVERPOSTALCODE'	],
											 DeliveryFormHash => 	\%::g_ShipContact,
											 LocationHash		=> 	\%::g_LocationInfo,
											 InputFormHash	 	=> 	\%::g_InputHash,
											 Nnam_1				=> 	'NAME',
											 Nnam_2				=> 	'ADDRESS1',
											);
	#
	# If we are not adding current address to Address book 
	# then Address book should be initialized here 
	# to populate the address form values initially 
	#	
	if (!defined($::g_InputHash{ADBADD}))
		{
		$::ACT_ADB->Init();
		}	
	}

############################################################
#
#  ConfigureAddressBook - configure address book
#  Sets values of text messages in address book
#  Address book object has to be created first
#
#  Ryszard Zybert  Mar 14 10:23:51 GMT 2000
#
#  Copyright (c) Actinic Software Ltd (2000)
#
############################################################

sub ConfigureAddressBook
	{
	#
	# Deal with fist/last names
	#
	if ($$::g_pSetupBlob{SHOPPER_NAME_HANDLING_MODE} eq 1)	# first name/ last name handling
		{
		$::g_ShipContact{'NAME'}	=  $::g_ShipContact{'FIRSTNAME'}.' '.$::g_ShipContact{'LASTNAME'};
		$::g_ShipContact{'NAME'}	=~ s/(.{0,$::g_pFieldSizes->{'NAME'}}).*/$1/;	# trim to max field size
		$::g_InputHash{'DELIVERNAME'}	=  $::g_InputHash{'DELIVERFIRSTNAME'}.' '.$::g_InputHash{'DELIVERLASTNAME'};
		$::g_InputHash{'DELIVERNAME'}	=~ s/(.{0,$::g_pFieldSizes->{'NAME'}}).*/$1/;	# trim to max field size
		}
	$::ACT_ADB->Set(
						 OneAddressMessage 	 => 	ACTINIC::GetPhrase(-1, 271),
						 MoreAddressesMessage => 	ACTINIC::GetPhrase(-1, 272),
						 StatusMessage 		 => 	ACTINIC::GetPhrase(-1, 273),
						 MaxAddressesWarning  => 	ACTINIC::GetPhrase(-1, 274, ACTINIC::GetPhrase(-1, 1971, $::g_sRequiredColor),ACTINIC::GetPhrase(-1, 1970)),
						 NoAddressesMessage 	 => 	ACTINIC::GetPhrase(-1, 275),
						 AddMessage 		    => 	ACTINIC::GetPhrase(-1, 276),
						 DeleteLabel 		    => 	ACTINIC::GetPhrase(-1, 277),
						 Action			       =>	$::g_InputHash{'ACTION'},
						 Sequence		       =>	$::g_InputHash{'SEQUENCE'}
						);
	$::ACT_ADB->Init();
	}

##################################################################################
##################################################################################
#
# END --- ACTINIC AddressBook functions --- END
#
##################################################################################
##################################################################################

#######################################################
#
# NotifyMallAdministratorOfNewOrder - pass the new
#	order information along to the mall adminstrator
#	to track billing
#
# Returns:	0 - $::SUCCESS or $::FAILURE
#				1 - undef or error message
#
#######################################################

sub NotifyMallAdministratorOfNewOrder
	{
#&	ActinicProfiler::StartLoadRuntime('MallInterfaceLayer');
	eval 'require MallInterfaceLayer;';
#&	ActinicProfiler::EndLoadRuntime('MallInterfaceLayer');
	if ($@)  												# the interface module does not exist
		{
		return($::SUCCESS);								# no processing is necessary
		}
	#
	# The mall admin is listening - tell them about the new order
	#
	return (MallInterfaceLayer::NewOrder(ACTINIC::GetPath(), $::g_InputHash{ORDERNUMBER}, $::g_InputHash{SHOP}));	# pass the word on
	}

#######################################################
#
# PrepareOrderTaxOpaqueData - prepare the order tax opaque data
#
# Input:	$sKeyPrefix - prefix for keys in the tax blob
#
# Returns:	0 - $::SUCCESS or $::FAILURE
#				1 - undef or error message
#				2 - tax opaque data
#
#######################################################

sub PrepareOrderTaxOpaqueData
	{
	my($sKeyPrefix) = @_;
	my $sKey = $sKeyPrefix . 'TAX_OPAQUE_DATA';
	my ($nTaxID, $sOpaqueData);
	foreach $nTaxID (sort keys %$::g_pTaxesBlob)
		{
		$sOpaqueData .= "$nTaxID\t$$::g_pTaxesBlob{$nTaxID}{$sKey}\n";
		}
	return($::SUCCESS, '', $sOpaqueData);
	}

#######################################################
#
# SetXMLFromHash - add specific hash items to the
# XML object.
#
# Input:		0 - \%HashID - Hash key => VarTable Key map
#				1 - \%Hash - has of values
#
# Returns:	0 - $::SUCCESS or $::FAILURE
#				1 - undef or error message
#
# Author: Zoltan Magyar
#
#######################################################

sub SetXMLFromHash
	{
	my ($pHashID, $pHash) = @_;
	my ($sKey, $sValue);
	while (($sKey, $sValue) = each(%$pHashID))
		{
		if ($$pHash{$sKey} eq "")						# is it empty?
			{													# clear XML tags
			$ACTINIC::B2B->SetXML($sValue, "");
			$ACTINIC::B2B->SetXML($sValue . "_SEP", "");
			}
		else													# otherwise add correct tags
			{
			$ACTINIC::B2B->SetXML($sValue, $$pHash{$sKey} . " ");
			$ACTINIC::B2B->SetXML($sValue . "_SEP", "\r\n");
			}
		}
	return($::SUCCESS, '');
	}

#######################################################
#
# EvaluatePaypalPro - get our paypal pro library and get it included
#
# Author: Zoltan Magyar
#
#######################################################

sub EvaluatePaypalPro
	{
	#
	# Set the payment to paypal to get the correct PSP script
	#
	$::g_PaymentInfo{'METHOD'} = $::PAYMENT_PAYPAL_PRO;
	my @Response = GetOCCScript(ACTINIC::GetPath());
	$::g_PaymentInfo{'METHOD'} = $::PAYMENT_CREDIT_CARD;

	if ($Response[0] != $::SUCCESS)					# couldn't load the script
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());	# bail out
		}

	my ($sScript) = $Response[2];
	#
	# now execute the plug-in
	#
	if (eval($sScript) != $::SUCCESS)				# execute the script
		{
		ACTINIC::ReportError($@, ACTINIC::GetPath());
		}
	#
	# Decrypt account
	#
	$::PAYPAL_USER = DecryptPPDetails($::PAYPAL_USER);
	$::PAYPAL_PWD = DecryptPPDetails($::PAYPAL_PWD);
	}

#######################################################
#
# EvaluatePaypalEC - get our paypal pro library and get it included
#
# Author: Zoltan Magyar
#
#######################################################

sub EvaluatePaypalEC
	{
	#
	# Set the payment to paypal to get the correct PSP script
	#
	$::g_PaymentInfo{'METHOD'} = $::PAYMENT_PAYPAL_EC;
	my @Response = GetOCCScript(ACTINIC::GetPath());
	$::g_PaymentInfo{'METHOD'} = $::PAYMENT_CREDIT_CARD;

	if ($Response[0] != $::SUCCESS)					# couldn't load the script
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());	# bail out
		}

	my ($sScript) = $Response[2];
	#
	# now execute the plug-in
	#
	if (eval($sScript) != $::SUCCESS)				# execute the script
		{
		ACTINIC::ReportError($@, ACTINIC::GetPath());
		}
	#
	# Decrypt account
	#
	$::PAYPAL_SIGNATURE = DecryptPPDetails($::PAYPAL_SIGNATURE);
	$::PAYPAL_PWD = DecryptPPDetails($::PAYPAL_PWD);
	}
	
#######################################################
#
# IncludeGoogleScript - prepare for google checkout 
#
# Author: Zoltan Magyar
#
#######################################################

sub IncludeGoogleScript
	{
	#
	# Set the payment to paypal to get the correct PSP script
	#
	$::g_PaymentInfo{'METHOD'} = $::PAYMENT_GOOGLE;
	my @Response = GetOCCScript(ACTINIC::GetPath());
	$::g_PaymentInfo{'METHOD'} = $::PAYMENT_CREDIT_CARD;

	if ($Response[0] != $::SUCCESS)					# couldn't load the script
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());	# bail out
		}

	my ($sScript) = $Response[2];
	#
	# Google will require XML parsing
	#
	eval
		{
		require <Actinic:Variable Name="ActinicPXMLPackage"/>;	# load parser library
		};
	if ($@)													# library load failed?
		{
		ReportError($@, GetPath());					# if so then record the error
		}
	#
	# Make sure we got MD5 for the ignature
	#
	eval
		{
		require Digest::MD5;								# Try loading MD5
		import Digest::MD5 'md5_hex';
		};
	if ($@)
		{
		require <Actinic:Variable Name="DigestPerlMD5"/>;
		import Digest::Perl::MD5 'md5_hex';			# Use Perl version if not found
		}
	#
	# now execute the plug-in
	#
	if (eval($sScript) != $::SUCCESS)				# execute the script
		{
		ACTINIC::ReportError($@, ACTINIC::GetPath());
		}
	#
	# Decrypt account
	#
	#$::sMerchantID = DecryptPPDetails($::sMerchantID);
	$::sMerchantKey = DecryptPPDetails($::sMerchantKey);
	}
	
#######################################################
#
# IncludePaypalScript - get our paypal library and get it included
#
# Author: Zoltan Magyar
#
#######################################################

sub IncludePaypalScript
	{
	if (defined $$::g_pPaymentList{$::PAYMENT_PAYPAL_EC})
		{
		EvaluatePaypalEC();
		}
	else
		{
		EvaluatePaypalPro();								# Make sure we got the paypal stuff
		}
	}
#######################################################
#
# GetPPAddressDetails - return the buyer address details
# 	as an array so it can be fed into the direct payment call
#
# Author: Zoltan Magyar
#
#######################################################

sub GetPPAddressDetails
	{
	my @aNames = split(/ /, $::g_BillContact{NAME});
	my ($sFirstName, $sLastName) = (shift @aNames, join ' ', @aNames);

	return(
	$sFirstName,
	$sLastName,
	$::g_BillContact{EMAIL},
	ActinicLocations::GetISOInvoiceCountryCode(),
	$::g_BillContact{ADDRESS4},
	$::g_BillContact{POSTALCODE},
	$::g_BillContact{ADDRESS3},
	$::g_BillContact{ADDRESS1} . ' ' .$::g_BillContact{ADDRESS2}
	);
	}

#######################################################
#
# DecryptPPDetails - get safer encrypted account details
#
# Author: Zoltan Magyar
#
#######################################################

sub DecryptPPDetails
	{
	my $sValue = shift;
	my $sUserKey = $::g_sUserKey;

	if ($sUserKey)
		{
		$sUserKey =~ s/([A-Fa-f0-9]{2})/pack("C",hex($1))/ge;
		my @PrivateKey = unpack('C*',$sUserKey);
		my ($sLength, $sDetails) = split(/ /, $sValue);
		$sDetails =~ s/([A-Fa-f0-9]{2})/pack("C",hex($1))/ge;

		ActinicEncrypt::InitEncrypt(@{$$::g_pSetupBlob{PUBLIC_KEY_128BIT}});
		$sDetails = ActinicEncrypt::DecryptSafer($sDetails, @PrivateKey);
		$sValue = substr($sDetails, 0, $sLength);	# restore it's size to the original length
		}
	else
		{
		ACTINIC::ReportError("The selected payment service provider is not supported on Actinic Host ", ACTINIC::GetPath());
		}
	return($sValue);
	}

#######################################################
#
# RecordPaypalOrder - implements paypal pro specific
# order completition (record order and auth at the same time)
#
# Returns:	0 - $::SUCCESS or $::FAILURE
#				1 - undef or error message
#
# Author: Zoltan Magyar
#
#######################################################

sub RecordPaypalOrder
	{
	my $oPaypal = shift;
	my $nAmount = ActinicOrder::GetOrderTotal();

	my $hResponse = $oPaypal->GetResponseHash();

	if ($$hResponse{RESULT} != 0)
		{
		return ($::FAILURE, $$hResponse{RESPMSG});
		}
	if ($$hResponse{ACK} eq "Failure")
		{
		return ($::FAILURE, $$hResponse{L_LONGMESSAGE0});
		}
	#
	# If we are here then the payment was accepted by paypal so we can record
	# the order as well as the authorization.
	#
	$::g_PaymentInfo{'METHOD'} = $::PAYMENT_PAYPAL_PRO;
	if (defined $$::g_pPaymentList{$::PAYMENT_PAYPAL_EC})
		{
		$::g_PaymentInfo{'METHOD'} = $::PAYMENT_PAYPAL_EC;
		}
	#
	# Order recording requires the card details wiped in case of PSP orders so do it here
	#
	undef $::g_PaymentInfo{'CARDNUMBER'};
	undef $::g_PaymentInfo{'CARDTYPE'};
	undef $::g_PaymentInfo{'EXPYEAR'};
	undef $::g_PaymentInfo{'EXPMONTH'};
	#
	# Call standard order recording function
	#
	my (@Response) = CompleteOrder();
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	#
	# Order is recorded, now record the authorization
	#
	my ($status, $sMessage, $sOrderNumber) = GetOrderNumber();
	my $sAction = $::g_InputHash{ACTION};				# the auth function uses this so we need to override but create a backup first
	$::g_InputHash{ON} = $sOrderNumber;
	$::g_InputHash{TM} = $oPaypal->{TESTMODE};
	$::g_InputHash{AM} = $nAmount * (10 ** $$::g_pCatalogBlob{"ICURRDIGITS"});
	$::g_InputHash{ACTION} = sprintf("AUTHORIZE_%d", $::g_PaymentInfo{'METHOD'});
	#
	# Build the parameters for the auth record
	#
	my ($sDate) = ACTINIC::GetActinicDate();
	($sDate) = ACTINIC::EncodeText2($sDate, $::FALSE);
	my $sParams = sprintf("ON=%s&TM=%s&AM=%s&CD=%s&TX=%s&DT=%s&",
		$sOrderNumber,
		$oPaypal->{TESTMODE},
		$nAmount * (10 ** $$::g_pCatalogBlob{"ICURRDIGITS"}),
		$$hResponse{PPREF},
		$$hResponse{PNREF},
		$sDate);
	if (defined $$::g_pPaymentList{$::PAYMENT_PAYPAL_EC})
		{
		$sParams = sprintf("ON=%s&TM=%s&AM=%s&CD=%s&TX=%s&DT=%s&",
			$sOrderNumber,
			$oPaypal->{TESTMODE},
			$nAmount * (10 ** $$::g_pCatalogBlob{"ICURRDIGITS"}),
			$$hResponse{TRANSACTIONID},
			$$hResponse{AUTHORIZATIONID},
			$sDate);
		}
	#
	# Make sure we got MD5 for the ignature
	#
	eval
		{
		require Digest::MD5;								# Try loading MD5
		import Digest::MD5 'md5_hex';
		};
	if ($@)
		{
		require <Actinic:Variable Name="DigestPerlMD5"/>;
		import Digest::Perl::MD5 'md5_hex';			# Use Perl version if not found
		}
	#
	# Create the signature
	#
	my $sSignature = md5_hex($sParams);
	$sParams .= sprintf("SN=%s", $sSignature);
	#
	# Record the authorization
	#
	my $sError = RecordAuthorization(\$sParams);
	$::g_InputHash{ACTION} = $sAction;				# restore the original action
	if (length $sError != 0)
		{
		# record any error to error.err
		#
		ACTINIC::RecordErrors($sError, ACTINIC::GetPath());
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 1964));
		}
	return ($::SUCCESS, '');
	}

#######################################################
#
# FormatTrackingPage - Format the tracking page
#
# Returns:	0 - Status
#				1 - Error message if any
#				3 - HTML
#
# Author: Mike Purnell
#
#######################################################

sub FormatTrackingPage
	{
	my $sHTML = '';
	#
	# Get the SSP Provider ID
	#
	my $nSSPID = $::g_InputHash{SSP_ID};
	#
	# Get the SSP Provider hash
	#
	my $phashSSPProvider = $$::g_pSSPSetupBlob{$nSSPID};
	if (!defined $phashSSPProvider)
		{
		return($::SUCCESS, '', ACTINIC::GetPhrase(-1, 2271));
		}
	#
	# Plug the access key
	#
	my %hashVariables;
	$hashVariables{$::VARPREFIX.'LICENSEKEY'} = ACTINIC::DecodeXOREncryption($$phashSSPProvider{'AccessKey'}, $::UPS_ENCRYPT_PASSWORD);
	$hashVariables{$::VARPREFIX.'TYPEOFINQUIRYNUMBER'} = $::g_InputHash{TrackingType};
	#
	# "Tracking by tracking number" specific variables
	#
	#
	# Get the maximum number for tracking numbers supported
	#
	my $nMaxTrackingNumbers = $$phashSSPProvider{MaxTrackingNumbers};
	my $i;
	#
	# Plug the tracking numbers into the template from the input hash
	# or clear missing number NQVs
	#
	for($i = 1; $i <= $nMaxTrackingNumbers; $i++)
		{
		#
		# Create the appropriate variables for the HTML substitution
		#
		if(defined $::g_InputHash{'NUMBER' . $i})
			{
			$hashVariables{$::VARPREFIX.'INQUIRYNR' . $i} = $::g_InputHash{'NUMBER' . $i};
			}
		else
			{
			$hashVariables{$::VARPREFIX.'INQUIRYNR' . $i} = '';
			}
		}
	#
	# "Tracking by reference number" specific variables
	#
	$hashVariables{$::VARPREFIX.'INQUIRYNR'} = $::g_InputHash{'NUMBER'};
	$hashVariables{$::VARPREFIX.'SENDERSHIPPERNUMBER'} = $::g_InputHash{'ShipperNumber'};
	$hashVariables{$::VARPREFIX.'DESTINATIONPOSTALCODE'} = $::g_InputHash{'DestinationPostalCode'};
	$hashVariables{$::VARPREFIX.'DESTINATIONCOUNTRY'} = $::g_InputHash{'DestinationCountry'};
	$hashVariables{$::VARPREFIX.'FROMPICKUPMONTH'} = $::g_InputHash{'FromPickupMonth'};
	$hashVariables{$::VARPREFIX.'FROMPICKUPDAY'} = $::g_InputHash{'FromPickupDay'};
	$hashVariables{$::VARPREFIX.'FROMPICKUPYEAR'} = $::g_InputHash{'FromPickupYear'};
	$hashVariables{$::VARPREFIX.'TOPICKUPMONTH'} = $::g_InputHash{'ToPickupMonth'};
	$hashVariables{$::VARPREFIX.'TOPICKUPDAY'} = $::g_InputHash{'ToPickupDay'};
	$hashVariables{$::VARPREFIX.'TOPICKUPYEAR'} = $::g_InputHash{'ToPickupYear'};
	#
	# Display the "Wait for your browser to forward..." message
	#
	$ACTINIC::B2B->SetXML('FORWARDMESSAGE', ACTINIC::GetPhrase(-1, 2272));
	#
	# Plug into the template
	#
	my @Response = ACTINIC::TemplateFile(ACTINIC::GetPath() . $$phashSSPProvider{TrackingTemplate}, \%hashVariables);
	if($Response[0] != $::SUCCESS)
		{
		return(@Response);
		}
	$sHTML = $Response[2];

	return($::SUCCESS, '', $sHTML);
	}

#######################################################
#
# GetContactDetailsString - retrieve the contact details
#  as a formatted text string
#
# Returns:	0 - string
#
#######################################################

sub GetContactDetailsString
	{
	my $sText;
	#
	# The Invoice Contact
	#
	$sText .= ACTINIC::GetPhrase(-1, 339) . "\n";
	unless (ACTINIC::IsPromptHidden(0, 0))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 0)  . " $::g_BillContact{'SALUTATION'}\n"; # the salutation
		}
	unless (ACTINIC::IsPromptHidden(0, 1))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 1)  . " $::g_BillContact{'NAME'}\n";	# the contact name
		}
	unless (ACTINIC::IsPromptHidden(0, 21))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 21)  . " $::g_BillContact{'FIRSTNAME'}\n"; # the contact first name
		}
	unless (ACTINIC::IsPromptHidden(0, 22))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 22)  . " $::g_BillContact{'LASTNAME'}\n"; # the contact last name
		}
	unless (ACTINIC::IsPromptHidden(0, 2))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 2)  . " $::g_BillContact{'JOBTITLE'}\n";	# the contact job title
		}
	unless (ACTINIC::IsPromptHidden(0, 3))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 3)  . " $::g_BillContact{'COMPANY'}\n";	# the contact company
		}
	unless (ACTINIC::IsPromptHidden(0, 4))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 4)  . " $::g_BillContact{'ADDRESS1'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(0, 5))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 5)  . " $::g_BillContact{'ADDRESS2'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(0, 6))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 6)  . " $::g_BillContact{'ADDRESS3'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(0, 7))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 7)  . " $::g_BillContact{'ADDRESS4'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(0, 8))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 8)  . " $::g_BillContact{'POSTALCODE'}\n";	# the contact post code
		}
	unless (ACTINIC::IsPromptHidden(0, 9))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 9)  . " $::g_BillContact{'COUNTRY'}\n";	# the contact country
		}
	unless (ACTINIC::IsPromptHidden(0, 10))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 10) . " $::g_BillContact{'PHONE'}\n";	# the contact phone
		}
	unless (ACTINIC::IsPromptHidden(0, 20))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 20) . " $::g_BillContact{'MOBILE'}\n";	# the contact mobile
		}

	unless (ACTINIC::IsPromptHidden(0, 11))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 11) . " $::g_BillContact{'FAX'}\n";	# the contact fax
		}
	unless (ACTINIC::IsPromptHidden(0, 12))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 12) . " $::g_BillContact{'EMAIL'}\n";	# the contact email
		}
	unless (ACTINIC::IsPromptHidden(0, 13))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(0, 13) . " $::g_BillContact{'USERDEFINED'}\n";	# the contact user defined
		}
	#
	# The Delivery Contact
	#
	$sText .= "\n" . ACTINIC::GetPhrase(-1, 340) . "\n";
	unless (ACTINIC::IsPromptHidden(1, 0))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 0)  . " $::g_ShipContact{'SALUTATION'}\n"; # the salutation
		}
	unless (ACTINIC::IsPromptHidden(1, 1))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 1)  . " $::g_ShipContact{'NAME'}\n";	# the contact name
		}
	unless (ACTINIC::IsPromptHidden(1, 21))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 21)  . " $::g_ShipContact{'FIRSTNAME'}\n";	# the contact first name
		}
	unless (ACTINIC::IsPromptHidden(1, 22))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 22)  . " $::g_ShipContact{'LASTNAME'}\n";	# the contact first name
		}
	unless (ACTINIC::IsPromptHidden(1, 2))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 2)  . " $::g_ShipContact{'JOBTITLE'}\n";	# the contact job title
		}
	unless (ACTINIC::IsPromptHidden(1, 3))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 3)  . " $::g_ShipContact{'COMPANY'}\n";	# the contact company
		}
	unless (ACTINIC::IsPromptHidden(1, 4))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 4)  . " $::g_ShipContact{'ADDRESS1'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(1, 5))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 5)  . " $::g_ShipContact{'ADDRESS2'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(1, 6))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 6)  . " $::g_ShipContact{'ADDRESS3'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(1, 7))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 7)  . " $::g_ShipContact{'ADDRESS4'}\n";	# the contact address
		}
	unless (ACTINIC::IsPromptHidden(1, 8))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 8)  . " $::g_ShipContact{'POSTALCODE'}\n";	# the contact post code
		}
	unless (ACTINIC::IsPromptHidden(1, 9))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 9)  . " $::g_ShipContact{'COUNTRY'}\n";	# the contact country
		}
	unless (ACTINIC::IsPromptHidden(1, 10))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 10) . " $::g_ShipContact{'PHONE'}\n";	# the contact phone
		}
	unless (ACTINIC::IsPromptHidden(1, 20))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 20) . " $::g_ShipContact{'MOBILE'}\n";	# the contact mobile
		}
	unless (ACTINIC::IsPromptHidden(1, 11))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 11) . " $::g_ShipContact{'FAX'}\n";	# the contact fax
		}
	unless (ACTINIC::IsPromptHidden(1, 12))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 12) . " $::g_ShipContact{'EMAIL'}\n";	# the contact email
		}
	unless (ACTINIC::IsPromptHidden(1, 13))
		{
		$sText .= "\t" . ACTINIC::GetPhrase(1, 13) . " $::g_ShipContact{'USERDEFINED'}\n";	# the contact user defined
		}

	return ($sText);
	}

#######################################################
#
# FormatShippingOpaqueData - Format the shipping opaque data
#
# Input:	$phashShippingDetails	- pointer to hash containing shipping details
#			$bParentExcluded			- whether parent product is excluded
#
# Returns:	$sOpaqueData	- formatted opaque data
#
#######################################################

sub FormatShippingOpaqueData
	{
	my ($phashShippingDetails, $bParentExcluded) = @_;
	my $sOpaqueData = $phashShippingDetails->{'OPAQUE_SHIPPING_DATA'};
	$sOpaqueData .= ";ALT_WEIGHT=$phashShippingDetails->{'ALT_WEIGHT'}";
	$sOpaqueData .= ";EXCLUDE_FROM_SHIP=$phashShippingDetails->{'EXCLUDE_FROM_SHIP'}";
	$sOpaqueData .= ";SHIP_CATEGORY=$phashShippingDetails->{'SHIP_CATEGORY'}";
	$sOpaqueData .= ";SHIP_QUANTITY=$phashShippingDetails->{'SHIP_QUANTITY'}";
	$sOpaqueData .= ";SHIP_SUPPLEMENT=$phashShippingDetails->{'SHIP_SUPPLEMENT'}";
	$sOpaqueData .= ";SHIP_SUPPLEMENT_ONCE=$phashShippingDetails->{'SHIP_SUPPLEMENT_ONCE'}";
	$sOpaqueData .= ";HAND_SUPPLEMENT=$phashShippingDetails->{'HAND_SUPPLEMENT'}";
	$sOpaqueData .= ";HAND_SUPPLEMENT_ONCE=$phashShippingDetails->{'HAND_SUPPLEMENT_ONCE'}";
	$sOpaqueData .= ";EXCLUDE_PARENT=$bParentExcluded";
	$sOpaqueData .= ";SEP_LINE=$phashShippingDetails->{'SEPARATE_LINE'}";
	$sOpaqueData .= ";USE_ASSOC_SHIP=$phashShippingDetails->{'USE_ASSOCIATED_SHIP'}";
	if($phashShippingDetails->{SHIP_SEPARATELY})
		{
		$sOpaqueData .= ';SEPARATE;';
		}
	else
		{
		$sOpaqueData .= ';';
		}
	return ($sOpaqueData);
	}

#---------------------------------------------------------------
#
# OrderBlob package
#
# This package is a simple wrapper for two arrays representing
# the order blob, one for the type of data and another for the
# value of the data.
#
#---------------------------------------------------------------

package OrderBlob;

################################################################
#
# OrderBlob->new - constructor for OrderBlob class
#
# Input:	$Proto		- class name or ref to class name
#			$parrType	- reference to array of variable types
#			$parrValue	- reference to array of variable values
#
# Author:	Mike Purnell
#
################################################################

sub new
	{
	my ($Proto, $parrType, $parrValue) = @_;
	my $sClass = ref($Proto) || $Proto;
	my $Self  = {};										# create self
	bless ($Self, $sClass);								# populate

	$Self->{_TYPES}	= $parrType;					# store reference to type array
	$Self->{_VALUES}	= $parrValue;					# store reference to value array
	return($Self);
	}

################################################################
#
# OrderBlob->AddByte - add a byte value
#
# Input:	$Self		- blob object
#			$nValue	- byte value
#
# Author:	Mike Purnell
#
################################################################

sub AddByte
	{
	my ($Self, $nValue) = @_;
	push @{$Self->{_TYPES}}, $::RBBYTE;				# this is a byte
	push @{$Self->{_VALUES}}, $nValue;				# add the value
	}

################################################################
#
# OrderBlob->AddWord - add a word value
#
# Input:	$Self		- blob object
#			$nValue	- word value
#
# Author:	Mike Purnell
#
################################################################

sub AddWord
	{
	my ($Self, $nValue) = @_;
	push @{$Self->{_TYPES}}, $::RBWORD;				# this is a word
	push @{$Self->{_VALUES}}, $nValue;				# add the value
	}

################################################################
#
# OrderBlob->AddDWord - add a double word value
#
# Input:	$Self		- blob object
#			$nValue	- double word value
#
# Author:	Mike Purnell
#
################################################################

sub AddDWord
	{
	my ($Self, $nValue) = @_;
	push @{$Self->{_TYPES}}, $::RBDWORD;			# this is a double word
	push @{$Self->{_VALUES}}, $nValue;				# add the value
	}

################################################################
#
# OrderBlob->AddQWord - add a quad word value
#
# Input:	$Self		- blob object
#			$nValue	- quad word value
#
# Author:	Mike Purnell
#
################################################################

sub AddQWord
	{
	my ($Self, $nValue) = @_;
	push @{$Self->{_TYPES}}, $::RBQWORD;			# this is a quad word
	push @{$Self->{_VALUES}}, $nValue;				# add the value
	}

################################################################
#
# OrderBlob->AddString - add a string value
#
# Input:	$Self		- blob object
#			$sValue	- string value
#
# Author:	Mike Purnell
#
################################################################

sub AddString
	{
	my ($Self, $sValue) = @_;
	push @{$Self->{_TYPES}}, $::RBSTRING;			# this is a string
	push @{$Self->{_VALUES}}, $sValue;				# add the string
	}

################################################################
#
# OrderBlob->AddContact - add a contact details line (invoice/shipping)
#
# Input:	$Self			- blob object
#			$pContact	- the contact hash
#
# Author:	Zoltan Magyar
#
################################################################

sub AddContact
	{
	my ($Self, $pContact) = @_;

	$Self->AddString($$pContact{'NAME'});		# the contact name
	$Self->AddString($$pContact{'FIRSTNAME'});	# the contact first name
	$Self->AddString($$pContact{'LASTNAME'}); 	# the contact last name
	$Self->AddString($$pContact{'SALUTATION'}); 	# the salutation
	$Self->AddString($$pContact{'JOBTITLE'});		# the contact job title
	$Self->AddString($$pContact{'COMPANY'});		# the contact company
	$Self->AddString($$pContact{'ADDRESS1'});		# the contact address
	$Self->AddString($$pContact{'ADDRESS2'});		# the contact address
	$Self->AddString($$pContact{'ADDRESS3'});		# the contact address
	$Self->AddString($$pContact{'REGION'});		# the contact address
	$Self->AddString($$pContact{'COUNTRY'});		# the contact country
	$Self->AddString($$pContact{'POSTALCODE'});	# the contact post code
	$Self->AddString($$pContact{'PHONE'});		# the contact phone
	$Self->AddString($$pContact{'MOBILE'});		# the contact mobile
	$Self->AddString($$pContact{'FAX'});		# the contact fax
	$Self->AddString($$pContact{'EMAIL'});		# the contact email
	$Self->AddString($$pContact{'USERDEFINED'});	# the contact user defined
	#
	# Do a safety check on the possibly undefined PRIVACY value
	#
	if (! defined $$pContact{PRIVACY} ||
		 $$pContact{PRIVACY} eq '')
		{
		$$pContact{PRIVACY} = $::FALSE;
		}
	$Self->AddByte($$pContact{'PRIVACY'});			# the privacy flag
	}

################################################################
#
# OrderBlob->AddAdjustment - add an adjustment
#
# Input:	$Self							- blob object
#			$nOrderSequenceNumber	- the index of the order line
#			$parrAdjustDetails		- reference to array of details
#			$pProduct					- reference to product
#
# Author:	Mike Purnell
#
################################################################

sub AddAdjustment
	{
	my ($Self, $nOrderSequenceNumber, $parrAdjustDetails, $pProduct) = @_;
	my $nAmount = $parrAdjustDetails->[$::eAdjIdxAmount];

	$Self->AddWord($ACTINIC::ORDER_DETAIL_BLOB_MAGIC);					# the order detail magic number
	$Self->AddByte($::ORDER_DETAIL_BLOB_VERSION);						# order detail version number
	$Self->AddString($parrAdjustDetails->[$::eAdjIdxProductRef]);	# the product reference
	$Self->AddString($parrAdjustDetails->[$::eAdjIdxProductDescription]);	# the product description
	$Self->AddDWord(0);															# the quantity ordered
	$Self->AddQWord($nAmount);													# the item price
	$Self->AddQWord($nAmount);													# the line price
	$Self->AddQWord(0);															# the cost price
	$Self->AddString('');														# the date field
	$Self->AddString('');														# the date field value
	$Self->AddString('');														# extra information
	$Self->AddString('');														# extra information value
	$Self->AddDWord(0);															# the quantity already shipped
	$Self->AddDWord(0);															# the quantity already cancelled
	#
	# Save the correct tax opaque data for adjustment
	#
	my $rarrTaxOpaqueData = ActinicOrder::PricesIncludeTaxes() ?	# if tax-inclusive
		$parrAdjustDetails->[$::eAdjIdxDefOpaqueData] :					# use default zone taxes
		$parrAdjustDetails->[$::eAdjIdxCurOpaqueData];					# else use current taxes
		
	$Self->AddString($rarrTaxOpaqueData->[0]);							# Tax 1 opaque data
	$Self->AddString($rarrTaxOpaqueData->[1]);							# Tax 2 opaque data
	#
	# Handle tax negation if in tax-inclusive mode
	#
	my $nTax = $parrAdjustDetails->[$::eAdjIdxTax1];
	if ($::g_TaxInfo{'EXEMPT1'} ||											# if they've declared exemption for tax 1
		!ActinicOrder::IsTaxApplicableForLocation('TAX_1'))			# or tax 1 isn't applicable for current location
		{
		if (ActinicOrder::PricesIncludeTaxes())							# if prices include taxes
			{
			$nTax = -$nTax;														# invert the taxes
			}
		}
	$Self->AddQWord($nTax);														# tax 1
	
	$nTax = $parrAdjustDetails->[$::eAdjIdxTax2];
	if ($::g_TaxInfo{'EXEMPT2'} ||											# if they've declared exemption for tax 2
		!ActinicOrder::IsTaxApplicableForLocation('TAX_2'))			# or tax 2 isn't applicable for current location
		{
		if (ActinicOrder::PricesIncludeTaxes())							# if prices include taxes
			{
			$nTax = -$nTax;														# invert the taxes
			}
		}
	$Self->AddQWord($nTax);														# tax 2
	
	$Self->AddString('');														# advanced shipping data
	$Self->AddQWord(0);															# discount total
	$Self->AddDWord(0);															# discount percent
	$Self->AddDWord(0);															# not component
	$Self->AddString('');														# Extra product description
	#
	# If this is a product adjustment we may have custom tax which might need adjusting
	#
	my @arrResponse;
	if($pProduct)
		{
		@arrResponse = ActinicOrder::PrepareProductTaxOpaqueData($pProduct,
			$nAmount, $$pProduct{'PRICE'}, $parrAdjustDetails->[$::eAdjIdxCustomTaxAsExempt]);
		}
	else
		{
		@arrResponse = ActinicOrder::PrepareProductTaxOpaqueData(undef,
			$nAmount, $nAmount, $::FALSE, $ActinicOrder::PRORATA);
		}
	$Self->AddString($arrResponse[2]);											# Write the adjustment opaque tax data

	$Self->AddByte(0);															# no order line for main product
	$Self->AddByte(0);															# components as separate order line
	$Self->AddByte($parrAdjustDetails->[$::eAdjIdxLineType]);		# order detail line type
	$Self->AddDWord($nOrderSequenceNumber);								# sequence number
	$Self->AddByte($parrAdjustDetails->[$::eAdjIdxTaxTreatment]);	# adjustment tax treatment
	$Self->AddString($parrAdjustDetails->[$::eAdjIdxCouponCode]);	# coupon code
	#
	# Add stock fields
	#
	$Self->AddByte(0);									# whether this is assembly product
	$Self->AddString('');								# aisle
	$Self->AddString('');								# rack
	$Self->AddString('');								# sub-rack
	$Self->AddString('');								# bin
	$Self->AddString('');								# barcode
	}

#---------------------------------------------------------------
#
# End of OrderBlob package
#
#---------------------------------------------------------------

