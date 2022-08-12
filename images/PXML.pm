#!perl
################################################################
#																					#
#  PXML.pm - pseudo XML parser											#
#																					#
#  Based on 																	#
#    Ryszard Zybert's PXML module built into ACTINIC.pm			#
#																					#
#  Author: Zoltan Magyar, 2:32 PM, November 28, 2001				#
#																					#
#  Copyright (c) Actinic Software Plc 2001							#
#																					#
################################################################
package PXML;
use strict;
push (@INC, "cgi-bin");
<Actinic:Variable Name="IncludePathAdjustment"/>
#
# Constants definition
#
use <Actinic:Variable Name="ActinicConstantsPackage"/>;
#
# Version
#
$PXML::prog_name = 'PXML.pm';							# Program Name
$PXML::prog_name = $PXML::prog_name;				# remove compiler warning
$PXML::prog_ver = '$Revision: 23159 $ ';				# program version
$PXML::prog_ver = substr($PXML::prog_ver, 11); 	# strip the revision information
$PXML::prog_ver =~ s/ \$//;							# and the trailers
################################################################
#
#  PXML->new() - constructor for PXML class
#  A very standard constructor. Allows inheritance.
#  Calls Set() function passing it all the arguments.
#  So the arguments may be specified here with name=>value
#  pairs or they may be set later using Set() method.
#  No arguments are obligatory in new() but all arguments must
#  be specified before Parse() method is used.
#  Following arguments are required:
#  ID       => prefix of tags to be handled (it may be specified in Parse())
#  tag1     => reference to function to handle <IDtag1>
#  tag1_End => reference to function to handle </IDtag1>
#  ...
#  Special optional arguments:
#  DEFAULT  => reference to a function handling unrecognised
#              tags (with prefix specified in ID)
#  XMLERROR => Error message to print when parser detects an error
#              Embedded %s will be replaced by the tag for which an error
#              was detected.
#              Default: "Error parsing XML text (%s)"
#  If DEFAULT is not specified the unknown tags are passed to
#  output unchanged.
#
#  Supplied function may or may not be different, the tag
#  name and the ID are passed to the function.
#  See comment for Parse().
#
#  Ryszard Zybert  Dec  1 18:15:36 GMT 1999
#
#  Copyright (c) Actinic Software Ltd 1999
#
################################################################
#
# Private variables:
#
# _XMLERROR		- The error message text for parse errors
# _LoopProtect	- Number of maximum allowable recursive loops 
#					  before infinitive loop error is raised
# _CurrentLoop	- The current loop counter for recursive calls
# _Tags			- Hash of the tag handler functions. All CODE typed
#					  parameter passed in via Set is stored here.
#
################################################################

sub new
	{
	my $Proto = shift;
	my $Class = ref($Proto) || $Proto;
	my $Self  = {};
	bless ($Self, $Class);
	$Self->{_XMLERROR} = "Error parsing XML text (%s)";
	$Self->{_LoopProtect} = 25000;
	$Self->{_CurrentLoop} = 0;
	$Self->Set(@_);

	return $Self;
	}
	
################################################################
#
#  PXML->Set() - set configuration parameters
#
#  Author: Ryszard Zybert  Nov 28 09:34:32 GMT 1999
#
#  Copyright (c) Actinic Software Ltd 1999
#
################################################################

sub Set
	{
	my $Self       = shift;
	my %Parameters = @_;
	#
	# Separate handlers from parameters amd make a hash
	#
	foreach (keys %Parameters)
		{
		if( ref($Parameters{$_}) eq "CODE" )	# Treat all functions as tag handlers (case sensitive)
			{
			$Self->{_Tags}->{uc($_)} = $Parameters{$_};
			}
		else												# Anything else is a parameter (case sensitive)
			{
			$Self->{$_} = $Parameters{$_};
			}
		}
 	}
 	
################################################################
#
#  PXML->Parse() - parse text
#
#  NOTE: It may be called recursively
#
#   Arguments:	0 - text to parse
#					1 - (optional) ID - prefix to look for
#
#   Returns:   0 - parsed text
#					1 - tag tree
#
#  When a tag is found, looks for the end-tag and calls function
#  which was declared to deal with this tag.
#  The text between start-tag and end-tag is parsed recursively
#  Then (if defined) function handing $tag.'_End' is called.
#  Abbreviated syntax: <tag/> is accepted.
#  Parameters are parsed and passed as a hash reference to the
#  handler (parameter without value is set to 'SET')
#
#  Tag handling function is called with five arguments:
#		$tag				- tag name
#		\$sText			- reference to text found between start and end tag
#		\%Parameters	- reference to parameter hash
#		ID					- prefix for this run
#		$sStartTag		- full text of start tag
#
#  It may return text to go to output and may also modify the
#  text between tags before it is parsed further
#
#  If end-tag handling function is defined then it is called
#  after the contents is parsed.
#  If not - it defaults to tag handling function.
#  End-tag handling function is called with the same arguments
#  as tag handling function but only arg 0, 3 and 4 are set.
#
#  Tags and ID are case sensitive
#  Parameters names are used in hash unchanged
#
#  If the tag handling function is not defined then:
#  If DEFAULT function is defined - it is called
#  If DEFAULT_End function is defined - it is called for End-tag
#  Otherwise the the tag is passed on to output unchanged.
#
#  Ryszard Zybert  Nov 28 14:40:12 GMT 1999
#
#
#  The parse has been extended to store the XML entities in
#	a structured tree. The tree is defined as nested Element objects of 
# 	the XML tags. E.g. the XML string
#
#	</SessionFile Veraion="1.0">
#  	<URLInfo>
#			<LASTSHOPPAGE>http://10.3.4.2/actinic/acatalog/index.html</LASTSHOPPAGE>
#			<LASTPAGE>http://10.3.4.2/actinic/acatalog/lastpage.html</LASTPAGE>
#			<BASEURL>http://10.3.4.2/actinic/acatalog/</BASEURL>
#		</URLInfo>
#	</SessionFile>
#
#	results an Element structure such as
#
#	[
#		{
#		_TAG = "SessionFile"
#		_PARAMETERS = 
#			{
#			Version => "1.0"
#			}
#		_CONTENT =>
#			[
#				{
#				_TAG => "URLInfo"
#				_PARAMETERS => {}
#				_CONTENT	=>
#					[
#						{
#						_TAG => "LASTSHOPPAGE" 
#						_PARAMETERS => {}
#						_CONTENT => "http://10.3.4.2/actinic/acatalog/index.html"
#						}, 
#						{
#						_TAG => "LASTPAGE" 
#						_PARAMETERS => {}
#						_CONTENT => "http://10.3.4.2/actinic/acatalog/lastpage.html"
#						},
#						{
#						_TAG => "BASEURL" 
#						_PARAMETERS => {}
#						_CONTENT => "http://10.3.4.2/actinic/acatalog/"
#						}
#					]
#				}
#			]
#		}
#	]
#
#
#	It works backwards as well. I.e. the XML file can be constructed
#	from the tag tree. See header of SaveXML().
#
#	Zoltan Magyar 5:14 PM, November 28, 2001
#
#  Copyright (c) Actinic Software Ltd 2001
#
################################################################

sub Parse
	{
	my $Self  = shift;
	my $sText = shift;
	my $sId   = shift;
	my $pTree;
	
	my $pResTree;
	my $sDummy;
	my $Result;
	
	if( !$sId ) 
		{ 
		$sId = $Self->{ID}; 								# ID parameter is optional here
		}
		
	$Self->{_CurrentLoop}++;
	if( $Self->{_CurrentLoop} > $Self->{_LoopProtect} )
		{
		$Result = $Self->{_XMLERROR};
		$Result =~ s/\%s/Infinite Loop \(\?\)/;
		return $Result;
		}
	#
	# This is where parsing is done
	# To change what is and what is not accepted/processed change the
	# regular expression below - note that results are used below, so
	# if brackets are added/removed, make sure that following code gets
	# fixed.
	#
	#pragma MUSTDO("MRP: Remove this or implement it")
#	$sText =~ s/<!--Act\|/</g;
#	$sText =~ s/\|Act-->/>/g;
	while ( $sText =~ /
			  (												# Start tag 										($1)
				<
				\s*											# Possible white space at the beginning
				$sId											# Identifier
				([0-9a-zA-Z_-]+?)							# Tag	name 											($2)(used)
				(												# Optional parameter list 						($3)(used)
				 (\s+											# Parameter starts from space					($4)
				  [0-9a-zA-Z_-]+?							# Parameter name
				  (\=											# Parameter value with equal sign			($5)
					(											# Parameter value									($6)
					 (\"[^\"]*\") |						# Parameter value in double quotes 			($7)
					 (\'[^\']*\') |						# Parameter value in single quotes 			($8)
					 ([^\"\'\ \/\>\r\n\t]+)				# Parameter value without quotes 			($9)
					)
				  )*?											# Value is optional (default is 'SET')
				 )*?											# Parameters are optional
				)
				\s*											# Possible white space
				(\/*?)										# Optional End mark 								($10)(used)
				\s*											# Possible white space at the end
				>
			  )
			  | (<!--.*?-->)								# Or comment 										($11)(used)
			  /sx )
		{
		$sText   = $';										# shift the buffer pointer
		$Result .= $`;										# add the front part

		#
		# Commented text is not processed
		# Usually this just saves time. But - note that if handlers have side effects
		# then it may matter a bit more if you comment out XML tags
		# To change that - simply comment out comment detection line from regexp above
		#
		if( $11 )											# If comment - pass it as is
			{
			$Result .= $&;									# Add commented part and continue
			next;
			}

		my $sTag					= $2;						# tag name
		my $sParameterText	= $3;						# parameter list
		my $sInsideText		= "";						# text between start and end (empty for now)
		my $sStartTag			= $&;						# complete start tag
		my $sEndTag;										# complete end tag (nothing yet)
		my $ParameterHash;								# hash of parameters (nothing yet)
		
		
		#
		# If there are parameters make a hash
		#
		if( $sParameterText )
			{
			$ParameterHash = $Self->ParseParameters($sParameterText);
			}
		#
		# If not 'abbreviated syntax' look for end-tag
		#
		if ( !$10 ) 
			{ 
			$sInsideText  = $Self->FindEndTag($sId,$sTag,\$sText,\$sEndTag); 
			}
		#
		# If tag handler or DEFAULT defined, call it, otherwise just return the whole text
		# In any case, parse the text recursively
		#
		my $sGeneralTag = uc($sTag);
		if ( !defined($Self->{_Tags}->{$sGeneralTag}) ) 
			{ 
			$sGeneralTag = 'DEFAULT'; 
			}

		if( defined($Self->{_Tags}->{$sGeneralTag}) )		# Tag handler found
			{
			#
			# Call tag handler and parse text that it returns
			#
			my $sReplace =	&{$Self->{_Tags}->{$sGeneralTag}}(
																		  $sTag,					# Tag name
																		  \$sInsideText,		# Reference to text between tags
																		  $ParameterHash,		# Reference to hash of parameters
																		  $sId,					# Current Prefix
																		  $sStartTag			# Full text of start tag
																		 );

			if( $sReplace eq $sStartTag )				# Try to avoid infinite loops
				{												# If nothing changed, don't parse again
				$Result .= $sReplace;
				}
			else
				{
				($sDummy, $pResTree) = $Self->Parse($sReplace,$sId);
				$Result .= $sDummy;
				}
			#
			# Parse text between start-tag and end-tag
			#
			($sDummy, $pResTree) = $Self->Parse($sInsideText,$sId);
			$Result .= $sDummy;
			
			if( defined($Self->{_Tags}->{$sGeneralTag.'_END'}) )	
				{												# End-tag - call handler and parse returned text
				$sReplace = &{$Self->{_Tags}->{$sGeneralTag.'_END'}}('/'.$sTag, "", "", $sId, $sEndTag);
				}
			else												# Default to the same as start tag
				{
				$sReplace = &{$Self->{_Tags}->{$sGeneralTag}}('/'.$sTag, "", "", $sId, $sEndTag);
				}

			if( $sReplace eq $sEndTag )				# Try to avoid infinite loops
				{												# If nothing changed, don't parse again
				$Result .= $sReplace;
				}
			else
				{
				($sDummy, $pResTree) = $Self->Parse($sReplace,$sId);
				$Result .= $sDummy;
				}
			}
		else													# No handler and no default, just parse text between tags
			{
			($sDummy, $pResTree) = $Self->Parse($sInsideText,$sId) ;
			$Result .= $sStartTag . $sDummy . $sEndTag;
			}
		#
		# Build the XML entity tree
		#
		my $pContent;
		if (ref($pResTree) ne 'ARRAY')				# the parse result is not an array
			{
			$pContent = ACTINIC::DecodeText($sDummy, $ACTINIC::HTML_ENCODED);							# then it is a leaf 
			}
		else													# otherwise it is a new branch
			{
			$pContent = $pResTree;						# so store the whole array
			}		
		my $pTemp = Element::new('Element', {
								_TAG 			=> $sTag,
								_PARAMETERS => $ParameterHash,
								_CONTENT		=> $pContent,
								_ORIGINAL	=> $sInsideText,
								});
		push @{$pTree}, $pTemp;
		}
	return $Result . $sText, $pTree;					# Append all the rest of text if no more tags
	}
	
################################################################
#
#  PXML->FindEndTag() - find end-tag
#   Input:		   $sId - current ID
#                 $sTag - tag name
#                 \$sText - reference to text to look in
#                 \$sEnd - reference to end tag (initialy empty)
#
#   $sText is changed to start after the end-tag
#
#   Output: 		text found before the end-tag
#
#  Author:  Ryszard Zybert  Nov 28 14:42:23 GMT 1999
#				Zoltan Magyar, 10:44 AM 3/25/2002
#					- processing of nested XML tags
#
#  Copyright (c) Actinic Software Ltd 2002
#
################################################################

sub FindEndTag
	{
	my $Self = shift;
	my ($sId, $sTag, $sText, $sEnd) = @_;
	my ($sBetween, $sAfter, $sBefore);
	$sAfter = $$sText;
	my $nStartCount = 1;									# we have one start tag already  when it is called
	my $nEndCount 	 = 0;									# end tag counter
	my $sIterate;
	
	while ($nStartCount > $nEndCount)
		{
		$nStartCount = 1;									# reset start tag counter
		if( $sAfter =~ / < \s* \/ $sId $sTag \s* > /sx )	# Look for end-tag
			{
			$sAfter = $';									# Text after end tag
			$$sEnd  = $&;									# Text of end tag
			$sBetween .= $`;								# Text between start-tag and end-tag
			$nEndCount++;									# count end tags
			}
		else													# Not found - return error and unchanged text
			{
			my $sErr = sprintf($Self->{_XMLERROR}, $sId. $sTag);
			return $sErr . $$sText;
			}			
		$sIterate = $sBetween . $$sEnd;
		#
		# Count begin tags
		#
		while( $sIterate =~ / < \s* $sId $sTag (\s [^<]* [^\/])? > /sx )	# Look for begin-tags (don't count abbreviated)
			{
			$sIterate = $';								# Text between start-tag and end-tag
			$nStartCount++;								# count begin tags
			}	
		if ($nStartCount > $nEndCount)				# if we still don't have match
			{
			$sBetween .= $$sEnd;							# add this end tag to the text 
			}
		}
	$$sText = $sAfter;
	return $sBetween;		
	}
	
################################################################
#
#  PXML->ParseParameters() - parse parameter list
#  Splits parameter list and makes a hash
#
#   Input:	parameter string (must start with white space)
#   Output:	parameter hash reference
#
#  Author: Ryszard Zybert  Nov 30 10:47:24 GMT 1999
#
#  Copyright (c) Actinic Software Ltd 1999
#
################################################################

sub ParseParameters
	{
	my $Self        = shift;
	my $sParameters = shift;

	my $ParameterHash = ();
	#
	# IMPORTANT:
	# Parameter string starts IMMEDIATELY after recognised _TAG
	# So: it MUST start from white space
	#
	while ( $sParameters =~ m/\G
			  \s+												# Obligatory white space
			  ([0-9a-zA-Z_-]+)								# Parameter name ($1)
			  (\=
				(
				 (\"[^\"]*\") |							# Parameter value in double quotes
				 (\'[^\']*\') |							# Parameter value in single quotes
				 ([^\"\'\ \/\>\r\n\t]+)					# Parameter value without quotes
				)												# Parameter value ($3)
			  )*												# '=value' may not be there ($2)
			  /gsx )
		{
		my $sName = $1;
		if( $2 )												# There is a value
			{
			my $sValue = ACTINIC::DecodeText($3, $ACTINIC::HTML_ENCODED);
			$sValue =~ s/^(\"|\')//;					# Remove leading quote
			$sValue =~ s/(\"|\')$//;					# Remove trailing quote
			$ParameterHash->{$sName} = $sValue;
			}
		else													# No value, set it to 'SET'
			{
			$ParameterHash->{$sName} = 'SET';
			}
		}
	return $ParameterHash;
	}
	
################################################################
#
#  PXML->SaveXML() - Convert the passed XML entity tree to XML format
#
#   Input:	0 - XML parameter tree
#   Output:	0 - XML string
#
#	NOTE: this function may be called recursively
#
# 	This function creates an XML from the passed in XML tag tree.
#	The function is called recursively on the tree to process
#	nested tags. 
#	The provided XML string is not formatted to avoid parameter
#	value confusion. Only the last nodes get line feeds.
#	See the header of Parse() for more detailed description 
#	of XML tag tree.
#
#  Author: Zoltan Magyar 5:14 PM, November 28, 2001
#
#  Copyright (c) Actinic Software Ltd 2001
#
################################################################

sub SaveXML
	{
	my $Self  		= shift;
	my $hashTree 	= $_[0];
	my $sIndent		= $_[1];

	my $pIterator;											# iterator variable for foreach
	my $sXML;												# XML buffer
	
	foreach $pIterator (@$$hashTree)					# take each entry of the array
		{
		my $sEmbed;
		my $sTag;
		my $sEndTag;
		my $sTagName = $$pIterator{_TAG};
		my $sParameters;
		my $pParam;
		#
		# Create parameter string
		#
		foreach $pParam (keys %{$$pIterator{_PARAMETERS}})
			{
			$sParameters .= "$pParam=\"" . ACTINIC::EncodeText2($$pIterator{_PARAMETERS}->{$pParam}) . "\" ";
			}
		#
		# Construct the XML tag
		#
		$sTag = "<$sTagName $sParameters";
		$sTag =~ s/\s*$//;								# remove unnecessary white space
		$sEndTag = "</$sTagName>";
		if ($$pIterator{_CONTENT} eq '')				# if abbreviated syntax
			{
			$sXML .= $sIndent . $sTag . "/>\n";
			next;
			}
		#
		# If the current item is an array then call recursively
		#
		if (ref($$pIterator{_CONTENT}) eq 'ARRAY')
			{
			$sTag .= ">\n";
			$sEndTag = $sIndent . $sEndTag;
			$sEmbed = $Self->SaveXML(\$$pIterator{_CONTENT}, $sIndent . "\t");
			}
		else													# it is a plain entry, just save it
			{
			$sTag .= ">";
			$sEmbed = ACTINIC::EncodeText2($$pIterator{_CONTENT});
			}
		#
		# Format and add to the XML buffer
		#
		$sXML .= "$sIndent$sTag$sEmbed$sEndTag\n";
		}
	return $sXML;
	}
	
################################################################
#
#  PXML->SaveXMLFile() - mapper for SaveXML
#		constructs the XML from the passed XML tree and saves 
#		to the specified file
#
#   Input:		0 - file name
#					1 - XML parameter tree
#
#   Output:		0 - success/failure
#					1 - the saved XML string
#
#  Author: Zoltan Magyar Thursday, 10:18 AM 11/29/2001
#
#  Copyright (c) Actinic Software Ltd 2001
#
################################################################

sub SaveXMLFile
	{
	my $Self  		= shift;
	my $sFilename	= shift;
	my $hashTree 	= $_[0];

	my $sXML;												# XML buffer
	#
	# Construct the XML string
	#
	$sXML = $Self->SaveXML(\$hashTree);
	#
	# Open the file and save
	#
	unless (open (XMLFILE, ">$sFilename"))			# open the file
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sFilename, $!));
		}
	unless (print XMLFILE $sXML)
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 28, $sFilename, $!));
		}
	close XMLFILE;
	 
	return ($::SUCCESS, $sXML);
	}	
	
################################################################
#
#  PXML->ParseFile() - mapper for Parse()
#		opens the specified file and parses its content 
#
#   Input:		0 - file name
#					1 - (optional) ID - prefix to look for		
#
#   Output:		0 - success/failure
#					1 - the saved XML string
#					2 - tree of the XML tags
#
#  Author: Zoltan Magyar Thursday, 10:18 AM 11/29/2001
#
#  Copyright (c) Actinic Software Ltd 2001
#
################################################################

sub ParseFile
	{
	my $Self  		= shift;
	my $sFilename	= shift;
	my $sId   		= shift;	
	my $sXML;
	#
	# Open the file 
	#
	unless (open (XMLFILE, "<$sFilename"))			# open the file
		{
		return ($::FAILURE, ACTINIC::GetPhrase(-1, 21, $sFilename, $!));
		}
	{
	local $/;
	$sXML = <XMLFILE>;									# read the entire file
	}
	close XMLFILE;
	
	my ($sParsedText, $pTree) = $Self->Parse($sXML, $sId);
	
	return ($::SUCCESS, $sXML, $pTree);
	}		

################################################################
#																					#
#  Element package - wrapper class for accessing and editing 	#
#  						elements of an xml structure					#
#																					#
#  The PXML package acts as a converter between 					#
#  textual XML descriptions and their low-level 					#
#  perl data representations.												#
#  The perl representation uses array and hash references		#
#  to describe the data structure of the underlying xml file.	#
#  An XML element of the structure has the following form:		#
#																					#
#  $element = {																#
#  _CONTENT => <node value> | Content => [<subnode1>, ...],		#
#  _PARAMETERS => {<param1> =><param value>, ...}					#
#  _TAG => <node name>														#
#  }																				#
#																					#
#  Element class defines getter-setter functions 					#
#  over these hash nodes to make the manipulation					#
#  of the structure easier.												#
#																					#
#  Author: Tibor Vajda, January 13, 2002								#
#																					#
#  Copyright (c) Actinic Software Plc 2002							#
#																					#
################################################################
package Element;
use strict;

################################################################
#
#  Element->new() - constructor for Element class
#
#  Input:	0 - a hash reference to an xml element  
#
#  Output: 	0 - the "blessed" form of the reference 
#							passed as argument
#    
################################################################

sub new
	{
	my $Proto = shift;
	my $Class = ref($Proto) || $Proto;
	my $Self = shift;										# a hash reference to the element
	#
	# If called with empty parameters, then create a blank structure
	#
	if (!$Self)
		{
		$Self = {};
		}			
	if (!exists $Self->{_CONTENT})
		{
		$Self->{_CONTENT} = '';			
		}
	if (!exists $Self->{_PARAMETERS})
		{
		$Self->{_PARAMETERS} = {};
		}
	if (!exists $Self->{_TAG})
		{
		$Self->{_TAG} = '';		
		}
	if (!exists $Self->{_ORIGINAL})
		{
		$Self->{_ORIGINAL} = '';		
		}		
	#
	# Bless the structure with this class
	#	
	bless ($Self, $Class);
	#
	# Return the blessed structure
	#	
	return $Self;
	}
	
################################################################
#
#  Element->IsElementNode() - determines whether the element 
#										is an ELEMENT_NODE or not
#
#  Output:	 0 - 	true:	the node is an ELEMENT_NODE
#    					false:	the node is not an ELEMENT_NODE, 
#									i.e. it is a TEXT_NODE 
#									in the current representation
#
################################################################

sub IsElementNode
	{
	my $Self  = shift;
	#
	# The element is an element node if and only if its content is an array
	#
	return (ref($Self->{_CONTENT}) eq 'ARRAY');
	}

################################################################
#
#  Element->IsTextNode() - determines whether the element 
#									is an TEXT_NODE or not
#
#  Output:	 0 -	true: the node is a TEXT_NODE
#    					false:	the node is not a TEXT_NODE, 
#									i.e. it is an ELEMENT_NODE in 
#									the current representation
#
################################################################

sub IsTextNode
	{		
	my $Self  = shift;
	#
	# The element is a text node if and only if its content is a string
	#
	return (ref($Self->{_CONTENT}) eq undef);
	}

################################################################
#
#  Element->GetChildNodeCount() - determines the number of 
#												child nodes of this ELEMENT_NODE
#
#  Output: number of child nodes
#
################################################################

sub GetChildNodeCount
	{
	my $Self = shift;
	#
	# Function operates only on element nodes
	#
#? ACTINIC::ASSERT($Self->IsElementNode(), "Function Element::GetChildNodeCount operates only on element nodes", __LINE__, __FILE__);
	#
	# Number of childs equals number of elements in the CONTENT array
	#
	my $nLength = @{$Self->{_CONTENT}};
	return $nLength;
	}
	
################################################################
#
#  Element->FindNode() - finds the first occurence of the 
#										specified node in the tree 
#										and returns it (undef otherwise)
#
#  Input: 	0 - 	tag name to look for
#				1 - 	attribut name to look for (if any)
#				2 -	attribute value (optional)
#
#  Output: 	0 - 	the child element, if it is an ELEMENT_NODE 
#								and has child with the specified name
#    							undef, otherwise
#
# Author:	Zoltan Magyar, 9:44 PM 3/13/2002
#
################################################################

sub FindNode	
	{
	my $Self  				= shift;
	my $sNodeName 			= shift;						# name of the requested child node
	my $sAttributeName 	= shift;
	my $sAttributeValue 	= shift;
	#
	# Function operates only on element nodes
	#
	if (!$Self->IsElementNode())
		{
		return undef;
		}
	#
	# Loop on the array of child nodes
	#
	my $pNode;
	foreach $pNode (@{$Self->{_CONTENT}})
		{
		#
		# If the child is node then do it recursively
		#
		if ($pNode->IsElementNode())
			{
			my $pRecNode = $pNode->FindNode($sNodeName, $sAttributeName, $sAttributeValue);
			if (defined $pRecNode)
				{
				return $pRecNode;	
				}
			}
		#
		# If the child's tag name equals to the requested one, then return it
		#
		if (%{$pNode}->{_TAG} eq $sNodeName &&
			 ($sAttributeName eq "" ||
			  $pNode->GetAttribute($sAttributeName) eq $sAttributeValue))
			{
			return $pNode;
			}
		}
	
	return undef;
	}
	
################################################################
#
#  Element->GetChildNodeAt() - returns the ith child node of 
#											this ELEMENT_NODE
#
#  Input:	0 - index of the child node
#  Output: 	the ith child node
#
################################################################

sub GetChildNodeAt
	{
	my $Self = shift;
	my $i = shift;											# index of the requested child node
	#
	# Function operates only on element nodes
	#
#? ACTINIC::ASSERT($Self->IsElementNode(), "Function Element::GetChildNodeAt operates only on element nodes", __LINE__, __FILE__);
	#
	# The ith child is the ith element of the CONTENT array
	#
	return $Self->{_CONTENT}[$i];
	}
	
################################################################
#
#  Element->GetChildNode() - returns the child node of 
#										this node element with the 
#										specified tag name
#
#  Input: 	0 - 	tag name of the child node
#
#  Output: 	0 - 	the child element, if it is an ELEMENT_NODE 
#								and has child with the specified name
#    							undef, otherwise
#
################################################################

sub GetChildNode	
	{
	my $Self  = shift;
	my $sNodeName = shift;								# name of the requested child node
	#
	# Function operates only on element nodes
	#
	if (!$Self->IsElementNode())
		{
		return undef;
		}
	#
	# Loop on the array of child nodes
	#
	my $pNode;
	foreach $pNode (@{$Self->{_CONTENT}})
		{
			#
			# If the child's tag name equals to the requested one, then return it
			#
			if (%{$pNode}->{_TAG} eq $sNodeName)
				{
				return $pNode;
				}
		}
	
	return undef;
	}

################################################################
#
#  Element->GetChildNodes() - returns an array of child nodes of 
#										this node element with the 
#										specified tag name
#
#  Input: 		0 - [optional] tag name of the child nodes
#							if empty, then all the child nodes are required 
#
#  Output: 		0 - 	reference to an array of child elements,
#							if it is an ELEMENT_NODE 
#    						undef, otherwise
#
#	Author: Zoltan Magyar
#
################################################################

sub GetChildNodes	
	{
	my $Self  = shift;
	my $sNodeName = shift;								# name of the requested child node
	#
	# Function operates only on element nodes
	#
	if (!$Self->IsElementNode())
		{
		return undef;
		}
	#
	# Loop on the array of child nodes
	#
	my $pChildNodes = [];
	my $i = 0;
	my $pNode;
	foreach $pNode (@{$Self->{_CONTENT}})
		{
			#
			# Add child node to the array
			#
			if (!$sNodeName ||								# node name is not defined
				%{$pNode}->{_TAG} eq $sNodeName) # or tag name equals to the specified node name
				{
				$pChildNodes->[$i++] = $pNode;
				}
		}
	
	return $pChildNodes;
	}

################################################################
#
#  Element->SetChildNode() - sets or adds the child node of 
#										this node element
#
#  Input: 0 - child node data structure
#
################################################################

sub SetChildNode	
	{
	my $Self  = shift;
	my $pElement = shift;								# the new child node
	#
	# If the content wasn't an array so far, than make it an array
	#
	if (!$Self->IsElementNode())
		{
		$Self->{_CONTENT} = [];
		}
	#
	# Loop through the child nodes and search for one with the same name as the new child node
	#	
	my $i = 0;												# index of the child node in the node array 
	my $pNode;
	foreach $pNode (@{$Self->{_CONTENT}})
		{
			#
			# if the content wasn't an array so far, than make it an array
			#
			if (%{$pNode}->{_TAG} eq $pElement->GetTag())
				{					
					$Self->{_CONTENT}[$i] = $pElement;
					return;
				}
			$i++;
		}
	#
	# Set the ith child if the node already exists
	# or add a node to the end of the array (determined by $i)
	#
	$Self->{_CONTENT}[$i] = $pElement;
	}

################################################################
#
#  Element->AddChildNode() - adds the child node of 
#										this node element
#
#  Input: 0 - child node data structure
#
################################################################

sub AddChildNode	
	{
	my $Self  = shift;
	my $pElement = shift;								# the new child node
	#
	# If the content wasn't an array so far, than make it an array
	#
	if (!$Self->IsElementNode())
		{
		$Self->{_CONTENT} = [];
		}
	#
	# Add a node to the end of the array
	#
	push(@{$Self->{_CONTENT}}, $pElement);
	}

################################################################
#
#  Element->RemoveChildNodes() - removes all child nodes from the node
#
#  Input: 0 - child node data structure
#
################################################################

sub RemoveChildNodes	
	{
	my $Self  = shift;
	my $pElement = shift;								# the new child node
	#
	# Function operates only on element nodes
	#
#? ACTINIC::ASSERT($Self->IsElementNode(), "Function Element::GetChildNode operates only on element nodes", __LINE__, __FILE__);
	#
	# Set the content to empty
	#
	$Self->{_CONTENT} = [];
	}

################################################################
#
#  Element->SetTextNode() - sets or adds the 
#					child node of this node element by using the
#					passed in name and value
#
#  Input:	 	0 - node name (_TAG)
#					1 - node value (_CONTENT)
#
################################################################

sub SetTextNode
	{
	my $Self  	= shift;
	my $sName 	= shift;									# the new child node
	my $sValue	= shift;
	#
	# If the content wasn't an array so far, than make it an array
	#
	if (!$Self->IsElementNode())
		{
		$Self->{_CONTENT} = [];
		}
	#
	# Loop through the child nodes and search for one with the same name as the new child node
	#	
	my $i = 0;												# index of the child node in the node array 
	my $pNode;
	foreach $pNode (@{$Self->{_CONTENT}})
		{
			#
			# if the content wasn't an array so far, than make it an array
			#
			if (%{$pNode}->{_TAG} eq $sName)
				{					
					$Self->{_CONTENT}[$i]->SetTag($sName);
					$Self->{_CONTENT}[$i]->SetNodeValue($sValue);
					return;
				}
			$i++;
		}
	#
	# Set the ith child if the node already exists
	# or add a node to the end of the array (determined by $i)
	#
	my $pElement = new Element({"_TAG" => $sName, "_CONTENT" => $sValue});
	push @{$Self->{_CONTENT}}, $pElement;
	}
	
################################################################
#
#  static Element->CreateElementFromLegacyStructure() - 
#		creates an element from legacy hash structure
#  	The legacy structure looks like:
#    	$element =
#    	{
#    	<Child Tag name1> => <subChild structure> | <value>
#    	...
#    	}
#
#  Input: 		0 - element name
#    				1 - the element in the legacy format
#
#  Output: 		0 - the created node as an Element
#  
################################################################

sub CreateElementFromLegacyStructure
	{
	my $sNodeName = shift;								# name of the element node
	my $pLegacyStructure = shift;						# element node represented by the legacy structure
	#
	# Create a node of the new structure
	#
	my $pNewElement = new Element();
	#
	# ... with the same tag name
	#
	$pNewElement->SetTag($sNodeName);
	#
	# ... add the CONTENT 
	#
	if (ref($pLegacyStructure) eq "HASH")			# this is an element node
		{
		#
		# Loop through the child nodes of the hash structure
		#
		my $key;
		foreach $key (keys(%{$pLegacyStructure}))
			{
			#
			# Recursively convert the child nodes and add them to this element
			#					
			$pNewElement->SetChildNode(Element::CreateElementFromLegacyStructure($key, $pLegacyStructure->{$key}));
			}
		}
	else														# this is a text node
		{
		#
		# Interpret the current structure as text value
		#					
		$pNewElement->SetNodeValue($pLegacyStructure)	;					
		}
	return $pNewElement;
	}

################################################################
#
#  static Element->ToLegacyStructure() - 
#		converts the element to the legacy hash structure
#    	The legacy structure looks like:
#    	$element =
#    	{
#    	<Child Tag name1> => <subChild structure> | <value>
#    	...
#    	}
#
#	Input:	0 - disallow empty root node (default TRUE)
#						if true empty root nodes result empty hash return
#						instead of empty string.
#
#  Output: 	0 - the legacy structure
#  
################################################################

sub ToLegacyStructure
	{
	my $Self 			= shift;
	my $bNoEmptyRoot 	= shift;
	#
	# Check if default should be used
	#
	if (!defined $bNoEmptyRoot)
		{
		$bNoEmptyRoot = $::TRUE;
		}
	#
	# Creates a new structure
	#					
	my $pLegacyStructure;
	#
	# Fill in the structure with the appropriate values
	#						
	if ($Self->IsTextNode())							# this is a text node
		{
		#
		# Set the structure to a string value 
		#					
		if ($Self->GetNodeValue() eq "" &&
			 $bNoEmptyRoot)
			{
			$pLegacyStructure = {};
			}
		else
			{
			$pLegacyStructure = $Self->GetNodeValue();
			}
		}
	else														# this is an element node
		{
		#
		# Set the structure to a hash of structures
		#					
		$pLegacyStructure = {};
		#
		# Loop through the child nodes and convert them one-by-one 
		#					
		for (my $i = 0; $i < $Self->GetChildNodeCount(); $i++)
			{
			my $pChildNode = $Self->GetChildNodeAt($i);
			#
			# Recursively convert the child structures
			#					
			$pLegacyStructure->{$pChildNode->GetTag()} = $pChildNode->ToLegacyStructure($::FALSE);
			}
		}
	#
	# Pass the built structure back
	#					
	return $pLegacyStructure;
	}

################################################################
#
#  Element->GetNodeValue() - returns the value of this text node
#
#  Output: the _CONTENT key of the hash
#
################################################################

sub GetNodeValue
	{
	my $Self  = shift;
#? ACTINIC::ASSERT($Self->IsTextNode(), "Function Element::GetNodeValue operates only on text nodes", __LINE__, __FILE__);
	#
	# Return the content string
	#					
	return $Self->{_CONTENT};		
	}

################################################################
#
#  Element->SetNodeValue() - sets the value of this text node
#
#  Input: 0 - the new content of the element
#
################################################################

sub SetNodeValue
	{
	my $Self  = shift;
	my $sValue = shift;									# the new string value of this text node
	#
	# Set the content string
	#					
	$Self->{_CONTENT} = $sValue;		
	}

################################################################
#
#  Element->GetTag() - returns the tag name of this element
#
#  Output: 0 - the tag name of the element
#
################################################################

sub GetTag
	{
	my $Self  = shift;
	#
	# Return the tag name
	#					
	return $Self->{_TAG};		
	}

################################################################
#
#  Element->SetTag() - sets the tag name of this element
#
#  Input: 0 - the new tag name of the element
#
################################################################

sub SetTag
	{
	my $Self  = shift;
	my $sTag = shift;										# new tag name
	#
	# Set the tag name
	#					
	$Self->{_TAG} = $sTag;		
	}	
	
################################################################
#
#  Element->GetAttribute() - 	gets the value of the specified attribute
#
#  Input: 		0 - name of the attribute
#
#	Output: 		0 - value of the attribute
#
################################################################

sub GetAttribute
	{
	my $Self  = shift;
	my $sName = shift;									# attribute name
	#
	# Return the attibute value
	#					
	return $Self->{_PARAMETERS}->{$sName};		
	}	

################################################################
#
#  Element->SetAttribute() - 	adds a new attribute to this
#										element node or sets an existing one
#
#  Input:	 	0 - name of the attribute
#					1 - value of the attribute
#
################################################################

sub SetAttribute
	{
	my $Self  = shift;
	my $sName = shift;									# attribute name
	my $sValue = shift;									# attribute value
	#
	# Add or set the attibute
	#					
	$Self->{_PARAMETERS}->{$sName} = $sValue;		
	}	

################################################################
#
#  Element->SetAttributes() - 	add a set of attributes to this
#										element node or sets an existing one
#
#  Input: 0 - hash of attributes
#
################################################################

sub SetAttributes
	{
	my $Self  	= shift;
	my $hValues = shift;									# attribute value
	#
	# Add or set the attibutes
	#	
	my $sKey;
	foreach $sKey (keys %{$hValues})
		{
		$Self->{_PARAMETERS}->{$sKey} = $$hValues{$sKey};		
		}
	}	
	
################################################################
#
#  Element->GetOriginal() - 	gets the value of the specified attribute
#
#	Output: 		0 - the value 
#
# 	Author:		Zoltan Magyar, 8:33 PM 3/13/2002
#
################################################################

sub GetOriginal
	{
	my $Self  = shift;
	#
	# Return the original value
	#					
	return $Self->{_ORIGINAL};		
	}	
	
1;