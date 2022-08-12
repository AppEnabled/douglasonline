#!<Actinic:Variable Name="PerlPath"/>  
#-d:ptkdb

use strict;
use Socket;

#######################################################
#                                                     #
# The above is the Path to Perl on the ISP's server   #
#                                                     #
# Requires Perl version 5.0 or later                	#
#                                                     #
#######################################################

#######################################################
#
# CATALOG CGI/PERL SCRIPT
#
# Copyright (c) 2000 ACTINIC SOFTWARE Plc
#
# written by George Menyhert
#
#######################################################

$::prog_name = "CATALOG";								# Program Name (8 characters)
$::prog_ver = '$Revision: 23357 $';						# ' <emacs formatting> # program version (6 characters)
$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
$::prog_ver =~ s/ \$//;									# and the trailers

$::FALSE = 0;
$::TRUE = 1;
$::DOS_SLEEP_DURATION = 2;

$::FAILURE 	= 0;
$::SUCCESS 	= 1;
$::NOTFOUND = 2;
$::FAILEDSEARCH = $::NOTFOUND;						# synonyms
$::EOF		= 3;
$::EOB     	= 4;
$::BADDATA	= 5;
$::WARNING	= 6;
$::ACCEPTED	= 7;
$::REJECTED	= 8;
$::PENDING	= 9;

#######################################################
#                                                     #
# This CGI program is designed to work in conjunction #
# with the CATALOG programs running at the supplier  	#
# site and the applet running at a buyer site.        #
#                                                     #
# It is the "honest broker" between these programs.   #
#                                                     #
# It is designed to have the minimum functionality in #
# order to make it easier to run across multiple      #
# platforms and also in order to make it acceptable   #
# to all Internet Service Providers.                  #
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

umask (0177);

$::g_nErrorNumber = 200;								# Set $::g_nErrorNumber to 'OK'
$::g_sErrorFilename = "error.err";					# Set $::g_sErrorFilename name
$::PAD_SPACE = " " x 40;								# Set $::PAD_SPACE to 40 blank spaces

$::g_sDaemonAddress = '<Actinic:Variable Name="DaemonAddress"/>';		# set daemon address (used only in host mode)
$::g_nDaemonPort    = '<Actinic:Variable Name="DaemonPort"/>';	# set daemon port (used only in host mode)

#######################################################
#
# path is the Path to the user's home directory,
# which is the directory where the data files will
# reside.
#
# This Path is hard coded into the script to prevent
# any possible user errors or misuse.
#
# At Actinic Host sites, this path is actually the path
# to the shops data file.
#
#######################################################

$::g_bPathKnown = 0;										# path unknown by default.  This flag tracks whether or not it is safe to log errors to error.err file.
$::g_sPath = '<Actinic:Variable Name="PathFromCGIToWeb"/>';						# Set directory path
$::g_sAlternatePath = '<Actinic:Variable Name="AlternatePath"/>';	# alternate path controlled by customvar
$::g_bUseAlternatePath = <Actinic:Variable Name="UseAlternatePath"/>;
SecurePath($::g_sPath, 459);							# make sure only valid filename characters exist in $::g_sPath to prevent hanky panky
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
# Now read the input.  On no input, just print a "Script Error" message
#
if ($ENV{CONTENT_LENGTH} > 0)
	{
	ReadAndParseHTTP();								# Read the http call information
	}
elsif ($ENV{QUERY_STRING} eq 'getordernum')
	{
	GetOrderNum();
	SendResponse();
	exit;
	}
else														# no data - must be query from web page with no data
	{
	my ($sMessage) = "<HTML>\n" .
		"<HEAD><TITLE>Script Error!</TITLE></HEAD>\n" .
		"<BODY>\n" .
		"<BLINK><B><FONT COLOR=\"\#FF0000\">\n" .
		"Script Error" .
		"</FONT></B></BLINK>\n" .
		"</BODY>\n" .
		"</HTML>\n";

	PrintHeader('text/html', length $sMessage, undef, $::FALSE);
	binmode STDOUT;
	print $sMessage;

	exit;
	}

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

#######################################################
#                                                     												#
# This script produces the following ACTINIC STATUS  								#
# CODES, when needed, whilst it is running.  These										#
# status codes are returned to the calling												#
# application.	 Any changes or additions to this list										#
# must be reflected in the error processing of the C++									#
#                                                     												#
# Error Code	Category			Description											#
#																				#
#    200  -  OK           		-  everything is OK		        							#
#    250  -  NOTEXIST 	-  filename is NULL        									#
#    251  -  NOTEXIST 	-  filename contains wildcard									#
#	252  -  PERMERROR	-  can't access file due  to the file permissions 					#
#    254  -  NOTEXIST 	-  can't find file         										#
#    255  -  DUPLICATE  	-  file already exists     									#
#    450  -  PASSERROR 	-  unable to open config   									#
#    451  -  PASSERROR 	-  user not found in config									#
#    453  -  PASSERROR 	-  password wrong          									#
#    454  -  NOTFOUND 	-  on LOOKUP no files match								#
#    455  -  SYNTAX    	-  contains invalid syntax 									#
#    456  -  SYNTAX   		-  no/invalid command sent 									#
#    457  -  SYNTAX  		-  create or append command is missing a filename 				#
#    458  -  SYNTAX       	-  create or append command is missing data for file contents 		#
#	459  -  SYNTAX       	-  path contains invalid characters							#
#	460  -  SYNTAX       	-  filename contains invalid characters							#
#    540  -  OPENERROR   	-  file open error,	permissions or invalid name 					#
#    541  -  DIRERROR     	-  error reading the dir										#
#	542  -  PATHERROR	-  the path specified does not exist							#
#	543  -  PATHREAD		-  the specified path is  not readable							#
#    550  -  OTHER        	-  internal program error  									#
#    551  -  FILEXTN      	-  invalid file extension  									#
#    553  -  DISKSPACE    	-  out of disk space       									#
#    554  -  CHECKSUM     	-  file checksum incorrect 									#
#                                                     												#
#	560  -  DAEMON		- 	AHDClient.pm not found									#
#	561  -  DAEMON		-  Can't connect											#
#	562  -  DAEMON		-  Invalid user											#
#	563  -  DAEMON		- 	expired account										#
#	564  -  DAEMON		- 	host data error on login									#
#	565  -  DAEMON		-  other error on login										#
#	566  -  DAEMON		-  delete failed - host data error								#
#	567  -  DAEMON		-  delete failed - permission problems							#
#	568  -  DAEMON		-  delete failed - file doesn't exist							#
#	569  -  DAEMON		-  delete failed - other problems								#
#	570  -  DAEMON		-  create failed - other problems								#
#	571  -  DAEMON		-  create failed - host data error								#
#	572  -  DAEMON		-  create failed - permission problems							#
#	573  -  DAEMON		-  create failed - invalid file data								#
#	584  -  ORDERNUM	- can't copy												#
#																				#
# 	600 -  STOCK 		- can't locate Stock Manager library							#
# 	601 -  STOCK 		- stock balance file update error								#
#																				#
#     999  -  EXCEPTION    -  exceptional error       									#
#                                                     												#
#######################################################

$::g_sErrorFilename = $::g_sPath . 'error.err'; # append the path to the
																# error file here because the path may
																# not have been defined before this point
																# if we are running in web host mode
#
# Make sure the action was expected
#
my %SupportedCommands = map { $_ => 1 } qw ( stockempty stocksend create getkey getordernum setordernum lookup lookrt shopid delete version date list trial baseurl rename getservertime extract);
unless ($SupportedCommands{$::g_sAction})			# We will only get to here if $::g_sAction contains an
	{															# illegal value so we
	$::g_sInternalErrors .= "unknown command :$::g_sAction:, ";	# Record internal error
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

################################################################
# Begin to PROCESS DATA according to users requested ACTION    #
################################################################


#######################################################
# Set correct PATH and add to filename                #
#######################################################

$::g_sFilename = $::g_sPath . $::g_sFilenameBase . '.' . $::g_sFilenameExtension; # Set PATH & filename
#
# STOCKSEND - update stock balance file with the data passed in
#
if ($::g_sAction eq "stocksend")
	{
	StockSend();
	}
#
# STOCKSEND - update stock balance file with the data passed in
#
elsif ($::g_sAction eq "stockempty")
	{
	StockEmpty();
	}
#
# CREATE a file
#
elsif ($::g_sAction eq "create")
	{
	CreateFile();
	}
#
# GETKEY - get the public key of the site
#
elsif ($::g_sAction eq "getkey")
	{
	GetPublicKey();
	}	
#
# GETORDERNUM - retrieve the order number from the lock file
#
elsif ($::g_sAction eq "getordernum")
	{
	GetOrderNum();
	}
#
# SETORDERNUM - adjust the content of the order lock file
#
elsif ($::g_sAction eq "setordernum")
	{
	SetOrderNum();
	}	
#
# LOOKUP a file and maybe RETURN the contents
#
elsif (substr($::g_sAction,0,4) eq "look")				# Action equals "Lookup" or "Lookrt"
	{
	LookUpAndRetrieve();
	}
#
# DELETE a file
#
elsif ($::g_sAction eq "delete")								# Action equals Delete a file
	{
	DeleteFile();
	}
#
# RENAME a file
#
elsif ($::g_sAction eq "rename")								# Action equals Delete a file
	{
	RenameFile();
	}
#
# VERSION - retrieve the anticipated script version
#
elsif ($::g_sAction eq "version")
	{
	my $s_scriptVersionDayno = "100 KDYA";	# script version and dayno
	if ($::g_sVersionDayno ge $s_scriptVersionDayno)
		{
		#
		# If client is current or later, return the script version
		#
		$::g_OutputData = $s_scriptVersionDayno;
		}
	else
		{
		#
		# For older clients, just echo the client version back
		#
		$::g_OutputData = $::g_sVersionDayno;
		}
	}
#
# date - retrieve the dates of selected files
#
elsif ($::g_sAction eq "date")
	{
	GetFileDate();
	}
#
# list - retrieve a listing of the specified files
#
elsif ($::g_sAction eq "list")
	{
	GetFileList();
	}
#
# trial - return the trial account state
#
elsif ($::g_sAction eq "trial")
	{
	$::g_OutputData = $::g_bTrial ? '1' : '0';	# return the trial state
	}
#
# Retrieve information from the configuration
#
elsif ($::g_sAction eq "shopid")						# Action equals retrieve configuration information
	{
	if ($::g_bActinicHostMode)							# we must be in web host mode for this
		{
		$::g_OutputData = $::g_sShopID;				# return the shop ID
		}
	}
#
# Send Catalog URL from Shop Data file
#
elsif ($::g_sAction eq "baseurl")					# Action equals retrieve configuration information
	{
	if ($::g_bActinicHostMode)							# we must be in web host mode for this
		{
		$::g_OutputData = $::g_sBaseURL;				# return the Catalog URL
		}
	}
#
# GETSERVERTIME - Gets the server time in sec's
# Refer to Cat7_Des_Processing Enhancements.doc sec: 3.2.10
# time() implementation depeneds on host OS. It specifically different in MacOS
# which is not been taken care here, as Server on MacOS was not available for 
# testing. Fix need to be done for MacOS 
#
elsif ($::g_sAction eq "getservertime")
	{
	my ($now);
	$now = time;
	$::g_OutputData = $now;                 #return the Server time
	}
#
# Extract compressed file
#
elsif ($::g_sAction eq "extract")
	{
	ExtractFile();
	}
#
#
# Check for an EXCEPTIONAL ERROR
#
else															# An exceptional error must have occurred to get here
	{
	$::g_sInternalErrors .= "script exception, "; # Record internal error
	$::g_nErrorNumber = 999;							# Also record a standard error
	$::g_Answer = $::g_sFilename;						# Record the file name for returning to user
	}
#
# Finish Off
#
RecordErrors();											# Write errors to error.err
SendResponse();											# Send the response to the user

exit;

#######################################################################################
##########################THIS IS THE END OF THE MAIN##################################
#######################################################################################

#######################################################
#   ReadAndParseHTTP	                                 #
#         read the http header and data, then parse it#
#                                                     #
#######################################################

sub ReadAndParseHTTP
	{
	#
	# Read the data sent from Catalog
	#
	binmode STDIN;
	my ($nStep, $InputBuffer, $InputData);
	$nStep = 0;
	while ((length $InputData) != $ENV{'CONTENT_LENGTH'})	# read until you have the entire chunk of data
		{
		#
		# read the input
		#
		$nStep = read(STDIN, $InputBuffer, $ENV{'CONTENT_LENGTH'});  # Set $InputData equal to user input
		$InputData .= $InputBuffer;					# append the latest chunk to the total data buffer
		if (0 == $nStep)									# EOF
			{
			last;												# stop read
			}
		}

	if ((length $InputData) != $ENV{'CONTENT_LENGTH'})
		{
		$::g_sInternalErrors .= "Some of the HTTP data is missing $::g_nLength != " . $ENV{'CONTENT_LENGTH'} . ", ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}
	#
	# Note:  As it stands today, the Catalog PerlScript
	# interface does not adhere to the normal CGI calling
	# method (e.g. ?a=b&c=d).  One reason for this is because
	# that method requires encoding the data.  Since we transmit large binary files
	# encoding would bloat the transfer.
	#
	# The format of the Catalog data is
	# <username> <password> <client major version> <client dayno> <command> <file length> <file> <remaining data>
	#
	my ($sUser, $sPassword, $nFilenameLength, $Data, $nMajorVersion, $sDayno);

	if ($InputData !~ /^(\w+) (\w+) ([.0-9]+) (\w+) (\w+) (\d+) (.*)/s)
		{
		$::g_sInternalErrors .= "Catalog data format invalid, ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		return;
		}
	($sUser, $sPassword, $nMajorVersion, $sDayno, $::g_sAction, $nFilenameLength, $Data) = ($1, $2, $3, $4, $5, $6, $7);
	#
	# Save the version and dayno
	#
	$::g_sVersionDayno = "$nMajorVersion $sDayno";

	$::g_sFilename = substr($Data, 0, $nFilenameLength); # read the filename
	SecurePath($::g_sFilename, 460);					# make sure only valid filename characters exist in $::g_sFilename to prevent hanky panky
	$::g_UserData = substr($Data, $nFilenameLength + 1); # trim off the filename

	my (@sFields) = split(/\./, $::g_sFilename);	 # Extract the file name and extension from $::g_sFilename
	$::g_sFilenameExtension = pop @sFields;
	$::g_sFilenameBase = join('.',@sFields);
	$::g_sFilenameExtension =~ s/ //g;				# Remove any extraneous spaces from $::g_sFilenameExtension

	if ($::g_sFilenameBase =~ /\.\./ ||				# if the caller is trying to access something outside of the web space
		 $::g_sFilenameBase =~ /:/ 	 ||
		 $::g_sFilenameBase =~ /\// 	 ||
		 $::g_sFilenameBase =~ /\\/ 	 )
		{														# foil the plans
		$::g_sInternalErrors .= "Attempt to access file outside of web space, ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}

	if ($::g_sFilenameExtension =~ /\.\./ ||		# if the caller is trying to access something outside of the web space
		 $::g_sFilenameExtension =~ /:/ 	 ||
		 $::g_sFilenameExtension =~ /\// 	 ||
		 $::g_sFilenameExtension =~ /\\/ 	 )
		{														# foil the plans
		$::g_sInternalErrors .= "Attempt to access file outside of web space, ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}
	#
	# Verify data length for security
	#
	if ( (length $sUser) > 12)
		{
		$::g_sInternalErrors .= "Parameters too large, user too long (" . (length $sUser) . "), ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}

	if ( (length $sPassword) > 12)
		{
		$::g_sInternalErrors .= "Parameters too large, password too long (" . (length $sPassword) . "), ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}

	if ($nFilenameLength > 10240)
		{
		$::g_sInternalErrors .= "Parameters too large, filename too long (" . (length $nFilenameLength) . "), ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		}

	if ((length $::g_UserData) < 1 &&				# Check that user input data exists and if not
		  $::g_sAction eq "create")
		{
		$::g_UserData = "NO DATA SENT";				# Write an error message and
		$::g_sInternalErrors .= "No message sent $::g_nLength, "; # Record internal error
		$::g_nErrorNumber = 458;						# Also record a standard error
		}
	#
	# Set alternate location for ord and occ files
	#
	if(!$::g_bActinicHostMode && 						# not in host mode
		$::g_bUseAlternatePath &&						# and we have alternate path
		($::g_sFilenameExtension eq "ord" ||		# if this is an order
		$::g_sFilenameExtension eq "occ" ||			# 	or auth file
		$::g_sFilenameExtension eq "session"))
		{
		$::g_sPath = $::g_sAlternatePath;
		}
	#
	# Authenticate the account
	#
	AuthenticateUser($sUser, $sPassword);
	}

#######################################################
#																				#
# CreateFile - Create the given file                  										#
#																				#
#######################################################

sub CreateFile
	{
	if ($::g_sFilenameBase eq "")						# So we Check for valid file name and, if not, we must
		{
		$::g_sInternalErrors .= "no filename given for CREATE, ";	# Record internal error
		$::g_nErrorNumber = 457;						# Also record a standard error
		$::g_Answer = $::g_sFilename;						# Record the file name for returning to user
		return;
		}
	#
	# try to remove any existing file
	#
	if (-e $::g_sFilename)								# if the file exists
		{
		chmod(0666, $::g_sFilename);					# change the permission on the file
		unlink($::g_sFilename);							# delete the file
		}

	my $uSum = substr($::g_UserData, 0, 12);
	my $sFileContents = substr($::g_UserData, 12);
	my $uTotal;
		{
		use integer;
		$uTotal = unpack('%32C*', $sFileContents);
		}
	if ($uTotal != $uSum)
		{
		$::g_sInternalErrors .= "corrupt file transfer: local($uTotal) != remote($uSum) " . substr($sFileContents, 0, 10) . "| " . length ($sFileContents) . ", ";	# Record internal error
		$::g_nErrorNumber = 554;						# Also record a standard error
		return;
		}
	if (!$::g_bActinicHostMode)						# In standalone catalog mode. Do direct file operations.
		{
		if (open(NQFILE, ">" . $::g_sFilename))	# create it and
			{
			binmode NQFILE;								# make sure the file is in binary mode
			unless(print NQFILE ($sFileContents))	# write the data to it
				{
				$::g_sInternalErrors .= "out of disk space, ";	# Record internal error
				$::g_nErrorNumber = 553;				# Also record a standard error
				}
			$::g_Answer = $::g_sFilename;				# Record the file name for returning to user
			close (NQFILE);
			}
		else
			{
			$::g_sInternalErrors .= "unable to create $::g_sFilename $!, ";	# Record internal error
			$::g_nErrorNumber = 540;					# Also record a standard error
			$::g_Answer = $::g_sFilename;				# Record the file name for returning to user
			}
		chmod(0644, $::g_sFilename);					# change the permission on the file
		}
	else														# In host mode. Use the daemon library.
		{
		eval
			{
			require AHDClient;							# load the library
			};
		if ($@)
			{
			$::g_sInternalErrors .= "unable to load the daemon client library ($@)";
			$::g_nErrorNumber = 560;
			return;
			}
			my ($nStatus, $sError, $pClient) = new AHDClient($::g_sDaemonAddress, $::g_nDaemonPort, '<Actinic:Variable Name="PathFromCGIToWeb"/>');
			if ($nStatus != $::SUCCESS)
				{
				$::g_sInternalErrors .= "Unable to connect to the Host Daemon. $sError\n";
				$::g_nErrorNumber = 561;
				return;
				}
			($nStatus, $sError) = $pClient->SetUsernameAndPassword($::g_sUsername, $::g_sPassword);
			if ($nStatus != $::SUCCESS)
				{
				$::g_sInternalErrors .= "Unable to log in to the Host Daemon. $sError\n";
				if ($sError == 201)
					{
					$::g_nErrorNumber = 562;			# invalid username/password
					}
				elsif ($sError == 290)					# host data error
					{
					$::g_nErrorNumber = 564;			# host data error during login
					}
				else
					{
					$::g_nErrorNumber = 565;			# other error during login
					}
				return;
				}
			my $sName = $::g_sFilenameBase.".".$::g_sFilenameExtension;
			unlink($::g_sFilename);						# try to delete any previous file directly
			if (-e $::g_sFilename)						# or by the host daemon
				{
				($nStatus, $sError) = $pClient->DeleteFile($sName);
				if ($nStatus != $::SUCCESS)
					{
					$::g_sInternalErrors .= "Unable to delete file. $sError\n";
					if ($sError == 815)						# shop has been expired
						{
						$::g_nErrorNumber = 563;
						}
					elsif ($sError == 817)					# host data error
						{
						$::g_nErrorNumber = 566;
						}
					elsif ($sError == 860)					# permission problems
						{
						$::g_nErrorNumber = 567;
						}
					elsif ($sError == 861)					# file doesn't exist
						{
						$::g_nErrorNumber = 568;
						}
					else											# some other problem
						{
						$::g_nErrorNumber = 569;
						}
					return;
					}
				}
			($nStatus, $sError) = $pClient->CreateFile($sName, $sFileContents);
			if ($nStatus != $::SUCCESS)
				{
				$::g_sInternalErrors .= "Unable to create file. $sError\n";
				if ($sError == 815)							# shop has been expired
					{
					$::g_nErrorNumber = 563;
					}
				elsif ($sError == 817)						# host data error
					{
					$::g_nErrorNumber = 571;
					}
				elsif ($sError == 820)						# permission problems
					{
					$::g_nErrorNumber = 572;
					}
				elsif ($sError == 811)						# invalid file data
					{
					$::g_nErrorNumber = 573;
					}
				else												# some other problem
					{
					$::g_nErrorNumber = 570;
					}
				return;
				}
		$pClient->RecordClientVersions({UploadVersion=>'<Actinic:Variable Name="ActinicScriptRelease"/>'});
		}
	}

######################################################
# LookUpAndRetrieve                                   #
#    Find the first file that matches the string and  #
#    optionally return the data contained in it.      #
#######################################################

sub LookUpAndRetrieve
	{
	my ($nFoundCount, $sOldErrors);
	$nFoundCount = 0;

	$sOldErrors = $::g_sInternalErrors;				# backup copy of the current error list

	my @listFile = ReadTheDir($::g_sPath);			# read the directory

	if ($::g_sInternalErrors eq $sOldErrors)		# if there were no problems reading the directory
		{
		my ($sFile, $sBase, $sExtension);

		@listFile = sort (@listFile);					# Sort the file names list

		foreach $sFile (@listFile)						# Look at each file name and
			{
      	#
      	# extract the file name  and extension
      	#
			if ($sFile =~ /\.([^\.]+)$/)				# does it match?
				{
				$sBase = $`;								# separate file name
				$sExtension = $1;							# and extension
				}
			else
				{
				next;											# No extension, don't bother
				}

			if ($sExtension eq $::g_sFilenameExtension ) # Check file extension matches
				{
				if ($sBase =~ /^$::g_sFilenameBase/)	# See if there are any matches
					{
					$::g_Answer = $::g_sPath.$sFile;		# Record the file name for returning to user
																# $::g_sPath is added here and removed later
					$nFoundCount++;						# The increment the number of matching files
					}
				}
			}

		if ($::g_Answer eq "")								# If no matches were found so we
			{
			$::g_nErrorNumber = 454;					# record a standard error
			$::g_Answer = $::g_sFilename;					# Record the file name for returning to user
			$::g_OutputData = "0";						# no files found
			}
		else													# Otherwise if we found a match
			{
			if ($::g_sAction eq "lookrt")				# Read data if $::g_sAction is "lookrt"
				{
				if($::g_sFilenameExtension eq "ord" ||	# if this is an order
					$::g_sFilenameExtension eq "inf")	# 	or information
					{
					chmod(0666, $::g_Answer);				# change the permission on the file
					}

				if (open(NQFILE, "<$::g_Answer"))			# Open the matching file
					{
					my ($Buffer);
					binmode NQFILE;						# make sure the file is in binary mode
					while ( read (NQFILE, $Buffer, 16384) )
						{
						$::g_OutputData .= $Buffer;	# Read data from the data file
						}
					close (NQFILE);
					#
					# add the checksum to the data
					#
						{
						use integer;
						$::g_OutputData = sprintf('%12d', unpack('%32C*', $::g_OutputData)) . $::g_OutputData;
						}
					}
				else											# error opening the file
					{
					$::g_sInternalErrors .= "unable to read $::g_Answer $!, ";	# Record internal error
					$::g_nErrorNumber = 540;			# Also record a standard error
					$::g_Answer = $::g_sFilename;			# Record the file name for returning to user

					}

				if($::g_sFilenameExtension eq "ord" ||	# if this is an order
					$::g_sFilenameExtension eq "inf") # 	or information
					{
					chmod(0200, $::g_Answer);				# change the permission on the file
					}
				}
			else												#  if this is a lookup, return the number of files of the given type
				{
				$::g_OutputData = $nFoundCount . ' '; # number of files found
				}
			}
		}
	else														# But if there is a problem opening the directory then
		{
		$::g_sInternalErrors .= "unable to read directory, ";	# Record internal error
		$::g_nErrorNumber = 541;						# Also record a standard error
		$::g_Answer = $::g_sFilename;						# Record the file name for returning to user
		$::g_OutputData = "0";							# no files found
		}

	my ($nState, $sFile, $nLength);

	$nState = substr($::g_nErrorNumber, 0,3);		# grab the status code

	if ($nState == 200)									# if things appear to be OK, check the filename
		{
		$sFile = $::g_Answer;									# copy the response
		$sFile =~ s/[ \t\r\n]//;						# strip any white space

		$nLength = length $sFile;						# double check that if the answer is not a real file, skip it
		if ($nLength == 0)
			{
			$::g_nErrorNumber = 454;					# record a standard error
			$::g_Answer = "none";								# Record the file name for returning to user
			$::g_OutputData = "0";						# no files found
			}
		}
	}

#######################################################
# DeleteFile                                          #
#    Delete the specified file                        #
#######################################################

sub DeleteFile
	{
	if ($::g_sFilenameBase eq "")						# Check for valid file name and, if not, we must
		{
		$::g_sInternalErrors .= "filename for delete is NULL, ";	# Record internal error
		$::g_nErrorNumber = 250;						# Also record a standard error
		return;
		}
	unless (-e $::g_sFilename)							# Make sure the file exists, otherwise
			{
			# this is tolerable so don't bother to log the error $::g_sInternalErrors .= "file $::g_sFilename doesn't exist"; # record internal error
			$::g_nErrorNumber = 254;					# Also record a standard error
			$::g_Answer = $::g_sFilename;				# Record the file name for returning to user
			return;
			}
  	chmod(0666, $::g_sFilename);						# change the permission on the file

	if (! $::g_bActinicHostMode )						# Standalone mode. Directly delete the file.
		{
		unless (-w $::g_sFilename)						# make sure the file is deletable
			{
			$::g_nErrorNumber = 252;					# replay to the client that there was a problem
			$::g_sInternalErrors .= "tried to delete read-only file $::g_sFilename, ";
			}
		else
			{
			unlink ($::g_sFilename);					# Delete the file called $::g_sFilename
			}
		}
	else														# Host mode. Use the daemon library.
		{
		if (0 == unlink ($::g_sFilename))			# First, try to delete the file directly,
			{
			eval												# then if failed, delete it using the daemon
				{
				require AHDClient;
				};
			if ($@)
				{
				$::g_sInternalErrors .= "unable to load the daemon client library ($@)";
				$::g_nErrorNumber = 560;
				return;
				}
			my ($nStatus, $sError, $pClient) = new AHDClient($::g_sDaemonAddress, $::g_nDaemonPort, '<Actinic:Variable Name="PathFromCGIToWeb"/>');
			if ($nStatus != $::SUCCESS)
				{
				$::g_sInternalErrors .= "Unable to connect to the Host Daemon. $sError\n";
				$::g_nErrorNumber = 561;
				return;
				}
			($nStatus, $sError) = $pClient->SetUsernameAndPassword($::g_sUsername, $::g_sPassword);
			if ($nStatus != $::SUCCESS)
				{
				$::g_sInternalErrors .= "Unable to log in to the Host Daemon. $sError\n";
				if ($sError == 201)
					{
					$::g_nErrorNumber = 562;			# invalid username/password
					}
				elsif ($sError == 290)					# host data error
					{
					$::g_nErrorNumber = 564;			# host data error during login
					}
				else
					{
					$::g_nErrorNumber = 565;			# other error during login
					}
				$::g_nErrorNumber = 561;
				return;
				}
			my $sName = $::g_sFilenameBase.".".$::g_sFilenameExtension;
			($nStatus, $sError) = $pClient->DeleteFile($sName);
			if ($nStatus != $::SUCCESS)
				{
				$::g_sInternalErrors .= "Unable to delete file. $sError\n";
				if ($sError == 815)						# shop has been expired
					{
					$::g_nErrorNumber = 563;
					}
				elsif ($sError == 817)					# host data error
					{
					$::g_nErrorNumber = 566;
					}
				elsif ($sError == 860)					# permission problems
					{
					$::g_nErrorNumber = 567;
					}
				elsif ($sError == 861)					# file doesn't exist
					{
					$::g_nErrorNumber = 568;
					}
				else
					{
					$::g_nErrorNumber = 569;
					}
				return;
				}
			}
		}
		$::g_Answer = $::g_sFilename;					# Record the file name for returning to user
	}

###########################################################
#
# Rename File - Rename the specified file
#
# Expects	$::g_sFilename as old name
#				$::g_UserData as the new name
#
# Output		$::g_Answer id the new name if it is successful
#									the old name if not
#				$::g_sInternalErrors, $::g_nErrorNumber are set
#
# Author		Tamas Viola 2002.12.10
#
###########################################################

sub RenameFile
	{
	my $sNewFileName = $::g_UserData;				# get the new filename
	if ($sNewFileName =~ /\.\./ ||					# if the caller is trying to access something outside of the web space
		 $sNewFileName =~ /:/ 	 ||
		 $sNewFileName =~ /\// 	 ||
		 $sNewFileName =~ /\\/ 	 )
		{														# foil the plans
		$::g_sInternalErrors .= "Attempt to access file outside of web space, ";	# Record internal error
		$::g_nErrorNumber = 455;						# Also record a standard error
		return;
		}
	$sNewFileName = $::g_sPath . $sNewFileName;	# make the filename absolute
	unless (-e $::g_sFilename)							# Make sure the file exists, otherwise
		{
		$::g_sInternalErrors .= "File $::g_sFilename doesn't exist, "; # record internal error
		$::g_nErrorNumber = 254;						# Also record a standard error
		$::g_Answer = $::g_sFilename;					# Record the file name for returning to user
		return;
		}
	my $mode = (stat($::g_sFilename))[2];			# get the actual permission of the file
	chmod(0666, $::g_sFilename);						# make it writeable
	if (rename ($::g_sFilename, $sNewFileName))	# try ro rename the file called $::g_sFilename
		{
		$::g_Answer = $sNewFileName;					# Record the new file name for returning to user
		}
	else
		{
		$::g_Answer = $::g_sFilename;					# give back the old file name if it was unsuccesful
		$::g_sInternalErrors .= "Couldn't rename $::g_sFilename, "; # record internal error
		$::g_nErrorNumber = 252;						# Also record a standard error
		}
	chmod($mode, $::g_sFilename);						# change the permission to the original
	}

###########################################################
#
# ExtractFile - unzip the specified file
#
# Expects	$::g_sFilename - zip file name
#
# Output		$::g_Answer - "OK" or the file name is failed
#				$::g_sInternalErrors, $::g_nErrorNumber are set
#
# Author		Zoltan Magyar
#
###########################################################

sub ExtractFile
	{
	unless (-e $::g_sFilename)							# Make sure the file exists, otherwise
		{
		$::g_sInternalErrors .= "File $::g_sFilename doesn't exist, "; # record internal error
		$::g_nErrorNumber = 254;						# Also record a standard error
		$::g_Answer = $::g_sFilename;					# Record the file name for returning to user
		return;
		}
	#
	# Get zip lib
	#
 	eval
		{
		require Archive::Zip;
		};
	if ($@)
		{
		$::g_sInternalErrors = $@;
		$::g_nErrorNumber = 586;
		return;
		}
		
	chmod(0666, $::g_sFilename);						# make it accessible
	my $pArchive = Archive::Zip->new();
	my $status = $pArchive->read( $::g_sFilename );
	if ($status != 0) #AZ_OK
		{
		$::g_sInternalErrors = "Read of $::g_sFilename failed\n";
		$::g_nErrorNumber = 254;
		return;
		}
	#
	# Extract files one by one 
	# $pArchive->extractTree does the same but it got some version dependency so it's better to implemented here
	#
	my @arrMembers = $pArchive->members();
	my $member;
	foreach $member (@arrMembers)
		{
		#
		# Construct file name
		#
		my $sFile = $member->fileName(); 
		my $sAbsFileName = $::g_sPath . $sFile;
		#
		# Extract the file
		#
		$status = $member->extractToFileNamed( $sAbsFileName );
		if ($status != 0)									# if extraction was unsuccessfull
			{
			$::g_Answer = $::g_sFilename;				# give back the old file name if it was unsuccesful
			$::g_sInternalErrors .= "Couldn't unzip $::g_sFilename, "; # record internal error
			$::g_nErrorNumber = 252;					# Also record a standard error
			return;
			}
		#
		# Set permissions on the file depending on its type
		#
		if ($sFile =~ /(diff|full)[^.]*\.fil/i)	# diff files get full r/w prmission
			{
			chmod(0666, $sAbsFileName);
			}
		else
			{
			chmod(0644, $sAbsFileName);
			}
		}
	#
	# Get rid of the zip file now as we don't need it anymore
	#
	unlink $::g_sFilename;
	$::g_Answer = "OK";									# Record OK for returning to user
	}

################################################################
#
# GetFileDate - retrieve the mod dates of the listed files
#
################################################################

sub GetFileDate
	{
	$::g_Answer = '';
	$::g_UserData =~ s/'//g;                     # ' <emacs formatting> # strip any single quotes - they are passed from Cat because it is convenient formatting
	my @listFiles = split(/,/, $::g_UserData);	# parse the file list
	#
	# Get the file dates
	#
	my $sFile;
	foreach $sFile (@listFiles)
		{
		my $sFilePath = $::g_sPath . $sFile;
		if (!-e $sFilePath)
			{
			$::g_OutputData .= ",-";					# - indicates file not found
			}
		else
			{
			my @stat = stat $sFilePath;				# get the file statistics
			my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst, $sDate);
			($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($stat[9]);	# convert the mod date into a printable date
			$mon++;											# make month 1 based
			$year += 1900;									# make year AD based
			$sDate = sprintf("%4.4d/%2.2d/%2.2d %2.2d:%2.2d:%2.2d %1.1d", $year, $mon, $mday, $hour, $min, $sec, $isdst);
			$::g_OutputData .= "," . $sDate;			# return the mod date
			}
		}
	$::g_OutputData =~ s/^,//;							# strip the extraneous leading comma
	}

################################################################
#
# GetFileList - return a listing of all files with the given
#   extension
#
################################################################

sub GetFileList
	{
	$::g_Answer = '';
	$::g_sFilenameExtension =~ s/\./\\\./g;		# escape any "."
	#
	# Get the files
	#
	my @listFiles = ReadTheDir($::g_sPath);
	my $sFile;
	foreach $sFile (@listFiles)						# go over the list of files
		{
		if ($sFile =~ /\.([^\.]+)$/)					# does it match?
			{
			if ($1 eq $::g_sFilenameExtension )		# Check file extension matches
				{
				$::g_OutputData .= ',' . $sFile;		# add it to the list
				}
			}
		}
	$::g_OutputData =~ s/^,//;							# strip the extraneous leading comma
	}

#######################################################
# ReadTheDir                                          #
#     Open a directory and read its contents - this   #
#     is a hack-around for a bug in PerlIS for NT.    #
#																		#
# Params: 0 - the directory path to read              #
#																		#
# Returns: the contents
#																		#
#######################################################

sub ReadTheDir
	{
	#
	# This routine reports any errors directly to the error log.  But does
	# not leave any errors on the stack.  Its errors are silent.
	#
	my $RTDInternalErrors = $::g_sInternalErrors; # make a backup copy
	$::g_sInternalErrors = "";							# clear the buffer

	my $RDpath = $_[0];									# get the pathname from the argument list

   if( opendir (NQDIR, "$RDpath") )					# open the directory to get a file listing
		{														# if successful,
		my @arglist = readdir (NQDIR);				# read the directory
		closedir (NQDIR);									# close the directory
		RecordErrors();									# write our errors to disk
		$::g_sInternalErrors = $RTDInternalErrors; # restore the previous errors
		return (@arglist);
		}

	$::g_sInternalErrors .= "unable to read directory - 2nd open failed, ";	# record internal error if there were problems
	RecordErrors();										# write our errors to disk
	$::g_sInternalErrors = $RTDInternalErrors;	# restore the previous errors
	return (undef);
	}

#######################################################
#   RecordErrors                                      #
# Record any errors, only if they exist               #
#                                                     #
#   Check the top of the file for error codes...      #
#                                                     #
#                                                     #
# These error codes and status codes are written to a #
# file called 'error.err' but when the INTERNAL ERROR #
# CODE does NOT equal '0' (everything is OK) or '7'   #
# (system data file does not exist).                  #
#                                                     #
# When the file, 'error.err' is created (which should #
# be never) it is written to the home directory,  as  #
# specified by $::g_sPath (see above).
#                                                     #
# The format of the error file is:                    #
#                                                     #
#   Text             char(10) "Program = "            #
#   Program          char(8)     program name         #
#   Text             char(20) ", Program version = "  #
#   Program version  char(6)     version number       #
#   Text             char(15) ", HTTP Server = "      #
#   Program version  char(25) server name             #
#   Text             char(17) ", Error number = "     #
#   Error number     char(4)  internal error code     #
#   Text             char(16) ", Return code = "      #
#   Return code      char(40) actinic status code     #
#   Text             char(18) ", Date and time = "    #
#   Date and time    char(16) date & time             #
#                                                     #
#######################################################

sub RecordErrors
	{
	if ( (length $::g_sInternalErrors) > 0 &&		# if there are any errors
		  $::g_bPathKnown)								# and we know where to stick the error log
		{

		open(NQFILE, ">>".$::g_sErrorFilename);	# Open the error file

		print NQFILE ("Program = ");					# Begin to write error file details
		print NQFILE (substr($::prog_name.$::PAD_SPACE,0,8));  # Write error file details

		print NQFILE (", Program version = ");    # Write error file details
		print NQFILE (substr($::prog_ver.$::PAD_SPACE,0,6));# Write error file details

		print NQFILE (", HTTP Server = ");			# Write error file details
		print NQFILE (substr($ENV{'SERVER_SOFTWARE'}.$::PAD_SPACE,0,30));  # Write error file details

		print NQFILE (", Return code = ");			# Write error file details
		print NQFILE (substr($::g_nErrorNumber.$::PAD_SPACE,0,20));  # Write error file details

		print NQFILE (", Date and Time = ");      # Write error file details
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)
			= localtime(time);							# platform independent time
		$mon++;												# make month 1 based
		$year += 1900;
		my $sFormat = sprintf("%2.2d/%2.2d/%4.4d %2.2d:%2.2d:%2.2d", $mday, $mon, $year, $hour, $min, $sec);
		print NQFILE ($sFormat);						# Write error file details
		$wday = $wday;										#
		$yday = $yday;										# remove compiler warning
		$isdst = $isdst;									#

		print NQFILE (", Internal Errors = ");		# Write error file details
		print NQFILE ($::g_sInternalErrors);		# Write error file details

		print NQFILE "\n";

		close NQFILE;

		chmod(0666, $::g_sErrorFilename);			# free up the error file
		}
	}

#######################################################
# SendResponce                                        #
# Send back the ANSWER to the user                    #
#                                                     #
# $::g_nErrorNumber will contain a 3 character ACTINIC           #
# error/status code                                   #
#                                                     #
# $::g_Answer consist of a variable length string    		#
#                                                     #
# If the query was a lookup, then also return the     #
# number of files that matched the query string.      #
#                                                     #
# Any further characters in $::g_Answer will represent    #
# the contents of the file with this filename         #
#                                                     #
#######################################################

sub SendResponse
	{
	if ($::g_Answer eq "")									# If $::g_Answer is not set to any value (due to an error occurring)
		{
		$::g_Answer = substr($::PAD_SPACE,0,16);		# Set $::g_Answer to 16 blank characters
		}
	else
		{
		$::g_Answer = substr($::g_Answer, length ($::g_sPath)); # Remove the path from $::g_Answer
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

	binmode STDOUT;										# the return message is binary so the data is not corrupted and the headers are OK
	PrintHeader('application/octet-stream', (length $SResponse), undef, $::FALSE);
	print $SResponse;										# send the user data
	}


#######################################################
#
# PrintHeader - print the HTTP header
#
#	Params: 	0 - content type
#				1 - content length
#				2 - cookie if any (or undef)
#				3 - no-cache flag - if $::TRUE,
#					include no-cache flag.
#
#######################################################

sub PrintHeader
	{
	my ($sType, $nLength, $sCookie, $bNoCache) = @_;
	#
	# Build a date for the expiry
	#
	my (@expires, $day, $month, $now, $later, $expiry, @now, $sNow);
	my (@days) = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
	my (@months) = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

	$now = time;
	@now = gmtime($now);
	$day = $days[$now[6]];
	$month = $months[$now[4]];
	$sNow = sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT", $day, $now[3],
							$month, $now[5]+1900, $now[2], $now[1], $now[0]);
	$later = $now + 2 * 365 * 24 * 3600;			# Time in 2 years
	@expires = gmtime($later);							# grab time components
	$day = $days[$expires[6]];
	$month = $months[$expires[4]];
	$expiry = sprintf("%s, %02d-%s-%04d %02d:%02d:%02d GMT", $day, $expires[3],
							$month, $expires[5]+1900, $expires[2], $expires[1], $expires[0]);
	#
	# set the cookie if it needs to be set
	#
	my $bCookie = ( (length $sCookie) > 0);		# if a cookie is to be saved
	#
	# now print the header
	#
	if($ENV{'PerlXS'} eq 'PerlIS')					# Windows IIS6 may be using PerIS.dll insteasd of perl.exe
		{
		print "HTTP/1.0 200 OK\n";						# so we must insert the protocol and return status
		}

	if ($bCookie)											# if we are to save the cookie
		{
		print "Set-Cookie: ACTINIC_CART=" .			# set the cookie
		   $sCookie . "; EXPIRES=" .
			$expiry . "; PATH=/;\r\n";
	   print "Date: $sNow\r\n";							# print the date to allow the browser to compensate between server and client differences
	   }

	if ($bNoCache)
		{
		print "Pragma: no-cache\r\n";
		}

	print "Content-type: $sType\r\n";
	print "Content-length: $nLength\r\n\r\n";
	}


sub DebugOut
	{
	open (DBOUT, ">>output.txt");
	print DBOUT $_[0] . "\n";
	close DBOUT;
	}

#######################################################
#
# SecurePath - Error out if the specified path contains
#	any shell characters
#
# Params:	0 - path
#				1 - error code
#
#######################################################

sub SecurePath
	{
	my ($sPath, $nCode) = @_;
	if ($^O =~ /win/i)									# NT
		{
		if ($sPath =~ m|[!&<>\|*?()^;\${}\[\]\`\'\"\n\r]| ||		# the secure path characters (allow backslashes)
			 $sPath =~ m|\0|)
			{
			$::g_nErrorNumber = $nCode;				# Also record a standard error
			$::g_OutputData = $sPath;
			SendResponse();								# Send the response to the user
			exit;
			}
		}
	else
		{
		if ($sPath =~ m|[!&<>\|*?()^;\${}\[\]\`\'\"\\~\n\r]| ||		# the secure path characters (no backslashes)
			 $sPath =~ m|\0|)
			{
			$::g_nErrorNumber = $nCode;				# Also record a standard error
			$::g_OutputData = $sPath;
			SendResponse();								# Send the response to the user
			exit;
			}
		}
	}

#######################################################
#
# AuthenticateUser - verify the username and password
#  Exits on error.
#
# Input:	   0 - user
#				1 - password
#
#######################################################

sub AuthenticateUser
	{
	my ($sUsername, $sPassword) = @_;
	my ($sCorrectUsername, $sCorrectPassword) = ('<Actinic:Variable Name="UserName"/>', '<Actinic:Variable Name="Password"/>');
	#
	# The username and password must be defined.
	#
	if (!$sUsername ||
		 !$sPassword)
		{
		$::g_sInternalErrors .= "Invalid username/password attempt ($sUsername, $sPassword), "; # record internal error
		$::g_nErrorNumber = 453;						# Also record a standard error
		sleep $::DOS_SLEEP_DURATION;					# Discourage DOS attacks
		RecordErrors();									# Write errors to error.err
		SendResponse();									# Send the response to the user
		exit;
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
	# Verify the account
	#
	if (!$::g_bActinicHostMode)						# stand alone catalogs
		{
		if (md5_hex($sUsername) ne $sCorrectUsername ||
			 md5_hex($sPassword) ne $sCorrectPassword)
			{
			$::g_sInternalErrors .= "Invalid username/password attempt ($sUsername, $sPassword), "; # record internal error
			$::g_nErrorNumber = 453;					# Also record a standard error
			sleep $::DOS_SLEEP_DURATION;				# Discourage DOS attacks
			RecordErrors();								# Write errors to error.err
			SendResponse();								# Send the response to the user
			exit;
			}
		}
	else														# Actinic Host mode
		{
		#
		# Load the module for access to the configuration files
		#
		eval 'require AHDClient;';
		if ($@)												# the interface module does not exist
			{
			$::g_sInternalErrors .= 'An error occurred loading the AHDClient module.  ' . $@; # record internal error
			$::g_nErrorNumber = 560;					# Also record a standard error
			sleep $::DOS_SLEEP_DURATION;				# Discourage DOS attacks
			# don't have path yet, so can't record errors to file... RecordErrors();								# Write errors to error.err
			SendResponse();								# Send the response to the user
			exit;
			}
		#
		# Retrieve the appropriate record
		#
		my ($nStatus, $sError, $pClient);
		($nStatus, $sError, $pClient) = new_readonly AHDClient('<Actinic:Variable Name="PathFromCGIToWeb"/>');
		if ($nStatus!= $::SUCCESS)
			{
			$::g_sInternalErrors .= 'An error occured accessing the shop data.' . $sError;
			# TODO: allocate error code for this
			$::g_nErrorNumber = 450;
			sleep $::DOS_SLEEP_DURATION;
			SendResponse();
			exit;
			}
		($nStatus, $sError, my $pShop)= $pClient->GetShopDetailsFromUsernameAndPassword($sUsername, $sPassword);
		if ($nStatus != $::SUCCESS)
			{
			$::g_sInternalErrors .= "Error accessing the configuration file, $sError.  ";	# record internal error
			$::g_nErrorNumber = 450;					# Also record a standard error
			sleep $::DOS_SLEEP_DURATION;				# Discourage DOS attacks
			# don't have path yet, so can't record errors to file... RecordErrors();								# Write errors to error.err
			SendResponse();								# Send the response to the user
			exit;
			}
		elsif (!defined($pShop))						# no shop is accessible via the supplied credentials
			{
			$::g_sInternalErrors .= "Invalid username/password attempt.  $sError.  "; # record internal error
			$::g_nErrorNumber = 562;					# Also record a standard error
			sleep $::DOS_SLEEP_DURATION;				# Discourage DOS attacks
			# don't have path yet, so can't record errors to file... RecordErrors();								# Write errors to error.err
			SendResponse();								# Send the response to the user
			exit;
			}
		if ($::g_sAction eq 'lookup')
			{
			if ($pShop->{DownloadVersion} ne '<Actinic:Variable Name="ActinicScriptRelease"/>')
				{
				($nStatus, $sError, my $pWriteClient) = new AHDClient($::g_sDaemonAddress, $::g_nDaemonPort, '<Actinic:Variable Name="PathFromCGIToWeb"/>');
				if ($nStatus == $::SUCCESS)
					{
					$pWriteClient->SetUsernameAndPassword($sUsername, $sPassword);
					$pWriteClient->RecordClientVersions({DownloadVersion=>'<Actinic:Variable Name="ActinicScriptRelease"/>'});
					}
				}
			}
		#
		# Record the values
		#
		$::g_sPath = $pShop->{Path};					# copy the path to the global variable for use elsewhere
		$::g_sShopID = $pShop->{ShopID};				# the ShopID
		$::g_bTrial  = $pShop->{TrialAccount};		# the trial account mode
		$::g_sBaseURL  = $pShop->{BaseURL};			# the Catalog URL
		$::g_sUsername = $sUsername;
		$::g_sPassword = $sPassword;
      #
      # Check the path for Host catalogs here.  We finally have the actual path now
      #
		$::g_sPath =~ m|(.*?)([^/]+)$|;				# break the complete path into the
		my ($sDirPath, $sFile) = ($1, $2);			# directory and file components

		$sDirPath =~ s|/$||;								# strip any trailing slash from the directory
		opendir (DIR, $sDirPath ? $sDirPath : './');	# open that directory
		my @ShopFiles = grep { /^$sFile/ } readdir(DIR);
		closedir(DIR);

		if (! -e $::g_sPath &&							# if the path does not exist
			 scalar @ShopFiles == 0)					# and it does not refer to a shop index
			{
			$::g_sInternalErrors .= "path does not exist :$::g_sPath:, "; # Record internal error
			$::g_nErrorNumber = 542;					# Also record a standard error
			$::g_bPathKnown = 0;							# path unknown
			}
		elsif (! -r $::g_sPath &&						# if the path is not readable
				 (scalar @ShopFiles == 0 ||			# and it does not refer to any shop files or
				  (scalar @ShopFiles > 0 &&			# we are referring to a shop file
					! -r $sDirPath . '/' . $ShopFiles[0]))) # and the first shop index file is not readable
			{
			$::g_sInternalErrors .= "path is not readable :$::g_sPath:, "; # Record internal error
			$::g_nErrorNumber = 543;					# Also record a standard error
			$::g_bPathKnown = 0;							# path unknown
			}
		else
			{
			$::g_bPathKnown = 1;							# the path is now known
			}
		}
	}

#######################################################
#
# GetPublicKey - receive the public key of the shop
#
# Return:	0 - public key
#
# Author: Zoltan Magyar
#
#######################################################

sub GetPublicKey
	{
	my $sFilename = $::g_sPath . "nqset00.fil" ;

	unless (open (SCRIPTFILE, "<$sFilename"))		# open the file
		{
		$::g_OutputData = "";
		return;
		}

	my $nCheckSum = <SCRIPTFILE>;						# read the checksum
	chomp $nCheckSum;										# strip any trailing CRLF
	$nCheckSum =~ s/;$//;								# strip the trailing ;

	my $sScript;
	{
	local $/;
	$sScript = <SCRIPTFILE>;							# read the entire file
	}
	close (SCRIPTFILE);									# close the file
	#
	# calculate the script checksum
	#
	my $uTotal;
		{
		use integer;
		$uTotal = unpack('%32C*', $sScript);
		}
	#
	# verify the script
	#
	if ($nCheckSum != $uTotal)
		{
		$::g_OutputData = "";
		return;
		}

	$sScript =~ s/\r//g;									# remove the dos <CR>

	if (!eval($sScript))
		{
		$::g_OutputData = "";
		return;
		}
	#
	# No we have the setup blob
	# Lets get the encryption key
	#		
	my ($nCount, $sKey);
	my $sKeyLength = $$::g_pSetupBlob{'KEY_LENGTH'};
	my ($pKey) = $$::g_pSetupBlob{'PUBLIC_KEY_' . $sKeyLength . 'BIT'};
	for ($nCount = ($sKeyLength / 8) - 1; $nCount >= 0; $nCount--)
		{
		$sKey .= sprintf('%2.2x', $$pKey[$nCount]);
		}	
	$::g_OutputData = $sKey;
	}
	
#######################################################
#
# GetOrderNum - retrieve the incremental order number 
#
# Return:	0 - order number
#
# Author: Zoltan Magyar
#
#######################################################

sub GetOrderNum
	{
	#
	# We need File::copy here. Be Friendly and check if it exists
	#
	eval ('require File::Copy;');
	if ($@) 
		{
		$::g_sInternalErrors .= "Unable to load File::Copy module -  $@, ";	# Record internal error
		$::g_nErrorNumber = 999;				
		return;
		}
	#
	# If none of the files exist then no order was placed so far.
	# Therefore there isn't anything to do just indicate by
	# returning -1
	#
	my $sUnLockFile = $::g_sPath . 'Order.num'; 	# name of the lock file in its unlocked state
	my $sBackupFile = $::g_sPath . 'Backup.num'; # name of the lock file in its unlocked state	
	my $sQueryFile  = $::g_sPath . 'Query.num'; 	# name of the copy of the lock file 
	my $sLockFile   = $::g_sPath . 'OrderLock.num'; # name of the lock file in its locked state
	
	if (!-e $sUnLockFile &&								# none of the files exist
		 !-e $sLockFile &&
		 !-e $sBackupFile)
		{
		$::g_OutputData = -1;
		return;
		}
	if (!-e $sUnLockFile &&								# if the backup file is only there
		 !-e $sLockFile &&
		  -e $sBackupFile)		
		{														# try to restore by copying backup file
		if (!File::Copy::copy($sBackupFile, $sUnLockFile))
			{
			$::g_sInternalErrors .= "Unable to copy of the backup file to unlock file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;		
			}			
		}			
	#
	# Now try to copy the unlocked file. The file might be locked therefore 
	# we try to copy a few times in case of failure.
	#		
	my $bGotCopy = $::FALSE;
	my $nRetries = 20;									# number of times to retry the lock file
	while ($nRetries > 0)								# repeat the attempt to grab the file until you have it or give up
		{	
		if (File::Copy::copy($sUnLockFile, $sQueryFile))
			{
			#
			# note the success, and get out of the loop
			#
			$bGotCopy = $::TRUE;
			last;			
			}
		$nRetries--;										# decrement the retry count
		sleep 2;												# pause before we try again			
		}
	#
	# Check if we got copy of the lock file. If we still do not have 
	# a copy then try the backup file
	#
	if (!$bGotCopy)
		{
		if (!-e $sBackupFile)
			{
			$::g_sInternalErrors .= "Backup file doesn't exist -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;			
			}
		#
		# Try to copy the backup file
		#
		if (!File::Copy::copy($sBackupFile, $sQueryFile))
			{
			$::g_sInternalErrors .= "Unable to get a copy of the backup file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;		
			}			
		}
	#
	# If we are here then we have a copy of the lock file.
	# Lets open it and extract the sequence number
	#
	my $nByteLength = 4;
	unless (open (LOCK, "<$sQueryFile"))			# open the file
		{
		$::g_sInternalErrors .= "Unable to open the copy of the lock file -  $!, ";	# Record internal error
		$::g_nErrorNumber = 584;				
		return;		
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
			$::g_sInternalErrors .= "Unable to open the backup file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;			
			}
		binmode LOCK;
		unless ($nByteLength == read (LOCK, $nCounterBin, $nByteLength))
			{
			#
			# the backup file is dead as well - report the error as if the problem was with the
			# first file
			#
			$::g_sInternalErrors .= "Both lock and backup files are dead -  $sError -- $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;
			}
		}
	close (LOCK);											# close the file
	#
	# Remove the copy file
	#
	chmod(0666, $sQueryFile);
	unlink($sQueryFile);
	#
	# We got the counter
	#
	$::g_OutputData = unpack("N", $nCounterBin);	
	}
	
	
#######################################################
#
# SetOrderNum - adjust the incremental order number 
#
# Author: Zoltan Magyar
#
#######################################################

sub SetOrderNum
	{
	#
	# We need File::copy here. Be Friendly and check if it exists
	#
	eval ('require File::Copy;');
	if ($@) 
		{
		$::g_sInternalErrors .= "Unable to load File::Copy module -  $@, ";	# Record internal error
		$::g_nErrorNumber = 999;				
		return;
		}
	my $sUnLockFile = $::g_sPath . 'Order.num'; 	# name of the lock file in its unlocked state
	my $sBackupFile = $::g_sPath . 'Backup.num'; # name of the lock file in its unlocked state
	my $sLockFile   = $::g_sPath . 'OrderLock.num'; # name of the lock file in its locked state
	#
	# If none of the files exists then no order was placed so far.
	# Therefore the files should be created now
	#	
	if (!-e $sUnLockFile &&								# none of the files exist
		 !-e $sLockFile &&
		 !-e $sBackupFile)
		{
		#
		# create the unlocked file
		#
		unless (open (LOCK, ">$sUnLockFile"))
			{
			$::g_sInternalErrors .= "Unable to create the lock file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;	
			}
		binmode LOCK;
		my $nCounter = pack("N", $::g_UserData);
		unless (print LOCK $nCounter)
			{
			$::g_sInternalErrors .= "Unable to write to the lock file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;
			}
		#
		# Try to copy the backup file
		#
		if (!File::Copy::copy($sUnLockFile, $sBackupFile))
			{
			$::g_sInternalErrors .= "Unable to get a copy to the backup file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;		
			}					
		close (LOCK);
		sleep 2;			
		return;												# the lock file is created, nothing else to do
		}
	if (!-e $sUnLockFile &&								# if the backup file is only there
		 !-e $sLockFile &&
		  -e $sBackupFile)		
		{														# try to restore by copying backup file
		if (!File::Copy::copy($sBackupFile, $sUnLockFile))
			{
			$::g_sInternalErrors .= "Unable to copy of the backup file to unlock file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 584;				
			return;		
			}			
		}		
	#
	# Now try to lock the file
	#
	my $nDate;												# the date on the lock file
	my $bFileIsLocked = $::FALSE;						# note if we get the file
	my $sRenameError;
	my $nNumberBreakRetries = 1;
	my $nByteLength = 4;
	
RETRY:
	$bFileIsLocked = $::FALSE;
	if ($nNumberBreakRetries < 0)						# we seem to be in an unrecoverable situation
		{
		$::g_sInternalErrors .= "0 - Couldn't lock the file -  $sRenameError, ";	# Record internal error
		$::g_nErrorNumber = 585;				
		return;
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
				$::g_sInternalErrors .= "1 - Couldn't lock the file -  $sRenameError, ";	# Record internal error
				$::g_nErrorNumber = 585;				
				return;
				}

			if (!defined $tmp[9])						# file was removed just before we got the current date -
				{												# assume it is free and try again
				$nNumberBreakRetries--;					# decrement the counter
				sleep 2;
				goto RETRY;
				}

			if ($nDate == $tmp[9])						# the lock file date has not changed
				{
				if (!rename($sLockFile, $sUnLockFile))	# try to unlock the file
					{
					#
					# failure
					#
					$::g_sInternalErrors .= "Couldn't rename lock file -  $!, ";	# Record internal error
					$::g_nErrorNumber = 585;				
					return;
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
		$::g_sInternalErrors .= "Couldn't open the lock file -  $!, ";	# Record internal error
		$::g_nErrorNumber = 585;				
		return;
		}
	binmode LOCK;
	my $nCounterBin;
	unless ($nByteLength == read (LOCK, $nCounterBin, $nByteLength))	# read the counter
		{
		#
		# the lock file failed to contain the counter.  Try the backup file
		#
		close (LOCK);
		unless (open (LOCK, "<$sBackupFile"))
			{
			$::g_sInternalErrors .= "Couldn't open the backup file -  $!, ";	# Record internal error
			$::g_nErrorNumber = 585;				
			return;
			}
		binmode LOCK;
		unless ($nByteLength == read (LOCK, $nCounterBin, $nByteLength))
			{
			#
			# the backup file is dead as well - report the error as if the problem was with the
			# first file
			#
			close (LOCK);
			$::g_sInternalErrors .= "The backup file doesn't contain valid counter -  $!, ";	# Record internal error
			$::g_nErrorNumber = 585;				
			return;
			}
		}
	close (LOCK);											# close the file
	#
	# update the lock file
	#
	$nCounterBin = pack ("N", $::g_UserData);
	unless (open (LOCK, ">$sLockFile"))
		{
		$::g_sInternalErrors .= "Couldn't open the lock file -  $!, ";	# Record internal error
		$::g_nErrorNumber = 585;				
		return;
		}
	binmode LOCK;
	unless (print LOCK $nCounterBin)
		{
		close (LOCK);
		$::g_sInternalErrors .= "Couldn't write to the lock file -  $!, ";	# Record internal error
		$::g_nErrorNumber = 585;				
		return;
		}
	close (LOCK);
	#
	# update the backup file
	#
	unless (open (LOCK, ">$sBackupFile"))
		{
		$::g_sInternalErrors .= "Couldn't open the backup file -  $!, ";	# Record internal error
		$::g_nErrorNumber = 585;				
		return;
		}
	binmode LOCK;
	unless (print LOCK $nCounterBin)
		{
		close (LOCK);
		$::g_sInternalErrors .= "Couldn't write to the backup file -  $!, ";	# Record internal error
		$::g_nErrorNumber = 585;				
		return;
		}
	close (LOCK);
	#
	# unlock the file
	#
	if (!rename ($sLockFile, $sUnLockFile))
		{
		$::g_sInternalErrors .= "Couldn't unlock the file -  $!, ";	# Record internal error
		$::g_nErrorNumber = 585;				
		return;
		}
	}	

#######################################################
#																				#
# StockSend - Create the given file                  										#
#																				#
#######################################################

sub StockSend
	{
	my $uSum = substr($::g_UserData, 0, 12);
	my $sStockData = substr($::g_UserData, 12);
	my $uTotal;
		{
		use integer;
		$uTotal = unpack('%32C*', $sStockData);
		}
	if ($uTotal != $uSum)
		{
		$::g_sInternalErrors .= "corrupt file transfer: local($uTotal) != remote($uSum) " . substr($sStockData, 0, 10) . "| " . length ($sStockData) . ", ";	# Record internal error
		$::g_nErrorNumber = 554;						# Also record a standard error
		return;
		}
	#
	# Now see if we can include our stock management library
	#
	eval												# then if failed, delete it using the daemon
		{
		require <Actinic:Variable Name="StockManagerPackage"/>;
		};
	if ($@)
		{
		$::g_sInternalErrors .= "unable to load the stock manager library ($@)";
		$::g_nErrorNumber = 600;
		return;
		}
	#
	# Extract product reference - stock level pairs from the user data
	#
	my @aPairs = split /\&/, $sStockData;
	my ($sItem, @aProdRefs, @aValues);
	foreach $sItem (@aPairs)
		{
		my ($sRef, $sValue) = split /=/, $sItem;
		#
		# Decode the value
		#
		$sRef =~ s/\+/ /g;							# replace + signs with the spaces they represent
		$sRef =~ s/%([A-Fa-f0-9]{2})/pack('c',hex($1))/ge;	# Convert %XX from hex numbers to character equivalent
		#
		# Push into the resulting arrays 
		#
		push @aProdRefs, $sRef;
		push @aValues, $sValue;
		}
	#
	# Create our stock manager
	#
	my $StockManager = new StockManager($::g_sPath);
	my ($Status, $Message) = $StockManager->SetStock(\@aProdRefs, \@aValues);
	if ($Status != $::SUCCESS)
		{
		$::g_sInternalErrors .= "Failure running stock balance file update ($Message)";
		$::g_nErrorNumber = 601;
		}
	}
	
#######################################################
#																				#
# StockSend - Create the given file                  										#
#																				#
#######################################################

sub StockEmpty
	{
	#
	# Try to include our stock management library
	#
	eval												# then if failed, delete it using the daemon
		{
		require <Actinic:Variable Name="StockManagerPackage"/>;
		};
	if ($@)
		{
		$::g_sInternalErrors .= "unable to load the stock manager library ($@)";
		$::g_nErrorNumber = 600;
		return;
		}
	#
	# Create our stock manager
	#
	my $StockManager = new StockManager($::g_sPath);
	my ($Status, $Message) = $StockManager->EmptyTransactions();
	if ($Status != $::SUCCESS)
		{
		$::g_sInternalErrors .= "Failure cleaning up stock transaction file ($Message)";
		$::g_nErrorNumber = 602;
		}
	}
	