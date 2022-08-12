/***********************************************************************
*
* Recently viewed product code. V0.02. Uses cookie "ACTINIC_RECENT" of format:
*
*	ProductID\tProductName\tProductPrice\tProductThumbNailImage\fProductID\tProductName\t...
*
************************************************************************/

//END Configuration variables - alter with care

var nStartPos = -1;		// Start position (-1 means default)

/***********************************************************************
*
* CreateRecentProduct 	- create Recent Product object
*
* Input: sPid		- Product ID
*	 sPname		- Product Name (Actinic encoded)
*	 sPprice	- Product Price
*	 sThumb		- Product Thumbnail Image
*
* Returns: object with sPid, sPname, sPprice, sThumb properties
*
************************************************************************/

function CreateRecentProduct(sPid, sPname, sPprice, sThumb)
	{
	this.sPid = sPid
	this.sPname = sPname;
	this.sPprice = sPprice;
	this.sThumb = sThumb;
	}

/***********************************************************************
*
* GetRecentFromCookie -	gets list of recent products from cookie
*
* Input: nothing
*
* Returns: array of Recent Product objects
* Returns: false if no cookie items saved
*
************************************************************************/

function GetRecentFromCookie()
	{
	var sRecent = getCookie('ACTINIC_RECENT');
	if ( (sRecent != null) && (sRecent.length > 10) ) 
		{
		var aRecentViewed = new Array();
		var aCookieList = sRecent.split("\f");
		for ( var i=0; i<aCookieList.length; i++) 
			{
			var aCurrentRecent = aCookieList[i].split("\t");
			aRecentViewed.push(new CreateRecentProduct(aCurrentRecent[0], aCurrentRecent[1], aCurrentRecent[2], aCurrentRecent[3]));
			}
		return aRecentViewed;
		}
	return false;	
	}

/***********************************************************************
*
* SetRecentToCookie - saves recent products cookie
*
* Input: aRecentViewed	- array of Recent Product objects
*
* Returns: nothing
*
************************************************************************/

function SetRecentToCookie(aRecentViewed)
	{
	var sCookie = '';
	for ( var i=0; i<aRecentViewed.length; i++) sCookie += aRecentViewed[i].sPid + "\t" + aRecentViewed[i].sPname + "\t" + aRecentViewed[i].sPprice + "\t" + aRecentViewed[i].sThumb + "\f";
	sCookie = sCookie.slice(0, -1);		// lose trailing delimiter
	var dRecentExpiry = new Date();		// current time
	dRecentExpiry.setTime(dRecentExpiry.getTime() + (1000 * 60 * 60 * nKeepRecentHours));	// add hours to keep
	setCookie('ACTINIC_RECENT', sCookie, dRecentExpiry);
	}


/***********************************************************************
*
* ReplaceVariables - replace variable markers with content
*
* Input: 
*	sTemplate 	- template
*	aRecentItem 	- recentitem object
*
* Returns: template with replacements
*
************************************************************************/

function ReplaceVariables(sTemplate, aRecentItem)
	{
	var sImageURL = catalogDir + aRecentItem.sThumb;				//	add catalog path to Image
	sTemplate = sTemplate.replace(/_PID_/g,   aRecentItem.sPid);			//	_PID_	replaced by ProductID
	sTemplate = sTemplate.replace(/_ENAME_/g, escape(aRecentItem.sPname));		//	_ENAME_	replaced by Escaped Product Name
	sTemplate = sTemplate.replace(/_NAME_/g,  aRecentItem.sPname);			//	_NAME_	replaced by Product Name
	sTemplate = sTemplate.replace(/_PRICE_/g, aRecentItem.sPprice);			//	_PRICE_	replaced by Product Price
	sTemplate = sTemplate.replace(/_THUMB_/g, sImageURL);				//	_THUMB_	replaced by Image filename
	sTemplate = sTemplate.replace(/_SSURL_/g, ssURL);				//	_SSURL_	replaced by SearchScript URL
	sTemplate = sTemplate.replace(/_HREF_/g, 'href');				//	_HREF_	replaced by href (prevents actinic Perl munging it)
	return sTemplate;
	}

/***********************************************************************
*
* ScrollBackRecent - scroll back list if possible
*
* Input: nothing
*
* Returns: nothing (affects global nStartPos)
*
************************************************************************/

function ScrollBackRecent()
	{
	var aRecentViewed = GetRecentFromCookie();
	if ( aRecentViewed && (aRecentViewed.length > nTrimListTo) ) 	// can scroll back
			{
			nStartPos -= nScrollBy;			// scroll back by set length
			if ( nStartPos < 0 ) nStartPos = 0;
			document.getElementById('recenthtlist').innerHTML = RecentProductsListTableHTML();	// redisplay list
			SetBackForwardButtons ();
			}

	}	

/***********************************************************************
*
* ScrollForwardRecent - scroll forward list if possible
*
* Input: nothing
*
* Returns: nothing (affects global nStartPos)
*
************************************************************************/

function ScrollForwardRecent()
	{
	var aRecentViewed = GetRecentFromCookie();
	if ( aRecentViewed && (aRecentViewed.length > nTrimListTo) ) 	// can scroll forward
			{
			if ( nStartPos < 0 ) nStartPos = 0;
			nStartPos += nScrollBy;			// scroll forward by set count
			if ( nStartPos > (aRecentViewed.length - nTrimListTo) ) nStartPos = (aRecentViewed.length - nTrimListTo);	// don't go off end off list
			document.getElementById('recenthtlist').innerHTML = RecentProductsListTableHTML();			// redisplay list
			SetBackForwardButtons ();
			}
	}	

/***********************************************************************
*
* SetBackForwardButtons - enable disbale scroll buttons
*
* Input: nothing
*
* Returns: nothing
*
************************************************************************/

function SetBackForwardButtons()
	{
	var aRecentViewed = GetRecentFromCookie();
	if ( aRecentViewed ) 	// can scroll 
			{
			var d; if ( d = document.getElementById('scrollbackrecent') ) 
				{
				d.disabled = (nStartPos <= 0);
				d.style.cursor = (nStartPos <= 0) ? 'default' : 'pointer';
				}
			if ( d = document.getElementById('scrollforwardrecent') )
				{
				d.disabled = (nStartPos >= (aRecentViewed.length - nTrimListTo));
				d.style.cursor = (nStartPos >= (aRecentViewed.length - nTrimListTo)) ? 'default' : 'pointer';
				}
			}
	}	

/***********************************************************************
*
* TrimRecentProductsList - Reduce list to desired number of items
*
* Input: aRecentViewed	- array of Recent Product objects
*
* Returns: reduced array of Recent Product objects
*
************************************************************************/

function TrimRecentProductsList(aRecentViewed)
	{
	var nRecentListTotal = aRecentViewed.length;
	if ( nRecentListTotal <= nTrimListTo ) 		// list doesn't need truncating
		{
		nStartPos = 0;
		return aRecentViewed;
		}
	var aRecentSubList = new Array();
	if ( nStartPos < 0 ) nStartPos = nRecentListTotal - nTrimListTo;
	if ( nStartPos > (nRecentListTotal - nTrimListTo) ) nStartPos = nRecentListTotal - nTrimListTo;
	for ( i=0; i<nTrimListTo; i++ )
		{
		aRecentSubList.push(aRecentViewed[nStartPos + i]);
		}
	return aRecentSubList;
	}

/***********************************************************************
*
* RecentProductsListHTML - generate simple recent products HTML - no trimming or navigation
*
* Input: nothing - uses cookie
*
* Returns: recent products HTML or empty list string
*
************************************************************************/

function RecentProductsListHTML()
	{
	var aRecentViewed = GetRecentFromCookie();
	if ( aRecentViewed )
		{
		if ( bDisplayReversed ) aRecentViewed.reverse();		// reverse if required
		var sHTML = ''
		for (var i=0; i<aRecentViewed.length; i++)
			{
			sHTML += ReplaceVariables(sRecentItem, aRecentViewed[i]);
			}
 		if ( sHTML != '' ) return sRecentPrefix + sHTML + sRecentSuffix;
		}
	return sRecentEmptyList;		
	}

/***********************************************************************
*
* RecentProductsListTableHTML - generate horizontal table of recent products HTML - use trimmed list
*
* Input: nothing - uses cookie
*
* Returns: recent products HTML or empty list string
*
************************************************************************/

function RecentProductsListTableHTML()
	{
	var aRecentViewed = GetRecentFromCookie();
	if ( aRecentViewed )
		{
		aRecentViewed = TrimRecentProductsList(aRecentViewed);		// trim list
		if ( bDisplayReversed ) aRecentViewed.reverse();		// reverse if required
		var bHhaveItems = false;
		var sImageRowHTML = sRecentImageRowPrefix;
		var sDescRowHTML = sRecentDescRowPrefix;
		var sPriceRowHTML= sRecentPriceRowPrefix;
		var sDeleteRowHTML = sRecentDeleteRowPrefix;
		for (var i=0; i<aRecentViewed.length; i++)
			{
			bHaveItems = true;
			sImageRowHTML += ReplaceVariables(sRecentImageItem, aRecentViewed[i]);
			sDescRowHTML += ReplaceVariables(sRecentDescItem, aRecentViewed[i]);
			sPriceRowHTML += ReplaceVariables(sRecentPriceItem, aRecentViewed[i]);
			sDeleteRowHTML += ReplaceVariables(sRecentDeleteItem, aRecentViewed[i]);
			}
 		if ( bHaveItems ) return ( sRecentPrefix 
 			+ sImageRowHTML + sRecentImageRowSuffix 
 			+ sDescRowHTML + sRecentDescRowSuffix 
 			+ sPriceRowHTML + sRecentPriceRowSuffix
 			+ sDeleteRowHTML + sRecentDeleteRowSuffix
 			+ sRecentSuffix );
		}
	return sRecentEmptyList;		
	}
	
/***********************************************************************
*
* DisplayRecentProducts - write recent products HTML to page
*
* Input: bTable	- whether to use horizontal table or simple layout
* 
* Returns: nothing
*
************************************************************************/

function DisplayRecentProducts(bTable)
	{
	if (bTable) 
		{
		document.write(RecentProductsListTableHTML());
		SetBackForwardButtons();
		}
	else
		{	
		document.write(RecentProductsListHTML());
		}
	}

/***********************************************************************
*
* SaveRecentProduct - called from Product List layout - save product detail to cookie
*
* Input: sPid		- Product ID
*	 sPname		- Product Name (Actinic encoded)
*	 sPprice	- Product Price
*	 sThumb		- Product Thumbnail Image
* 
* Returns: nothing
*
************************************************************************/

function SaveRecentProduct(sPid, sPname, sPprice, sThumb)
	{
	if ( sThumb == '' ) return;		// skip items with no thumbnail
	var aRecentViewed = new Array();
	var aCurrentRecent = GetRecentFromCookie();
	if ( aCurrentRecent )
		{
		for ( var i=0; i<aCurrentRecent.length; i++) if ( aCurrentRecent[i].sPid != sPid ) aRecentViewed.push(aCurrentRecent[i]);	// remove any identical products from list
		}	
	aRecentViewed.push(new CreateRecentProduct(sPid, sPname, sPprice, sThumb));	// save at end of list
	while ( aRecentViewed.length > nMaxRecent ) aRecentViewed.shift();		// trim excess entries
	SetRecentToCookie(aRecentViewed);
	}

/***********************************************************************
*
* DeleteRecent - called from Product display - delete selected product from recent products list
*
* Input: sPid	- ProductID
*	 bTable	- Whether to use simple layout or table
* 
* Returns: nothing
*
************************************************************************/

function DeleteRecent(sPid, bTable)
	{
	var aRecentViewed = new Array();
	var aCurrentRecent = GetRecentFromCookie();
	if ( aCurrentRecent )
		{
		for ( var i=0; i<aCurrentRecent.length; i++) if ( aCurrentRecent[i].sPid != sPid ) aRecentViewed.push(aCurrentRecent[i]);	// remove matching products from list
		}	
	SetRecentToCookie(aRecentViewed);
	if ( bTable )
		{
		document.getElementById('recenthtlist').innerHTML = RecentProductsListTableHTML();	// redisplay horiz table list
		}
	else
		{	
		document.getElementById('recentstlist').innerHTML = RecentProductsListHTML();		// redisplay simple list
		}
	SetBackForwardButtons();
	}
// END - Recently viewed product code. 