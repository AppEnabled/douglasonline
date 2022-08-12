#!<actinic:variable name="PerlPath"/>

use Socket;
use Cwd;

push (@INC, "cgi-bin");

#######################################################
#                                                     #
# CATALOG CGI/PERL TEST SCRIPT                        #
#                                                     #
# Copyright (c) 1997 ACTINIC SOFTWARE LIMITED         #
#                                                     #
# written by George Menyhert                          #
#                                                     #
#######################################################

my ($Program, $Version);

umask (0666);												# update the process umask

$Program = "CATTEST";									# Program Name
$Version = '$Revision: 18819 $ ';							# program version
$Version = substr($Version, 11);						# strip the revision information
$Version =~ s/ \$//;									# and the trailers

$BAD = 0;													# define some constants
$GOOD = 1;
$::FALSE 	= 0;
$::TRUE	 	= 1;
$::FAILURE 	= 0;
$::SUCCESS 	= 1;

$gsMessage = "";											# initialize the message

#
# assume nothing works at first
#
$gMailServer 		= $BAD;								# problem contacting the mail server
$gPathToWeb 		= $BAD;								# path to the web site directory does not exist
$gWebPermissions 	= $BAD;								# unable to create a file in the web site directory
$gPostEnabled		= $BAD;								# the server does not support posts

$gsDirectory = '<actinic:variable name="PathFromCGIToWeb"/>';			# the path from the cgi-bin to the web site
#
# Some messages from prompts
#
$gsTestEmailMsg 			= '<actinic:variable name="TestEmailMessage" encoding="perl"/>';
$gsTestMsg 					= '<actinic:variable name="TestMessage" encoding="perl"/>';
$gsEmailAddressMsg 		= '<actinic:variable name="EmailAddressMessage" encoding="perl"/>';
$gsNetworkSettingsMsg 	= '<actinic:variable name="NetworkSettingMessage" encoding="perl"/>';
$gsTestSSL					= '<actinic:variable name="SSLTest"/>';
$gsDirError					= '<actinic:variable name="ReadDirectoryErrorMessage"/>' . "\r\n\r\n";	# An error occurred trying to read %s\r\n\r\n
$gsCGIDir					= '<actinic:variable name="CGIDirectoryErrorMessage"/>';				# CGI-BIN Working Directory
$gsDirContent				= '<actinic:variable name="DirectoryContentErrorMessage"/>' . "\r\n";	# %s Directory Contents\r\n
$gsCGIContent				= '<actinic:variable name="CGIContentErrorMessage"/>' . "\r\n";			# CGI-BIN Working Directory Contents\r\n
$gsErrInvalidPath			= '<actinic:variable name="InvalidPathErrorMessage"/>' . "\r\n";		# The path to the web site directory you specified (%s) points to a file.\r\n
$gsErrNoPOST				= '<actinic:variable name="NoPostErrorMessage"/>' . "\r\n\r\n";			# No POSTed data was found\r\n\r\n
$gsErrCorruptPost			= '<actinic:variable name="CorruptPostErrorMessage"/>' . "\r\n\r\n";	# POSTed data was corrupted \"%s\"\r\n\r\n
$gsErrCannotRead			= '<actinic:variable name="CannotReadErrorMessage"/>' . "\r\n";
$gsErrCannotWrite			= '<actinic:variable name="CannotWriteErrorMessage"/>' . "\r\n";
$gsErrCannotCreateFile	= '<actinic:variable name="CannotCreateFileErrorMessage"/>';
$gsErrCannotCreateDir	= '<actinic:variable name="CannotCreateDirectoryErrorMessage"/>';
$gsErrDNSFail				= '<actinic:variable name="DNSErrorMessage"/>';
$gsErrSockAddrFail		= '<actinic:variable name="SocketAddrFailErrorMessage"/>';
$gsErrSockFail				= '<actinic:variable name="SocketFailErrorMessage"/>';
$gsErrConnectFail			= '<actinic:variable name="ConnectFailErrorMessage"/>';
$gsErrGeneralFail			= "\t" . '<actinic:variable name="GeneralFailErrorMessage"/>' . "\r\n";
$gsErrGeneralPrint		= "\t" . '<actinic:variable name="GeneralPrintErrorMessage"/>' . "\r\n";
$gsErrMailMsg				= '<actinic:variable name="MailServerMessage"/>' . "\r\n\r\n";
$gsSMTPMandatory 			= '<actinic:variable name="NeedSMTP"/>';

my $sMessage = "Actinic Mail Test completed successfully\r\n";
my $PASSED = "passed";
my $FAILED = "failed";

# SMTP Authectication parameters
$::sSMTPUsername = '<actinic:variable name="SmtpUserName"/>';
$::sSMTPPassword = '<actinic:variable name="SmtpPassword"/>';
$::bSTMPAuth = <actinic:variable name="SmtpAuth"/>;

if ($gsTestSSL eq 'FALSE')
	{
	CheckPOST();											# check the POST operation
	
	if($gsSMTPMandatory eq 'TRUE')
		{
		my ($bDNS, $bConnect, $bSocket, $bCommunication, $bAuthorisation, $sError) =
		CheckSendMail();
		#
		# Response must be of the format
		#
		#		server:				passed/failed
		#		sockets: 			passed/failed
		#		connection: 		passed/failed
		#		communications:	passed/failed
		#		authorisation:		passed/failed
		#		message: 			<operating system error message>
		#
		$sMessage .= "server:\t\t" . ($bDNS ? $PASSED : $FAILED) ."\r\n";
		$sMessage .= "connection:\t" . ($bConnect ? $PASSED : $FAILED) ."\r\n";
		$sMessage .= "sockets:\t\t" . ($bSocket ? $PASSED : $FAILED) ."\r\n";
		$sMessage .= "communications:\t" . ($bCommunication ? $PASSED : $FAILED) ."\r\n";
		$sMessage .= "authorisation:\t" . ($bAuthorisation ? $PASSED : $FAILED) ."\r\n";
		$sMessage .= "message:\t\t" .							# ensure some text goes back in the message block
		( (length $sError) > 0 ? $sError : '-') ."\r\n";	    # or the C++ has trouble parsing it
		
		$gsMessage = $sMessage;
		}
	}
else
	{
	$gMailServer = $GOOD;
	$gPostEnabled = $GOOD;
	}

CheckPathToWeb();											# check the path from the cgi-bin dir to the web site dir

CheckWebSitePermissions();								# check the web site permissions

my $bCgiBinDirProblem = CheckCgiBin();				# check if the server executes the cgi scripts in the cgi-bin
#
# build and send the reply
#
my ($nLength, $Response);
$nLength = length($gsMessage);

$Response = "20000" .
   $gMailServer . $gPathToWeb . $gWebPermissions .
   $gPostEnabled . $bCgiBinDirProblem .
   $nLength . " " . $gsMessage;						# generate the complete response message

$nLength = length($Response);							# calculate the length of the entire response
#
# Build a date for the expiry
#
my ($day, $month, $now, @now, $sNow);
my (@days) = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
my (@months) = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

$now = time;
@now = gmtime($now);
$day = $days[$now[6]];
$month = $months[$now[4]];
$sNow = sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT", $day, $now[3],
					 $month, $now[5]+1900, $now[2], $now[1], $now[0]);

binmode STDOUT;											# the return message is binary so the data is not corrupted

if($ENV{'PerlXS'} eq 'PerlIS')					# Windows IIS6 may be using PerIS.dll insteasd of perl.exe
	{
	print "HTTP/1.0 200 OK\n";						# so we must insert the protocol and return status
	}

print "Content-type: text/plain\r\n";				# finish the http header
print "Content-length: $nLength\r\n";
print "Date: $sNow\r\n\r\n";							# print the date to allow the browser to compensate between server and client differences

print $Response;											# send the user data

exit;

#######################################################
#																		#
# CheckPOST                                           #
#																		#
# Read and check the POST input                       #
#                                                     #
#######################################################

sub CheckPOST
	{
	my ($InputData, $nInputLength, $sOriginalData);

	#
	# Read the POSTED data
	#
	binmode STDIN;
	read(STDIN, $InputData, $ENV{'CONTENT_LENGTH'});
	$nInputLength = length $InputData;
	$sOriginalData = $InputData;

	if ($nInputLength == 0)								# error if there was no input
		{
		$gsMessage = $gsErrNoPOST;
		return;
		}

	$InputData =~ s/&$//;								# loose any bogus trailing &'s
	$InputData =~ s/=$/= /;								# make sure trailing ='s have a value
	#
	# parse and decode the input
	#
	my (@CheckData, %DecodedInput);
	@CheckData = split (/[&=]/, $InputData);		# check the input line
	if ($#CheckData % 2 != 1)
		{
		$gsMessage = sprintf($gsErrCorruptPost, $sOriginalData);
		}
	my %EncodedInput = split(/[&=]/, $InputData);	# parse the input hash
	my ($key, $value);
	while (($key, $value) = each %EncodedInput)
		{
		$key =~ s/\+/ /g;									# replace + signs with the spaces they represent
		$key =~ s/%([A-Fa-f0-9]{2})/pack("c",hex($1))/ge; # Convert %XX from hex numbers to character equivalent
		$value =~ s/\+/ /g;								# replace + signs with the spaces they represent
		$value =~ s/%([A-Fa-f0-9]{2})/pack("c",hex($1))/ge; # Convert %XX from hex numbers to character equivalent
		$DecodedInput{$key} = $value;
		}

	if ($DecodedInput{'ACTINIC'} eq "RULES")
		{
		$gPostEnabled = $GOOD;							# the POST was successful
		}

	return;
	}

#######################################################
#                                                     #
# CheckPathToWeb                                   	#
#																		#
# Make sure the specified path from the web site dir  #
#   is valid.                                         #
#                                                     #
#######################################################

sub CheckPathToWeb
	{
	#
	# check
	#	exists
	#	is a directory
	#
	my $sMessage;
	if (!-e $gsDirectory)								# if the directory does not exist
		{
		$sMessage = BuildWebDirMessage();			# build the error message
		}
	if (!-d $gsDirectory)
		{
		$sMessage .= sprintf($gsErrInvalidPath, $gsDirectory);
		}

	if ($sMessage eq "")
		{
		$gPathToWeb = $GOOD;								# path is ok
		}
	else
		{
		$gsMessage .= $sMessage . "\r\n";
		}
	}

#######################################################
#
# CheckCgiBin - see if the server executes cgi scripts
#	in the cgi-bin.
#
# Returns:	$GOOD if it does or $BAD if not
#
#######################################################

sub CheckCgiBin
	{
	my $sScriptName = $ENV{'SCRIPT_NAME'};			# get the full script name/path from the server
	my @ParsedScriptPath = split('/', $sScriptName);
	$sScriptName = $ParsedScriptPath[-1];			# get just the script name from the path
	#
	# see if the script is in the current directory
	#
	if (!$sScriptName)									# if the script name is blank
		{
		return($GOOD);										# assume all is ok
		}
	elsif (-e $sScriptName)								# if the script exists in this directory
		{
		return ($GOOD);									# it is OK
		}
	else
		{
		return ($BAD);
		}
	}

#######################################################
#                                                     #
# CheckWebSitePermissions                          	#
#																		#
# Make sure the web site directory allows read/write  #
#   from CGI scripts.                                 #
#                                                     #
#######################################################

sub CheckWebSitePermissions
	{
	my ($sTestFile, $sMessage);

	if (!-r $gsDirectory)
		{
		$sMessage .= $gsErrCannotRead;
		}
	if (!-w $gsDirectory)
		{
		$sMessage .= $gsErrCannotWrite;
		}
	$sTestFile = $gsDirectory . "test_blah.dat";	# create the full test filename
	if (open(TESTFILE, ">$sTestFile"))				# attempt to open the file for writing
		{
		close (TESTFILE);									# close the file
		chmod 0666, $sTestFile;							# make sure the file is removable
		unlink ($sTestFile);								# remove the file
		}
	else
		{
		$sMessage .= $gsErrCannotCreateFile . "\r\n\r\n\t $! \r\n\r\n";
		}
	my $sFile = $gsDirectory . "__ActinicCgiTestSampleDir";
	if (mkdir $sFile, 0766)
		{
		rmdir $sFile;
		}
	else
		{
		$sMessage .= $gsErrCannotCreateDir . "\r\n\r\n\t $! \r\n\r\n";
		}

	if ($sMessage eq "")
		{
		$gWebPermissions = $GOOD;						# successful
		}
	else
		{
		$gsMessage .= $sMessage;
		}
	}

#######################################################
#
# GetHostname - attempt to retrieve the hostname
#
#	Returns:	0 - hostname or IP address or ''
#
#######################################################

sub GetHostName
	{
	my $sLocalhost = $ENV{SERVER_NAME};				# try the environment
	$sLocalhost =~ s/[^-a-zA-Z0-9.]//g;				# strip any bad characters

	if (!$sLocalhost)										# if still no hostname is found
		{
		$sLocalhost = $ENV{HOST};						# try a different environment variable
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g;			# strip any bad characters
		}
	if (!$sLocalhost)										# if still no hostname is found
		{
		$sLocalhost = $ENV{HTTP_HOST};				# try a different environment variable
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g;			# strip any bad characters
		}
	if (!$sLocalhost)										# if still no hostname is found
		{
		$sLocalhost = $ENV{LOCALDOMAIN};				# try a different environment variable
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g;			# strip any bad characters
		}
	if (!$sLocalhost)										# if still no hostname is found
		{
		$sLocalhost = `hostname`;						# try the command line
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g;			# strip any bad characters
		}
	if (!$sLocalhost &&									# if still no hostname and
		 $^O eq 'MSWin32')								# NT
		{
		my $sHost = `ipconfig`;							# run ipconfig and gather the collection of addresses
		$sHost =~ /IP Address\D*([0-9.]*)/;			# get the first address in the list
		$sLocalhost = $1;
		$sLocalhost =~ s/[^-a-zA-Z0-9.]//g;			# strip any bad characters
		}

	return ($sLocalhost);
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
#				1	-	$bDetail request for detailed response
#									for authentication
#
# Returns:	0	$::SUCCESS	-	if SMTP command accepted
#					$::FAILURE	-	if any error occured or
#										nothing was responded
#				1	-	response message from the server
#				2	-	if $bDetail is $::TRUE, then a list
#						with all line(s) of response in format:
#						"code,message"
#
#######################################################

sub CheckSMTPResponse
	{
	my ($pSocket, $bDetail) = @_;
	my ($sMessage, $sCode, $bMore, $nResult, @lDetails);

	$nResult = $::SUCCESS;
	do
		{
		my $sTemp;
		$sMessage = readline($pSocket);				# read a line from SMTP server
		$sMessage =~ s/^(\d\d\d)(.?)//;				# parse and remove response code and contiune flag
		$sCode = $1;										# get response code
		$bMore = $2 eq "-";								# check if there is another line of this response
		if ($bDetail)
			{
			$sTemp = $sCode . ',' . $sMessage;		# construct the detail line
			push @lDetails, $sTemp;						# add it to the list
			}
		if (length $sCode < 3)							# not a valid SMTP response
			{
			$nResult = $::FAILURE;						# bad response code
			}
		if ($sCode =~ /^[45]/)							# if it is an error message
			{
			$nResult = $::FAILURE;						# this is an error response
			}
		} while ($bMore);									# continue reading if further line is reported
	if ($bDetail)
		{
		return ($nResult, $sMessage, @lDetails);
		}
	else
		{
		return ($nResult, $sMessage);
		}
	}

#######################################################
#
# CheckSendMail - check the mail server
#
# Returns:	0 - out - false if server DNS failed
#				1 - out - false if connection to server
#								failed
#				2 - out - false if generic socket error
#								occurred
#				3 - out - false if the server responded
#								with an error
#				4 - out - error message if any
#
#######################################################

sub CheckSendMail
	{
	my ($bDNS, $bConnection, $bSocket, $bCommunication, $bAuthorisation, $sError) =
		(undef, undef, undef, undef, undef, "");
	my (@lDetails);
	my ($sEmailAddress, $sServerAddress);

	$sEmailAddress = '<actinic:variable name="Email" encoding = "perl"/>'; # get the email address
	$sServerAddress = '<actinic:variable name="SmtpServer" encoding = "perl"/>';	# get mail server host
	if ($sServerAddress eq "")
		{
		$sError = "Mail Server not Specified";
		goto ERRORNOCLOSE;
		}
	#
	# Gather the SMTP host, server, and socket information
	#
	my ($nProto, $them, $nSmtpPort, $sMessage, $ServerIPAddress);

	my $sLocalhost = GetHostName();

	$nProto = getprotobyname('tcp');
	$nSmtpPort = 25;										# Use the default port (lookup is stupid since the port may not
																# be configured on the client machine)

	$ServerIPAddress = inet_aton($sServerAddress);	# do the dns lookup and get the ip address
	if (!defined $ServerIPAddress)					# lookup failed
		{
		$sError = $!;
		goto ERRORNOCLOSE;
		}
	$bDNS = 1;												# DNS succeeded

	$them = sockaddr_in($nSmtpPort, $ServerIPAddress); # create the sockaddr
	if (!defined $them)									# sockaddr undefined
		{
		$sError = $!;
		goto ERRORNOCLOSE;
		}
	$bSocket = 1;											# socket operation succeeded

	unless (socket(MYSOCKET, PF_INET, SOCK_STREAM, $nProto)) # create the socked
		{
		$sError = $!;
		$bSocket = undef; 								# this socket operation failed
		goto ERRORNOCLOSE;
		}

	unless (connect(MYSOCKET, $them))				# connect to the remote host
		{
		$sError = $!;
		goto ERROR;
		}
	$bConnection = 1; 									# connection established

	binmode MYSOCKET; 									# just incase

	my($oldfh) = select(MYSOCKET);					# make MYSOCKET the current file handle
	$| = 1;													# make each command send a flush
	select($oldfh);										# return to the default file handle

	my $SMTPSocket = *MYSOCKET;
	my $nResult;											# $::SUCCESS if the response was OK
	($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
	if ($nResult != $::SUCCESS)						# check for failures
		{
		$sError = $sMessage;
		goto ERROR;
		}
	$bCommunication = 1; 								# communications are established

	my $sHelloMsg = ($::bSTMPAuth == $::TRUE ? 'EHLO ' : 'HELO ') . "$sLocalhost\r\n";
	unless (print MYSOCKET $sHelloMsg)				# start the conversation with the SMTP server
		{
		$sError = $!;
		$bCommunication = undef;						# this communication failed
		goto ERROR;
		}
	
	($nResult, $sMessage, @lDetails) = CheckSMTPResponse($SMTPSocket, $::TRUE);	# see what the SMTP server has to say
	if ($nResult != $::SUCCESS)						# check for failures
		{
		$sError = $sMessage;
		$bCommunication = undef;						# this communication failed
		goto ERROR;
		}
		
	if ($::bSTMPAuth == $::TRUE)						# check if Authentication is requested
		{
		($nResult, $sMessage) = SMTPAuthentication($SMTPSocket, @lDetails);	# call Authentication routine
		if ($nResult != $::SUCCESS)					# check for failures
			{
			$sError = $sMessage;							# Record internal error
			$bCommunication = undef;
			goto ERROR;
			}
		}
	$bAuthorisation = 1;									# authorisation successful
	
	if ($sEmailAddress ne "")
		{
		unless (print MYSOCKET "MAIL FROM:<" . $sEmailAddress . ">\r\n") # specify the origin (I will have the self as the origin)
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		if ($nResult != $::SUCCESS)						# check for failures
			{
			$sError = $sMessage;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "RCPT TO:<",$sEmailAddress,">\r\n") # reciepient is always the supplier
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		if ($nResult != $::SUCCESS)					# check for failures
			{
			$sError = $sMessage;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "DATA\r\n")			# the rest of the is the message body until the <CRLF>.<CRLF>
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		if ($nResult != $::SUCCESS)					# check for failures
			{
			$sError = $sMessage;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "From: $sEmailAddress\r\n") # subject
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "Subject: $gsTestEmailMsg\r\n") # subject
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "To: $sEmailAddress\r\n") # subject
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "Reply-To: $sEmailAddress\r\n\r\n") # subject
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "$gsTestMsg\r\n") 	# the message
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "$gsEmailAddressMsg\r\n") # the message continued
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "$gsNetworkSettingsMsg\r\n") # continued some more
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		unless (print MYSOCKET "\r\n.\r\n") 		# finish the message
			{
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}
		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		if ($nResult != $::SUCCESS)					# check for failures
			{
			$sError = $sMessage;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}
		}
	else
		{
		unless (print MYSOCKET "NOOP\r\n")			# no email address - just check the
			{													# response to a no-op
			$sError = $!;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}

		($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
		if ($nResult != $::SUCCESS)					# check for failures
			{
			$sError = $sMessage;
			$bCommunication = undef;					# this communication failed
			goto ERROR;
			}
		}

	sleep 1; 												# pause

	unless (print MYSOCKET "QUIT\r\n")				# end the conversation
		{
		$sError = $!;
		$bCommunication = undef;						# this communication failed
		goto ERROR;
		}

	($nResult, $sMessage) = CheckSMTPResponse($SMTPSocket);	# see what the SMTP server has to say
	if ($nResult != $::SUCCESS)						# check for failures
		{
		$sError = $sMessage;
		$bCommunication = undef;						# this communication failed
		goto ERROR;
		}

	$gMailServer = $GOOD;
	
ERROR:														# jump to here on error

	sleep 1; 												# pause
	
	shutdown MYSOCKET, 1;								# shutdown sends

	while ($sMessage = <MYSOCKET>)					# clear the buffer
		{
		# no-op
		}

	close MYSOCKET;										# done

ERRORNOCLOSE:												# jump to here on error before the connection is established

	return ($bDNS, $bConnection, $bSocket, $bCommunication, $bAuthorisation, $sError);
	}

#######################################################
#
# SMTPAuthentication	-	It does the SMTP authentication
#								before the normal S?TP process
#								See RFC 2554 for details
#
# Params:	0	-	SMTP socket
#				1	-	@lDetail initial response string
#									of the SMTP server
#
# Returns:	0	$::SUCCESS	-	if SMTP command accepted
#					$::FAILURE	-	if any error occured or
#										nothing was responded
#				1	-	response message from the server
#
#######################################################

sub SMTPAuthentication
	{
	my ($pSocket, @lDetails) = @_;
	my ($sOfferedMethods, @lsSupportedMethods, $sTemp, $sSelectedMethod, $sSelectedHandler, $sMessage, $nResult, $nCode, $sAnswer);
	eval
		{
		require <actinic:variable name="ActinicSmtpAuth"/>;
		};
	if ($@)
		{
		return ($::FAILURE, "Actinic SMTP Authentication Module NOT available in this server! Please do 'Update WebSite and then Redo the Test");
		}
	$ActinicSMTPAuth::sServername = GetHostName();	# set the hostname for Digest-MD5 authentication

	#
	# check if the response includes the AUTH string
	# which identify the Auth extension
	#
	foreach $sTemp (@lDetails)
		{
		my ($sCode, $sMessage) = split(/,/, $sTemp);
		if ($sTemp =~ /AUTH[ |=](.*)$/i)
			{
			$sOfferedMethods = $1;
			last;
			}
		}
	if (length $sOfferedMethods == 0)				# SMTP Authentication is not supported by this server
		{
		return ($::FAILURE, "SMTP Authentication is not supported by this server!");
		}
	for( my $nI = 0; $nI <= $#ActinicSMTPAuth::lsProtocol; $nI++)	# try to select the highest security level of auth method
		{
		if ($sOfferedMethods =~ /$ActinicSMTPAuth::lsProtocol[$nI]/i)
			{
			$sSelectedMethod = $ActinicSMTPAuth::lsProtocol[$nI];	# the name of the protocol
			$sSelectedHandler = $ActinicSMTPAuth::lpHandler[$nI];	# the handler routine in ActinicSMTPAuth.pm
			if (length $sSelectedMethod == 0)		# We couldn't find matching methods in Supported and offered methods!"
				{
				return ($::FAILURE, "We couldn't find matching methods in Supported and Offered methods!");
				}
			#
			# initiate the authentication process with the AUTH "$method" string
			#
			my $sAuthTrailer;
			($nResult, $sAuthTrailer) = &$sSelectedHandler(0, $sAnswer);	# get the AUTH command trailer string
			if ($nResult != $::SUCCESS)				# check for failures
				{
				return($::FAILURE, $sMessage);
				}
			$sTemp = "AUTH " . $sSelectedMethod . ' ' . $sAuthTrailer . "\r\n";
			unless (print $pSocket $sTemp)
				{
				$sMessage = GetPhrase(-1, 18, 2, $!);	# Record internal error
				return($::FAILURE, $sMessage);
				}
			my $bNeedMore = $::TRUE;
			for (my $nII = 1; 1; $nII++)				# do the necessery sends and receives
				{
				($nResult, $sMessage, @lDetails) = CheckSMTPResponse($pSocket, $::TRUE);	# see what the SMTP server's response
				$lDetails[0] =~ /([^,]*),(.*)/;
				$nCode = $1;
				$sAnswer = $2;
				#
				# Check the response code here.
				# If if it is 235, then we are authenticated,
				# else the response code must be 334 or error code
				#
				if ($nCode == 235)						# user is successfully authenticated
					{
					return ($::SUCCESS, '');
					}
				if ($nCode != 334)						# if the answer was not accepted by the server
					{
					last;										# fall back to the next method
					}
				#
				# Call the selected handler routine
				#
				($nResult, $sTemp, $bNeedMore) = &$sSelectedHandler($nII, $sAnswer);
				if ($nResult != $::SUCCESS)
					{
					return($::FAILURE, $sTemp);		# return the error for displaying
					}
				unless (print $pSocket $sTemp)		# send the string to the server
					{
					$sMessage = GetPhrase(-1, 18, 2, $!);	# Record internal error
					return($::FAILURE, $sMessage);
					}
				}
			}
		}
		return($::FAILURE, $nCode . ' ' . $sAnswer);	# return the answer for displaying
	}


#######################################################
#
# BuildWebDirMessage - Review the directory structure
#	and bulid a message from it.
#
# Returns: message
#
#######################################################

sub BuildWebDirMessage
	{
	my ($sDir);

	$sDir = cwd();											# read the current working directory
	if ($sDir eq "")										# if that didn't work
		{
		$sDir = getcwd();									# try to read it another way
		}

	my $sMessage;
	if (length ($sDir) > 0)
		{
		$sMessage .=										# note the current directory
	      $gsCGIDir . ": \"" . $sDir . "\"\r\n\r\n";
		}

	$sMessage .= ReadDirectoryPath($gsDirectory);# read each directory from here to there

	return ($sMessage);
	}

#######################################################
#
# ReadDirectoryPath - Read the directories from here
#	to the web directory and add the listing to the
#	output message.
#
# Returns: message
#
#######################################################

sub ReadDirectoryPath
	{
	my ($sPath, @DirArray, $sDir, $sCurrentDir, $Success, $Message, @Filelist, $sFile);

	$sPath = $_[0];										# retrieve the path to read

	#
	# first read the current directory (the CGI-BIN directory)
	#
	my $sMessage;
	@Filelist = ReadTheDir(".");						# read the current directory
	if (!defined @Filelist ||							# an error occured
		 $#Filelist < 0)
		{
		$sMessage .= sprintf($gsDirError, $gsCGIDir);
		}
	else														# the read was successful
		{														# append the contents of this directory to the list
		$sMessage .= $gsCGIContent;

		foreach $sFile (@Filelist)
			{
			$sMessage .= "\t$sFile\r\n";
			}
		$sMessage .= "\r\n";
		}

	@DirArray = split ('/', $sPath);					# parse the rest of the path

	$sCurrentDir = "";
	foreach $sDir (@DirArray)							# for each directory in the path
		{
		$sCurrentDir .= $sDir . "/";					# next directory

		@Filelist = ReadTheDir($sCurrentDir);		# read this directory
		if (!defined @Filelist ||						# an error occured
			 $#Filelist < 0)
			{
			$sMessage .= sprintf($gsDirError, "\"$sCurrentDir\"");
			next;
			}

		$sMessage .= sprintf($gsDirContent, "\"$sCurrentDir\"");

		foreach $sFile (@Filelist)						# append the contents of this directory to the list
			{
			$sMessage .= "\t$sFile\r\n";
			}
		$sMessage .= "\r\n";
		}

	return ($sMessage);
	}

#######################################################
#                                                     #
# ReadTheDir                                          #
#																		#
# Read the specified directory                        #
#                                                     #
#######################################################

sub ReadTheDir
	{
	my ($sPath, @FileList);
	$sPath = $_[0];

   if( opendir (NQDIR, "$sPath") )					# open the directory to get a file listing
		{														# if successful,
		@FileList = readdir (NQDIR);					# read the directory
		closedir (NQDIR);									# close the directory
		return (@FileList);								# return the directory contents
		}

	return;
	}