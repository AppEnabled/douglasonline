#!<Actinic:Variable Name="PerlPath"/>
#######################################################
#																		#
# SiteExplorer.pl - diagnostic script for Catalog		#
#																		#
# Copyright (c) 2002 ACTINIC SOFTWARE Plc					#
#																		#
# Written by Zoltan Magyar 									#
# December 25 2002												#
#																		#
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

use strict;
use Socket;
#?use CGI::Carp qw(fatalsToBrowser);
#
# Version information
#
$::prog_name = "EXPLORER";								# Program Name (8 characters)
$::prog_ver = '$Revision: 22654 $';						# program version (6 characters)
$::prog_ver = substr($::prog_ver, 11);				# strip the revision information
$::prog_ver =~ s/ \$//;									# and the trailers
#
# Generic constants
#
$::FALSE 	= 0;
$::TRUE	 	= 1;
$::FAILURE 	= 0;
$::SUCCESS 	= 1;

$ACTINIC::FORM_URL_ENCODED 			= 0;			# standard application/x-www-form-urlencoded (%xx) encoding	- This value is referenced in the PSP plug-ins - any changes need to be reflected there
$ACTINIC::MODIFIED_FORM_URL_ENCODED	= 1;			# Actinic format - identical to eParameter except an
																# underscore is used instead of a percent sign and the string is prepended with an "a"
$ACTINIC::HTML_ENCODED					= 2;			# standard HTML encoding (&dd;)
#
# Settings
#
$::g_sEmailAddress = '<Actinic:Variable Name="Email"/>'; # get the email address
$::g_sServerAddress = '<Actinic:Variable Name="SmtpServer"/>';	# get mail server host
$::g_sPathToAcatalog = '<Actinic:Variable Name="PathFromCGIToWeb"/>';
$::g_bIsWindowsOS = $::FALSE;
#
# Messages
#
$::g_pPrompts =
	{
	'IDS_SE_COULDNT_READ_DIRECTORY' => "Couldn't read the directory list for ",
	'IDS_SE_INFO_FILE_PERMISSIONS' => "File Permissions",
	'IDS_SE_INFO_FILE_PERMISSIONS_ACATALOG' => "Files in Online Store Folder",
	'IDS_SE_INFO_FILE_PERMISSIONS_ACATALOG_ROOT' => "Files in root of Online Store Folder",
	'IDS_SE_INFO_FILE_PERMISSIONS_CGI' => "Files in /cgi-bin",
	'IDS_SE_INFO_FILE_PERMISSIONS_CGI_ROOT' => "Files in /cgi-bin/../",
	'IDS_SE_INFO_SCRIPT_PERMISSIONS_ACATALOG' => "Check script permissions in Online Store Folder.",
	'IDS_SE_CREATE_FILE' => 'Create file in Online Store Folder...',
	'IDS_SE_SUCCESS' => 'Success',
	'IDS_SE_FAILURE' => 'Failure',
	'IDS_SE_CHMOD_FILE' => 'Chmod file...',
	'IDS_SE_RENAME_FILE' => 'Rename file...',
	'IDS_SE_REMOVE_FILE' => 'Remove file...',
	'IDS_SE_AUTH_FAILURE' => 'Invalid username/password attempt',
	'IDS_SE_INFO_PERL' => 'Perl Environment',
	'IDS_SE_INFO_PERL_VERSION' => 'Perl Version',
	'IDS_SE_INFO_PERL_MODULES' => 'Perl Modules',
	'IDS_SE_INFO_NOT_INSTALLED' => 'Not installed',
	'IDS_SE_INFO_INSTALLED' => 'Installed',
	'IDS_SE_INFO_REAL_USER' => 'Real CGI User',
	'IDS_SE_INFO_REAL_GROUP' => 'Real CGI Group',
	'IDS_SE_INFO_EFF_USER' => 'Effective CGI User',
	'IDS_SE_INFO_EFF_GROUP' => 'Effective CGI Group',
	'IDS_SE_INFO_SCRIPTNAME' => 'Script name',
	'IDS_SE_INFO_FTP_USER' => 'FTP User',
	'IDS_SE_INFO_FTP_GROUP' => 'FTP Group',
	'IDS_SE_INFO_ENV' => 'Server Environment',
	'IDS_SE_INFO_SMTP' => 'SMTP Communication',
	};

###############################################################
#
# Main - END
#
###############################################################

Init();
ProcessInput();
exit;

###############################################################
#
# Init - initialize the script
#
###############################################################

sub Init
	{
	my ($status, $message, $temp);
	($status, $message, $::g_OriginalInputData, $temp, %::g_InputHash) = ReadAndParseInput();
	if ($status != $::SUCCESS)
		{
		PrintPage($message);
		exit;
		}
	#
	# Authenticate the user
	#
	AuthenticateUser($::g_InputHash{USER}, $::g_InputHash{PASS});
	}

###############################################################
#
# ProcessInput - check what should be done
#
# Input:	   0 - user
#				1 - password
#
###############################################################

sub ProcessInput
	{
	#
	# Checking the functions step by step
	# To get rid of any check just comment out the appropriate line below
	#
	my $sHTML;
	$sHTML .= GetFormatedEnv();
	$sHTML .= GetPerlEnv();
	$sHTML .= CheckPerlModules();
	$sHTML .= GetAcatalogPermissions();
	$sHTML .= GetPermissions();
	$sHTML .= CheckSendMail();

	PrintPage($sHTML);
	}

###############################################################
#
# AuthenticateUser - verify the username and password
#  Exits on error.
#
# Input:	   0 - user
#				1 - password
#
###############################################################

sub AuthenticateUser
	{
	my ($sUsername, $sPassword) = @_;
	my ($sCorrectUsername, $sCorrectPassword) = ('<Actinic:Variable Name="UserName"/>', '<Actinic:Variable Name="Password"/>');
	my ($sSupportUsername, $sSupportPassword) = ('2b90dd375486e278f32319aeed5524ce', '86521a90867b3a095f26c4250f086b95');
	my $sReturn;
	#
	# The username and password must be defined.
	#
	if (!$sUsername ||
		 !$sPassword)
		{
		$sReturn = $$::g_pPrompts{'IDS_SE_AUTH_FAILURE'} . " ($sUsername, $sPassword), ";
		PrintPage($sReturn);
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
	if (md5_hex($sUsername) ne $sCorrectUsername ||
		 md5_hex($sPassword) ne $sCorrectPassword)
		{
		#
		# Check for support password
		#
		if (md5_hex($sUsername) ne $sSupportUsername ||
			 md5_hex($sPassword) ne $sSupportPassword)
			{
			$sReturn = $$::g_pPrompts{'IDS_SE_AUTH_FAILURE'} . " ($sUsername, $sPassword), ";
			PrintPage($sReturn);
			exit;
			}
		}
	}

###############################################################
#
# GetAcatalogPermissions - check what permissions are available
#					for the active CGI user on the acatalog folder
#
###############################################################

sub GetAcatalogPermissions
	{
	my $sTestFileName = $::g_sPathToAcatalog . "ActinicTestFile.html";
	my $sRenamedTestFile = $::g_sPathToAcatalog . "ActinicTestFileRenamed.html";
	my $sHTML = "<H1>" . $$::g_pPrompts{'IDS_SE_INFO_SCRIPT_PERMISSIONS_ACATALOG'} . "</H1>";
	#
	# Try to create a file in acatalog
	#
	$sHTML .= FormatSent($$::g_pPrompts{'IDS_SE_CREATE_FILE'});
	unless (open(TESTFILE, ">>$sTestFileName"))
		{
		$sHTML .= FormatReceived($$::g_pPrompts{'IDS_SE_FAILURE'} . " - " . $!);
		return $sHTML ;
		}
	unless (print TESTFILE "Test")
		{
		$sHTML .= FormatReceived($$::g_pPrompts{'IDS_SE_FAILURE'} . " - " . $!);
		return $sHTML ;
		}
	close TESTFILE;
	$sHTML .= FormatReceived($$::g_pPrompts{'IDS_SE_SUCCESS'});
	#
	# Try chmod file
	#
	$sHTML .= FormatSent($$::g_pPrompts{'IDS_SE_CHMOD_FILE'});
	$sHTML .= TestReturnValue(chmod(0777, $sTestFileName));
	#
	# Try rename file
	#
	$sHTML .= FormatSent($$::g_pPrompts{'IDS_SE_RENAME_FILE'});
	$sHTML .= TestReturnValue(rename $sTestFileName, $sRenamedTestFile);
	#
	# Try remove file
	#
	$sHTML .= FormatSent($$::g_pPrompts{'IDS_SE_REMOVE_FILE'});
	$sHTML .= TestReturnValue(unlink $sRenamedTestFile);
	return $sHTML;
	}

###############################################################
#
# GetAcatalogPermissions - check what permissions are available
#					for the active CGI user on the acatalog folder
#
###############################################################

sub TestReturnValue
	{
	my $bValue = shift;
	my $sReturn = $bValue ? $$::g_pPrompts{'IDS_SE_SUCCESS'} : $$::g_pPrompts{'IDS_SE_FAILURE'} . " - " . $!;
	return FormatReceived($sReturn);
	}

###############################################################
#
# GetPermissions - build HTML formatted directory
#						HTML formatted
#
###############################################################

sub GetPermissions
	{
	require Cwd;											# we need this for directory change
	my $sHTML = "<H1>" . $$::g_pPrompts{'IDS_SE_INFO_FILE_PERMISSIONS'} . "</H1>";
	#
	# Determine current directory and list its content
	#
	my $sCGIPath = Cwd::getcwd() . "/";
	$sHTML .= "<H2>" . $$::g_pPrompts{'IDS_SE_INFO_FILE_PERMISSIONS_CGI'} . "</H2>";
	$sHTML .=  DumpDirListing($sCGIPath);
	#
	# Get root of CGI
	#
	chdir "../";
	my $sCGIRoot = Cwd::getcwd() . "/";
	$sHTML .= "<H2>" . $$::g_pPrompts{'IDS_SE_INFO_FILE_PERMISSIONS_CGI_ROOT'} . "</H2>";
	$sHTML .=  DumpDirListing($sCGIRoot);
	#
	# Get /acatalog content
	#
	chdir $sCGIPath;
	$sHTML .= "<H2>" . $$::g_pPrompts{'IDS_SE_INFO_FILE_PERMISSIONS_ACATALOG'} . "</H2>";
	$sHTML .=  DumpDirListing($::g_sPathToAcatalog);
	#
	# Get root of /acatalog/
	#
	chdir $sCGIPath;
	chdir $::g_sPathToAcatalog;
	chdir "../";
	my $sAcatalogRoot = Cwd::getcwd() . "/";
	$sHTML .= "<H2>" . $$::g_pPrompts{'IDS_SE_INFO_FILE_PERMISSIONS_ACATALOG_ROOT'} . "</H2>";
	$sHTML .=  DumpDirListing($sAcatalogRoot);

	return($sHTML);
	}

###############################################################
#
# DumpDirListing
#     Open a directory and read its contents and dump HTML formatted
#
# Params: 0 - the directory path to read
#
# Returns: the HTML formatted contents
#
###############################################################

sub DumpDirListing
	{
	my $RDpath = $_[0];									# get the pathname from the argument list
	#
	# Read the directory list
	#
	my $sHTML;
   if (!opendir (NQDIR, "$RDpath") )				# open the directory to get a file listing
		{														# if not successful,
		$sHTML .= $$::g_pPrompts{'IDS_SE_COULDNT_READ_DIRECTORY'} . $RDpath;
		return($sHTML);									# bomb out
		}
	my @aDirList = readdir (NQDIR);					# read the directory
	closedir (NQDIR);										# close the directory

	$sHTML .= "<B>$RDpath</B>";
	$sHTML .= "<TABLE  BORDER=0>";
	my $var;
	foreach $var (@aDirList)
		{														# add all as a new row
		my @Results = stat($RDpath . $var);
		$sHTML .= FormatLine($var, @Results) . "\n";
		}
	$sHTML .= "</TABLE><HR>";								# close table
	return($sHTML);
	}

###############################################################
#
# FormatLine
#     Format the file stat line as string
#
# Params: 0 - the file name
#			 1 - the file stat (returned by stat)
#
# Returns: the formatted contents
#
###############################################################

sub FormatLine
	{
	my $sFilename = shift;
	my @stat = @_;
	my ($nMode, $nGroup, $nUser) = ($stat[2], $stat[5], $stat[4]);
	#
	# Format the date first
	#
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($stat[9]);	# convert the mod date into a printable date
	$mon++;													# make month 1 based
	$year += 1900;											# make year AD based
	my $sDate = sprintf("%4.4d/%2.2d/%2.2d %2.2d:%2.2d:%2.2d ", $year, $mon, $mday, $hour, $min, $sec);
	#
	# Format the permission
	#
	my $sPermission = FormatPerm($nMode);
	#
	# Format owner
	#
	my ($sGroup, $sUser) = GetUserAndGroup($nUser, $nGroup);
	#
	# Format final line
	#
	my $sLine = "<TR><TD>" . $sPermission . "</TD>" .
					"<TD>" . $sUser . "</TD>" .
					"<TD>" . $sGroup . "</TD>" .
					"<TD>" . $stat[7] . "</TD>" .
					"<TD>" . $sDate . "</TD>" .
					"<TD><B>" . $sFilename. "</B></TD></TR>";
	return($sLine);
	}

###############################################################
#
# GetUserAndGrop
#     Determine the user and group name by using the passed
#		in UID and GID
#
# Params: 	0 - UID
#				1 - GID
#
# Returns: 	0 - user name
#				1 - group name
#
###############################################################

sub GetUserAndGroup
	{
	my ($nUser, $nGroup) = @_;
	my ($sGroup, $sUser);
	#
	# Check OS to use specific functions
	#
	if ($::g_bIsWindowsOS)								# is it Win32?
		{
		eval 'require Win32;';
		if (!$@)
			{
			my ($sServer, $nType);
			Win32::LookupAccountSID("", $sUser, $sUser, $sServer, $nType);
			$sGroup = $nGroup;
			}
		}
	else
		{
		#
		# getpwuid and getgrgid might not be supported on some platforms
		# therefor we should threat them carefully
		#
		eval
			{
			$sUser = getpwuid($nUser);					# convert UID to name
			$sGroup = getgrgid($nGroup);				# convert GID to name
			}
		}
	return($sUser, $sGroup);
	}

###############################################################
#
# FormatPerm
#     Format the file permission as string
#
# Params: 0 - the file stat (returned by stat)
#
# Returns: the formatted permission
#
###############################################################

sub FormatPerm
	{
	my ($nMode) = @_;
	my $sPerm = '-' x 9;
	substr($sPerm, 0, 1) = 'r' if ($nMode & 00400);
	substr($sPerm, 1, 1) = 'w' if ($nMode & 00200);
	substr($sPerm, 2, 1) = 'x' if ($nMode & 00100);
	substr($sPerm, 3, 1) = 'r' if ($nMode & 00040);
	substr($sPerm, 4, 1) = 'w' if ($nMode & 00020);
	substr($sPerm, 5, 1) = 'x' if ($nMode & 00010);
	substr($sPerm, 6, 1) = 'r' if ($nMode & 00004);
	substr($sPerm, 7, 1) = 'w' if ($nMode & 00002);
	substr($sPerm, 8, 1) = 'x' if ($nMode & 00001);
	substr($sPerm, 2, 1) = 's' if ($nMode & 04000);
	substr($sPerm, 5, 1) = 's' if ($nMode & 02000);
	substr($sPerm, 8, 1) = 't' if ($nMode & 01000);
	return($sPerm);
	}

###############################################################
#
# GetPerlEnv - Get Perl Environment and return it HTML formatted
#
###############################################################

sub GetPerlEnv
	{
	my $sHTML = "<H1>" . $$::g_pPrompts{'IDS_SE_INFO_PERL'} . "</H1>";
	$sHTML .= "<TABLE BORDER=1>";						# format table

	$sHTML .= "<TR><TD>" . $$::g_pPrompts{'IDS_SE_INFO_PERL_VERSION'} . "</TD><TD>" . $] . "</TD></TR>\n";
	#
	# Check current user
	#
	my ($sUser, $sGroup, $sRUser, $sRGroup);
	if ($::g_bIsWindowsOS)								# is it Win32?
		{
		eval 'require Win32;';
		$sUser = $@ ? "" : Win32::LoginName();
		$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_EFF_USER'}."</TD><TD>" . $sUser . "</TD></TR>\n";
		}
	else
		{
		#
		# The functions below might be unimplemented in some environment
		# therefore we should be carefull here
		#
		eval
			{
			($sRUser, $sRGroup) = GetUserAndGroup($<, $();
			($sUser, $sGroup) = GetUserAndGroup($>, $));
			$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_REAL_USER'}."</TD><TD>" . $sRUser . "</TD></TR>\n";
			$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_REAL_GROUP'}."</TD><TD>" . $sRGroup . "</TD></TR>\n";
			$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_EFF_USER'}."</TD><TD>" . $sUser . "</TD></TR>\n";
			$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_EFF_GROUP'} ."</TD><TD>" . $sGroup . "</TD></TR>\n";
			}
		}

	$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_SCRIPTNAME'}."</TD><TD>" . $0 . "</TD></TR>\n";
	#
	# Check the ftp user by investigating the current script owner
	#
	if (!$::g_bIsWindowsOS)								# is it not Win32?
		{
		my ($sFtpUser, $sFtpGroup) = GetUserAndGroup((stat($0))[4, 5]);
		$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_FTP_USER'}."</TD><TD>" . $sFtpUser . "</TD></TR>\n";
		$sHTML .= "<TR><TD>".$$::g_pPrompts{'IDS_SE_INFO_FTP_GROUP'}."</TD><TD>" . $sFtpGroup . "</TD></TR>\n";
		}
	$sHTML .= "</TABLE>";								# close table
	return($sHTML);
	}

###############################################################
#
# CheckPerlModules - Check for specific perl modules
#
# Returns: 	Results in HTML table
#
###############################################################

sub CheckPerlModules
	{
	my $sHTML = "<H1>" . $$::g_pPrompts{'IDS_SE_INFO_PERL_MODULES'} . "</H1>";
	$sHTML .= "<TABLE BORDER=1>";						# format table
	#
	# Check for key perl modules
	#
	$sHTML .= CheckPerlModuleInstalled("Digest::MD5");
	$sHTML .= CheckPerlModuleInstalled("ActinicEncrypt1024");
	$sHTML .= CheckPerlModuleInstalled("Exporter");
	$sHTML .= CheckPerlModuleInstalled("File::Temp");
	$sHTML .= CheckPerlModuleInstalled("LWP::UserAgent");
	$sHTML .= CheckPerlModuleInstalled("Crypt::SSLEasy");
	$sHTML .= CheckPerlModuleInstalled("CGI");
	$sHTML .= CheckPerlModuleInstalled("CGI::Carp");
	$sHTML .= CheckPerlModuleInstalled("Archive::Zip");
	$sHTML .= CheckPerlModuleInstalled("Net::SSL");

	$sHTML .= "</TABLE>";								# close table
	return($sHTML);
	}

###############################################################
#
# CheckPerlModules - Check for specific perl modules
#
# Params: 	0 - Name of module to look for
#
# Returns: 	HTML row of module name and installed indication
#
###############################################################

sub CheckPerlModuleInstalled
	{
	my ($sModule) = @_;
	my $sCommand = sprintf('require %s;', $sModule);
	eval $sCommand;
	my $sInstalled = $@ ? $$::g_pPrompts{'IDS_SE_INFO_NOT_INSTALLED'} : $$::g_pPrompts{'IDS_SE_INFO_INSTALLED'};
	my $sHTML = "<TR><TD>$sModule</TD><TD>" . $sInstalled . "</TD></TR>\n";
	return($sHTML);
	}

###############################################################
#
# GetFormatedEnv - Get content of %ENV and return it
#						HTML formatted
#
###############################################################

sub GetFormatedEnv
	{
	my $sHTML = "<H1>" . $$::g_pPrompts{'IDS_SE_INFO_ENV'} . "</H1>";
	$sHTML .= "<TABLE BORDER=1>";						# format table
	if ($^O =~ /win/i)									# is it Win32
		{
		$::g_bIsWindowsOS = $::TRUE;
		}
	$sHTML .= "<TR><TD>Operating System </TD><TD>" . $^O . "</TD></TR>\n";
	my $var;
	foreach $var (sort(keys(%ENV))) 					# iterate ENV variables
		{														# add all as a new row
		$sHTML .= "<TR><TD>" . $var . "</TD><TD>" . $ENV{$var} . "</TD></TR>\n";
		}
	$sHTML .= "</TABLE>";								# close table
	return($sHTML);
	}

###############################################################
#
# CheckSendMail - check the mail server
#
# Returns:	0 - out - HTML formatted SMTP communication stream
#
###############################################################

sub CheckSendMail
	{
	my $sHTML = "<H1>" . $$::g_pPrompts{'IDS_SE_INFO_SMTP'} . "</H1><BR>";
	#
	# Gather the SMTP host, server, and socket information
	#
	my ($nProto, $them, $nSmtpPort, $sMessage, $ServerIPAddress);
	my $bPassed = $::TRUE;
	#
	# Check if the SMTP server is specified. If not, then there is no need for testing
	#
	if ($::g_sServerAddress eq '')
		{
		$sHTML .= FormatReceived("No SMTP server is specified.");
		$bPassed = $::FALSE;
		goto ERRORNOCLOSE;
		}

	my $sLocalhost = GetHostName();					# get the local machine name or ip address
	if ($sLocalhost eq '')
		{
		$sLocalhost = 'localhost';						# try localhost as a final possibility
																# GetHostname should not fail on most of the systems
		}
	$sHTML .= FormatSent("Get host name...");
	$sHTML .= FormatReceived("Host name is '$sLocalhost'");
	$sHTML .= FormatSent("DNS lookup...");
	$nProto = getprotobyname('tcp');
	$nSmtpPort = 25;										# Use the default port (lookup is stupid since the port may not
																# be configured on the client machine)
	$ServerIPAddress = inet_aton($::g_sServerAddress);	# do the dns lookup and get the ip address
	if (!defined $ServerIPAddress)					# lookup failed
		{
		$sHTML .= FormatReceived("FAILED. $!");
		$bPassed = $::FALSE;
		goto ERRORNOCLOSE;
		}
	$sHTML .= FormatReceived("OK");

	$sHTML .= FormatSent("Create socket address...");
	$them = sockaddr_in($nSmtpPort, $ServerIPAddress); # create the sockaddr
	if (!defined $them)									# sockaddr undefined
		{
		$sHTML .= FormatReceived("FAILED. $!");
		$bPassed = $::FALSE;
		goto ERRORNOCLOSE;
		}
	$sHTML .= FormatReceived("OK");

	$sHTML .= FormatSent("Create socket...");
	unless (socket(MYSOCKET, PF_INET, SOCK_STREAM, $nProto)) # create the socked
		{
		$sHTML .= FormatReceived("FAILED. $!");	# this socket operation failed
		$bPassed = $::FALSE;
		goto ERRORNOCLOSE;
		}
	$sHTML .= FormatReceived("OK");

	$sHTML .= FormatSent("Connecting to socket...");
	unless (connect(MYSOCKET, $them))				# connect to the remote host
		{
		$sHTML .= FormatReceived("FAILED. $!");
		$bPassed = $::FALSE;
		goto ERROR;
		}
	$sHTML .= FormatReceived("OK"); 					# connection established

	binmode MYSOCKET; 									# just incase

	my($oldfh) = select(MYSOCKET);					# make MYSOCKET the current file handle
	$| = 1;													# make each command send a flush
	select($oldfh);										# return to the default file handle
	my $SMTPSocket = *MYSOCKET;						# get the reference of the socket
	my $nResult;											# $::SUCCESS if the response was OK

	$sHTML .= FormatSent("The connect message from the SMTP server...");
	($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
	if (length $sMessage)								# if there was an answer
		{
		$sHTML .= FormatReceived($sMessage);
		}
		else													# the server not responded
		{
		$sHTML .= FormatReceived('No response from the server.');
		}
	if ($nResult != $::SUCCESS)						# check for failures
		{
		$bPassed = $::FALSE;
		goto ERROR;
		}

	$sHTML .= FormatSent("Sent: HELO $sLocalhost");
	unless (print MYSOCKET "HELO $sLocalhost\r\n")	# start the conversation with the SMTP server
		{
		$sHTML .= FormatReceived("FAILED. $!");
		$bPassed = $::FALSE;
		goto ERROR;
		}

	($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
	$sHTML .= FormatReceived($sMessage);
	if ($nResult != $::SUCCESS)						# check for failures
		{
		$bPassed = $::FALSE;
		goto ERROR;
		}

	if ($::g_sEmailAddress ne "")
		{
		$sHTML .= FormatSent("Sent: MAIL FROM:&lt;" . $::g_sEmailAddress . ">");
		unless (print MYSOCKET "MAIL FROM:<" . $::g_sEmailAddress . ">\r\n") # specify the origin (I will have the self as the origin)
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		$sHTML .= FormatReceived($sMessage);
		if ($nResult != $::SUCCESS)						# check for failures
			{
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: RCPT TO:&lt;" . $::g_sEmailAddress . ">");
		unless (print MYSOCKET "RCPT TO:<",$::g_sEmailAddress,">\r\n") # reciepient is always the supplier
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		$sHTML .= FormatReceived($sMessage);
		if ($nResult != $::SUCCESS)						# check for failures
			{
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: DATA");
		unless (print MYSOCKET "DATA\r\n")			# the rest of the is the message body until the <CRLF>.<CRLF>
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		$sHTML .= FormatReceived($sMessage);
		if ($nResult != $::SUCCESS)						# check for failures
			{
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: From: $::g_sEmailAddress");
		unless (print MYSOCKET "From: $::g_sEmailAddress\r\n") # subject
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: Subject: This is a test email from Actinic Catalog.");
		unless (print MYSOCKET "Subject: This is a test email from Actinic Catalog.\r\n") # subject
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: To: $::g_sEmailAddress");
		unless (print MYSOCKET "To: $::g_sEmailAddress\r\n") # subject
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: Reply-To: $::g_sEmailAddress");
		unless (print MYSOCKET "Reply-To: $::g_sEmailAddress\r\n\r\n") # subject
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: This is the test message from Actinic Catalog.");
		unless (print MYSOCKET "This is the test message from Actinic Catalog.\r\n") # the message
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}
		$sHTML .= FormatSent("Sent: The email address and SMTP server you specified");
		unless (print MYSOCKET "The email address and SMTP server you specified\r\n") # the message continued
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}
		$sHTML .= FormatSent("Sent: in the network preferences are correct.");
		unless (print MYSOCKET "in the network preferences are correct.\r\n") # continued some more
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		$sHTML .= FormatSent("Sent: .");
		unless (print MYSOCKET "\r\n.\r\n") 		# finish the message
			{
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}
		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		$sHTML .= FormatReceived($sMessage);
		if ($nResult != $::SUCCESS)						# check for failures
			{
			$bPassed = $::FALSE;
			goto ERROR;
			}
		}
	else
		{
		$sHTML .= FormatSent("NOOP");
		unless (print MYSOCKET "NOOP\r\n")			# no email address - just check the
			{													# response to a no-op
			$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
			$bPassed = $::FALSE;
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		$sHTML .= FormatReceived($sMessage);
		if ($nResult != $::SUCCESS)						# check for failures
			{
			$bPassed = $::FALSE;
			goto ERROR;
			}
		}

	sleep 1; 												# pause

	$sHTML .= FormatSent("QUIT");
	unless (print MYSOCKET "QUIT\r\n")				# end the conversation
		{
		$sHTML .= FormatReceived("FAILED. $!");	# this communication failed
		$bPassed = $::FALSE;
		goto ERROR;
		}

	($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
	$sHTML .= FormatReceived($sMessage);
	if ($nResult != $::SUCCESS)						# check for failures
		{
		$sHTML .= FormatReceived("FAILED. $!");
		$bPassed = $::FALSE;
		goto ERROR;
		}

ERROR:														# jump to here on error

	sleep 1; 												# pause

	shutdown MYSOCKET, 1;								# shutdown sends

	while ($sMessage = <MYSOCKET>)					# clear the buffer
		{
		$sHTML .= FormatReceived($sMessage);
		}

	close MYSOCKET;										# done

ERRORNOCLOSE:												# jump to here on error before the connection is established

	if ($bPassed)											# check if the test passed
		{
		$sHTML .= FormatSent('SMTP Test passed');
		}
		else
		{
		$sHTML .= FormatSent('SMTP Test failed');
		}
	$sHTML .= FormatSent('_____ End of SMTP Test ____');

	return ($sHTML);
	}

###############################################################
#
# FormatSent	-	format messages sent to SMTP
#
# Params:	Text to be formatted
#
# Returns:	Formated text
#
###############################################################

sub FormatSent
	{
	return($_[0] . "<BR>");
	}

###############################################################
#
# FormatReceived	-	format messages sent to SMTP
#
# Params:	Text to be formatted
#
# Returns:	Formated text
#
###############################################################

sub FormatReceived
	{
	return("<BLOCKQUOTE>$_[0]</BLOCKQUOTE>");
	}

#######################################################
#
# CheckSMTPResponse	-	Checks if the SMTP server
#								response is an error message
#								checks also if there were
#								any response at all
#								See RFC 821 for details
#
# Params:	0	-	SMTP socket
#
# Returns:	0	$::SUCCESS	-	if SMTP command accepted
#					$::FAILURE	-	if any error occured or
#										nothing was responded
#				1	response from the server
#
#######################################################

sub CheckSMTPResponse
	{
	my $pSocket = shift;
	my ($sMessage, $sMsg, $sCode, $bMore, $nResult);

	$nResult = $::SUCCESS;
	do
		{
		$sMsg = readline($pSocket);					# read a line from SMTP server
		$sMsg =~ /^(\d\d\d)(.?)/;						# parse and get response code and contiune flag
		$sCode = $1;										# get response code
		$bMore = $2 eq "-";								# check if there is another line of this response
		if (length $sMessage)							# insert line break after every line, if the response is multiline
			{
			$sMessage .= "<BR>";
			}
		$sMessage .= $sMsg;								# collect all line, if the response is multiline
		if (length $sCode < 3)							# not a valid SMTP response
			{
			$nResult = $::FAILURE;						# bad response code
			}
		if ($sCode =~ /^[45]/)							# if it is an error message
			{
			$nResult = $::FAILURE;						# this is an error response
			}
		} while ($bMore);									# continue reading if further line is reported
	return ($nResult, $sMessage);
	}

###############################################################
#
# GetHostName - determines the actual host's name
#
# Returns:	the host name
#
###############################################################

sub GetHostName
	{
	my $sLocalhost = $ENV{SERVER_NAME}; 			# try the environment
	$sLocalhost =~ s/[^-a-zA-Z0-9.]//g; 			# strip any bad characters

	if (!$sLocalhost) 									# if still no hostname is found
		{
		$sLocalhost = $ENV{HOST};						# try a different environment variable
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g; 		# strip any bad characters
		}
	if (!$sLocalhost) 									# if still no hostname is found
		{
		$sLocalhost = $ENV{HTTP_HOST};				# try a different environment variable
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g; 		# strip any bad characters
		}
	if (!$sLocalhost) 									# if still no hostname is found
		{
		$sLocalhost = $ENV{LOCALDOMAIN}; 			# try a different environment variable
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g; 		# strip any bad characters
		}
	if (!$sLocalhost) 									# if still no hostname is found
		{
		$sLocalhost = `hostname`;						# try the command line
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g; 		# strip any bad characters
		}
	if (!$sLocalhost &&									# if still no hostname and
		 $::g_bIsWindowsOS)								# NT
		{
		my $sHost = `ipconfig`; 						# run ipconfig and gather the collection of addresses
		$sHost =~ /IP Address\D*([0-9.]*)/; 		# get the first address in the list
		$sLocalhost = $1;
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g; 		# strip any bad characters
		}
	return($sLocalhost);
	}

###############################################################
#
# PrintPage - print the HTML page
#
#	Params: 	0 - HTML to print
#				1 - source reference cookie
#
###############################################################

sub PrintPage
	{
	my ($nLength, $sHTML, $sCookie);
	($sHTML, $sCookie) = @_;

	$nLength = length $sHTML;

	binmode STDOUT;										# dump in binary mode so the line breaks are correct and the data is not corrupted

	PrintHeader('text/html', $nLength, $sCookie);

	print $sHTML;											# the body
	}

###############################################################
#
# PrintHeader - print the HTTP header
#
#	Params: 	0 - content type
#				1 - content length
#				2 - cookie
#
###############################################################

sub PrintHeader
	{
	my ($sType, $nLength, $sCookie) = @_;
	#
	# Build a date for the expiry
	#
	my (@expires, $day, $month, $now, $later, @now, $sNow);
	my (@days) = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
	my (@months) = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

	$now = time;
	@now = gmtime($now);
	$day = $days[$now[6]];
	$month = $months[$now[4]];
	$sNow = sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT", $day, $now[3],
							$month, $now[5]+1900, $now[2], $now[1], $now[0]);

	if($ENV{'PerlXS'} eq 'PerlIS')					# Windows IIS6 may be using PerIS.dll insteasd of perl.exe
		{
		print "HTTP/1.0 200 OK\n";						# so we must insert the protocol and return status
		}

	print "Date: $sNow\r\n";							# print the date to allow the browser to compensate between server and client differences

	print "Content-type: $sType\r\n";
	print "Content-length: $nLength\r\n\r\n";
	}

###############################################################
#
# ReadAndParseInput - read the input and parse it
#
# Expects:	$::ENV to be defined
#
# Returns:	0 - status
#				1 - error message
#				2 - the input string
#				3 - spacer to keep output even
#				4+ - input hash table
#
###############################################################

sub ReadAndParseInput
	{
	my ($InputData, $nInputLength);

	if ( (length $::ENV{'QUERY_STRING'}) > 0)		# if there is query string data (GET)
		{
		$InputData = $::ENV{'QUERY_STRING'};		# read it
		$nInputLength = length $InputData;
		}
	else														# otherwise, there must be a POST
		{
		my ($nStep, $InputBuffer);
		$nInputLength = 0;
		$nStep = 0;
		while ($nInputLength != $ENV{'CONTENT_LENGTH'})	# read until you have the entire chunk of data
			{
			#
			# read the input
			#
			binmode STDIN;
			$nStep = read(STDIN, $InputBuffer, $ENV{'CONTENT_LENGTH'});  # Set $::g_InputData equal to user input
			$nInputLength += $nStep;					# keep track of the total data length
			$InputData .= $InputBuffer;				# append the latest chunk to the total data buffer
			if (0 == $nStep)								# EOF
				{
				last;											# stop read
				}
			}

		if ($nInputLength != $ENV{'CONTENT_LENGTH'})
			{
			return ($::FAILURE, "Bad input.  The data length actually read ($nInputLength) does not match the length specified " . $ENV{'CONTENT_LENGTH'} . "\n", '', '', 0, 0);
			}
		}
	$InputData =~ s/&$//;								# loose any bogus trailing &'s
	$InputData =~ s/=$/= /;								# make sure trailing ='s have a value
	my ($OriginalInputData);
	$OriginalInputData = $InputData;					# copy the input string for use later

	if ($nInputLength == 0)								# error if there was no input
		{
		return ($::FAILURE, "The input is NULL", '', '', 0, 0);
		}
	#
	# parse and decode the input
	#
	my (@CheckData, %DecodedInput);
	@CheckData = split (/[&=]/, $InputData);		# check the input line
	if ($#CheckData % 2 != 1)
		{
		return ($::FAILURE, "Bad input string \"" . $InputData . "\".  Argument count " . $#CheckData . ".\n", '', '', 0, 0);
		}
	my %EncodedInput = split(/[&=]/, $InputData);	# parse the input hash
	my ($key, $value);
	while (($key, $value) = each %EncodedInput)
		{
		$key = DecodeText($key, $ACTINIC::FORM_URL_ENCODED);	# decode the hash entry
		$value = DecodeText($value, $ACTINIC::FORM_URL_ENCODED);
		if ( ($key =~ /\0/ ||								# check for poison NULLs
			  $value =~ /\0/))
			{
			return ($::FAILURE, "Input contains invalid characters.", undef, undef, undef, undef);
			}

		$DecodedInput{$key} = $value;
		}

	return ($::SUCCESS, '', $OriginalInputData, '', %DecodedInput);
	}

###############################################################
#
# DecodeText - this function is similar
#	to EncodeText with two exceptions: 1) it deals with
#	characters stored as %xx and 2) it works in reverse
#	restoring the character for the % value
#
# Params:	0 - the string to convert
#				1 - decode method flag $ACTINIC::HTML_ENCODED or $ACTINIC::FORM_URL_ENCODED or $ACTINIC::MODIFIED_FORM_URL_ENCODED
#					$ACTINIC::HTML_ENCODED = standard html encoding (&)
#					$ACTINIC::FORM_URL_ENCODED = decode using application/x-www-form-urlencoded (%xx)
#					$ACTINIC::MODIFIED_FORM_URL_ENCODED = Actinic format - identical to $::FORM_URL_ENCODED except an
#						underscore is used instead of a percent sign and the string is
#						prepended with an "a".  This encoding is used to map arbitrary
#						strings into HTML "ID and NAME" data types.
#						NAME tokens must begin with a letter ([A-Za-z]) and may be
#						followed by any number of letters, digits ([0-9]), hyphens ("-"),
#						underscores ("_"), colons (":"), and periods (".")
#
# Returns:	($sString) - the converted string
#
###############################################################

sub DecodeText
	{

	my ($sString, $eEncoding) = @_;

	if ($eEncoding == $ACTINIC::MODIFIED_FORM_URL_ENCODED)
		{
		$sString =~ s/^a//;								# string the leading a
		$sString =~ s/_([A-Fa-f0-9]{2})/pack('c',hex($1))/ge;	# Convert _XX from hex numbers to character equivalent
		}
	elsif ($eEncoding == $ACTINIC::FORM_URL_ENCODED)
		{
		$sString =~ s/\+/ /g;							# replace + signs with the spaces they represent
		$sString =~ s/%([A-Fa-f0-9]{2})/pack('c',hex($1))/ge;	# Convert %XX from hex numbers to character equivalent
		}
	elsif ($eEncoding == $ACTINIC::HTML_ENCODED)
		{
		$sString =~ s/&#([0-9]+);/chr($1)/eg;
		}

	return ($sString);
	}