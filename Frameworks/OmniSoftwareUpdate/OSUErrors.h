// Copyright 2007-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/NSError-OBExtensions.h>

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

#define OSUErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OSUErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OSUError(error, code, description, suggestion) OSUErrorWithInfo((error), (code), (description), (suggestion), nil)


// User info key indicating the application bundle identifier of interest
// (currently used to help OSUChooseLocationErrorRecovery guess a good install location)
#define OSUBundleIdentifierErrorInfoKey (@"OmniSoftwareUpdate.errorInfo.bundleIdentifier")

