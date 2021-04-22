// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSError-OBExtensions.h>

extern NSErrorDomain const OUIDocumentErrorDomain;

typedef NS_ERROR_ENUM(OUIDocumentErrorDomain, OUIDocumentError) {
    // Zero typically means no error
    OUIDocumentErrorCannotMoveItemFromInbox = 1,
    OUIDocumentErrorImportFailed,
    OUIDocumentErrorPhotoLibraryAccessRestrictedOrDenied,
};

#define OUIDocumentErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OUIDocumentErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OUIDocumentError(error, code, description, reason) OUIDocumentErrorWithInfo((error), (code), (description), (reason), nil)
