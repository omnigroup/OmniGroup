// Copyright 2007-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniFoundation/OFBinding.h>

@class NSWindow;

@protocol OSUInstallerDelegate
- (void)setStatus:(NSString *)newStatusText;
- (void)close;
- (NSWindow *)windowForSheet;
@end

@interface OSUInstaller : NSObject
{
    BOOL keepExistingVersion;          // If true, leave the existing version where it is (perh. with a new name) instead of moving it to the trash
    BOOL deletePackageOnSuccess;       // If true, move the DMG/tar file/etc to the trash once done
    NSString *packagePath;             // The path to the disk image or tar file
    NSString *existingVersionPath_;    // The path to the installed copy we're replacing
    NSString *installationDirectory;   // The path to the directory we'll install to (usually derived from existingVersionPath)
    NSString *installationName;        // The name (within installationDirectory) of the version we're installing
    
    NSObject <OSUInstallerDelegate> *nonretained_delegate;
    
    /* These are set up as the installer does its thing */
    NSString *unpackedPath;           // Unpacked copy of the new application, on same filesystem as eventual destination
    
    BOOL haveAskedForInstallLocation; // Have we already asked for an installation location?
}

+ (NSArray *)supportedPackageFormats;
+ (NSError *)checkTargetFilesystem:(NSString *)path;
+ (NSString *)suggestAnotherInstallationDirectory:(NSString *)lastAttemptedPath trySelf:(BOOL)checkOwnDirectory;

@property (assign, readwrite) BOOL archiveExistingVersion;
@property (assign, readwrite) BOOL deletePackageOnSuccess;
@property (copy  , readwrite) NSString *installationDirectory;
@property (assign, readwrite) id delegate;

- initWithPackagePath:(NSString *)packagePath;
- (void)setInstalledVersion:(NSString *)aPath;

- (void)run;
- (BOOL)extract:(NSError **)outError;
- (BOOL)installAndRelaunch:(BOOL)shouldRelaunch error:(NSError **)outError;

/* This runs a modal panel to choose an installation directory, and calls [self setInstallationDirectory:] if successful. Returns YES if a directory was chosen, NO if the user cancels or an error occurs. */
- (BOOL)chooseInstallationDirectory:(NSString *)previousAttemptedPath;

@end
