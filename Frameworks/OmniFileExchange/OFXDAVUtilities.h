// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@class ODAVConnection, ODAVMultipleFileInfoResult;

extern ODAVMultipleFileInfoResult *OFXFetchFileInfosEnsuringDirectoryExists(ODAVConnection *connection, NSURL *directoryURL, NSError **outError) OB_HIDDEN;

extern void OFXWriteDataToURLAtomically(ODAVConnection *connection, NSData *data, NSURL *destinationURL, NSURL *temporaryDirectoryURL, NSURL *accountBaseURL, BOOL overwrite, void (^completionHandler)(NSURL *url, NSError *errorOrNil)) OB_HIDDEN;

extern NSURL *OFXMoveURLToMissingURLCreatingContainerIfNeeded(ODAVConnection *connection, NSURL *sourceURL, NSURL *destinationURL, NSError **outError) OB_HIDDEN;
