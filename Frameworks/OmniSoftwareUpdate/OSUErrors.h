// Copyright 2007-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSError-OBExtensions.h>

#import "OSUErrorDomain.h"

#define OSUErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OSUErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OSUError(error, code, description, suggestion) OSUErrorWithInfo((error), (code), (description), (suggestion), nil)


// User info key indicating the application bundle identifier of interest
// (currently used to help OSUChooseLocationErrorRecovery guess a good install location)
#define OSUBundleIdentifierErrorInfoKey (@"OmniSoftwareUpdate.errorInfo.bundleIdentifier")

