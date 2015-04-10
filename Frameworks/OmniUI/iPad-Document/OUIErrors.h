// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
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
    _OUIDocumentNoError = 0,
    
    OUICannotMoveItemFromInbox,
    OUIInvalidZipArchive,
    OUIPhotoLibraryAccessRestrictedOrDenied,
};

extern NSString * const OUIDocumentErrorDomain;

#define OUIDocumentErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OUIDocumentErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OUIDocumentError(error, code, description, reason) OUIDocumentErrorWithInfo((error), (code), (description), (reason), nil)
