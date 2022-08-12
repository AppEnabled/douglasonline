#!<actinic:variable name="PerlPath"/>

#######################################################
#                                                     #
# CATALOG CGI/PERL TEST SCRIPT                       	#
#                                                     #
# Copyright (c) 1997 ACTINIC SOFTWARE LIMITED         #
#                                                     #
# written by George Menyhert                          #
#                                                     #
#######################################################

$Program = "CATTEST2";									# Program Name
$Version = '$Revision: 18819 $ ';							# program version
$Version = substr($Version, 11);						# strip the revision information
$Version =~ s/ \$//;										# and the trailers

$BAD = 0;													# define some constants
$GOOD = 1;
#
# assume nothing works at first
#
my ($bVersionState, $sMessage) =
	CheckPerlVersion();									# check the perl version
#
# check to see if CYBERsitter is mangling our code
#
my $bCyberSitter = $GOOD;
#
# The following line contains text that would usually be detected by network filters
# The use of 'bad language' is necessary here to trigger the filter
#
my $nSum = unpack('%32C*', "sexy fuck");
if ($nSum != 914)
	{
	$bCyberSitter = $BAD;
	$sMessage .= "It appears as if CyberSitter or some other network filter is mangling the CGI scripts.\r\n";
	}
#
# build and send the reply
#
$Response = "20000" . $bVersionState . $bCyberSitter . (length $sMessage) .
   " " . $sMessage;										# generate the complete response message

$nLength = length($Response);							# calculate the length of the entire response

#
# Turn on non-parsed headers by default when running under IIS server and Doug MacEachern's modperl
#
my $bNPH = 0;
if ( (defined($ENV{'SERVER_SOFTWARE'}) && $ENV{'SERVER_SOFTWARE'}=~/IIS/) ||
	  (defined($ENV{'GATEWAY_INTERFACE'}) && $ENV{'GATEWAY_INTERFACE'} =~ /^CGI-Perl/) ||
	  ($ENV{'PerlXS'} eq 'PerlIS'))					# Windows IIS6 may be using PerIS.dll insteasd of perl.exe
	{
	$bNPH = 1;
	}
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

binmode STDOUT;											# the return message is binary so the data is not corrupted and header line breaks are correct
#
# now print the header
#
if ($bNPH)
	{
	print "HTTP/1.0 200 OK\r\n";						# the status
	}
print "Content-type: text/plain\r\n";				# finish the http header
print "Content-length: $nLength\r\n";
print "Date: $sNow\r\n\r\n";							# print the date to allow the browser to compensate between server and client differences

print $Response;											# send the user data

exit;

#######################################################
# CheckPerlVersion
#
# Make sure the current Perl version is 5.002 or
#   greater.
#
# Returns:	0 - $GOOD or $BAD
#				1 - message
#
#######################################################

sub CheckPerlVersion
	{
	if ($] >= 5.002)										# check the perl version
		{
		return ($GOOD, "");
		}
	else
		{
		return ($BAD, "The current Perl version is $].\r\n");
		}
	}

