// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/NSError-OBExtensions.h>

enum {
    OSUUnableToUpgrade = 1, // skip zero since it means 'no error' to AppleScript
    OSUUnableToMountDiskImage,
    OSUUnableToFetchSoftwareUpdateInformation,
    OSUUnableToParseSoftwareUpdateData,
    OSUUnableToParseSoftwareUpdateItem,
    OSUDownloadAlreadyInProgress,
    OSUDownloadFailed,
};

#define OSUErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OMNI_BUNDLE_IDENTIFIER, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OSUError(error, code, description, suggestion) OSUErrorWithInfo((error), (code), (description), (suggestion), nil)
