// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUInstaller.h"

#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/OFController.h>
#import <OmniAppKit/NSFileManager-OAExtensions.h>
#import <Security/Security.h>

#import "OSUChecker.h"
#import "OSUErrors.h"
#import <unistd.h>

RCS_ID("$Id$");

@interface OSUInstaller (Private)
// Disk image support
+ (NSString *)_unpackedPathFromDiskImage:(NSString *)diskImagePath existingVersionPath:(NSString *)existingVersionPath statusBindingPoint:(OFBindingPoint)statusBindingPoint error:(NSError **)outError;
+ (NSString *)_mountDiskImage:(NSString *)diskImagePath error:(NSError **)outError;
+ (void)_unmountDiskImage:(NSString *)mountPoint;
+ (NSString *)_unpackApplicationFromMountPoint:(NSString *)mountPoint intoTemporaryLocationForCopyingTo:(NSString *)existingVersionPath error:(NSError **)outError;
// tar/bz2 support
+ (NSString *)_unpackApplicationFromTarBzip2File:(NSString *)diskImagePath existingVersionPath:(NSString *)existingVersionPath statusBindingPoint:(OFBindingPoint)statusBindingPoint error:(NSError **)outError;
// Install & Relaunch
+ (BOOL)_installPath:(NSString *)sourcePath destinationPath:(NSString *)destinationPath archivePath:(NSString *)archivePath error:(NSError **)outError;
+ (void)_relaunchFromPath:(NSString *)pathString;
+ (NSString *)_reportStringForData:(NSData *)data;

@end

@implementation OSUInstaller

+ (NSArray *)supportedPackageFormats;
{
    static NSArray *SupportedPackageFormats = nil;
    
    if (!SupportedPackageFormats)
        SupportedPackageFormats = [[NSArray alloc] initWithObjects:@"tbz2", @"dmg", nil];
    return SupportedPackageFormats;
}

+ (NSString *)preferredPackageFormat;
{
    static NSString *PreferredPackageFormat = nil;

    // This is lame, but we really don't *want* mulitple format support; we are just transitioning from dmg to tbz2.
    PreferredPackageFormat = [[[NSUserDefaults standardUserDefaults] stringForKey:@"OSUPreferredPackageFormat"] copy];
    if (!PreferredPackageFormat)
        PreferredPackageFormat = @"tbz2";
    OBASSERT([[self supportedPackageFormats] containsObject:PreferredPackageFormat]);
    
    return PreferredPackageFormat;
}


static void _setStatus(OFBindingPoint statusBindingPoint, NSString *status)
{
    id object = statusBindingPoint.object;
    [object setValue:status forKeyPath:statusBindingPoint.keyPath];
    
    if ([object respondsToSelector:@selector(window)])
        [[object window] displayIfNeeded];
}
#define UPDATE_STATUS(status) _setStatus(statusBindingPoint, (status))

+ (BOOL)installAndRelaunchFromPackage:(NSString *)packagePath
               archiveExistingVersion:(BOOL)archiveExistingVersion
             deleteDiskImageOnSuccess:(BOOL)deleteDiskImageOnSuccess
                   statusBindingPoint:(OFBindingPoint)statusBindingPoint
                                error:(NSError **)outError;
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *existingVersionPath = [[[NSBundle mainBundle] bundlePath] stringByExpandingTildeInPath];
#ifdef DEBUG    
    NSLog(@"Replacing '%@' with contents of '%@'...", existingVersionPath, packagePath);
#endif    
    
    NSString *unpackedPath;
    NSString *packageExtension = [packagePath pathExtension];

    if ([packageExtension isEqualToString:@"dmg"]) {
        unpackedPath = [self _unpackedPathFromDiskImage:packagePath existingVersionPath:existingVersionPath statusBindingPoint:statusBindingPoint error:outError];
    } else if ([packageExtension isEqualToString:@"tbz2"]) {
        unpackedPath = [self _unpackApplicationFromTarBzip2File:packagePath existingVersionPath:existingVersionPath statusBindingPoint:statusBindingPoint error:outError];
    } else {
        OSUError(outError, OSUUnableToUpgrade, @"Unable to open package.", @"Unknown package type.");
        return NO;
    }
    
    if (!unpackedPath)
        return NO;
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Installing...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    
    // Read information about our bundle version and build a new name for any possible archived version.
    NSString *archivePath = nil;
    {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];

        // TODO: We could try to include the marketing version, but if they user *already* included it when the originally downloaded the app, they could get 'OmniFocus 1.0 1.0.app'.  Of course, if the app wrapper has been renamed, then the *new* app will be misnamed too (if they update from "Foo 1.0" to "Foo" v2.0, they'll have an app called 'Foo 1.0' that is actually 2.0.  We could maybe detect if the app isn't named what it is expected to be named (based on the existing app's name and the updating apps' name) and rename stuff differently.  Needs more thought on all the cases.
        //NSString *marketingVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
        
        NSString *bundleVersion = [infoDictionary objectForKey:(NSString *)kCFBundleVersionKey];
        
        if (![NSString isEmptyString:bundleVersion])
            archivePath = [[[existingVersionPath stringByDeletingPathExtension] stringByAppendingFormat:@" %@", bundleVersion] stringByAppendingPathExtension:[existingVersionPath pathExtension]];

        archivePath = [manager uniqueFilenameFromName:archivePath allowOriginal:YES create:NO error:outError];
        if (!archivePath)
            return NO;
    }
    
    if (![self _installPath:unpackedPath destinationPath:existingVersionPath archivePath:archivePath error:outError])
        return NO;
    
    if (deleteDiskImageOnSuccess) {
        // The install portion is done; we can torch the dmg now.  Put it in the trash instead of deleting it forever.
        NSInteger tag;
        if (![[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[packagePath stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[packagePath lastPathComponent]] tag:&tag]) {
#ifdef DEBUG	
            NSLog(@"Error moving package from '%@' to the trash.", packagePath);
#endif	    
	}
    }
    
    if (!archiveExistingVersion) {
        // Delete the old version
        NSInteger tag;
        if (![[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[archivePath stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[archivePath lastPathComponent]] tag:&tag]) {
#ifdef DEBUG	
            NSLog(@"Error moving previous version from '%@' to the trash.", archivePath);
#endif	    
            if (![[NSFileManager defaultManager] deleteFileUsingFinder:archivePath]) {
                NSLog(@"Error moving previous version from '%@' to the trash.", archivePath);
            }
	}
    }
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Restarting...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    [self _relaunchFromPath:existingVersionPath];
    
    // We shouldn't get here.
    OBASSERT_NOT_REACHED("We should have relaunched!");
    exit(1);
    return YES;
}

@end

@implementation OSUInstaller (Private)

#pragma mark -
#pragma mark Disk image support

+ (NSString *)_unpackedPathFromDiskImage:(NSString *)diskImagePath existingVersionPath:(NSString *)existingVersionPath statusBindingPoint:(OFBindingPoint)statusBindingPoint error:(NSError **)outError;
{
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Mounting disk image...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    NSString *mountPoint = [self _mountDiskImage:diskImagePath error:outError];
    if (!mountPoint)
        return NO;
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Extracting updated application...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    NSString *unpackedPath = [self _unpackApplicationFromMountPoint:mountPoint intoTemporaryLocationForCopyingTo:existingVersionPath error:outError];
    
    // The disk image is unneeded now; unmount even if there was an error unpacking it.
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Unmounting disk image...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    [self _unmountDiskImage:mountPoint];
    
    return unpackedPath;
}

+ (NSString *)_mountDiskImage:(NSString *)diskImagePath error:(NSError **)outError;
{
    // hdituil emits the plist and the EULA on stdout.  Clever.  Luckily, it only puts the EULA through the PAGER, so we'll deep six that part.  It would be nicer if the data filtering method had an environment dictionary, but no one is likely to care what an app's PAGER is.  Still...
    // (RADAR 4708028, not that Apple's likely to fix it.)
    setenv("PAGER", "/bin/cat /dev/null", 1);
    
    *outError = nil;
    
    // We still have to agree to the EULA.  Terrible.
#warning Does the answer to the EULA agreement need to be localized?    
    NSData *yesData = [@"y\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open]; // or appending to the stream will produce an error
    
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

    NSData *hdiResults = [yesData filterDataThroughCommandAtPath:@"/usr/bin/hdiutil" withArguments:arguments includeErrorsInOutput:NO errorStream:errorStream error:outError];
    
    // filterDataThroughCommandAtPath:... will return an empty data in some cases -- once we figure out what that is, we should fix it.
    if (hdiResults == nil || [hdiResults length] == 0) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"hdiutil failed to attach the disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]], @"hdiutil-stderr", nil];
        
        if (hdiResults)
            [userInfo setObject:hdiResults forKey:@"hdi-result-data"];
        OBASSERT(*outError != nil);
        if (*outError)
            [userInfo setObject:*outError forKey:NSUnderlyingErrorKey];
        
        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToMountDiskImage userInfo:userInfo];

        return nil;
    }
    
    NSString *plistError = nil;
    NSDictionary *plist = [NSPropertyListSerialization propertyListFromData:hdiResults mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&plistError];
    
    if (!plist && plistError) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to parse the response from hdiutil: %@", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), plistError];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, hdiResults, @"hdi-result-data", [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]], @"hdiutil-stderr", nil];
        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToMountDiskImage userInfo:userInfo];
        return nil;
    }

    NSArray *entities = [plist objectForKey:@"system-entities"];
    
    // There can be multiple entries in entities; and the order isn't well defined.
    NSString *mountPoint = nil;
    unsigned int entityIndex, entityCount = [entities count];
    for (entityIndex = 0; entityIndex < entityCount; entityIndex++) {
        NSDictionary *entity = [entities objectAtIndex:entityIndex];
        NSString *potentialMountPoint = [entity objectForKey:@"mount-point"];
        if (potentialMountPoint) {
            if (mountPoint && ![mountPoint isEqualToString:potentialMountPoint]) { // Never seen a case where they are equal, just checking.
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Multiple mount points found in hdiutil results.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), plistError];
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, plist, @"hdi-result-plist", [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]], @"hdiutil-stderr", nil];
                *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToMountDiskImage userInfo:userInfo];
                return nil;
            } else
                mountPoint = potentialMountPoint;
        }
    }

    if (mountPoint == nil) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to mount disk image", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No mount point found in hdiutil results.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), plistError];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, plist, @"hdi-result-plist", [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]], @"hdiutil-stderr", nil];
        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToMountDiskImage userInfo:userInfo];
        return nil;
    }
    
    return mountPoint;
}

+ (void)_unmountDiskImage:(NSString *)mountPoint;
{
    NSLog(@"Unmounting '%@'", mountPoint);
    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"detach", @"-force", @"-quiet", mountPoint, nil]];
}

+ (NSString *)_unpackApplicationFromMountPoint:(NSString *)mountPoint intoTemporaryLocationForCopyingTo:(NSString *)existingVersionPath error:(NSError **)outError;
{
    NSString *extractPath = [OMNI_BUNDLE pathForResource:@"OSUExtract" ofType:@"rb"];
    if (!extractPath) {
	NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Unable to find extract script.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        OSUError(outError, OSUUnableToUpgrade, description, reason);
        return NO;
    }
    
    NSString *temporaryPath = [[NSFileManager defaultManager] temporaryPathForWritingToPath:existingVersionPath allowOriginalDirectory:YES create:NO error:outError];
    if (!temporaryPath)
        return nil;
    
    NSArray *arguments = [NSArray arrayWithObjects:@"--mount-point", mountPoint, @"--temporary-path", temporaryPath, nil];

    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open]; // or appending to the stream will produce an error

    NSData *extractResults = [[NSData data] filterDataThroughCommandAtPath:extractPath withArguments:arguments includeErrorsInOutput:NO errorStream:errorStream error:outError];
    OBASSERT(!extractResults || [extractResults length] == 0); // nothing should be written to stdout, only stderr
#if 1 && defined(DEBUG_bungi)
    NSLog(@"Extract:\n%@", [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]]);
#endif
    
    if (!extractResults) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Extract script failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey,
            [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]], @"extract-stderr", nil];
        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToUpgrade userInfo:userInfo];
        return nil;
    }
    
    return temporaryPath;
}

#pragma mark -
#pragma mark tar/bz2 support

+ (NSString *)_unpackApplicationFromTarBzip2File:(NSString *)bzip2File existingVersionPath:(NSString *)existingVersionPath statusBindingPoint:(OFBindingPoint)statusBindingPoint error:(NSError **)outError;
{
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Decompressing...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    
    // Create a temporary directory into which to unpack
    NSString *temporaryPath = [[NSFileManager defaultManager] temporaryPathForWritingToPath:existingVersionPath allowOriginalDirectory:YES create:NO error:outError];
    if (!temporaryPath)
        return nil;
    
    NSFileManager *manager = [NSFileManager defaultManager];
    
    if (![manager createDirectoryAtPath:temporaryPath withIntermediateDirectories:YES attributes:nil error:outError]) {
        NSString *reason = [NSString stringWithFormat:@"Could not create temporary directory at '%@'.", temporaryPath];
        OSUError(outError, OSUUnableToUpgrade, @"Unable to install update.", reason);
        return nil;
    }
    
    NSString *extractPath = [OMNI_BUNDLE pathForResource:@"OSUExtract-tbz2" ofType:@"sh"];
    if (!extractPath) {
        OSUError(outError, OSUUnableToUpgrade, @"Unable to install update", @"Unable to find extract script.");
        return NO;
    }
    
    NSArray *arguments = [NSArray arrayWithObjects:bzip2File, temporaryPath, nil];
    
    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open]; // or appending to the stream will produce an error
    
    NSData *extractResults = [[NSData data] filterDataThroughCommandAtPath:extractPath withArguments:arguments includeErrorsInOutput:NO errorStream:errorStream error:outError];
    OBASSERT(!extractResults || [extractResults length] == 0); // nothing should be written to stdout, only stderr
#if 1 && defined(DEBUG_bungi)
    NSLog(@"Extract:\n%@", [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]]);
#endif
    
    if (!extractResults) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Extract script failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey,
            [self _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]], @"extract-stderr", nil];
        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToUpgrade userInfo:userInfo];
        return nil;
    }
    
    // Look for a single .app directory inside the unpacked path; this is what we are to return.
    NSError *subError = nil;
    NSArray *applications = [manager directoryContentsAtPath:temporaryPath havingExtension:@"app" error:&subError];
    if ([applications count] != 1) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Expected to find exactly one application, but found %d.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), [applications count]];
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
        if (!applications && subError)
            [userInfo setObject:subError forKey:NSUnderlyingErrorKey];
        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToUpgrade userInfo:userInfo];
        return nil;
    }
    
    return [temporaryPath stringByAppendingPathComponent:[applications lastObject]];
}

#pragma mark -
#pragma mark Install & Relaunch

static BOOL NeedsAuthentication(NSString *path, uid_t pathUID, gid_t pathGID)
{
    uid_t runningUID = getuid();
    gid_t runningGID = getgid();
    
    if (pathUID != runningUID) {
        NSLog(@"Running user has uid %d while installed application '%@' has owner id %d.  Will perform authenticated installation.", runningUID, path, pathUID);
        return YES;
    }
    
    if (pathGID != runningGID) {
        
        // Directories with the sticky bit set, like /Applications, can result in installed applications having one of our supplementary GIDs.
        BOOL groupMatch = NO;
        gid_t otherGIDs[NGROUPS_MAX];
        int ngroups = getgroups(NGROUPS_MAX, otherGIDs);
        if (ngroups > 0) {
            int groupindex;
            for(groupindex = 0; groupindex < ngroups; groupindex ++) {
                if (pathGID == otherGIDs[groupindex]) {
                    groupMatch = YES;
                    break;
                }
            }
        }
        
        if (!groupMatch) {
            NSLog(@"Running user has gid %d while installed application '%@' has group id %d.  Will perform authenticated installation.", runningGID, path, pathGID);
            return YES;
        }
        
        NSLog(@"Installed application has group id %d, which is in running user's supplementary groups list.", pathGID);
    }
    
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager isWritableFileAtPath:path]) {
        NSLog(@"Installed path '%@' is not writable.  Will perform authenticated installation.", path);
        return YES;
    }
    
    NSString *installationDirectory = [path stringByDeletingLastPathComponent];
    if (![manager isWritableFileAtPath:installationDirectory]) {
        NSLog(@"Installation folder '%@' is not writable.  Will perform authenticated installation.", installationDirectory);
        return YES;
    }
    
    return NO;
}

static BOOL PerformNormalInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError);
static BOOL PerformAuthenticatedInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError);

+ (BOOL)_installPath:(NSString *)sourcePath destinationPath:(NSString *)destinationPath archivePath:(NSString *)archivePath error:(NSError **)outError;
{
    OBPRECONDITION(sourcePath);
    OBPRECONDITION(destinationPath);
    OBPRECONDITION(archivePath);
    
    NSString *installerPath = [OMNI_BUNDLE pathForResource:@"OSUInstaller" ofType:@"sh"];
    if (!installerPath) {
	NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Cannot find the installer script.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        OSUError(outError, OSUUnableToUpgrade, description, reason);
        return NO;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *destinationAttributes = [manager attributesOfItemAtPath:destinationPath error:outError];
    if (!destinationAttributes)
	return NO;
    
    uid_t destinationUID = [[destinationAttributes objectForKey:NSFileOwnerAccountID] unsignedIntValue];
    gid_t destinationGID = [[destinationAttributes objectForKey:NSFileGroupOwnerAccountID] unsignedIntValue];
    
    // The authorization framework gives stdin/stdout if we ask, but we want stderr.  So, the installer script takes the name of a file to write its errors to.
    NSString *errorFile = [manager temporaryPathForWritingToPath:@"/tmp/OSUInstallerLog" allowOriginalDirectory:YES create:NO error:outError];
    if (!errorFile)
        return NO;
    
    NSArray *installerArguments = [NSArray arrayWithObjects:sourcePath, destinationPath, archivePath, errorFile, nil];

    if (NeedsAuthentication(destinationPath, destinationUID, destinationGID))
        return PerformAuthenticatedInstall(installerPath, installerArguments, errorFile, outError);
    else
        return PerformNormalInstall(installerPath, installerArguments, errorFile, outError);
}

static BOOL PerformNormalInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError)
{
    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open]; // or appending to the stream will produce an error

    NSData *installerResults = [[NSData data] filterDataThroughCommandAtPath:installerPath withArguments:installerArguments includeErrorsInOutput:NO errorStream:errorStream error:outError];
    OBASSERT(!installerResults || [installerResults length] == 0); // nothing should be written to stdout, only stderr
    
    if (!installerResults) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Install script failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");

        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey,
            [OSUInstaller _reportStringForData:[errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey]], @"install-stderr", nil];

        // The script will try to write to the specified error file, but we'll look at both that and the stream, just in case.
        NSError *stringError = nil;
        NSString *errorString = [[[NSString alloc] initWithContentsOfFile:errorFile encoding:NSUTF8StringEncoding error:&stringError] autorelease];
        if (errorString)
            [userInfo setObject:errorString forKey:@"stderr"];

        *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToUpgrade userInfo:userInfo];
        return NO;
    }
    
    return YES;
}

static void AuthInstallError(NSError **outError, NSString *reason, NSError *underlyingError, NSString *errorFile)
{
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
    
    if (underlyingError)
        [userInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
    
    NSError *stringError = nil;
    NSString *errorString = [[[NSString alloc] initWithContentsOfFile:errorFile encoding:NSUTF8StringEncoding error:&stringError] autorelease];
    if (errorString)
        [userInfo setObject:errorString forKey:@"stderr"];
    *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToUpgrade userInfo:userInfo];
}

static BOOL PerformAuthenticatedInstall(NSString *installerPath, NSArray *installerArguments, NSString *errorFile, NSError **outError)
{
    AuthorizationRef auth;
    OSStatus err;
    
    err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (err != errAuthorizationSuccess) {
        AuthInstallError(outError, NSLocalizedStringFromTableInBundle(@"Failed to created authorization.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil], nil);
        return NO;
    }
    
    unsigned int argumentIndex, argumentCount = [installerArguments count];
    char **argumentCStrings = calloc(sizeof(*argumentCStrings), (argumentCount + 1)); // plus one for the terminating null
    for (argumentIndex = 0; argumentIndex < argumentCount; argumentIndex++)
        argumentCStrings[argumentIndex] = (char *)[[installerArguments objectAtIndex:argumentIndex] UTF8String];
    
    NSFileManager *manager = [NSFileManager defaultManager];
    
    err = AuthorizationExecuteWithPrivileges(auth, [manager fileSystemRepresentationWithPath:installerPath], kAuthorizationFlagDefaults, argumentCStrings, NULL);
    
    if (err != errAuthorizationSuccess) { // errAuthorizationToolEnvironmentError if our tool itself errored out
        free(argumentCStrings);
        AuthorizationFree(auth, 0);
        AuthInstallError(outError, NSLocalizedStringFromTableInBundle(@"Failed to execute install script with authorization.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil], errorFile);
        return NO;
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
        AuthInstallError(outError, NSLocalizedStringFromTableInBundle(@"System call wait() failed for install script.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), [NSError errorWithDomain:NSPOSIXErrorDomain code:OMNI_ERRNO() userInfo:nil], errorFile);
        return NO;
    } else if (WIFEXITED(status)) {
        unsigned int terminationStatus = WEXITSTATUS(status);
        if (terminationStatus != 0) {
            AuthInstallError(outError, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Install script exited with status %d.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), terminationStatus], nil, errorFile);
            return NO;
        }
    } else {
        unsigned int terminationSignal = WTERMSIG(status);
        AuthInstallError(outError, [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Install script exited due to signal %d.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), terminationSignal], nil, errorFile);
        return NO;
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
                rc = execl("/usr/bin/open", "/usr/bin/open", path, NULL);
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

+ (NSString *)_reportStringForData:(NSData *)data;
{
    NSString *string = [NSString stringWithData:data encoding:NSUTF8StringEncoding];
    if (string == nil) {
        string = [NSString stringWithData:data encoding:NSMacOSRomanStringEncoding];
        if (string == nil)
            string = [data description];
    }
    return string;
}

@end
