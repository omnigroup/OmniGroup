// Copyright 2010-2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/NSError-OBExtensions.h>

extern NSErrorDomain const ODSErrorDomain;

typedef NS_ERROR_ENUM(ODSErrorDomain, ODSError) {
    // skip zero since it means 'no error' to AppleScript (actually the first 10-ish are defined in NSScriptCommand)
    _ODSNoError = 0,

    ODSUnrecognizedFileType,
    ODSFilenameAlreadyInUse,
    
};

#define ODSErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, ODSErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define ODSError(error, code, description, reason) ODSErrorWithInfo((error), (code), (description), (reason), nil)
