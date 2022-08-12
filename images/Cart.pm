#!perl
################################################################
#
#  Cart.pm - impementation of the cart object
#
#  Based on 
#    Cart related functions of ActinicOrder.pm
#
#  Zoltan Magyar, 10:50 AM 12/3/2001
#
#  Copyright (c) Actinic Software Plc 2001
#
################################################################
package Cart;
require 5.002;

push (@INC, "cgi-bin");
<Actinic:Variable Name="IncludePathAdjustment"/>

use strict;
#
# Constants definition
#
require <Actinic:Variable Name="ActinicConstantsPackage"/>;
require <Actinic:Variable Name="ActinicDiscountsPackage"/>;
#
# Version
#
$Cart::prog_name = 'Cart.pm';							# Program Name
$Cart::prog_name = $Cart::prog_name;				# remove compiler warning
$Cart::prog_ver = '$Revision: 22228 $ ';				# program version
$Cart::prog_ver = substr($Cart::prog_ver, 11); 	# strip the revision information
$Cart::prog_ver =~ s/ \$//;							# and the trailers
#
# Xml main entry names
#
$Cart::XML_CARTROOT	= 'ActinicSavedCart';		# the root XML entry
$Cart::CARTVERSION	= "1.0";							# the cart XML version

################################################################
#
#  Cart->new() - constructor for Cart class
#
#  A very standard constructor. Allows inheritance.
#  Calls Set() function passing it all the arguments.
#  So the arguments may be specified here with name=>value
#  pairs or they may be set later using Set() method.
#
#  No arguments are obligatory in new(). But CARTSTRING 
#  parameter might be specified.
#
#  Zoltan Magyar - 11:25 AM 12/4/2001
#
#  Copyright (c) Actinic Software Ltd 1999
#
################################################################

sub new
	{
	my $Proto 			= shift;
	my $sCartID			= shift;							# receive the cart (or session) ID
	my $sPath			= shift;							# catalog path
	my $pCart 			= shift;							# receive cart structure (list of products) if defined
	my $bIsCallBack 	= shift;							# the cart object is created during a call-back validation or not
	my $Class = ref($Proto) || $Proto;
	my $Self  = {};										# create self 
	bless ($Self, $Class);								# populate
	#
	# The session ID must be specified
	#
#? ACTINIC::ASSERT($sCartID, "The session ID must be specified for the cart object", __LINE__, __FILE__);
	$Self->{_CARTID}  = $sCartID;
	$Self->{_PATH}		= $sPath;
	$Self->{_ISCALLBACK} = $bIsCallBack;
	#
	# Set up the adjustment fields
	#
	$Self->{_PRODUCTADJUSTMENTS}	= {};
	$Self->{_ORDERADJUSTMENTS}	= ();
	$Self->{_FINALORDERADJUSTMENTS}	= ();
	$Self->{_ADJUSTMENTSCOUNT}	= 0;
	$Self->{_PRODUCTADJUSTMENTSPROCESSED} = $::FALSE;
	$Self->{_ORDERADJUSTMENTSPROCESSED} = $::FALSE;
	$Self->{_FINALORDERADJUSTMENTSPROCESSED} = $::FALSE;
	$Self->{_PASSWORDHASH} = '';
	#
	# Set cart content if defined
	#
	$Self->SetCart($pCart);							# store the cart in member variable

	return $Self;
	}

##############################################################################################################
#
# Get/Set methods
#
##############################################################################################################	
################################################################
#
#  Session->SetCart() - set the cart 
#
#  Input:	 0 - reference to a list of products
#
################################################################

sub SetCart
	{
	my $Self  = shift;
	my $pCart = shift;									# reference to a list of products	
	#
	# Store it in private member
	#
	$Self->{_CART} = $pCart;
	#
	# Then process it immediately
	#
	$Self->ProcessCart();
 	}

################################################################
#
#  Session->GetCart() - get the cart structure
#
#	Output:		0 - parameter value
#
################################################################

sub GetCart
	{
	my $Self		= shift;
	return $Self->{_CART};
 	} 	
 	
################################################################
#
#  Session->GetCartList() - get the array of cart items
#
#	Output:		0 - parameter value
#
################################################################

sub GetCartList
	{
	my $Self		= shift;
	return $Self->{_CartList};
 	} 	
 	
##############################################################################################################
#
# Cart processing methods
#
##############################################################################################################	 	
################################################################
#
# Cart->ProcessCart() - read the shopping cart
#
# This function caches the cart contents to prevent
#	multiple disk hits.  The Cache is maintained by
#  the other cart functions as well.
#
# Output:	0 - status
#				1 - message
#				2 - a pointer to an array containing the 
#					hashes of the individual order details
#
################################################################

sub ProcessCart
	{
	my $Self = shift;
	
	my @Response;
	#
	# Empty the cart
	#
	$Self->{_CartList} = [];
	#
	# Get XML cart
	#
	my ($nStatus, $sMessage, $pFailures) = $Self->FromXml($Self->GetCart(), $::TRUE);
	if ($nStatus == $::FAILURE)
		{
		ACTINIC::TerminalError($sMessage);
		}
	#
	# Check for similar items
	#
	if ($#{$Self->{_CartList}} > 0)
		{
		$Self->CombineCartLines(); # Combine identical cart lines
		}
	return ($::SUCCESS, '', \@{$Self->{_CartList}});		
	}

################################################################
#
# Cart->ClearCart() - Clear the shopping cart
#
# Output:	0 - status
#				1 - message
#				2 - a pointer to an array containing the 
#					hashes of the individual order details
#
################################################################

sub ClearCart
	{
	my $Self = shift;
	
	my @Response;
	#
	# Empty the cart
	#
	$Self->{_CartList} = [];
	return ($::SUCCESS, '', \@{$Self->{_CartList}});		
	}

################################################################
#
#  Cart->CombineCartLines() 
#
#  Compares lines in the product cart and modifies Cart List so that
#  if the same product appears more than once, it shows as one item
#  with all quantities added.
#
#  CartList may get modified here!
#
#  Ryszard Zybert  Dec 12 21:49:20 GMT 2000
#
#  Copyright (c) Actinic Software Ltd (2000)
#
################################################################

sub CombineCartLines
	{
	my $Self 		= shift;
	my $pCartList 	= $Self->{_CartList};												# reference to cart list
	my $nCartIndex;
	my %Removed;																				# list of removed items

	for( $nCartIndex = 1; $nCartIndex <= $#$pCartList; $nCartIndex++ )		# loop over the whole list
		{
		my $pCartItem = $pCartList->[$nCartIndex];
		my @aFoundIndices = $Self->FindSimilarCartItems($pCartItem, 0, $nCartIndex - 1);
		my $nFoundIndex;
		foreach $nFoundIndex (@aFoundIndices)
			{
			$Removed{$nCartIndex} = $::TRUE;												# Identical, remember to remove this one
			$pCartList->[$nFoundIndex]->{QUANTITY} += $pCartList->[$nCartIndex]->{QUANTITY};		# add quantity to the other one
			}
		}
	foreach (sort {$b <=> $a} keys(%Removed))											# Remove repeated lines (backwards!)
		{
		splice @$pCartList,$_,1;
		}
	}

################################################################
#
#  Cart->FindSimilarCartItems() 
#
#  Compares a specified cart item with a range of items in  the cart
#	
#	Input	:	$pCartItem					- cart item to be compared
#				$nLowerIdx	(optional)	- lower index of the analyzed range of the cart
#				$nLowerIdx	(optional)	- upper index of the analyzed range of the cart
#
#	Output:	@aFoundIndices				- indices of items in cart, which are similar to the specified item
#
#  Author:	Tibor Vajda
#
#  Copyright (c) Actinic Software Ltd (2002)
#
################################################################

sub FindSimilarCartItems
	{
		my $Self				= shift;
		my $pCartItem		= shift;
		my $pCartList	= $Self->{_CartList};
		my $nLowerCartIdx	= $#_ > -1 ? shift : 0;	# optional cart processing range bound - default: 0
		my $nUpperCartIdx = $#_ > -1 ? shift : $#$pCartList; # optional cart processing range bound - default: cart item count
		my @aFoundIndices;
		my $nFoundIndex;
		#
		# Loop through the specified cart range
		#
FIND:	for( $nFoundIndex = $nLowerCartIdx; $nFoundIndex <= $nUpperCartIdx; $nFoundIndex++ )	
			{
			#
			# Compare $pCartItem with the $nFoundIndex-th item in the cart
			#
			foreach (keys %{$pCartItem}, keys %{$pCartList->[$nFoundIndex]})	# compare all fields except quantity
				{
				if( ($_ ne 'QUANTITY') &&				# not the quantity
					 ($_ ne 'SID')  &&					# not the section ID													
					 $pCartItem->{$_} ne $pCartList->[$nFoundIndex]->{$_} )	
					{
					#
					# Not similar, try the next item
					#
					next FIND;							
					}
				}
			push @aFoundIndices, $nFoundIndex;											# add the similar item to the return list
			}
		return @aFoundIndices;
	}

################################################################
#
# Cart->UpdateCart() - update the cart string
#	Any cart operation is done on the cart array. Before
#	the cart is saved all changes should be reflected back 
#	to the cart string which is done by this function.
#
# Output:	0 - status
#				1 - error message
#
################################################################

sub UpdateCart
	{
	my $Self = shift;

	my @Response = $Self->ToXml();
	if ($Response[0] == $::SUCCESS)
		{
		#
		# Store it in private member
		#
		$Self->{_CART} = $Response[2];
		}
	return @Response;	
	}	
	
################################################################
#
# Cart->AddItem() - add the specified order detail
#	to the shopping cart
#
# Input:		0 - a reference to order detail object
#
# Output:	0 - status
#				1 - error message
#				2+ - 0
#
################################################################

sub AddItem
	{
	my $Self = shift;
	my $pOrderDetail = $_[0];

	push (@{$Self->{_CartList}}, {%{$pOrderDetail}});	# add it to the list of orders

	return ($::SUCCESS, '');
	}
	
################################################################
#
# Cart->CountItems - count the number of order detail
#	lines in the specified cart
#
# Output:	0 - the number of items in the cart
#
################################################################

sub CountItems
	{
	my $Self = shift;
	
	if (defined $Self->{_CartList})					# if the cart is alread cached
		{														# return immediately
		return $#{$Self->{_CartList}} + 1;
		}

	my $pCartList = ProcessCart();					# read the guts of the cart

	#
	# TODO: Handle empty cart here
	#

	my $nCount = $#$pCartList + 1;

	return $nCount;
	}	
	
################################################################
#
# Cart->CountQuantities - summarize the number of items in each
#  order detail lines 
#
# Output:	0 - the summarized quantity
#
################################################################

sub CountQuantities
	{
	my $Self = shift;
	my $pItem;
	my $nCount = 0;										# counter
	
	foreach $pItem (@{$Self->{_CartList}})			# for all item in the cart
		{														
		$nCount += $pItem->{'QUANTITY'};				# add the quantity to the sum
		}

	return $nCount;
	}	
	
################################################################
#
# Cart->UpdateItem() - change the specified item in the
#	specified cart to be the item stored in the specified
#	object.  By specified, I mean passed-in
#
# Input:		0 - item id (number in item list)
#				2 - a reference to the cart item
#
# Output:	0 - status
#				1 - error message
#
################################################################

sub UpdateItem
	{
	my $Self 			= shift;
	my $nItemIndex 	= shift;
	my $pOrderDetail 	= $_[0];
	#
	# Check if the index is invalid and bomb out
	#
	if ($nItemIndex < 0 ||
		 $nItemIndex > $#{$Self->{_CartList}} )
		{
		return($::NOTFOUND, "");
		}	
	#
	# Otherwise update the cart
	#
	$Self->{_CartList}[$nItemIndex] = {%{$pOrderDetail}};	# add it to the list of orders
	return ($::SUCCESS, '');
	}
	
################################################################
#
# Cart->RemoveItem() - remove the specified item from
#	the cart file
#
# Input:		0 - item id (number in item list)
#
# Output:	0 - status
#				1 - error message
#
################################################################

sub RemoveItem
	{
	my $Self 		= shift;
	my $nItemIndex = shift;
	#
	# Check if the index is invalid and bomb out
	#
	if ($nItemIndex < 0 ||
		 $nItemIndex > $#{$Self->{_CartList}} )
		{
		return($::NOTFOUND, "");
		}
	#
	# Otherwise remove the item from the cart
	#
	splice @{$Self->{_CartList}}, $nItemIndex, 1;
	return ($::SUCCESS, '');
	}
	
################################################################
#
# Cart->GetAlsoBoughtList() - get also bought list of for the cart
#
# Input:		$sTpe	- type of the list (ALSOBOUGHT/RELATED)
#
# Output:	0 - status
#				1 - error message
#				2 - resulting list
#
################################################################

sub GetRelatedList
	{
	my $Self 		= shift;
	my $sType		= shift;
	#
	# Store the cart items in hash for quick lookup
	#
	my %hCartList;
	my %hAlsoBoughtRefs;
	my $pCartItem;
	foreach $pCartItem (@{$Self->{_CartList}})
		{
		$hCartList{$pCartItem->{'PRODUCT_REFERENCE'}} = 1;
		}
	#
	# Now create a list of unique also bought items
	#
	foreach $pCartItem (@{$Self->{_CartList}})	# for each product in the cart
		{
		#
		# For each also bought items of the cart item
		#
		my ($Status, $Message, $pProduct) = GetProduct($pCartItem->{'PRODUCT_REFERENCE'}, $pCartItem->{'SID'});
		foreach my $sABRefs (@{$$pProduct{$sType}})
			{
			#
			# If the also bought item is not in the cart
			#
			if (!defined $hCartList{$sABRefs})
				{
				$hAlsoBoughtRefs{$sABRefs} = 1;		# then add it to the list
				}
			}
		}
	#
	# Generate random array
	#
	srand;
	my @aOriginal = keys %hAlsoBoughtRefs;
	my @aReturn;
	while (@aOriginal) 
		{
		push(@aReturn, splice(@aOriginal, rand @aOriginal, 1));
		}
	return ($::SUCCESS, '', \@aReturn);
	}
	
##############################################################################################################
#
# My Shopping List related functions
#
##############################################################################################################		
################################################################
#
# Cart->IsExternalCartFileExist() - check if restore is
# available for the customer
#
# Output:	0 - result - $::TRUE/$::FALSE
#
################################################################

sub IsExternalCartFileExist
	{
	my $Self 		= shift;
	#
	# Get the name of the shopping list file
	#
	my $sFileName = $Self->GetExternalCartFileName();
	#
	# Check if the file exist 
	#
	return ($sFileName ne '' && -e $sFileName);
	}

################################################################
#
# Cart->GetExternalCartFileName() - determine the external
# (import/export) cart file name for the given customer
#
# Output:	0 - the determined file name
#
################################################################

sub GetExternalCartFileName
	{
	my $Self 		= shift;
	my $sFileName;
	if ($::g_pSetupBlob->{'NAMED_SHOPPING_CART'})
		{
		my $sFileName = lc($::g_InputHash{'CART_USERNAME'});
		if ($sFileName ne '')
			{
			$sFileName = ACTINIC::GetMD5Hash($sFileName . $::sSavedCartSecretKey);
			return (ACTINIC::GetPath() . $sFileName . '.save');
			}
		}
	else
		{
		#
		# Is this a business account?
		#
		my ($sDigest,$sBaseFile) = ACTINIC::CaccGetCookies();	# See if the user logged in already	
		if ($sDigest)
			{
			my ($Status, $sMessage, $pBuyer) = ACTINIC::GetBuyer($sDigest, ACTINIC::GetPath()); # look up the buyer
			if ($Status != $::SUCCESS)
				{
				return ("");
				}
			$sFileName = "reg_" . $$pBuyer{AccountID};
			}
		else
			{
			#
			# Retail customer so the file name is the cart ID
			#
			$sFileName = $Self->{_CARTID};
			}
		return (ACTINIC::GetPath() . $sFileName . '_00.save');
		}
	return '';
	}
	
################################################################
#
# Cart->ToXml() - 	returns the xml representation
#							of the cart 
#
# Output:	0 - status
#				1 - error message
#				2 - list of xml descriptions of the products
#
################################################################

sub ToXml
	{
	my $Self 		= shift;
	my $pXmlCartItems = [];
	#
	# Process the items in the cart
	#
	my $pCartItem;
	foreach $pCartItem (@{$Self->{_CartList}})
		{
		#
		# Retrieve the product object
		#
		my ($Status, $Message, $pProduct) = GetProduct($pCartItem->{'PRODUCT_REFERENCE'}, $pCartItem->{'SID'});
		if ($Status == $::FAILURE)
			{
			return ($Status, $Message, []);
			}
		elsif ($Status == $::NOTFOUND)				# product lookup problem?
			{
			next;												# skip product;
			}
		#
		# Compose the cart item node
		#
		my $pXmlCartItem = new Element();			# create the node of this item
		$pXmlCartItem->SetTag('Product');			# set the name of the node
		$pXmlCartItem->SetAttributes({'Reference' => $pCartItem->{'PRODUCT_REFERENCE'},
												'Name' 		=> $pProduct->{'NAME'},
												'SID'			=> $pCartItem->{'SID'}});
		#
		# Compose the quantity child node
		#
		$pXmlCartItem->SetTextNode('Quantity', $pCartItem->{'QUANTITY'}); # add the quantity child node to the item node
		#
		# Compose the Info child node
		#
		if ($pCartItem->{'INFOINPUT'})				# if Info prompt is given
			{
			$pXmlCartItem->SetTextNode('Info', $pCartItem->{'INFOINPUT'}); # add the info child node to the item node
			}			
		#
		# Compose the Date child node
		#
		if ($pCartItem->{'DATE'})						# if Date prompt is given
			{
			my $sDate = $pCartItem->{'DATE'};		# temporal storage of date
			if ($sDate =~ /([0-9]{4})\/([0-9]{2})\/([0-9]{2})/) # parse the date, which is in yyyy/mm/dd format
				{
				my $pXmlDate = new Element();				# create the info child node object 
				$pXmlDate->SetTag('Date');					# set the name of node
				$pXmlDate->SetAttributes({ 'Day' 	=> $3, 	# set the day attribute
													'Month'	=> $2, 	# set the month attribute
													'Year'	=> $1});	# set the year attribute
				$pXmlCartItem->SetChildNode($pXmlDate); # add the info child node to the item node
				}
			}			
		#
		# Compose the QDQualify child node
		#
		if (exists $pCartItem->{'QDQUALIFY'})
			{
			$pXmlCartItem->SetTextNode('QDQualify', $pCartItem->{'QDQUALIFY'}); # add the qdqualify child node to the item node
			}
		#
		# Compose the Component and Attribute child nodes
		#
		if( $pProduct->{COMPONENTS} )
			{
			my ($VariantList, $k);
			foreach $k (keys %{$pCartItem})
				{
				if( $k =~ /^COMPONENT\_/ )
					{
					$VariantList->[$'] = $pCartItem->{$k};
					}
				}
			my %Component;
			my $pItem;
			my $nIndex = 0;
			foreach $pItem (@{$pProduct->{COMPONENTS}})
				{
				my @Response = ActinicOrder::FindComponent($pItem, $VariantList);
				($Status, %Component) = @Response;
				if ($Status == $::FAILURE)
					{
					return ($Status, $Component{text});
					}
				my $pNames = $Component{Names};
				if (!$pNames)								# be paranoid and init if isn't defined 
					{
					$pNames = {};
					}
				if ($pNames->{COMPONENT})				# it is a component
					{
					my $pXmlComponent = new Element();
					$pXmlComponent->SetTag("Component");
					$pXmlComponent->SetAttributes({"Name"	=> $pNames->{COMPONENT}->{NAME},
															 "Index"	=> $pNames->{COMPONENT}->{INDEX}});
					if (1 < keys %{$pNames})			# is there any attribute?
						{
						my $sAttribute;
						foreach $sAttribute (keys %{$pNames})	# check them
							{
							if ($sAttribute ne "COMPONENT")	# component name?
								{										# no so add to the XML
								my $pXMLAttribute = new Element();
								$pXMLAttribute->SetTag("Attribute");
								$pXMLAttribute->SetAttributes({"Index"	=> $sAttribute,
																		 "Value"	=> $pNames->{$sAttribute}->{VALUE},
																		 "Name"	=>	$pNames->{$sAttribute}->{ATTRIBUTE},
																		 "Choice"=> $pNames->{$sAttribute}->{CHOICE}});
								$pXmlComponent->AddChildNode($pXMLAttribute);
								}
							}
						}
					$pXmlCartItem->AddChildNode($pXmlComponent);	
					}
				else											# it is an attribute
					{
					my $sAttribute;
					foreach $sAttribute (keys %{$pNames})	# check them
						{
						if ($sAttribute ne "COMPONENT")	# component name?
							{										# no so add to the XML
							my $pXMLAttribute = new Element();
							$pXMLAttribute->SetTag("Attribute");
							$pXMLAttribute->SetAttributes({"Index"	=> $sAttribute,
																	 "Value"	=> $pNames->{$sAttribute}->{VALUE},
																	 "Name"	=>	$pNames->{$sAttribute}->{ATTRIBUTE},
																	 "Choice"=> $pNames->{$sAttribute}->{CHOICE}});							
							$pXmlCartItem->AddChildNode($pXMLAttribute);
							}
						}					
					}
				$nIndex++;
				}
			}		
		#		
		# Add the cart item node to the root
		#
		push (@{$pXmlCartItems}, $pXmlCartItem);	# add the created item node to the list
		}
	return ($::SUCCESS, '', $pXmlCartItems);
	}

################################################################
#
# Cart->SaveXmlFile() - Save the cart to external Xml file
#
# Output:	0 - status
#				1 - error message
#
################################################################

sub SaveXmlFile
	{
	my  $Self 		= shift;
	#
	# Initialization
	#
	my $pXml = new PXML();
	my $sFileName = $Self->GetExternalCartFileName();
	#
	# Composing the xml representation of the shopping cart
	#
	my $pXmlCartItems = $Self->ToXml();
	my $pXmlCart = new Element();
	$pXmlCart->SetTag($Cart::XML_CARTROOT);		# set the name of the root node
	$pXmlCart->SetAttributes({	'Version' => $Cart::CARTVERSION, # Set the version attribute
										'CatalogVersion' => $$::g_pCatalogBlob{VERSIONFULL}}); # set the CatalogVersion attribute
	#
	# If we have a password hash, save it
	#
	if ($Self->{_PASSWORDHASH} ne '')
		{
		$pXmlCart->SetTextNode('Password', $Self->{_PASSWORDHASH}); # set the password hash
		}
	my $pXmlCartItem;
	foreach $pXmlCartItem (@{$pXmlCartItems})	# add product descriptions to the root	
		{
		$pXmlCart->AddChildNode($pXmlCartItem);
		}
	#
	# Saving the xml representation to the permanent cart file
	#
 	ACTINIC::ChangeAccess("rw", $sFileName);		# allow rw access on the file
	my @Response = $pXml->SaveXMLFile($sFileName, [$pXmlCart]); # save the xml cart object to the external file
	$::Session->{_NEWESTSAVEDCARTTIME} = time;	# remember the time the file was saved, needed for the cookie expiry
	ACTINIC::ChangeAccess("", $sFileName);			# restore file permission

	return @Response;
	}	
	
################################################################
#
# Cart->FromXml() - Restore cart items from an xml structure
#
# Input:		0 - 	a list of products
#				1 -	cart description reliability (optional):
#						$::TRUE 					- in case of loading session file
#						$::FALSE (default) 	- in case of loading saved cart file	
# Output:	0 - status
#				1 - message
#				2 - list of failures
#
################################################################

sub FromXml
	{
	my $Self 			= shift;
	my $pXmlCartItems = shift;							# reference to a list of products
	my $bReliableDescription = shift;	
	#
	# Initializations
	#
	my $sWarnings = "";	
	my ($Status, $Message, $pFailure);
	#
	# Process the items in the stored cart
	# and merge them to the current cart
	#
	my $pXmlCartItem;
	foreach $pXmlCartItem (@{$pXmlCartItems})
		{
		if ($pXmlCartItem->GetTag() eq 'Password')
			{
			next;
			}
		my $pCartItem = {};
		#
		# Retrieve the product reference
		#
		if (!$bReliableDescription &&
			 !$pXmlCartItem->GetAttribute('Reference')) 	# the Reference attribute is not specified
			{
			$sWarnings .= ACTINIC::GetPhrase(-1, 2153) . "<P>\n";
			ACTINIC::LogData("Attribute 'Reference' is not defined\n", $::DC_CART_RESTORE); 
			next;
			}
		else															# the Reference attribute is specified
			{
			$pCartItem->{'PRODUCT_REFERENCE'} = $pXmlCartItem->GetAttribute('Reference');
			}
		#
		# Check the section ID
		# 
		if ($bReliableDescription ||
			 $pXmlCartItem->GetAttribute('SID'))
			{
			$pCartItem->{'SID'} = $pXmlCartItem->GetAttribute('SID');
			}
		else	
			{
			#
			# Look up the section ID associated with the product
			#
			my $nSID;
			($Status, $nSID) = ACTINIC::LookUpSectionID($Self->{_PATH}, $pCartItem->{'PRODUCT_REFERENCE'});
			if ($Status != $::SUCCESS)					# Lookup failed?
				{												# provide appropriate message
				$sWarnings .= ACTINIC::GetPhrase(-1, 2154, '#' . $pCartItem->{'PRODUCT_REFERENCE'}) . "<P>\n";
				ACTINIC::LogData("Section ID lookup failed for $pCartItem->{'PRODUCT_REFERENCE'}\n", $::DC_CART_RESTORE);				
				next;											# and skip the product
				}
			$pCartItem->{'SID'} = $nSID;
			}
		#
		# Retrieve the product object
		#
		my $pProduct;
		($Status, $Message, $pProduct) = GetProduct($pCartItem->{'PRODUCT_REFERENCE'}, $pCartItem->{'SID'});
		if ($Status == $::FAILURE)
			{
			return ($Status, $Message, []);
			}
		elsif ($Status == $::NOTFOUND)						# product lookup problem?
			{
			$sWarnings .= ACTINIC::GetPhrase(-1, 2154, '#' . $pCartItem->{'PRODUCT_REFERENCE'}) . "<P>\n";
			ACTINIC::LogData("Product can't be located by product reference:$pCartItem->{'PRODUCT_REFERENCE'}\n", $::DC_CART_RESTORE);
			next;												# skip product;
			}
		#
		# Check that the product still can be ordered online
		#
		if (exists $pProduct->{'NO_ORDER'})			# if the product can't be ordered online
			{
			ACTINIC::LogData("Product ($pCartItem->{'PRODUCT_REFERENCE'}) can't be ordered online.\n", $::DC_CART_RESTORE);
			next;												# no warning, just skip the product
			}
		#
		# Check that the product still visible on the site (Hide on Web Site is set to false)
		# Note: this check is only done if the cart content is reliable. This is because 
		# we are maintanining the old v3 feature which uses hidden products instead of components
		# 
		if (!$bReliableDescription && exists $pProduct->{'HIDE'})		# if the product is hidden on the web site
			{
			ACTINIC::LogData("Product ($pCartItem->{'PRODUCT_REFERENCE'}) is hidden.\n", $::DC_CART_RESTORE);
			next;												# no warning, just skip the product
			}
		#
		# Check that the product still visible for the user's price schedule
		#
		if (!($Self->{_ISCALLBACK}))						# if no callback, because in this case there is not enough information about the customer
			{
			if (!ACTINIC::IsProductVisible($pCartItem->{'PRODUCT_REFERENCE'})) # if the product no longer visible for the user's price schedule
				{
				ACTINIC::LogData("Product ($pCartItem->{'PRODUCT_REFERENCE'})is not visible for price schedule.\n", $::DC_CART_RESTORE);
				next;												# no warning, just skip the product
				}
			}
		#
		# Check the product equivalence by name
		#
		my $sProductName = $pXmlCartItem->GetAttribute('Name');
		if (	$sProductName	&&									# if the product name is specified
				$pProduct->{'NAME'} ne $sProductName &&	# and the specified name not equals to the current name
				$$::g_pSetupBlob{'PROD_REF_COUNT'} == 0)	# and the product reference is auto generated
			{
			#
			# Ignore product
			#
			$sWarnings .= ACTINIC::GetPhrase(-1, 2154, $sProductName) . "<P>\n";
			ACTINIC::LogData("Specified product name '$sProductName' doesn't equals to product name '$pProduct->{NAME}'\n", $::DC_CART_RESTORE);
			next;
			}
		#
		# Process the quantity child node
		#
		my $pXmlQuantity = $pXmlCartItem->GetChildNode('Quantity');
		#
		# Retrieve the quantity value
		#
		if (!$bReliableDescription &&
			 !$pXmlQuantity)								# the quantity node not found
			{
			#
			# involve the product in the cart with 0 quantity 
			#
			$pCartItem->{'QUANTITY'} = 0;			
			$sWarnings .= ACTINIC::GetPhrase(-1, 2155, $pProduct->{'NAME'}) . "<P>\n"; # nevertheless, throw a warning
			ACTINIC::LogData("Required XML node 'Quantity' not found.\n", $::DC_CART_RESTORE);
			}
		else													# the quantity node exists
			{
			if (!$bReliableDescription &&
				 $pXmlQuantity->GetAttribute('Value'))	# if quantity is provided as an attribute value
				{
				$pCartItem->{'QUANTITY'} = $pXmlQuantity->GetAttribute('Value');
				}
			else													# if quantity is provided as text node value
				{
				$pCartItem->{'QUANTITY'} = $pXmlQuantity->GetNodeValue();
				}
			}
		#
		# Checking the quantity against the min. max. quantity
		# will be done by the ActinicOrder::ValidateOrderDetails() function
		#
		#
		# Process the QDQualify child node
		#
		my $pXmlQDQualify = $pXmlCartItem->GetChildNode('QDQualify');
		#
		# Retrieve the QDQualify value
		#
		if ($pXmlQDQualify)								# the QDQualify node found
			{
			$pCartItem->{'QDQUALIFY'} = $pXmlQDQualify->GetNodeValue();
			}
		#
		# Process the Info child node
		#
		if ($bReliableDescription)
			{
			if ($pXmlCartItem->GetChildNode('Info'))	# if Info node exists
				{
				$pCartItem->{'INFOINPUT'} = $pXmlCartItem->GetChildNode('Info')->GetNodeValue();
				}
			}
		else
			{
			if ($pProduct->{'OTHER_INFO_PROMPT'})		# Info node should be specified
				{
				my $sInfoInput;
				if ($pXmlCartItem->GetChildNode('Info'))	# if Info node exists
					{
					my $pXmlInfo = $pXmlCartItem->GetChildNode('Info');
					$sInfoInput = $pXmlInfo->GetNodeValue();
					}
				else
					{
					#
					# Give default info
					#
					$sInfoInput = '';
					#
					# Warning will be displayed by the ActinicOrder::ValidateOrderDetails() function
					#
					}
				$pCartItem->{'INFOINPUT'} = $sInfoInput;
				}
			}
		#
		# Process the Date child node
		#
		if ($bReliableDescription)
			{
			if ($pXmlCartItem->GetChildNode('Date'))	# if Date node exists
				{
				my ($sDay, $sMonth, $sYear);
				my $pXmlDateNode = $pXmlCartItem->GetChildNode('Date');
				$sDay = $pXmlDateNode->GetAttribute('Day');		# retrieve day 
				$sMonth = $pXmlDateNode->GetAttribute('Month');	# retrieve month
				$sYear = $pXmlDateNode->GetAttribute('Year');	# retrieve year
				#
				# Compose the date prompt
				#
				$pCartItem->{'DATE'} = $sYear . "/" . $sMonth . "/" . $sDay;
				}
			}
		else
			{
			if ($pProduct->{'DATE_PROMPT'})				# Date node should exist
				{
				my ($sDay, $sMonth, $sYear);
				if ($pXmlCartItem->GetChildNode('Date'))	# if Date node exists
					{
					my $pXmlDateNode = $pXmlCartItem->GetChildNode('Date');
					$sDay = $pXmlDateNode->GetAttribute('Day');		# retrieve day 
					$sMonth = $pXmlDateNode->GetAttribute('Month');	# retrieve month
					$sYear = $pXmlDateNode->GetAttribute('Year');	# retrieve year
					#
					# Store the specified date
					#
					if (!$sDay										# if one of the required attributes (day, month, year) is not defined
						 || !$sMonth								
						 || !$sYear)								
						{
						$sWarnings .= ACTINIC::GetPhrase(-1, 2155, $pProduct->{'NAME'}) . "<P>\n";
						ACTINIC::LogData("Malformed xml node 'Date'.\n", $::DC_CART_RESTORE);
						next;
						}
					}
				else													
					{
					$sWarnings .= ACTINIC::GetPhrase(-1, 2158, $pProduct->{'NAME'}) . "<P>\n";
					ACTINIC::LogData("Required node 'Date' not found.\n", $::DC_CART_RESTORE);
					#
					# Determine default date
					#
					my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime(time);	# platform independent time
					$sDay = $mday;
					$sMonth = $mon++;							# make month 1 based
					$sYear = $year + 1900;					# make year AD based
					}
				#
				# Compose the date prompt
				#
				$pCartItem->{'DATE'} = $sYear . "/" . $sMonth . "/" . $sDay;
				}
			}
		#
		# Process the Component and Attribute child nodes
		#
		my ($pXmlComponents, $pComponents, $pAttributes);
		$pXmlComponents = $pXmlCartItem->GetChildNodes("Component");		# components defined in the xml
		if (!$bReliableDescription)		
			{
			my $pComponentHash = ActinicOrder::GetComponents($pProduct);	# components defined in the product BLOB
			$pComponents = $pComponentHash->{COMPONENTS};
			$pAttributes = $pComponentHash->{ATTRIBUTES};
			}
		my $pXmlComponent;
		foreach $pXmlComponent (@{$pXmlComponents})
			{
			my $pComponent;
			if ($bReliableDescription)
				{
				my $nIndex = $pXmlComponent->GetAttribute("Index");
				$pCartItem->{sprintf("COMPONENT_%d", $nIndex)} = "on";
				}
			else
				{
				my $sComponentName = $pXmlComponent->GetAttribute("Name");
				if (!$sComponentName)
					{
					$sWarnings .= ACTINIC::GetPhrase(-1, 2158, $pProduct->{'NAME'}) . "<P>\n";
					ACTINIC::LogData("Required XML attribute 'Name' not found .\n", $::DC_CART_RESTORE);
					next;
					}
				#
				# Look for the component definition
				#				
				$pComponent = $pComponents->{$sComponentName};
				if (!$pComponent)
					{
					$sWarnings .= ACTINIC::GetPhrase(-1, 2155, $pProduct->{'NAME'}) . "<P>\n";
					ACTINIC::LogData("Component '$sComponentName' not found for product '$pProduct->{NAME}'.\n", $::DC_CART_RESTORE);
					next;										# next component in the xml definition
					}
				#
				# Store the component option
				#
				$pCartItem->{sprintf("COMPONENT_%d", $pComponent->{INDEX})} = "on";					
				}
			#
			# Process the component's attributes
			#			
			my $pXmlAttributes = $pXmlComponent->GetChildNodes("Attribute");
			my $pComponentAttributes;
			if (!$bReliableDescription)
				{
				$pComponentAttributes = $pComponent->{ATTRIBUTES};
				}
			($Status, $Message) = ProcessAttributes($pCartItem, $pXmlAttributes, $pProduct, $pComponentAttributes, $bReliableDescription);
			if ($Status != $::SUCCESS)
				{
				$sWarnings .= $Message;
				}
			}
		#
		# Process Attributes
		#
		my $pXmlAttributes = $pXmlCartItem->GetChildNodes("Attribute");
		if (	@{$pXmlComponents} > 0 &&				# if COMPONENT and ATTRIBUTE tags are present at the same time
				@{$pXmlAttributes} > 0)
			{			
			$sWarnings .= ACTINIC::GetPhrase(-1, 2155, $pProduct->{'NAME'}) . "<P>\n";
			ACTINIC::LogData("XML definition of product '$pProduct->{'NAME'} contains both COMPONENT and ATTRIBUTE tags.\n", $::DC_CART_RESTORE);
			}
		else													# if there were no COMPONENT tags, then process the ATTRIBUTEs
			{
			($Status, $Message) = ProcessAttributes($pCartItem, $pXmlAttributes, $pProduct, $pAttributes, $bReliableDescription);
			if ($Status != $::SUCCESS)
				{
				$sWarnings .= $Message;
				}
			}
		#
		# Correct missing component or attribute descriptions of the saved cart file
		#
		if (!$bReliableDescription)
			{
			FillComponentInfoGaps($pCartItem, $pComponents, $pAttributes);
			}
		#
		# Check whether a similar item is already in the cart
		#
		if (!$bReliableDescription)
			{
			my @aFoundIndices = $Self->FindSimilarCartItems($pCartItem);
			if (scalar(@aFoundIndices) != 0)			# there is no similar item in the cart
				{
				#
				# Forget the read item
				#
				next;
				}
			}
		#
		# Check that the restored component is correct
		#
		my $VariantList = ActinicOrder::GetCartVariantList($pCartItem);
		my $pComp;
		my $bValidationFailed = $::FALSE;
		
		foreach $pComp (@{$pProduct->{COMPONENTS}})								# For all components in the product
			{
			my @Response = ActinicOrder::FindComponent($pComp,$VariantList);	# Find what matches the selection
			my ($Status, %Component) = @Response;
			if ($Status != $::SUCCESS)													# This means a problem - 'not found' is SUCCESS here
				{
				$bValidationFailed = $::TRUE;
				}
			}
		#
		# Store the cart item if everything went well
		#
		if (!$bValidationFailed)
			{
			$Self->AddItem($pCartItem);			
			}
		}
	#
	# Validate the composed cart items
	#		
	my $pFailures = [];
	if (!$bReliableDescription)
		{
		my $nIndex = 0;
		my $pCartItem;
		foreach $pCartItem (@{$Self->{_CartList}})
			{
			($Status, $Message, $pFailure) = ActinicOrder::ValidateOrderDetails($pCartItem, $nIndex);
			if ($Status == $::FAILURE)
				{
				return ($::FAILURE, $sWarnings, $pFailures);
				}
			elsif ($Status == $::BADDATA)
				{
				$sWarnings .= $Message . "<P>\n";
				push @{$pFailures}, $pFailure;
				}
			else
				{
				push @{$pFailures}, {};				
				}
			$nIndex++;
			}
		}
	#
	# Determine whether failures occured during the processing or not
	#	
	if (length $sWarnings > 0)						# failure occured
		{
		return ($::BADDATA, $sWarnings, $pFailures);
		}
	else													# all right
		{
		return ($::SUCCESS, '', $pFailures);
		}
	}
	
################################################################
#
# Cart->ProcessAttributes() - process product attribute and component 
#			attribute definitions from the saved cart file 
#
# Input:		0 - 	reference to the cart (inner representation)
#				1 -	reference to the cart description (xml representation)
#				2 -	reference to the product object
#				3 -	reference to the attribute list of a product or a component (hash)
#				4 -	flag, which indicates whether the xml representation should be validated 
#
# Output:	0 - status
#				1 - message (warnings to be displayed)
#
################################################################

sub ProcessAttributes
	{
	my $pCartItem					= shift;		
	my $pXmlAttributes			= shift;
	my $pProduct					= shift; 
	my $pAttributes				= shift;
	my $bReliableDescription	= shift;
	#
	# Initialization
	#
	my $sWarnings = '';
	#
	# Process the attribute descriptions one-by-one
	#
	my $pXmlAttribute;
	foreach $pXmlAttribute (@{$pXmlAttributes})
		{
		if ($bReliableDescription)
			{
			#
			# Add the appropriate row to the inner representation
			#
			my $nIndex = $pXmlAttribute->GetAttribute("Index");	# we sure that these attributes exist
			my $sValue = $pXmlAttribute->GetAttribute("Value");
			$pCartItem->{sprintf("COMPONENT_%d", $nIndex)} = $sValue; 
			}
		else
			{
			#
			# Add the appropriate row to the inner representation
			# by determining and validating the attribute beforehand
			#
			my $sAttributeName = $pXmlAttribute->GetAttribute("Name");
			my $sAttributeChoice = $pXmlAttribute->GetAttribute("Choice");
			my $nAttributeValue = $pXmlAttribute->GetAttribute("Value");
			#
			# Check the existence of the xml attributes
			#
			if (!$sAttributeName)
				{
				$sWarnings .= ACTINIC::GetPhrase(-1, 2155, $pProduct->{'NAME'}) . "<P>\n";
				ACTINIC::LogData("Attribute 'Name' is missing from xml definition of product '$pProduct->{'NAME'}'.\n", $::DC_CART_RESTORE);
				next;
				}
			my $pAttribute = $pAttributes->{$sAttributeName};
			if (!$pAttribute)
				{
				$sWarnings .= ACTINIC::GetPhrase(-1, 2155, $pProduct->{'NAME'}) . "<P>\n";
				ACTINIC::LogData("Attribute '$sAttributeName' cannot be found.\n", $::DC_CART_RESTORE);
				next;
				}
			#
			# Look for the choice by name
			#
			my $i = 0;
			my $nChoiceIdx = -1;
			my $choice;
			foreach $choice (@{$pAttribute->{CHOICES}})
				{						
				if ($choice eq $sAttributeChoice)
					{
					$nChoiceIdx = $i;
					}
				$i++;
				}
			if ($nChoiceIdx == -1 &&					# if choice wasn't found by name
				 0 <= $nAttributeValue &&				# and the specified index is correct
				 $nAttributeValue < @{$pAttribute->{CHOICES}})
				{
				$nChoiceIdx = $nAttributeValue;		# use the specified index
				}
			#
			# Compose the entry by the determined data
			#
			if ($nChoiceIdx > -1)
				{
				$pCartItem->{sprintf("COMPONENT_%d", $pAttribute->{INDEX})} = $nChoiceIdx + 1;
				}						
			}				
		}

		return ($sWarnings ? $::BADDATA : $::SUCCESS, $sWarnings);
	}
	
################################################################
#
# Cart->FillComponentInfoGaps() -	revise the restored cart and completes 
#												the missing attribute and component descriptions
#												in the inner cart representation
#	An attribute should be present in the cart representation if
#	- it is a product attribute 
#	- it is an attribute of a component specified in the cart
#	A component should be present in the cart representation if
#	- it is not optional
#	
#	The function operates recursively to process component attributes.
#
# Input:		0 - 	reference to the cart (inner representation)
#				1 -	reference to a hash of components 
#				2 -	reference to a hash of attributes
#
# Output:	0 - status
#				1 - message (warnings to be displayed)
#
################################################################

sub FillComponentInfoGaps
	{
	my $pCartItem	= shift;
	my $pComponents = shift;
	my $pAttributes = shift;
	
	#
	# loop the components in the specified hash
	#
	my $pComponent;
	foreach $pComponent (values %{$pComponents})
		{
		#
		# Add the component the product representation
		# if it is not optional and not specified yet
		# 
		if (!$pComponent->{IS_OPTIONAL} &&
			 !$pCartItem->{sprintf("COMPONENT_%d", $pComponent->{INDEX})})
			{
			$pCartItem->{sprintf("COMPONENT_%d", $pComponent->{INDEX})} = "on";
			}
		#
		# Process the added components' attributes
		# 
		if ($pCartItem->{sprintf("COMPONENT_%d", $pComponent->{INDEX})})
			{
			FillComponentInfoGaps($pCartItem, {}, $pComponent->{ATTRIBUTES});
			}
		}		
	#
	# loop the attributes in the specified hash
	#
	my $pAttribute;
	foreach $pAttribute (values %{$pAttributes})
		{
		#
		# Add the attribute the product representation
		# if it is not specified yet
		# 
		if (!$pCartItem->{sprintf("COMPONENT_%d", $pAttribute->{INDEX})})
			{
			$pCartItem->{sprintf("COMPONENT_%d", $pAttribute->{INDEX})} = 1; # setting default value				
			}
		}
	}
	
################################################################
#
# Cart->RestoreXmlFile() - Restore cart from external Xml file
#
# Output:	0 - status
#				1 - error message
#				2 - list of failures
#
################################################################

sub RestoreXmlFile
	{
	my  $Self 		= shift;
	#
	# Initialization
	#
	my $pXml = new PXML();
	my $sFileName = $Self->GetExternalCartFileName();	
	#
	# Check the existence of the external cart file
	#
	if (!$Self->IsExternalCartFileExist())
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 2152) . "<P>\n");
		}
	#
	# Loading the xml cart file
	#
 	ACTINIC::ChangeAccess("r", $sFileName);		# allow r access on the file							
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
	# Check the version number of the xml root
	#
	#
	# ToDo: version checking - will be implemented after the first version step
	#
	#
	# Process the Product nodes of the xml root
	#
	my $pXmlCartItems = $pXmlCart->GetChildNodes('Product');
	if (!$pXmlCartItems ||								# if the root doesn't contain children
		 @{$pXmlCartItems} == 0)						# or there is no Product definition among the children
		{
		return ($::BADDATA, ACTINIC::GetPhrase(-1, 2159) . "<P>\n");
		}
	else														
		{
		#
		# Ideally we should use utime to update the file date but this is not supported in 5.004 or on Windows
		#
		@Response = $pXml->SaveXMLFile($sFileName, [$pXmlCart]); # save the xml cart object to the external file
		$::Session->{_NEWESTSAVEDCARTTIME} = time;
		#
		# Return the cart list
		#
		return $Self->FromXml($pXmlCartItems, $::FALSE);		# process the Product nodes
		}
	}		

################################################################
#
# Cart->AddProductAdjustment - add a product adjustment
#
# Input:	$Self								- cart object
#			$nIndex							- index into the cart product list
#			$sProductRef					- product reference
#			$sDescription					- description of the adjustment
#			$nAmount							- amount of the adjustment
#			$nAdjustmentTaxTreatment	- how tax is handled
#			$sTaxProductRef				- tax product reference
#			$bTreatCustomTaxAsExempt	- whether custom tax should be treated as exempt
#
# Author: Mike Purnell
#
################################################################

sub AddProductAdjustment 
	{
	my ($Self, $nIndex, $sProductRef, $sDescription, $nAmount, 
		$nAdjustmentTaxTreatment, $sTaxProductRef, $bTreatCustomTaxAsExempt, $sCoupon, $nID, $nReward) = @_;
	
	if(!defined $Self->{_PRODUCTADJUSTMENTS}->{$nIndex})				# if this is the first adjustment
		{
		$Self->{_PRODUCTADJUSTMENTS}->{$nIndex} = ();			# set an empty array
		}

	my @arrAdjust = ($sProductRef, $sDescription, $nAmount, $nAdjustmentTaxTreatment, $::eOrderLineProductAdjust);
	#
	# Save the tax product reference
	#
	$arrAdjust[$::eAdjIdxTaxProductRef] = $sTaxProductRef;
	#
	# Save whether we treat custom tax as exempt
	#
	$arrAdjust[$::eAdjIdxCustomTaxAsExempt] = $bTreatCustomTaxAsExempt;
	#
	# Coupon code
	#
	$arrAdjust[$::eAdjIdxCouponCode] = $sCoupon;
	#
	# Discount ID
	#
	$arrAdjust[$::eAdjIdxDiscountID] = $nID;
	#
	# Cart index
	#
	$arrAdjust[$::eAdjIdxCartIndex] = $nIndex;
	#
	# Reward
	#
	$arrAdjust[$::eAdjIdxRewardType] = $nReward;
	
	push @{$Self->{_PRODUCTADJUSTMENTS}->{$nIndex}} , \@arrAdjust;	# add to list of adjustments 
	$Self->{_ADJUSTMENTSCOUNT}++;						# increment adjustment count
	}

################################################################
#
# Cart->AddOrderAdjustment - add an order adjustment
#
# Input:	$Self								- cart object
#			$sDescription					- description of the adjustment
#			$nAmount							- amount of the adjustment
#			$nAdjustmentTaxTreatment	- how tax is handled
#			$sTaxProductRef				- tax product reference
#
# Author: Mike Purnell
#
################################################################

sub AddOrderAdjustment 
	{
	my ($Self, $sDescription, $nAmount, $nAdjustmentTaxTreatment, $sTaxProductRef, $nBasis, $sCoupon) = @_;

	my @arrAdjust = (':::::', $sDescription, $nAmount, $nAdjustmentTaxTreatment, $::eOrderLineOrderAdjust);
	#
	# Save the tax product reference
	#
	$arrAdjust[$::eAdjIdxTaxProductRef] = $sTaxProductRef;
	#
	# Never treat custom tax as exempt
	#
	$arrAdjust[$::eAdjIdxCustomTaxAsExempt] = $::FALSE;
	#
	# Adjustment calculation basis
	#
	$arrAdjust[$::eAdjIdxAdjustmentBasis] = $nBasis;
	#
	# Coupon code
	#
	$arrAdjust[$::eAdjIdxCouponCode] = $sCoupon;
	
	push @{$Self->{_ORDERADJUSTMENTS}} , \@arrAdjust;	# add to list of adjustments 
	$Self->{_ADJUSTMENTSCOUNT}++;						# increment adjustment count
	}

################################################################
#
# Cart->AddFinalAdjustment - add a final order adjustment
#
# Input:	$Self								- cart object
#			$sDescription					- description of the adjustment
#			$nAmount							- amount of the adjustment
#			$nAdjustmentTaxTreatment	- how tax is handled
#			$sTaxProductRef				- tax product reference
#
# Author: Mike Purnell
#
################################################################

sub AddFinalAdjustment 
	{
	my ($Self, $sDescription, $nAmount, $nAdjustmentTaxTreatment, $sTaxProductRef, $nBasis) = @_;

	my @arrAdjust = (':::::', $sDescription, $nAmount, $nAdjustmentTaxTreatment, $::eOrderLineOrderAdjust);
	#
	# Save the tax product reference
	#
	$arrAdjust[$::eAdjIdxTaxProductRef] = $sTaxProductRef;
	#
	# Never treat custom tax as exempt
	#
	$arrAdjust[$::eAdjIdxCustomTaxAsExempt] = $::FALSE;
	#
	# Adjustment calculation basis
	#
	$arrAdjust[$::eAdjIdxAdjustmentBasis] = $nBasis;	
	
	push @{$Self->{_FINALORDERADJUSTMENTS}} , \@arrAdjust;	# add to list of adjustments 
	$Self->{_ADJUSTMENTSCOUNT}++;						# increment adjustment count
	}

################################################################
#
# Cart->GetProductAdjustments - add a product adjustment
#
# Input:	$Self		- cart object
#			$nIndex	- index into the cart product list
#
# Author: Mike Purnell
#
################################################################

sub GetProductAdjustments 
	{
	my ($Self, $nIndex) = @_;
#?	ACTINIC::ASSERT($Self->{_PRODUCTADJUSTMENTSPROCESSED}, 'ProcessProductAdjustments must be called first.');

	if(defined $Self->{_PRODUCTADJUSTMENTS}->{$nIndex})	# if we have any adjustments for this order line
		{
		return(\@{$Self->{_PRODUCTADJUSTMENTS}->{$nIndex}});	# return them
		}
	return(());								# return empty array
	}

################################################################
#
# Cart->GetConsolidatedProductAdjustments - consolidate product 
#			adjustments and return their list (used for displaying
#			only)
#
# Input:	$Self		- cart object
#			$nIndex	- index into the cart product list
#
# Author: Zoltan Magyar
#
################################################################

sub GetConsolidatedProductAdjustments 
	{
	my ($Self, $nIndex) = @_;
#?	ACTINIC::ASSERT($Self->{_PRODUCTADJUSTMENTSPROCESSED}, 'ProcessProductAdjustments must be called first.');	
	#
	# Check if we are in discount debug mode
	#
	if (defined $::DISPLAY_INDIVIDUAL_ADJUSTMENT_LINES)	# if so
		{														# then do not consolidate the adjustment lines
		return($Self->GetProductAdjustments($nIndex));
		}
	#
	# If we have been before the do not consolidate the lines again
	#
	if (defined $Self->{_CONSOLIDATION_DONE})
		{
		if (defined $Self->{_CONSOLIDATEDADJUSTMENTS}->{$nIndex})	# if we have any adjustments for this order line
			{
			return(\@{$Self->{_CONSOLIDATEDADJUSTMENTS}->{$nIndex}});	# return them
			}
		else
			{
			return(());
			}
		}
	#
	# Consolidate the lines if requested for displaying
	#
	my $pValues;
	my %mapIDToItem;
	#
	# Get a list of all items first.
	#
	foreach $pValues (values %{$Self->{_PRODUCTADJUSTMENTS}})
		{
		my $pItem;
		foreach $pItem (@{$pValues})
			{
			#
			# We need a copy of the amount and the description only
			#
			my @Temp;
			$Temp[$::eAdjIdxAmount] = $$pItem[$::eAdjIdxAmount];
			$Temp[$::eAdjIdxProductDescription] = $$pItem[$::eAdjIdxProductDescription];
			#
			# Now see if we have this already
			#
			if (!$mapIDToItem{$$pItem[$::eAdjIdxDiscountID]} || # we havent processed this ID so far, OR
				(($$pItem[$::eAdjIdxRewardType] == $::eRewardMoneyOff) 						&& !$$::g_pDiscountBlob{'CONSOLIDATE_MONEY_OFF'}) ||
				(($$pItem[$::eAdjIdxRewardType] == $::eRewardPercentageOff) 				&& !$$::g_pDiscountBlob{'CONSOLIDATE_PERCENTAGE_OFF'}) ||
				(($$pItem[$::eAdjIdxRewardType] == $::eRewardPercentageOffCheapest) 		&& !$$::g_pDiscountBlob{'CONSOLIDATE_PERCENTAGE_OFF_CHEAPEST'}) ||
				(($$pItem[$::eAdjIdxRewardType] == $::eRewardMoneyOffExtraProduct) 		&& !$$::g_pDiscountBlob{'CONSOLIDATE_MONEY_OFF_EXTRA'}) ||
				(($$pItem[$::eAdjIdxRewardType] == $::eRewardPercentageOffExtraProduct) && !$$::g_pDiscountBlob{'CONSOLIDATE_PERCENTAGE_OFF_EXTRA'}) ||
				(($$pItem[$::eAdjIdxRewardType] == $::eRewardFixedPrice) 					&& !$$::g_pDiscountBlob{'CONSOLIDATE_FIXED_PRICE'}))
				{	
				$mapIDToItem{$$pItem[$::eAdjIdxDiscountID]} = \@Temp;
				push @{$Self->{_CONSOLIDATEDADJUSTMENTS}->{$$pItem[$::eAdjIdxCartIndex]}}, \@Temp;
				}
			else
				{
				$mapIDToItem{$$pItem[$::eAdjIdxDiscountID]}->[$::eAdjIdxAmount] += $Temp[$::eAdjIdxAmount];
				}
			}
		}
	#
	# Now make sure it is not done angain and return the value for this line
	#
	$Self->{_CONSOLIDATION_DONE} = $::TRUE;
	
	if (defined $Self->{_CONSOLIDATEDADJUSTMENTS}->{$nIndex})	# if we have any adjustments for this order line
		{
		return(\@{$Self->{_CONSOLIDATEDADJUSTMENTS}->{$nIndex}});	# return them
		}
	else
		{
		return(());
		}
	}
	
################################################################
#
# Cart->GetOrderAdjustments - add an order adjustment
#
# Input:	$Self	- cart object
#
# Author: Mike Purnell
#
################################################################

sub GetOrderAdjustments 
	{
	my ($Self) = @_;
#?	ACTINIC::ASSERT($Self->{_ORDERADJUSTMENTSPROCESSED}, 'ProcessOrderAdjustments must be called first.');
	return(\@{$Self->{_ORDERADJUSTMENTS}});
	}

################################################################
#
# Cart->GetFinalAdjustments - add an order adjustment
#
# Input:	$Self	- cart object
#
# Author: Mike Purnell
#
################################################################

sub GetFinalAdjustments 
	{
	my ($Self) = @_;
#?	ACTINIC::ASSERT($Self->{_FINALORDERADJUSTMENTSPROCESSED}, 'ProcessFinalAdjustments must be called first.');
	return(\@{$Self->{_FINALORDERADJUSTMENTS}});
	}

################################################################
#
# Cart->GetAdjustmentCount - get the number of order adjustments
#
# Input:	$Self	- cart object
#
# Returns:	$nCount	- number of adjustments
#
# Author: Mike Purnell
#
################################################################

sub GetAdjustmentCount 
	{
	my ($Self) = @_;
	return($Self->{_ADJUSTMENTSCOUNT});
	}

################################################################
#
# Cart->ProcessProductAdjustments - process the product adjustments
#
# Input:	$Self	- cart object
#
# Author: Mike Purnell
#
################################################################

sub ProcessProductAdjustments 
	{
	my ($Self) = @_;
	#
	# Only execute this code once
	#
	if($Self->{_PRODUCTADJUSTMENTSPROCESSED})
		{
		return($::SUCCESS, '');
		}
	$Self->{_PRODUCTADJUSTMENTSPROCESSED} = $::TRUE;
	my ($nReturn, $sError);
	#
	# Read discount setup
	#
	my ($Status, $Message) = ACTINIC::ReadDiscountBlob($Self->{_PATH}); 
	if ($Status != $::SUCCESS)							# on error, bail
		{
		return ($Status, $Message);
		}	

	my $nCartIndex = 0;
	my $pitemCart;
	my %hashGroupQuantities;
	my %hashGroupPrices;
	#
	# Prepare cart content for discount calculation
	#
	my %hashGroupToData;
	foreach $pitemCart (@{$Self->{_CartList}})
		{
		#
		# Get the product details
		#
		my $pProduct;
		($nReturn, $sError, $pProduct) = GetProduct($pitemCart->{'PRODUCT_REFERENCE'}, $pitemCart->{'SID'});
		if($nReturn == $::FAILURE)
			{
			return($nReturn, $sError);
			}
		#
		# Get line's pricing details
		#
		my @Prices = $Self->GetCartItemPrice($pitemCart);
		if ($Prices[0] != $::SUCCESS)
			{
			return($Prices[0], $Prices[1]);
			}
		my @ItemDetails = @Prices[2..9];				# add pricing info
		unshift @ItemDetails, $nCartIndex, $pitemCart->{'QUANTITY'};
		push @ItemDetails, 0;							# add the used quantity
		push @ItemDetails, 0;							# add the used value
		push @ItemDetails, $pitemCart->{'PRODUCT_REFERENCE'};
		push @{$hashGroupToData{$$pProduct{'PRODUCT_GROUP'}}}, \@ItemDetails;
		#
		# Prepare our data structure
		#
		$nCartIndex++;
		}			
	#
	# Now calculate discounts
	#
	my ($parrAdjustments, $parrAdjustment);
	($nReturn, $sError, $parrAdjustments) = ActinicDiscounts::CalculateProductAdjustment(\%hashGroupToData);
	#
	# Save the adjustments for this product
	#
	foreach $parrAdjustment (@$parrAdjustments)
		{
		$Self->AddProductAdjustment($parrAdjustment->[$::eAdjIdxCartIndex], 
			$parrAdjustment->[$::eAdjIdxProductRef], 
			$parrAdjustment->[$::eAdjIdxProductDescription], 
			$parrAdjustment->[$::eAdjIdxAmount], 
			$parrAdjustment->[$::eAdjIdxTaxTreatment],
			"", #$parrAdjustment->[$::eAdjIdxProductRef], 
			$::FALSE,
			$parrAdjustment->[$::eAdjIdxCouponCode],
			$parrAdjustment->[$::eAdjIdxDiscountID],
			$parrAdjustment->[$::eAdjIdxRewardType]);
		}

	return($::SUCCESS, '');
	}

################################################################
#
# Cart->ProcessOrderAdjustments - process the order adjustments
#
# Input:	$Self					- cart object
#			$parrOrderTotals	- ref to array of order totals
#
# Author: Mike Purnell
#
################################################################

sub ProcessOrderAdjustments 
	{
	my ($Self, $parrOrderTotals) = @_;
#?	ACTINIC::ASSERT($Self->{_PRODUCTADJUSTMENTSPROCESSED}, 'ProcessProductAdjustments must be called first.');
	#
	# Only execute this code once
	#
	if($Self->{_ORDERADJUSTMENTSPROCESSED})
		{
		$Self->{_ORDERADJUSTMENTSPROCESSED} = $::TRUE;
		return($::SUCCESS, '', $Self->GetOrderAdjustments());
		}
	#
	# Clear order adjustments if being called a second time
	#
	$Self->ClearAdjustmentCache("_ORDERADJUSTMENTS");
	#
	# Calculate the adjustments for the order
	#
	my ($nReturn, $sError, $parrAdjustments, $parrAdjustment);
	($nReturn, $sError, $parrAdjustments) = 
		ActinicDiscounts::CalculateOrderAdjustment($parrOrderTotals);
	#
	# Save the adjustments for this product
	#
	foreach $parrAdjustment (@$parrAdjustments)
		{
		$Self->AddOrderAdjustment(@$parrAdjustment);
		}
	$Self->{_ORDERADJUSTMENTSPROCESSED} = $::TRUE;
	return($::SUCCESS, '', $Self->GetOrderAdjustments());
	}

################################################################
#
# Cart->ProcessFinalAdjustments - process the final order adjustments
#
# Input:	$Self					- cart object
#			$parrOrderTotals	- ref to array of order totals
#
# Author: Mike Purnell
#
################################################################

sub ProcessFinalAdjustments 
	{
	my ($Self, $parrOrderTotals) = @_;
#?	ACTINIC::ASSERT($Self->{_PRODUCTADJUSTMENTSPROCESSED}, 'ProcessProductAdjustments must be called first.');
	#
	# Only execute this code once
	#
	if($Self->{_FINALORDERADJUSTMENTSPROCESSED})
		{
		$Self->{_FINALORDERADJUSTMENTSPROCESSED} = $::TRUE;
		return($::SUCCESS, '', $Self->GetFinalAdjustments());
		}
	#
	# Clear final adjustments if being called a second time
	#
	$Self->ClearAdjustmentCache("_FINALORDERADJUSTMENTS");
	#
	# Calculate the adjustments for the order
	#
	my ($nReturn, $sError, $parrAdjustments, $parrAdjustment);
	($nReturn, $sError, $parrAdjustments) = 
		ActinicDiscounts::CalculateOrderAdjustment($parrOrderTotals);
	#
	# Save the adjustments for this product
	#
	foreach $parrAdjustment (@$parrAdjustments)
		{
		$Self->AddFinalAdjustment(@$parrAdjustment);
		}
	$Self->{_FINALORDERADJUSTMENTSPROCESSED} = $::TRUE;
	return($::SUCCESS, '', $Self->GetFinalAdjustments());
	}

################################################################
#
# Cart->ClearAdjustmentCache - empty the adjustment cache
#
# Input:	$Self					- cart object
#			$sAdjustLabel		- adjustment label
#
# Author: Gordon Camley
#
################################################################

sub ClearAdjustmentCache
		{
		my ($Self, $sAdjustLabel) = @_;
		if ($Self->{$sAdjustLabel . 'PROCESSED'})
			{
			$Self->{_ADJUSTMENTSCOUNT}	-= scalar @{$Self->{$sAdjustLabel}};	# decrement the adjustment counter
			$Self->{$sAdjustLabel} = ();					# empty the cache
			$Self->{$sAdjustLabel . 'PROCESSED'} = $::FALSE;	# flag as not done
			}
		return();
		}

#######################################################
#
# Cart->SummarizeOrder - summarize the order and return
#	the values.
#
# Input:	$Self							- pointer to the cart object
#			$bIgnoreAdvancedErrors	- optional - flag indicating
#											how to handle advanced shipping
#											errors.  if $::TRUE, ignore them.
#											Default - $::FALSE
#
# Returns:	0 - status
#				1 - error
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
#######################################################

sub SummarizeOrder
	{
	my ($Self, $bIgnoreAdvancedErrors) = @_;
	if (defined $Self->{_ORDERSUMMARY} &&			# if we've already summarized the order
	   !ActinicOrder::IsTaxInfoChanged())			# and no tax changes
		{
		return(@{$Self->{_ORDERSUMMARY}});			# return the result
		}
	#
	# Call the ActinicOrder function
	#
	my @Response = ActinicOrder::SummarizeOrder($Self->GetCartList(), $bIgnoreAdvancedErrors);
	$Self->{_ORDERSUMMARY} = \@Response;				# save the response
	#
	# If the call failed and CallShippingPlugin wasn't called, save the
	# response to SummarizeOrder as the _CALLSHIPPINGPLUGINRESPONSE response.
	#
	if($Response[0] != $::SUCCESS &&
		!defined $Self->{_CALLSHIPPINGPLUGINRESPONSE})
		{
		$Self->{_CALLSHIPPINGPLUGINRESPONSE} = \@Response;
		}
	return(@Response);									# return the response
	}

#######################################################
#
# Cart->GetCartItemPrice - get all pricing information 
#	of a selected line of the cart
#
# Input:	$Self				- pointer to the cart object
#			$pOrderDetail	- the order detail hash
#
# Returns:	0 - status
#				1 - error
#				2 - total price of the line
#				3 - price of one item of the line
#				4 - tax band 1
#				5 - tax band 2
#				6 - actual tax 1
#				7 - actual tax 2
#				8 - default tax 1
#				9 - default tax 2
#
# Author: Zoltan Magyar - Wednesday, November 26, 2003
#
#######################################################

sub GetCartItemPrice
	{
	my $Self 			= shift;
	my $pOrderDetail 	= shift;
	my @Response;
	my @DefaultTaxResponse;
	my ($nComponentsTax1, $nComponentsTax2, $nComponentsDefTax1, $nComponentsDefTax2);
	my ($nUComponentsTax1, $nUComponentsTax2, $nUComponentsDefTax1, $nUComponentsDefTax2);

	my $sDigest = $ACTINIC::B2B->Get('UserDigest');	# Get User ID once
	my $nScheduleID = ActinicOrder::GetScheduleID($sDigest);

	my %CurrentItem = %$pOrderDetail;				# get the item details
	my ($nStatus, $sMessage, $pProduct) = GetProduct($CurrentItem{"PRODUCT_REFERENCE"}, $CurrentItem{SID});	# get this product object
	if ($nStatus != $::SUCCESS)
		{
		return ($nStatus, $sMessage);
		}
	#
	# Calculate effective quantity taking into account identical items in the cart
	#
	my $nEffectiveQuantity = ActinicOrder::EffectiveCartQuantity($pOrderDetail,$Self->GetCartList(),\&ActinicOrder::IdenticalCartLines,undef);

	my $nPrice = ActinicOrder::CalculateSchPrice($pProduct, $nEffectiveQuantity, $sDigest);
	#
	# Get the product tax bands
	#
	@Response = ActinicOrder::GetProductTaxBands($pProduct);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my ($rarrCurTaxBands, $rarrDefTaxBands) = @Response[2, 3];
	my $nRetailProdPrice = $pProduct->{PRICE};

	my $nComponentPrice = 0;
	my $nAlreadyTaxed  = 0;
	#
	# Check if there are any variants
	#
	if( $pProduct->{COMPONENTS} &&
		 $pProduct->{PRICING_MODEL} != $ActinicOrder::PRICING_MODEL_STANDARD )
		{
		my $VariantList = ActinicOrder::GetCartVariantList(\%CurrentItem);
		my (%Component, $c);
		my $nIndex = 1;

		foreach $c (@{$pProduct->{COMPONENTS}})
			{
			($nStatus, %Component) = ActinicOrder::FindComponent($c, $VariantList);
			if ($nStatus != $::SUCCESS)
				{
				return ($nStatus, $Component{text});
				}
			if ($Component{quantity} > 0 )
				{
				my $sRef= $Component{code} && 
								($c->[$::CBIDX_ASSOCPRODPRICE] == 1 ||
								$Component{'AssociatedPrice'}) ? 
								$Component{code} : $CurrentItem{"PRODUCT_REFERENCE"} . "_" . $nIndex;
				#
				# Get the component price based on schedule and effective quantity and adjusted tax opaque data
				#
				@Response = GetComponentPriceAndTaxBands(\%Component, $sRef, $nEffectiveQuantity, $nRetailProdPrice, 
					$rarrCurTaxBands, $rarrDefTaxBands, $pProduct, $nScheduleID);
				if ($Response[0] != $::SUCCESS)
					{
					return (@Response);
					}
				my ($nItemPrice, $phashTaxBands, $rarrCurCompTaxBands, $rarrDefCompTaxBands) = @Response[2 .. 5];
					
				$nComponentPrice += $nItemPrice * $Component{quantity};		# summarize component prices
				
				if ($c->[$::CBIDX_SEPARATELINE])		# if the component is a separate line, calculate the tax
					{
					my $nTaxQuantity = $CurrentItem{"QUANTITY"} * $Component{quantity};
					@Response = ActinicOrder::CalculateTax($nItemPrice, $nTaxQuantity, 
						$rarrCurCompTaxBands, $rarrDefCompTaxBands, $nItemPrice);

					@DefaultTaxResponse = ActinicOrder::CalculateDefaultTax($nItemPrice, $nTaxQuantity, 
						$rarrCurCompTaxBands, $rarrDefCompTaxBands, $nItemPrice);
					if ($Response[0] != $::SUCCESS)
						{
						return (@Response);
						}
					$nComponentsTax1 += $Response[2];			# calculate the tax 1 composite total
					$nComponentsTax2 += $Response[3];			# calculate the tax 2 composite total
					$nComponentsDefTax1 += $DefaultTaxResponse[2];		# calculate the tax 1 composite total
					$nComponentsDefTax2 += $DefaultTaxResponse[3];		# calculate the tax 2 composite total
					#
					# Get un-rounded tax values
					#
					$nUComponentsTax1 += $Response[4];			# calculate the tax 1 composite total
					$nUComponentsTax2 += $Response[5];			# calculate the tax 2 composite total
					$nUComponentsDefTax1 += $DefaultTaxResponse[4];		# calculate the tax 1 composite total
					$nUComponentsDefTax2 += $DefaultTaxResponse[5];		# calculate the tax 2 composite total
					
					$nAlreadyTaxed += $nItemPrice * $Component{quantity};
					}
				}
			$nIndex++;
			}
		}
	my $nTaxBase = $nPrice;
	my $nPriceModel = $pProduct->{PRICING_MODEL};
	if( $nPriceModel == $ActinicOrder::PRICING_MODEL_PROD_COMP )
		{
		$nPrice += $nComponentPrice;
		$nTaxBase = $nPrice - $nAlreadyTaxed;		# tax already calculated as component
		}
	elsif( $nPriceModel == $ActinicOrder::PRICING_MODEL_COMP )
		{
		$nPrice = $nComponentPrice;
		$nTaxBase = $nPrice - $nAlreadyTaxed;		# tax already calculated as component
		}

	my $nLineTotal += $nPrice * $CurrentItem{"QUANTITY"};
	#
	# Calculate Tax
	#
	@Response = ActinicOrder::CalculateTax($nTaxBase, $CurrentItem{"QUANTITY"}, $rarrCurTaxBands, $rarrDefTaxBands, 
		$$pProduct{"PRICE"});
	@DefaultTaxResponse = ActinicOrder::CalculateDefaultTax($nTaxBase, $CurrentItem{"QUANTITY"}, $rarrCurTaxBands, $rarrDefTaxBands, $$pProduct{"PRICE"});
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my $nProductSubTotalTax1 = $Response[2] + $nComponentsTax1;
	my $nProductSubTotalTax2 = $Response[3] + $nComponentsTax2;	
	my $nProductSubTotalDefTax1 = $DefaultTaxResponse[2] + $nComponentsDefTax1;
	my $nProductSubTotalDefTax2 = $DefaultTaxResponse[3] + $nComponentsDefTax2;	
	#
	# Get un-rounded tax values
	#
	my $nUProductSubTotalTax1 = $Response[4] + $nUComponentsTax1;
	my $nUProductSubTotalTax2 = $Response[5] + $nUComponentsTax2;	
	my $nUProductSubTotalDefTax1 = $DefaultTaxResponse[4] + $nUComponentsDefTax1;
	my $nUProductSubTotalDefTax2 = $DefaultTaxResponse[5] + $nUComponentsDefTax2;	
	return ($::SUCCESS, "", $nLineTotal, $nPrice, $rarrCurTaxBands, $rarrDefTaxBands, 
		$nProductSubTotalTax1, $nProductSubTotalTax2, $nProductSubTotalDefTax1, $nProductSubTotalDefTax2, 
		$nUProductSubTotalTax1, $nUProductSubTotalTax2, $nUProductSubTotalDefTax1, $nUProductSubTotalDefTax2);
	}

#######################################################
#
# Cart->SetShippingPluginResponse - save the response
#			of ActincOrder::CallShippingPlugin
#
# Input:	$Self			- pointer to the cart object
#			$pResponse	- the response from CallShippingPlugin
#
# Author: Mike Purnell
#
#######################################################

sub SetShippingPluginResponse
	{
	my ($Self, $pResponse) = @_;
	#
	# Set the value
	#
	$Self->{_CALLSHIPPINGPLUGINRESPONSE} = $pResponse;
	}

#######################################################
#
# Cart->GetShippingPluginResponse - get the stored response
#			of ActincOrder::CallShippingPlugin
#
# Input:	$Self	- pointer to the cart object
#
# Output:	$0	- the response from CallShippingPlugin
#
# Author: Mike Purnell
#
#######################################################

sub GetShippingPluginResponse
	{
	my ($Self) = @_;
#?	ACTINIC::ASSERT($Self->{_CALLSHIPPINGPLUGINRESPONSE}, 'SetShippingPluginResponse must be called first.');
	#
	# Return the cached response
	#
	return(@{$Self->{_CALLSHIPPINGPLUGINRESPONSE}});
	}

##############################################################################################################
#
# Helper functions
#
##############################################################################################################		

################################################################
#
# GetProduct() - 	returns the product hash
#
# Input: 	0 - product reference (PRODUCT_REFERENCE)
#				1 - section blob ID (SID) - optional
#
# Output:	0 - status ($::SUCCESS, $::FAILURE, $::NOTFOUND)
#				1 - error message
#				2 - reference to the product hash
#
################################################################

sub GetProduct
	{
	my ($sProductReference, $sSID) = @_;
	my ($nStatus, $sMessage, $sSectionBlobName, $pProduct);
	if(@_ == 1)												# if no section ID supplied
		{
		($nStatus, $sSID) = ACTINIC::LookUpSectionID(ACTINIC::GetPath(), $sProductReference);	# look it up
		if($nStatus == $::FAILURE)
			{
			return ($nStatus, $sMessage, undef);
			}
		}
	#
	# Locate the section blob
	#
	($nStatus, $sMessage, $sSectionBlobName) = ACTINIC::GetSectionBlobName($sSID); # retrieve the blob name
	if ($nStatus == $::FAILURE)
		{
		return ($nStatus, $sMessage, undef);
		}
	#
	# locate this product's object.
	#
	($nStatus, $sMessage, $pProduct) = ACTINIC::GetProduct($sProductReference, $sSectionBlobName,
											  ACTINIC::GetPath());	# get this product object

	return ($nStatus, $sMessage, $pProduct);
	}	
	
################################################################
#
# AdjustCustomTax - adjust the tax opaque data if custom tax
#
# Input:	   $sTaxOpaqueData	- tax opaque data
#				$nOrigUnitPrice	- original unit price
#				$nNewUnitPrice		- new unit price
#
# Returns:  adjusted tax opaque data	
#
# Author: Mike Purnell
#
################################################################

sub AdjustCustomTax
	{
	my ($sTaxOpaqueData, $nOrigUnitPrice, $nNewUnitPrice) = @_;
	
	my ($nBandID, $nPercent, $nFlatRate, $sBandName) = split /=/, $sTaxOpaqueData;
	if ($nBandID == $ActinicOrder::CUSTOM && 
		$nOrigUnitPrice != $nNewUnitPrice)
		{
		if ($nOrigUnitPrice == 0)
			{
			return ('6=0=0=');
			}
		$nFlatRate = $nNewUnitPrice / $nOrigUnitPrice * $nFlatRate;
		$nFlatRate = ActinicOrder::RoundTax($nFlatRate, $ActinicOrder::SCIENTIFIC_NORMAL);
		#
		# Reformat the opaque data
		#
		return (sprintf("%d=%d=%d=", $nBandID, $nPercent, $nFlatRate));
		}
	return ($sTaxOpaqueData);
	}

################################################################
#
# GetComponentPriceAndTaxBands - adjust the tax opaque data if custom tax
#
# Input:	   $rhashComponent	- the component hash
#				$sRef					- product reference or internal component reference
#				$nQuantity			- product quantity
#				$nRetailProdPrice	- retail product price
#				$sProdTax1Band		- product tax 1 band
#				$sProdTax2Band		- product tax 2 band
#				$pProduct			- reference to the product hash
#				$nScheduleID		- price schedule ID
#
# Returns: (status code,		# $::SUCCESS or response from failure 
#				error message,		# '' or error message from failure 
#				$nDiscUnitPrice,	# item unit price based on qty and/or price schedule 
#				$sCompTax1Band,	# adjusted component tax 1 band 
#				$sCompTax2Band, 	# adjusted component tax 2 band 
#				$rhashTaxBands)	# hash containing the relevant product/component tax opaque data 	
#
# Author: Mike Purnell
#
################################################################

sub GetComponentPriceAndTaxBands
	{
	my ($rhashComponent, $sRef, $nQuantity, $nRetailProdPrice, 
		$rarrCurTaxBands, $rarrDefTaxBands, $pProduct, $nScheduleID) = @_;
	
	my $rhashTaxBands = $pProduct;
	#
	# Get component price based on quantity
	#
	my @Response = ActinicOrder::GetComponentPrice($rhashComponent->{price}, $nQuantity, 
		$rhashComponent->{quantity}, $nScheduleID, $sRef);
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	my $nDiscUnitPrice = $Response[2] / $rhashComponent->{quantity};	# store component price
	
	my $bUseAssocPrice = $rhashComponent->{'UseAssociatedPrice'};
	my $bUseAssocTax = $rhashComponent->{'AssociatedTax'};
	#
	# Get the associated product tax
	#		
	if ($bUseAssocTax)									# if we're using associated product tax
		{
		@Response = ActinicOrder::GetProductTaxBands($rhashComponent);
		($rarrCurTaxBands, $rarrDefTaxBands) = @Response[2, 3];
		$rhashTaxBands = $rhashComponent;			# use the associated product tax bands
		}
	my @arrCurTaxBands = @{$rarrCurTaxBands};
	my @arrDefTaxBands = @{$rarrDefTaxBands};
	#
	# Get the associated product price if we're using associated price or tax
	#		
	my $nAssocRetailProdPrice = undef;
	if ($bUseAssocPrice || $bUseAssocTax)
		{
		$nAssocRetailProdPrice = $rhashComponent->{'RetailPrice'};
		}
	#
	# Now we set the variables that will be used for adjusting the custom tax data
	#		
	my ($nOrigTaxPrice);		
	if ($bUseAssocPrice && $bUseAssocTax)			# if we're using associated product price and tax
		{
		$nOrigTaxPrice = $nAssocRetailProdPrice;
		}
	elsif ($bUseAssocPrice)								# if we're using associated product price and main product tax
		{
		$nOrigTaxPrice = $nRetailProdPrice;
		}
	elsif ($bUseAssocTax)								# if we're using associated product tax and component price
		{
		$nOrigTaxPrice = $nAssocRetailProdPrice;
		}
	else														# if we're using main product tax and component price
		{
		$nOrigTaxPrice = $nRetailProdPrice;
		}
	#
	# Now adjust the tax opaque data for both taxes
	#
	my $rarrTemp;
	foreach $rarrTemp ((\@arrCurTaxBands, \@arrDefTaxBands))
		{
		my $nTaxIndex;
		foreach $nTaxIndex (0 .. 1)
			{
			$rarrTemp->[$nTaxIndex] = 
				AdjustCustomTax($rarrTemp->[$nTaxIndex], $nOrigTaxPrice, $nDiscUnitPrice); 
			}
		}	

	return ($::SUCCESS, '', $nDiscUnitPrice, $rhashTaxBands, \@arrCurTaxBands, \@arrDefTaxBands);
	}

################################################################
#
# GetAdjustmentTaxBands - check whether the product and its components have common tax bands
#
# Input:	   $Self					- reference to self
#				$pProduct			- reference to the product hash
#				$nCartIndex			- index into the cart array
#				$sProdTax1Band		- parent product tax 1 band
#				$sProdTax2Band		- parent product tax 2 band
#				$nProdRetailPrice - parent product retail unit price
#
# Output:  	0 - $::SUCCESS or $::FAILURE
#				1 - error message or '' if $::SUCCESS
#				2 - reference to current zone product tax bands
#				3 - reference to default zone product tax bands
#				4 - applicable retail product price for custom tax
#
# Author: Mike Purnell
#
################################################################

sub GetAdjustmentTaxBands
	{
	my ($Self, $pProduct, $nCartIndex, $rarrCurProdTaxBands, $rarrDefProdTaxBands, $nProdRetailPrice) = @_;	# get parameters
	#
	# If the product uses product-only pricing, return product fields
	#
	if ($pProduct->{PRICING_MODEL} == $ActinicOrder::PRICING_MODEL_STANDARD)
		{
		return ($::SUCCESS, '', $rarrCurProdTaxBands, $rarrDefProdTaxBands, $nProdRetailPrice);
		}
	#
	# Get the cart item and variant list
	#
	my $pCartItem = @{$Self->{_CartList}}[$nCartIndex];
	my $VariantList = ActinicOrder::GetCartVariantList($pCartItem);

	my @arrTaxBandHashes = ({}, {});					# array of tax band hashes
	my @arrDefTaxBandHashes = ({}, {});				# array of default zone tax band hashes
	my @arrTaxBandHashArray = (\@arrTaxBandHashes, \@arrDefTaxBandHashes);
	my ($nBandID, $nPercent, $nFlatRate, $sBandName, $sTaxBand);	# general purpose vars for parsing band data
	#
	# If the product contributes to pricing, add it to the tax band hashes
	#
	if ($pProduct->{PRICING_MODEL} == $ActinicOrder::PRICING_MODEL_PROD_COMP)
		{
		my ($rarrTaxBands, $nArrIndex);
		foreach $rarrTaxBands(($rarrCurProdTaxBands, $rarrDefProdTaxBands))
			{
			my $rarrTaxBandHash = $arrTaxBandHashArray[$nArrIndex];
			my $nTaxIndex = 0;
			foreach $sTaxBand(@{$rarrTaxBands})	# for each product tax band
				{
				($nBandID, $nPercent, $nFlatRate, $sBandName) = split /=/, $sTaxBand;	# parse tax band
				if ($nBandID ne '')
					{
					$rarrTaxBandHash->[$nTaxIndex]{$nBandID} = $sTaxBand;	# map band ID to opaque data
					}
				$nTaxIndex++;									# next tax
				}
			$nArrIndex++;
			}
		}
	
	my $nTaxableRetailPrice = $nProdRetailPrice;	# assume we're using the product retail price

	my ($rarrCurCompTaxBands, $rarrDefCompTaxBands);
	#
	# Now go through the components
	#
	my ($pProdComponent);
	foreach $pProdComponent (@{$pProduct->{COMPONENTS}})
		{
		my ($nStatus, %Component) = ActinicOrder::FindComponent($pProdComponent, $VariantList);
		if ($nStatus != $::SUCCESS)
			{
#?			ACTINIC::ASSERT($nStatus == $::SUCCESS, "FindComponent failed", __LINE__, __FILE__);
			return ($::FAILURE, "FindComponent failed");
			}
		if ($Component{quantity} > 0)					# if this component is used
			{
			if ($Component{AssociatedTax})			# if it is using associated product tax
				{
				my @Response = ActinicOrder::GetProductTaxBands(\%Component);	# Get the tax bands for the associated product
				if ($Response[0] != $::SUCCESS)
					{
					return ($::FAILURE, "GetProductTaxBands failed");
					}
				($rarrCurCompTaxBands, $rarrDefCompTaxBands) = @Response[2, 3];
				$nTaxableRetailPrice = $Component{'RetailPrice'};	# the custom tax is using the component retail price
				}
			else
				{
				$rarrCurCompTaxBands = $rarrCurProdTaxBands;
				$rarrDefCompTaxBands = $rarrDefProdTaxBands;
				}
				
			my ($rarrTaxBands, $nArrIndex);
			foreach $rarrTaxBands(($rarrCurCompTaxBands, $rarrDefCompTaxBands))
				{
				my $rarrTaxBandHash = $arrTaxBandHashArray[$nArrIndex];
				my $nTaxIndex = 0;
				foreach $sTaxBand(@{$rarrTaxBands})	# for each product tax band
					{
					($nBandID, $nPercent, $nFlatRate, $sBandName) = split /=/, $sTaxBand;	# parse tax band
					if ($nBandID ne '')
						{
						if ($nBandID == $ActinicOrder::CUSTOM)	# custom tax?
							{
							if (defined $rarrTaxBandHash->[$nTaxIndex]{$nBandID})	# already have some custom tax?
								{
								$rarrTaxBandHash->[$nTaxIndex]{$ActinicOrder::PRORATA} = $sTaxBand;	# make sure we have more than one band ID mapped
								}
							}
						$rarrTaxBandHash->[$nTaxIndex]{$nBandID} = $sTaxBand;	# map the band
						}
					$nTaxIndex++;									# next tax
					}
				$nArrIndex++;
				}
			}
		}
	#
	# Now decide on the tax bands to return
	#
	my @arrTaxBands = ('5=0=0=', '5=0=0=');		# default to pro-rata
	my @arrDefTaxBands = ('5=0=0=', '5=0=0=');			# default to pro-rata
	my @arrReturnArrays = (\@arrTaxBands, \@arrDefTaxBands);
	my $nArrIndex = 0;
	my $rarrTaxBandHashes;
	foreach $rarrTaxBandHashes(@arrTaxBandHashArray)
		{
		my $nTaxIndex = 0;
		my $phashTaxBands;
		foreach $phashTaxBands (@{$rarrTaxBandHashes})	# for each tax
			{
			if (scalar(keys %$phashTaxBands) == 1)		# only one band ID defined
				{
				$nBandID = (keys %$phashTaxBands)[0];	# get the band ID
				$arrReturnArrays[$nArrIndex]->[$nTaxIndex] =
					$phashTaxBands->{$nBandID};			# set the opaque data
				}
			$nTaxIndex++;											# next tax
			}
		$nArrIndex++;
		}	
	return ($::SUCCESS, '', \@arrTaxBands, \@arrDefTaxBands, $nTaxableRetailPrice);	# return bands and appropriate unit price
	}

1;
