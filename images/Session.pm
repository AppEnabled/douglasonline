#!perl
################################################################
#
# Session.pm - Session object implementation
#
# Written by Zoltan Magyar, 2:32 PM, November 28, 2001
#
# Copyright (c) ACTINIC SOFTWARE Plc 2001
#################################################################
package Session;
use strict;

push (@INC, "cgi-bin");
<Actinic:Variable Name="IncludePathAdjustment"/>

use <Actinic:Variable Name="PXMLPackage"/>;
require <Actinic:Variable Name="ActinicPackage"/>;
require <Actinic:Variable Name="ActinicConstantsPackage"/>;
#
# Version
#
$Session::prog_name = 'Session.pm';					# Program Name
$Session::prog_name = $Session::prog_name;		# remove compiler warning
$Session::prog_ver = '$Revision: 23197 $ ';			# program version
$Session::prog_ver = substr($Session::prog_ver, 11); # strip the revision information
$Session::prog_ver =~ s/ \$//;						# and the trailers

$Session::SESSIONFILEVERSION = "1.0";
#
# XML main entry names
#
$Session::XML_ROOT				= 'SessionFile';				# the root XML entry
$Session::XML_URLINFO			= 'URLInfo';
$Session::XML_CHECKOUTINFO		= 'CheckoutInfo';
$Session::XML_SHOPPINGCART 	= 'ShoppingCart';

$Session::XML_BASEURL 		= "BASEURL";
$Session::XML_LASTSHOPPAGE = "LASTSHOPPAGE";
$Session::XML_LASTPAGE 		= "LASTPAGE";

$Session::XML_CLOSED 		= "Closed";
$Session::XML_PAYMENT 		= "Payment";
$Session::XML_IPCHECK 		= "IPCheck";
$Session::XML_DIGEST			= "Digest";
$Session::XML_CHECKOUTSTARTED	= "CheckoutStarted";
#
# Paypal pro specific entries
#
$Session::XML_PPTOKEN		= "Token";
$Session::XML_PPPAYERID		= "PayerID";

################################################################
#
#  Session->new() - constructor for Session class
#  A very standard constructor. Allows inheritance.
#  Calls Set() function passing it all the arguments.
#  So the arguments may be specified here with name=>value
#  pairs or they may be set later using Set() method.
#
# Arguments:	0 - sessionID
#					1 - cookie string
#					2 - path
#					3 - optional calling identifier (false - OrderScript)
#					4 - true if the session object is created during an
#						 SSL  or PSP callback (optional)
#
# Returns:		0 - object pointer
#
#  Zoltan Magyar, 2:32 PM, November 28, 2001
#
#  Copyright (c) Actinic Software Ltd 2001
#
################################################################

sub new
	{
	my $Proto = shift;
	my $Class = ref($Proto) || $Proto;
	my $sSessionID 	= shift;
	my $sCookieString = shift;
	my $sPath			= shift;
	my $sCallerID		= shift;
	my $bCallBack		= shift;

	if (!defined $bCallBack || $bCallBack != $::TRUE)	# just to be sure it has a proper value
		{
		$bCallBack = $::FALSE;
		}

	my $Self  = {};
	bless ($Self, $Class);
	#
	# Set parameters if any
	#
	$Self->Set(@_);
	#
	# Do some garbage collection before anything else
	#
	$Self->{_PATH}						= $sPath;		# path is required before cleanup
	$Self->{_OLDSESSIONID}			= $sSessionID;	# save the current session ID (needed by ACTINIC::PrintHeader)
	$Self->{_NEWESTSAVEDCARTTIME}	= 0;				# time stamp of newest saved cart for this session ID
	$Self->ClearOldFiles();
	$Self->CheckForBadPaths();							# ensure we don't allow access to non actinic files
	#
	# Check Session ID
	#
	if ($sSessionID eq "")								# if we don't have one
		{
		my @Response = $Self->CreateSessionID();	# then create an uniquie session ID
		if ($Response[0] != $::SUCCESS)				# if failed then bomb out
			{
			ACTINIC::ReportError($Response[1], $Self->GetSessionFileFolder());
			}
		}
	else
		{
		$Self->{_SESSIONID} 	= $sSessionID;
		}
	#
	# Copy passed in parameters
	#
	$Self->{_SESSIONFILE} 	= $Self->{_SESSIONID} . ".session";	# init file name
	$Self->{_COOKIESTRING}	= $sCookieString;
	#
	# create session file locker object to avoid multiple instance or process error
	# used only, when PAyPal or Nochex exists and enabled
	#
 	my $sFullFileName = $Self->GetSessionFileFolder() . $Self->{_SESSIONFILE};
	$Self->{_LOCKER} = new SessionLock($sFullFileName);
	#
	# Init base structure
	#
	$Self->{_SESSIONINFO} = new Element({'_TAG' => $Session::XML_ROOT, '_PARAMETERS' => {'Version' => $Session::SESSIONFILEVERSION}});
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_URLINFO, "");
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_CHECKOUTINFO, "");
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_SHOPPINGCART, "");
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_PAYMENT, "");
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_IPCHECK, "");
	#
	# Init callback flag
	#
	$Self->{_ISCALLBACK} = $bCallBack;
	#
	# Init new session file indicator
	#
	$Self->{_NEWSESSIONFILE} = $::FALSE;
	#
	# Restore the session
	#
	$Self->RestoreSession();
	#
	# Check if session files purged during checkout
	#
	if ($Self->{_NEWSESSIONFILE} &&					# it is a new session file
		 !$sCallerID &&									# and orderscript call
		 $::g_InputHash{'ACTION'} ne ACTINIC::GetPhrase(-1, 113) &&	# but not start checkout
		 $::g_InputHash{'ACTION'} ne "PPSTARTCHECKOUT" &&
		 $::g_InputHash{'ACTION'} !~ /^OFFLINE_AUTHORIZE/i)
		{
		my $sRefPage = $::g_InputHash{'REFPAGE'};
		if (!$sRefPage)
			{
			$sRefPage = $$::g_pSetupBlob{CATALOG_URL};
			}
		$::bCookieCheckRequired = $::FALSE;				# cookie checking must be added to the next generated html page
		my @Response = ACTINIC::BounceToPageEnhanced(undef, ACTINIC::GetPhrase(-1, 1962) . ACTINIC::GetPhrase(-1, 2249, $::g_sCart, $::g_sCart) . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2049),
																$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
																$::g_sWebSiteUrl,
																$::g_sContentUrl, $::g_pSetupBlob, $sRefPage, \%::g_InputHash,
																$::FALSE);
		
		if ($Response[0] != $::SUCCESS)
			{
			ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 2249), $Self->GetSessionFileFolder());
			}
		ACTINIC::PrintPage($Response[2], undef);
		exit;
		}
	#
	# Check if it is a registered customer
	#
	my ($sDigest,$sBaseFile) = ACTINIC::CaccGetCookies();
	#
	# Be sure that different registered (or retail) customers can't see each other
	# cart and details by browsing from the same PC
	#
	# So we store a "Digest" node in the session which is the user digest
	# for registered and empty string for unregistered customers.
	# If the actual and the stored digest is not the same we reset the session.
	#
	if (!$Self->{_ISCALLBACK} && ($Self->GetDigest() ne $sDigest))				# if it is not a callback than it is owned by someone else?
		{
		$Self->ResetSession();							# erase the session
		$Self->SetDigest($sDigest);					# set the new digest
		}
	#
	# Check Closed session
	#
	if ($Self->IsClosed() &&							# if the cart is closed
		 $sCallerID)										# and not an OrderScript call
		{														# then reset the cart and closed cart indicator
		#
		# Create empty shopping cart node
		#
		$Self->{_SESSIONINFO}->SetTextNode($Session::XML_SHOPPINGCART, "");
		#
		# Create empty closed node
		#
		$Self->{_SESSIONINFO}->SetTextNode($Session::XML_CLOSED, "");
		#
		# Reset checkoutstarted flag
		#
		$Self->{_SESSIONINFO}->SetTextNode($Session::XML_CHECKOUTSTARTED, "");
		#
		# clear the payment was made flag
		#
		$Self->{_SESSIONINFO}->SetTextNode($Session::XML_PAYMENT, "");
		#
		# clear the IP check flag
		#
		$Self->{_SESSIONINFO}->SetTextNode($Session::XML_IPCHECK, "");
		#
		# Reset the contact details in case of retail user
		#
		if ($sDigest eq "")
			{
			$Self->UpdateCheckoutInfo({}, {}, {}, {}, {}, {}, {});	# reset the data structure
			#
			# Then restore the checkout info if remember me is on
			#
			my $pRemember = $Self->GetCheckoutInfo()->GetChildNode('BillContact');
			if (defined $pRemember ||
				 defined $pRemember->GetChildNode('REMEMBERME')	||
				 defined $pRemember->GetChildNode('REMEMBERME')->GetNodeValue() ||
				 $pRemember->GetChildNode('REMEMBERME')->GetNodeValue() == $::TRUE )
				{
				$Self->CookieStringToContactDetails();	# restore the data structure from cookie
				}
			}
		}
	#
	# Init the URL info
	#
	$Self->InitURLs();
	return $Self;
	}

################################################################
#
#	Session->ResetSession() - reset session file
#
################################################################

sub ResetSession
	{
	my $Self = shift;
	#
	# Reset the session
	#
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_SHOPPINGCART, "");
	$Self->UpdateCheckoutInfo({}, {}, {}, {}, {}, {}, {});	# reset the data structure
	#
	# Remove the user's digest
	#
	$Self->SetDigest("");
	#
	# Reset checkoutstarted flag
	#
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_CHECKOUTSTARTED, "");
	#
	# Reset the URL info
	#
	$Self->GetURLInfo()->SetTextNode($Session::XML_LASTSHOPPAGE, "");
	$Self->GetURLInfo()->SetTextNode($Session::XML_BASEURL, "");
	$Self->GetURLInfo()->SetTextNode($Session::XML_LASTPAGE, "");
	}

##############################################################################################################
#
# Get/Set methods
#
##############################################################################################################

################################################################
#
#  General get methods for easier access to
#  - URLInfo
#	- CheckoutInfo
#	- ShoppingCart
#  tags of the session info.
#
#	Return:		the appropriate Element object
#
################################################################

sub GetURLInfo
	{
	my $Self = shift;
	return $Self->{_SESSIONINFO}->GetChildNode($Session::XML_URLINFO);
	}

sub GetCheckoutInfo
	{
	my $Self = shift;
	return $Self->{_SESSIONINFO}->GetChildNode($Session::XML_CHECKOUTINFO);
	}

sub GetCartInfo
	{
	my $Self = shift;
	return $Self->{_SESSIONINFO}->GetChildNode($Session::XML_SHOPPINGCART);
	}

sub SetCartInfo
	{
	my $Self = shift;
	my $pXmlCartItems = shift;
	#
	# Empty the cart info
	#
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_SHOPPINGCART, "");
	#
	# Add items to the cart info list
	#
	my $pShoppingCart = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_SHOPPINGCART);
#? ACTINIC::ASSERT($Self->{_SESSIONINFO}->GetChildNode($Session::XML_SHOPPINGCART), "Undefined child node.", __LINE__, __FILE__);
	my $pXmlCartItem;
	foreach $pXmlCartItem (@{$pXmlCartItems})
		{
		$pShoppingCart->AddChildNode($pXmlCartItem);
		}
	}

################################################################
#
#  Session->Set() - set configuration parameters
#
#  Input: 0 - hash of paramaters
#
################################################################

sub Set
	{
	my $Self       = shift;
	my %Parameters = @_;
	#
	# Make a hash
	#
	foreach (keys %Parameters)
		{
		$Self->{$_} = $Parameters{$_};
		}
 	}

################################################################
#
#  Session->Get() - get object parameters
#
#  Input:	0 - parameter name
#	Output:	0 - parameter value
#
################################################################

sub Get
	{
	my $Self		= shift;
	my $sParam 	= shift;
	return $Self->{$sParam};
 	}

################################################################
#
#  Session->GetSessionID() - get the session identifier
#
#	Output:		0 - Sesion ID
#
################################################################

sub GetSessionID
	{
	my $Self		= shift;
	return $Self->{_SESSIONID};
 	}

################################################################
#
#  Session->GetBaseUrl()
#
#	Output:		0 - the base URL
#
################################################################

sub GetBaseUrl
	{
	my $Self		= shift;
#? ACTINIC::ASSERT($Self->GetURLInfo()->GetChildNode($Session::XML_BASEURL), "Undefined child node.", __LINE__, __FILE__);
 	my $sURL = $Self->GetURLInfo()->GetChildNode($Session::XML_BASEURL)->GetNodeValue();
 	$sURL =~ s|/[^/]*$|/|;				# strip file name if any
	return $sURL;
 	}

################################################################
#
#  Session->GetLastShopPage()
#
#	Output:		0 - the last shop page
#
################################################################

sub GetLastShopPage
	{
	my $Self		= shift;

# ACTINIC::ASSERT($Self->GetURLInfo()->GetChildNode($Session::XML_LASTSHOPPAGE), "Undefined child node.", __LINE__, __FILE__);
	#
	# if lastshop page is not stored yet, we give back the baseURL to avoid errors
	#
	if (!$Self->GetURLInfo()->IsElementNode() ||
			($Self->GetURLInfo()->IsElementNode() &&
		!$Self->GetURLInfo()->GetChildNode($Session::XML_LASTSHOPPAGE)))
		{
		return $Self->GetBaseUrl();
		}
	else
		{
		return $Self->GetURLInfo()->GetChildNode($Session::XML_LASTSHOPPAGE)->GetNodeValue();
	 	}
 	}

################################################################
#
#  Session->GetLastPage()
#
#	Return:		0 - the last page
#
################################################################

sub GetLastPage
	{
	my $Self		= shift;

#? ACTINIC::ASSERT($Self->GetURLInfo()->GetChildNode($Session::XML_LASTPAGE), "Undefined child node.", __LINE__, __FILE__);
	return $Self->GetURLInfo()->GetChildNode($Session::XML_LASTPAGE)->GetNodeValue();
	}

################################################################
#
#  Session->IPCheckFailed() - set invalid PSP IP check flag
#
#	Author: Tamas Viola
#
################################################################

sub IPCheckFailed
	{
	my $Self		= shift;

	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_IPCHECK, "Failed");
	}

################################################################
#
#  Session->IsIPCheckFailed() - check if the PSP IP check failed
#
# 	Output:	0 - $::TRUE if the PSP IP check failed
#
#	Author: Tamas Viola
#
################################################################

sub IsIPCheckFailed
	{
	my $Self		= shift;

	my $pNode = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_IPCHECK);

	if (!$pNode || $pNode->GetNodeValue() ne "Failed")
		{
		return $::FALSE;
		}
	return $::TRUE;
	}

################################################################
#
#  Session->PaymentMade() - mark the transaction as payed
#
#	Author: Tamas Viola
#
################################################################

sub PaymentMade
	{
	my $Self		= shift;

	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_PAYMENT, "True");
	}

################################################################
#
#  Session->ClearPaymentMade() - clears the mark of the transaction as payed
#
#	Author: Tamas Viola
#
################################################################

sub ClearPaymentMade
	{
	my $Self		= shift;

	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_PAYMENT, "");
	}


################################################################
#
#  Session->IsPaymentMade() - check if the transaction is payed
#
# 	Output:	0 - $::TRUE if the transaction is payed
#
#	Author: Tamas Viola
#
################################################################

sub IsPaymentMade
	{
	my $Self		= shift;

	my $pNode = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_PAYMENT);

	if (!$pNode || $pNode->GetNodeValue() ne "True")
		{
		return $::FALSE;
		}
	return $::TRUE;
	}

################################################################
#
#  Session->SetPaypalProIDs() - store paypal pro specific IDs
#
#  Input:  	0 - paypal trasaction ientifier token
#				1 - payer ID 
#
#	Author: Zoltan Magyar
#
################################################################

sub SetPaypalProIDs
	{
	my $Self		= shift;
	my $sToken	= shift;
	my $sPayerID = shift;

	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_PPTOKEN, $sToken);
	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_PPPAYERID, $sPayerID);
	}

################################################################
#
#  Session->GetPaypalProIDs() - retrieve paypal pro specific IDs
#
# 	Output:	0 - paypal trasaction ientifier token
#				1 - payer ID 
#
#	Author: Zoltan Magyar
#
################################################################

sub GetPaypalProIDs
	{
	my $Self		= shift;
	my ($sToken, $sPayerID);
	
	my $pNode = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_PPTOKEN);
	if ($pNode)
		{
		$sToken = $pNode->GetNodeValue();
		}
	undef $pNode;
	
	my $pNode = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_PPPAYERID);
	if ($pNode)
		{
		$sPayerID = $pNode->GetNodeValue();
		}
		
	return ($sToken, $sPayerID);
	}
	
################################################################
#
#  Session->MarkAsClosed() - mark the session as finished
#
################################################################

sub MarkAsClosed
	{
	my $Self		= shift;

	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_CLOSED, "True");
	}

################################################################
#
#  Session->IsClosed() - check if the session is finished
#
# 	Output:	0 - $::TRUE if the session is finished
#
################################################################

sub IsClosed
	{
	my $Self		= shift;

	my $pNode = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_CLOSED);

	if (!$pNode || $pNode->GetNodeValue() ne "True")
		{
		return $::FALSE;
		}
	return $::TRUE;
	}

################################################################
#
#  Session->SetCheckoutStarted() - mark as started
#
################################################################

sub SetCheckoutStarted
	{
	my $Self		= shift;

	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_CHECKOUTSTARTED, "True");
	}

################################################################
#
#  Session->IsCheckoutStarted() - check if the checkout is
#					started once
#
# 	Output:	0 - $::TRUE if the checkout is started
#
################################################################

sub IsCheckoutStarted
	{
	my $Self		= shift;

	my $pNode = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_CHECKOUTSTARTED);

	if (!$pNode || $pNode->GetNodeValue() ne "True")
		{
		return $::FALSE;
		}
	return $::TRUE;
	}

################################################################
#
#  Session->SetDigest() - set the user's digest
#
#  Input:	0 - the user digest
#
################################################################

sub SetDigest
	{
	my $Self		= shift;
	my $sDigest	= shift;

	$Self->{_SESSIONINFO}->SetTextNode($Session::XML_DIGEST, $sDigest);
	}

################################################################
#
#  Session->GetDigest() - get the user digest
#
# 	Output:	0 - the user digest if registered, otherwise empty string
#
################################################################

sub GetDigest
	{
	my $Self		= shift;

	my $pNode = $Self->{_SESSIONINFO}->GetChildNode($Session::XML_DIGEST);

	if ($pNode)
		{
		return  $pNode->GetNodeValue();
		}
	return "";
	}

################################################################
#
#  Session->IsCallBack() -
#
#		check if the session is created during a call-back validation
#
# 	Output:	0 - $::TRUE if launched from call-back
#
#	Author: Tibor Vajda
#
################################################################

sub IsCallBack
	{
	my $Self		= shift;

	return $Self->{_ISCALLBACK};
	}

################################################################
#
#  Session->SetCallBack() - set the Call Back flag
#
# 	Input:	0 - 	Call Back flag: true or false
#
################################################################

sub SetCallBack
	{
	my $Self		= shift;
	my $IsCallBack = shift;

	$Self->{_ISCALLBACK} = $IsCallBack;
	}

################################################################
#
#  Session->SetCoupon() - set the coupon code
#
# 	Input:	0 - 	the coupon code
#
################################################################

sub SetCoupon
	{
	my $Self 	= shift;
	my $sCoupon = shift;
	$Self->GetCheckoutInfo()->GetChildNode('PaymentInfo')->SetTextNode("COUPONCODE", $sCoupon);
	}

################################################################
#
#  Session->SetReferrer() - set the referrer code
#
# 	Input:	0 - 	the referrer code
#
#	Author:	Gordon Camley
#
################################################################

sub SetReferrer
	{
	my $Self 	= shift;
	my $sReferrer = shift;
	$Self->GetCheckoutInfo()->GetChildNode('GeneralInfo')->SetTextNode("USERDEFINED", $sReferrer);
	}

################################################################
#
#  Session->GetReferrer() - get the referrer code
#
# 	Returns the referrer code
#
#	Author:	Gordon Camley
#
################################################################

sub GetReferrer
	{
	my $Self 	= shift;
	my $sReferrer;
	if ($Self->GetCheckoutInfo()->IsElementNode() &&
		 $Self->GetCheckoutInfo()->GetChildNode('GeneralInfo') &&
		 $Self->GetCheckoutInfo()->GetChildNode('GeneralInfo')->GetChildNode("USERDEFINED") &&
		 $Self->GetCheckoutInfo()->GetChildNode('GeneralInfo')->GetChildNode("USERDEFINED")->IsTextNode())
		{
		$sReferrer = $Self->GetCheckoutInfo()->GetChildNode('GeneralInfo')->GetChildNode("USERDEFINED")->GetNodeValue();
		}
	return $sReferrer;
	}

################################################################
#
# Session->UpdateCheckoutInfo()
#		Concerts the old hashes to the new format and stores
#		it in the object. Introduced for compatibility.
#
# Input:		0 - pointer to billing address info
#				1 - pointer to shipping address info
#				2 - pointer to shipping charge info
#				3 - pointer to tax info
#				4 - pointer to general info
#				5 - pointer to payment info
#				6 - pointer to location info
#
#	NOTE: this function desn't save to file only updates the object
#
#	Output:		0 - status
#					1 - error message
#					2 - ""
#
################################################################

sub UpdateCheckoutInfo
	{
	my $Self = shift;
	my ($pBillContact, $pShipContact, $pShipInfo, $pTaxInfo,
		$pGeneralInfo, $pPaymentInfo, $pLocationInfo) = @_;
	#
	# If the cart is already closed then nothing should be changed
	#
	if ($Self->IsClosed())
		{
		return ($::SUCCESS, "", "");
		}
	#
	# Update elements of the checkoutinfo hash node
	#
	$Self->GetCheckoutInfo()->SetChildNode(Element::CreateElementFromLegacyStructure('BillContact', $pBillContact));
	$Self->GetCheckoutInfo()->SetChildNode(Element::CreateElementFromLegacyStructure('ShipContact', $pShipContact));
	$Self->GetCheckoutInfo()->SetChildNode(Element::CreateElementFromLegacyStructure('ShipInfo', $pShipInfo));
	$Self->GetCheckoutInfo()->SetChildNode(Element::CreateElementFromLegacyStructure('TaxInfo', $pTaxInfo));
	$Self->GetCheckoutInfo()->SetChildNode(Element::CreateElementFromLegacyStructure('GeneralInfo', $pGeneralInfo));
	$Self->GetCheckoutInfo()->SetChildNode(Element::CreateElementFromLegacyStructure('PaymentInfo', $pPaymentInfo));
	$Self->GetCheckoutInfo()->SetChildNode(Element::CreateElementFromLegacyStructure('LocationInfo', $pLocationInfo));

	return ($::SUCCESS, "", "");
	}

################################################################
#
# Session->RestoreCheckoutInfo
#	Read the checkout status from object
#
# Output: 	0 - status code
#				1 - error message if any
#				2 - pointer to billing address info
#				3 - pointer to shipping address info
#				4 - pointer to shipping charge info
#				5 - pointer to tax info
#				6 - pointer to general info
#				7 - pointer to payment info
#				8 - pointer to the location info
#
################################################################

sub RestoreCheckoutInfo
	{
	my $Self 			= shift;
	#
	# Construct the return values in the legacy structure for compatibility
	#
#? ACTINIC::ASSERT($Self->GetCheckoutInfo()->GetChildNode('BillContact'), "Undefined child node BillContact.", __LINE__, __FILE__);
#? ACTINIC::ASSERT($Self->GetCheckoutInfo()->GetChildNode('ShipContact'), "Undefined child node ShipContact.", __LINE__, __FILE__);
#? ACTINIC::ASSERT($Self->GetCheckoutInfo()->GetChildNode('ShipInfo'), "Undefined child node ShipInfo.", __LINE__, __FILE__);
#? ACTINIC::ASSERT($Self->GetCheckoutInfo()->GetChildNode('TaxInfo'), "Undefined child node TaxInfo.", __LINE__, __FILE__);
#? ACTINIC::ASSERT($Self->GetCheckoutInfo()->GetChildNode('GeneralInfo'), "Undefined child node GeneralInfo.", __LINE__, __FILE__);
#? ACTINIC::ASSERT($Self->GetCheckoutInfo()->GetChildNode('PaymentInfo'), "Undefined child node PaymentInfo.", __LINE__, __FILE__);
#? ACTINIC::ASSERT($Self->GetCheckoutInfo()->GetChildNode('LocationInfo'), "Undefined child node LocationInfo.", __LINE__, __FILE__);
	return ($::SUCCESS, '',
				$Self->GetCheckoutInfo()->GetChildNode('BillContact')->ToLegacyStructure(),
				$Self->GetCheckoutInfo()->GetChildNode('ShipContact')->ToLegacyStructure(),
				$Self->GetCheckoutInfo()->GetChildNode('ShipInfo')->ToLegacyStructure(),
				$Self->GetCheckoutInfo()->GetChildNode('TaxInfo')->ToLegacyStructure(),
				$Self->GetCheckoutInfo()->GetChildNode('GeneralInfo')->ToLegacyStructure(),
				$Self->GetCheckoutInfo()->GetChildNode('PaymentInfo')->ToLegacyStructure(),
				$Self->GetCheckoutInfo()->GetChildNode('LocationInfo')->ToLegacyStructure());
	}

################################################################
#
# Session->IsCheckoutInfoChanged
#	Compare the passed in info hash with the stored values
#
# Input:		0 - the node name to compare (e.g. 'TaxInfo')
#				1 - the associated hash (e.g. $::g_TaxInfo)
#
# Output: 	0 - status code ($::TRUE/$::FALSE)
#
# Author: Zoltan Magyar - 3:06 PM 12/19/2002
#
################################################################

sub IsCheckoutInfoChanged
	{
	my $Self 		= shift;
	my $sNodeName 	= shift;
	my $pHash		= shift;
	#
	# If the node doesn't exist then it couln't be changed
	#
	if (!defined $Self->GetCheckoutInfo() ||
		 !defined $Self->GetCheckoutInfo()->GetChildNode($sNodeName))
		{
		return $::FALSE;									# therefore return false
		}
	#
	# Get the node if we are sure it exists and see if there is any child nodes
	#
	my $pBaseNode = $Self->GetCheckoutInfo()->GetChildNode($sNodeName);
	if (!$pBaseNode->IsElementNode())				# no child node?
		{
		return $::FALSE;									# couldn't be changed
		}
	#
	# If there are child nodes then get each node value and compare with the hash values
	#
	for (my $i = 0; $i < $pBaseNode->GetChildNodeCount(); $i++)
		{
		my $pChildNode = $pBaseNode->GetChildNodeAt($i);
		#
		# Compare values
		#
		if ($pHash->{$pChildNode->GetTag()} != $pChildNode->GetNodeValue())
			{
			return $::TRUE;								# not the same? Then indicate changed state
			}
		}
	return $::FALSE;										# if we are here then then values are identical
	}

################################################################
#
# Session->GetCartObject - restore the cart details from the
# 		session file if exists
#
# Input:		0 - if true then closed cart indicator
#						is ignored (optional)
#
# Output:	0 - status
#				1 - error message
#				2 - Cart object
#
################################################################

sub GetCartObject
 	{
 	my $Self				= shift;
	my $bIgonreClose 	= shift;
	#
	# If the cart is closed and ignore is not required then pass back
	# failure and empty hashes
	#
	if ($Self->IsClosed() && !$bIgonreClose)
		{
		return ($::EOF, ACTINIC::GetPhrase(-1, 1282), []);
		}
 	#
 	# See if the cart object is already created
 	#
 	if (!defined $Self->{_CART})
 		{
		#
		# Create the cart object if it hasn't been done
		#
		require <Actinic:Variable Name="CartPackage"/>;
		#
		# If the cart is not empty then init by the existing values
		# otherwise use empty cart
		#
#? ACTINIC::ASSERT($Self->{_SESSIONINFO}->GetChildNode($Session::XML_SHOPPINGCART), "Undefined child node ShoppingCart.", __LINE__, __FILE__);
		if ($Self->{_SESSIONINFO}->GetChildNode($Session::XML_SHOPPINGCART)->IsElementNode())
			{
			$Self->{_CART} = Cart::new("Cart", $Self->{_SESSIONID}, $Self->{_PATH}, $Self->GetCartInfo()->GetChildNodes(), $Self->IsCallBack());
			}
		else
			{
			$Self->{_CART} = Cart::new("Cart", $Self->{_SESSIONID}, $Self->{_PATH}, [], $Self->IsCallBack());
			}
		}
	return ($::SUCCESS, "", $Self->{_CART});
 	}

##############################################################################################################
#
# Save/Restore functions
#
##############################################################################################################
################################################################
#
# Session->RestoreSession - restore the session data from the
# 		session file if exists
#
################################################################

sub RestoreSession
 	{
 	my $Self	= shift;
 	my $sFileName 	= $Self->GetSessionFileName($Self->{_SESSIONID});
 	#
 	# check if we have PayPal or Nochex enabled here and lock the session file only in this case
 	#
 	my $bSessionLockIsNeeded = $::FALSE;
 	if (defined $::g_pPaymentList &&
 		(($$::g_pPaymentList{$::PAYMENT_PAYPAL}{ENABLED} == 1)	||	# PayPal exists and enabled
 		 ($$::g_pPaymentList{$::PAYMENT_NOCHEX}{ENABLED} == 1)))		# or Nochex exists and enabled
 		{
 		$bSessionLockIsNeeded = $::TRUE;
 		}
	#
 	# If the session file doesn't exist then try to
 	# restore from the old data format
 	#
 	if (! (-e $sFileName)  ||							# the file doesn't exist
 		    -z $sFileName)								# or zero length
 		{
 		#
 		# Indicate new file creation
 		#
 		$Self->{_NEWSESSIONFILE} = $::TRUE;
 		#
 		# Try to restore old chk file
 		#
 		my @Response = $Self->RestoreOldChkFile($Self->{_PATH} . $Self->{_SESSIONID} . ".chk");
 		#
 		# If the old session format doesn't exist then
 		# try to extract it from the cookie
 		#
 		if ($Response[0] != $::SUCCESS)
 			{
 			if ($::FAILURE == $Self->CookieStringToContactDetails())		# if there isn't contact details cookie
 				{
 				$Self->UpdateCheckoutInfo({}, {}, {}, {}, {}, {}, {});	# reset the data structure
 				}
 			}
 		}
	else
		{
	 	#
	 	# Otherwise restore the data from the file
	 	#
	 	$Self->GetXMLTree();
		}
	if ($bSessionLockIsNeeded == $::TRUE)
		{
		if ($Self->{_LOCKER}->Lock() != $SessionLock::SUCCESS)	# try to get the lock
			{
			ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 2310, $sFileName), $Self->GetSessionFileFolder());
			}
		}
 	}

################################################################
#
# Session->GetSessionFileFolder - get the folder where session files should be
#
# Return: 	0 - the path to session files
#
################################################################

 sub GetSessionFileFolder
 	{
 	my $Self			= shift;
 	#
 	# Check if alternate location is specified for session files
 	#
 	if ($$::g_pSetupBlob{'PATH_TO_CART'} ne "" &&# we have alternate location
 		!$ACTINIC::ActinicHostMode)					# and we are not in host mode
 		{
 		return($$::g_pSetupBlob{'PATH_TO_CART'});
 		}
 	else
 		{
	 	return($Self->{_PATH});
	 	}
 	}

################################################################
#
# Session->Unlock - use customver specified permission on
#		the selected file
#
# Input:		0 - the file name
#
################################################################

 sub Unlock
 	{
 	my $Self			= shift;
 	my $sFile		= shift;
 	#
 	# Check if alternate permission is specified for session files
 	#
 	if ($$::g_pSetupBlob{'CART_PERMISSIONS_UNLOCK'} ne "" &&	# we have alternate location
 		!$ACTINIC::ActinicHostMode)					# and we are not in host mode
 		{
 		chmod oct($$::g_pSetupBlob{'CART_PERMISSIONS_UNLOCK'}), $sFile;
 		}
 	else
 		{
	 	ACTINIC::ChangeAccess("rw", $sFile);
	 	}
 	}

################################################################
#
# Session->Lock - use customver specified permission on
#		the selected file
#
# Input:		0 - the file name
#
################################################################

 sub Lock
 	{
 	my $Self			= shift;
 	my $sFile		= shift;
 	#
 	# Check if alternate permission is specified for session files
 	#
 	if ($$::g_pSetupBlob{'CART_PERMISSIONS_LOCK'} ne "" &&	# we have alternate permission
 		!$ACTINIC::ActinicHostMode)					# and we are not in host mode
 		{
 		chmod oct($$::g_pSetupBlob{'CART_PERMISSIONS_LOCK'}), $sFile;
 		}
 	else
 		{
	 	ACTINIC::ChangeAccess("", $sFile);
	 	}
 	}

################################################################
#
# Session->GetXMLTree - get the tree of session file content
#
# Input: 	0 - the session file content
#
# Affects:	- $Self->{_SESSIONINFO}
#
################################################################

 sub GetXMLTree
 	{
 	my $Self			= shift;
	my $sFileName  = $Self->GetSessionFileFolder() . $Self->{_SESSIONFILE};
 	my $pParser 	= new PXML;
 	#
 	# Create parser object and get the tree of XML tags
 	#
 	$Self->Unlock($sFileName);							# allow rw access on the file
	my @Response = $pParser->ParseFile($sFileName);
	$Self->Lock($sFileName);							# restore file permission
	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], $Self->GetSessionFileFolder());
		}
	#
	# Save the tree
	#
	$Self->{_SESSIONINFO} = new Element(@{$Response[2]}[0]);
 	}

################################################################
#
# Session->SaveSession - save the session info to file
#
################################################################

 sub SaveSession
 	{
 	my $Self			= shift;
 	my $sFileName 	= $Self->GetSessionFileFolder() . $Self->{_SESSIONFILE};
 	my $pParser 	= new PXML;
 	#
 	# Update the cart content before save
 	#
 	if ($Self->{_CART})									# did we use the cart object?
 		{
 		$Self->{_CART}->UpdateCart();
		$Self->SetCartInfo($Self->{_CART}->GetCart());
		}
 	#
 	# Create parser object and get the tree of XML tags
 	#
	my $pXmlRoot = [$Self->{_SESSIONINFO}];

	$Self->Unlock($sFileName);							# allow rw access on the file
	my @Response = $pParser->SaveXMLFile($sFileName, $pXmlRoot);
	$Self->Lock($sFileName);							# restore file permission
	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], $Self->GetSessionFileFolder());
		}
 	}

################################################################
#
# Session->ClearOldFiles - Remove any old files
#
################################################################

sub ClearOldFiles
   {
   my $Self = shift;
   my $sPath = $Self->GetSessionFileFolder();

	my (@FileList, @Response, $Status, $Message);

	@Response = ACTINIC::ReadTheDir($sPath);		# read the contents of the directory
	($Status, $Message, @FileList) = @Response;	# get a copy of the directory listing
	if ($Status != $::SUCCESS)
		{
		return;
		}

	my ($sFile, $sFilePath, @stat, $Now, $LifeSpan);
   foreach $sFile (@FileList)							# look at the files in the directory
		{
		#
		# We should deal with the old files as well.
		# Note that the OPN and LCK files will be deleted when the session file is deleted
		#
		my (@FileParts);
		@FileParts = split (/\./, $sFile);			# break the file name into parts separated by "."
		my $sExtension = $FileParts[$#FileParts];	# determine the file extension
		if ($sExtension ne "chk" &&					# if the extension is neither the old or
			 $sExtension ne "cart" &&					# new session file
			 $sExtension ne "done" &&
			 $sExtension ne "save" &&
			 $sExtension ne "session" &&
			 $sExtension ne "stk" &&
			 $sExtension ne "mail")
			{
			next;												# the skip the file
			}

		$sFilePath = $sPath.$sFile;					# now let's build the entire file path

		@stat = stat $sFilePath;						# get the file stat info

		$Now = time;										# get the current time
		#
		# Determine the life span of the file
		# Default to the cart expiry
		#
		$LifeSpan = 60 * 60 * $$::g_pSetupBlob{'CART_EXPIRY'};
		my $bMySavedUnRegCart = $::FALSE;
		
		if ($sExtension eq "save")					# shopping list file?
			{
			#
			# check for registered user's shopping list file names
			#
			if ($FileParts[-2] =~ /^reg_(\d*)_(\d*)$/)
				{
				$LifeSpan = 60 * 60 * 24 * $$::g_pSetupBlob{'REG_SHOPPING_LIST_EXPIRY'};
				}
			else
				{
				if ($FileParts[-2] =~ /^$Self->{_OLDSESSIONID}_(\d*)$/)
					{
					$bMySavedUnRegCart = $::TRUE;		# we are looking at a saved cart for this unregistered customer
					}
				$LifeSpan = 60 * 60 * 24 * $$::g_pSetupBlob{'UNREG_SHOPPING_LIST_EXPIRY'};
				}
			}

		if ( ($Now - $LifeSpan) < $stat[9])			# if the exipiration time is younger than the file
			{
			#
			# Find the most recent
			#
			if ($bMySavedUnRegCart &&
				 ($stat[9] > $Self->{_NEWESTSAVEDCARTTIME}))
				{
				$Self->{_NEWESTSAVEDCARTTIME} = $stat[9];	# save the file date of the most recently saved cart
				}
			next;												# skip it
			}

		ACTINIC::ChangeAccess("rw", $sFilePath);	# make the file writable
		ACTINIC::SecurePath($sFilePath);				# make sure only valid filename characters exist in $file to prevent hanky panky

		if ($sExtension eq "session")					# if it is the session that we are deleting
			{													# then delete any related OPN or LCK files
			if (-e "$sFilePath.OPN")
				{
				unlink "$sFilePath.OPN";				# delete the .OPN file using full path
				}
			if (-e "$sFilePath.LCK")
				{
				unlink "$sFilePath.LCK";				# delete the .LCK file using full path
				}
			}
		unlink ($sFilePath);								# if we got here, the file is a cart and is old, remove it
		}
   }

################################################################
#
# Session->CheckForBadPaths - ensure we don't allow access to 
#										non actinic files
#
################################################################
sub CheckForBadPaths
	{
	if (defined $::g_InputHash{PRODUCTPAGE})		# AccountsScript product page
		{
		ACTINIC::CheckSafeFilePath($::g_InputHash{PRODUCTPAGE});
		}
	if (defined $::g_InputHash{PAGEFILENAME})		# SearchScript product page
		{
		ACTINIC::CheckSafeFilePath($::g_InputHash{PAGEFILENAME});
		}
	if (defined $::g_InputHash{DESTINATION})		# Referrer script target page
		{
		ACTINIC::CheckSafeFilePath($::g_InputHash{DESTINATION});
		}
	}

################################################################
#
# Session->InitURLs - update the URL info entries
#
# Affects: 	URLInfo entries
#
################################################################
################################################################
#
# Note: This function deals with the Base URL and page history
# determination and maintenance.
#
# DO NOT CHANGE IT UNLESS YOU ARE PRETTY SURE ABOUT THE EFFECTS
#
################################################################
################################################################

sub InitURLs
	{
	my $Self = shift;
	my $sReferrer = ACTINIC::GetReferrer();
	my $bExpired = $::FALSE;							# expired session indicator
	#############################################################
	#
	# Update the last page
	#
	#############################################################
	$Self->GetURLInfo()->SetTextNode($Session::XML_LASTPAGE, $sReferrer);

	#############################################################
	#
	# Update the last shop page if required
	#
	#############################################################
	my ($sDigest,$sBaseFile) = ACTINIC::CaccGetCookies();
	my $sLocalPage;
	if( $sDigest )											# In B2B construct path to account script
		{
		#
		# Check if we are from the login page
		#
		if (($sReferrer =~ /$::g_sAccountScriptName$/i) &&
			 ($sReferrer !~ /\?/))						# needed in case script name is on end of a parameter such as ACTINIC_REFERRER
			{
			my ($sBodyPage, $sProductPage) = ACTINIC::CAccCatalogBody();
			$sReferrer .= "?PRODUCTPAGE\=" . $sBodyPage;
			}
		$sReferrer =~ /$::g_sAccountScriptName.*(\?|&)PRODUCTPAGE\=\"?(.*?)\"?(&|$)/i;
		if ((ACTINIC::IsStaticPage($2)) &&
			 ((!$$::g_pSetupBlob{USE_FRAMES}) ||
			  (!ACTINIC::IsFramePage($2))))
			{
			if (defined $::g_InputHash{SHOP} &&		# in host mode we have to add the ShopID
				$sReferrer !~ /[\?|\&]SHOP=/)			# if not defined yet in the query
				{
				my $sShop = 'SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE);
				$sReferrer =~ s/$::g_sAccountScriptName\?/$::g_sAccountScriptName\?$sShop\&/i;
				}
			$Self->GetURLInfo()->SetTextNode($Session::XML_LASTSHOPPAGE, $sReferrer);
			}
		}
	elsif (ACTINIC::IsStaticPage($sReferrer) &&	# if this is a static page
			(!$::g_InputHash{BPN}))						# and BPN is not defined
		{
		#
		# See if frames are used
		#
		my $sLocalPage = $sReferrer;
		my $sFileName = $sReferrer;
		$sFileName =~ s/.*\/([^\/\=]+$)/$1/;		# get the filename
		my ($bFramePage) = ACTINIC::IsFramePage($sFileName);	# true if the call is from frame other than CatalogBody
		#
		# Don't use the current item if it looks like it came from a third party server (e.g. PSP "Back" operations).  This
		# is determined by the following rules:
		#
		# 1) We already have a shop page
		# 2) The server is not the same as the last shop page
		#
		my ($sOriginalServer, $sNewServer);
		$sLocalPage =~ m|https?://([-.a-zA-Z0-9]+)|; # get the server part
		$sNewServer = lc $1;

		if (!$bFramePage)									# no need to save if from frame outside CatalogBody
			{
			if ($Self->GetURLInfo()->GetChildNode($Session::XML_LASTSHOPPAGE) &&
				 $Self->GetLastShopPage())					# if there is an "original" static page
				{
				$Self->GetLastShopPage() =~ m|https?://([-.a-zA-Z0-9]+)|; # get the server part
				$sOriginalServer = lc $1;
				}

			unless ($Self->GetURLInfo()->GetChildNode($Session::XML_LASTSHOPPAGE) &&
					  $Self->GetLastShopPage() &&			# we already have a "last shop page" and
					  ($sOriginalServer ne $sNewServer))# the servers are different
				{
				$Self->GetURLInfo()->SetTextNode($Session::XML_LASTSHOPPAGE, $sLocalPage);
				}
			}
		}
	elsif ($::g_InputHash{BPN})						# BPN is defined
		{
		$Self->GetURLInfo()->SetTextNode($Session::XML_LASTSHOPPAGE, $$::g_pSetupBlob{CATALOG_URL} . $$::g_pSetupBlob{CATALOG_PAGE});
		}
	#
	# If LASTSHOPPAGE has still not been set, set to default page
	# This only happens when the session is expired
	#
	if (!$Self->GetURLInfo()->IsElementNode() ||
		($Self->GetURLInfo()->IsElementNode() &&
		!$Self->GetURLInfo()->GetChildNode($Session::XML_LASTSHOPPAGE)))
		{
		$Self->GetURLInfo()->SetTextNode($Session::XML_LASTSHOPPAGE, $$::g_pSetupBlob{CATALOG_URL} . $$::g_pSetupBlob{CATALOG_PAGE});
		$bExpired = $::TRUE;
		}

	#############################################################
	#
	# The BASEURL should only be updated at the beginning
	# of the session
	#
	#############################################################
	my $sBaseURLInfo;
	#
	# Determine the current base url info
	#
	if ($Self->GetURLInfo()->IsElementNode() &&
		 $Self->GetURLInfo()->GetChildNode($Session::XML_BASEURL) &&
		 $Self->GetURLInfo()->GetChildNode($Session::XML_BASEURL)->IsTextNode())
		{
		$sBaseURLInfo = $Self->GetURLInfo()->GetChildNode($Session::XML_BASEURL)->GetNodeValue();
		}
	if (!defined $sBaseURLInfo ||						# if there isn't base url info yet or it is deleted
		 $sBaseURLInfo eq "")
		{
		if (!ACTINIC::IsStaticPage($sReferrer))	# only use static page for base page
			{
			$sReferrer = "";
			}
		else
			{
			#
			# Be sure that the base URL doesn't contain file name
			#
			$sReferrer =~ s|/[^/]*$|/|;					# strip file name if any
			#
			# If ACTINIC_REFERRER is not defined then it must be a call inside Catalog or Brochure
			# we should check the case when it comes from the Brochure index page which is
			# not in the /acatalog directory
			#
			if (!defined $::g_InputHash{ACTINIC_REFERRER})
				{
				$sReferrer =~ m|[^/]/([^/]+)/$|;		# get the last dir of the URL
				#
				# We don't check for matches above because the unmatch is used below
				#
				my $sLastDir = $1;
				if ($$::g_pSetupBlob{CATALOG_URL} !~ /$sLastDir\/$/ ||	# is it the same as the catalog URL (http://server/path/)?
					 !defined $sLastDir)					# if the last dir is not defined (http://server/)
					{											# it is different so we should check for brochure index page
					#
					# Check that the referrer's last dir is the same as the directory above
					# /acatalog. If so then modify it to get the correct URL of catalog
					# But note if the server is configured to have a virtual server
					# which hides /acatalog
					#
					if ($$::g_pSetupBlob{CATALOG_URL} !~ /\/\/[^\/]+\/$/ &&
						$$::g_pSetupBlob{CATALOG_URL} =~ /$sLastDir\/([^\/]+)\/$/)
						{
						$sReferrer .= $1 . "/";			# fix the referrer
						}
					}
				}
			}
		#
		# If we still don't have referrer then use the hard coded one
		#
		if (!$sReferrer ||								# if the referrer is not defined
			 !ACTINIC::IsStaticPage($sReferrer))	# or it isn't a static page
			{													# fall back to hard coded value
			$sReferrer = $$::g_pSetupBlob{CATALOG_URL};
			}
		#
		# Check if the cart is expired and the determined base URL
		# looks like a CGI url
		#
		if ($bExpired)
			{
			$sReferrer =~ s/\/[^\/]*$/\//;			# strip file name if any
			$sReferrer =~ /[^\/]\/([^\/]+)\/$/;		# get the last dir of the URL

			my $sLastDir = $1;
			if (defined $sLastDir &&					# got lastdir
				 $$::g_pSetupBlob{CGI_URL} =~ /$sLastDir\/$/)	# and looks like CGI
				{
				$sReferrer = $$::g_pSetupBlob{CATALOG_URL};	# fall back to hard coded
				}
			}
		$Self->GetURLInfo()->SetTextNode($Session::XML_BASEURL, $sReferrer);
		}
	}

################################################################
#
# Session->ContactDetailsToCookieString
#	Convert the current contact details into a cookie string.
#	If the remember me flag is false, only save the state of
#	the remember me flag.
#
# Expects: $Self->{_SESSIONINFO}
#
# Output:	0 - the cookie
#
################################################################

sub ContactDetailsToCookieString
	{
	my $Self = shift;
	#
	# Variables
	#
	my ($Status, $Message, $pBillContact, $pShipContact, $pShipInfo, $pTaxInfo,
		$pGeneralInfo, $pPaymentInfo, $pLocationInfo) = $Self->RestoreCheckoutInfo();
	my $sCookie;
	#
	# If REMEMBERME is not defined, then...
	#
	if (!$$pBillContact{'REMEMBERME'})
		{
		$sCookie .= $ACTINIC::BILLCONTACT."\n";	# write the data chunk name
		$sCookie .= "REMEMBERME=0\n";					# just write the remember me flag
		$sCookie .= "\n";									# end the hash table with a blank line
		#
		# now encode the entire cookie to eliminate problems with newlines, equals, etc.
		#
		$sCookie = "ACTINIC_CONTACT=\"" . ACTINIC::EncodeText2($sCookie, $::FALSE) . "\"";
		return ($sCookie);
		}
	#
	# Create helper hash
	#
	my %hContactDetails = (
		$ACTINIC::BILLCONTACT => $pBillContact,
		$ACTINIC::SHIPCONTACT => $pShipContact,
		$ACTINIC::SHIPINFO => $pShipInfo,
		$ACTINIC::TAXINFO => $pTaxInfo,
		$ACTINIC::PAYMENTINFO => $pPaymentInfo,
		$ACTINIC::LOCATIONINFO => $pLocationInfo,
		$ACTINIC::GENERALINFO => $pGeneralInfo
	);
	#
	# Loop the helper hash created above
	#
	my ($sKeyContactDetails, $pValueContactDetails, $Temp);
	while (($sKeyContactDetails, $pValueContactDetails) = each %hContactDetails)
		{
		$sCookie .= $sKeyContactDetails."\n";		# write the data chunk name
		my ($key, $value, $temp);
		if (ref($pValueContactDetails) eq 'HASH')
			{
			while (($key, $value) = each %{$pValueContactDetails})	# write every entry in the hash
				{
				if (($sKeyContactDetails eq $ACTINIC::BILLCONTACT) &&	# skip the T&C, to enable the user to check this
				    ($key eq "AGREEDTANDC"))
					{
					next;
					}
				if (($sKeyContactDetails eq $ACTINIC::SHIPINFO) && (
				    ($key eq "ADVANCED") ||			# skip the shipping and handling opaque data since it is too easy
				    ($key eq "HANDLING")))				# to corrupt
					{
					next;
					}
				if (($sKeyContactDetails eq $ACTINIC::GENERALINFO) &&
				    ($key eq "USERDEFINED") &&		# skip referrer code
					 (ACTINIC::IsPromptHidden(4, 2)))	# if prompt is hidden i.e. this is the source from referrer.pl
					{
					next;
					}
				if (($sKeyContactDetails eq $ACTINIC::PAYMENTINFO) && (
				    ($key eq "ORDERNUMBER") ||		# skip order number, purchase order number
				    ($key eq "COUPONCODE")  ||		# and coupon code
				    ($key eq "PONO")))					# because these won't be the same on next purchase
				   {
				   next;
				   }
				$sCookie .= ACTINIC::EncodeText2($key, $::FALSE) . "=" . ACTINIC::EncodeText2($value, $::FALSE) . "\n"; # write the data
				}
			$temp = keys %$pValueContactDetails;	# reset the iterator for "each"
			}
		$sCookie .= "\n";									# end the hash table with a blank line
		}
	$Temp = keys %hContactDetails;					# reset the iterator for "each"
	#
	# now encode the entire cookie to eliminate problems with newlines, equals, etc.
	#
	$sCookie = "ACTINIC_CONTACT=\"" . ACTINIC::EncodeText2($sCookie, $::FALSE) . "\"";

	$Self->{_COOKIESTRING} = $sCookie;				# store the cookie internally
	return ($sCookie);									# and return it
	}

################################################################
#
# Session->CookieStringToContactDetails
#	read the checkout status from the cookie.
#
# Affects: $Self->{_SESSIONINFO}
#
# Return:	$::SUCCESS - if the cookie is restored
#				$::FAILURE - otherwise
#
################################################################

sub CookieStringToContactDetails
	{
	my $Self = shift;
	my $sContactDetails = $Self->{_COOKIESTRING};
	#
	# read the hashes from the cookie - one at a time in the order listed below
	#
	my (%BillContact, %ShipContact, %ShipInfo, %TaxInfo, %GeneralInfo, %PaymentInfo, %LocationInfo);

	if (!$sContactDetails)								# if the file does not exist, return empty hashes
		{
		$Self->UpdateCheckoutInfo(\%BillContact, \%ShipContact, \%ShipInfo, \%TaxInfo, \%GeneralInfo, \%PaymentInfo, \%LocationInfo);
		return $::FAILURE;
		}
	#
	# decode the cookie and build a list of lines from it
	#
	$sContactDetails = ACTINIC::DecodeText($sContactDetails, $ACTINIC::FORM_URL_ENCODED);
	my @Lines = split(/\n/, $sContactDetails);
	#
	# outer loop reads the hash names
	#
	my ($key, $value, $Temp, $sLine, $pHash);
	foreach $sLine (@Lines)								# read the next line
		{
		if ($sLine eq $ACTINIC::BILLCONTACT)		# determine which has is being read and
			{
			$pHash = \%BillContact;						# refer $pHash to it
			}
		elsif ($sLine eq $ACTINIC::SHIPCONTACT)
			{
			$pHash = \%ShipContact;
			}
		elsif ($sLine eq $ACTINIC::SHIPINFO)
			{
			$pHash = \%ShipInfo;
			}
		elsif ($sLine eq $ACTINIC::TAXINFO)
			{
			$pHash = \%TaxInfo;
			}
		elsif ($sLine eq $ACTINIC::GENERALINFO)
			{
			$pHash = \%GeneralInfo;
			}
		elsif ($sLine eq $ACTINIC::PAYMENTINFO)
			{
			$pHash = \%PaymentInfo;
			}
		elsif ($sLine eq $ACTINIC::LOCATIONINFO)
			{
			$pHash = \%LocationInfo;
			}
		#
		# a blank line indicates EOH (end of hash)
		#
		elsif ($sLine eq '')								# if the line is blank - EOH
			{
			next;												# exit loop
			}
		else
			{
			($key, $value) = map {ACTINIC::DecodeText($_, $ACTINIC::FORM_URL_ENCODED)} split (/=/, $sLine); 	# parse the line and decode it
			$$pHash{$key} = $value;						# add this key to the hash
			}
		}

	$Self->UpdateCheckoutInfo(\%BillContact, \%ShipContact, \%ShipInfo, \%TaxInfo, \%GeneralInfo, \%PaymentInfo, \%LocationInfo);
	return $::SUCCESS;
	}

################################################################
#
# Session->RetrieveCheckoutStatus - read the checkout
#	status from	disk.
#
# Input:		0 - the file path
#				1 - cart id
#				2 - optional closed cart indicator
#
# Output: 	0 - status code
#				1 - error message if any
#				2 - pointer to billing address info
#				3 - pointer to shipping address info
#				4 - pointer to shipping charge info
#				5 - pointer to tax info
#				6 - pointer to general info
#				7 - pointer to payment info
#				8 - pointer to the location info
#
################################################################

sub RestoreOldChkFile
	{
	my $Self	= shift;
	my $sFilename = shift;
	my (%BillContact, %ShipContact, %ShipInfo, %TaxInfo, %GeneralInfo, %PaymentInfo, %LocationInfo);

	$::BILLCONTACT 	= "INVOICE";
	$::SHIPCONTACT 	= "DELIVERY";
	$::SHIPINFO 		= "SHIPPING";
	$::TAXINFO 			= "TAX";
	$::GENERALINFO 	= "GENERAL";
	$::PAYMENTINFO 	= "PAYMENT";
	$::LOCATIONINFO 	= "LOCATION";

	unless (open (CKFILE, "<$sFilename"))			# open the file
		{
		my ($sError);
		$sError = $!;
		ACTINIC::ChangeAccess('', $sFilename);		# lock the file
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sFilename, $sError), 0, 0);
		}
	#
	# outer loop reads the hash names
	#
	my ($key, $value, $Temp, $sLine, $pHash);
	while (defined ($sLine = <CKFILE>))				# read the next line
		{
		chomp $sLine;
		if ($sLine eq $::BILLCONTACT)					# determine which has is being read and
			{
			$pHash = \%BillContact;						# refer $pHash to it
			}
		elsif ($sLine eq $::SHIPCONTACT)
			{
			$pHash = \%ShipContact;
			}
		elsif ($sLine eq $::SHIPINFO)
			{
			$pHash = \%ShipInfo;
			}
		elsif ($sLine eq $::TAXINFO)
			{
			$pHash = \%TaxInfo;
			}
		elsif ($sLine eq $::GENERALINFO)
			{
			$pHash = \%GeneralInfo;
			}
		elsif ($sLine eq $::PAYMENTINFO)
			{
			$pHash = \%PaymentInfo;
			}
		elsif ($sLine eq $::LOCATIONINFO)
			{
			$pHash = \%LocationInfo;
			}
		#
		# the inner loop reads the hash fields - a blank line indicates EOH (end of hash)
		#
		while (defined ($sLine = <CKFILE>))			# read the next line
			{
			chomp $sLine;
			if ($sLine eq '')								# if the line is blank - EOH
				{
				last;											# exit loop
				}
			($key, $value) = split (/\|\|G\|\|/, $sLine);	# parse the line ("||G||" separated
			$$pHash{$key} = $value;						# add this key to the hash
			}
		}

	close (CKFILE);

	$Self->UpdateCheckoutInfo(\%BillContact, \%ShipContact, \%ShipInfo, \%TaxInfo, \%GeneralInfo, \%PaymentInfo, \%LocationInfo);
	}

################################################################
#
# CreateSessionID - If the Session ID does not exist,
# 		create a new unique session id.
#
# Expects:	the file path ($Self->{_PATH}) must be defined
#
# Affects: 	the result is written to $Self->{_SESSIONID}
#
# Output: 	0 - status code
#				1 - error message if any
#				2 - cart ID
#
################################################################

sub CreateSessionID
	{
	my $Self = shift;

	$::bCookieCheckRequired = $::TRUE;				# cookie checking must be added to the next generated html page

	my ($sCartID, $sPath);
	$sPath = $Self->GetSessionFileFolder();
	#
	# Check if we have done it already and have a cart ID
	#
	if (defined $Self->{_SESSIONID} &&
		 $Self->{_SESSIONID} ne '')
		{
		return;
		}

	if (!$sCartID)											# if the id does not exist or is meaningless (empty, 0, etc.)
		{
		my $sClient;
		if (length $::ENV{REMOTE_HOST} > 0)			# attempt to use the host name for the cart id
			{
			$sClient = $::ENV{REMOTE_HOST};
			}
		else													# if the hostname is empty, use the host address
			{
			$sClient = $::ENV{REMOTE_ADDR};			# use the ip address
			}
		$sClient =~ s/[^a-zA-Z0-9]/Z/g;

		$sCartID = $sClient . 'A' . time . 'B' . $$; # generate a cookie name that should be mostly unique

		my ($sCartFile, $bTriedToRemove, @Response);
		$sCartFile = $Self->GetSessionFileName($sCartID); # get the associated filename

		$bTriedToRemove = $::FALSE;					# trap loops

		my $nIndex = 0;
		my $sBase = $sCartID;							# get the base name
		while (-f $sCartFile)							# if the cart file already exists
			{
			my (@stat);
			@stat = stat $sCartFile;					# get the date of the file

			if ($stat[9] < (time - 60 * 60 * 2) &&	# if the file is more than 2 hours old
				 !$bTriedToRemove)						# and we have not already tried to remove the file
				{
				ACTINIC::ChangeAccess("rw", $sCartFile);		# make the file writable
				ACTINIC::SecurePath($sCartFile);		# make sure only valid filename characters exist in $file to prevent hanky panky
				unlink ($sCartFile);						# assume the file is no longer in use - remove it
				$bTriedToRemove = $::TRUE;				# prevent infinite loops if I don't have permission to remove
				}
			else												# if the file is current
				{
				$sCartID = $sBase . 'C' . $nIndex;	# find a new cart id (cat on the process ID)
				$sCartFile = $Self->GetSessionFileName($sCartID); # get the new filename
				$bTriedToRemove = $::FALSE;			# try to remove it again
				}
			$nIndex++;
			}
		#
		# NOW WE HAVE A UNIQUE CART ID
		#
		ACTINIC::SecurePath($sCartFile);				# make sure only valid filename characters exist in $file to prevent hanky panky
		unless (open (GCIFILE, ">$sCartFile"))		# create the cart file so other processes know you got it
			{
			return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sCartFile, $!), 0, 0);
			}
		close (GCIFILE);									# done with this file
		ACTINIC::ChangeAccess('', $sCartFile);		# lock the file
		}
	#
	# Store the ID in a global variable to avoid its recreation within the same seesion
	#
	$Self->{_SESSIONID} = $sCartID;

	return ($::SUCCESS, '', $sCartID, 0);
	}

################################################################
#
# GetSessionFileName - retrieve the session filename
#
# Input:		0 - session id
#
# Output:	0 - cart file name
#
################################################################

sub GetSessionFileName
	{
	my $Self = shift;
	my $sID 	= shift;
	my $sPath = $Self->GetSessionFileFolder();	# get the path to the web site dir

	return ($sPath . $sID . '.session'); 			# build and return the session filename
	}

###############################################################
#
# package SessionLock - portable file locking module
#
# Written by Zoltan Bodi
# Modified for session object by Tamas Viola
#
# Copyright (c) Actinic Software Ltd 2003
#
###############################################################

# Usage:
#
#	my $rLck = new SessionLock('../users.dat');
#	my $nRet = $rLck->Lock();							# try to get the lock
#	if ($nRet == $SessionLock::SUCCESS)
#		{
#		# use the locked file here
#		}
#	elsif ($nRet == $SessionLock::ERR_TIMEOUT)
#		{
#		# a timeout has occured
#		}
#	elsif ($nRet == $SessionLock::ERR_DIRPERMS)
#		{
#		# file permission problems
#		}
#	elsif ($nRet == $SessionLock::FAILURE)
#
#	$rLck->Unlock();										# release the lock
#	(Note that the lock is automatically released on the object's destruction.)
#
#	$rLck->SetLockSample(100, 0.1);					# nRetries, minimum delay
#		100 tries in 15 seconds [0.1 * 1.5 => 150 milliseconds average]
#
#	my $nLogLockTries = $rLck->GetTryCount();
#

package SessionLock;
use strict;

#
# extract the revision number into both Actinic and CPAN version variables
#

use vars qw($SUCCESS $ERR_TIMEOUT $ERR_DIRPERMS $ERR_OPNANDLCK $ERR_NOOPNNOLCK
				$ERR_MORELCK $ERR_STALELCK $ERR_RECURSE $FAILURE $s_sHostname);

$SUCCESS = 0;
$FAILURE = -1;
$ERR_TIMEOUT  = 1;										# timeout waiting for a lock
$ERR_DIRPERMS = 2;										# insufficient (directory) permissions
$ERR_OPNANDLCK = 3;										# insane state: both .OPN and .LCK present
$ERR_NOOPNNOLCK = 4;										# insane state: none of the above are present
$ERR_MORELCK = 5;											# insane state: more .LCK files (obsolete)
$ERR_STALELCK = 6;										# stale lockfile detected
$ERR_RECURSE = 7;											# recursion detected

$s_sHostname = '';										# hostname is stored here once retrieved

################################################################
#
# SessionLock::new - lock object constructor. Note that the Lock()
#  method should be called to actually acquire the lock.
#
#  Input:	(classname)
#				base filename for the lock
#           (optional) hostname to initialize cache
#
#	Returns: blessed reference to the lock object
#
###############################################################

sub new
	{
	my $rSelf = {};										# create a hash for the object
	my $sThis= shift;
	my $sClass = ref($sThis)||$sThis;				# get the name for the class
	$rSelf->{basename}= shift;
	$rSelf->{locked}=0;
	$rSelf->{nTriesDone}	= 0;							# number of tries attempted
	$rSelf->{recurse_level} = 0;
	$rSelf->{ID} = int(rand(1000));					# unique(ish) ID to identify the locking process
	$rSelf->{locktime} = 0;								# last seen time of the LCK file
	$rSelf->{maxrecurse} = 5;							# maximum number of recurssions
	#
	# nRetrytime * nRetries = minimum timeout period in seconds
	# staleage should be less than the minimum timeout period
	#
	$rSelf->{nRetrytime}	= 0.3;						# time to wait between retries
	$rSelf->{nRetries}	= 200;						# total number of retries
	$rSelf->{staleage}	= 40;							# stale age limit in seconds

	bless $rSelf,$sClass;
	}

###############################################################
#
# SessionLock::SetLockSample - Set/Read Lock Sample Parameters
#
#  Input:	0 - classname
#           1 - number of retries [1 to 10000]
#           2 - minimum retry delay (fraction of a second) [0.01 to 1.0]
#
#  Returns: 0 - number of retries
#           1 - minimum retry delay
#
#  Author:  Bill Birthisel
#
# Average retry delay is randomly selected between the minimum and twice
# that value. So the total time approximates: 1.5 * retries * minimum
#
###############################################################

sub SetLockSample
	{
	my $rSelf=shift;
	if (@_ == 2)
		{
		my ($nNewTry, $nNewTime) = @_;
		if (($nNewTry >= 1) &&
			 ($nNewTry <= 10000))
			{
			$rSelf->{nRetries} = $nNewTry;			# total number of retries
			}
		if (($nNewTime >= 0.01) &&						# 15 millisecond average
			 ($nNewTime <= 1.0))							# 1.5 second average
			{
			$rSelf->{nRetrytime} = $nNewTime;		# minimum time between retries
			}
		}
	return ($rSelf->{nRetries}, $rSelf->{nRetrytime});
	}

###############################################################
#
# SessionLock::GetTryCount - Read number of tries to get lock
#
#  Input:	0 - classname
#
#  Returns: 0 - number of tries [0 to nRetries]
#
#  Author:  Bill Birthisel
#
###############################################################

sub GetTryCount
	{
	my $rSelf = shift;
	return $rSelf->{nTriesDone};						# 1 == first try
	}

###############################################################
#
# SessionLock::DESTROY - destructor. Note that the lock is released
#  on the object's destruction.
#
#  Input:	none (just the classname)
#
#	Returns: n/a  (don't call this method explicitly)
#
###############################################################

sub DESTROY
	{
	my $rSelf=shift;
	$rSelf->Unlock;
	}

################################################################
#
# _try_rename - Try to get the lock by renaming 'basename'.OPN to
#	'basename'.LCK.
#
#	Input:	basename
#
#	Returns: $SUCCESS if the rename was successful, otherwise $FAILURE
#
###############################################################

sub _try_rename
	{
	my $rSelf = shift;
	my $fn = shift;
	my $fnLCK = "$fn.$rSelf->{ID}.LCK";
	#
	# rename returns true/false
	#
	if (rename("$fn.OPN", $fnLCK))					# rename it to a unique name
		{
		if (rename($fnLCK, "$fn.LCK"))				# it's ours so rename to .LCK
			{
			return $SUCCESS;								# we have the renamed file
			}
		}
	return $FAILURE;										# we didn't get it
	}

################################################################
#
# _try_rename_back - Try to release the lock by renaming 'basename'.LCK.PID
#	to 'basename'.OPN. Non public method.
#
#	Input:	basename
#
#	Returns: $SUCCESS if the rename was successful, otherwise $FAILURE
#
###############################################################

sub _try_rename_back
	{
	my $rSelf = shift;
	my $fn = shift;
	#
	# rename returns true/false
	#
	if (rename("$fn.LCK", "$fn.OPN"))
		{
		return $SUCCESS;
		}
	return $FAILURE;
	}

#################################################################
#
# _cleanup - Try to delete all lockfiles associated to the given
#	basename.
#
#  Input:	none (just the classname)
#
#	Returns: $SessionLock::SUCCESS,
#				$SessionLock::ERR_DIRPERMS, if the directory cannot be read
#
###############################################################

sub _cleanup
	{
	my $rSelf = shift;
	my $fn = $rSelf->{basename} . '.LCK';
	if (-e $fn)
		{
		unlink $fn;											# delete the file using full path
		}
	if (-e $fn)
		{
		ACTINIC::RecordErrors("_cleanup\[$rSelf->{ID}\]: Deleting file : " . $fn . " failed", ACTINIC::GetPath());
		}
	$rSelf->{locked} = 0;
	return $SUCCESS;
	}

##################################################################
#
# _init - Initialize the lock by creating an .OPN flag. Call this
# only for locks on newly created files. This saves some timeout
# delay on the first call of Lock().
#
#	Input:	basename
#
#	Returns: $SessionLock::SUCCESS,
#				$SessionLock::ERR_DIRPERMS, on file creation problems.
#
###############################################################

sub _init
	{
	my $rSelf = shift;
	unless ((-e "$rSelf->{basename}.OPN") ||		# only if the .OPN file does not exist
			  (-e "$rSelf->{basename}.LCK"))			# and the .LCK file does not exist
		{
		my $sFn = "$rSelf->{basename}.OPN";
		unless (open(TF, '>' . $sFn))					# try to create the file
			{
			ACTINIC::RecordErrors("_init\[$rSelf->{ID}\]: Error creating $sFn", ACTINIC::GetPath());
			return $ERR_DIRPERMS;
			}
		close(TF);											# close it
		}
	return $SUCCESS;
	}

###################################################################
#
# _do_lock - (Try to) get the lock. Don't call this directly
# from outside the package. This is a private method.
#
#	Input:	none (except the object reference)
#
#	Returns: $SessionLock::SUCCESS,
#				$SessionLock::ERR_DIRPERMS,		on file creation problems.
#				$SessionLock::ERR_TIMEOUT,		timeout on acquiring the lock
#				$SessionLock::ERR_NOOPNNOLCK,	no lockfiles (uninitialized state)
#				$SessionLock::ERR_STALELCK,		a stale lockfile has found
#
###############################################################

sub _do_lock
	{
	my $rSelf = shift;
	$rSelf->{nTriesDone}	= 0;							# initialize number of tries

	my $sOpenFile = "$rSelf->{basename}.OPN";
	my $sLockFile = "$rSelf->{basename}.LCK";

	if ((!(-e $sOpenFile)) &&							# .OPN is NOT present
		 (!(-e $sLockFile)) && 							# and .LCK is NOT present
		 (!(-e $sOpenFile))) 							# and .OPN is still NOT present
		{
		return $ERR_NOOPNNOLCK;							# uninitialized state
		}

	if ((-e $sOpenFile) &&								# .OPN is present
		 (-e $sLockFile) && 								# and .LCK is present
		 (-e $sOpenFile)) 								# and .OPN is still present
		{
		return $ERR_OPNANDLCK;							# bad state, both files exist
		}
	#
	# we now have either an .OPN or .LCK file
	#
	my ($bExists, $nAge, $nNow);
	while ($rSelf->{nTriesDone} < $rSelf->{nRetries})
		{
		#
		# Try to do the rename
		#
		$rSelf->{nTriesDone}++;							# number of tries so far
		my $Stat = $rSelf->_try_rename($rSelf->{basename});
		if ($Stat == $SUCCESS)
			{
			$rSelf->{locked}=1;							# OK, we have the lock
			return $SUCCESS;
			}
		else
			{
			#
			# Unsuccessful rename.
			#
			($bExists, $nAge) = $rSelf->FileExists($sLockFile);
			if ($bExists)									# .LCK is present
				{
				#
				# This means that the lock is in a (sane) occupied state
				#
				if ($rSelf->{locktime} != $nAge)		# time of LCK file has changed
					{
					#
					# The LCK file time has changed so we still have a chance to get the lock
					#
					$rSelf->{locktime} = $nAge;		# save the new LCK file time
					}
				$nNow = time;
				if (($nNow - $nAge) > $rSelf->{staleage})	# see if the lock is older than the stale limit
					{
					ACTINIC::RecordErrors("_do_lock\[$rSelf->{ID}\]: ERR_STALELCK diff=" . $nNow-$nAge . " file=" . $sLockFile, ACTINIC::GetPath());
					return $ERR_STALELCK;
					}
				}
			#
			# Wait for a while and try again
			#
			select (undef, undef, undef, $rSelf->{nRetrytime});
			}
		}
	#
	# Still no success after several tries
	# Check for directory permissions
	#
	my $rn = int(rand(10000));
	my $tempname = $rSelf->{basename} . ".TEMP.$$.$rn";
	unless ( open(TF, ">$tempname.OPN") &&			# create a temp file
				close(TF) &&								# close it
				($rSelf->_try_rename($tempname) == $SUCCESS) &&		# rename it as if it were an open lock
				($rSelf->_try_rename_back($tempname) == $SUCCESS) &&	# rename it back
				unlink("$tempname.OPN") )				# delete
		{
		return $ERR_DIRPERMS;							# if any of these fails return error
		}
	return $ERR_TIMEOUT;									# timeout getting lock
	}

####################################################################
#
# FileExists - Check if file really exists
#					Note: this checks the file twise if file exists but no time found
#
#	Input:	File to look for
#
#	Returns: $::TRUE and the age of the file if present
#				$::FALSE and undefined if not present
#
####################################################################

sub FileExists
	{
	my $rSelf = shift;
	my $sFile = shift;
	my (@FileStat, $bExists);
	@FileStat = stat $sFile;
	$bExists = (-e $sFile);
	if ($bExists &&
		 ($FileStat[9] gt 0))
		{
		return ($::TRUE, $FileStat[9]);				# we have a file
		}

	select (undef, undef, undef, 0.01);				# short wait 1/100s

	@FileStat = stat $sFile;
	$bExists = (-e $sFile);
	if ($bExists &&
		 (($FileStat[9] gt 0)))
		{
		return ($::TRUE, $FileStat[9]);				# we have a file
		}

	return ($::FALSE, undef);
	}

####################################################################
#
# Lock - Public method for getting the lock.
#
#	Input:	Initialise flag
#
#	Returns: $SessionLock::SUCCESS,
#				$SessionLock::ERR_TIMEOUT,		timeout on acquiring the lock
#				$SessionLock::ERR_DIRPERMS,		on file creation problems
#				$SessionLock::FAILURE,			failure on cleanup/initialization
#				($SessionLock::RECURSE,			internal recursion detected)
#
###############################################################

# Note that this calls itself recursively on retries but takes care not to run away.
sub Lock
	{
	my $rSelf=shift;
	my $bInit = $::FALSE;
	if (@_ == 1)
		{
		($bInit) = @_;
		}
	my $sLockFile = $rSelf->{basename} . ".LCK";
	my $ret;
	if ($bInit)												# if init is required
		{
		$ret = $rSelf->_init();							# recreate the .OPN file
		if ($ret != $SUCCESS)
			{
			ACTINIC::RecordErrors("Lock\[$rSelf->{ID}\]: Init failed", ACTINIC::GetPath());
			$rSelf->{recurse_level}--;
		 	return $ret;
			}
		}
	if (++$rSelf->{recurse_level} > $rSelf->{maxrecurse})	# check that we are not looping in recurse
		{
		ACTINIC::RecordErrors("_do_lock\[$rSelf->{ID}\]: Recurse error", ACTINIC::GetPath());
		return $ERR_RECURSE;
		}
	if ($rSelf->{locked})
		{
		$rSelf->{recurse_level}--;
		return ($SUCCESS);
		}
	$ret = $rSelf->_do_lock();
	if ($ret == $SUCCESS)
		{
		#
		# Successfully got the lock.
		#
		$rSelf->{recurse_level}--;
		my $nNow = time;									# let's change the mtime of the open lock
		utime($nNow, $nNow, $sLockFile);				# set the modified date (required for the detection of stale locks)
		return $SUCCESS;									# successfully got the lock
		}
	elsif ($ret == $ERR_TIMEOUT)
		{
		#
		# A timeout has occured.
		# If the LCK file time has changed then we still have a chance to get the lock
		#
		my ($bExists, $nAge) = $rSelf->FileExists($sLockFile);
		if ($bExists)										# do we have a closed lock
			{
			my $now = time;
			if ($rSelf->{locktime} != $nAge)			# time of LCK file has changed
				{
				$rSelf->{locktime} = $nAge;			# save the new LCK file time
				my $ret = $rSelf->Lock();				# try the lock again
				$rSelf->{recurse_level}--;
				return ($ret==$SUCCESS) ? $SUCCESS : $ERR_TIMEOUT;
				}
			}

		$rSelf->{recurse_level}--;
		ACTINIC::RecordErrors("Lock\[$rSelf->{ID}\]: Time out", ACTINIC::GetPath());
		return $ERR_TIMEOUT								# we had a timeout
		}
	elsif ($ret == $ERR_STALELCK)
		{
		#
		# A stale lock has been detected
		#
		if (-e $sLockFile)								# do we have a closed lock
			{
			#
			# Force removal of LCK file and try again
			#
			ACTINIC::RecordErrors("Lock:\[$rSelf->{ID}\]: Stale lock - forcing removal of $rSelf->{basename}.LCK", ACTINIC::GetPath());
			$rSelf->{locked}=1;							# claim ownership of the lock
			$rSelf->Unlock();								# unlock the file
			$ret = $rSelf->Lock();						# try the lock again
			}
		$rSelf->{recurse_level}--;
		return ($ret==$SUCCESS) ? $SUCCESS : $FAILURE;
		}
	elsif ($ret == $ERR_DIRPERMS)
		{
		#
		# A (possible) problem with directory permissions
		#
		ACTINIC::RecordErrors("Lock:\[$rSelf->{ID}\]: Permissions error", ACTINIC::GetPath());
		return $ERR_DIRPERMS;
		}
	elsif ($ret == $ERR_NOOPNNOLCK)
		{
		#
		# Uninitialized. Initialize the lock in open state
		#
		select(undef, undef, undef, 0.01);			# wait a while 2/100s
		#
		# Try to get the lock again, force initialise on penultimate retry
		#
		my $bInit = ($rSelf->{recurse_level} == ($rSelf->{maxrecurse} - 1)) ? $::TRUE : $::FALSE;
		$ret = $rSelf->Lock($bInit);
		$rSelf->{recurse_level}--;
		return ($ret==$SUCCESS)?$SUCCESS:$FAILURE;	# return success if OK
		}
	elsif ($ret == $ERR_OPNANDLCK)					# Invalid status
		{
		ACTINIC::RecordErrors("Lock\[$rSelf->{ID}\]: Invalid status", ACTINIC::GetPath());
		$rSelf->_cleanup();								# remove the .LCK file
		$ret = $rSelf->Lock();							# try to get the lock
		$rSelf->{recurse_level}--;
		return ($ret==$SUCCESS)?$SUCCESS:$FAILURE;	# return success if OK
		}
	}

#####################################################################
#
# Unlock - Release the lock
#
#	Input:	none (except the object reference)
#
#	Returns: $SessionLock::SUCCESS, $SessionLock::FAILURE
#
###############################################################

sub Unlock
	{
	my $rSelf=shift;
	if ($rSelf->{locked})
		{
		if ($rSelf->_try_rename_back($rSelf->{basename}) != $SUCCESS)
			{
			ACTINIC::RecordErrors("Unlock\[$rSelf->{ID}\]: Unlock: failed : " . $rSelf->{basename}, ACTINIC::GetPath());
			return $FAILURE;
			}
		$rSelf->{locked}=0;
		}
	return $SUCCESS;
	}

###############################################################
#
# Lock Functions - end
#
###############################################################
1;