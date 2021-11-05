// Copyright 2007-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// This header is used in command line tools that we don't want to depend on OmniBase. Because of this, it is split out from OSUErrors.h, which references OmniBase functions.

@class NSString;

enum {
    // Generic error
    OSUUnableToUpgrade = 1,                               // skip zero since it means 'no error' to AppleScript

    // Problems fetching the list of available updates
    OSUUnableToFetchSoftwareUpdateInformation,
    OSUUnableToParseSoftwareUpdateData,
    OSUUnableToParseSoftwareUpdateItem,

    // Problems retrieving the actual download
    OSUDownloadAlreadyInProgress,
    OSUDownloadFailed,

    // Problems installing the downloaded update
    OSUPreflightNotPerformed,                             // programmer error, preflight wasn't run
    OSUCannotUninstallPrivilegedHelper,                   // there are other active connections to the privileged helper
    OSUUnableToProcessPackage,                            // other failures (tar, etc.)
    OSUBadInstallationDirectory,                          // There's something wrong with the destination location

    // Check operation
    OSUCheckServiceTimedOut,
    OSUCheckServiceFailed,
    OSUServerError,
    OSUExceptionRaised,

    // XPC Service communication
    OSURequiredArgumentMissing,
};

extern NSString * const OSUErrorDomain;

