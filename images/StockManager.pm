#!/usr/bin/perl
###############################################################
#																							#
#  package StockManager - ACTINIC stock management package										#
#																							#
#  This module contains the StockManager object description.											#		
#  This object is dealing with stock management related operations of Actinic shopping cart scripts			#
#	The main functions implemented here is to manage the online stock files which are 						#
#	- stock.fil - the stock balance file which is a B-tree generated ad desktop but updated on the server		#
#				in case of synchronisation (to save time on full blob generation)						#
# 	- stocktrans.fil - the stock transaction file, which is a perl hash definition file and used to store 		#
#				the stock changes between two synchronisations										#
#																							#
#	Author: Zoltan Magyar																		#
#																							#
#  Copyright (c)2009 Actinic Software Ltd 														#
#																							#
###############################################################

package StockManager;

$::STOCK_FILE_NAME = "stock.fil";
$::RETRY_SLEEP_DURATION = 1;
$::MAX_RETRY_COUNT      = 10;
$::g_nStockIndexVersion = 257;
$::ACCESS_MODE_READ 		= 0;
$::ACCESS_MODE_WRITE 	= 1;
$::ACCESS_MODE_EMPTY 	= 2;
$::TRUE 	= 1;
$::FALSE 	= 0;

$::INDEX_CORRUPT_ERR = "Error seeking in the index '%s'. %s.  The index is corrupt.";
$::STOCK_TRANS_LOCK_ERR 	= 'Actinic ecommerce is unable to lock the stock transaction file.  %s';
$::STOCK_TRANS_RELEASE_ERR = 'An error occurred while releasing the order number counter lock file.  %s';
$::STOCK_TRANS_WRITE_ERR 	= 'Error writing to %s (%s).';
$::STOCK_TRANS_CREATE_ERR 	= 'An error occurred while creating the stock transaction lock file (%s).  The error was %s.';

################################################################
#
# StockManager->new - constructor for StockManager class
#
# Input:	$Proto		- class name or ref to class name
#		$sPath 		- path to the acatalog folder
#
# Author:	Zoltan Magyar
#
################################################################

sub new
	{
	my ($Proto, $sPath) = @_;
	my $sClass = ref($Proto) || $Proto;
	my $Self  = {};										# create self
	bless ($Self, $sClass);								# populate

	$Self->{PATH}	= $sPath;							# store reference to type array
	
	$Self->{LOCKFILE} = $sPath . "stocktrans_lck.fil";
	$Self->{UNLOCKFILE} = $sPath . "stocktrans.fil";
	$Self->{BACKUPFILE} = $sPath . "stocktrans_bak.fil";
	return($Self);
	}
	
################################################################
#
# AllocateStock - Set stock level for  a single product
#
# Input: 	0 - product reference to look up
#			1 - the new stock value
#
# Output:  	0 - status
#			1 - error message if any
#			2 - the stock level
#
# Author: Zoltan Magyar
#
################################################################

sub AllocateStock
	{
	my ($Self, $pProdRefs, $pValues) = @_;
	#
	# We got the balance value. Now see the transaction value
	#
	my ($Status, $sMessage) = $Self->AccessWithLock($::ACCESS_MODE_WRITE, $pProdRefs, $pValues);
	if ($Status == $::FAILURE)							# search engine error
		{
		return ($::FAILURE, $sMessage);							# report it
		}
	return ($::SUCCESS, ''); 
	}
	
################################################################
#
# EmptyTransactions - clean up the stock transaction file
#
# Output:  	0 - status
#			1 - error message if any
#
# Author: Zoltan Magyar
#
################################################################

sub EmptyTransactions
	{
	my ($Self) = @_;
	#
	# We got the balance value. Now see the transaction value
	#
	my ($Status, $sMessage) = $Self->AccessWithLock($::ACCESS_MODE_EMPTY);
	return ($Status, $sMessage);	
	}
	
################################################################
#
# SetStock - Set stock level for  a single product
#
# Input: 	0 - product reference to look up
#			1 - the new stock value
#
# Output:  	0 - status
#			1 - error message if any
#
# Author: Zoltan Magyar
#
################################################################

sub SetStock
	{
	my ($Self, $pProdRefs, $pValues) = @_;
	#
	# Open the stock index file
	#
	my ($status, $sError, $rFile) = $Self->OpenStockIndex();
	if ($status != $::SUCCESS)							# search engine error
		{
		return ($::FAILURE, 0);							# report it
		}
	#
	# Set the product stock
	#
	while (@$pProdRefs)
		{
		my ($sRef, $nValue) = (pop @$pProdRefs, pop @$pValues);
		my ($Status, $sMessage, $sValue) = $Self->SetNewIndexValue($sRef, $nValue, 2, $rFile, $::STOCK_FILE_NAME);
		#
		# Return value may be $::NOTFOUND what is not threated as error here
		#
		if ($Status == $::FAILURE)
			{
			close($rFile);
			return ($Status, $sMessage);
			}
		}
	#
	# Close the index file
	#
	close($rFile);
	return ($::SUCCESS, ''); 
	}
	
################################################################
#
# GetStock - Get stock level for  a single product
#
# Input: 	0 - product reference to look up
#
# Output:  	0 - status
#			1 - error message if any
#			2 - the stock level
#
# Author: Zoltan Magyar
#
################################################################

sub GetStock
	{
	my ($Self, $sProductReference) = @_;
	#
	# Open the stock index file
	#
	my ($Status, $sMessage, $hResult) = $Self->GetStockBalanceForProducts([$sProductReference]);
	if ($Status != $::SUCCESS)
		{
		return ($Status, $sMessage, "");
		}
	#
	# Lets see if we got stock for this product
	#
	if (!defined $$hResult{$sProductReference})
		{
		return ($::NOTFOUND, '', undef); 
		}
	#
	# We got the balance value. Now see the transaction value
	#
	($Status, $sMessage) = $Self->AccessWithLock($::ACCESS_MODE_READ);
	if ($Status == $::FAILURE)							# search engine error
		{
		return ($::FAILURE, $sMessage);							# report it
		}
	my $nTransaction = $$::g_pStockList{$sProductReference};
	
	return ($::SUCCESS, '', $$hResult{$sProductReference} - $nTransaction); 
	}
	
#######################################################
#
# GetStockForSection - get the stock level for each product in the section
#
# Expects:	%::g_InputHash should be defined
#
# Input: 	0 - the section ID to look up
#
# Output:  	0 - status
#			1 - error message if any
#			2 - the stock level
#
# Author: Zoltan Magyar - 10:58 PM 2/15/2002
#
#######################################################

sub GetStockForSection
	{
	my ($Self, $nSID) = @_;
	#
	# Get the section BLOB name
	#
	if ($nSID !~ /^(\d+)$/)								# if the section ID does not contain only digits
		{
		return ($::FAILURE, "Invalid section ID");		# bad input
		}
	my $nID = $1;											# retrieve the ID
	my $sSectionBlobName = sprintf('A000%d.cat', $nID);	
	#
	# Open up the section BLOB
	#
	my ($Status, $sMessage) = $Self->ReadConfigurationFile($Self->{PATH} . $sSectionBlobName);	# read the blob
	if ($Status != $::SUCCESS)
		{
		$Self->TerminalError($sMessage);
		}
	#
	# Iterate on the section
	#
	my ($sKey, $sOut, @aRefs);
	foreach $sKey (keys %{$::g_pSectionList{$sSectionBlobName}})
		{
		#
		# The value must be a hash for product hashes
		#
		if (ref($::g_pSectionList{$sSectionBlobName}{$sKey}) ne 'HASH')
			{
			next;												# can take the next item
			}
		#
		# And it should have a 'REFERENCE' key otherwise it's not a product has so we can take the next
		#
		if (!defined $::g_pSectionList{$sSectionBlobName}{$sKey}{'REFERENCE'})
			{
			next;
			}
		#
		# If we are here then $sKey contains a product reference so look up the stock value
		#
		push @aRefs, $sKey;
		}
	#
	# Now get the tock balance values
	#
	my $hResult;
	($Status, $sMessage, $hResult) = $Self->GetStockBalanceForProducts(\@aRefs);
	if ($Status != $::SUCCESS)
		{
		return ($Status, $sMessage, "");
		}
	#
	# Read the transaction file as we will need that in the loop below
	#
	($Status, $sMessage) = $Self->AccessWithLock($::ACCESS_MODE_READ);
	if ($Status == $::FAILURE)							# search engine error
		{
		return ($::FAILURE, $sMessage);							# report it
		}
	#
	# Now construct the output
	#
	foreach $sKey (keys %{$hResult})
		{
		my $nStock = $$hResult{$sKey};
		#
		# Also involve the transaction file
		#
		my $nTransaction = $$::g_pStockList{$sKey};
		$nStock -= $nTransaction;
		#
		# Construct a JSON object to allow simple processing in javascript - see RFC 4627
		#
		$sOut .= '"' . $sKey . '":' . $nStock . ",";
		}
	#
	# Complete JSON formatting
	#
	$sOut =~ s/,$//;
	$sOut = "{" . $sOut . "}";
	
	return ($::SUCCESS, '', $sOut); 
	}
	
#######################################################
#
# GetStockBalanceForProducts - get the stock balance file content for the given products
#
# Input: 	0 - array of product references to be looked up
#
# Output:  	0 - status
#			1 - error message if any
#			2 - hash of the product reference - stock value for the given products
#
# Author: Zoltan Magyar - 10:58 PM 4/28/2009
#
#######################################################

sub GetStockBalanceForProducts
	{
	my ($Self, $pProdRefs) = @_;
	#
	# Open the stock index file as we will need it in the loop below
	#
	my ($status, $sError, $rFile) = $Self->OpenStockIndex();
	if ($status != $::SUCCESS)							# search engine error
		{
		return ($::FAILURE, 0);							# report it
		}
	#
	# Iterate on the section
	#
	my ($sKey, $sOut, %hResult);
	foreach $sKey (@$pProdRefs)
		{
		#
		# If we are here then $sKey contains a product reference so look up the stock value
		#
		my $nStock;
		my ($Status, $sMessage, $sValue) = $Self->SetNewIndexValue($sKey, 0, 2, $rFile, $::STOCK_FILE_NAME);
		#
		# The pack function doesn't have formatter for signed longs in network byte order
		# therefore we need to deal with byte order here and construct our long value manually
		#
		my $nValue = $Self->BytesToLong($sValue);
		if ($Status != $::SUCCESS)
			{
			#
			# In case of any error just try to process the rest
			#
			next;
			}
		#
		# Add to the result
		#
		$hResult{$sKey} = $nValue;
		}
	#
	# Close the stock BLOB and return the results
	#
	close($rFile);	
	return ($::SUCCESS, '', \%hResult); 
	}

###############################################################
#
# AllocateStockCallback - allocates stock by adding the changes to the transaction file
#
# Input:		0 - array of product references
#			1 - array of matching stock value changes
#
# Returns:  	0 - status
#          		1 - error message
#           	2 - value
#
###############################################################

sub AllocateStockCallback()
	{
	my ($Self, $pProdRefs, $pValues) = @_;
	#
	# Open the transaction file
	#
	my @Response = $Self->ReadTransactionFile();
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	#
	# Now update the stock levels
	#
	while (@$pProdRefs)
		{
		my ($sRef, $nValue) = (pop @$pProdRefs, pop @$pValues);
		my $nTransaction = $$::g_pStockList{$sRef};
		#
		# Update the transaction file
		#
		$$::g_pStockList{$sRef} += $nValue;
		}
	
	return ($::SUCCESS, "", "");
	}
	
###############################################################
#
# SerializeTransactionFile - serializes the stock transaction file
#
# Returns:  0 - status
#           1 - error message
#           2 - value
#
###############################################################

sub SerializeTransactionFile()
	{
	my ($Self) = @_;
	
	my ($sVarDump, $key, $value);
	
	while (($key, $value) = each(%{$::g_pStockList}))
		{
		$sVarDump .= sprintf("\t'%s' => '%s',\r\n", $key, $value);
		}
	my $sOut = sprintf("\$::g_pStockList = \r\n\t{\r\n%s\t};\r\nreturn(\$::SUCCESS);", $sVarDump);
	my $uTotal;
		{
		use integer;
		$uTotal = unpack('%32C*', $sOut);
		}
	return sprintf("%d;\r\n%s", $uTotal, $sOut);
	}

#######################################################
#
# ReadTransactionFile - read the stock transaction blob file.
#
# Returns:	0 - status
#			1 - error message
#
# Affects:	$::g_pStockList - points to the global  transaction hash
#
#######################################################

sub ReadTransactionFile
	{
	my ($Self) = @_;
	
	my @Response = $Self->ReadConfigurationFile($Self->{LOCKFILE});	
	if ($Response[0] != $::SUCCESS)
		{
		return (@Response);
		}
	return ($::SUCCESS, "", 0, 0);					# we are done
	}
	
#######################################################
#
# AccessWithLock - access the transaction file with lock. The purpose of the access may be either 
#	reading the content or updating it with fresh data
#
# Input:		0 - the access mode, it can be either $::ACCESS_MODE_READ  or $::ACCESS_MODE_WRITE
#
# Returns:	0 - status
#			1 - error message
#
# Affects:	$::g_pStockList - points to the global  transaction hash
#
#######################################################

sub AccessWithLock
	{
	my ($Self, $nMode, @pParams) = @_;
	
	my $nNumberBreakRetries = 1;						# number of times to try to break the lock file if it is dead
	my $sUnLockFile = $Self->{UNLOCKFILE}; 		# name of the lock file in its unlocked state
	my $sBackupFile = $Self->{BACKUPFILE}; 		# name of the lock file in its unlocked state
	my $sLockFile = $Self->{LOCKFILE}; 				# name of the lock file in its locked state
	#
	# if none of the files exist, create the order file and then sleep for a bit before trying to obtain a lock
	# to it.
	#
START_AGAIN:
	if (!-e $sUnLockFile &&								# none of the files exist
		 !-e $sLockFile &&
		 !-e $sBackupFile)
		{
		#
		# create the unlocked file
		#
		unless (open (LOCK, ">$sUnLockFile"))
			{
			return ($::FAILURE, sprintf($::STOCK_TRANS_CREATE_ERR, $sUnLockFile, $!), undef, undef);
			}
		#
		# 	Write a space to the file for now
		#
		unless (print LOCK $Self->SerializeTransactionFile())
			{
			my $sError = $!;
			close (LOCK);
			return ($::FAILURE, sprintf($::STOCK_TRANS_WRITE_ERR, $sUnLockFile, $sError), undef, undef);
			}
		close (LOCK);

		sleep 2;												# now pause to allow concurrent processes to lock the file
		}
	#
	# if only the backup file exists, copy it to the unlock file
	#
	if (!-e $sUnLockFile &&								# only the backup file exists
		 !-e $sLockFile &&
		  -e $sBackupFile)
		{
		#
		# create the unlocked file from the backup file
		#
		unless (open (BACK, "<$sBackupFile"))
			{
			my $sError = $!;
			return ($::FAILURE, sprintf($::STOCK_TRANS_WRITE_ERR, $sBackupFile, $sError), undef, undef);
			}
	
		my $sScript;
		{
		local $/;
		$sScript = <BACK>;								# read the entire file
		}
		close (BACK);
		
		unless (open (LOCK, ">$sUnLockFile"))
			{
			return ($::FAILURE, sprintf($::STOCK_TRANS_CREATE_ERR, $sUnLockFile, $!), undef, undef);
			}
		
		unless (print LOCK $sScript)
			{
			my $sError = $!;
			close (LOCK);
			return ($::FAILURE, sprintf($::STOCK_TRANS_WRITE_ERR, $sUnLockFile, $sError), undef, undef);
			}
		close (LOCK);

		sleep 2;												# now pause to allow concurrent processes to lock the file
		}

	my $nDate;												# the date on the lock file
	my $bFileIsLocked = $::FALSE;						# note if we get the file
	my $sRenameError;
RETRY:
	$bFileIsLocked = $::FALSE;
	if ($nNumberBreakRetries < 0)						# we seem to be in an unrecoverable situation
		{
		return ($::FAILURE, sprintf($::STOCK_TRANS_LOCK_ERR, $sRenameError), undef, undef);
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
				return ($::FAILURE, sprintf($::STOCK_TRANS_LOCK_ERR, $sRenameError), undef, undef);
				}

			if (!defined $tmp[9])						# file was removed just before we got the current date -
				{												# assume it is free and try again
				$nNumberBreakRetries--;					# decrement the counter
				sleep 2;
				goto RETRY;
				}

			if ($nDate == $tmp[9])						# the lock file date has not changed
				{
				#
				# Check the file size. If it seems to be empty (corrupt) then
				# remove the file and go back to the beginning to give a chance for the backup file
				#
				if ($tmp[7] == 0)							# empty?
					{
					if (!unlink($sLockFile))			# try to remove
						{										# report if couldn't remove
						return ($::FAILURE, sprintf($::STOCK_TRANS_LOCK_ERR, $!), undef, undef);
						}
					sleep 2;
					goto START_AGAIN;						# try again from the beginning
					}
				if (!rename($sLockFile, $sUnLockFile))	# try to unlock the file
					{
					#
					# failure
					#
					return ($::FAILURE, sprintf($::STOCK_TRANS_LOCK_ERR, $!), undef, undef);
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
	# Depending on the mode either just read the file or write out the new content
	#
	if (($nMode == $::ACCESS_MODE_WRITE) ||
		 ($nMode == $::ACCESS_MODE_EMPTY))
		{
		my @Response;
		#
		# In case of Write mode read the current file
		#
		if ($nMode == $::ACCESS_MODE_WRITE)
			{
			@Response = $Self->AllocateStockCallback($pParams[0], $pParams[1]);
			if ($Response[0] != $::SUCCESS)
				{
				return (@Response);
				}
			}
		#
		# Otherwise it's empty mode so just define an empty hash
		#
		else
			{
			$::g_pStockList = {};
			}
		#
		# Now serialize the content and write it to the transaction file and its backup
		#
		my $sContent = $Self->SerializeTransactionFile();
		unless (open (LOCK, ">$sLockFile"))
			{
			return ($::FAILURE, sprintf($::STOCK_TRANS_CREATE_ERR, $sLockFile, $!), undef, undef);
			}
		unless (print LOCK $sContent)
			{
			my $sError = $!;
			close (LOCK);
			return ($::FAILURE, sprintf($::STOCK_TRANS_WRITE_ERR, $sLockFile, $sError), undef, undef);
			}
		close (LOCK);
		#
		# copy to the backup file
		#
		unless (open (LOCK, ">$sBackupFile"))
			{
			return ($::FAILURE, sprintf($::STOCK_TRANS_CREATE_ERR, $sBackupFile, $!), undef, undef);
			}
		
		unless (print LOCK $sContent)
			{
			my $sError = $!;
			close (LOCK);
			return ($::FAILURE, sprintf($::STOCK_TRANS_WRITE_ERR, $sBackupFile, $sError), undef, undef);
			}
		close (LOCK);
		}
	else 														# it must be read mode then
		{
		#
		# Read mode
		#
		my @Response = $Self->ReadTransactionFile();
		if ($Response[0] != $::SUCCESS)
			{
			return (@Response);
			}
		}
	#
	# now we have a unique ID for this order - unlock the file
	#
	if (!rename ($sLockFile, $sUnLockFile))
		{
		return ($::FAILURE, sprintf($::STOCK_TRANS_RELEASE_ERR, $!), undef, undef);
		}
		
	return ($::SUCCESS, "", 0, 0);					# we are done
	}

################################################################
#
# OpenStockIndex - Open up the stock blob
#
# Output:  	0 - status - always success as errors go to the terminal here
#			1 - message
#			2 - the opened file
#
# Author: Zoltan Magyar
#
################################################################

sub OpenStockIndex
	{
	my ($Self) = @_;	
	
	my $rFile = \*STOCKINDEX;
	my $sFilename = $Self->{PATH} . $::STOCK_FILE_NAME;
	my ($status, $sError) = $Self->InitIndex($sFilename, $rFile, $::g_nStockIndexVersion);
	if ($status != $::SUCCESS)
		{
		$Self->TerminalError($sError);
		}

	return ($::SUCCESS, '', $rFile);
	}
	
################################################################
#
# InitIndex - initialize the specified index file tables
#
# Input:	   0 - the path to the data file
#           1 - a reference to the desired file handle
#           2 - expected file version
#
# Returns:	0 - status
#           1 - error message if any
#
################################################################

sub InitIndex
	{
	my ($Self, $sPath, $rFileHandle, $nExpectedVersion) = @_;
	#
	# Open the index.  Retry a couple of times on failure just incase an update is in progress.
	#
	my ($status, $sError);
	my $nRetryCount = $::MAX_RETRY_COUNT;
	$status = $::SUCCESS;
	while ($nRetryCount--)
		{
		unless (open ($rFileHandle, "+<$sPath"))
			{
			$sError = $!;
			sleep $::RETRY_SLEEP_DURATION;	# pause a moment
			$status = $::FAILURE;
			$sError = sprintf("Error opening the index '%s'.  %s.  The web site is probably being updated.", $sPath, $sError);
			next;
			}
		binmode $rFileHandle;
	   #
	   # Check the file version number
	   #
		my $sBuffer;
		unless (read($rFileHandle, $sBuffer, 4) == 4) # read the blob version number (a short)
			{
			$sError = $!;
			close ($rFileHandle);
			return ($::FAILURE, sprintf("Error reading the index '%s'.  %s.  The index is corrupt.", $sPath, $sError));
			}

		my ($nVersion) = unpack("n", $sBuffer);	# convert to a number
		if ($nVersion != $nExpectedVersion)
			{
			close($rFileHandle);
			sleep $::RETRY_SLEEP_DURATION;	# pause a moment
			$status = $::FAILURE;
			$sError = sprintf("Unsupported index version for '%s'.  Expected %d.  Found %d.", $sPath, $nExpectedVersion, $nVersion);
			next;
			}

		last;
		}

	return($status, $sError);
	}
	
###############################################################
#
# SetNewIndexValue - search an index for the key.  When the key found then update the associated value with
# 		the new value passed in to the function
#
# Input:	   0 - search key (or remaining fragment on
#               recursive call)
#           1 - point to start in the file
#           2 - file handle
#           3 - file path (for identification in errors)
#
# Returns:  0 - status
#           1 - error message
#           2 - value
###############################################################
# NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE
###############################################################
# This function is also called from Perlscript.pl therefore the ACTINIC library may not be available. So please 
# avoid using any ACTINIC functions in this function
###############################################################

sub SetNewIndexValue
	{
	my ($Self, $sKey, $sNewValue, $nLocation, $rFile, $sFileName) = @_;

	my ($nDependencies, $nCount, $nRefs, $sRefs, $sBuff, $sFragment, $sValue);
	my ($nIndex, $sSeek, $nHere, $nLength, $sNext, $nRead);
	#
   # At the start of the file, we have an (empty) value list
   # followed by a list of dependency records
	#
	unless (seek($rFile, $nLocation, 0))			# Seek to node
		{
		return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
		}
	#
   # Read the value (if any).
	#
	unless (read($rFile, $sBuff, 2) == 2)			# Read the count
		{
		return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
		}

	($nCount) = unpack("n", $sBuff);					# Turn into an integer

	for ($nIndex = 0; $nIndex < $nCount; $nIndex++)
		{
		unless (read($rFile, $sBuff, 2) == 2)		# Get value length
			{
			return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
			}

		($nLength) = unpack("n", $sBuff);			# unpack the value length
		#
		# Next is te value, so save this position
		#
		my $nValueHere = tell($rFile);					# Save where we are
		
		unless (read ($rFile, $sValue, $nLength) == $nLength) # read the value
			{
			return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
			}

		unless (read($rFile, $sBuff, 1) == 1)		# read the reference count
			{
			return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
			}
		($nRefs) = unpack("C", $sBuff);				# Unpack it

		$sRefs = "";										# Kill left-over references
		if ($nRefs > 0)
			{
			unless (read($rFile, $sRefs, $nRefs) == $nRefs)	# Read and ignore the actual refs
				{
				return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
				}
			}

		if ($sKey eq "")					# If this is an exact match
			{
			#
			# We found out match so write in the new value
			#
			unless (seek($rFile, $nValueHere, 0))			# Back to where we were
				{
				return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
				}
				
			my $nValue = $Self->BytesToLong($sValue);	
			#
			# The new value in the blob should be the sum of the existing value and the passed in new value
			# but it needs to be determined and written back to the index if the value is greater than 0
			#
			if ($sNewValue != 0)
				{
				my $nNewValue = $nValue + $sNewValue;
				my $pBuffer = $Self->LongToBytes($nNewValue);
				#
				# Now write the data
				#
				unless (print $rFile $pBuffer)					# write the number
					{
					return ($::FAILURE, "Error writing a word to the file: $!\n", 0);
					}
				}
			return ($::SUCCESS, undef, $sValue);
			}
		}
	#
   # Now search the dependencies
   #
	unless (read($rFile, $sBuff, 2) == 2)			# Read count
		{
		return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
		}
	$nDependencies = unpack("n", $sBuff);			# Count of dependencies (network short)

	for ($nIndex = 0; $nIndex < $nDependencies; $nIndex++)
		{
		unless (read($rFile, $sBuff, 1) == 1)		# Read fragment length
			{
			return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
			}
		$nLength = unpack("C", $sBuff);				# Unpack it

		unless (read($rFile, $sFragment, $nLength) == $nLength) # Read the string fragment
			{
			return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
			}
		unless (read($rFile, $sSeek, 4) == 4)		# Read the link (convert later, if we need it)
			{
			return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
			}
		#
		# Allow special regex characters in $sFragment
		#
		my $sQuotedFragment = quotemeta($sFragment);
		#
		# If the fragment partially matches our word then we
		# continue down the tree. It only needs to match as much
		# of the word as we have - it's perfectly possible for
		# the fragment to be longer than the word
		#
		if ($sKey =~ m/^$sQuotedFragment/) # Does it match?
			{
			$sNext = $';									# Get part after match
			$nHere = tell($rFile);						# Save where we are

			my ($status, $sError, $sValue) = $Self->SetNewIndexValue($sNext, $sNewValue, unpack("N", $sSeek), $rFile, $sFileName); # Look down tree
			if ($status == $::FAILURE ||				# if the lookup errored or
				 $status == $::SUCCESS)					# if it was completed,
				{
				return ($status, $sError, $sValue);	# return the state
				}
			#
			# If we are here, $::NOTFOUND was returned, try the next one
			#
			unless (seek($rFile, $nHere, 0))			# Back to where we were
				{
				return ($::FAILURE, sprintf($::INDEX_CORRUPT_ERR, $sFileName, $!));
				}
			}

		if ($sFragment gt $sKey)						# If we've passed the point in the list
			{
			last;												# Don't look further
			}
		}

	return ($::NOTFOUND, 'Item not found in index');
	}

################################################################
#
# BytesToLong - convert 4 bytes to a signed integer
#
# Input:	   	0 - data buffer to be converted
#
# Returns:	0 - the converted signed long value
#
################################################################

sub BytesToLong
	{
	my ($Self, $sValue) = @_;
	#
	# The new value in the blob should be the sum of the existing value and the passed in new value
	#
	my @bytes = unpack("C4", $sValue);
	my $nValue = $bytes[0] + $bytes[1] * 0x100 + $bytes[2] * 0x10000 + ($bytes[3] & 0x7f) * 0x1000000;
	if (($bytes[3] & 0x80) != 0)
		{
		$nValue = $nValue - 0x80000000;
		}
	return $nValue;
	}
	
################################################################
#
# LongToBytes - convert a signed long value to a buffer of 4 bytes 
#
# Input:	   	0 - signed long value to be converted
#
# Returns:	0 - the converted data buffer
#
################################################################

sub LongToBytes
	{
	my ($Self, $nValue) = @_;
	my $bNegative = ($nValue < 0);
	if ($bNegative)
		{
		$nValue += 0x80000000;
		}
	#
	# Convert it to signed long similar way to the reading (no signed long in network byte order for pack so implement our own packing)
	#
	my @bytes;
	$bytes[0] = $nValue % 0x100;
	$bytes[1] = int ($nValue / 0x100) % 0x100;
	$bytes[2] = int ($nValue / 0x10000) % 0x100;
	$bytes[3] = int ($nValue / 0x1000000) % 0x100;
	if ($bNegative)
		{
		$bytes[3] |= 0x80;
		}
	return (pack("C4", @bytes));
	}
	
#######################################################
#
# TerminalError - generate the error html
#
#	Params: 	0 - the error
#
#######################################################

sub TerminalError
	{
	my ($Self, $sError) = @_;										# get the error message

	my $sHTML  = "<HTML><TITLE>Actinic</TITLE><BODY>";
	$sHTML .= "<H1>" . "A General Script Error Occurred" . "</H1>";
	$sHTML .= "<HR>" . "Error" . ": $sError<HR>";
	$sHTML .= "Press the Browser back button and try again or contact the site owner.";
	$sHTML .= "</BODY></HTML>";
	#
	# now print the header
	#
	my $nLength = length $sHTML;
	if($ENV{'PerlXS'} eq 'PerlIS')					# Windows IIS6 may be using PerIS.dll insteasd of perl.exe
		{
		print "HTTP/1.0 200 OK\n";						# so we must insert the protocol and return status
		}
	print "Content-type: text/html\r\n";
	print "Content-length: $nLength\r\n";
	print "\r\n";
	print $sHTML;

	exit;
	}
	
#######################################################
#
# ReadConfigurationFile - read the specified blob
#	file
#
# Params:	0 - blob filename
#
# Returns:	0 - status
#				1 - error message
#
# Affects:	the appropriate blob
#
#######################################################

sub ReadConfigurationFile
	{
	my ($Self, $sFilename) = @_;		

	my @Response = $Self->ReadAndVerifyFile($sFilename);
	if ($Response[0] != $::SUCCESS)
		{
		return(@Response);
		}
	#
	# execute the script (parse the blob)
	#
	if (eval($Response[2]) != $::SUCCESS)
		{
		return ($::FAILURE, "Error loading configuration file $sFilename. $@", 0, 0);
		}

	return ($::SUCCESS, "", 0, 0);					# we are done
	}
	
#######################################################
#
# ReadAndVerifyFile - read the specified script and
#	verify its signature
#
# Params:	0 - filename
#
# Returns:	0 - status
#				1 - error message
#				2 - script
#
#######################################################

sub ReadAndVerifyFile
	{
	my ($Self, $sFilename) = @_;									# set the blob filename

	unless (open (SCRIPTFILE, "<$sFilename"))		# open the file
		{
		return ($::FAILURE, "Error opening configuration file $sFilename. $!", 0, 0);
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
		return ($::FAILURE, "$sFilename is corrupt.  The signature is invalid.", 0, 0);
		}

	$sScript =~ s/\r//g;									# remove the dos <CR>

	return ($::SUCCESS, "", $sScript, 0);
	}
	
1;
