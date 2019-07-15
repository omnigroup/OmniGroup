// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


// Helpers for the details of how snapshots are formatted on the remote server

#define kOFXRemoteInfoFilename @"Info.plist"

@class ODAVConnection, ODAVFileInfo;

extern NSString *OFXHashFileNameForData(NSData *data) OB_HIDDEN;


/*
 We want to use something that:
 
 -- won't be returned by OFXMLCreateID (which could be anything in the 'NAME' production in <http://www.w3.org/TR/2004/REC-xml-20040204/#sec-common-syn> (letter, digit, [.-_:])
 -- doesn't require URI percent-encoding, which some servers mess up <https://tools.ietf.org/html/rfc3986#section-2.2>
 
 The only character that is in the URI unreserved set and isn't in the a XML identifier character is "~".
 
 */
#define OFXRemoteFileIdentifierToVersionSeparator @"~" // No (...) wrapping this since I use it in one spot where I want string constant concatenation done by the compiler

extern NSString *OFXFileItemIdentifierFromRemoteSnapshotURL(NSURL *remoteSnapshotURL, NSUInteger *outVersion, NSError **outError) OB_HIDDEN;

extern NSArray <ODAVFileInfo *> *OFXFetchDocumentFileInfos(ODAVConnection *connection, NSURL *containerURL, NSString *identifier, NSError **outError) OB_HIDDEN;

extern NSComparisonResult OFXCompareFileInfoByVersion(ODAVFileInfo *fileInfo1, ODAVFileInfo *fileInfo2) OB_HIDDEN;
