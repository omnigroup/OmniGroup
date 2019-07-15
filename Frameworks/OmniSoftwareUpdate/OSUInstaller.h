// Copyright 2007-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@protocol OSUInstallerDelegate;

@interface OSUInstaller : NSObject

+ (NSArray *)supportedPackageFormats;
+ (NSString *)suggestAnotherInstallationDirectory:(NSString *)lastAttemptedPath trySelf:(BOOL)checkOwnDirectory;
+ (void)chooseInstallationDirectory:(NSString *)initialDirectoryPath modalForWindow:(NSWindow *)parentWindow completionHandler:(void (^)(NSError *error, NSString *result))handler;
+ (BOOL)validateTargetFilesystem:(NSString *)path error:(NSError **)outError;

- (id)initWithPackagePath:(NSString *)packagePath;

@property (nonatomic, copy) NSString *installedVersionPath;
@property (nonatomic, copy) NSString *installationDirectory;
@property (nonatomic, weak) id <OSUInstallerDelegate> delegate;

- (void)run;

// This runs a modal panel to choose an installation directory, and calls [self setInstallationDirectory:] if successful.
// Returns YES if a directory was chosen, NO if the user cancels or an error occurs. */
- (BOOL)chooseInstallationDirectory:(NSString *)previousAttemptedPath;

@end

#pragma mark -

@class NSWindow;

@protocol OSUInstallerDelegate
   
- (void)setStatus:(NSString *)statusText;
- (void)close;

@end

