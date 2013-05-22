// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OFSDAVFileManager;

extern NSArray *OFXFetchFileInfosEnsuringDirectoryExists(OFSDAVFileManager *fileManager, NSURL *directoryURL, NSDate **outServerDate, NSError **outError) OB_HIDDEN;

extern NSURL *OFXWriteDataToURLAtomically(OFSDAVFileManager *fileManager, NSData *data, NSURL *destinationURL, NSURL *temporaryDirectoryURL, BOOL overwrite, NSError **outError) OB_HIDDEN;

extern NSURL *OFXMoveURLToMissingURLCreatingContainerIfNeeded(OFSDAVFileManager *fileManager, NSURL *sourceURL, NSURL *destinationURL, NSError **outError) OB_HIDDEN;
