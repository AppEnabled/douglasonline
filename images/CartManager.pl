#!<Actinic:Variable Name="PerlPath"/>
#?use CGI::Carp qw(fatalsToBrowser);
#######################################################
#																		#
# CartManager.pl - Editable Cart management functions	#
#	for Actinic Catalog											#
#																		#
# Copyright (c) 2002 ACTINIC SOFTWARE Plc					#
#																		#
# Written by Zoltan Magyar 									#
# 6:00 PM 1/13/2002												#
#																		#
#######################################################

#######################################################
#                                                     #
# The above is the Path to Perl on the ISP's server   #
#                                                     #
# Requires Perl version 5.0 or later                	#
#                                                     #
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

require <Actinic:Variable Name="ActinicPackage"/>;
require <Actinic:Variable Name="ActinicOrder"/>;
require <Actinic:Variable Name="SessionPackage"/>;

$::sSavedCartSecretKey = '<Actinic:Variable Name="SavedCartSecretKey"/>';

use strict;


Init();														# initialize the global constants and data structures

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
	my (@Response, $Status, $Message, $sHTML, $sAction, $pFailures, $sCartID);
	
	$sAction = $::g_InputHash{"ACTION"};			# check the page action
	#
	# Update?
	#
	if ($sAction eq $::g_sUpdateCartLabel ||		# Update button?
		 $sAction eq "" ||								# no action? May be one order line and enter pressed
		 $sAction eq $::g_sSendCouponLabel)			# send coupon was pressed
		{
		@Response = UpdateCart();						# update items
		$::s_bCartQuantityCalculated = $::FALSE;	# disable cart cache
		}
	#
	# Continue Shopping?
	#
	elsif ($sAction eq $::g_sContinueShoppingLabel)	# Continue shopping action
		{
		@Response = ContinueShopping();
		}
	#
	# Save?
	#		
	elsif ($sAction eq $::g_sSaveShoppingListLabel)	# Cart save action
		{
		@Response = SaveCartToXmlFile($::FALSE);
		}
	#
	# Restore?
	#		
	elsif ($sAction eq $::g_sGetShoppingListLabel)	# Cart Restore action
		{
		@Response = GetCartFromXmlFile();
		}
	#
	# Confirm overwrite?
	#
	elsif ($::g_InputHash{"PAGE"} eq "CONFIRM")	# overwrite confirmation?
		{
		#
		# If confirmaed then save the cart otherwise no action required
		# just redisplay the cart
		#
		if ($sAction eq $::g_sConfirmButtonLabel)	# confirmed
			{
			@Response = SaveCartToXmlFile($::TRUE);
			}
		else
			{
			@Response = ($::SUCCESS, "", undef);
			}
		}
	#
	# Checkout now?
	#
	elsif ($sAction eq $::g_sCheckoutNowLabel)	# checkout now?
		{
		@Response = StartCheckout();															
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
		exit;
		}
	#
	# If everthing went well then redisplay the cart
	#
	($Status, $Message, $sHTML,$sCartID) = ActinicOrder::ShowCart($pFailures);
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		exit;
		}	
	PrintPage($sHTML, $sCartID);		
	}

#######################################################
#
# StartCheckout - Updates the cart and start checkout
#
#	Update the cart content with the new values entered
#		by the user and goes to the first checkout phase 
#
# Output:	0 - if $ReturnCode = $::FAILURE, the operation failed
#					 for the reason specified in $Error
#				1 - $Error - error message if any
#				2 - \@aFailureList - list of validation failures
#
#######################################################

sub StartCheckout
	{
	#
	# Update the cart first
	#
	my @Response = UpdateCart();
	if ($Response[0] == $::BADDATA)
		{
		return @Response;									# validation failed, redisplay cart
		}
	#
	# If everything went well then bounce to checkout
	#
	my $sURL = $::g_InputHash{CHECKOUTURL} ;
	$sURL   .= $::g_InputHash{SHOP} ? '&SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : '';
	my ($bClearFrames) = ACTINIC::IsPartOfFrameset() && $$::g_pSetupBlob{UNFRAMED_CHECKOUT};

	@Response = ACTINIC::BounceToPagePlain(0, "",
															$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
															$::g_sWebSiteUrl,
															$::g_sContentUrl, $::g_pSetupBlob, $sURL , \%::g_InputHash,
															$bClearFrames);	
	my ($Status, $Message, $sHTML) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}		
	PrintPage($sHTML);
	exit;		
	}
	
#######################################################
#
# ContinueShopping - Updates the cart and bounces
#		back to the last shop page
#
#	Update the cart content with the new values entered
#		by the user and goes back to the last shop page
#
# Output:	0 - if $ReturnCode = $::FAILURE, the operation failed
#					 for the reason specified in $Error
#				1 - $Error - error message if any
#				2 - \@aFailureList - list of validation failures
#
#######################################################

sub ContinueShopping
	{
	#
	# Update the cart first
	#
	my @Response = UpdateCart();
	if ($Response[0] == $::BADDATA)
		{
		return @Response;									# validation failed, redisplay cart
		}
	#
	# If everything went well then bounce to the last product page
	#
	my $sURL = $::Session->GetLastShopPage();
	#
	# There is a huge mess in ACTINIC::BounceToPagePlain. Unluckily it is
	# not really safe to touch that code. Therefore a local fix is applied here.
	# See cix:actinic_catlog/bugs_details9:1984
	#
	my ($bClearFrames) = $::FALSE;
	if (!ACTINIC::IsPartOfFrameset() &&				# Current page is not in a frame
		ACTINIC::IsCatalogFramed())					# but Catalog should be framed
		{
		$sURL = ACTINIC::RestoreFrameURL($sURL);	# change the URL to restore the frameset
		$bClearFrames = $::TRUE;						# just in case there is actually a frameset
		}
	else
		{
		if ($ACTINIC::B2B->Get('UserDigest') &&	# if B2B
			 ACTINIC::IsCatalogFramed() &&			# and Catalog should be framed
			 $$::g_pSetupBlob{'UNFRAMED_CHECKOUT'})# and checkout is not framed
			{
			$bClearFrames = $::TRUE;					# BounceToPagePlain needs to clear frames
			}
		}
	@Response = ACTINIC::BounceToPagePlain(0, "",
															"",
															$::g_sWebSiteUrl,
															$::g_sContentUrl, $::g_pSetupBlob, $sURL , \%::g_InputHash,
															$bClearFrames);

	my ($Status, $Message, $sHTML) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}		
	PrintPage($sHTML);
	exit;		
	}
	
#######################################################
#
# UpdateCart - Update the cart items 
#
#	Update the cart content with the new values entered
#		by the user (quantities and prompts). 
#
# Expects:	%::g_InputHash, and %g_SetupBlob
#					should be defined
#
# Output:	0 - if $ReturnCode = $::FAILURE, the operation failed
#					 for the reason specified in $Error
#				1 - $Error - error message if any
#				2 - \@aFailureList - list of validation failures
#
#######################################################

sub UpdateCart
	{
	my ($nStatus, $sMessage, $pFailure, @Response);
	#
	# Read the cart
	#
	@Response = $::Session->GetCartObject();		# get the cart object
	my $pCartObject = $Response[2];
	my $pCartList = $pCartObject->GetCartList();	# get the shopping cart
	my @aFailureList;										# array of validation failures
	my %hRemoved;											# hash of removed items

	my ($pOrderDetail, $sErrorMessage);
	my $nIndex;
	#
	# Initially remove the items marked for delete
	# Separate loop is used for this to not mess up the min
	# max orderable amount calculation
	#
	my $nItemCount = $#$pCartList;
	foreach ($nIndex = $nItemCount; $nIndex >= 0; $nIndex--)
		{
		#
		# We have to detect if the given quantity is a number
		#
		my $nTempQuantity = GetQuantity($nIndex)+1-1;
		#
		# When the item is marked for remove then remove it
		#
		if (IsMarkedForRemove($nIndex) ||			# if remove checkbox is on
			 ($nTempQuantity eq GetQuantity($nIndex) &&
			 GetQuantity($nIndex) == 0))				# or the quantity is zero (and  the quantity is a number)
			{
			$pCartObject->RemoveItem($nIndex);		# then remove it
			$hRemoved{$nIndex} = 1;						# indicate
			}		
		}
	#
	# When the items are removed then process the remained ones
	#		
	$nIndex	= 0;
	my $nLoopIndex;
	#
	# Update cart items before we check them,
	# to avoid misbehaviour
	#
	foreach ($nLoopIndex = 0; $nLoopIndex <= $nItemCount; $nLoopIndex++)
		{
		#
		# Check if item is already removed
		#
		if ($hRemoved{$nLoopIndex})
			{
			next;
			}
		$pOrderDetail = $pCartList->[$nIndex];
		#
		# Update the quantity field
		#
		$$pOrderDetail{"QUANTITY"} = GetQuantity($nLoopIndex);
		#
		# Update the other info prompt
		#
		my $sInfo = ActinicOrder::InfoGetValue($$pOrderDetail{'PRODUCT_REFERENCE'}, $nLoopIndex);
		if ($sInfo)											# when the info prompt defined for the product
			{
			$$pOrderDetail{"INFOINPUT"} = $sInfo;
			}
		#
		# Update the date prompt
		#
		my ($nStatus, $sYear, $sMonth, $sDay) = GetDate($nLoopIndex);
		if ($nStatus == $::SUCCESS)
			{
			$$pOrderDetail{"DATE"} = sprintf("%4.4d/%2.2d/%2.2d", $sYear, $sMonth, $sDay);
			}
		#
		# Update cart items before checking it.
		#
		$pCartObject->UpdateItem($nIndex, $pOrderDetail);
		$nIndex++;
		}
	$nIndex = 0;
	foreach ($nLoopIndex = 0; $nLoopIndex <= $nItemCount; $nLoopIndex++)
		{
		#
		# Check if item is already removed
		#
		if ($hRemoved{$nLoopIndex})
			{
			next;
			}
		$pOrderDetail = $pCartList->[$nIndex];
		#
		# Update the quantity field
		#
		$$pOrderDetail{"QUANTITY"} = GetQuantity($nLoopIndex);
		#
		# Update the other info prompt
		#
		my $sInfo = ActinicOrder::InfoGetValue($$pOrderDetail{'PRODUCT_REFERENCE'}, $nLoopIndex);
		if ($sInfo)											# when the info prompt defined for the product
			{
			$$pOrderDetail{"INFOINPUT"} = $sInfo;
			}
		#
		# Update the date prompt
		#
		my ($nStatus, $sYear, $sMonth, $sDay) = GetDate($nLoopIndex);
		if ($nStatus == $::SUCCESS)
			{
			$$pOrderDetail{"DATE"} = sprintf("%4.4d/%2.2d/%2.2d", $sYear, $sMonth, $sDay);
			}	
		#
		# Do the validation item by item
		# Note: tha failed validation of any item MAY NOT stop
		# the processing
		#
		($nStatus, $sMessage, $pFailure) = ValidateCartItem($nIndex, $nLoopIndex, $pOrderDetail);
		if ($nStatus != $::SUCCESS)
			{
			$sErrorMessage .= "<BR>" . $sMessage;
			push @aFailureList, $pFailure;
			$nIndex++;
			next;
			}
		push @aFailureList, {};
		
		$nIndex++;
		}
	#
	# Check coupon code
	#
	my $sCoupon = $::g_InputHash{'COUPONCODE'};
	if ($sCoupon ne "" &&
		 $$::g_pDiscountBlob{'COUPON_ON_CART'})
		{
		@Response = ActinicDiscounts::ValidateCoupon($sCoupon);
		if ($Response[0] == $::FAILURE)
			{
			$sErrorMessage .= ACTINIC::GetPhrase(-1, 1971,  $::g_sRequiredColor) . $Response[1] . ACTINIC::GetPhrase(-1, 1970);
			}
		else
			{
			if (ACTINIC::GetPhrase(-1, 2355) ne $sCoupon)
				{
				$::g_PaymentInfo{'COUPONCODE'} = $sCoupon;
				$::Session->SetCoupon($::g_PaymentInfo{'COUPONCODE'});
				}
			}
		}

	#
	# Need to validate the Preliminary Info if TAX_AND_SHIP_EARLY is selected
	# See AC10-173
	#
	if ($$::g_pSetupBlob{'TAX_AND_SHIP_EARLY'})
	   {
	   $sMessage = ActinicOrder::ValidatePreliminaryInfo($::TRUE, $::FALSE);
	   if (length $sMessage > 0)
	      {
	      $sErrorMessage .= "<br />" . $sMessage;
	      }
		}

	#
	# Construct error message
	#
	if (length $sErrorMessage > 0)
		{
		my $sHTML = sprintf($::ERROR_FORMAT, $sErrorMessage);
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', $sHTML);
		return ($::BADDATA, "", \@aFailureList);
		}
	else
		{
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', '');
		}
	#
	# If everything went well then merge the identical items
	#
	$pCartObject->CombineCartLines();
	return ($::SUCCESS, "", \@aFailureList);
	}

#######################################################
#
# ValidateCartItem - Validates the individual cart item
#
# Expects:	%::g_InputHash, and %g_SetupBlob
#					should be defined
#
# Input:		0 - the item cart index
#				1 - the item page index
#				1 - the item details
#
# Output:	0 - status
#				1 - error message if any
#
#######################################################

sub ValidateCartItem
	{
	my ($nIndex, $nLoopIndex, $pCurrentDetail) = @_;
	my $pOrderDetail;
	#
	# Construct the updated order detail data
	#
	$$pOrderDetail{'PRODUCT_REFERENCE'} = $$pCurrentDetail{'PRODUCT_REFERENCE'};
	$$pOrderDetail{"SID"} 			= $$pCurrentDetail{"SID"};
	$$pOrderDetail{"QUANTITY"} 	= GetQuantity($nLoopIndex);
	$$pOrderDetail{"INFOINPUT"} 	= ActinicOrder::InfoGetValue($$pOrderDetail{'PRODUCT_REFERENCE'}, $nLoopIndex);
	my ($nStatus, $sYear, $sMonth, $sDay) = GetDate($nLoopIndex);
	if ($nStatus == $::SUCCESS)
		{
		$$pOrderDetail{"DATE"} = sprintf("%4.4d/%2.2d/%2.2d", $sYear, $sMonth, $sDay);
		}	
	foreach my $key (keys %$pCurrentDetail)
		{
		if ($key =~ /COMPONENT_/)						# if it is a component indicator
			{
			$$pOrderDetail{$key} = $$pCurrentDetail{$key};	# then copy it for ActinicOrder::ValidateOrderDetails call
			}
		}
	#
	# Sorry folks but the quantity cache must be turned off as the 
	# quantities might change during each call of this function
	#
	$::s_bCartQuantityCalculated = $::FALSE;
	return(ActinicOrder::ValidateOrderDetails($pOrderDetail, $nIndex));
	}
	
#######################################################
#
# IsMarkedForRemove - Returns true if the indexed cart
# 	item is marked for deletion
#
# Expects:	%::g_InputHash should be defined
#
# Input:		0 - the item index
#
# Output:	$::TRUE or $::FALSE
#
#######################################################

sub IsMarkedForRemove
	{
	my $nIndex = shift;
	return($::g_InputHash{"D_" . $nIndex} =~ /on/i ? $::TRUE : $::FALSE);
	}

#######################################################
#
# GetQuantity - Get the line quantity for the indexed
# 	cart item.
#
# Expects:	%::g_InputHash should be defined
#
# Input:		0 - the item index
#
# Output:	$::TRUE or $::FALSE
#
#######################################################

sub GetQuantity
	{
	my $nIndex = shift;
	return($::g_InputHash{"Q_" . $nIndex});
	}
	
#######################################################
#
# GetDate - Get the line's date info prompt value
#
# Expects:	%::g_InputHash should be defined
#
# Input:		0 - the item index
#
# Output:	0 - status
#				1 - year
#				2 - month
#				3 - day
#
#######################################################

sub GetDate
	{
	my $nIndex = shift;
	my $sYear 	= $::g_InputHash{"Y_" . $nIndex};
	my $sMonth	= $::g_MonthMap{$::g_InputHash{"M_" . $nIndex}};
	my $sDay 	= $::g_InputHash{"DAY_" . $nIndex};
	
	if ($sYear  &&											# if all fields defined
		 $sMonth &&
		 $sDay)
		{
		return ($::SUCCESS, $sYear, $sMonth, $sDay);
		}
	return ($::FAILURE, 0, 0, 0);
	}
	
#######################################################
#
# SaveCartToXmlFile - saves the cart to an xml file
#
# Input:		$bSkipCheck	- skip the overwrite check
#
# Output:	($ReturnCode, $Error)
#
#######################################################

sub SaveCartToXmlFile
	{
	my $bSkipCheck = shift;
	#
	# Update the cart first
	#
	if ($::g_InputHash{"PAGE"} eq "CART")			# if button were pressed on cart page
		{
		my @Response = UpdateCart();
		if ($Response[0] == $::BADDATA)
			{
			return @Response;								# validation failed, redisplay cart
			}	
		}	
	#
	# Get the cart object
	#
	my @Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# return the error
		}
	my $pCartObject = $Response[2];
	#
	# If we're using named shopping carts
	#
	if ($::g_pSetupBlob->{'NAMED_SHOPPING_CART'})
		{
		my $sError = '';
		if ($::g_InputHash{'CART_USERNAME'} eq '')
			{
			$sError = ACTINIC::GetPhrase(-1, 2489, ACTINIC::GetPhrase(-1, 2487));
			}
		my $sInputPassword = $::g_InputHash{'CART_PASSWORD'};
		if ($sError eq '' && $sInputPassword eq '')
			{
			$sError = ACTINIC::GetPhrase(-1, 2489, ACTINIC::GetPhrase(-1, 2488));
			}
		if ($sError eq '' && !CartPasswordIsValid($pCartObject))
			{
			$sError = ACTINIC::GetPhrase(-1, 2490, ACTINIC::GetPhrase(-1, 2488), ACTINIC::GetPhrase(-1, 2487));
			}
			
		if ($sError ne '')
			{
			$ACTINIC::B2B->SetXML('CARTUPDATEERROR', ACTINIC::GroomError($sError));
			return ($::SUCCESS, '', [$sError]);
			}
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', '');			
		$pCartObject->{_PASSWORDHASH} = ACTINIC::GetMD5Hash($sInputPassword . $::sSavedCartSecretKey);
		}
	#
	# Save the cart if it is not empty
	#
	if ($pCartObject->CountItems() > 0) 			# if the cart is not empty
		{
		#
		# Display confirmation page if the external file is already exist
		#
		if ($pCartObject->IsExternalCartFileExist() &&	# if the cart file exists	
			!$bSkipCheck)											# and we haven't been here before
			{
			if (!$::g_pSetupBlob->{'NAMED_SHOPPING_CART'})
				{
				return (DisplayConfirmationPage());
				}
			}
		@Response = $pCartObject->SaveXmlFile();	# save the cart
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}		
		if ($::g_InputHash{'CLEAR_CART_ON_SAVE'})
			{
			@Response = $pCartObject->ClearCart();	# clear the cart 
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
				}		
			}
		return (@Response);
		}
	else														# the cart is empty
		{
		@Response = ACTINIC::BounceToPageEnhanced(5, ACTINIC::GetPhrase(-1, 1962) . ACTINIC::GetPhrase(-1, 44, $::g_sCart, $::g_sCart) . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2049),
																$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
																$::g_sWebSiteUrl,
																$::g_sContentUrl, $::g_pSetupBlob, $::Session->GetLastPage(), \%::g_InputHash,
																$::FALSE);	
		my ($Status, $Message, $sHTML) = @Response;
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}		
		PrintPage($sHTML);
		exit;																
		}

	return @Response;
	}
	
#######################################################
#
# DisplayConfirmationPage - display the overwrite 
# 	confirmation page
#
# Output:	0 - status
#				1 - error message (if any)
#				2 - the generated HTML
#
#######################################################

sub DisplayConfirmationPage
	{	
	my $sLine;
	my %VariableTable;
	#
	# Generate button HTML
	#
	$sLine = ACTINIC::GetPhrase(-1, 1962) . ACTINIC::GetPhrase(-1, 2163) . ACTINIC::GetPhrase(-1, 1970);
	$sLine .= "<P>";
	$sLine .= "<INPUT TYPE=SUBMIT NAME=ACTION VALUE=\"$::g_sConfirmButtonLabel\"> \n";
	$sLine .= "<INPUT TYPE=SUBMIT NAME=ACTION VALUE=\"$::g_sCancelButtonLabel\"> <P>\n";
	#
	# Add page ID
	#
	$VariableTable{$::VARPREFIX."BODY"} = $sLine;	# add the page name
	$VariableTable{$::VARPREFIX."PAGE"} = "<INPUT TYPE=HIDDEN NAME=PAGE VALUE=\"CONFIRM\">\n";
	
	my ($Status, $Message, $sPath, $sHTML);
	$sPath = ACTINIC::GetPath();					# get the path to the web site dir

	my @Response = ACTINIC::TemplateFile($sPath."CRTemplate.html", \%VariableTable); # make the substitutions
	($Status, $Message, $sHTML) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}
	PrintPage($sHTML);
	exit;
	}
	
#######################################################
#
# GetCartFromXmlFile - retrieves the cart from an xml file
#
# Output:	($ReturnCode, $Error)
#
#######################################################

sub GetCartFromXmlFile
	{
	#
	# Update the cart first
	#
	if ($::g_InputHash{"PAGE"} eq "CART")			# if button were pressed on cart page
		{
		my @Response = UpdateCart();
		if ($Response[0] == $::BADDATA)
			{
			return @Response;								# validation failed, redisplay cart
			}	
		}	
	#
	# Get the cart object
	#
	my @Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# general error
		{
		return (@Response);								# error so return empty string
		}
	my $pCartObject = $Response[2];
	#
	# Check if there is any saved cart file
	#
	if (!$pCartObject->IsExternalCartFileExist())
		{
		if ($::g_pSetupBlob->{'NAMED_SHOPPING_CART'})
			{
			my $sError = '';
			if ($::g_InputHash{'CART_USERNAME'} eq '')
				{
				$sError = ACTINIC::GetPhrase(-1, 2489, ACTINIC::GetPhrase(-1, 2487));
				}
			else
				{
				$sError = ACTINIC::GetPhrase(-1, 2490, ACTINIC::GetPhrase(-1, 2488), ACTINIC::GetPhrase(-1, 2487));
				}
			$ACTINIC::B2B->SetXML('CARTUPDATEERROR', ACTINIC::GroomError($sError));
			return ($::SUCCESS, '', [$sError]);
			}
		#
		# if the saved cart files doesnt exist, we have to create the URL for the cart display, because the LastPage is pointing
		# to the cart manager, but can not call this link without the proper input
		#
		my $sCartUrl = $::g_sCartScript . "?ACTION=SHOWCART&BPN=catalogbody.html";
		@Response = ACTINIC::BounceToPageEnhanced(5, ACTINIC::GetPhrase(-1, 1962) . ACTINIC::GetPhrase(-1, 2159) . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2049),
																$$::g_pSetupBlob{CHECKOUT_DESCRIPTION},
																$::g_sWebSiteUrl,
																$::g_sContentUrl, $::g_pSetupBlob, $sCartUrl, \%::g_InputHash,
																$::FALSE);	
		my ($Status, $Message, $sHTML) = @Response;
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}		
		PrintPage($sHTML);
		exit;			
		}
		
	if ($::g_pSetupBlob->{'NAMED_SHOPPING_CART'})
		{
		my $sError = '';
		my $sInputPassword = $::g_InputHash{'CART_PASSWORD'};
		if ($sError eq '' && $sInputPassword eq '')
			{
			$sError = ACTINIC::GetPhrase(-1, 2489, ACTINIC::GetPhrase(-1, 2488));
			}
		if ($sError eq '' && !CartPasswordIsValid($pCartObject))
			{
			$sError = ACTINIC::GetPhrase(-1, 2490, ACTINIC::GetPhrase(-1, 2488), ACTINIC::GetPhrase(-1, 2487));
			}
			
		if ($sError ne '')
			{
			$ACTINIC::B2B->SetXML('CARTUPDATEERROR', ACTINIC::GroomError($sError));
			return ($::SUCCESS, '', [$sError]);
			}
		}
	#
	# Restore the saved cart file
	#
	@Response = $pCartObject->RestoreXmlFile();
	if ($Response[0] == $::FAILURE)					# general error
		{
		return (@Response);								# error so return empty string
		}
	if ($Response[0] == $::BADDATA)
		{
		my $sHTML = sprintf($::ERROR_FORMAT, $Response[1]);
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', $sHTML);
		}
	return ($::SUCCESS, '', $Response[2]);
	}

#######################################################
#
# CartPasswordIsValid - Returns whether a cart password is valid
#
# Output:	true if password matches
#
#######################################################

sub CartPasswordIsValid
	{
	my ($pCartObject) = @_;
	
	my $sInputPassword = $::g_InputHash{'CART_PASSWORD'};
	if ($sInputPassword eq '')
		{
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', 'Empty pass word');
		return ($::SUCCESS, '', ['Empty password']);
		}
	my $sFileName = $pCartObject->GetExternalCartFileName();
 	ACTINIC::ChangeAccess("r", $sFileName);		# allow r access on the file							
	my $pXml = new PXML();
	my @Response = $pXml->ParseFile($sFileName); # loads and parse the xml cart file 
	ACTINIC::ChangeAccess("", $sFileName);			# restore file permission
	if ($Response[0] != $::SUCCESS)
		{
		return @Response;
		}	
	#
	# Restore the cart from the xml structure
	#
	my $pXmlCart = @{$Response[2]}[0];
	#
	# Check the hashed password against the saved hash
	#
	my $pXmlPassword = $pXmlCart->GetChildNode('Password');
	my $sPasswordHash = ACTINIC::GetMD5Hash($sInputPassword . $::sSavedCartSecretKey);
	return ($pXmlPassword->GetNodeValue() eq $sPasswordHash);
	}

##############################################################################################################
#
# Command Processing - End
#
##############################################################################################################

##############################################################################################################
#
# Initialization and Input - Begin
#
##############################################################################################################

#######################################################
#
# Init - initialize the script
#
#######################################################

sub Init
	{
	$::prog_name = "CARTMAN";							# Program Name
	$::prog_name = $::prog_name;
	$::prog_ver = '$Revision: 23869 $ ';					# program version
	$::prog_ver = substr($::prog_ver, 11);			# strip the revision information
	$::prog_ver =~ s/ \$//;								# and the trailers

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
	# Initialise image buttons
	#
	if(!defined $::g_InputHash{"ACTION"})
		{
		if(defined $::g_InputHash{"ACTION_UPDATE.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sUpdateCartLabel;
			}
		elsif(defined $::g_InputHash{"ACTION_SAVE.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sSaveShoppingListLabel;
			}
		elsif(defined $::g_InputHash{"ACTION_GET.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sGetShoppingListLabel;
			}
		elsif(defined $::g_InputHash{"ACTION_BUYNOW.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sCheckoutNowLabel;
			}			
		elsif(defined $::g_InputHash{"ACTION_CONTINUE.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sContinueShoppingLabel;
			}				
		elsif(defined $::g_InputHash{"ACTION_SEND.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sSendCouponLabel;
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

	@Response = ACTINIC::ReadLocationsFile($sPath);	# read the locations
	($Status, $Message) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}
	#
	# read the payment blob
	#
	@Response = ACTINIC::ReadPaymentFile($sPath);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}		
	#
	# Read discount setup
	#
	my ($Status, $Message) = ACTINIC::ReadDiscountBlob($sPath); 
	if ($Status != $::SUCCESS)							# on error, bail
		{
		return ($Status, $Message);
		}				
	#
	# Overwrite the cart/checkout error format string
	#
	$::ERROR_FORMAT = ACTINIC::GetPhrase(-1,2178, $$::g_pSetupBlob{FORM_BACKGROUND_COLOR}) .
		ACTINIC::GetPhrase(-1, 1961) . ACTINIC::GetPhrase(-1,2180);
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

	#
	# read the tax blob
	#
	@Response = ACTINIC::ReadTaxSetupFile($sPath);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	ActinicOrder::ParseAdvancedTax();

	return ($::SUCCESS, "");
	}

##############################################################################################################
#
# Initialization and Input - End
#
##############################################################################################################

##############################################################################################################
#
# Output - Begin
#
##############################################################################################################



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
	#
	# Create cart cookie before process
	#
	my $sCartCookie = ActinicOrder::GenerateCartCookie();
	return (
			  ACTINIC::UpdateDisplay($_[0], $::g_OriginalInputData,
											$_[1], $_[2], '', $sCartCookie)
			 );
	}
	
##############################################################################################################
#
# Output - End
#
##############################################################################################################
