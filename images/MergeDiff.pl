#!<Actinic:Variable Name="PerlPath"/>

################################################################
#
# MergeDiff.pl - script to merge binary diffs into the
#  primary file.  To eliminate file access conflicts
#  merge the changes into a new file and then
#  rename the file when done.
#
# $Revision: 18819 $
#
################################################################

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

use File::Copy;
use strict;

#
# Constants for diff file
#

$::BD_COPY_32 = 0x01;									 # Copy x bytes (32 bit count)
$::BD_COPY_16 = 0x02;									 # Copy x bytes (16 bit count)
$::BD_COPY_8  = 0x03;									 # Copy x bytes (8 bit count)

$::BD_INSERT_32 = 0x04;									 # Insert following x bytes
$::BD_INSERT_16 = 0x05;									 # Insert following x bytes
$::BD_INSERT_8  = 0x06;									 # Insert following x bytes

$::BD_DELETE_32 = 0x07;									 # Delete x bytes
$::BD_DELETE_16 = 0x08;									 # Delete x bytes
$::BD_DELETE_8  = 0x09;									 # Delete x bytes

$::BD_CHECKSUM_TO = 0x0A;								 # 32 bit checksum of all bytes in 'to' file
$::BD_LENGTH_TO   = 0x0B;								 # 32 bit length of 'to' file

$::MAX_RETRY_COUNT      = 10;
$::RETRY_SLEEP_DURATION = 1;

$::s_bUseNonParsedHeaders = $::FALSE;
#
# Dump the HTTP headers so we can do proper non parsed header processing (for dynamic feedback)
#
PrepareResponse();
#
# Read the input strings.  We expect a list of file basenames, and the path.  In the future, this should change,
# but let's leave it for now.
#
my ($status, $sError, $sEnv, $unused);
($status, $sError, $sEnv, $unused, %::g_InputHash) = ACTINIC::ReadAndParseInput();
if ($::SUCCESS != $status)
	{
	SendResponse($sError . "\n");
	CompleteResponse();
	exit;
	}

my $sPath = ACTINIC::GetPath();						# retrieve the path
ACTINIC::SecurePath($sPath);							# make sure there is nothing funny going on
#
# Authenticate the user
#
($status, $sError) = ACTINIC::AuthenticateUser($::g_InputHash{USER}, $::g_InputHash{PASS});
if ($status != $::SUCCESS)
	{
	#
	# If authorization is failed return a custom message (the prompt file is not read yet
	# so $sError is meaningless)
	#
	SendResponse(InsertString("IDS_MD_AUTHORISATION_FAILED") . "\n");
	CompleteResponse();
	exit;
	}
#
# The following is the list of file base names that are to be merged from diff files.
#
my @Basenames = split(/ /, $::g_InputHash{BASE});
#
# Now do the work of merging the files
#
my $sBase;
foreach $sBase (@Basenames)							 # check each base name in the list
	{
   $sBase = ACTINIC::CleanFileName($sBase);		 # strip any bad characters

	SendResponse("Message: Applying changes to $sBase\n");

	($status, $sError) = BDApplyDiff($sPath . "old"  . $sBase . ".fil",
												$sPath . "full" . $sBase . ".fil",
												$sPath . "diff" . $sBase . ".fil");
	if ($::SUCCESS != $status)
		{
	   SendResponse($sError . "\n");
		CompleteResponse();
		exit;
		}
	}

SendResponse("OK\n");
CompleteResponse();
exit;

################################################################
#
# BDApplyDiff	- Apply a difference file.  If no difference file
#	exists, the function returns immediately.  Otherwise,
#	if a new file exists with the diff, the diff is applied
#	to the new file and saved under the old filename.  If
#	no new file exists, but an old one does, the diff is
#	applied to the old file and saved as the old file.  If
#	the diff file exists and no complete file exists, an
#	error is returned.  Under normal operation, a new file
#	should not exist, but it could happen if an upload is
#	cancelled before the merfer or errors out.  Finally,
#  If just a new file and an old file exist, just copy
#  the new file to the old file.
#
# Input:	   0 - Permanent filename (name of file from last
#               upload).
#               Typically oldtext.fil, oldprod.fil, etc.  Name
#               must include path.
#			   1 - New filename.  (new file from this upload)
#               Typically fulltext.fil, fullprod.fil,
#               etc.  Name must include path.
#			   2 - Name of difference file.  Name must include path.
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub BDApplyDiff
	{
#? ACTINIC::ASSERT($#_ == 2, "Incorrect parameter count BDApplyDiff(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($sOldFileName, $sNewFileName, $sDiffFileName) = @_;
	#
	# The differential file is applied as follows:
	#
	#	Old	New	Diff		Operation
	#
	#                       no-op
	#   X							no-op
	#         X             copy new to old
	#               X       error
	#   X     X             copy new to old
	#   X           X       apply diff to old
	#         X     X       copy new to old
	#   X     X     X       copy new to old
	#
	# In short: If there is a new file, copy the new file to the old.
	# If there is a differential file and no other then error out.
	# If there is a diff file and an old file but no new file then apply the diff to the old.
	# In any case, the resulting file is copied to the old.
	#
	# Diff files of zero length are considered non-existant, but left in place.
	#
#? ACTINIC::ASSERT(length $sOldFileName != 0, "Empty old file name", __LINE__, __FILE__);
#? ACTINIC::ASSERT(length $sNewFileName != 0, "Empty old file name", __LINE__, __FILE__);
#? ACTINIC::ASSERT(length $sDiffFileName != 0, "Empty old file name", __LINE__, __FILE__);
	#
	# If no new or diff file exists, there is nothing to do, just exit.
	#
	my $bDiffFileExists = (-e $sDiffFileName && 0 != -s $sDiffFileName);	# the diff file is considered to exist if it is there and not 0 bytes
	my $bNewFileExists = -e $sNewFileName;
	my $bOldFileExists = -e $sOldFileName;
	if (!$bNewFileExists &&								# if the new file is not there
		 !$bDiffFileExists)								# and the diff file is not there
		{
		return ($::SUCCESS, undef);					# nothing to do
		}
	#
	# At this point we have at least a diff or a new file
	# If new file exists at this point, just copy the new file over the old
	#
	if ($bNewFileExists)
		{
		if ($bOldFileExists)								# old file exitst
			{
			unlink($sOldFileName);						# attempt to manually remove the destination file as some systems do not automatically remove it with the copy command
			}
		if (!copy($sNewFileName, $sOldFileName))	# copy new file to old file
			{
			my $sError = $!;
			return ($::FAILURE, InsertString("IDS_MD_CORUPTINDEX", $sNewFileName, $sOldFileName, $sError));
			}
		else
			{
			return ($::SUCCESS, undef);				# all is well
			}
		}
	#
	# At this point we have a diff file
	# If no old file exists to apply the diff to, error out.
	#
	if (!$bOldFileExists)								# old file isn't there
		{
		return ($::FAILURE, InsertString("IDS_MD_NO_COMPLETE_FILE"));
		}
	#
	# If here, we are merging the diff file with the old file so open a temporary scratch file to write the merged changes to. 
	# Later we will overwrite the old file with the scratch file.
	#
	my $sPath = $sOldFileName;
	$sPath =~ s/[^\/]*$//;							 # strip the filename off of $sOldFileName to find the path
	my $sScratchFilePart = "aaaaaaaa";			 # build a temporary filename start point - would like to use POSIX::tmpnam, but don't want to
															 # require yet another package.
	my $nCount = 0;
	while (-e ($sPath . $sScratchFilePart . '.fil') && # loop until a unique file name is found
			 $nCount < 4000)							 # but don't loop forever
		{
		$sScratchFilePart++;							 # try a new file name
		}

	if (4000 == $nCount)								 # if no unique file
		{
		return ($::FAILURE, InsertString("IDS_MD_CANT_CREATE_UNIQUE_SCRATCH"));
		}

	my $sScratchFile = $sPath . $sScratchFilePart . '.fil'; # build the full scratch file path
	#
	# This is more of the norm as far as day to day operation goes.  There is an older
	# file and a differential file, but no "new" file.  The differential is applied
	# to the old file and written to a scratch file.  Later the scratch file is used to overwrite the old file.
	#
	my ($status, $sMessage) = OpenWithRetry(\*FROM, "<$sOldFileName");
	if ($status != $::SUCCESS)
		{
		return ($::FAILURE, InsertString("IDS_MD_CANT_OPEN_FROM", $sOldFileName,  $sMessage));
		}
	binmode FROM;

	($status, $sMessage) = OpenWithRetry(\*TO, ">$sScratchFile");
	if ($status != $::SUCCESS)
		{
		close(FROM);
		return ($::FAILURE, InsertString("IDS_MD_CANT_OPEN_TO", $sScratchFile,  $sMessage));
		}
	binmode TO;

	unless (open (DIFF, "<$sDiffFileName"))
		{
		my $sError = $!;
		close(TO);
		close(FROM);
		unlink ($sScratchFile);
		return ($::FAILURE, InsertString("IDS_MD_CANT_OPEN_DIFF", $sDiffFileName,  $sError));
		}
	binmode DIFF;

	my $sFromFile = $sOldFileName;
	#
	# Get the file length and init the progress meter
	#
	SendResponse("Progress: 0\n");
	my @tmp = stat DIFF;
	my $nFileLength = $tmp[7];
	#
	# Read the diff file and apply the differences to the the from file to generate
	# the to file
	#
	my ($status, $sError, $nLength, $nCommand, $Buffer);
	my $nChecksum = 0;
	my $nCurrentProgress = 0;

	while (!eof(DIFF))									# while there is diff data left in the file
		{
		#
		# Update the progress meter
		#
		if (0 < $nFileLength)							# if the file length is known
			{
			my $nProgress = int ((tell DIFF) / $nFileLength * 100);	# track the progress
			if (abs($nProgress - $nCurrentProgress) > 3)	# Only update the progress message from time to time
				{
				$nCurrentProgress = $nProgress;
				SendResponse("Progress: $nProgress\n"); # update the progress meter
				}
			}

		unless (1 == read DIFF, $Buffer, 1)			 # Read the command
			{
			last;
			}

		($nCommand) = unpack "C", $Buffer;			 # unpack the binary data into a command

		if ($::BD_COPY_32 == $nCommand)				 # Copy x bytes (32 bit count)
			{
			($status, $sError, $nLength) = BDGetLength32(\*DIFF);	# Get 32 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			($status, $sError, $nChecksum) = BDCopyData(\*FROM, \*TO, $nLength, $nChecksum); # Copy the data
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}
			}
		elsif ($::BD_COPY_16 == $nCommand)			 # Copy x bytes (16 bit count)
			{
			($status, $sError, $nLength) = BDGetLength16(\*DIFF);	# Get 16 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			($status, $sError, $nChecksum) = BDCopyData(\*FROM, \*TO, $nLength, $nChecksum); # Copy the data
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}
			}
		elsif ($::BD_COPY_8 == $nCommand)			 # Copy x bytes (8 bit count)
			{
			($status, $sError, $nLength) = BDGetLength8(\*DIFF);	# Get 8 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			($status, $sError, $nChecksum) = BDCopyData(\*FROM, \*TO, $nLength, $nChecksum); # Copy the data
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}
			}
		elsif ($::BD_INSERT_32 == $nCommand)		 # Insert x bytes (32 bit count)
			{
			($status, $sError, $nLength) = BDGetLength32(\*DIFF);	# Get 32 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			($status, $sError, $nChecksum) = BDCopyData(\*DIFF, \*TO, $nLength, $nChecksum); # Copy the data
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}
			}
		elsif ($::BD_INSERT_16 == $nCommand)		 # Insert x bytes (16 bit count)
			{
			($status, $sError, $nLength) = BDGetLength16(\*DIFF);	# Get 16 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			($status, $sError, $nChecksum) = BDCopyData(\*DIFF, \*TO, $nLength, $nChecksum); # Copy the data
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}
			}
		elsif ($::BD_INSERT_8 == $nCommand)			 # Insert x bytes (8 bit count)
			{
			($status, $sError, $nLength) = BDGetLength8(\*DIFF);	# Get 8 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			($status, $sError, $nChecksum) = BDCopyData(\*DIFF, \*TO, $nLength, $nChecksum); # Copy the data
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}
			}
		elsif ($::BD_DELETE_32 == $nCommand)		 # Delete x bytes
			{
			($status, $sError, $nLength) = BDGetLength32(\*DIFF);	# Get 32 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			unless (seek FROM, $nLength, 1)			 # Seek to point
				{
				my $sError = $!;
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($::FAILURE, InsertString("IDS_MD_ERROR_SEEKING_FROM", $sFromFile, tell(FROM), $nLength, $sError));
				}
			}
		elsif($::BD_DELETE_16 == $nCommand)			 # Delete x bytes
			{
			($status, $sError, $nLength) = BDGetLength16(\*DIFF);	# Get 16 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			unless (seek FROM, $nLength, 1)			 # Seek to point
				{
				my $sError = $!;
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($::FAILURE, InsertString("IDS_MD_ERROR_SEEKING_FROM", $sFromFile, tell(FROM), $nLength, $sError));
				}
			}
		elsif ($::BD_DELETE_8 == $nCommand)								# Delete x bytes
			{
			($status, $sError, $nLength) = BDGetLength8(\*DIFF);	# Get 8 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			unless (seek FROM, $nLength, 1)			 # Seek to point
				{
				my $sError = $!;
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($::FAILURE, InsertString("IDS_MD_ERROR_SEEKING_FROM", $sFromFile, tell(FROM), $nLength, $sError));
				}
			}
		elsif ($::BD_CHECKSUM_TO == $nCommand)		 # 32 bit checksum of all bytes in 'to' file
			{
			($status, $sError, $nLength) = BDGetLength32(\*DIFF);	# Get 32 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			if ($nLength != $nChecksum)				 # Validate against our checksum
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($::FAILURE, InsertString("IDS_MD_CHECKSUM_ERROR", $nLength, $nChecksum));
				}
			}
		elsif ($::BD_LENGTH_TO)							 # 32 bit length of 'to' file
			{
			($status, $sError, $nLength) = BDGetLength32(\*DIFF);	# Get 32 bit length
			if ($::SUCCESS != $status)
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($status, $sError);
				}

			my $nTell = tell TO;							 # get the current file position
			if ($nLength != $nTell)						 # Check the length we've written
				{
				close(DIFF);
				close(TO);
				close(FROM);
				if ($sScratchFile)						 # clean up the scratch file if it was created
					{
					unlink ($sScratchFile);
					}
				return ($::FAILURE, InsertString("IDS_MD_DIFF_LENGTH_ERROR", $nLength, $nTell));
				}
			}
		}

	close(FROM);
	close(TO);
	close(DIFF);
	#
	# If we merged with the old file, rename the scratch file over the old file
	#
	if ($sScratchFile)									# we used a scratch file
		{
		unlink($sOldFileName);							# attempt to manually remove the destination file as some systems do not automatically remove it with the rename command
		if (!rename ($sScratchFile, $sOldFileName))
			{
			my $sError = $!;
			unlink ($sScratchFile);
			return ($::FAILURE, InsertString("IDS_MD_CORRUPT_WEB", $sScratchFile, $sOldFileName, $sError));
			}
		}

	return ($::SUCCESS);
	}

################################################################
#
# BDGetLength32	- get a 4 byte length in network order
#
# Input:    0 - reference to a file handle
#
# Returns:	0 - status
#           1 - error message
#           2 - length
#
################################################################

sub BDGetLength32
	{
#? ACTINIC::ASSERT($#_ == 0, "Incorrect parameter count BDGetLength32(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($pFile) = @_;

	my $nLength = 0;
	my $Buffer;
	unless (4 == read $pFile, $Buffer, 4)			 # Read the double word
		{
		return($::FAILURE, InsertString("IDS_MD_ERROR_READING_FILE", $!)); # Read failed
		}

	($nLength) = unpack "N", $Buffer;					 # unpack the binary data

	return($::SUCCESS, undef, $nLength);
	}

################################################################
#
# BDGetLength16	- get a 2 byte length in network order
#
# Input:    0 - reference to a file handle
#
# Returns:	0 - status
#           1 - error message
#           2 - length
#
################################################################

sub BDGetLength16
	{
#? ACTINIC::ASSERT($#_ == 0, "Incorrect parameter count BDGetLength16(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($pFile) = @_;

	my $nLength = 0;
	my $Buffer;
	unless (2 == read $pFile, $Buffer, 2)			 # Read the word
		{
		return($::FAILURE, InsertString("IDS_MD_ERROR_READING_FILE", $!)); # Read failed
		}

	($nLength) = unpack "n", $Buffer;					 # unpack the binary data

	return($::SUCCESS, undef, $nLength);
	}

################################################################
#
# BDGetLength8	- get a byte length in network order
#
# Input:    0 - reference to a file handle
#
# Returns:	0 - status
#           1 - error message
#           2 - length
#
################################################################

sub BDGetLength8
	{
#? ACTINIC::ASSERT($#_ == 0, "Incorrect parameter count BDGetLength8(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($pFile) = @_;

	my $nLength = 0;
	my $Buffer;
	unless (1 == read $pFile, $Buffer, 1)			 # Read the byte
		{
		return($::FAILURE, InsertString("IDS_MD_ERROR_READING_FILE", $!)); # Read failed
		}

	($nLength) = unpack "C", $Buffer;					 # unpack the binary data

	return($::SUCCESS, undef, $nLength);
	}

################################################################
#
# BDCopyData	- copy from the 'from' file to the 'to' file
#
# Input	:	0 - a reference to the 'from' file handle
#				1 - a reference to the 'to' file handle
#				2 - amount to copy
#           3 - current checksum
#
# Returns:	0 - status
#           1 - error message
#           2 - updated check sum
#
################################################################

sub BDCopyData
	{
#? ACTINIC::ASSERT($#_ == 3, "Incorrect parameter count BDCopyData(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($pFrom, $pTo, $nLength, $nChecksum) = @_;
	my	$nChar;
	#
	# To speed things up a bit, lets read everything at once, do the check sum, then write everything in one
	# fell swoop.
	#
	my $Buffer;
	unless ($nLength == read $pFrom, $Buffer, $nLength)
		{
		return ($::FAILURE, InsertString("IDS_MD_ERROR_COPY_FROM", $!), $nChecksum);
		}

	my @Data = unpack "C$nLength", $Buffer;
#? ACTINIC::ASSERT($#Data == $nLength - 1, "BDCopyData unpack problem (" . $#Data . ", $nLength).", __LINE__, __FILE__);

	$nChecksum += unpack "%32C*", $Buffer;			 # calculate the check sum

	unless (print $pTo $Buffer)
		{
		return ($::FAILURE, InsertString("IDS_MD_ERROR_COPY_TO", $!), $nChecksum);
		}

	return($::SUCCESS, undef, $nChecksum);
	}

################################################################
#
# OpenWithRetry - open the specified file, but retry on error
#
# Input	:	0 - a reference to the file handle
#           1 - file string (with direction indicator)
#
# Returns:	0 - status
#           1 - error message
#
################################################################

sub OpenWithRetry
	{
#? ACTINIC::ASSERT($#_ == 1, "Incorrect parameter count OpenWithRetry(" . join(', ', @_) . ").", __LINE__, __FILE__);
	my ($rFile, $sFilename) = @_;
	my $nAttempt = $::MAX_RETRY_COUNT;
	my $bOpenFailed = $::TRUE;

	while ($nAttempt-- &&								# try to open the file until we run out of attempts or are successful
			 $bOpenFailed)
		{
		if (open ($rFile, $sFilename))				# attempt the open
			{
			$bOpenFailed = $::FALSE;					# note the success
			}

		if ($nAttempt &&									# if the open failed
			 $bOpenFailed)
			{
			sleep($::RETRY_SLEEP_DURATION);			# pause before retrying
			}
		}
	#
	# $! should still be intact
	#
	return ($bOpenFailed ? $::FAILURE : $::SUCCESS, $!);
	}

#######################################################
#
# PrepareResponse - prepare the output if necessary
#   This does nothing unless we are using non-parsed
#   headers with dynamic feedback.
#
#######################################################

sub PrepareResponse
	{
	if ($::s_bUseNonParsedHeaders)
		{
		ACTINIC::PrintNonParsedHeader("text/plain");
		binmode STDOUT;
		}
	}

#######################################################
#
# SendResponse - send the message to the client.  If
#  we are not using non parsed headers, we cached the
#  response.
#
# Input:  0 - message to send
#
#######################################################

sub SendResponse
	{
	if ($::s_bUseNonParsedHeaders)
		{
		print STDOUT $_[0];
		}
	else
		{
		$::s_sResponseCache .= $_[0];
		}
	}

#######################################################
#
# CompleteResponse - wrap up the response regardless
#  of the method
#
#######################################################

sub CompleteResponse
	{
	if (!$::s_bUseNonParsedHeaders)
		{
		binmode STDOUT;
		ACTINIC::PrintHeader("text/plain", (length $::s_sResponseCache), undef, $::FALSE);
		print STDOUT $::s_sResponseCache;
		}
	}

#######################################################
#
# InsertString  - Get the specified message and format it.
#
# Params:	0 - string ID
#				1+ - optional list of arguments supplied
#					to complete string formatting
#
# Returns:	0 - prompt string
#
# Friday, September 14, 2001 - zmagyar
#
#######################################################

sub InsertString
	{
	no strict 'refs';										# this class routine symbolic references
	my ($sResult, $sID, @args);
	if ($#_ < 0)											# incorrect number of arguments
		{
		return ("Invalid argument count in sub InsertString!");
		}

	($sID, @args) = @_;

	#
	# Try to read the phrase file if never tried
	#
	if (!defined $::g_pPrompts)
		{
		my @Response = ACTINIC::ReadConfigurationFile($sPath . "mergephrase.fil",'$g_pPrompts');	# load the phrases
		$::s_bLoadFailed = ($Response[0] != $::SUCCESS);
		}
	#
	# If the load failed or the phrase doesn't exist in the loaded hash
	# then fall back to the default prompts
	#
	if ($::s_bLoadFailed ||								# if load failed
		! defined $$::g_pPrompts{$sID})				# or the requested phrase doesn't exist
		{														# fall back to default phrases
		$::g_pPrompts =
			{
			'IDS_MD_NO_COMPLETE_FILE' => "No complete file exists to apply the differential file to.  Please refresh the catalog site.\n",
			'IDS_MD_CORUPTINDEX' => "The web site index has been corrupted.  Catalog is unable to update the index.  Copy %s to %s failed.  %s.  Please refresh the site.",
			'IDS_MD_CANT_OPEN_FROM' => "Cannot open differential 'old' file '%s'.  %s",
			'IDS_MD_CANT_OPEN_TO' => "Cannot open output scratch file '%s'.  %s",
			'IDS_MD_CANT_OPEN_DIFF' => "Cannot open differential 'diff' file '%s'.  %s",
			'IDS_MD_CANT_CREATE_UNIQUE_SCRATCH' => "Unable to create a unique scratch file.",
			'IDS_MD_ERROR_SEEKING_FROM' => "Error seeking in 'from' file '%s' (%d, %d).  %s",
			'IDS_MD_CHECKSUM_ERROR' => "Diff file checksum error (Calculated %d, Expected %d).\r\nPlease refresh your website. If the problem persists and you are unable to upload your store contact support.",
			'IDS_MD_DIFF_LENGTH_ERROR' => "Diff file length error (Expected %d, Actual %d).",
			'IDS_MD_CORRUPT_WEB' => "The web site index has been corrupted.  Copy %s to %s.  %s.  Please refresh the site.",
			'IDS_MD_ERROR_READING_FILE' => "Error reading file. %s",
			'IDS_MD_ERROR_COPY_FROM' => "Error copying from 'from' file.  %s",
			'IDS_MD_ERROR_COPY_TO' => "Error copying to 'to' file.  %s",
			'IDS_MD_AUTHORISATION_FAILED' => "Bad Catalog username or password. Check your Housekeeping | Security settings and try again. If that fails, try refreshing the site.",
			};
		}
	#
	# If the phrase is still not defined then return the error
	#
	if (!defined $$::g_pPrompts{$sID})
		{
		return ("The requested phrase is not defined!");
		}

	$sResult = $$::g_pPrompts{$sID};					# get the phrase
	#
	# process any substitution
	#
	if ($#args > -1)										# there are values to substitute
		{
		$sResult = sprintf($sResult, @args);		# perform the substitution
		}
	return ($sResult); 									# return the phrase
	}
