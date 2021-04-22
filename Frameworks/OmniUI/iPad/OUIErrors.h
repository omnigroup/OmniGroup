// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSError-OBUtilities.h>

enum {
    OUINoError = 0, // Zero often means no error.
    
    OUIDocumentHasNoURLError,
    OUISendFeedbackError,
};

extern NSString * const OUIErrorDomain;

#define OUIErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OUIErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OUIError(error, code, description, reason) OUIErrorWithInfo((error), (code), (description), (reason), nil)
