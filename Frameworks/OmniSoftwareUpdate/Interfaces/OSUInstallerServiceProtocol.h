// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSDictionary, NSError, NSData, NSURL;

@protocol OSUInstallerService

- (void)preflightUpdate:(NSDictionary *)arguments reply:(void (^)(BOOL success, NSError *error, NSData *authorizationData))reply;
- (void)installUpdate:(NSDictionary *)arguments reply:(void (^)(BOOL success, NSError *error))reply;
- (void)launchApplicationAtURL:(NSURL *)applicationURL afterTerminationOfProcessWithIdentifier:(pid_t)pid reply:(void (^)(void))reply;

@end

extern NSString * const OSUInstallerInstallationAuthorizationDataKey;
extern NSString * const OSUInstallerUnpackedApplicationPathKey;
extern NSString * const OSUInstallerInstallationDirectoryPathKey;
extern NSString * const OSUInstallerCurrentlyInstalledVersionPathKey;
extern NSString * const OSUInstallerInstallationNameKey;

extern NSString * const OSUInstallerBundleNameKey;
extern NSString * const OSUInstallerBundleIconPathKey;
