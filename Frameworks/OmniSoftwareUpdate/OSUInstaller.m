// Copyright 2007-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUInstaller.h"

#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSFileManager-OAExtensions.h>
#import <OmniBase/OmniBase.h>
#import <AppKit/AppKit.h>
#import <Security/Security.h>

#import "OSUChecker.h"
#import "OSUErrors.h"
#import "OSUSendFeedbackErrorRecovery.h"
#import "OSUChooseLocationErrorRecovery.h"
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>

#include <CoreServices/CoreServices.h> // For CSIdentity*

RCS_ID("$Id$");

@interface OSUInstaller (/*Private*/)

// General
- (NSString *)_findApplicationInDirectory:(NSString *)dir error:(NSError **)outError;

// Error presentation/recovery callback
- (void)_retry:(BOOL)recovered context:(void *)p;

// Disk image support
- (BOOL)_unpackApplicationFromDiskImage:(NSError **)outError;
- (NSString *)_mountDiskImage:(NSString *)diskImagePath error:(NSError **)outError;
- (void)_unmountDiskImage:(NSString *)mountPoint;
- (BOOL)_unpackApplicationFromMountPoint:(NSString *)mountPoint error:(NSError **)outError;

// tar/bz2 support
- (BOOL)_unpackApplicationFromTarBzip2File:(NSError **)outError;

// Install & Relaunch
- (BOOL)_installAndArchive:(NSError **)outError;
+ (void)_relaunchFromPath:(NSString *)pathString;
static id reportStringForCapturedOutput(NSOutputStream *errorStream);
static id reportStringForCapturedOutputData(NSData *errorStreamData);
static BOOL trashFile(NSString *path, NSString *description, BOOL tryFinder);

@end

@implementation OSUInstaller

+ (NSArray *)supportedPackageFormats;
{
    static NSArray *SupportedPackageFormats = nil;
    
    if (!SupportedPackageFormats) {
        /* This is the list of formats we actually know how to handle */
        NSMutableArray *supportedFormats = [[NSMutableArray alloc] initWithObjects:@"tar.bz2", @"tbz2", @"tar.gz", @"tgz", @"dmg", nil];
        
        /* Allow the user to change the preference ordering, for testing */
        id formatPreference = [[NSUserDefaults standardUserDefaults] objectForKey:@"OSUPreferredPackageFormat"];
        NSArray *preferredFormats;
        if (formatPreference && [formatPreference isKindOfClass:[NSString class]])
            preferredFormats = [NSArray arrayWithObject:formatPreference];
        else if (formatPreference && [formatPreference isKindOfClass:[NSArray class]])
            preferredFormats = formatPreference;
        else
            preferredFormats = nil;
        if (preferredFormats)
            [supportedFormats sortBasedOnOrderInArray:preferredFormats identical:NO unknownAtFront:NO];
        
        SupportedPackageFormats = [supportedFormats copy];
        
        [supportedFormats release];
    }
    return SupportedPackageFormats;
}

#define UPDATE_STATUS(status) [nonretained_delegate setValue:(status) forKey:@"status"]

- initWithPackagePath:(NSString *)newPackage
{
    if (!(self = [super init]))
        return nil;
    
    // Some default settings
    keepExistingVersion = NO;
    deletePackageOnSuccess = YES;
    packagePath = [newPackage copy];
    
    existingVersionPath_ = nil;
    installationDirectory = nil;
    installationName = nil;
    
    haveAskedForInstallLocation = NO;

    return self;
}

@synthesize archiveExistingVersion = keepExistingVersion, deletePackageOnSuccess;
@synthesize delegate = nonretained_delegate;
@synthesize installationDirectory;

- (void)setInstalledVersion:(NSString *)aPath;
{
    aPath = [aPath copy];
    [existingVersionPath_ release];
    existingVersionPath_ = aPath;
    
    if ([[[existingVersionPath_ lastPathComponent] pathExtension] isEqualToString:@"app"])
        [self setInstallationDirectory:[existingVersionPath_ stringByDeletingLastPathComponent]];
}

- (void)run
{
    NSError *error = nil;
    
    if (![self extract:&error]) {
        
        if ([[error domain] isEqualToString:OSUErrorDomain] && [error code] == OSUBadInstallationDirectory && !haveAskedForInstallLocation) {
            if ([self chooseInstallationDirectory:nil]) {
                OBASSERT(haveAskedForInstallLocation);
                [self run];
                return;
            } else {
                if (haveAskedForInstallLocation) {
                    // Handle this like any other failed recovery attempt
                    [[self retain] _retry:NO context:NULL];
                    return;
                }
                // Else, fall through to the normal error presentation code, below.
            }
        }
        
        if (![error recoveryAttempter])
            error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:self options:[OSUChooseLocationErrorRecovery class], [OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
        
        [(nonretained_delegate ? nonretained_delegate : NSApp) presentError:error
                                     modalForWindow:nil
                                           delegate:[self retain] didPresentSelector:@selector(_retry:context:) contextInfo:NULL];
        return; // The didPresentSelector: will take care of the ongoing activity
    }
    
    if (![self installAndRelaunch:YES error:&error]) {
        if (![error recoveryAttempter])
            error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:nil options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
        
        // We don't have any useful recoveries here, but this lets the user opt to send a bug report
        [(nonretained_delegate ? nonretained_delegate : NSApp) presentError:error
                                     modalForWindow:nil
                                           delegate:[self retain] didPresentSelector:@selector(_retry:context:) contextInfo:NULL];
        return; // The didPresentSelector: will take care of the ongoing activity
    }
    
    // We won't normally reach here
    OBASSERT_NOT_REACHED("Should not be able to reach the end of -continueInstallation");
}

+ (NSError *)checkTargetFilesystem:(NSString *)installationPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    /* Check whether the installation path is on a read-only filesystem. (The usual reason for this is that the user is running the application from a disk image, but CDs, network mounts, and so on are other possibilities.) */
    /* NSFileManager doesn't return filesystem flags or anything, so use the POSIX API */
    NSString *statPath;
    int hadError;
    struct statfs sbuf;
    bzero(&sbuf, sizeof(sbuf));
    statPath = installationPath;
    hadError = statfs([fileManager fileSystemRepresentationWithPath:statPath], &sbuf);
    if (hadError != 0 && errno == ENOENT) {
        // Well, maybe we're installing to a new name; see if we can stat the directory
        statPath = [installationPath stringByDeletingLastPathComponent];
        hadError = statfs([fileManager fileSystemRepresentationWithPath:statPath], &sbuf);
    }
    
    if (hadError == 0) {
        if ((sbuf.f_flags & MNT_RDONLY) || (sbuf.f_flags & MNT_NOEXEC)) {
            /* This isn't a filesystem we can install an upgraded application on. */
            
            NSString *whynot, *descr;
            NSString *volname = [fileManager volumeNameForPath:statPath error:NULL];
            
            if (sbuf.f_flags & MNT_RDONLY)
                whynot = NSLocalizedStringFromTableInBundle(@"The destination volume, \\U201C%@\\U201D, is not writable.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error failure reason - when the destination location is on a read-only filesystem such as a disk image or CDROM");
            else
                whynot = NSLocalizedStringFromTableInBundle(@"The destination volume, \\U201C%@\\U201D, does not allow applications.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error failure reason - when the destination location is on a filesystem mounted with NOEXEC (cannot run programs from it)");
            whynot = [NSString stringWithFormat:whynot, volname];
            
            descr = NSLocalizedStringFromTableInBundle(@"Cannot install update there", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - when we notice that we won't be able to unpack the update to the specified location - more detailed text, and an option to choose a different location, will follow");
            
#if 0
            NSString *sugg = NSLocalizedStringFromTableInBundle(@"You may be able to install in a different location.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error recovery suggestion - when we notice that we won't be able to unpack the update to the specified location - we offer to let the user choose another install location");
            
            OSUErrorWithInfo(outError, OSUBadInstallationDirectory,
                             descr, ([NSString stringWithStrings:whynot, @"\n", sugg, nil]),
                             NSLocalizedFailureReasonErrorKey, whynot,
                             NSRecoveryAttempterErrorKey, self,
                             NSLocalizedRecoveryOptionsErrorKey, [NSArray arrayWithObjects:@"foo", @"bar", nil],
                             nil);
#else
            OSUChecker *checker = [OSUChecker sharedUpdateChecker];
            return [NSError errorWithDomain:OSUErrorDomain
                                       code:OSUBadInstallationDirectory
                                   userInfo:[NSDictionary dictionaryWithObjectsAndKeys: descr, NSLocalizedDescriptionKey, whynot, NSLocalizedFailureReasonErrorKey, whynot, NSLocalizedRecoverySuggestionErrorKey, installationPath, NSFilePathErrorKey, [checker applicationIdentifier], OSUBundleIdentifierErrorInfoKey, nil]];
#endif
        }
    }
    
    if (hadError != 0 && !(errno == ENOENT)) {
        /* These errors would presumably keep us from installing anything, quit early */
        
        NSError *error = nil;
        NSString *descr;
        descr = NSLocalizedStringFromTableInBundle(@"Cannot install update there", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - when we notice that we won't be able to unpack the update to the specified location - more detailed text, and an option to choose a different location, will follow");
        
        OBErrorWithErrno(&error, errno, "statfs", statPath, nil);
        OSUErrorWithInfo(&error, OSUBadInstallationDirectory,
                         descr, [error localizedFailureReason],
                         installationPath, NSFilePathErrorKey, nil); // Wraps the errno error
        return error;
    }
    
    return nil; // No error --> success
}

- (BOOL)extract:(NSError **)outError;
{
    BOOL isDir;
    isDir = NO;
    if (unpackedPath &&
        [[NSFileManager defaultManager] fileExistsAtPath:unpackedPath isDirectory:&isDir] &&
        isDir) {
        // We could reach here depending on error recovery
        NSLog(@"Unpacked file already exists at %@, skipping extract step", unpackedPath);
        return YES;
    }
    
    NSError *targetError = [[self class] checkTargetFilesystem:installationDirectory];
    if (targetError) {
        if (outError)
            *outError = targetError;
        return NO;
    }
    
    if ([packagePath hasSuffix:@".dmg"]) {
        return [self _unpackApplicationFromDiskImage:outError];
    } else if ([packagePath hasSuffix:@".tbz2"] || [packagePath hasSuffix:@".tar.bz2"]) {
        return [self _unpackApplicationFromTarBzip2File:outError];
    } else {
        OSUError(outError, OSUUnableToProcessPackage, @"Unable to open package.", @"Unknown package type.");
        return NO;
    }
}

- (NSString *)_chooseAsideNameForFile:(NSString *)existingFile;
{
    if (!existingFile)
        return nil;
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *info = [manager attributesOfItemAtPath:existingFile error:NULL];
    if (!info) {
        // Doesn't exist?
        return nil;
    }
    
    NSString *existingFileDir = [existingFile stringByDeletingLastPathComponent];
    
    // Read information about our bundle version and build a new name for any possible archived version.
    // There are several filenames to consider here, not all of which exist on disk right now:
    //   - The name of the currently installed application
    //   - The name we want to give the newly installed application (may be the same)
    //   - A non-colliding name to give to the application when we archive it
    //   - Any other files which might exist in the target directory
    NSString *archivePath = nil;
    
    NSString *bundleVersion = nil;
    
    NSDictionary *selfInfo = [manager attributesOfItemAtPath:[[NSBundle mainBundle] bundlePath] error:NULL];
    if (selfInfo != nil && [selfInfo isEqual:info]) {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        
        // TODO: We could try to include the marketing version, but if the user *already* included it when the originally downloaded the app, they could get 'OmniFocus 1.0 1.0.app'.  Of course, if the app wrapper has been renamed, then the *new* app will be misnamed too (if they update from "Foo 1.0" to "Foo" v2.0, they'll have an app called 'Foo 1.0' that is actually 2.0.  We could maybe detect if the app isn't named what it is expected to be named (based on the existing app's name and the updating apps' name) and rename stuff differently. In addition, we might want to take into account localized names. Needs more thought on all the cases.
        //NSString *marketingVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
        
        bundleVersion = [infoDictionary objectForKey:(NSString *)kCFBundleVersionKey];
    } else {
        /* If the destination file isn't a valid bundle, this will set bundleVersion to nil, which is what we want. */
        NSBundle *tryBundle = [NSBundle bundleWithPath:existingFile];
        bundleVersion = [[tryBundle infoDictionary] objectForKey:(NSString *)kCFBundleVersionKey];
    }
    
    NSString *oldName = [existingFile lastPathComponent];
    NSString *oldExt = [oldName pathExtension];
    NSString *newName = oldName;
    if (![NSString isEmptyString:bundleVersion]) {
        newName = [[[oldName stringByDeletingPathExtension] stringByAppendingFormat:@" %@", bundleVersion] stringByAppendingPathExtension:oldExt];
    }
    archivePath = [existingFileDir stringByAppendingPathComponent:newName];

    return archivePath;
}

- (BOOL)installAndRelaunch:(BOOL)shouldRelaunch error:(NSError **)outError;
{    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Installing\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));

    OBPRECONDITION(![NSString isEmptyString:installationName]);
    OBPRECONDITION(![NSString isEmptyString:packagePath]);
    
    if (![self _installAndArchive:outError])
        return NO;
    
    if (deletePackageOnSuccess) {
        // The install portion is done; we can torch the dmg now.  Put it in the trash instead of deleting it forever.
        trashFile(packagePath, @"package", NO);
    }
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Restarting\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description - when quitting this application in order to finish upgrading")));
    [[self class] _relaunchFromPath:[installationDirectory stringByAppendingPathComponent:installationName]];
    
    // We shouldn't get here.
    OBASSERT_NOT_REACHED("We should have relaunched!");
    exit(1);
    return YES;
}

+ (NSString *)suggestAnotherInstallationDirectory:(NSString *)lastAttemptedPath trySelf:(BOOL)checkOwnDirectory;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (checkOwnDirectory) {
        NSString *ownDir = [[[[NSBundle mainBundle] bundlePath] stringByExpandingTildeInPath] stringByDeletingLastPathComponent];
        if (![NSString isEmptyString:ownDir]) {
            // Just install in our current location if it looks OK.
            if (!(lastAttemptedPath && [ownDir hasPrefix:lastAttemptedPath]) &&
                ![self checkTargetFilesystem:ownDir]) {
                return ownDir;
            }
            
            // I guess we should add ownDir to the list of candidate directories, but if it didn't pass the above tests, it won't pass the below ones either.
        }
    }
        
    // Our algorithm: Find the set of normal installation directories, and look for one of these in order:
    //   An installation directory that already contains an app with this bundle identifier
    //   An installation directory that is writable by this user
    // This will probably need some tweaking once we get feedback on actual user experiences.
    
    // We use multiple calls to NSSearchPathForDirectoriesInDomains() because we want to tweak the order of entries
    NSMutableArray *appDirectories = [NSMutableArray array];
    [appDirectories addObjectsFromArray:NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSUserDomainMask|NSLocalDomainMask|NSNetworkDomainMask, YES)];
    [appDirectories reverse]; // The search path goes from local to global; we want to prefer a more global installation
    [appDirectories addObjectsFromArray:NSSearchPathForDirectoriesInDomains(NSDemoApplicationDirectory, NSLocalDomainMask|NSNetworkDomainMask, YES)];
    [appDirectories addObjectsFromArray:NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES)];
    
    // NSLog(@"Directories: %@", appDirectories);

    NSMutableArray *candidates = [NSMutableArray arrayWithCapacity:[appDirectories count]];
    for(NSUInteger dirIndex = 0; dirIndex < [appDirectories count]; dirIndex ++) {
        NSString *appDir = [appDirectories objectAtIndex:dirIndex];
        
        if (lastAttemptedPath && [appDir isEqualToString:lastAttemptedPath]) {
            // Didn't work last time -> don't re-suggest it
            continue;
        }
        
        if ([OSUInstaller checkTargetFilesystem:appDir] == nil) {
            // No error -> looks OK
            [candidates addObject:appDir];
        }
    }
    
    // NSLog(@"Candidates: %@", candidates);
    
    NSString *installedDirectory = nil;
    
    // See if the application is already installed in one of the directories we're considering
    NSString *installingBundleIdentifier = [[OSUChecker sharedUpdateChecker] applicationIdentifier];
    
    if (![NSString isEmptyString:installingBundleIdentifier]) {
        CFURLRef appURL = NULL;
        OSStatus osErr = LSFindApplicationForInfo(kLSUnknownCreator, (CFStringRef)installingBundleIdentifier, NULL, NULL, &appURL);
        if (osErr == noErr && appURL != NULL) {
            CFURLRef absolute = CFURLCopyAbsoluteURL(appURL);
            CFStringRef urlPath = CFURLCopyFileSystemPath(absolute, kCFURLPOSIXPathStyle);
            installedDirectory = [(NSString *)urlPath autorelease];
            CFRelease(absolute);
            CFRelease(appURL);
        }
    }
    
    NSString *chosenDirectory = nil;
    
    if (installedDirectory) {
        // NSLog(@"Installed copy: %@", installedDirectory);
        for(NSUInteger dirIndex = 0; dirIndex < [candidates count]; dirIndex ++) {
            NSString *appDir = [candidates objectAtIndex:dirIndex];
            if ([installedDirectory hasPrefix:appDir]) {
                // The app might be in a subdirectory of one of the standard directories, e.g. /Network/Applications/Omni/Blah.app
                chosenDirectory = [installedDirectory stringByDeletingLastPathComponent];
                // NSLog(@"Choosing %@ because it contains installed copy", chosenDirectory);
                break;
            }
        }
    }
    
    // Otherwise, just look for the first writable directory
    if (!chosenDirectory) {
        for(NSUInteger dirIndex = 0; dirIndex < [candidates count]; dirIndex ++) {
            NSString *appDir = [candidates objectAtIndex:dirIndex];
            if ([fileManager isWritableFileAtPath:appDir]) {
                chosenDirectory = appDir;
                // NSLog(@"Choosing %@ because it's writable", chosenDirectory);
                break;
            }
        }
    }
    
    return chosenDirectory; // May still be nil.
}

- (BOOL)chooseInstallationDirectory:(NSString *)lastAttemptedPath;
{
    // Set up the save panel for selecting an install location.
    NSOpenPanel *chooseInstallLocation = [NSOpenPanel openPanel];
    [chooseInstallLocation setAllowedFileTypes:[NSArray arrayWithObject:(id)kUTTypeApplicationBundle]];
    [chooseInstallLocation setAllowsOtherFileTypes:NO];
    [chooseInstallLocation setCanCreateDirectories:YES];
    [chooseInstallLocation setCanChooseDirectories:YES];
    [chooseInstallLocation setCanChooseFiles:NO];
    [chooseInstallLocation setResolvesAliases:YES];
    [chooseInstallLocation setAllowsMultipleSelection:NO];    

    NSString *chosenDirectory = [[self class] suggestAnotherInstallationDirectory:lastAttemptedPath trySelf:NO];
    
    if (!chosenDirectory) {
        // If we couldn't find any writable directories, we're kind of screwed, but go ahead and pop up the panel in case the user can navigate somewhere
        if (lastAttemptedPath)
            chosenDirectory = [lastAttemptedPath stringByDeletingLastPathComponent];
    }

    if (chosenDirectory)
        [chooseInstallLocation setDirectoryURL:[NSURL fileURLWithPath:chosenDirectory]];
    
    // There is no analog to the file argument of the deprecated -runModalForDirectory:file: as far as I can tell.
    // NSString *selectedFile = lastAttemptedPath ? [lastAttemptedPath lastPathComponent] : installationName;
    
    haveAskedForInstallLocation = YES;
    NSUInteger code = [chooseInstallLocation runModal];
    
    // TODO: Run the panel as a sheet if [nonretained_delegate windowForSheet] is non-nil
    
    if (code == NSFileHandlingPanelOKButton) {
        // Success!
        NSURL *resultURL = [[[chooseInstallLocation URLs] lastObject] absoluteURL];
        [self setInstallationDirectory:[resultURL path]];
        return YES;
    } else {
        // Failure!
        return NO;
    }
}


#pragma mark -
#pragma mark Private

/* This is used as the didPresent selector for error presentation / recovery */
- (void)_retry:(BOOL)recovered context:(void *)p
{
    [self autorelease];
    
    if (recovered) {
        [self run];
    } else {
        // Reveal the disk image (or other downloaded package) on failure.
        [[NSWorkspace sharedWorkspace] selectFile:packagePath inFileViewerRootedAtPath:nil];
        [nonretained_delegate close];
    }
}

- (NSString *)_findApplicationInDirectory:(NSString *)dir error:(NSError **)outError;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    /* Avoid scanning the directory using NSFileManager (or any other Carbon APIs), due to RADAR 5468824 (see below) */
    const char *dirPath = [dir fileSystemRepresentation];
    DIR *dirhandle = opendir(dirPath);
    if (!dirhandle) {
        OBErrorWithErrno(outError, errno, "opendir", dir, NSLocalizedStringFromTableInBundle(@"Could not read directory", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - we downloaded and unpacked an update, but now we can't read it"));
        return nil;
    }
    
    NSMutableArray *appDirNames, *nonAppDirNames;
    appDirNames = [NSMutableArray array];
    nonAppDirNames = [NSMutableArray array];
    
    for(;;) {
        struct dirent buf, *bufp;
        bzero(&buf, sizeof(buf));
        if(readdir_r(dirhandle, &buf, &bufp)) {
            OBErrorWithErrno(outError, errno, "readdir", dir, NSLocalizedStringFromTableInBundle(@"Could not read directory", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - we downloaded and unpacked an update, but now we can't read it"));
            return nil;
        }

        /* NULL bufp indicates we've read all the dir entries */
        if (!bufp)
            break;
        
        /* We're not interested in hidden files */
        if (buf.d_namlen < 1 || buf.d_name[0] == '.')
            continue;
        
        /* We sometimes do get a d_type, and sometimes don't. Depends on the fs type. Sigh. */
        if (buf.d_type == DT_UNKNOWN) {
            char *fullpath = malloc(strlen(dirPath) + buf.d_namlen + 2);
            strcpy(fullpath, dirPath);
            strcat(fullpath, "/");
            strcat(fullpath, buf.d_name);
            struct stat sbuf;
            bzero(&sbuf, sizeof(sbuf));
            int rc = stat(fullpath, &sbuf);
            free(fullpath);
            if (rc == 0)
                buf.d_type = IFTODT(sbuf.st_mode);
        }
        
        /* We're only interested in directories (.app bundles and subdirs) */
        if (buf.d_type != DT_DIR)
            continue;
        
        NSString *dirname = [fileManager stringWithFileSystemRepresentation:buf.d_name length:buf.d_namlen];
        if ([dirname hasSuffix:@".app"])
            [appDirNames addObject:dirname];
        else
            [nonAppDirNames addObject:dirname];
    }
    
    closedir(dirhandle);
    
    NSUInteger appCount = [appDirNames count];
    
    if (appCount == 1) {
        /* Good, we found exactly one app. Return it. */
        return [dir stringByAppendingPathComponent:[appDirNames objectAtIndex:0]];
    } else if (appCount == 0 && [nonAppDirNames count] == 1) {
        /* If we don't see any applications, but there is exactly one subdirectory, check in there */
        return [self _findApplicationInDirectory:[dir stringByAppendingPathComponent:[nonAppDirNames objectAtIndex:0]] error:outError];
    } else {
        /* Otherwise, we fail to find an application in this directory */
        if (outError) {
            NSString *description, *reason;
            
            description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - we downloaded an update, but it doesn't seem to be valid");
            
            if (appCount > 1)
                reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"More than one application found in update (%@)", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - we downloaded an update, and it has more than one application in it"), [appDirNames componentsJoinedByComma]];
            else
                reason = NSLocalizedStringFromTableInBundle(@"No application was found in the update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - we downloaded an update, but it doesn't seem to contain a new application");
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToUpgrade userInfo:userInfo];
        }
        return nil;
    }
}

static BOOL isApplicationSuperficiallyValid(NSString *path, NSError **outError)
{
    struct stat sbuf;
    NSString *badness;
    
    // Check a handful of things about an application before we try to install it, just to avoid installing a completely broken app.
    // As with _findApplicationInDirectory:error:, we want to avoid indirectly using Carbon APIs here.
    // None of these tests should ever fail unless we've made an error packaging up the application for distribution, but we have been known to do that...
    
    if (stat([path fileSystemRepresentation], &sbuf) != 0) {
        OBErrorWithErrno(outError, errno, "stat", path, NSLocalizedStringFromTableInBundle(@"Could not read directory", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - we downloaded and unpacked an update, but now we can't read it"));
        return NO;
    }
    if (!S_ISDIR(sbuf.st_mode)) {
        badness = @"App bundle is not a directory";
        goto return_failure;
    }
        
    NSString *contentsPath = [path stringByAppendingPathComponent:@"Contents"];
    
    NSData *infoPlistBytes = [NSData dataWithContentsOfFile:[contentsPath stringByAppendingPathComponent:@"Info.plist"] options:NSMappedRead error:outError];
    if (!infoPlistBytes)
        return NO; // NSData set outError for us
    CFStringRef err = NULL;
    NSDictionary *infoPlist = (NSDictionary *)CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)infoPlistBytes, kCFPropertyListImmutable, &err);
    if (!infoPlist) {
        badness = [NSString stringWithFormat:@"Can't read Info.plist: %@", err];
        goto return_failure;
    }
    [infoPlist autorelease];
    if (![infoPlist isKindOfClass:[NSDictionary class]] ||
        ![[infoPlist objectForKey:(NSString *)kCFBundleIdentifierKey] isKindOfClass:[NSString class]] ||
        ![[infoPlist objectForKey:(NSString *)kCFBundleExecutableKey] isKindOfClass:[NSString class]]) {
        badness = @"Info.plist does not contain necessary information";
        goto return_failure;
    }
    
    NSString *execFile = [[contentsPath stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:[infoPlist objectForKey:(NSString *)kCFBundleExecutableKey]];
    if (stat([execFile fileSystemRepresentation], &sbuf) != 0) {
        OBErrorWithErrno(outError, errno, "stat", execFile, NSLocalizedStringFromTableInBundle(@"Could not examine application", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - we downloaded and unpacked an update, but we can't stat its CFBundleExecutable file"));
        return NO;
    }
    if (!S_ISREG(sbuf.st_mode) || !(sbuf.st_mode & S_IXUSR) || (sbuf.st_size < 1024)) {
        badness = [NSString stringWithFormat:@"Not an executable: %@", [infoPlist objectForKey:(NSString *)kCFBundleExecutableKey]];
        goto return_failure;
    }

    // We didn't see anything obviously wrong, so it's probably OK
    return YES;
    
    
    if (0) {
        NSString *description, *reason;

    return_failure:

        if (outError) {
            description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - we downloaded an update, but there seems to be something wrong with the application it contained");
            reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The updated application is invalid (%@)", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - we downloaded an update, but there's something obviously wrong with the updated application, like it doesn't have an Info.plist or whatever"), badness];
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToUpgrade userInfo:userInfo];
        }
        return NO;
    }
}

#pragma mark -
#pragma mark Disk image support

- (BOOL)_unpackApplicationFromDiskImage:(NSError **)outError;
{
    BOOL extracted;
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Mounting disk image\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status message")));
    NSString *mountPoint = [self _mountDiskImage:packagePath error:outError];
    if (!mountPoint)
        return NO;
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Extracting updated application\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status message - copying application from disk image to target filesystem")));
    extracted = [self _unpackApplicationFromMountPoint:mountPoint error:outError];
    
    // The disk image is unneeded now; unmount even if there was an error unpacking it.
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Unmounting disk image\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status message")));
    [self _unmountDiskImage:mountPoint];
    
    return extracted;
}

- (NSString *)_mountDiskImage:(NSString *)diskImagePath error:(NSError **)outError;
{
    // hdituil emits the plist *and* the EULA on stdout.  Clever.  Luckily, it only puts the EULA through the PAGER, so we'll deep six that part.
    // (RADAR 4708028, not that Apple's likely to fix it.)
    NSDictionary *hdiutilEnvirons = [[NSProcessInfo processInfo] environment];
    hdiutilEnvirons = [hdiutilEnvirons dictionaryWithObject:@"/bin/cat /dev/null" forKey:@"PAGER"];
    
    if (outError)
        *outError = nil;
    
    // We still have to agree to the EULA.  Terrible.
#warning Does the answer to the EULA agreement need to be localized?    
    NSData *yesData = [@"y\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open]; // or appending to the stream will produce an error
    NSOutputStream *outputStream = [NSOutputStream outputStreamToMemory];
    [outputStream open];

    // Radar 5468824: hdiutil attach can confuse NSFileManager.  It seems this can results in NSFileManager reading from some random other mounted disk image if there is one.  If no other disk image is mounted, it works OK.   Passing just '-plist' doesn't make the problem any better, it seems.
    // NOTE: We aren't using NSFileManager to do the unpack anymore, so I'm turning these flags back on so that disk images will stop popping up on screen for users.

    NSArray *arguments = [NSMutableArray arrayWithObjects:@"attach",
        @"-plist", // provide result output in plist format.  Other programs invoking hdiutil are expected to use -plist rather than try to parse the usual output.  The usual output will remain consistent but unstructured.
        @"-private", // suppress mount notifications to the rest of the system.  Note that -private can confuse programs using the Carbon File Manager and should generally be avoided.
        @"-nobrowse", // mark the volumes non-browsable in applications such as the Finder.
        @"-noautoopen", // do [not] auto-open volumes (in the Finder) after attaching an image.  By default, read-only volumes are auto-opened in the Finder.
        
        // Trying -nokernel in an attempt to avoid <bug://40976>, where in one case we got an error from hdiutil:
        //    load_hdi: IOHDIXControllerArrivalCallback: timed out waiting for IOKit to finish matching.
        // Well, if the kernel can get b0rked, let's try using a user-space process instead.
        @"-nokernel", // attach with a helper process.
        
        diskImagePath, nil]; // Finally, the image we want to mount

    OFFilterProcess *hdiutil = [[OFFilterProcess alloc] initWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:yesData, OFFilterProcessInputDataKey,
                                                                            @"/usr/bin/hdiutil", OFFilterProcessCommandPathKey,
                                                                            arguments, OFFilterProcessArgumentsKey,
                                                                            hdiutilEnvirons, OFFilterProcessReplacementEnvironmentKey, nil]
                                                            standardOutput:outputStream
                                                             standardError:errorStream];
    
    if ([hdiutil error]) {
        if (outError)
            *outError = [hdiutil error];
        [hdiutil autorelease];
        return nil;
    }
    
    [hdiutil run];
    
    if ([hdiutil error]) {
        if (outError)
            *outError = [hdiutil error];
        [hdiutil autorelease];
        return nil;
    }
    [outputStream close];
    [errorStream close];
    [hdiutil release];
    
    if ([outputStream streamStatus] == NSStreamStatusError) {
        if (outError)
            *outError = [outputStream streamError];
        return nil;
    }
    
    NSData *hdiResults = [outputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    
    // filterDataThroughCommandAtPath:... will return an empty data in some cases -- once we figure out what that is, we should fix it.
    if (hdiResults == nil || [hdiResults length] == 0) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"hdiutil failed to attach the disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey,   reportStringForCapturedOutput(errorStream), @"hdiutil-stderr", nil];
            
            if (hdiResults)
                [userInfo setObject:hdiResults forKey:@"hdi-result-data"];
            OBASSERT(*outError != nil);
            if (*outError)
                [userInfo setObject:*outError forKey:NSUnderlyingErrorKey];
            
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToMountDiskImage userInfo:userInfo];
        }

        return nil;
    }
    
    NSString *plistError = nil;
    NSDictionary *plist = [NSPropertyListSerialization propertyListFromData:hdiResults mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&plistError];
    
    if (!plist && plistError) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to parse the response from hdiutil: %@", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), plistError];
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, hdiResults, @"hdi-result-data", reportStringForCapturedOutput(errorStream), @"hdiutil-stderr", nil];
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToMountDiskImage userInfo:userInfo];
        }
        return nil;
    }

    NSArray *entities = [plist objectForKey:@"system-entities"];
    
    // There can be multiple entries in entities; and the order isn't well defined.
    NSString *mountPoint = nil;
    NSUInteger entityIndex, entityCount = [entities count];
    for (entityIndex = 0; entityIndex < entityCount; entityIndex++) {
        NSDictionary *entity = [entities objectAtIndex:entityIndex];
        NSString *potentialMountPoint = [entity objectForKey:@"mount-point"];
        if (potentialMountPoint) {
            if (mountPoint && ![mountPoint isEqualToString:potentialMountPoint]) { // Never seen a case where they are equal, just checking.
                if (outError) {
                    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
                    NSString *reason = NSLocalizedStringFromTableInBundle(@"Multiple mount points found in hdiutil results.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, plist, @"hdi-result-plist", reportStringForCapturedOutput(errorStream), @"hdiutil-stderr", nil];
                    *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToMountDiskImage userInfo:userInfo];
                }
                return nil;
            } else
                mountPoint = potentialMountPoint;
        }
    }

    if (mountPoint == nil) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"No mount point found in hdiutil results.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, plist, @"hdi-result-plist", reportStringForCapturedOutput(errorStream), @"hdiutil-stderr", nil];
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToMountDiskImage userInfo:userInfo];
        }
        return nil;
    }
    NSLog(@"Disk image mounted at '%@'", mountPoint);
    
    return mountPoint;
}

- (void)_unmountDiskImage:(NSString *)mountPoint;
{
    NSLog(@"Unmounting '%@'", mountPoint);
    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"detach", @"-force", @"-quiet", mountPoint, nil]];
}

- (NSString *)_chooseTemporaryPath:(NSString *)nameHint error:(NSError **)outError;
{
    NSString *result = [[NSFileManager defaultManager] temporaryPathForWritingToPath:[installationDirectory stringByAppendingPathComponent:nameHint] allowOriginalDirectory:YES create:NO error:outError];

#ifdef DEBUG
    NSLog(@"Choosing directory to unpack into: installationDirectory=%@ installationName=%@ nameHint=%@ %@",
          installationDirectory, installationName, nameHint,
          result? [NSString stringWithFormat:@"temporaryPath=%@", result] : [NSString stringWithFormat:@"error=%@", outError ? [*outError description] : @"???"]);
#endif
    
    return result;
}

- (BOOL)_unpackApplicationFromMountPoint:(NSString *)mountPoint error:(NSError **)outError;
{
    NSString *packagedApp = [self _findApplicationInDirectory:mountPoint error:outError];
    
    if (!packagedApp)
        return NO;
    
    if (!isApplicationSuperficiallyValid(packagedApp, outError))
        return NO;
    
    if ([NSString isEmptyString:installationName]) {
        [installationName release];
        installationName = [[packagedApp lastPathComponent] retain];
    }
    
    NSString *temporaryPath = [self _chooseTemporaryPath:installationName error:outError];
    if (!temporaryPath)
        return NO;
    
    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open];
    
    OFFilterProcess *ditto = [[OFFilterProcess alloc] initWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                          [NSData data], OFFilterProcessInputDataKey,
                                                                          @"/usr/bin/ditto", OFFilterProcessCommandPathKey,
                                                                          [NSArray arrayWithObjects:packagedApp, temporaryPath, nil], OFFilterProcessArgumentsKey,
                                                                          nil]
                                                          standardOutput:errorStream
                                                           standardError:errorStream];
    [ditto run];
    [errorStream close];
    
    if ([ditto error]) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - could not copy from disk image to destination filesystem");
            NSString *reason = reportStringForCapturedOutput(errorStream);
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey,
                                      [ditto error], NSUnderlyingErrorKey, nil];
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToProcessPackage userInfo:userInfo];
        }
        
        [ditto release];
        return NO;
    }
    
    [ditto release];
    
    if (!isApplicationSuperficiallyValid(temporaryPath, outError)) {
        // Ditto didn't work?
        return NO;
    }
    
    unpackedPath = [temporaryPath copy];
    return YES;
}

#pragma mark -
#pragma mark tar/bz2 support

- (BOOL)_unpackApplicationFromTarBzip2File:(NSError **)outError;
{
    NSString *expander;
    
    if ([packagePath hasSuffix:@".tbz2"] || [packagePath hasSuffix:@".tar.bz2"])
        expander = @"--bzip2";
    else if ([packagePath hasSuffix:@".tgz"] || [packagePath hasSuffix:@".tar.gz"])
        expander = @"--gzip";
    else if ([packagePath hasSuffix:@".tar"])
        expander = nil;
    else {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - could not process .tar.bz2 file");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Unknown package type.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - downloaded upgrade package was not in a format we recognize");
        OSUError(outError, OSUUnableToProcessPackage, description, reason);
        return NO;
    }
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Decompressing\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    
    // Create a temporary directory into which to unpack
    NSString *temporaryPath = [self _chooseTemporaryPath:[[packagePath lastPathComponent] stringByDeletingPathExtension] error:outError];
    if (!temporaryPath)
        return NO;
    
    NSFileManager *manager = [NSFileManager defaultManager];
    
    if (![manager createDirectoryAtPath:temporaryPath withIntermediateDirectories:YES attributes:nil error:outError]) {
        NSString *reason = [NSString stringWithFormat:@"Could not create temporary directory at '%@'.", temporaryPath];
        OSUError(outError, OSUBadInstallationDirectory, @"Unable to install update.", reason);
        return NO;
    }
    
    NSMutableDictionary *extract = [NSMutableDictionary dictionary];
    [extract setObject:@"/usr/bin/tar"
                forKey:OFFilterProcessCommandPathKey];
    [extract setObject:[NSArray arrayWithObjects:@"xf", packagePath, expander /* may be nil, therefore must be last */, nil]
                forKey:OFFilterProcessArgumentsKey];
    [extract setObject:temporaryPath
                forKey:OFFilterProcessWorkingDirectoryPathKey];
    
    NSData *errData = nil;
    
    if (![OFFilterProcess runWithParameters:extract
                                     inMode:NSModalPanelRunLoopMode
                             standardOutput:&errData standardError:&errData
                                      error:outError]) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - could not process .tar.bz2 file");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"Extract script failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey,
                                      reportStringForCapturedOutputData(errData), @"extract-stderr", extract, @"filter-params", nil];
            if (*outError)
                userInfo = [userInfo dictionaryWithObject:*outError forKey:NSUnderlyingErrorKey];
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToProcessPackage userInfo:userInfo];
        }
        return NO;
    }
        
    // Look for a single .app directory inside the unpacked path; this is what we are to return.
    NSString *appPath = [self _findApplicationInDirectory:temporaryPath error:outError];
    if (!appPath)
        return NO;
    
    if (!isApplicationSuperficiallyValid(appPath, outError))
        return NO;
    
    unpackedPath = [appPath copy];
    
    if ([NSString isEmptyString:installationName]) {
        [installationName release];
        installationName = [[unpackedPath lastPathComponent] retain];
    }
    
    return YES;
}

#pragma mark -
#pragma mark Install & Relaunch

static BOOL isInGroupList(gid_t targetGID)
{
    if (targetGID == getgid())
        return YES;
    
    gid_t otherGIDs[NGROUPS_MAX];
    int ngroups = getgroups(NGROUPS_MAX, otherGIDs);
    if (ngroups > 0) {
        int groupindex;
        for(groupindex = 0; groupindex < ngroups; groupindex ++) {
            if (targetGID == otherGIDs[groupindex]) {
                return YES;
            }
        }
    }
    
    return NO;
}

static BOOL NeedsAuthentication_DestDir(NSString *installationDirectory)
{
    // There are two reasons we might need to elevate privileges in order to install. One possibility is that we want to install as some other user (e.g., as 'root' or 'appowner' in a shared directory). The other possibility is that we're trying to install in a directory which we don't have write access to.
    
    uid_t runningUID = getuid();
        
    NSFileManager *manager = [NSFileManager defaultManager];
    
    // Use access(), which handles groups, ACLs, blah blah.
    if(access([manager fileSystemRepresentationWithPath:installationDirectory], R_OK|W_OK)) {
        if (errno == EACCES) {
            NSLog(@"Running user (id %u) cannot write to installation directory '%@'.  Will perform authenticated installation.", (unsigned)runningUID, installationDirectory);
            return YES;
        } else {
            NSLog(@"Warning: installation may fail; access(%@): %s", installationDirectory, strerror(errno));
        }
    }
        
    if (![manager isWritableFileAtPath:installationDirectory]) {
        NSLog(@"Installation folder '%@' is not writable.  Will perform authenticated installation.", installationDirectory);
        return YES;
    }
    
    return NO;
}

static BOOL NeedsAuthentication_Ownership(uid_t destinationUID, gid_t destinationGID)
{
    // There are two reasons we might need to elevate privileges in order to install. One possibility is that we want to install as some other user (e.g., as 'root' or 'appowner' in a shared directory). The other possibility is that we're trying to install in a directory which we don't have write access to.
    
    uid_t runningUID = getuid();
    
    if (destinationUID != runningUID) {
        NSLog(@"Running user has uid %d but we want to install as owner uid %d.  Will perform authenticated installation.", runningUID, destinationUID);
        return YES;
    }
    
    // Directories with the sticky bit set, like /Applications, can result in installed applications having one of our supplementary GIDs.
    if (!isInGroupList(destinationGID)) {
        NSLog(@"Running user has gid %d but we want to install as group id %d.  Will perform authenticated installation.", getgid(), destinationGID);
        return YES;
    }
    
    return NO;
}

static BOOL PerformNormalInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError);
static BOOL PerformAuthenticatedInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError);

static CSIdentityRef copyCSIdentityFromPosixId(id_t posixId, CSIdentityClass identityClass)
{
    CSIdentityRef result;
    
    CSIdentityQueryRef query = CSIdentityQueryCreateForPosixID(kCFAllocatorDefault, posixId, identityClass, CSGetDefaultIdentityAuthority());
    if (CSIdentityQueryExecute(query, kCSIdentityQueryIncludeHiddenIdentities, NULL)) {
        CFArrayRef idents = CSIdentityQueryCopyResults(query);
        if (CFArrayGetCount(idents) > 0) {
            result = (CSIdentityRef)CFArrayGetValueAtIndex(idents, 0);
            CFRetain(result);
        } else {
            result = NULL;
        }
        CFRelease(idents);
    } else {
        result = NULL;
    }
    CFRelease(query);
    
    return result;
}

// Try to guess what uid and gid the user expects the installed version to be owned by.
// This is all pretty heuristic; what we mostly do is imitate the old version's ownership if it's owned by a system user, but if it's owned by a normal user, just install as us.
static void checkInstallAsOtherUser(const struct stat *sbuf, uid_t *as_uid, gid_t *as_gid)
{
    uid_t destinationUID = sbuf->st_uid;
    gid_t destinationGID = sbuf->st_gid;
    
    if (destinationUID != *as_uid) {
        // If it's owned by a special user, install the new version as that user. Otherwise, assume it should be owned by whoever installs it.
        CSIdentityRef owner = copyCSIdentityFromPosixId(destinationUID, kCSIdentityClassUser);
        if (owner && CSIdentityIsHidden(owner)) {
            *as_uid = destinationUID;
            *as_gid = destinationGID;  // TODO: Only do this if group matches owner? Need actual use case info
        }
        if (owner)
            CFRelease(owner);
    } else {
        // If it's owned by us, but by one of our supplementary group IDs, chown to the same supplementary gid when we install it.
        // (If it's owned by us but group-ownership is some group we're not in, don't bother elevating privs to install, just install as us)
        if (destinationUID == getuid()) {
            if (isInGroupList(destinationGID)) {
                *as_gid = destinationGID;
            }
        }
    }
}

static void checkInstallWithFlags(const char *posixPath, const struct stat *sbuf, BOOL *setImmutable, BOOL *authRequired)
{
    /* Deal with the immutable flag (aka the Finder's "Locked" checkbox) */
    if (sbuf->st_flags & (UF_IMMUTABLE|UF_APPEND|SF_IMMUTABLE|SF_APPEND)) {
        char *flagsstr = fflagstostr(sbuf->st_flags);
        NSLog(@"existing file's flags = %s", flagsstr);
        free(flagsstr);
        
        *setImmutable = YES;
        
        /* Can we turn off the immutable bit ourselves? If so, no need to authenticate. */
        if (chflags(posixPath, sbuf->st_flags & ~(UF_IMMUTABLE|UF_APPEND|SF_IMMUTABLE|SF_APPEND)) == 0) {
            /* Hooray. */
        } else {
            *authRequired = YES;
            NSLog(@"  (Will perform authenticated installation to change flags.)");
        }
    }
}

- (BOOL)_installAndArchive:(NSError **)outError;
{
    OBPRECONDITION(unpackedPath);
    OBPRECONDITION(installationDirectory);
    OBPRECONDITION(installationName);
    NSFileManager *manager = [NSFileManager defaultManager];
        
    NSString *installerPath = [OMNI_BUNDLE pathForResource:@"OSUInstaller" ofType:@"sh"];
    if (!installerPath) {
	NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Cannot find the installer script.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - OSUInstaller.sh is missing");
        OSUError(outError, OSUUnableToUpgrade, description, reason);
        return NO;
    }
    
#ifdef DEBUG
    NSLog(@"existingVersionPath = %@", existingVersionPath_);
    NSLog(@"unpackedPath = %@", unpackedPath);
    NSLog(@"installationDirectory = %@", installationDirectory);
    NSLog(@"installationName = %@", installationName);
#endif
    
    /* The path at which the new application will end up */
    NSString *finalInstalledPath = [installationDirectory stringByAppendingPathComponent:installationName];
    
    /* Are we going to rename something (an existing version)? If so, what are we renaming it to? */
    NSString *pathToArchive, *archivePath;
    pathToArchive = nil;
    
    BOOL authRequired = NO;  // Are we going to need to authenticate to install?
    
    // UID, GID, and uimmutable settings for the new application
    uid_t destinationUID = getuid();
    gid_t destinationGID = getgid();
    BOOL setImmutable = NO;

    // Our theory here is that if we're installing in the same directory as the existing version, we're "replacing" it and should imitate its ownership, otherwise we're just installing as us.
    if ([installationDirectory isEqualToString:[existingVersionPath_ stringByDeletingLastPathComponent]]) {
        struct stat dest_stat;
        bzero(&dest_stat, sizeof(dest_stat));
        const char *posixPath = [existingVersionPath_ fileSystemRepresentation];
        
        if (stat(posixPath, &dest_stat) == 0) {

            /* Decide whether we should chown the app to some other uid or gid */
            checkInstallAsOtherUser(&dest_stat, &destinationUID, &destinationGID);
            checkInstallWithFlags(posixPath, &dest_stat, &setImmutable, &authRequired);
            
            pathToArchive = existingVersionPath_;
        }
    }
    if (![existingVersionPath_ isEqualToString:finalInstalledPath]) {
        // Otherwise, check if we're *literally* replacing some file that *isn't* us.
        
        struct stat dest_stat;
        bzero(&dest_stat, sizeof(dest_stat));
        const char *posixPath = [finalInstalledPath fileSystemRepresentation];
     
        if (stat(posixPath, &dest_stat) == 0) {
            
            /* Decide whether we should chown the app to some other uid or gid */
            checkInstallAsOtherUser(&dest_stat, &destinationUID, &destinationGID);
            checkInstallWithFlags(posixPath, &dest_stat, &setImmutable, &authRequired);

            // Can we simply trash the other guy now? Can we, can we? Huh boss? Can we?
            BOOL doArchiveDance = YES;
            
            if (!keepExistingVersion) {
                if (trashFile(finalInstalledPath, @"other version", !authRequired))
                    doArchiveDance = NO;
            }
            
            if (doArchiveDance) {
                // Nah, gotta do the archive dance
                
                if (pathToArchive)
                    NSLog(@"OmniSoftwareUpdate: Not sure whether I should archive %@ or %@. Choosing %@.",
                          [existingVersionPath_ lastPathComponent], [finalInstalledPath lastPathComponent], [finalInstalledPath lastPathComponent]);
                pathToArchive = finalInstalledPath;
            }
        }
    }
    
    /* Choose a name for the file we're moving aside (archiving) */
    if (pathToArchive) {
#ifdef DEBUG
        NSLog(@"pathToArchive = %@", pathToArchive);
#endif
        archivePath = [self _chooseAsideNameForFile:pathToArchive];
        archivePath = [manager uniqueFilenameFromName:archivePath allowOriginal:YES create:NO error:outError];
        if (!archivePath)
            return NO;
#ifdef DEBUG
        NSLog(@"archivePath = %@", archivePath);
#endif
    } else {
        archivePath = nil;
    }
        
    // The authorization framework gives stdin/stdout if we ask, but we want stderr.  So, the installer script takes the name of a file to write its errors to.
    NSString *errorFile = [manager temporaryPathForWritingToPath:@"/tmp/OSUInstallerLog" allowOriginalDirectory:YES create:NO error:outError];
    if (!errorFile)
        return NO;
    
    // Installer script arguments: what to install from, where to install it, and where to put stderr
    NSMutableArray *installerArguments = [NSMutableArray arrayWithObjects:unpackedPath, finalInstalledPath, errorFile, nil];
    
    // Note that the install script doesn't use a real getopt, so the ordering of all the arguments and options is fixed
    
    // If we want to change the ownership of the file, pass the -u flag
    NSString *ugid = (destinationUID == getuid())? @"" : [NSString stringWithFormat:@"%u", destinationUID];
    if (destinationGID != getgid())
        ugid = [ugid stringByAppendingFormat:@":%u", destinationGID];
    if (![NSString isEmptyString:ugid]) {
        [installerArguments addObjects:@"-u", ugid, nil];
    }
    
    // Check for some other reasons we'll need to authenticate.
    if (NeedsAuthentication_DestDir(installationDirectory))
        authRequired = YES;
    if (NeedsAuthentication_Ownership(destinationUID, destinationGID))
        authRequired = YES;
    
    // If we want to archive the existing version, pass the -a flag
    if (pathToArchive && archivePath) {
        [installerArguments addObjects:@"-a", pathToArchive, archivePath, nil];
        
        // Even though we're just moving the old version, we'll need write permission in order to do so
        // (the UNIX reason for this is that we need access to modify the '..' entry in its directory but I'm guessing that that's just historical at this point)
        if (!authRequired && ![manager isWritableFileAtPath:pathToArchive]) {
            NSDictionary *movingAttributes = [manager attributesOfItemAtPath:pathToArchive error:NULL];
            BOOL unwritable;
            
            if (movingAttributes) {
                /* Perhaps we can make it writable, move it aside, then restore its original permissions? */
                NSUInteger oldMode = [movingAttributes filePosixPermissions];
                if ((oldMode & (S_IWUSR|S_IXUSR)) != (S_IWUSR|S_IXUSR) && [manager setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:(oldMode | (S_IWUSR|S_IXUSR))] forKey:NSFilePosixPermissions] ofItemAtPath:pathToArchive error:NULL]) {
                    [installerArguments addObjects:@"-am", [NSString stringWithFormat:@"0%o", (unsigned int)oldMode], nil];
                    unwritable = NO;
                } else
                    unwritable = YES;
            } else
                unwritable = YES;
            
            if (unwritable) {
                NSLog(@"Installed path '%@' is not writable.  Will request privileges so that we can move it aside.", pathToArchive);
                authRequired = YES;
            }
        }
    }
    
    // If the user had the immutable flag set ("locked" file) then pass -f.
    // As a side effect this will tell the script to try unlocking the old version.
    if (setImmutable) {
        [installerArguments addObjects:@"-f", @"uchg", nil];
    }
    
    NSLog(@"[%@auth] %@ %@", authRequired?@"":@"no", [installerPath lastPathComponent], [installerArguments componentsJoinedByString:@" "]);
    
    BOOL succeeded;
    
    if (authRequired)
        succeeded = PerformAuthenticatedInstall(installerPath, installerArguments, errorFile, outError);
    else
        succeeded = PerformNormalInstall(installerPath, installerArguments, errorFile, outError);
    
    // If we moved something aside, but don't want to keep it, then move it to the trash now.
    if (succeeded && archivePath && !keepExistingVersion) {
        trashFile(archivePath, @"previous version", YES);
    }
    
    return succeeded;
}

static BOOL PerformNormalInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError)
{
    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open]; // or appending to the stream will produce an error

    NSData *installerResults = [[NSData data] filterDataThroughCommandAtPath:installerPath withArguments:installerArguments includeErrorsInOutput:NO errorStream:errorStream error:outError];
    OBASSERT(!installerResults || [installerResults length] == 0); // nothing should be written to stdout, only stderr
    
    if (!installerResults) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - could not move application into place during install");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"Install script failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
            
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey,
                                             reportStringForCapturedOutput(errorStream), @"install-stderr", nil];
            
            // The script will try to write to the specified error file, but we'll look at both that and the stream, just in case.
            NSError *stringError = nil;
            NSString *errorString = [[[NSString alloc] initWithContentsOfFile:errorFile encoding:NSUTF8StringEncoding error:&stringError] autorelease];
            if (errorString)
                [userInfo setObject:errorString forKey:@"stderr"];
            
            if (installerResults && [installerResults length])
                [userInfo setObject:reportStringForCapturedOutputData(installerResults) forKey:@"stdout"];
            
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToUpgrade userInfo:userInfo];
        }
        
        return NO;
    }
    
    return YES;
}

// Returns NO to satisfy the outError convention and so caller can just "return AuthInstallError(...);
static BOOL AuthInstallError(NSError **outError, NSString *reason, NSError *underlyingError, NSString *errorFile)
{
    if (outError) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - could not move application into place during install");
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        
        [userInfo setObject:description forKey:NSLocalizedDescriptionKey];
        [userInfo setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
        
        if (underlyingError)
            [userInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
        
        if (errorFile) {
            NSError *stringError = nil;
            NSString *errorString = [[NSString alloc] initWithContentsOfFile:errorFile encoding:NSUTF8StringEncoding error:&stringError];
            if (errorString)
                [userInfo setObject:errorString forKey:@"stderr"];
            [errorString release];
        }
        
        if (underlyingError && [[underlyingError domain] isEqual:NSOSStatusErrorDomain] && [underlyingError code] == errAuthorizationCanceled) {
            /* Translate errAuthorizationCanceled into NSUserCancelledError because AppKit doesn't handle errAuthorizationCanceled appropriately */
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:userInfo];
        } else {
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToUpgrade userInfo:userInfo];
        }
    }
    return NO;
}

static NSError *mkAuthError(OSStatus errCode, NSString *function)
{
    NSDictionary *userInfo;
    if (function)
        userInfo = [NSDictionary dictionaryWithObject:function forKey:@"function"];
    else
        userInfo = nil;
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:errCode userInfo:userInfo];
}

static BOOL PerformAuthenticatedInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError)
{
    AuthorizationRef auth;
    OSStatus err;
    NSFileManager *manager = [NSFileManager defaultManager];
    
    auth = 0;
    err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagInteractionAllowed, &auth);
    if (err != errAuthorizationSuccess) {
        return AuthInstallError(outError, NSLocalizedStringFromTableInBundle(@"Failed to create authorization.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), mkAuthError(err, @"AuthorizationCreate"), nil);
    }
        
    NSUInteger argumentIndex, argumentCount = [installerArguments count];
    char **argumentCStrings = calloc(sizeof(*argumentCStrings), (argumentCount + 1)); // plus one for the terminating null
    for (argumentIndex = 0; argumentIndex < argumentCount; argumentIndex++)
        argumentCStrings[argumentIndex] = (char *)[[installerArguments objectAtIndex:argumentIndex] UTF8String];
    
    err = AuthorizationExecuteWithPrivileges(auth, [manager fileSystemRepresentationWithPath:installerPath], kAuthorizationFlagDefaults, argumentCStrings, NULL);
    
    if (err != errAuthorizationSuccess) { // errAuthorizationToolEnvironmentError if our tool itself errored out
        free(argumentCStrings);
        AuthorizationFree(auth, 0);
        return AuthInstallError(outError, NSLocalizedStringFromTableInBundle(@"Failed to execute install script with authorization.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), mkAuthError(err, @"AuthorizationExecuteWithPrivileges"), errorFile);
    }
    
    // Wait for the tool to do its thing.  Sadly we have no idea what the child process is, so the exiting child could be anything.  Hurray for iffy API design.
    int status;
    pid_t pid;
    
    do {
        pid = wait(&status);
    } while (pid < 0 && OMNI_ERRNO() == EINTR); // SIGCHLD will interrupt wait(2).
    
    free(argumentCStrings);
    AuthorizationFree(auth, 0);
    
    if (pid == -1) {
        return AuthInstallError(outError, NSLocalizedStringFromTableInBundle(@"System call wait() failed for install script.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), [NSError errorWithDomain:NSPOSIXErrorDomain code:OMNI_ERRNO() userInfo:nil], errorFile);
    } else if (WIFEXITED(status)) {
        unsigned int terminationStatus = WEXITSTATUS(status);
        if (terminationStatus != 0) {
            return AuthInstallError(outError, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Install script exited with status %d.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), terminationStatus], nil, errorFile);
        }
    } else {
        unsigned int terminationSignal = WTERMSIG(status);
        return AuthInstallError(outError, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Install script exited due to signal %d.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), terminationSignal], nil, errorFile);
    }
    
    return YES;
}

static void _terminate(int status) __attribute__((__noreturn__));
static void _terminate(int status)
{
    // I don't call -terminate: any more.  We explicitly ask NSDocumentController to shut down and don't do the install if it fails to close a document.  NSApp will do its 'deallc hard core' thing which cleans up all sorts of cruft.  In particular, 10.5 seems to have a zombie in shutting down the HTTP connection for our NSURLDownload.  Let's not crash when updating, though it would be nice to figure this out I at least want to see if this avoids the problem.
    // [NSApp terminate:nil];
    
    // We do at least need to shut down the OSUChecker so that our defaults get written correctly
    // <bug://bugs/43918> (console message about OSULastRunStartInterval default is non-nil when I use software update)
    [OSUChecker controllerWillTerminate:[OFController sharedController]];
    
    exit(status);
}

+ (void)_relaunchFromPath:(NSString *)pathString;
{
    const char *path = [pathString UTF8String];
    
    int childPipe[2];
    
    if (pipe(childPipe) < 0) {
        // out of file descriptors?
        perror("pipe");
	NSString *title = NSLocalizedStringFromTableInBundle(@"Unable to relaunch", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error title");
        NSString *message = NSLocalizedStringFromTableInBundle(@"Failed to create child pipe: %s", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error message");	
        NSString *quit = NSLocalizedStringFromTableInBundle(@"Quit", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error button");	
        NSRunAlertPanel(title, message, quit, nil, nil, strerror(OMNI_ERRNO()));
        _terminate(1);
        return;
    }

    int readFD = childPipe[0];
    int writeFD = childPipe[1];
    
    pid_t child = fork();
    if (child < 0) {
	NSString *title = NSLocalizedStringFromTableInBundle(@"Unable to relaunch", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error title");
        NSString *message = NSLocalizedStringFromTableInBundle(@"Failed to fork child process: %s", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error message");	
        NSString *quit = NSLocalizedStringFromTableInBundle(@"Quit", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error button");	
        NSRunAlertPanel(title, message, quit, nil, nil, strerror(OMNI_ERRNO()));
        _terminate(1);
        return;
    }
    
    if (child != 0) {
        // Parent
        close(readFD); // probably not necessary, but good form -- we'll never read from the pipe
        _terminate(0);
        return;
    } else {
        // Child
        
        // close our copy of the write end of the pipe; otherwise our select below will never signal that the read end is dead.
        close(writeFD);
        
        // wait for the parent to die; when it does, our end of the pipe will die.
        while (1) {
            fd_set readfds, errorfds;
            
            FD_ZERO(&readfds);
            FD_ZERO(&errorfds);
            
            FD_SET(readFD, &readfds);
            FD_SET(readFD, &errorfds);
            
            struct timeval timeout = (struct timeval){.tv_sec = 2, .tv_usec = 0};
            int rc = select(readFD+1, &readfds, NULL, &errorfds, &timeout);
            if (rc == 1) {
                execl("/usr/bin/open", "/usr/bin/open", path, NULL);
                perror("execl");
                _exit(1);
            } else {
#ifdef DEBUG // stdio usage here is bad; after fork but before exec.
                fprintf(stderr, "select -> %d, errno = %d\n", rc, OMNI_ERRNO());
#endif
            }
        }
    }
}

// This will return an NSData instead of a string if the captured output doesn't look stringy enough --- it's just going into a plist.
static id reportStringForCapturedOutput(NSOutputStream *errorStream)
{
    if (!errorStream)
        return @"<no stream>";
    
    NSData *data = [errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    if (!data)
        return @"";  // RADAR 6160521
    
    return reportStringForCapturedOutputData(data);
}
static id reportStringForCapturedOutputData(NSData *data)
{
    if (!data)
        return @"<no data>";
    
    NSString *string = [NSString stringWithData:data encoding:NSUTF8StringEncoding];
    if (string == nil) {
        string = [NSString stringWithData:data encoding:NSMacOSRomanStringEncoding];
        if (string == nil)
            return data;
    }
    return string;
}

static BOOL trashFile(NSString *path, NSString *description, BOOL tryFinder)
{
    NSInteger tag;
    
    NSString *basename = [path lastPathComponent];
    NSString *dirname = [path stringByDeletingLastPathComponent];
    
    if (![[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:dirname destination:@"" files:[NSArray arrayWithObject:basename] tag:&tag]) {
#ifdef DEBUG	
        NSLog(@"Error moving %@ '%@' from '%@' to the trash.", description, basename, dirname);
#endif	    
        
        if (!tryFinder)
            return NO;
        
        /* We can message the Finder to move something to the trash for us. It will authenticate if it thinks that'll help. But if know we're already going to authenticate, we skip that step so the user doesn't have to deal with more authentication dialogs than needed. */
        
        if (![[NSFileManager defaultManager] deleteFileUsingFinder:path]) {
            NSLog(@"Error moving %@ from '%@' to the trash.", description, path);
            return NO;
        } else {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                NSLog(@"Failed to move %@ from '%@' to the trash.", description, path);
                return NO;
            }
            return YES;
        }
    } else {
        return YES; // Success.
    }
}

@end
