#!<Actinic:Variable Name="PerlPath"/>
#######################################################
#																		#
# MailScript.pl - provides mail support for Catalog	#
#																		#
# Copyright (c) 2001 ACTINIC SOFTWARE Plc					#
#																		#
# Written by Zoltan Magyar 									#
# March 31 2001													#
#																		#
#######################################################

#######################################################
#                                                     #
# The above is the Path to Perl on the ISP's server   #
#                                                     #
# Requires Perl version 5.0 or later                	#
#                                                     #
#######################################################

#######################################################
#                                                     #
# PROBLEM SOLVING                                     #
#                                                     #
# This script has been successfully tested on a large #
# number of different computer systems and servers.   #
#                                                     #
# Listed below are the most common reasons why this   #
# script may fail to operate correctly:               #
#                                                     #
# This cgi script MUST be installed in the 'CGI-BIN'  #
# directory allocated to the user on server of the    #
# Internet Service Provider.                          #
#                                                     #
# The script MUST be uploaded to this directory as    #
# an ASCII file. Do NOT use the 'AUTO' option in your #
# FTP program for the type of file upload . We have   #
# found that some of these FTP programs default to an #
# incorrect upload format.                            #
#                                                     #
# If you receive any error messages from the server,  #
# usually with an error code of 500 or 501, then the  #
# cause will usually be that this file has been sent  #
# to the server using the wrong transfer mode. To     #
# this please re-upload this file as an ASCII file.   #
#                                                     #
# The file permissions need to be correctly set on    #
# this file when it is installed on UNIX servers.     #
# These permissions need to be set as 'rwx r-x r-x'   #
# which equates to a file mask of '755'. These can    #
# usually be easily set via your FTP program.         #
#                                                     #
#######################################################

#######################################################
#                                                     #
# This script creates INTERNAL ERROR CODES, when		#
# needed, whilst it is running.  These error codes		#
# are stored as relatively meaningful text strings		#
# and are logged to the error file error.err in the	#
# $path directory.  These errors are stored in        #
# $::g_sInternalErrors.											#
#                                                     #
#######################################################
#                                                     #
# This script produces the following ACTINIC STATUS   #
# CODES, when needed, whilst it is running.  These		#
# status codes are returned to the calling				#
# application.	 Any changes or additions to this list	#
# must be reflected in the error processing of the C++#
#                                                     #
# Error Code	Category			Description					#
#																		#
#     200  -  OK           -  everything is OK        #
#     450  -  PASSERROR    -  unable to open config   #
#     451  -  PASSERROR    -  user not found in config#
#     453  -  PASSERROR    -  password wrong          #
# 		580  -  EMAIL			-  invalid address			#
#		581  -  EMAIL			-  invalid mail input data	#
#		582  -  EMAIL			-  empty mail					#
#		583  -  EMAIL			-  SMTP error					#
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

Init();
DispatchCommands();
exit;

#######################################################################################
##########################THIS IS THE END OF THE MAIN##################################
#######################################################################################

sub Init
	{
	$::prog_name = "MailScript";							# Program Name (8 characters)
	$::prog_ver = '$Revision: 18819 $';						# ' <emacs formatting> # program version (6 characters)
	$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
	$::prog_ver =~ s/ \$//;									# and the trailers

	$::FALSE = 0;
	$::TRUE = 1;
	$::DOS_SLEEP_DURATION = 2;

	$::FAILURE 	= 0;
	$::SUCCESS 	= 1;
	$::NOTFOUND = 2;

	umask (0177);

	$::g_nErrorNumber = 200;								# Set $::g_nErrorNumber to 'OK'
	$::PAD_SPACE = " " x 40;								# Set $::PAD_SPACE to 40 blank spaces

	$::g_sSmtpServer 	  = '<Actinic:Variable Name="SmtpServer"/>';
	$::g_bPathKnown = 0;										# path unknown by default.  This flag tracks whether or not it is safe to log errors to error.err file.
	#
	# Read the input strings.  
	#
	my ($status, $sError, $sEnv, $unused);
	($status, $sError, $sEnv, $unused, %::g_InputHash) = ACTINIC::ReadAndParseInput();	
	if ($::SUCCESS != $status)
		{
		$::g_sInternalErrors .= "Input is invalid ";	# Record internal error 
		$::g_nErrorNumber = 581;							# Also record a standard error
		RecordErrors();										# Write errors to error.err
		SendResponse();										# Send the response to the user
		exit;
		}
	#
	# Validate the input data
	#
	ValidateInput();
	#
	# Authenticate the user
	#
	($status, $sError) = ACTINIC::AuthenticateUser($::g_InputHash{USER}, $::g_InputHash{PASS});
	if ($status != $::SUCCESS)
		{
		$::g_sInternalErrors .= "Authentication failed ($::g_InputHash{USER}, $::g_InputHash{PASS}), ";	# Record internal error 
		$::g_nErrorNumber = 453;							# Also record a standard error
		RecordErrors();										# Write errors to error.err
		SendResponse();										# Send the response to the user
		exit;
		}	
	$::g_sPath = ACTINIC::GetPath();						# retrieve the path
	ACTINIC::SecurePath($::g_sPath);						# make sure there is nothing funny going on		
	#
	# Note the mode
	#
	$::g_bActinicHostMode = <Actinic:Variable Name="ActinicHostMode"/>;
	# 
	# Check the path - we authenticate the path here for stand-alone catalogs because we want to do it as early as possible to support
	# proper error logging.  We can't do it for Host catalogs yet because the path lookup has not occurred yet.
	#
	if (!$::g_bActinicHostMode)							# stand alone mode
		{
		if (! -e $::g_sPath)									# if the path does not exist
			{
			$::g_sInternalErrors .= "path does not exist :$::g_sPath:, "; # Record internal error 
			$::g_nErrorNumber = 542;						# Also record a standard error
			$::g_bPathKnown = 0;								# path unknown
			}
		elsif (! -r $::g_sPath)								# if the path is not readable
			{
			$::g_sInternalErrors .= "path is not readable :$::g_sPath:, "; # Record internal error 
			$::g_nErrorNumber = 543;						# Also record a standard error
			$::g_bPathKnown = 0;								# path unknown
			}
		else
			{
			$::g_bPathKnown = 1;								# path is OK
			}
		}
	#
	# Set up the version and dayno as a global
	#
	$::g_sVersionDayno = '';
	#
	# Make sure the action was expected
	#
	my %SupportedCommands = map { $_ => 1 } qw ( send );
	unless ($SupportedCommands{$::g_InputHash{ACTION}})	# We will only get to here if ACTION contains an 
		{															# illegal value so we
		$::g_sInternalErrors .= "unknown command :$::g_InputHash{ACTION}:, ";	# Record internal error 
		$::g_nErrorNumber = 456;							# Also record a standard error
		RecordErrors();										# Write errors to error.err
		SendResponse();										# Send the response to the user
		exit;
		}
	#
	# Check overall data validity - error and exit if we have already run across an error
	#
	if ($::g_sInternalErrors ne '')						#  Bail if there are errors at this point
		{
		RecordErrors();										# Write errors to error.err
		SendResponse();										# Send the response to the user
		exit;
		}
	}

##########################################################
#																			#
# DispatchCommands - process input as required				#
#																			#
##########################################################

sub DispatchCommands
	{
	#
	# SEND - send mails
	#
	if ($::g_InputHash{ACTION} eq "send")
		{
		#
		# Enable prompts first
		#
		my @Response = ACTINIC::ReadPromptFile($::g_sPath);
		if ($Response[0] == $::SUCCESS)
			{
			#
			# Try to send mail
			#
			@Response = ACTINIC::SendRichMail($::g_sSmtpServer, $::sMailTo, $::sMailSubject, $::sMailText, $::sMailHTML, $::sMailReturn);
			if ($Response[0] != $::SUCCESS)
				{	
				$::g_sInternalErrors .= $Response[1]; # Record internal error 
				$::g_nErrorNumber = 583;	
				$::g_Answer = $::sMailTo;
				}
			}
		else
			{
			$::g_sInternalErrors .= $Response[1]; # Record internal error 
			$::g_nErrorNumber = 999;	
			$::g_Answer = $::sMailTo;
			}
		$::g_OutputData = $Response[1];
		}
	#
	# Check for an EXCEPTIONAL ERROR
	#
	else															# An exceptional error must have occurred to get here 
		{
		$::g_sInternalErrors .= "script exception, "; # Record internal error 
		$::g_nErrorNumber = 999;							# Also record a standard error
		$::g_Answer = $::sMailTo;							# Record the file name for returning to user
		}
	#
	# Finish Off
	#
	RecordErrors();											# Write errors to error.err
	SendResponse();											# Send the response to the user
	}

#######################################################
#                                                     #
# RecordErrors  - wrapper for ACTINIC::RcordErrors  	#
# Record any errors, only if they exist               #
#                                                     #
#   Check the top of the file for error codes...      #
#                                                     #
#######################################################

sub RecordErrors
	{
	if ( (length $::g_sInternalErrors) > 0 &&		# if there are any errors
		  $::g_bPathKnown)								# and we know where to stick the error log
		{
		ACTINIC::RecordErrors($::g_sInternalErrors, $::g_sPath);
		}
	}
	
#######################################################
#                                                     #
# ValidateInput -		                                 #
#    validates the script input and store errors   	#
# Note that this function also initialise some global	#
# variables of input data										#
#                                                     #
#######################################################

sub ValidateInput
	{
	$::sMailTo			= $::g_InputHash{TO}; 
	$::sMailSubject	= $::g_InputHash{SUBJECT};
	$::sMailReturn		= $::g_InputHash{RETURN};
	$::sMailText		= $::g_InputHash{TEXTDATA};
	$::sMailHTML		= $::g_InputHash{HTMLDATA};
	#
	# Verify data length for security
	#
	if ( (length $::sMailTo) < 5)						# the mail address should be at least 5 chars (a@b.c)
		{
		$::g_sInternalErrors .= "E-mail address too short (" . ($::sMailTo) . "), ";	# Record internal error
		$::g_nErrorNumber = 580;						# Also record a standard error
		}
	if ((length $::sMailText) == 0 &&				# empty mail?
		 (length $::sMailHTML) == 0)
		{
		$::g_sInternalErrors .= "The mail content is not defined (can't send empty mails) ";	# Record internal error
		$::g_nErrorNumber = 582;						# Also record a standard error		
		}	
	#
	# The empty HTML content is extended by a space if passed as last parameter
	# so check this condition
	#
	if ($::sMailHTML eq ' ')
		{
		$::sMailHTML = '';
		}
	if ( (length $::g_InputHash{USER}) > 12)
		{
		$::g_sInternalErrors .= "Parameters too large, user too long (" . (length $::g_InputHash{USER}) . "), ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}

	if ( (length $::g_InputHash{PASS}) > 12)
		{
		$::g_sInternalErrors .= "Parameters too large, password too long (" . (length $::g_InputHash{PASS}) . "), ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}
	}

#######################################################
# SendResponce                                        #
# Send back the ANSWER to the user                    #
#                                                     #
# $::g_nErrorNumber will contain a 3 character ACTINIC#
# error/status code                                   #
#                                                     #
# $::g_Answer consist of a variable length string    	#
#                                                     #
# If the query was a lookup, then also return the     #
# number of files that matched the query string.      #
#                                                     #
# Any further characters in $::g_Answer will represent#
# the contents of the file with this filename         #
#                                                     #
#######################################################

sub SendResponse
	{
	if ($::g_Answer eq "")									# If $::g_Answer is not set to any value (due to an error occurring)  
		{
		$::g_Answer = substr($::PAD_SPACE,0,16);		# Set $::g_Answer to 16 blank characters
		} 

	my $SRAnswerLength = length $::g_Answer;		# get the answer length (which is almost always a filename)
	if ($SRAnswerLength < 10)							# if the length is single digits, zero buffer
		{
		$SRAnswerLength = "0".$SRAnswerLength;
		}
	elsif ($SRAnswerLength > 99 ||
			 $SRAnswerLength < 1)
		{
		$::g_sInternalErrors .= "Answer is too small or too large, ";
		RecordErrors();
		}

	my $SResponse = $::g_nErrorNumber.$SRAnswerLength.$::g_Answer.$::g_OutputData;	# generate the complete response message
	
	binmode STDOUT;										# the return message is binary so the data is not corrupted
	ACTINIC::PrintHeader('application/octet-stream', (length $SResponse), undef, $::FALSE);
	print $SResponse;										# send the user data
	}

