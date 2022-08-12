#!<Actinic:Variable Name="PerlPath"/>
################################################################
#
# download.pl - Digital download extension for Actinic Catalog
#
# Copyright (c) Actinic Software Ltd 2002
#
# $Revision: 21305 $
#
################################################################
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

use strict;
require <Actinic:Variable Name="DownloadModule"/>;
use CGI;

#
# Retrieve the encrypted download data
#
my $pCGI = new CGI;
my $DAT = $pCGI->param('DAT');						# get the query data
if (!$DAT ||												# validate the input - must exist
	 $DAT !~ /^[a-fA-F0-9]+$/ ||						# contain only hex bytes
	 (length $DAT) % 2 != 0)							# and have an even number of characters
	{
	Error("The link you clicked on was invalid. Please check the link and make sure you have included the entire URL.", $pCGI);
	exit;
	}
#
# Decrypt the input
#
my ($status, $sError, $nTime, $sFile) = DigitalDownload::_UnpackData($pCGI->param('DAT'));
if ($status != $DigitalDownload::SUCCESS)
	{
	Error($sError, $pCGI);
	exit;
	}
#
# Verify that the file is still accessible.  A special time value of $DigitalDownload::UNLIMITED means their is no limit to the download expiration.
#
if ($nTime != $DigitalDownload::UNLIMITED &&
	 $nTime < time())
	{
	Error("The download has expired.  Please contact us for the files.", $pCGI);
	exit;
	}
#
# Validate the filename
#
unless ($sFile =~ /^([-a-zA-Z0-9 _.]+)$/)
	{
	Error("Invalid filename.", $pCGI);
	exit;
	}
$sFile = $DigitalDownload::CONTENTPATH . $1;		# untaint the filename and build the complete path
#
# Make sure the file exists
#
unless (-e $sFile &&
		  -r $sFile &&
		  -f $sFile)
	{
	Error("Unable to access file.", $pCGI);
	exit;
	}
#
# Extract the presentation file name
#
my $sPresentationFilename;
if ($sFile =~ /.*?_\d+_([- _a-zA-Z0-9.]+)$/)		# the presentation filename is the trailing bit of the decorated file name
	{
	$sPresentationFilename = $1;						# grab the filename
	}
#
# Get the file size in bytes
#
my $SIZE_INDEX = 7;
my @temp = stat $sFile;
my $nSize = $temp[$SIZE_INDEX];						# get the file size
#
# Send the headers - By default we use NPH so we don't bog the server down with huge files in memory.  This can
# be disabled in digdown.pl by setting NPH to false.
#
if ($DigitalDownload::NPH)
	{
	$|=1;
	print $::ENV{SERVER_PROTOCOL} . " 200 OK\n";
	}

print "Content-type: application/octet\n";
print "Content-disposition: attachment; filename=$sPresentationFilename\n";
print "Content-length: $nSize\n";
print "Server: " . $::ENV{SERVER_SOFTWARE} . "\n";
#
# Build a date for the expiry
#
my ($day, $month, $now, $later, $expiry, @now, $sNow);
my (@days) = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
my (@months) = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

$now = time;
@now = gmtime($now);
$day = $days[$now[6]];
$month = $months[$now[4]];
$sNow = sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT", $day, $now[3],
					 $month, $now[5]+1900, $now[2], $now[1], $now[0]);

print "Date: $sNow\n\n";							# print the date to allow the browser to compensate between server and client differences
#
# Open the file and feed it to the client in BLOCKSIZE chunks
#
my $BLOCKSIZE = 512000;									# 500K blocks
unless (open (DAT, "<$sFile"))
	{
	Error("Unable to open file> $!", $pCGI);
	exit;
	}

binmode DAT;												# make sure we read
binmode STDOUT;											# and write binary

my $Block;

while (read DAT, $Block, $BLOCKSIZE)				# read BLOCKSIZE blocks
	{
	print $Block;											# pass them to the server
	}

close DAT;

exit;

###############################################################
#
# Error - Print application error
#
# Input:    0 - error string
#           1 - a pointer to a CGI object
#
###############################################################

sub Error
	{
	my ($sString, $pCGI) = @_;
	#
	# Dump the page
	#
	if ($DigitalDownload::NPH)							# respect the NPH mode
		{
		$|=1;													# make the pipes hot (autoflush)
		print $pCGI->header(-nph => 1);				# tell CGI about it
		}
	else														# regular parsed headers mode
		{
		print $pCGI->header;
		}
	print $pCGI->start_html("Error");
	print $pCGI->h1("Error");
	print $sString;
	print $pCGI->end_html;
	}
																#
