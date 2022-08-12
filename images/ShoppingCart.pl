#!<Actinic:Variable Name="PerlPath"/>
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
# Copyright (c) 1997 ACTINIC SOFTWARE LIMITED         #
#                                                     #
# written by George Menyhert                          #
#                                                     #
#######################################################

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
	my (@Response, $Status, $Message, $sHTML, $sAction, $sCartID);
	$::g_sCurrentPage = $::g_InputHash{"PAGE"};			# identify the calling page
	$sAction = $::g_InputHash{"ACTION"};				# check the page action
	#
	# static pages call the shopping cart page via ?ACTION=SHOWCART
	# static pages call the active X order control page via ?ACTION=ORDERACTIVEX
	# static pages call the Java order control page via ?ACTION=ORDERJAVA
	#
	# All other queries are page specific.
	#

	my ($key, $value);
	if ($sAction eq "REGQUERY")
		{
		SendRegInfo();
		exit;
		}
	elsif ($sAction eq "COOKIEERROR")
		{
		$::bCookieCheckRequired = $::FALSE;
		my $sMessage = ACTINIC::GetPhrase(-1, 52) . "\n";
		($Status, $Message, $sHTML) = ReturnToLastPage(-1, $sMessage, ACTINIC::GetPhrase(-1, 53));
		PrintPage($sHTML, $sCartID);			# print the page and set the cookie
		exit;
		}
	#
	# Check for suspended Catalog before we do anything
	#
	elsif ($$::g_pSetupBlob{CATALOG_SUSPENDED})
		{
		@Response = ReturnToLastPage(7, ACTINIC::GetPhrase(-1, 2077), "");	# bounce back in the broswer
		($Status, $Message, $sHTML) = @Response;	# parse the response
		if ($Status != $::SUCCESS)
			{
			ACTINIC::ReportError($Message, ACTINIC::GetPath());
			exit;
			}
		@Response = BounceHelper($sHTML);
		($Status, $Message, $sHTML) = @Response;	# parse the response
		if ($Status != $::SUCCESS)
			{
			ACTINIC::ReportError($Message, ACTINIC::GetPath());
			exit;
			}
		PrintPage($sHTML);
		}
	elsif (($sAction eq $::g_sSendCouponLabel) ||	# the action of the coupon send label
		 	(($sAction eq "") &&								# or there is no action
		 	 ($::g_InputHash{'COUPONCODE'} ne "")))	# but the coupon field is defined
		{
		RecordCouponCode();
		exit;
		}
	elsif ($sAction eq "SSLBOUNCE")
		{
		PrintSSLBouncePage();
		exit;
		}
	elsif ($sAction eq "SHOWCART")						# display the shopping cart - this is a
		{
		ShowCart();
		}
	elsif ($::g_sCurrentPage eq "PRODUCT")			# the call was made from a product page which means - add item to cart
		{
		ProcessAddToCartCall();
		}
	elsif ($::g_sCurrentPage eq "ORDERDETAIL")		# the call was made from the order detail page
		{

		if ($sAction eq $::g_sCancelButtonLabel)		# Cancel the add
			{
			@Response = ReturnToLastPage(0, "", "");	# bounce back in the broswer
			($Status, $Message, $sHTML) = @Response;	# parse the response
			if ($Status != $::SUCCESS)
				{
				ACTINIC::ReportError($Message, ACTINIC::GetPath());
				exit;
				}
			PrintPage($sHTML);
			}

		else													# Confirm the add (or confirm and checkout now)
			{
			my %OrderDetails;
			($Status, $Message, %OrderDetails) = ValidateOrderDetails($::FALSE);	# attempt to validate the data entered by the user
			if ($Status == $::BADDATA)					# the data was invalid
				{
				$sHTML = $Message; 						# but act like life was a ::SUCCESS - display the warning
				PrintPage($sHTML, $sCartID);			# print the page and set the cookie
				exit;
				}
			elsif ($Status != $::SUCCESS)				# error while validating the data
				{
				ACTINIC::ReportError($Message, ACTINIC::GetPath());
				}

			AddItemToCart(\%OrderDetails);			# add this data item to the cart

			@Response = BounceAfterAddToCart();		# generate bounce page
			($Status, $Message, $sHTML, $sCartID) = @Response; # parse the response
			if ($Status != $::SUCCESS)
				{
				ACTINIC::ReportError($Message, ACTINIC::GetPath());
				exit;
				}
			PrintPage($sHTML, $sCartID);				# print the page and set the cookie
			}
		}
	else														# there is no ACTION specified
		{
		ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 1284), ACTINIC::GetPath());
		exit;
		}
	}

#######################################################
#
# RecordCouponCode - record the coupon code and redisplay
#		the last page
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	nothing
#
# Author: Zoltan Magyar - Sunday, November 09, 2003
#
#######################################################

sub RecordCouponCode
	{
	#
	# Check coupon code
	#
	my $sErrorMessage;
	my @Response = $::Session->GetCartObject();	# be sure we have discounting loaded
	if ($::g_InputHash{'COUPONCODE'} ne "" &&
		 $$::g_pDiscountBlob{'COUPON_ON_PRODUCT'})
		{
		@Response = ActinicDiscounts::ValidateCoupon($::g_InputHash{'COUPONCODE'});
		if ($Response[0] == $::FAILURE)
			{
			$sErrorMessage .= ACTINIC::GetPhrase(-1, 1971,  $::g_sRequiredColor) . $Response[1] . ACTINIC::GetPhrase(-1, 1970);
			}
		else
			{
			$::g_PaymentInfo{'COUPONCODE'} = $::g_InputHash{'COUPONCODE'};
			$::Session->SetCoupon($::g_PaymentInfo{'COUPONCODE'});
			}
		}
	#
	# Check if there were errors
	#
	if ($sErrorMessage ne "")
		{
		my %hErrors;
		@Response = ReturnToLastPage(5, $sErrorMessage);
		}
	else
		{
		@Response = ReturnToLastPage(0, "");
		}
	PrintPage($Response[2]);
	}

#######################################################
#
# ProcessAddToCartCall - check the page's add to cart
#		method and calls the appropriate method
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	nothing
#
# Author: Zoltan Magyar - 10:58 PM 2/15/2002
#
#######################################################

sub ProcessAddToCartCall
	{
	my ($sHTML, $sCartID, @Response);
	#
	# See which add to cart method is used
	#
	my ($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($::g_InputHash{SID}); # retrieve the blob name
	if ($Status == $::FAILURE)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		}
	($Status, $Message) = ACTINIC::ReadSectionFile(ACTINIC::GetPath().$sSectionBlobName);	# read the blob

	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		}

	my $nCartMode = ${$::g_pSectionList{$sSectionBlobName}}{CART_MODE};	# get cart mode
	#
	# call the appropriate function
	#
	if ($nCartMode == $::ATCM_SIMPLE)				# old style add to cart
		{
		@Response = OrderDetails();					# prompt the customer for order details
		}
	elsif	($nCartMode == $::ATCM_ADVANCED)			# product details captured on product page
		{
		@Response = AddSingleItem();
		}
	elsif ($nCartMode == $::ATCM_SINGLE)			# single add to cart
		{
		@Response = AddMultipleItems();
		}
	elsif ($nCartMode == $::ATCM_PDONCART)			# quantity and product details will be set on cart display page
		{
		@Response = AddItemWithDefaultParams();	# Add this item with quantity 1 (quantity = 1 is generated into the page as hidden value)
		}
	($Status, $Message, $sHTML, $sCartID) = @Response;	# parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		exit;
		}
	PrintPage($sHTML, $sCartID);
	exit
	}

#######################################################
#
# AddItemToCart - wrapper for add to cart function of
#		the cart object
#
# Expects:	cart object should be defined
#
# Input:		0 - the hash containing the product details
#
# Returns:	nothing
#
# Author: Zoltan Magyar - Tuesday, November 25, 2003
#
#######################################################

sub AddItemToCart
	{
	my $pValues = shift;
	#
	# Strip out the duplicate product reference tags
	#
	$$pValues{'PRODUCT_REFERENCE'} =~ s/^\d+\!//g;	# if there is a duplicate product code then remove it
	#
	# Get the cart object
	#
	my ($Status, $Message, $pCartObject) = $::Session->GetCartObject();
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		exit;													# bomb out in case of any problem
		}
	$pCartObject->AddItem($pValues);					# add this product item to the cart
	$pCartObject->CombineCartLines();				# check if there are similar products already in the cart, then combine them if possible
	}

#######################################################
#
# AddItemWithDefaultParams - process add to cart for single item
#		where product details are captured on the cart display page
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	($ReturnCode, $Error, $sHTML)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the cart display page
#
# Author: Tamas Viola - 3/25/2002
#
#######################################################

sub AddItemWithDefaultParams
	{
	#
	# Determine product details of the item to be added
	#
	my ($sProdRef, $pProduct) = GetProductDetails();
	#
	# Locate the appropriate section
	#
	my ($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($::g_InputHash{SID}); # retrieve the blob name
	if ($Status == $::FAILURE)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		}
	my @Response;
	#
	# Check the available quantity - Validate cart total less this item
	#
	@Response = CheckQuantity($sProdRef, $sSectionBlobName, $pProduct, -1);
	if ($Response[0] != $::SUCCESS)
		{
		#
		# Return success with the error message formatted as bounce page
		#
		return ($::SUCCESS, $Response[1], $Response[2], "");
		}
	#
	# See the price schedules and determine if the customer is allowed to buy
	#
	my ($bAllowedToBuy, $sMessage) = IsCustomerAllowedToBuy($pProduct);
	if (!$bAllowedToBuy)									# unable to buy
		{
		@Response = ReturnToLastPage(-1, $sMessage);	# bounce back in the browser
		return @Response;
		}
	#
	# Retrieve the product details from the HTML
	#
	my ($pCartObject);
	my %Values = GetProductFromInput($sProdRef, $pProduct);
	if (!defined $Values{QUANTITY})					# check if the Quantity field is exist (we don't know here if other info is required or not)
		{
		$sMessage = "<B>" . $$pProduct{"NAME"} . ":</B><BR><BLOCKQOUTE>" . "Invalid order details" . "</BLOCKQOUTE>";
		return ($::FAILURE, $sMessage, undef, undef);
		}

	my ($nCartQuantity, $nMinQuantity);
	$nMinQuantity = $$pProduct{"MIN_QUANTITY_ORDERABLE"}; # get the min quantity count.  this is maintained on a per product.
	#
	# we have to summarize product quantities in the cart
	# for the proper validation
	#
	my ($pProductQuantities);
	($Status, $sMessage, $pProductQuantities) = ActinicOrder::CalculateCartQuantities();
	if ($Status != $::SUCCESS)
		{
		return ($Status, $sMessage);
		}
	$nCartQuantity = $$pProductQuantities{$sProdRef};
	#
	# if the quantity in the cart plus the quantity to be added is less than the minimum
	# then add sufficient quantity to reach the minimum order quantity
	#
	if (($Values{QUANTITY} + $nCartQuantity) < $nMinQuantity)
		{
		$Values{QUANTITY} = $nMinQuantity - $nCartQuantity;	# add the difference to the cart
		}
	#
	# The cart quantities are cached for min qty calculation. We need to reset
	# the cache to get proper prices on the cart display then.
	#
	$::s_bCartQuantityCalculated = $::FALSE;		# reset the quantity cache
	AddItemToCart(\%Values);							# add this product item to the cart
	my @aFailureList;
	@Response = ActinicOrder::ShowCart(\@aFailureList);	# show the cart to the custumer to edit parameters of the newly added product
	return @Response;
	}

#######################################################
#
# AddSingleItem - process add to cart for single item
#		where product details are captured on product page
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	($ReturnCode, $Error, $sHTML)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the order detail page
#
# Author: Zoltan Magyar - 10:58 PM 2/15/2002
#
#######################################################

sub AddSingleItem
	{
	#
	# Determine product details of the item to be added
	#
	my ($sProdRef, $pProduct) = GetProductDetails();
	#
	# Retrieve the product details from the HTML
	#
	my %Values = GetProductFromInput($sProdRef, $pProduct);
	#
	# See the price schedules and determine if the customer is allowed to buy
	#
	my ($bAllowedToBuy, $sMessage) = IsCustomerAllowedToBuy($pProduct);
	if (!$bAllowedToBuy)									# unable to buy
		{
		my @Response = ReturnToLastPage(-1, $sMessage);	# bounce back in the browser
		return @Response;
		}
	#
	# Validate the item
	#
	my ($Status, $Message, $pFailures) = ActinicOrder::ValidateOrderDetails(\%Values);
	if ($Status == $::SUCCESS)
		{
		AddItemToCart(\%Values);						# add this data item to the cart

		return (BounceAfterAddToCart());
		}
	my (%hErrors, $sItem);
	$pFailures->{MESSAGE} = $Message;				# save the message
	$pFailures->{PRODUCTNAME} = $pProduct->{NAME};	# save the name for the list of problematic product
	$pFailures->{PREVQUANTITY} = $Values{QUANTITY};	# save the quantity for redisplay
	$pFailures->{PREVDATE} = $Values{DATE};				# save the date info for redisplay
	$pFailures->{PREVINFOINPUT} = $Values{INFOINPUT};	# save the other info for redisplay
	foreach $sItem (keys %::g_InputHash)			# saving component and attribute values for redisplay
		{
		if ($sItem =~ /(v_$sProdRef\_\d+)$/)			# component or attribute input value
			{
			$pFailures->{$1} = $::g_InputHash{$1};	# save the value
			}
		}
	$hErrors{$sProdRef} = $pFailures;

	$Message = ACTINIC::GetPhrase(-1,2181);
	my @Response = RedisplayProductPageWithErrors($Message, %hErrors);
	return @Response;
	}

#######################################################
#
# AddMultipleItems - process add to cart for all product
#		on the page (product details are captured on product page)
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	($ReturnCode, $Error, $sHTML)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the order detail page
#
# Author: Zoltan Magyar - 10:58 PM 2/15/2002
#
#######################################################

sub AddMultipleItems
	{
	my $sPath = ACTINIC::GetPath();					# get the path to the web site dir
	#
	# Locate the appropriate section
	#
	my ($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($::g_InputHash{SID}); # retrieve the blob name
	if ($Status == $::FAILURE)
		{
		ACTINIC::ReportError($Message, $sPath);
		}
	#
	# Check if item should be added
	#
	my $sItem;												# iterator
	my %hErrors;											# error collection
	my $bErrorOnPage = $::FALSE;
	#
	# Get cart object
	#
	my ($pCartObject, @Response, @aToBeAdded);
	@Response = $::Session->GetCartObject();
	($Status, $Message, $pCartObject) = @Response;	# parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		exit;
		}
	my $nAddedProducts = 0;								# we count the added products in this variable
	my $nFailedProducts = 0;
	my ($Status, $Message, $bFailure, $pFailures, $bAllowedToBuy);
	foreach $sItem (keys %::g_InputHash)
		{
		$bFailure = $::FALSE;
		if ($sItem !~ /^Q_(.*)$/)						# it isn't quantity tag
			{
			next;
			}
		my $sProdref = $1;
		#
		# Quantity is greater than zero?
		#
		if ($::g_InputHash{$sItem} eq "" ||			# if quantity field is empty
			 $::g_InputHash{$sItem} eq "0")			# or 0
			{
			next;												# then skip it
			}
		#
		# Now locate this product's object.  To do this, we must read the catalog blob
		#
		my ($pProduct);
		@Response = ACTINIC::GetProduct($sProdref, $sSectionBlobName, $sPath);	# get this product object
		($Status, $Message, $pProduct) = @Response;
		#
		# products deleted from the catalog should not be tolerated at this point, so error out
		#
		if ($Status != $::SUCCESS)
			{
			ACTINIC::ReportError($Message, $sPath);
			}
		#
		# Retrieve the product details from the HTML
		#
		my %Values = GetProductFromInput($sProdref, $pProduct);
		#
		# See the price schedules and determine if the customer is allowed to buy
		#
		($bAllowedToBuy, $Message) = IsCustomerAllowedToBuy($pProduct);
		if (!$bAllowedToBuy)
			{
			$pFailures = {};
			$nFailedProducts++;
			$bFailure = $::TRUE;
			}
		#
		# Validate the item
		#
		if (!$bFailure)
			{
			($Status, $Message, $pFailures) = ActinicOrder::ValidateOrderDetails(\%Values);
			if ($Status == $::SUCCESS)
				{
				push @aToBeAdded, \%Values;			# add to the array of valid items
				$nAddedProducts++;						# count added items
				}
			else
				{
				$nFailedProducts++;
				$bFailure = $::TRUE;
				$bErrorOnPage = $::TRUE;				# indicate that there were errors
				}
			}
		#
		# Fill in failure hash perhaps we need this if the product page is redisplayed
		# due to any error occured for any product
		#
		$pFailures->{REDISPLAYONLY} = !$bFailure;			# indicate if it is a real failure or not
		$pFailures->{MESSAGE} = $Message;					# add error message to the failure hash
		$pFailures->{PRODUCTNAME} = $pProduct->{NAME};	# save the name for the list of problematic product
		$pFailures->{PREVQUANTITY} = $Values{QUANTITY};	# save the quantity for redisplay
		$pFailures->{PREVDATE} = $Values{DATE};			# save the date info for redisplay
		$pFailures->{PREVINFOINPUT} = $Values{INFOINPUT};	# save the other info for redisplay
		my $sVariantKey;
		foreach $sVariantKey (keys %::g_InputHash)				# saving component and attribute values for redisplay
			{
			if ($sVariantKey =~ /(v_$sProdref\_\d+)$/)			# component or attribute input value
				{
				$pFailures->{$1} = $::g_InputHash{$1};		# save the value
				}
			}
		$hErrors{$sProdref} = $pFailures;			# the store it it the collection
		}
	#
	# Check if any error occured
	#
	if ($nAddedProducts == 0 &&						# if no items were added then we display a warning
		 $nFailedProducts == 0)
		{
		$Message = ACTINIC::GetPhrase(-1,2202);	# the warning message about no items were added
		$bErrorOnPage = $::TRUE;						# indicate that there were errors
		}
	elsif ($nFailedProducts == 0)						# add all items to the cart if none is failed
		{
		my $pItem;
		foreach $pItem (@aToBeAdded)
			{
			AddItemToCart($pItem);						# add item to the cart
			}
		}
	#
	# Check if there were any errors
	#
	if ($bErrorOnPage)
		{
		if ($nAddedProducts > 0) 						# we put the general message if there are problematic items
			{
			$Message = ACTINIC::GetPhrase(-1,2181);
			}
		@Response = RedisplayProductPageWithErrors($Message, %hErrors);
		}
	else
		{
		@Response = BounceAfterAddToCart();
		}

	return @Response;
	}

#######################################################
#
# RedisplayProductPageWithErrors - process add to cart for single item
#		where product details are captured on product page
#
# Input:		1	General Error message
#				2	Hash of problematic product info
#
# Returns:	($ReturnCode, $Error, $sHTML)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the order detail page
#
# Author: Zoltan Magyar - 10:58 PM 2/15/2002
#
#######################################################

sub RedisplayProductPageWithErrors
	{
	my ($sErrorMessage, %hErrors) = @_;				# receive parameters
	my $sPath = ACTINIC::GetPath();					# get the path to the web site dir
	#
	# Get the file name
	#
	my $sFileName = $::g_InputHash{PAGEFILENAME}; # get the page file name
	my $sMessage;
	#
	# Initiate the general error messages
	#
	$sMessage = ACTINIC::GetPhrase(-1,1971, $::g_sErrorColor) . $sErrorMessage . ACTINIC::GetPhrase(-1,1970);
	my $sGenMessage = ACTINIC::GetPhrase(-1,2178, $$::g_pSetupBlob{FORM_BACKGROUND_COLOR}, $sMessage);	# construct the HTML error message header
	#
	# Set build product page with error messages
	#
	my %VariableTable;
	#
	#	Get the HTML content
	#
	my @Response = ACTINIC::TemplateFile($sPath.$sFileName, \%VariableTable);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);								# if Template file was not succesful, then we can't do anything
		}
	my $sProdref;
	foreach $sProdref (keys %hErrors)
		{
		#
		# Set XML tags
		#
		$sMessage = $hErrors{$sProdref}->{MESSAGE};
		$sMessage = ACTINIC::GetPhrase(-1,1971, $::g_sErrorColor) . $sMessage . ACTINIC::GetPhrase(-1,1970);
		$ACTINIC::B2B->SetXML('CartError_' . $sProdref, $sMessage);
		#
		# customize the file here manually,
		# because the TemplateFile is not prepared for such a sophicticated substitutions
		#
		my $sProdRefMeta = quotemeta ($sProdref);
		my $sStyle = " STYLE=\"background-color: $::g_sErrorColor\"";
		#
		# Highlight input field where values were wrong
		#
		my ($sTemp, $sTempIndex);

		if ($hErrors{$sProdref}->{QUANTITY})		# wrong quantity?
			{
			$Response[2] =~ s/(NAME=\s*["']?Q_$sProdRefMeta['"]?)/$1 $sStyle/is;
			}
		if ($hErrors{$sProdref}->{INFOINPUT})		# wrong other info prompt?
			{
			$Response[2] =~ s/(NAME=\s*["']?O_$sProdRefMeta['"]?)/$1 $sStyle/is;
			}
		if ($hErrors{$sProdref}->{DATE})				# wrong date prompt?
			{
			$Response[2] =~ s/(NAME=\s*["']?Y_$sProdRefMeta['"]?)/$1 $sStyle/is;
			$Response[2] =~ s/(NAME=\s*["']?M_$sProdRefMeta['"]?)/$1 $sStyle/is;
			$Response[2] =~ s/(NAME=\s*["']?DAY_$sProdRefMeta['"]?)/$1 $sStyle/is;
			}
		#
		# reset the input field values for correcting
		#

		#
		# Quantity
		#
		$sTemp = $hErrors{$sProdref}->{PREVQUANTITY};	# get the previously entered data
		$Response[2] =~ s/(NAME=\s*["']?Q_$sProdRefMeta['"]?[^>]*?VALUE=\s*["']?)(\d+)(['"]?)/$1$sTemp$3/is;	# reset the previously entered data into quantity field
		#
		# Other info
		#
		$sTemp = $hErrors{$sProdref}->{PREVINFOINPUT};
		if ($sTemp)											# only if there is anything to restore
			{
			if (!($Response[2] =~ /NAME=\s*["']?O_$sProdRefMeta['"]?[^>]*?VALUE=\s*['"]?/) )	# " if there vere no previous value in the other info field
				{
				#
				# in this case we have to add the VALUE="" tag into the field because it is not generated for empty field
				# and at the same time we reset the previously entered text
				#
				$Response[2] =~ s/(NAME=\s*["']?O_$sProdRefMeta['"]?.*?)(>)/$1 VALUE=\"$sTemp\"$2/is;
				}
				else
				{
				$Response[2] =~ s/(NAME=\s*["']?O_$sProdRefMeta['"]?[^>]*?VALUE=\s*["']?)(.*?)(['"]?)/$1$sTemp$3/is;	# reset the previously entered text into other info field
				}
			}
		#
		# Separating the date info
		#
		my ($nYear, $nMonth, $nDay, $sMonth);
		$sTemp = $hErrors{$sProdref}->{PREVDATE};
		if ($sTemp)											# if there is date prompt to restore
			{
			($nYear, $nMonth, $nDay, $sMonth) = ParseDateStamp($sTemp);	# get the values from the date info
			#
			# select the previous date
			#

			#
			# There can be only one SELECTED preselector in the field for proper functioning, so
			# we have to delete the default SELECTED for the year field only,
			# because this tag is preselected due to the selectable year range during the HTML generation.
			#
			$Response[2] =~ s/(NAME=\s*["']?Y_$sProdRefMeta['"]?.*?)(<OPTION)\s+SELECTED(>)(.*?)(<\/SELECT)/$1$2$3$4$5/is;
			$Response[2] =~ s/(NAME=\s*["']?Y_$sProdRefMeta['"]?.*?)(<OPTION)(>$nYear)/$1$2 SELECTED$3/is;	# Year part of date info
			$Response[2] =~ s/(NAME=\s*["']?M_$sProdRefMeta['"]?.*?)(<OPTION)(>$sMonth)/$1$2 SELECTED$3/is;	# Mont part of date info
			$Response[2] =~ s/(NAME=\s*["']?DAY_$sProdRefMeta['"]?.*?)(<OPTION)(>$nDay)/$1$2 SELECTED$3/is;	# Day part of date info
			}
		#
		# select the previous components and attributes
		#
		my $sKey;
		my ($sSearch, $sSearch1);
		foreach $sKey (keys %{$hErrors{$sProdref}})	# scanning for components or attributes
			{
			if ($sKey =~ /v_$sProdRefMeta\_(\d+)/)		# we found one
				{
				my $nCompIndex = $1;							# get the index part of Product_Index like <SELECT NAME="6_1" ...
				#
				# detect the input field type for proper set
				#
				$sTempIndex = 'v_' . $sProdRefMeta . '_' . $nCompIndex;	# construct the key for the hash
				$sTemp = $hErrors{$sProdref}->{$sKey};
				my $sDropDownRegExp = "<SELECT\\s+NAME=\\s*[\"']?" . $sTempIndex . "[\"']?";
				my $sRadioButtonRegExp = "<INPUT\\s+TYPE=RADIO\\s+NAME=\\s*[\"']?" . $sTempIndex . "[\"']?";
				my $sCheckBoxRegExp = "<INPUT\\s+TYPE=CHECKBOX\\s+NAME=\\s*[\"']?" . $sTempIndex . "[\"']?";

				if ($Response[2] =~ /$sDropDownRegExp/is)	# drop down list
					{
					$sSearch = "(NAME=\\s*[\"']?" . $sTempIndex . "[\"']?.*?\\<OPTION\\s+VALUE=\\s*[\"']?" . $sTemp . "[\"']?)";
					$Response[2] =~ s/$sSearch/$1 SELECTED/is;
					}
				elsif ($Response[2] =~ /$sRadioButtonRegExp/is)	# radio button
					{
					$sSearch = "(<INPUT\\s+TYPE=RADIO\\s+NAME=\\s*[\"']?" . $sTempIndex . "[\"']?\\s+VALUE=\\s*[\"']?" . $sTemp . "[\"']?)";
					$sSearch1 = "(<INPUT\\s+TYPE=RADIO\\s+NAME=\\s*[\"']?" . $sTempIndex . "[\"']?\\s+VALUE=\\s*[\"']?.*?[\"']?)\\s+CHECKED\\s*(>)";
					$Response[2] =~ s/$sSearch1/$1$2/is;	# delete any previous CHECKED string
					$Response[2] =~ s/$sSearch/$1 CHECKED/is;	# set the desired one
					}
				elsif ($Response[2] =~ /$sCheckBoxRegExp/is)	# checkbox
					{
					if ($sTemp =~ /on/i)
						{
						$sSearch = "(<INPUT\\s+TYPE=CHECKBOX\\s+NAME=\\s*[\"']?" . $sTempIndex . "[\"']?)";
						$Response[2] =~ s/$sSearch/$1 CHECKED /is;
						}
					}
				}
			}
		#
		# Create the link item for the list of problematic products but only
		# in that case if this is a real failure
		#
		if (!$hErrors{$sProdref}->{REDISPLAYONLY})
			{
			$sGenMessage .= ACTINIC::GetPhrase(-1,2179, $sProdref, $hErrors{$sProdref}->{PRODUCTNAME});	# insert product ref into the error message
			}
		}
	$Response[2] = ACTINIC::MakeExtendedInfoLinksAbsolute($Response[2], $::g_sWebSiteUrl);
    #
	# Set the general error messages
	#
	$sGenMessage .= ACTINIC::GetPhrase(-1,2180); # cart error footer
	$ACTINIC::B2B->SetXML('CartError_List', $sGenMessage);

	return (@Response);
	}

#######################################################
#
# GetProductFromInput - get the product details from
#		the input hash
#
# Input:		0 - product reference
#				1 - the product hash
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	0 - status
#				1 - message
#				2 - the order details
#
# Author: Zoltan Magyar - 10:58 PM 2/15/2002
#
#######################################################

sub GetProductFromInput
	{
	my ($ProductRef, $pProduct) = @_;

	my ($bInfoExists, $bDateExists, $key, $value, $sMessage, %Values, @Response);
	$bInfoExists = $::FALSE;
	$bDateExists = $::FALSE;
	$sMessage = "";
	#
	# Locate the product of interest
	#
	$bInfoExists = (length $$pProduct{"OTHER_INFO_PROMPT"} != 0); # see if the info field exists.
	$bDateExists = (length $$pProduct{"DATE_PROMPT"} != 0); # see if the date field exists
	my $pOrderDetail;
	#
	# Construct the updated order detail data
	#
	$Values{'PRODUCT_REFERENCE'} = $ProductRef;	# store the product reference
	$Values{'QDQUALIFY'} = '1';						# By default similar products count for quality discount
	if (defined $::g_InputHash{"Q_" . $ProductRef})	# in case of multiple items
		{
		$Values{"QUANTITY"} 	= $::g_InputHash{"Q_" . $ProductRef};		# retrieve the quantity ordered
		}
	else														# in case of single item (Confirmation page)
		{
		$Values{"QUANTITY"} 	= $::g_InputHash{"QUANTITY"};					# retrieve the quantity ordered
		}
	$Values{"SID"} 		= $::g_InputHash{"SID"}; 			# store the section blob
	#
	# Info prompt?
	#
	if ($bInfoExists )
		{
		$Values{"INFOINPUT"} = ActinicOrder::InfoGetValue($ProductRef, $ProductRef);
		}
	#
	# Date prompt?
	#
	if ($bDateExists)
		{
		my $sYear 	= $::g_InputHash{"Y_" . $ProductRef};
		my $sMonth	= $::g_InputHash{"M_" . $ProductRef};
		my $sDay 	= $::g_InputHash{"DAY_" . $ProductRef};
		$sMonth	= $::g_MonthMap{$sMonth};
		if ($sYear eq "") 
			{
			my $now = time(); 
			my @now = gmtime($now); 
			$sDay = $now[3]; 
			$sMonth = $now[4] + 1; 
			$sYear = $now[5] + 1900; 
			} 
		$Values{"DATE"} = sprintf("%4.4d/%2.2d/%2.2d", $sYear, $sMonth, $sDay);
		}
	#
	# Check if there are any variants
	#
	if( $pProduct->{COMPONENTS} )
		{
		if( $pProduct->{PRICING_MODEL} != $ActinicOrder::PRICING_MODEL_STANDARD )	# Price depends on components
			{
			$Values{'QDQUALIFY'} = '0';															# Don't count different components
			}																								# together for volume discount
		my $k;
		foreach $k (keys %::g_InputHash)				# check if we have any components selected
			{
			if( $k =~ /^v_\Q$ProductRef\E\_/ )
				{
				$Values{'COMPONENT_'.$'} = $::g_InputHash{$k};	# no, so add it to values for processing
				}
			elsif ($k =~ /^vb_\Q$ProductRef\E\_/)	# variant buttons, needs more processing
				{
				my @sVarSpecItems = split('_', $');
				my $nCount;
				for ($nCount = 0; $nCount <= $#sVarSpecItems; $nCount+=2)
					{
					$Values{'COMPONENT_' . $sVarSpecItems[$nCount]} = $sVarSpecItems[$nCount + 1];
					}
				}
			}
		}
	return %Values;
	}

#######################################################
#
# SendRegInfo - Sends the content of actreg.fil when
#		query robot ask for this.
#
# Params:	none
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	nothing
#
# Author: Zoltan Magyar
#
#######################################################

sub SendRegInfo
	{
	my ($sPath, $sOut, $sType, $key, $value);
	my @ItemsToSend = qw(VERSIONFULL CATALOGURL LICENSE DETAILS LASTUPLOADDATE);
	#
	# Do we want text/html or application/octet-stream?
	#
	if (defined $::g_InputHash{"HTML"} && $::g_InputHash{"HTML"} == 1)
		{
		#
		# Put it out as HTML
		#
		$sType = 'text/html';
		$sOut = "<HTML><BODY><TABLE WIDTH=100%>";
		foreach (@ItemsToSend)
			{
			$sOut .= "<TR><TD WIDTH=20%>$_</TD><TD WIDTH=80%>$$::g_pCatalogBlob{$_}</TD></TR>";
			}
		$sOut .= "</TABLE></BODY></HTML>";
		}
	else
		{
		#
		# Just put it out as it is
		#
		$sType = 'application/octet-stream';
		foreach (@ItemsToSend)
			{
			$sOut .= "$_|$$::g_pCatalogBlob{$_}|";
			}
		}
	my $nLength = length $sOut;

	binmode STDOUT;										# dump in binary mode since Netscape likes it

	ACTINIC::PrintHeader($sType, $nLength, "", $::TRUE);

	print $sOut;
	}

#######################################################
#
# BounceAfterAddToCart - generate bounce page
#
#	Generates bounce page containing "Your cart contains..."
#	message..
#
# Expects:	%::g_InputHash, and %g_SetupBlob
#					should be defined
#
# Returns:	($ReturnCode, $Error, $sHTML, $sCartID)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the order detail page
#				$sCartID - the cart id
#
#######################################################

sub BounceAfterAddToCart
	{
	my ($Status, $Message, %OrderDetails, $sCartID, @Response);
	#
	# Be sure that the correct prices will be displayed on the bounce page
	#
	$::s_bCartQuantityCalculated = $::FALSE;
	#
	# If we are here, the data is valid, add the item to the cart
	#
	my $pCartObject;
	@Response = $::Session->GetCartObject();
	($Status, $Message, $pCartObject) = @Response;	# parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		exit;
		}
	#
	# Be sure that the identical items are merged
	#
	$pCartObject->CombineCartLines();
	#
	# Then count
	#
	my $nLineCount = $pCartObject->CountItems();

	my ($sPageTitle, $sCartHTML);
	#
	# Compose the page title
	#
	$sPageTitle = ACTINIC::GetPhrase(-1, 51);
	#
	# Compose a summary of the shopping cart
	#
	my $pCartList = $pCartObject->GetCartList();
	@Response = ActinicOrder::GenerateShoppingCartLines($pCartList, $::FALSE, [], "ODTemplate.html");
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my $sCartHTML = $Response[2];

	my ($sHTML);
	my $nBounceDelay = $$::g_pSetupBlob{'BOUNCE_PAGE_DELAY'};
	#
	# Presnet: check if we want to display the shopping cart contents after confirmation
	#
	if ($nBounceDelay == 0 ||							# the specified bounce delay is 0
		(defined $$::g_pSetupBlob{'DISPLAY_CART_AFTER_CONFIRM'} &&	# or PRESNET activated
		$$::g_pSetupBlob{'DISPLAY_CART_AFTER_CONFIRM'}))
		{
		#
		# Display the cart contents with links
		#
		$::s_bCartQuantityCalculated = $::FALSE;		# make sure the cache is reloaded after addition
		ShowCart();
		#
		# ShowCart will exit!!!
		#
		}
	elsif ($::g_InputHash{ACTION} eq ACTINIC::GetPhrase(-1, 184))	# checkout now - bounce to the ordering screen
		{
		#
		# append the original URL to the checkout URL so it can find the images, etc.
		#
		@Response = ACTINIC::EncodeText($::Session->GetBaseUrl(), $::FALSE);
		my $sDestinationUrl = $::g_InputHash{CHECKOUTURL} ;
		#
		# Check cart value for B2B
		#
		($Status, $sHTML) = ActinicOrder::CheckBuyerLimit($sCartID,$sDestinationUrl,$::FALSE);	# Check buyer cash limit
		if ($Status != $::SUCCESS)						# error out
			{
			return ($::SUCCESS,"",$sHTML,$sCartID);
			}

		#
		# now post the message and forward the browser
		#
		@Response = ACTINIC::BounceToPageEnhanced(2, ACTINIC::GetPhrase(-1, 1962) .  $sCartHTML . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2051),
			$sPageTitle, $::g_sWebSiteUrl,
			$::g_sContentUrl, $::g_pSetupBlob,
			$sDestinationUrl, \%::g_InputHash, $$::g_pSetupBlob{UNFRAMED_CHECKOUT});	# bounce to the checkout screen in the broswer - NOTE that the last argument causes the browser to use javascript to clear the frames if necessary
		($Status, $Message, $sHTML) = @Response;		# parse the response
		if ($Status != $::SUCCESS)							# error out
			{
			return (@Response);
			}
		}
	else															# standard confirmation
		{
		@Response = ReturnToLastPage($nBounceDelay, ACTINIC::GetPhrase(-1, 1962) . $sCartHTML . ACTINIC::GetPhrase(-1, 1970) . ACTINIC::GetPhrase(-1, 2051),
			$sPageTitle);										# bounce back in the broswer
		($Status, $Message, $sHTML) = @Response;		# parse the response
		if ($Status != $::SUCCESS)							# error out
			{
			return (@Response);
			}
		}

	return ($::SUCCESS, "", $sHTML);
	}

#######################################################
#
# ValidateOrderDetails - Validate the order details.
#	If they are valid, return ::SUCCESS.  If any are
#	invalid, return ::BADDATA with a modified OrderDetails
#	page packed into $Error.  Can also return ::FAILURE
#	on unrecoverable error.
#
# Expects:	%::g_InputHash, and %g_SetupBlob
#					should be defined
#
# Returns:	0 - $ReturnCode
#				1 - $Error
#				2 - $pData (a reference to the order details)
#
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				else $ReturnCode = $::BADDATA then $Error contains
#					the order detail page HTML modified to
#					correct the order
#				else $::SUCCESS then $pData contains the data
#					the page
#
#######################################################

sub ValidateOrderDetails
	{
#? ACTINIC::ASSERT($#_ == 0, "Invalid argument count in ValidateOrderDetails ($#_)", __LINE__, __FILE__);

	my ($bInfoExists, $bDateExists, $key, $value, $sMessage, %Values);
	$bInfoExists = $::FALSE;
	$bDateExists = $::FALSE;
	$sMessage = "";

	#
	# Validate the cookie exists
	#
	#
	# parse the cookie - look for the actinic cart
	my ($sCookie, $Status, $Message, @Response);
	$sCookie = $::Session->GetSessionID();			# retrieve the actinic cart ID
	#
	# Locate the product of interest
	#
	my ($ProductRef, $pProduct);
	$ProductRef = $::g_InputHash{"PRODREF"};
	if (length $ProductRef == 0)						# if the product reference was not found
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 54), 0, 0);
		}

	my ($sSectionBlobName);
	($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($::g_InputHash{SID}); # retrieve the blob name
	if ($Status == $::FAILURE)
		{
		return ($Status, $Message);
		}
	@Response = ACTINIC::GetProduct($ProductRef, $sSectionBlobName, ACTINIC::GetPath());		# get this product object
	($Status, $Message, $pProduct) = @Response;
	#
	# items deleted from the catalog should error out here - they can't be tolerated at this point
	#
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}
	%Values = GetProductFromInput($ProductRef, $pProduct);
	#
	# Validate the order details
	#
	my $pFailure;
	($Status, $Message, $pFailure) = ActinicOrder::ValidateOrderDetails(\%Values, -1);
	if ($Status != $::SUCCESS)							# there was a problem with at least one of the fields
		{

		my $sHTML = sprintf($::ERROR_FORMAT, $Message);
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', $sHTML);

		my $sCartID;
		my ($nYear, $nMonth, $nDay, $sMonth) = ParseDateStamp($Values{"DATE"});	# get the separate values of date
		@Response = OrderDetails($nDay, $nMonth, $nYear, $Values{"INFOINPUT"}, $pFailure);	# rebuild the order detail page
		($Status, $Message, $sHTML, $sCartID) = @Response;	# read the response
		if ($Status != $::SUCCESS)						# error out
			{
			return(@Response);
			}
		#
		# Insert the old values for the default values
		#
		my (%Variables);
		$Variables{"NAME=QUANTITY VALUE=\"\\d+\""} = # make the last quantity the default
		   "NAME=QUANTITY VALUE=\"" . $::g_InputHash{"QUANTITY"} ."\"";	# for the next round

		@Response = ACTINIC::TemplateString($sHTML, \%Variables); # make the substitutions
		($Status, $Message, $sHTML) = @Response;
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}
		return ($::BADDATA, $sHTML, 0, 0);			# return notifying that the data was incorrect
		}
	else														# the data is valid, record its values
		{
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', '');
		#
		# save the modified data
		#
		my (%EmptyPaymentInfo);
		#
		# Save the payment method
		#
		$EmptyPaymentInfo{'METHOD'} 		= $::g_PaymentInfo{'METHOD'};
		$EmptyPaymentInfo{'USERDEFINED'} = $::g_PaymentInfo{'USERDEFINED'};
		$EmptyPaymentInfo{'PONO'}			= $::g_PaymentInfo{'PONO'};
		$EmptyPaymentInfo{'COUPONCODE'}	= $::g_PaymentInfo{'COUPONCODE'};
		#
		# If we are in B2B mode, save the price schedule
		#
		if ($ACTINIC::B2B->Get('UserDigest') ||
			 defined $::g_PaymentInfo{'SCHEDULE'})
			{
			$EmptyPaymentInfo{'SCHEDULE'} = $::g_PaymentInfo{'SCHEDULE'};
			}
		$::Session->UpdateCheckoutInfo(\%::g_BillContact, \%::g_ShipContact, \%::g_ShipInfo, \%::g_TaxInfo,
											\%::g_GeneralInfo, \%EmptyPaymentInfo, \%::g_LocationInfo);

		return ($::SUCCESS, "", %Values);				# return the values
		}

	return ($::FAILURE, "Should never get here (ValidateData)", 0, 0);
	}

#######################################################
#
# GetProductDetails - determine the product reference
#	 and product hash of item to be added to the cart
#
# Expects:	%::g_InputHash
#
# Returns:	0 - product reference
#				1 - product hash
#
#	Failures are reported directly
#
# Author: Zoltan Magyar - 10:58 PM 2/15/2002
#
#######################################################

sub GetProductDetails
	{
	my ($ProductRef, $key, $value);

	my $sPath = ACTINIC::GetPath();					# get the path to the web site dir

	foreach (keys %::g_InputHash)						# New variants - 'add' button is '_' followed by prodref
		{
		if( $_ =~ /^_/)									# search for _xxx
			{
			$ProductRef = $';
			$ProductRef =~ s/\.[xy]$//;				# if it was an image button, remove the indicator
			$ProductRef =~ s/_.*//g;					# if there is a component ID, remove it
			last;
			}
		}

	#
	# Locate the appropriate section
	#
	my ($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($::g_InputHash{SID}); # retrieve the blob name
	if ($Status == $::FAILURE)
		{
		ACTINIC::ReportError($Message, $sPath);
		}
	my ($sImageButtonName, $sSuffix);

	if( !$ProductRef )
		{
		$ProductRef = $::g_InputHash{"PRODREF"};
		}
	if (length $ProductRef == 0)						# if the product reference was not found
		{
		while (($key, $value) = each %::g_InputHash)	# locate the product reference
			{
			if (length $::g_sAddToButtonLabel > 0 && 	# found the add to cart button identified by the button
				 $value =~ /\Q$::g_sAddToButtonLabel\E/ &&	# label and a key that does not contain "_".  "_" indicates
				 $key !~ /_/)								# that this button is used for variants (and is processed below)
				{
				$ProductRef = $key;						# store the product reference
				}
			#
			# If it was an Image button, we don't seem to get the "Add To" value
			# so we have to look for something that looks like a coordinate
			# This will simply be the button name followed by ".x" or ".y"
			#
			if ($key =~ /(.+)\.([xy])$/ &&			# Looks like an image co-ordinate, but we must rule out
				 $key !~ /_/)								# product variants (handled below)
				{
				#
				# We have something that ends in .x or .y.  If both are present
				# we assume that this came from an IMAGE button
				#
				if($sImageButtonName)					# already found a .[xy] suffix?
					{
					if($sSuffix ne $2)					# and the suffix is different
						{
						$ProductRef = $sImageButtonName;	# use the de-suffixed name
						}
					}
				else											# first [xy] suffix
					{
					$sImageButtonName = $1;				# save the key without the suffix
					$sSuffix = $2;							# save the suffix
					}
				}
			#
			# Check for variant button
			#
			if ($key =~ /^vb_([^_]*)_/)				# and the button is a variant pushbutton
				{
				$ProductRef = $1;							# store the product reference
				}
			}

		my ($Temp);
		$Temp = keys %::g_InputHash;					# reset the iterator for "each"
		$Temp = $Temp;										# remove compiler warning
		}
	if (!$ProductRef)										# if the product reference was not found
		{
		if( $sImageButtonName )
			{
			$ProductRef = $sImageButtonName;
			}
		else
			{
			#
			# If we still don't have product reference then it might be because
			# the form was submitted by enter key while qty captured on product page
			# So check the input hash for qty field
			#
			foreach (keys %::g_InputHash)
				{
				if ($_ =~ /^Q_/i)							# search for Q_xxx
					{
					$ProductRef = $';
					last;
					}
				}
			#
			# If the product ref is still missing then report error
			#
			if (!$ProductRef)
				{
				ACTINIC::ReportError(ACTINIC::GetPhrase(-1, 54), $sPath);
				}
			}
		}
	#
	# Now locate this product's object.  To do this, we must read the catalog blob
	#
	my ($pProduct);
	my @Response = ACTINIC::GetProduct($ProductRef, $sSectionBlobName, $sPath);	# get this product object
	($Status, $Message, $pProduct) = @Response;
	#
	# products deleted from the catalog should not be tolerated at this point, so error out
	#
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, $sPath);
		}
	return ($ProductRef, $pProduct);
	}

#######################################################
#
# CheckQuantity - check if the desired quantity can be
#	 added to the cart
#
# Params:
#				0 - the product reference
#				1 - the section blob name where the product details are
#				2 - the product details hash
#				3 - cart index or
#					-1 => Adding quantity
#					-2 => Validate cart
#
# Returns:	($ReturnCode, $Error, $sHTML, $nMaxQuantity)
#				if $ReturnCode = $::FAILURE, the desired
#					quantity can not be added to the cart
#				Otherwise everything is OK
#				$sHTML - the HTML of the error page if status is failure
#				$nMaxQuantity - the maximum available quantity
#
#######################################################

sub CheckQuantity
	{
	my ($ProductRef, $sSectionBlobName, $pProduct, $nIndex) = @_;

	my ($nMaxQuantity, @Response, $Status, $Message);

	if ($::g_sCurrentPage eq "PRODUCT")				# if this is the first viewing of the OD page,
		{
		($Status, $Message, $nMaxQuantity) =
	      ActinicOrder::GetMaxRemains($ProductRef, $sSectionBlobName, $nIndex);	# calculate the maximum quantity of this item that can be added to the cart
		if ($Status != $::SUCCESS)
			{
			ACTINIC::ReportError($Message, ACTINIC::GetPath());
			}

		if (($nMaxQuantity == -1) ||					# if max quantity has been met (already sold out)
			(($::g_sCurrentPage eq "PRODUCT") &&	# or this is the first viewing of the OD page
			 ($nMaxQuantity == 0)))						# and already reached the max orderable
			{
			$Message .= "<B>" . ACTINIC::GetPhrase(-1, 63) . "</B>";

			@Response = ReturnToLastPage(5, $Message, ACTINIC::GetPhrase(-1, 64));
			return ($::FAILURE, $Response[1], $Response[2], "");
			}
		#
		# Check is out of stock
		#
		if ($$pProduct{'OUT_OF_STOCK'})
			{
			$Message .= ACTINIC::GetPhrase(-1, 297, $$pProduct{'NAME'}) . "<P>\n";
			@Response = ReturnToLastPage(5, $Message, ACTINIC::GetPhrase(-1, 64));
			return ($::FAILURE, $Response[1], $Response[2], "");
			}
		}
	return ($::SUCCESS, "", "", $nMaxQuantity);
	}

#######################################################
#
# OrderDetails - display the details of this
#	 order line
#
# Params:
#				0 - the default day (optional)
#				1 - the default month (optional)
#				2 - the default year (optional)
#				3 - the default info prompt (optional)
#				4 - optional hash of failures
#
# Returns:	($ReturnCode, $Error, $sHTML, 0)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the order detail page
#
#######################################################

sub OrderDetails
	{
	my (@Date, $sDefaultInfo, $pFailure);
	($Date[0], $Date[1], $Date[2], $sDefaultInfo, $pFailure) = @_;	# get the edit mode and default date and info (if any)
	#
	# If date is not specified then default to today
	#
	if (!defined $Date[0])
		{
		my $now = time;
		my @now = gmtime($now);
		$Date[0] = $now[3];
		$Date[1] = $now[4] + 1;
		$Date[2] = $now[5] + 1900;
		}

	my ($sPath, $bStandAlonePage);
	$sPath = ACTINIC::GetPath();						# get the path to the web site dir

	my ($sLine, %VariableTable);
	#
	# Determine product reference of the item
	#
	my ($ProductRef, $pProduct) = GetProductDetails();
	#
	# Locate the appropriate section
	#
	my ($Status, $Message, $sSectionBlobName) = ACTINIC::GetSectionBlobName($::g_InputHash{SID}); # retrieve the blob name
	if ($Status == $::FAILURE)
		{
		ACTINIC::ReportError($Message, $sPath);
		}

	my ($sCartID, $nMaxQuantity, @Response);
	#
	# Check the available quantity - Validate cart total quantity
	#
	if ($::g_sCurrentPage eq "PRODUCT")				# if this is the first viewing of the OD page,
		{
		@Response = CheckQuantity($ProductRef, $sSectionBlobName, $pProduct, -1);
		}
	else
		{
		@Response = CheckQuantity($ProductRef, $sSectionBlobName, $pProduct, -2);
		}
	if ($Response[0] != $::SUCCESS)
		{
		#
		# Return success with the error message formatted as bounce page
		#
		return ($::SUCCESS, $Response[1], $Response[2], "");
		}
	$nMaxQuantity = $Response[3];
	#
	# Process the optional ship and tax prompts
	#
	my (@DeleteDelimiters, @KeepDelimiters);
	my($sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable);
	($Status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters, $pSelectTable) =
		ActinicOrder::DisplayPreliminaryInfoPhase($::FALSE); # get the ship charge phase  info
	if ($Status != $::SUCCESS)
		{
		return ($Status, $sMessage, $pVarTable, $pDeleteDelimiters, $pKeepDelimiters);
		}
	my (@Array1, @Array2, %SelectTable);			# append the shipping stuff to the rest of it
	@Array1 = %$pVarTable;
	@Array2 = %VariableTable;
	push (@Array1, @Array2);
	%VariableTable = @Array1;
	if (defined $pSelectTable)
		{
		@Array1 = %$pSelectTable;
		@Array2 = %SelectTable;
		push (@Array1, @Array2);
		%SelectTable = @Array1;
		}
	push (@DeleteDelimiters, @$pDeleteDelimiters);
	push (@KeepDelimiters, @$pKeepDelimiters);


	($pDeleteDelimiters, $pKeepDelimiters) =		# get the information that tells us which prompts to remove
		ActinicOrder::ParseDelimiterStatus($::PRELIMINARYINFOPHASE);
	push (@DeleteDelimiters, @$pDeleteDelimiters);
	push (@KeepDelimiters, @$pKeepDelimiters);

	#######
	# Now we have all of the information that we need to proceed.  Check to see if the max quantity count =
	# min quantity count.  If so and there are no prompts, automatically add it to the cart with quantity = min.
	#######
	# In this version confirmation page is always shown so the corresponding section is commented out
	#######
	my $nVarCount = (keys %$pVarTable) + (keys %$pSelectTable);
#	if (($$pProduct{"MIN_QUANTITY_ORDERABLE"} == $$pProduct{"MAX_QUANTITY_ORDERABLE"} || # if the quantities are equal or
#		  ($::g_sCurrentPage eq "PRODUCT" && $nMaxQuantity == 1)) && # this operation can only add one
#		 $$pProduct{"DATE_PROMPT"} eq "" &&				# and there is no date prompt
#		 $$pProduct{"OTHER_INFO_PROMPT"} eq "" &&		# and there is no other info prompt
#		 (!$$::g_pSetupBlob{TAX_AND_SHIP_EARLY} ||	# and either we are not taking tax and ship info early, or
#		 $nVarCount == 0))									# the tax and shipping phases are hidden
#		{
#		#
#		# Create a bounce page the emulates the order detail page.  To do this, build the CGI GET URL.
#		#
#		my ($sCgiUrl);
#		$sCgiUrl = sprintf('%sca%6.6d%s', $$::g_pSetupBlob{'CGI_URL'}, $$::g_pSetupBlob{'CGI_ID'},
#			$$::g_pSetupBlob{'CGI_EXT'});					# the cgi scrip URL
#		#
#		# Now add the parameters
#		#
#		my ($sGet);
#		$sGet = "?";
#		srand();
#		my ($Random) = rand();
#		$sGet .= "RANDOM=" . $Random;
#		@Response = ACTINIC::EncodeText($sPath, $::FALSE);
#		$sGet .= ($::g_InputHash{SHOP} ? '&SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) : '');
#		$sGet .= "&PAGE=ORDERDETAIL";
#		@Response = ACTINIC::EncodeText(ACTINIC::GetReferrer(), $::FALSE);
#		$sGet .= "&REFPAGE=" . $Response[1];
#		@Response = ACTINIC::EncodeText($$pProduct{'REFERENCE'}, $::FALSE);
#		$sGet .= "&PRODREF=" . $Response[1];
#		if ($pProduct->{MIN_QUANTITY_ORDERABLE} == $pProduct->{MAX_QUANTITY_ORDERABLE}) # we are here because the min = max so there is no quantity choice
#			{
#			$sGet .= "&QUANTITY=" . $$pProduct{"MIN_QUANTITY_ORDERABLE"};
#			}
#		else													# we are here because the remaining count is 1 and there is no quantity choice
#			{
#			$sGet .= "&QUANTITY=1";
#			}
#		$sGet .= "&SID=" . $::g_InputHash{SID};
#		$sGet .= "&ACTION=" . ACTINIC::EncodeText2($::g_sConfirmButtonLabel, $::FALSE);
#		#
#		# now generate the page
#		#
#		my ($sRefPage, $sHTML);
#		$sRefPage = $sCgiUrl . $sGet;
#		@Response = ACTINIC::BounceToPagePlain(0, undef,
#			undef, $::g_sWebSiteUrl, $::g_sContentUrl, $::g_pSetupBlob, $sRefPage, \%::g_InputHash);
#		if ($Response[0] != $::SUCCESS)
#			{
#			return (@Response);
#			}

#		return ($::SUCCESS, "", $Response[2], $sCartID);	# add the item to the cart
#		}

	$sLine = "<INPUT TYPE=HIDDEN NAME=PRODREF VALUE=\"$ProductRef\">";
	$sLine .= "<INPUT TYPE=HIDDEN NAME=SID VALUE=\"$::g_InputHash{SID}\">";

	#
	# Check if there are any variants
	#
	my $VariantList;
	if( $pProduct->{COMPONENTS} )
		{
		my $sProdRefHTML;
		#
		# Get the variants and product ref HTML for this product
		#
		($VariantList, $sProdRefHTML) = ACTINIC::GetVariantList($ProductRef);
		$sLine .= $sProdRefHTML;
		}
	$VariableTable{$::VARPREFIX."PRODUCTREF"} = $sLine; # add the product reference to the var table
	#
	# Preprocess the template
	#
	my $pTree;
	($Status, $sMessage, $pTree) = ACTINIC::PreProcessXMLTemplate(ACTINIC::GetPath() . "ODTemplate.html");
	if ($Status != $::SUCCESS)
		{
		return ($Status, $sMessage);
		}
	my $pXML = new Element({"_CONTENT" => $pTree});	# bless the result to have Element structure
	my $sProductLineHTML = ACTINIC_PXML::GetTemplateFragment($pXML, "ODLine");
	#
	# Add the product name to the html
	#
	my %hVariables;
	my $sProductTable;
	if (!$pProduct->{NO_ORDERLINE} )					# no order line required for main product
		{
		@Response = ACTINIC::ProcessEscapableText($$pProduct{"NAME"});# get the product name
		($Status, $sLine) = @Response;					# format the product name for HTML
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}
		$hVariables{$::VARPREFIX."PRODUCTNAME"} = $sLine; # add the product name to the var table
		#
		# Add the product reference to the html
		#
		@Response = FormatProductReference($ProductRef);
		($Status, $Message, $sLine) = @Response;
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}
		$hVariables{$::VARPREFIX."DISPLAYPRODUCTREF"} = '&nbsp;' . $sLine; # add the product ref to the var table
		#
		# Do the substitution for NETQUOTEVARs
		#
		($Status, $Message, $sProductTable) = ACTINIC::TemplateString($sProductLineHTML, \%hVariables); # make the substitutions
		if ($Status != $::SUCCESS)
			{
			return ($Status, $Message);
			}
		}

	my (%Component, $pAcomponent, $sComponents);
	foreach $pAcomponent (@{$pProduct->{COMPONENTS}})
		{
		@Response = ActinicOrder::FindComponent($pAcomponent,$VariantList);
		($Status, %Component) = @Response;
		if ($Status != $::SUCCESS)
			{
			return ($Status,$Component{text});
			}
		if( $Component{quantity} > 0 )
			{
			#
			# Reset variable table
			#
			$hVariables{$::VARPREFIX."PRODUCTNAME"} = "";
			$hVariables{$::VARPREFIX."DISPLAYPRODUCTREF"} = "";

			if ( $Component{text} )
				{
				@Response = ACTINIC::ProcessEscapableText($Component{text});# get the product name
				($Status, $sLine) = @Response;					# format the product name for HTML
				if ($Status != $::SUCCESS)
					{
					return (@Response);
					}
				$hVariables{$::VARPREFIX."PRODUCTNAME"} =  $sLine;
				}
			#
			# Add the product reference to the html if exists
			#
			if ( $Component{code} )
				{
				@Response = FormatProductReference($Component{code});
				($Status, $Message, $sLine) = @Response;
				if ($Status == $::SUCCESS)
					{
					$hVariables{$::VARPREFIX."DISPLAYPRODUCTREF"} = '&nbsp;' . $sLine; # add the component ref to the var table
					}
				}
			#
			# Do the substitution for NETQUOTEVARs
			#
			($Status, $Message, $sLine) = ACTINIC::TemplateString($sProductLineHTML, \%hVariables); # make the substitutions
			if ($Status != $::SUCCESS)
				{
				return ($Status, $Message);
				}
			$sProductTable .= $sLine;
			}
		}
	#
	# Write back product table to the template
	# It will be done during XML parsing
	#
	$ACTINIC::B2B->SetXML("ODLine", $sProductTable );
	#
	# See the price schedules and determine if the customer is allowed to buy
	#
	my ($bAllowedToBuy, $sMessage) = IsCustomerAllowedToBuy($pProduct);
	if (!$bAllowedToBuy)								# unable to buy
		{
		my @Response = ReturnToLastPage(-1, $sMessage);	# bounce back in the browser
		return @Response;
		}
	#
	# Get the product prices to display
	#
	@Response = ActinicOrder::GetProductPricesHTML($pProduct, $VariantList, $sSectionBlobName);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	$VariableTable{$::VARPREFIX."PRODUCTPRICE"} = $Response[2]; # add the product price to the var table
	#
	# add the quantity prompt.  if the min=max, hard code the quantity.  otherwise, offer the prompt
	#
   if (($$pProduct{"MIN_QUANTITY_ORDERABLE"} == $$pProduct{"MAX_QUANTITY_ORDERABLE"}) || # nothing to edit - so hard code the quantity
		 ($::g_sCurrentPage eq "PRODUCT" && $nMaxQuantity == 1))
		{
		if ($nMaxQuantity == 1)
			{
			$VariableTable{$::VARPREFIX."QUANTITY"} = '1' . # hard code the quantity
				"<INPUT TYPE=HIDDEN NAME=QUANTITY VALUE=\"1\">";
			}
		else
			{
			$VariableTable{$::VARPREFIX."QUANTITY"} = $$pProduct{"MIN_QUANTITY_ORDERABLE"} . # hard code the quantity
				"<INPUT TYPE=HIDDEN NAME=QUANTITY VALUE=\"" . $$pProduct{"MIN_QUANTITY_ORDERABLE"} . "\">";
			}
		}
	else														# the user can specify
		{
		#
		# Determine how many more can be ordered.  Default to the minimum amount orderable given the circumstances:
		# If the cart already contains some of this item, default to just adding one more.  If not, default to the
		# minimum quantity orderable.  Note that this check only applies when items are being added to the cart.
		# For edits, etc. just offer the minimum quantity orderable because it is overwritten by the calling routines.
		#
		my $nDefaultQuantity = $pProduct->{MIN_QUANTITY_ORDERABLE};

		if ($::g_sCurrentPage eq "PRODUCT")			# if this is the first viewing of the OD page,
			{
			my $nMaxOrderable = ($pProduct->{MAX_QUANTITY_ORDERABLE} == 0 ? $::MAX_ORD_QTY : $pProduct->{MAX_QUANTITY_ORDERABLE});
			if ($nMaxQuantity != $nMaxOrderable)	# if something is already in the cart
				{
				$nDefaultQuantity = 1;					# set the minimum incremental addition
				}
			}
		else
			{
			$nDefaultQuantity = $::g_InputHash{"Q_$ProductRef"};	# redisplay the previously entered quantity
			}

		$VariableTable{$::VARPREFIX."QUANTITY"} = "<INPUT TYPE=TEXT NAME=\"Q_$ProductRef\" VALUE=\"" .
		   $nDefaultQuantity . "\" SIZE=6 MAXLENGTH=10>";
		}

	#
	# add the date prompt (if any) to the html
	#
	if (length $$pProduct{"DATE_PROMPT"} > 0)		# if there is a date prompt, print the message and format the prompt
		{
		my $nMinYear = $$pProduct{"DATE_MIN"};
		my $nMaxYear = $$pProduct{"DATE_MAX"};
		my ($nDefaultDay, $nDefaultMonth, $nDefaultYear) = (1, 1, $nMinYear);

		if ($#Date > 0)									# if a default date was supplied
			{
			if (defined $Date[0])						# use the default day
				{
				$nDefaultDay = $Date[0];
				}
			if (defined $Date[1])						# use the default day
				{
				$nDefaultMonth = $Date[1];
				}
			if (defined $Date[2])						# use the default day
				{
				$nDefaultYear = $Date[2];
				}
			}
		my ($sStyle, $sYearLine);
		if ($pFailure->{"DATE"})
			{
			$sStyle = " style=\"background-color: $::g_sErrorColor\"";
			}
		my $sDayLine 	= ACTINIC::GenerateComboHTML("DAY_$ProductRef", $nDefaultDay, "%2.2d", $sStyle, (1..31));	# add the day drop down list
		my $sMonthLine = ACTINIC::GenerateComboHTML("M_$ProductRef", $::g_InverseMonthMap{$nDefaultMonth}, "%s", $sStyle, @::gMonthList);	# add the day drop down list
		if ($nMinYear == $nMaxYear)					# if the date range is only one year, the we generate a static text instead of year combo
			{
			$sYearLine = "$nMinYear<INPUT TYPE=HIDDEN NAME=\"Y_$ProductRef\" VALUE=\"$nMinYear\">"
			}
		else
			{
			$sYearLine 	= ACTINIC::GenerateComboHTML("Y_$ProductRef", $nDefaultYear, "%4.4d", $sStyle, ($nMinYear..$nMaxYear)); # add the year drop down list
			}
		my $sDatePrompt = ACTINIC::FormatDate($sDayLine, $sMonthLine, $sYearLine);

		$ACTINIC::B2B->SetXML("DateInput", 1);		# set flag to keep this fragment during XML parse
		#
		# Populate NQVs
		#
		$VariableTable{$::VARPREFIX."DATEPROMPTCAPTION"} = $$pProduct{"DATE_PROMPT"};
		$VariableTable{$::VARPREFIX."DATEPROMPTVALUE"} = $sDatePrompt; # add the date prompt (if any) to the var table
		}
	#
	# add the info prompt (if any) to the html
	#
	my $sInfoPrompt = $$pProduct{"OTHER_INFO_PROMPT"};
	if (length $sInfoPrompt > 0)						# if there is an info prompt, print the message and format the prompt
		{
		$ACTINIC::B2B->SetXML("InfoInput", 1);		# set flag to keep this fragment during XML parse

		$VariableTable{$::VARPREFIX."INFOINPUTCAPTION"} = $sInfoPrompt;
		$VariableTable{$::VARPREFIX."INFOINPUTVALUE"} = ActinicOrder::InfoHTMLGenerate($ProductRef, $ProductRef, $sDefaultInfo, $::FALSE, $pFailure->{"INFOINPUT"});	# add the text field to the list
		}
	#
	# Presnet: we may not want to display the cart contents until the item has been added
	#
	if (defined $$::g_pSetupBlob{'SUPPRESS_CART_WITH_CONFIRM'} &&
		$$::g_pSetupBlob{'SUPPRESS_CART_WITH_CONFIRM'})
		{
		$ACTINIC::B2B->SetXML("ShoppingCart", "");  # don't display the cart contents
		}
	else
		{
		#
		# Now display a summary of the shopping cart
		#
		my $pCartObject;
		@Response = $::Session->GetCartObject();
		($Status, $Message, $pCartObject) = @Response;	# parse the response
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}

		my $pCartList = $pCartObject->GetCartList();
		#
		# if the cart contains any items, display it.  Otherwise, skip it
		#
		if ($#{$pCartList} >= 0)
			{
			@Response = ActinicOrder::GenerateShoppingCartLines($pCartList, $::FALSE, [], "ODTemplate.html");
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
				}
			}
		else
			{
			$ACTINIC::B2B->SetXML("ShoppingCart", "");
			}
		}

	#######
	# customize the file
	#######
	@Response = ACTINIC::TemplateFile($sPath."ODTemplate.html", \%VariableTable);	# customize the file
	my ($sHTML);
	($Status, $Message, $sHTML) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}

	#######
	# make the file references point to the correct directory
	#######
	@Response = BounceHelper($sHTML);
	($Status, $Message, $sHTML) = @Response;
	if ($Status != $::SUCCESS)
		{
		return (@Response);
		}
	#
	# remove unused form blocks
	#
	my ($sDelimiter);
	foreach $sDelimiter (@DeleteDelimiters)			# for each delimited section that is to be deleted
		{
		$sHTML =~ s/$::DELPREFIX$sDelimiter(.*?)$::DELPREFIX$sDelimiter//gis;	# delete it (/s removes the \n limitation of .)
		}
	#
	# remove unused delimiters
	#
	foreach $sDelimiter (@KeepDelimiters)				# for each delimiter that is not used
		{
		$sHTML =~ s/$::DELPREFIX$sDelimiter//gis;			# delete it
		}
	#
	# perform special handling of <SELECT> form field defaults since it is too difficult
	#	to do with the standard TemplateFile architecture
	#
	my ($sSelectName, $sDefaultOption);
	while ( ($sSelectName, $sDefaultOption) = each %$pSelectTable)
		{
		$sHTML =~ s/(<\s*SELECT[^>]+?NAME\s*=\s*("|')?$sSelectName.+?)<OPTION\s+VALUE\s*=\s*("|')?$sDefaultOption("|')?\s*>/$1<OPTION SELECTED VALUE="$sDefaultOption">/is;
		}

	return ($::SUCCESS, "", $sHTML);
	}

#######################################################
#
# IsCustomerAllowedToBuy - See the price schedules and
#		determine if the customer is allowed to buy
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	$bAllowedToBuy - $::FALSE == current customer is not allowed to buy
#				$Message			- failure message if $bAllowedToBuy == $::FALSE
#
# Author: Tibor Vajda
#
#######################################################

sub IsCustomerAllowedToBuy
	{
	my ($pProduct) = @_;
	my $sMessage;
	my $bAllowedToBuy = $::TRUE;
	#
	# Need to work out which prices to show
	#
	my ($bShowRetailPrices, $bShowCustomerPrices, $nAccountSchedule) = ACTINIC::DeterminePricesToShow();
	#
	# Distinguish retail and business users
	#
	if ('' ne $ACTINIC::B2B->Get('UserDigest'))
		{
		#
		# A registered user is not allowed to buy if:
		#
		if (
				( 	#
					# The user is on retail price only and no retail price for the product
					#
					($::FALSE == $bShowCustomerPrices) &&
					($::TRUE == $bShowRetailPrices) &&
					(0 ==  scalar(@{$pProduct->{'PRICES'}->{$ActinicOrder::RETAILID}}))
				)
				||	# OR
				(
					(	#
						# The user is on a price schedule and there is no price for this schedule
						#
						($::TRUE == $bShowCustomerPrices) &&
						(0 == scalar(@{$pProduct->{'PRICES'}->{$nAccountSchedule}}))
					)
					&&	# AND
					(	#
						# Either the user cannot order on retail price or no retail price included for the product
						#
						($::FALSE == $bShowRetailPrices) ||
						(0 == scalar(@{$pProduct->{'PRICES'}->{$ActinicOrder::RETAILID}}))
					)
				)
			)
			{
			$sMessage = ACTINIC::GetPhrase(-1, 351);	# 'This product is currently unavailable'
			$bAllowedToBuy = $::FALSE;
			}
		}
	else
		{
		#
		# An unregistered customer is not allowed to buy if the retail price is not available for the product
		#
		if (0 == scalar(@{$pProduct->{'PRICES'}->{$ActinicOrder::RETAILID}}))
			{
			$sMessage = ACTINIC::GetPhrase(-1,333);# 'This product is only avalable to registered customers'
			$bAllowedToBuy = $::FALSE;
			}
		}
	return ($bAllowedToBuy, $sMessage);
	}


##############################################################################################################
#
# Command Processing - End
#
##############################################################################################################

##############################################################################################################
#
# Text Processing - Begin
#
##############################################################################################################

#######################################################
#
# FormatProductReference - format the product reference
#
# Params:	$_[0] - the product reference
#
# Returns:	($ReturnCode, $Error, $sFormattedText, 0)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#
#######################################################

sub FormatProductReference
	{
	if (!defined $_[0])
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 12, 'FormatProductReference'), 0, 0);
		}

	my ($sProdRef, $sFormat, $sLine, @Response, $Status, $Message);
	$sProdRef = $_[0];									# retrieve the product ref from the argument list
	$sLine = "";

	if ($$::g_pSetupBlob{"PROD_REF_COUNT"} > 0)			# if the product ref is to be displayed
		{
		$sProdRef =~ s/^\d+\!//g;						# if there is a duplicate product code then remove it
		$sLine = ACTINIC::GetPhrase(-1, 65, $sProdRef);		# format the message

		@Response = ACTINIC::EncodeText($sLine);	# convert the special characters to their hex codes
		($Status, $sLine) = @Response;
		if ($Status != $::SUCCESS)
			{
			return (@Response);
			}
		}
	return ($::SUCCESS, "", $sLine, 0);
	}

##############################################################################################################
#
# Text Processing - End
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
	$::prog_name = "SHOPCART";							# Program Name
	$::prog_name = $::prog_name;
	$::prog_ver = '$Revision: 23746 $ ';				# program version
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
	# read the SSP setup blob
	#
	@Response = ACTINIC::ReadSSPSetupFile(ACTINIC::GetPath());
	if ($Response[0] != $::SUCCESS)
		{
		ACTINIC::ReportError($Response[1], ACTINIC::GetPath());
		}

	$ACTINIC::B2B->Set('UserDigest',ACTINIC::CAccFindUser());
	#
	# initialize some global hashes (must come after prompt file)
	#
	ACTINIC::InitMonthMap();
	# PRESNET
	#
	# initialize some Presnet hashes (must come after prompt file)
	#
	if(!defined $::g_InputHash{"ACTION"})
		{
		if(defined $::g_InputHash{"ACTION_CONFIRM.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sConfirmButtonLabel;
			}
		elsif(defined $::g_InputHash{"ACTION_CANCEL.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sCancelButtonLabel;
			}
		elsif(defined $::g_InputHash{"ACTION_BUYNOW.x"})
			{
			$::g_InputHash{"ACTION"} = ACTINIC::GetPhrase(-1, 184);
			}
		elsif(defined $::g_InputHash{"ACTION_SEND.x"})
			{
			$::g_InputHash{"ACTION"} = $::g_sSendCouponLabel;
			}
		elsif (defined $$::g_pSetupBlob{'EDIT_IMG'} && $$::g_pSetupBlob{'EDIT_IMG'} ne '')
			{
			my $sKey;
			foreach $sKey (keys(%::g_InputHash))
				{
				if ($sKey =~ /^ACTION_EDIT(\d+)\.x/)
					{
					$::g_InputHash{$1} = $::g_sEditButtonLabel;
					}
				elsif ($sKey =~ /^ACTION_REMOVE(\d+)\.x/)
					{
					$::g_InputHash{$1} = $::g_sRemoveButtonLabel;
					}
				}
			}
		}
	# PRESNET
	}

#######################################################
#
# ReadAndParseInput - read the input and parse it
#
# Expects:	$ENV to be defined
#
#
# Returns:	($ReturnCode, $Error)
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
# Returns:	($ReturnCode, $Error)
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
	($Status, $Message) = @Response; # parse the response
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
	# Set the old global variables for compatibility
	#
	$::g_sWebSiteUrl = $::Session->GetBaseUrl();
	$::g_sContentUrl = $::g_sWebSiteUrl;

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
	%::g_BillContact = %$pBillContact;				# copy the hashes to global tables
	%::g_ShipContact = %$pShipContact;
	%::g_ShipInfo		= %$pShipInfo;
	%::g_TaxInfo		= %$pTaxInfo;
	%::g_GeneralInfo = %$pGeneralInfo;
	%::g_PaymentInfo = %$pPaymentInfo;
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
# ReturnToLastPage - bounce the browser to the previous
#	page.  NOTE: this is a wrapper for the ACTINIC
#	package version.  It prevents a bunch of duplicate
#	work
#
# Params:	[0] - bounce delay
#				[1] - string to add to display
#				[2] - optional page title.  If the page
#						title exists, the page is formatted
#						using the bounce template
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	($ReturnCode, $Error, $sHTML, 0)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the bounce page
#
#######################################################

sub ReturnToLastPage
	{
	my ($nDelay, $sMessage, $sTitle);
	($nDelay, $sMessage, $sTitle) = @_;
	if (!defined $sTitle)
		{
		$sTitle = "";
		}

	return (ACTINIC::ReturnToLastPage($nDelay, $sMessage, $sTitle,
												 $::g_sWebSiteUrl,
												 $::g_sContentUrl, $::g_pSetupBlob, %::g_InputHash));
	}

#######################################################
#
# GroomHTML - Display HTML with header/footer and background
#	NOTE: this is a wrapper for the ACTINIC
#	package version.  It prevents a bunch of duplicate
#	work  (Presnet).
#
# Params:	[0] - string to add to display
#				[1] - optional page title.  If the page
#						title exists, the page is formatted
#						using the bounce template
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	($ReturnCode, $Error, $sHTML, 0)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the page
#
#######################################################

sub GroomHTML
	{
	my ($sMessage, $sTitle);
	($sMessage, $sTitle) = @_;
	if (!defined $sTitle)
		{
		$sTitle = "";
		}

	return (ACTINIC::GroomHTML($sMessage, $sTitle,
										 $::g_sWebSiteUrl,
										 $::g_sContentUrl, $::g_pSetupBlob, %::g_InputHash));
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
	#
	# Create cart cookie before process
	#
	my $sCartCookie = ActinicOrder::GenerateCartCookie();
	return (
			  ACTINIC::UpdateDisplay($_[0], $::g_OriginalInputData,
											$_[1], $_[2], '', $sCartCookie)
			 );
	}

#######################################################
#
# AddLink - Formats the HTML for a <A> link  (Presnet)
#
# Params:	[0] - URL
#				[1] - Text
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	($ReturnCode, $Error, $sHTML, 0)
#				if $ReturnCode = $::FAILURE, the operation failed
#					for the reason specified in $Error
#				Otherwise everything is OK
#				$sHTML - the HTML of the link
#
#######################################################

sub AddLink
	{
	my ($sURL, $sTarget, $sImage, $sAlt, $sText) = @_;
	my ($sHTML);
	#
	# add the opening tag
	#
	$sHTML .= "<A HREF=\"";
	$sHTML .= $sURL . "\"";
	#
	# add the target
	#
	$sHTML .= " TARGET=\"" . $sTarget . "\">";
	#
	# add the image
	#
	if (defined $sImage && $sImage ne '' && ACTINIC::CheckFileExists($sImage, ACTINIC::GetPath()))
		{
		$sHTML .= "<IMG SRC=\"" . $sImage ."\" ALT=\"" . $sAlt . "\" BORDER=0><BR>";
		}
	#
	# add the text label
	#
	$sHTML .= "" . $sText . "</A><BR>";
	return($::SUCCESS, "", $sHTML);
	}

#######################################################
#
# ShowCart - Gets the HTML for displaying
#		the cart contents with links to continue shopping
#		and going to checkout
#
# Expects:	%::g_InputHash should be defined
#
# Author: Zoltan Magyar, 11:37 AM 2/12/2002
#
#######################################################

sub ShowCart
	{
	my ($Status, $Message, $sHTML);
	#
	# First Validate the cart
	#
	my ($pCartObject, @Response);
	@Response = $::Session->GetCartObject();
	($Status, $Message, $pCartObject) = @Response;	# parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		exit;
		}
	my $pCartList = $pCartObject->GetCartList();
	my @aFailureList;

	my ($pOrderDetail, $sErrorMessage);
	my $nIndex;
	#
	# When the items are removed then process the remained ones
	#
	$nIndex	= 0;
	foreach $pOrderDetail (@{$pCartList})
		{
		#
		# Do the validation item by item
		# Note: tha failed validation of any item MAY NOT stop
		# the processing
		#
		# Validate the cart total
		#
		my ($nStatus, $sMessage, $pFailure) = ActinicOrder::ValidateOrderDetails($pOrderDetail, -2);
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
	# Construct error message
	#
	if (length $sErrorMessage > 0)
		{
		my $sHTML = sprintf($::ERROR_FORMAT, $sErrorMessage);
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', $sHTML);
		}
	else
		{
		$ACTINIC::B2B->SetXML('CARTUPDATEERROR', '');
		}
	@Response = ActinicOrder::ShowCart(\@aFailureList);
	($Status, $Message, $sHTML) = @Response; # parse the response
	if ($Status != $::SUCCESS)
		{
		ACTINIC::ReportError($Message, ACTINIC::GetPath());
		exit;
		}
	PrintPage($sHTML, $::Session->GetSessionID());
	#
	# Once we got here then no more processing required
	#
	exit;
	}

#######################################################
#
# PrintSSLBouncePage - create and print bouncing page
#		to OrderScript on the SSL site
#
# Params:	none
#
# Expects:	%::g_InputHash should be defined
#
# Returns:	nothing
#
#######################################################

sub PrintSSLBouncePage
	{
#? ACTINIC::ASSERT(defined $::g_InputHash{"URL"}, "URL parameter is not defined in PrintSSLBouncePage", __LINE__, __FILE__);
#? ACTINIC::ASSERT($::g_InputHash{"URL"} =~ /https:/, "URL parameter is not an https reference in PrintSSLBouncePage", __LINE__, __FILE__);
	my $sHTML;
	my ($nLineCount, @Response, $Status, $Message);
	my $pCartObject;
	@Response = $::Session->GetCartObject();
	if ($Response[0] != $::SUCCESS)					# closed cart
		{
		$nLineCount = 0;									# if so then the order line count is zero
		}
	else														# otherwise
		{
		$pCartObject = $Response[2];					# get the cart
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
		}
	else
		{
		#
		# Get the encoded cookie and referrer values
		#
		my $sCookie 		= ACTINIC::EncodeText2($ENV{'HTTP_COOKIE'}, $::TRUE);
		my $sSessionID 	= ACTINIC::EncodeText2($::Session->GetSessionID(), $::TRUE);
		my $sBusinessCookie 	= ACTINIC::CAccBusinessCookie();

		my $sReferrer	= ACTINIC::GetReferrer();
		if ((defined $::g_InputHash{REFPAGE}) &&		# REFPAGE is defined
		   (!ACTINIC::IsStaticPage($sReferrer)))		# And is not a static page
			{
			my ($sBefore, $sAfter) = split(/\?/, $sReferrer);
			my ($sNewRefPage) = "REFPAGE=" . ACTINIC::EncodeText2($::g_InputHash{REFPAGE}, $::FALSE);
			if ($sAfter !~ /=/)								# if there are no params (but may have target)
				{
				$sAfter = $sNewRefPage . $sAfter			# prefix with new REFAPGE
				}
			elsif ($sAfter =~ /(^|\&)REFPAGE=.*?(\&|$)/)	# If REFPAGE already defined in Referrer
				{
				$sAfter =~ s/(^|\&)REFPAGE=.*?(\&|$)/$1$sNewRefPage$2/;	# replace it with new REFPAGE
				}
			else
				{
				$sAfter = $sNewRefPage . ($sAfter =~ /=/ ? "&" : "") . $sAfter; # prefix with new REFPAGE parameter
				}
			$sReferrer = $sBefore . "?" . $sAfter;		# rebuild the referrer
			}
		#
		# Generate the SSL redirect page
		#
		my ($sURL, $sParams) = split /\?/, $::g_InputHash{'URL'};

		my %EncodedInput = split(/[&=]/, $sParams);
		my ($key, $value);
		my $sHTMLParams;
		while (($key, $value) = each %EncodedInput)
			{
			$value = ACTINIC::DecodeText($value, $ACTINIC::FORM_URL_ENCODED);
			$value = ACTINIC::EncodeText2($value);
			$sHTMLParams .= sprintf("<INPUT TYPE=HIDDEN NAME='%s' VALUE='%s'>", $key, $value);
			}

		$sHTML = "<HTML><HEAD>\n" .
			"<SCRIPT LANGUAGE='JavaScript'>\n" .
			"<!-- \n" .
			"function onLoad() {document.Bounce.submit();}\n" .
			"// -->\n" .
			"</SCRIPT>\n" .
			"</HEAD>\n" .
			"<BODY OnLoad='onLoad();'>\n" .
			"<FORM NAME='Bounce' METHOD=POST ACTION='$sURL'>\n" .
			"<INPUT TYPE=HIDDEN NAME='ACTINIC_REFERRER' VALUE='$sReferrer'>\n" .
			"<INPUT TYPE=HIDDEN NAME='COOKIE' VALUE='$sCookie'>\n" .
			"<INPUT TYPE=HIDDEN NAME='SESSIONID' VALUE='$sSessionID'>\n" .
			"<INPUT TYPE=HIDDEN NAME='DIGEST' VALUE='$sBusinessCookie'>\n" .
			$sHTMLParams .
			"</FORM>\n" .
			"</HEAD></HTML>\n";
		}
	ACTINIC::PrintPage($sHTML, $::Session->GetSessionID());
	}

#######################################################
#
# BounceHelper - helps to keep track with referencing
#		page data
#
# Params:	$sHTML - bounce page
#
# Returns:	1 - status (success or failure)
#				2 - the result HTML in case of success
#				3 - the error message in case of failure
#				4 - the cart ID if available
#
#######################################################

sub BounceHelper
	{
	my $sHTML = shift @_;
	my @Response;

	if( !$ACTINIC::B2B->Get('UserDigest') )
		{
		@Response = ACTINIC::MakeLinksAbsolute($sHTML, $::g_sWebSiteUrl, $::g_sContentUrl);
		}
	else
		{
		my $sBaseFile = $ACTINIC::B2B->Get('BaseFile');
		my $smPath = ($sBaseFile) ? $sBaseFile : $::g_sContentUrl;
		my $sCgiUrl = $::g_sAccountScript;
		$sCgiUrl   .= ($::g_InputHash{SHOP} ? '?SHOP=' . ACTINIC::EncodeText2($::g_InputHash{SHOP}, $::FALSE) . '&': '?');
		$sCgiUrl   .= 'PRODUCTPAGE=';
		@Response = ACTINIC::MakeLinksAbsolute($sHTML, $sCgiUrl, $smPath);
		}
	return(@Response);
	}

#######################################################
#
# ParseDateStamp - parses date in form YYYY/MM/DD, and
#						 returns the separate values
#
# Params:	0 - Date formatted YYYY/MM/DD
#
# Returns:	1 - $nYear
#				2 - $nMonth
#				3 - $nDay
#				4 - $sMonth (the name of the month)
#
#######################################################

sub ParseDateStamp
	{
	my $sDate = shift @_;
	my ($nYear, $nMonth, $sMonth, $nDay);

				$sDate =~ /(\d+)\/(\d+)\/(\d+)/;		# parse the string
				$nYear = $1;
				$nMonth = $2 +1 - 1;						# just be sure, it is a number
				$sMonth = $::g_InverseMonthMap{$nMonth};	# get the name of the month
				$nDay = $3 + 1 - 1;						# just be sure, it is a number
	return ($nYear, $nMonth, $nDay, $sMonth);
	}


##############################################################################################################
#
# Output - End
#
##############################################################################################################
