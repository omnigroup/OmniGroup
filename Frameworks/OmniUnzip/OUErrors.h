// Copyright 2006-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSError-OBExtensions.h>

enum {
    OmniUnzipUnknownFileType = 1,
    
    // Error codes mapped from zip library
    OmniUnzipUnableToOpenZipFile = 1012,
    OmniUnzipUnableToCloseZipFile,
    OmniUnzipUnableToReadZipFileContents,
    OmniUnzipUnableToCreateZipFile,
    OmniUnzipOpenSentToStreamInInvalidState,
    OmniUnzipReadSentToStreamInInvalidState,
    OmniUnzipCloseSentToStreamInInvalidState,
};

extern NSString * const OmniUnzipErrorDomain;

#define OmniUnzipErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OmniUnzipErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OmniUnzipError(error, code, description, reason) OmniUnzipErrorWithInfo((error), (code), (description), (reason), nil)
