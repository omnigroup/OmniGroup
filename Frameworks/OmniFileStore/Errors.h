// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/NSError-OBExtensions.h>

enum {
    // skip zero since it means 'no error' to AppleScript (actually the first 10-ish are defined in NSScriptCommand)

    // General
    OFSNoFileManagerForScheme = 1,
    OFSBaseURLIsNotAbsolute,
    OFSCannotCreateDirectory,
    OFSCannotMove,
    OFSCannotWriteFile,
    OFSNoSuchDirectory,
    OFSCannotDelete,
    
    // DAV
    OFSDAVFileManagerCannotAuthenticate,
};

extern NSString * const OFSErrorDomain;

#define OFSErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OFSErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OFSError(error, code, description, reason) OFSErrorWithInfo((error), (code), (description), (reason), nil)

extern NSString * const OFSDAVHTTPErrorDomain; // codes are the HTTP response number

#define OFSResponseLocationErrorKey (@"Location")

extern NSString * const OFSURLErrorFailingURLErrorKey;          // > 4.0 use NSURLErrorFailingURLErrorKey
extern NSString * const OFSURLErrorFailingURLStringErrorKey;    // > 4.0 use NSURLErrorFailingURLStringErrorKey
