// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSError, NSArray, NSURL, NSData;

// The value for OSUInstallerPrivilegedHelperVersion (set in the project as a custom build setting so that the app and tool see the same value, and it can be used in other build settings and Info.plists) *must* be bumped every time something in this protocol changes.
// The version number is how we determine at runtime whether we have a compatible tool installed, or must upgrade/downgrade it before doing an update.
//
// Whenever any significant implementation detail changes, you should also bump the version number so that we update the privileged helper tool before using it.

@protocol OSUInstallerPrivilegedHelper

#pragma mark Version 1 API (Required)

// This is required API. (This is how we determine the version of the tool installed so that we can up/downgrade as necessary.)
- (void)getVersionWithReply:(void (^)(NSUInteger version))reply;

#pragma mark Version 3 API

// NOTE: As of version 6, we install per-version helper tools rather than uninstalling the old one. Older versions will attempt to uninstall a mismatching version and install their own so they know how to talk to it.
// This will remove the launchd job associated with this privileged helper, and remove the tool from the filesystem if, and only if, the caller holds the only active connection.
// The privileged helper will exit after sending the reply.
//- (void)uninstallWithAuthorizationData:(NSData *)authorizationData reply:(void (^)(BOOL success, NSError *error))reply;

// Run the embedded installer script do to a privilege escallated install
- (void)runInstallerScriptWithArguments:(NSArray *)arguments localizationBundleURL:(NSURL *)bundleURL authorizationData:(NSData *)authorizationData reply:(void (^)(BOOL success, NSError *error))reply;

// Used to remove the previously installed item as part of the update process.
// Uses the same rights as -runInstallerScriptWithAuthorizationData:...
- (void)removeItemAtURL:(NSURL *)itemURL trashDirectoryURL:(NSURL *)trashDirectoryURL authorizationData:(NSData *)authorizationData reply:(void (^)(BOOL success, NSError *error))reply;

@end

extern NSString * const OSUInstallerPrivilegedHelperJobLabel;
