// Copyright 2007-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUInstaller.h"

@import OmniBase;
@import OmniFoundation;
@import OmniAppKit;
@import AppKit;
@import Darwin;

#import <OmniSoftwareUpdate/OSUChecker.h>
#import "OSUErrors.h"
#import "OSUChooseLocationErrorRecovery.h"
#import "OSUInstallerServiceProtocol.h"
#import "OSUSendFeedbackErrorRecovery.h"

RCS_ID("$Id$");

static BOOL OSUInstallerHasReceivedApplicationWillTerminate;

@interface OSUInstaller () <OFControllerStatusObserver> {
  @private
    __weak id <OSUInstallerDelegate> _weak_delegate;

    NSString *_packagePath;             // The path to the downloaded package
    NSString *_installedVersionPath;    // The path to the installed copy we're replacing
    NSString *_installationDirectory;   // The path to the directory we'll install to (usually derived from existingVersionPath)
    NSString *_installationName;        // The name (within installationDirectory) of the version we're installing

    // These are set up as the installer does its thing
    NSString *_unpackedPath;            // Unpacked copy of the new application, on same filesystem as eventual destination
    BOOL _hasAskedForInstallLocation;   // Have we already asked for an installation location?
    
    // XPC Service connection
    NSXPCConnection *_connection;
    struct {
        NSUInteger invalid:1;
        NSUInteger interrupted:1;
    } _connectionFlags;
    
    // Termination observer
    id _terminationObserver;
}

@property (nonatomic, copy) NSData *authorizationData;

// XPC
@property (nonatomic, readonly) NSXPCConnection *connection;

// Termination
@property (nonatomic, retain) id terminationObserver;

// General
- (BOOL)extract:(NSError **)outError;
- (BOOL)installAndRelaunch:(BOOL)shouldRelaunch error:(NSError **)outError;
- (NSString *)_findApplicationInDirectory:(NSString *)dir error:(NSError **)outError;

// Error presentation/recovery callback
- (void)_retry:(BOOL)recovered context:(void *)p;

// tar/bz2 support
- (BOOL)_unpackApplicationFromTarFile:(NSError **)outError;

// Install & Relaunch
- (BOOL)_installUpdate:(NSError **)outError;
- (void)_relaunchFromPath:(NSString *)pathString;

@end

static void _reportError(NSError *error, NSString *titleString, NSString *defaultButtonTitle, NSString *alternateButtonTitle, NSString *otherButtonTitle, CFOptionFlags *responseFlags);
static void _terminate(int status) __attribute__((__noreturn__));

static id _reportStringForCapturedOutputData(NSData *errorStreamData);
static BOOL _isApplicationSuperficiallyValid(NSString *path, NSError **outError);

#pragma mark -

@implementation OSUInstaller

+ (void)initialize;
{
    OBINITIALIZE;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
}

+ (void)applicationWillTerminate:(NSNotification *)notification;
{
    OSUInstallerHasReceivedApplicationWillTerminate = YES;
}

+ (NSArray *)supportedPackageFormats;
{
    static NSArray *SupportedPackageFormats = nil;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // This is the list of formats we actually know how to handle
        NSMutableArray *supportedFormats = [[NSMutableArray alloc] initWithObjects:@"tar.bz2", @"tbz2", @"tar.gz", @"tgz", nil];
        
        // Allow the user to change the preference ordering, for testing
        NSArray *preferredFormats = nil;
        id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"OSUPreferredPackageFormat"];
        
        if (value && [value isKindOfClass:[NSString class]]) {
            preferredFormats = [NSArray arrayWithObject:value];
        } else if (value && [value isKindOfClass:[NSArray class]]) {
            preferredFormats = value;
        }

        if (preferredFormats != nil) {
            [supportedFormats sortBasedOnOrderInArray:preferredFormats identical:NO unknownAtFront:NO];
        }
        
        SupportedPackageFormats = [supportedFormats copy];
    });

    return SupportedPackageFormats;
}

#define UPDATE_STATUS(status) \
    do { \
        id <OSUInstallerDelegate> delegate = self.delegate; \
        [delegate setStatus:(status)]; \
    } \
    while (0)

- (id)initWithPackagePath:(NSString *)newPackage
{
    if (!(self = [super init]))
        return nil;
    
    _packagePath = [newPackage copy];
    _installedVersionPath = nil;
    _installationDirectory = nil;
    _installationName = nil;
    
    _hasAskedForInstallLocation = NO;

    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_terminationObserver == nil);
    
    [_connection invalidate];

    if (_terminationObserver)
        [[NSNotificationCenter defaultCenter] removeObserver:_terminationObserver];
    
    [[OFController sharedController] removeStatusObserver:self];
}

@synthesize delegate = _weak_delegate;
@synthesize installationDirectory = _installationDirectory;

- (NSString *)installedVersionPath;
{
    return _installedVersionPath;
}

- (void)setInstalledVersionPath:(NSString *)path;
{
    if (path != _installedVersionPath) {
        _installedVersionPath = [path copy];
    }
    
    if ([[[_installedVersionPath lastPathComponent] pathExtension] isEqualToString:@"app"]) {
        [self setInstallationDirectory:[_installedVersionPath stringByDeletingLastPathComponent]];
    }
}

- (void)run
{
    // The caller should have ensured that the installation directory is on a valid filesystem.
    // Let's double check here.

    OBPRECONDITION([[self class] validateTargetFilesystem:_installationDirectory error:NULL]);

    // Extract the update
    
    __autoreleasing NSError *extractError = nil;
    if (![self extract:&extractError]) {
        if ([[extractError domain] isEqualToString:OSUErrorDomain] && [extractError code] == OSUBadInstallationDirectory && !_hasAskedForInstallLocation) {
            if ([self chooseInstallationDirectory:nil]) {
                OBASSERT(_hasAskedForInstallLocation);
                [self run];
                return;
            } else {
                if (_hasAskedForInstallLocation) {
                    // Handle this like any other failed recovery attempt.
                    // (Reveal the package in the Finder, close the progress window, and leave the application running).
                    //
                    // self is released in the _retry handler.
                    OBStrongRetain(self);
                    [self _retry:NO context:NULL];
                    return;
                }

                // Fall through to the normal error presentation code, below.
            }
        }
        
        if ([extractError recoveryAttempter] == nil) {
            extractError = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:extractError object:self options:[OSUChooseLocationErrorRecovery class], [OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
        }
        
        [self _presentError:extractError];
        return;
    }
    
    // Preflight any Authorization Rights we'll need to install/update the privileged helper tool, and install the update

    NSXPCConnection *connection = self.connection;
    id <OSUInstallerService> remoteObjectProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        [self _presentError:error];
        return;
    }];
    
    // Avoid zombie -- stay alive until the work below is done.
    OBStrongRetain(self);

    NSDictionary *installerArguments = [self _installerArguments];
    [remoteObjectProxy preflightUpdate:installerArguments reply:^(BOOL success, NSError *preflightError, NSData *authorizationData) {
        if (!success) {
            [self _presentError:preflightError];
            OBStrongRelease(self);
            return;
        } else {
            // Hold on to the authorization data that the service passed back to us.
            self.authorizationData = authorizationData;

            // Ask NSApplication to terminate. During the termination sequence, replace ourselves and relaunch
            void (^willTerminate)(NSNotification *notification) = ^(NSNotification *notification){
                [[OFController sharedController] removeStatusObserver:self];
                [[NSNotificationCenter defaultCenter] removeObserver:_terminationObserver];
                self.terminationObserver = nil;
                
                __autoreleasing NSError *error = nil;
                if (![self installAndRelaunch:YES error:&error]) {
                    // We are already in the termination sequence here.
                    // We cannot run a modal panel, or recover from an error. The best we can do is report it and terminate.
                    // The upside is that we should have preflighted for recoverable things before attempting the installation, so everything here should truly be non-recoverable.
                    
                    // We cannot run modal session during application termination; use CFUserNotification instead
                    NSString *format = NSLocalizedStringFromTableInBundle(@"Unable to Install %@", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error format string");
                    NSString *title = [NSString stringWithFormat:format, [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey]];
                    NSString *defaultButton = OAOK();
                    NSString *otherButton = [OSUSendFeedbackErrorRecovery defaultLocalizedRecoveryOption];
                    CFOptionFlags responseFlags = 0;
                    
                    NSLog(@"Error communicating with the OSUInstaller XPC service: %@", error);
                    _reportError(error, title, defaultButton, nil, otherButton, &responseFlags);
                    
                    if (responseFlags == kCFUserNotificationOtherResponse) {
                        OSUSendFeedbackErrorRecovery *recovery = [[OSUSendFeedbackErrorRecovery alloc] initWithLocalizedRecoveryOption:nil object:nil];
                        [recovery attemptRecoveryFromError:error];
                    }
                    
                    _terminate(1);
                }
                
                // We won't normally reach here
                OBASSERT_NOT_REACHED("Should not be able to reach the end of the termination handler in -[OSUInstaller run].");
            };

            UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Waiting to Install\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));

            OBASSERT(self.terminationObserver == nil);
            if (self.terminationObserver == nil) {
                [[OFController sharedController] addStatusObserver:self];
                self.terminationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:willTerminate];
            }
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [[NSProcessInfo processInfo] disableSuddenTermination];
                
                // Termination may run a modal event loop, so we need to perform-delay it; running it from within a dispatch block may cause a hang.
                [[NSApplication sharedApplication] performSelector:@selector(terminate:) withObject:nil afterDelay:0];
            }];
        }
    }];
}

- (BOOL)extract:(NSError **)outError;
{
    BOOL isDirectory = NO;
    if (_unpackedPath && [[NSFileManager defaultManager] fileExistsAtPath:_unpackedPath isDirectory:&isDirectory] && isDirectory) {
        // We could reach here depending on error recovery
        NSLog(@"Unpacked file already exists at %@, skipping extract step", _unpackedPath);
        return YES;
    }
    
    if (![[self class] validateTargetFilesystem:_installationDirectory error:outError]) {
        return NO;
    }
    
    if ([_packagePath hasSuffix:@".tbz2"] || [_packagePath hasSuffix:@".tar.bz2"] || [_packagePath hasSuffix:@".tgz"] || [_packagePath hasSuffix:@".tar.gz"]) {
        return [self _unpackApplicationFromTarFile:outError];
    } else {
        OSUError(outError, OSUUnableToProcessPackage, @"Unable to open package.", @"Unknown package type.");
        return NO;
    }
}

- (BOOL)installAndRelaunch:(BOOL)shouldRelaunch error:(NSError **)outError;
{    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Installing\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));

    OBPRECONDITION(![NSString isEmptyString:_installationName]);
    OBPRECONDITION(![NSString isEmptyString:_packagePath]);
    
    if (![self _installUpdate:outError])
        return NO;
    
    // The install portion is done; we can torch the downloaded package now.  Put it in the trash instead of deleting it forever, if possible.
    // We downloaded the package, so we should be able to trash it (if the volume has a trash can), or delete it, without concern for permission issues.
    __autoreleasing NSError *error = nil;
    NSURL *packageURL = [NSURL fileURLWithPath:_packagePath];
    if (![[NSFileManager defaultManager] trashItemAtURL:packageURL resultingItemURL:NULL error:&error]) {
        // The error will be NSCocoaErrorDomain/NSFeatureUnsupportedError if the volume doesn't have a trash can.
        if (![[NSFileManager defaultManager] removeItemAtURL:packageURL error:&error]) {
            NSLog(@"Error trying to remove package at path: %@", [packageURL path]);
        }
    }

    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Restarting\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description - when quitting this application in order to finish upgrading")));

    [self _relaunchFromPath:[_installationDirectory stringByAppendingPathComponent:_installationName]];

    // -_relaunchFromPath will return immediately.
    // It will initiate termination when it has received a response from the XPC installer service, or there was a communication error.
    
    return YES;
}

#pragma mark -
#pragma mark XPC

- (NSXPCConnection *)connection;
{
    if (_connection == nil) {
        _connectionFlags.invalid = NO;
        _connectionFlags.interrupted = NO;
        _connection = [[NSXPCConnection alloc] initWithServiceName:@"com.omnigroup.OmniSoftwareUpdate.OSUInstallerService"];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUInstallerService)];

        __weak typeof(self) weakSelf = self;
        _connection.interruptionHandler = ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_connectionFlags.interrupted = YES;
                [strongSelf->_connection invalidate];
                strongSelf->_connection = nil;
            }
        };

        _connection.invalidationHandler = ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_connectionFlags.invalid = YES;
                strongSelf->_connection = nil;
            }
        };
        
        [_connection resume];
    }
    
    return _connection;
}

#pragma mark -
#pragma mark Installation Location

+ (NSString *)suggestAnotherInstallationDirectory:(NSString *)lastAttemptedPath trySelf:(BOOL)checkOwnDirectory;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Replace the currently installed copy if it is on a writeable filesystem.
    // (This operation may eventually require elevated privileges.)
    if (checkOwnDirectory) {
        NSString *installedVersionDirectoryPath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
        if (![NSString isEmptyString:installedVersionDirectoryPath]) {
            if (!(![NSString isEmptyString:lastAttemptedPath] && [installedVersionDirectoryPath hasPrefix:lastAttemptedPath]) && [self validateTargetFilesystem:installedVersionDirectoryPath error:NULL]) {
                return installedVersionDirectoryPath;
            }
        }
    }
    
    // Suggest /Applications if that filesystem is writeable.
    NSURL *applicationsDirectoryURL = [[fileManager URLsForDirectory:NSApplicationDirectory inDomains:NSLocalDomainMask] lastObject];
    NSString *applicationsDirectory = [applicationsDirectoryURL path];
    if (![lastAttemptedPath isEqualToString:applicationsDirectory] && [self validateTargetFilesystem:[applicationsDirectoryURL path] error:NULL]) {
        return applicationsDirectory;
    }
    
    // We have no suitable place to install the application per our autosearch rules.
    // Return nil; the UI level code will ask the user where to install if it wishes to proceed.
    return nil;
}

- (BOOL)chooseInstallationDirectory:(NSString *)lastAttemptedPath;
{
    __autoreleasing NSError *error = nil;
    NSString *chosenDirectory = [[self class] suggestAnotherInstallationDirectory:lastAttemptedPath trySelf:NO];
    
    if (chosenDirectory == nil && ![NSString isEmptyString:lastAttemptedPath]) {
        // If we couldn't find any writable directories, we're kind of screwed, but go ahead and pop up the panel in case the user can navigate somewhere
        chosenDirectory = [lastAttemptedPath stringByDeletingLastPathComponent];
    }
    
    chosenDirectory = [[self class] chooseInstallationDirectory:chosenDirectory error:&error];
    
    if (chosenDirectory != nil) {
        [self setInstallationDirectory:chosenDirectory];
    }
    
    _hasAskedForInstallLocation = YES;
    
    return (chosenDirectory != nil);
}

+ (NSString *)chooseInstallationDirectory:(NSString *)initialDirectoryPath error:(NSError **)outError;
{
    __block NSString *localResult = nil;
    __block NSError *localError = nil;

    [self chooseInstallationDirectory:initialDirectoryPath modalForWindow:nil completionHandler:^(NSError *error, NSString *result) {
        localResult = [result copy];
        localError = [error copy];
    }];

    if (localResult == nil && outError != NULL) {
        *outError = localError;
    }
    
    return localResult;
}

+ (void)chooseInstallationDirectory:(NSString *)initialDirectoryPath modalForWindow:(NSWindow *)parentWindow completionHandler:(void (^)(NSError *error, NSString *result))handler;
{
    id delegate = (id <NSOpenSavePanelDelegate>)self;
    
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setDelegate:delegate];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:(id)kUTTypeApplicationBundle]];
    [panel setAllowsOtherFileTypes:NO];
    [panel setCanCreateDirectories:YES];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setResolvesAliases:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:NSLocalizedStringFromTableInBundle(@"Choose", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Choose install location button title")];
    if (parentWindow != nil) {
        [panel setMessage:NSLocalizedStringFromTableInBundle(@"Choose Install Location", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Choose install location panel title")];
    } else {
        [panel setTitle:NSLocalizedStringFromTableInBundle(@"Choose Install Location", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Choose install location panel title")];
    }
    
    if (![NSString isEmptyString:initialDirectoryPath]) {
        [panel setDirectoryURL:[NSURL fileURLWithPath:initialDirectoryPath]];
    }
    
    handler = [handler copy];
    
    void (^localCompletionHandler)(NSInteger result) = ^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            NSURL *resultURL = [[[panel URLs] lastObject] absoluteURL];
            handler(nil, [resultURL path]);
        } else {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
            handler(error, nil);
        }
    };
    
    localCompletionHandler = [localCompletionHandler copy];
    
    if (parentWindow != nil) {
        [panel beginSheetModalForWindow:parentWindow completionHandler:^(NSInteger result) {
            localCompletionHandler(result);
        }];
    } else {
        NSUInteger result = [panel runModal];
        localCompletionHandler(result);
    }
}

+ (BOOL)validateTargetFilesystem:(NSString *)installationPath error:(NSError **)outError;
{
    // Check whether the installation path is on a read-only filesystem. (The usual reason for this is that the user is running the application from a disk image, but CDs, network mounts, and so on are other possibilities.)
    // NSFileManager doesn't return filesystem flags or anything, so use the POSIX API
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    struct statfs sbuf;
    bzero(&sbuf, sizeof(sbuf));
    
    NSString *statPath = installationPath;
    int rc = statfs([fileManager fileSystemRepresentationWithPath:statPath], &sbuf);
    
    if (rc != 0 && errno == ENOENT) {
        // Well, maybe we're installing to a new name; see if we can stat the directory
        statPath = [installationPath stringByDeletingLastPathComponent];
        rc = statfs([fileManager fileSystemRepresentationWithPath:statPath], &sbuf);
    }
    
    if (rc == 0) {
        if ((sbuf.f_flags & MNT_RDONLY) || (sbuf.f_flags & MNT_NOEXEC)) {
            // This isn't a filesystem we can install an upgraded application on.
            if (outError != NULL) {
                NSString *localizedDescription = nil;
                NSString *localizedFailureReason = nil;
                
                NSString *mountPoint = [fileManager stringWithFileSystemRepresentation:sbuf.f_mntonname length:strnlen(sbuf.f_mntonname, sizeof(sbuf.f_mntonname))];
                NSString *volumeName = [mountPoint lastPathComponent];
                
                if ((sbuf.f_flags & MNT_RDONLY) != 0) {
                    localizedFailureReason = NSLocalizedStringFromTableInBundle(@"The destination volume, \\U201C%@\\U201D, is not writable.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error failure reason - when the destination location is on a read-only filesystem such as a disk image or CDROM");
                } else {
                    localizedFailureReason = NSLocalizedStringFromTableInBundle(@"The destination volume, \\U201C%@\\U201D, does not allow applications.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error failure reason - when the destination location is on a filesystem mounted with NOEXEC (cannot run programs from it)");
                }
                
                localizedFailureReason = [NSString stringWithFormat:localizedFailureReason, volumeName];
                localizedDescription = NSLocalizedStringFromTableInBundle(@"Cannot install update there", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - when we notice that we won't be able to unpack the update to the specified location - more detailed text, and an option to choose a different location, will follow");
                
                OSUChecker *checker = [OSUChecker sharedUpdateChecker];
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: localizedDescription,
                    NSLocalizedFailureReasonErrorKey: localizedFailureReason,
                    NSFilePathErrorKey: installationPath,
                    OSUBundleIdentifierErrorInfoKey: [checker applicationIdentifier]
                };
                
                *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUBadInstallationDirectory userInfo:userInfo];
            }
            
            return NO;
        }
    }
    
    if (rc != 0 && errno != ENOENT) {
        // These errors would presumably keep us from installing anything, quit early
        if (outError != NULL) {
            *outError = nil;
            OBErrorWithErrno(outError, errno, "statfs", statPath, nil);
            
            NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot install update there", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - when we notice that we won't be able to unpack the update to the specified location - more detailed text, and an option to choose a different location, will follow");
            
            OSUErrorWithInfo(outError, OSUBadInstallationDirectory, description, [*outError localizedFailureReason], installationPath, NSFilePathErrorKey, nil); // Wraps the errno error
        }
        
        return NO;
    }
    
    return YES;
}

#pragma mark -
#pragma mark NSOpenSavePanelDelegate

+ (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url;
{
    if (![url isFileURL]) {
        return NO;
    }
    
    if (![[self class] validateTargetFilesystem:[url path] error:NULL]) {
        return NO;
    }

    return YES;
}

+ (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError;
{
    if (![url isFileURL]) {
        if (outError != NULL) {
            NSDictionary *userInfo = @{
                NSURLErrorKey: url
            };
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError userInfo:userInfo];
        }
        return NO;
    }

    return [[self class] validateTargetFilesystem:[url path] error:outError];
}

#pragma mark -
#pragma mark tar/bz2 support

- (NSString *)_chooseTemporaryPath:(NSString *)nameHint error:(NSError **)outError;
{
    // We can (should?) probably use -[NSFileManager URLForDirectory:indomain:appropriateForURL:create:error:] here.
    // This will find an appropriate directly for replacing the named item.
    // It is documented for use by safe-saves (and currently creates a path with a component "(A Document Being Saved By <<BUNDLE_NAME>>)"), but is also appropriate for this use case.
    // Pass NSItemReplacementDirectory for the directory, and NSUserDomainMask for the mask (even if the URL is outside of $HOME.)
    
    NSString *result = [[NSFileManager defaultManager] temporaryPathForWritingToPath:[_installationDirectory stringByAppendingPathComponent:nameHint] allowOriginalDirectory:YES create:NO error:outError];

#ifdef DEBUG
    if (result != nil) {
        NSLog(@"Choosing directory to unpack into: installationDirectory=%@ installationName=%@ nameHint=%@ %@", _installationDirectory, _installationName, nameHint, result);
    } else {
        NSLog(@"Error choosing directory to unpack into: %@", outError != NULL ? *outError : @"UNKNOWN");
    }
#endif
    
    return result;
}

- (BOOL)_unpackApplicationFromTarFile:(NSError **)outError;
{
    NSString *expander = nil;
    NSString *untarPath = _packagePath;
    
    NSMutableDictionary *extract = [NSMutableDictionary dictionary];
    
    if ([_packagePath hasSuffix:@".tbz2"] || [_packagePath hasSuffix:@".tar.bz2"]) {
        expander = @"--bzip2";
    } else if ([_packagePath hasSuffix:@".tgz"] || [_packagePath hasSuffix:@".tar.gz"]) {
        expander = @"--gzip";
    } else if ([_packagePath hasSuffix:@".tar"]) {
        expander = nil;
    } else {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - could not process .tar.bz2 file");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Unknown package type.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - downloaded upgrade package was not in a format we recognize");
        OSUError(outError, OSUUnableToProcessPackage, description, reason);
        return NO;
    }
    
    UPDATE_STATUS((NSLocalizedStringFromTableInBundle(@"Decompressing\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"status description")));
    
#ifdef DEBUG
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OSUTestInstallationFailure"]) {
        OSUError(outError, OSUUnableToProcessPackage, @"Testing failure to install.", @"Test operation.");
        return NO;
    }
#endif
    
    // Create a temporary directory into which to unpack
    NSString *temporaryPath = [self _chooseTemporaryPath:[[_packagePath lastPathComponent] stringByDeletingPathExtension] error:outError];
    if (!temporaryPath) {
        return NO;
    }
    
    NSFileManager *manager = [NSFileManager defaultManager];
    
    if (![manager createDirectoryAtPath:temporaryPath withIntermediateDirectories:YES attributes:nil error:outError]) {
        NSString *reason = [NSString stringWithFormat:@"Could not create temporary directory at '%@'.", temporaryPath];
        OSUError(outError, OSUBadInstallationDirectory, @"Unable to install update.", reason);
        return NO;
    }
    
    [extract setObject:@"/usr/bin/tar"  forKey:OFFilterProcessCommandPathKey];
    [extract setObject:[NSArray arrayWithObjects:@"xf", untarPath, expander /* may be nil, therefore must be last */, nil] forKey:OFFilterProcessArgumentsKey];
    [extract setObject:temporaryPath forKey:OFFilterProcessWorkingDirectoryPathKey];
    
    __autoreleasing NSData *errData = nil;
    
    if (![OFFilterProcess runWithParameters:extract inMode:NSModalPanelRunLoopMode standardOutput:&errData standardError:&errData error:outError]) {
        if (outError != NULL) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - could not process .tar.bz2 file");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"Extract script failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, _reportStringForCapturedOutputData(errData), @"extract-stderr", extract, @"filter-params", nil];
            if (*outError != nil) {
                userInfo = [userInfo dictionaryWithObject:*outError forKey:NSUnderlyingErrorKey];
            }
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToProcessPackage userInfo:userInfo];
        }
        return NO;
    }
        
    // Look for a single .app directory inside the unpacked path; this is what we are to return.
    NSString *applicationPath = [self _findApplicationInDirectory:temporaryPath error:outError];
    if (applicationPath == nil) {
        return NO;
    }
    
    if (!_isApplicationSuperficiallyValid(applicationPath, outError)) {
        return NO;
    }
    
    _unpackedPath = [applicationPath copy];
    
    if ([NSString isEmptyString:_installationName]) {
        _installationName = [[_unpackedPath lastPathComponent] copy];
    }
    
    return YES;
}

#pragma mark -
#pragma mark OFControllerStatusObserver

- (void)controllerCancelledTermnation:(OFController *)controller;
{
    if (self.terminationObserver != nil) {
        // If we were waiting for termination, cancel our observers and abort this installation.
        //
        // We don't want to finish the installation at an arbitrary point in the future if the user explicitly cancelled termination. This is problematic because:
        // - Installing and relaunching at an arbitrary future point is unexpected.
        //   - Certainly the relaunch is; we could arrange to install without relaunch.
        //   - We could arrange to install without relaunch, but we'd need coordination with the rest of OSU so it knows it had an update pending.
        // - We need more coordination with the rest of OSU so that we can possibly
        //   - Install this update at termination without relaunch if appropriate
        //   - Abandon the queued update if we get a newer one in the meantime
        //   - Deal with the eventuality that we held onto an update so long it might be expired
        //   - Avoid preventing subsequent software update checks
        
        [[OFController sharedController] removeStatusObserver:self];
        [[NSNotificationCenter defaultCenter] removeObserver:self.terminationObserver];
        self.terminationObserver = nil;
        
        // Re-enabled sudden termination; we disabled it when we requested that the app terminate
        [[NSProcessInfo processInfo] enableSuddenTermination];
        
        // Close our host window.
        [self.delegate close];
        
        // Balance the strong retain we held on ourselves at the beginning of -run
        OBAutorelease(self);
    }
}

#pragma mark -
#pragma mark Install & Relaunch

- (NSDictionary *)_installerArguments;
{
    OBPRECONDITION(_unpackedPath != nil);
    OBPRECONDITION(_installationDirectory != nil);
    OBPRECONDITION(_installedVersionPath != nil);
    OBPRECONDITION(_installationName != nil);

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleName = [bundle objectForInfoDictionaryKey:(id)kCFBundleNameKey];
    NSString *iconName = [bundle objectForInfoDictionaryKey:@"CFBundleIconFile"];
    NSString *iconPath = [bundle pathForImageResource:iconName];

    if (iconPath == nil) {
        iconPath = @"";
    }

    NSDictionary *installerArguments = nil;
    NSDictionary *requiredArguments = @{
        OSUInstallerUnpackedApplicationPathKey : _unpackedPath,
        OSUInstallerInstallationDirectoryPathKey : _installationDirectory,
        OSUInstallerCurrentlyInstalledVersionPathKey : _installedVersionPath,
        OSUInstallerInstallationNameKey : _installationName,
        OSUInstallerBundleNameKey : bundleName,
        OSUInstallerBundleIconPathKey : iconPath,
    };

    if (self.authorizationData != nil) {
        NSMutableDictionary *args = [NSMutableDictionary dictionaryWithDictionary:requiredArguments];
        args[OSUInstallerInstallationAuthorizationDataKey] = self.authorizationData;
        installerArguments = args;
    } else {
        installerArguments = requiredArguments;
    }
    
    OBPOSTCONDITION(installerArguments != nil);
    return installerArguments;
}

- (BOOL)_installUpdate:(NSError **)outError;
{
    __block BOOL installerSucceeded = NO;
    __block NSError *installerError = nil;
    __block BOOL hasReceivedResponseOrError = NO;

    NSXPCConnection *connection = self.connection;
    id <OSUInstallerService> remoteObjectProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        installerSucceeded = NO;
        installerError = error;
        hasReceivedResponseOrError = YES;
    }];

    NSDictionary *installerArguments = [self _installerArguments];
    [remoteObjectProxy installUpdate:installerArguments reply:^(BOOL success, NSError *error) {
        installerSucceeded = success;
        installerError = error;
        hasReceivedResponseOrError = YES;
    }];

    // We really want this to be synchronous, so we have to carefully run the run loop waiting for a reply.
    
    while (!hasReceivedResponseOrError && !_connectionFlags.interrupted && !_connectionFlags.invalid) {
        NSTimeInterval pollInterval = 0.5;
        NSDate *limitDate = [NSDate dateWithTimeIntervalSinceNow:pollInterval];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:limitDate];
    }

    if (outError != NULL) {
        *outError = installerError;
    }
    
    return installerSucceeded;
}

- (void)_relaunchFromPath:(NSString *)pathString;
{
    OBPRECONDITION(OSUInstallerHasReceivedApplicationWillTerminate);

    NSXPCConnection *connection = self.connection;
    id <OSUInstallerService> remoteObjectProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        // We cannot run modal session during application termination; use CFUserNotification instead
        NSString *format = NSLocalizedStringFromTableInBundle(@"Unable to Reopen %@", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"relaunch error format string");
        NSString *title = [NSString stringWithFormat:format, [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey]];
        NSString *defaultButton = OAOK();

        NSLog(@"Error communicating with the OSUInstaller XPC service: %@", error);
        _reportError(error, title, defaultButton, nil, nil, NULL);
        _terminate(1);
    }];
    
    // Ask the OSUInstaller XPC Service to launch the application after we terminate; we cannot do it from here in the sandboxed case.
    // Block until the reply handler has been called so that we know the launch trampoline is ready.
    // After we have received a response, let the app terminate naturally (we are already in the terminate path) so that all interested parties get NSApplicationWillTerminateNotification.
    
    __block BOOL hasReceivedResponse = NO;
    NSURL *applicationURL = [NSURL fileURLWithPath:pathString];
    [remoteObjectProxy launchApplicationAtURL:applicationURL afterTerminationOfProcessWithIdentifier:getpid() reply:^{
        hasReceivedResponse = YES;
    }];
    
    while (!hasReceivedResponse && !_connectionFlags.interrupted && !_connectionFlags.invalid) {
        NSTimeInterval pollInterval = 0.5;
        NSDate *limitDate = [NSDate dateWithTimeIntervalSinceNow:pollInterval];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:limitDate];
    }

    // Continue termination...
}

#pragma mark -
#pragma mark Private

- (void)_presentError:(NSError *)error;
{
    OBPRECONDITION(error != nil);
    
    // This can get called from XPC background queues.
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (error == nil || [error causedByUserCancelling]) {
            OBStrongRetain(self);
            [self _retry:NO context:NULL];
        } else {
            OBStrongRetain(self); // `self` is released in the _retry handler
            
            id <OSUInstallerDelegate> delegate = self.delegate;
            id presenter = (delegate != nil ? (id)delegate : (id)[NSApplication sharedApplication]);
            
            NSError *errorToPresent = error;
            if ([error recoveryAttempter] == nil) {
                errorToPresent = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:self options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
            }
            
            // This yields a modal alert, but in 10.11 produces a warning. The -presentError: variant doesn't have a recovered/context handler, though.
            //
            // Can we use the modal prentation here, and rely on the result for whether recovery took place?
            // That's synchronous, so we don't need a callback selector - we can do the work serially after -presentError:.
            
            NSWindow *window = nil;
            
            [presenter presentError:errorToPresent modalForWindow:(NSWindow * _Nonnull)window delegate:self didPresentSelector:@selector(_retry:context:) contextInfo:NULL];
        }
    }];
}

// This is used as the didPresent selector for error presentation / recovery
- (void)_retry:(BOOL)recovered context:(void *)context
{
    OBAutorelease(self);
    
    if (recovered) {
        [self run];
    } else {
        // Reveal the downloaded package on failure.
        if (_packagePath != nil && [[NSFileManager defaultManager] fileExistsAtPath:_packagePath]) {
            [[NSWorkspace sharedWorkspace] selectFile:_packagePath inFileViewerRootedAtPath:[_packagePath stringByDeletingLastPathComponent]];
        }
        
        [self.delegate close];
    }
}

- (NSString *)_findApplicationInDirectory:(NSString *)dir error:(NSError **)outError;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Avoid scanning the directory using NSFileManager (or any other Carbon APIs), due to RADAR 5468824 (see below)
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
        
        // NULL bufp indicates we've read all the dir entries
        if (!bufp)
            break;
        
        // We're not interested in hidden files
        if (buf.d_namlen < 1 || buf.d_name[0] == '.')
            continue;
        
        // We sometimes do get a d_type, and sometimes don't. Depends on the fs type. Sigh.
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
        
        // We're only interested in directories (.app bundles and subdirs)
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
        // Good, we found exactly one app. Return it.
        return [dir stringByAppendingPathComponent:[appDirNames objectAtIndex:0]];
    } else if (appCount == 0 && [nonAppDirNames count] == 1) {
        // If we don't see any applications, but there is exactly one subdirectory, check in there
        return [self _findApplicationInDirectory:[dir stringByAppendingPathComponent:[nonAppDirNames objectAtIndex:0]] error:outError];
    } else {
        // Otherwise, we fail to find an application in this directory
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

@end

#pragma mark -

static void _reportError(NSError *error, NSString *titleString, NSString *defaultButtonTitle, NSString *alternateButtonTitle, NSString *otherButtonTitle, CFOptionFlags *responseFlags)
{
    NSString *iconName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIconFile"];
    NSURL *applicationIconURL = [[NSBundle mainBundle] URLForImageResource:iconName];

    CFURLRef iconURL = NULL;
    CFURLRef soundURL = NULL;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[applicationIconURL path]]) {
        iconURL = (__bridge CFURLRef)applicationIconURL;
    }

    CFStringRef title = (__bridge CFStringRef)titleString;
    CFStringRef message = (__bridge CFStringRef)[error localizedDescription];
    CFStringRef defaultButton = (__bridge CFStringRef)defaultButtonTitle;
    CFStringRef alternateButton = (__bridge CFStringRef)alternateButtonTitle;
    CFStringRef otherButton = (__bridge CFStringRef)otherButtonTitle;

    if (responseFlags != NULL) {
        *responseFlags = 0;
    }
    
    CFUserNotificationDisplayAlert(0, 0, iconURL, soundURL, NULL, title, message, defaultButton, alternateButton, otherButton, responseFlags);
}

static void _terminate(int status)
{
    // We don't send -terminate: to NSApplication here; this is called during the "Install & Reopen" which happens during termination now.
    // We don't send +controllerWillTerminate to OSUChecker either, for the same reasons.
    //
    // See r179622.

    OBASSERT(OSUInstallerHasReceivedApplicationWillTerminate);
    exit(status);
}

static id _reportStringForCapturedOutputData(NSData *data)
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

static BOOL _makeInstallError(NSString *errorDetail, NSError **outError)
{
    if (outError != NULL) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - we downloaded an update, but there seems to be something wrong with the application it contained");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The updated application is invalid (%@)", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - we downloaded an update, but there's something obviously wrong with the updated application, like it doesn't have an Info.plist or whatever"), errorDetail];
        
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey : description,
                                   NSLocalizedFailureReasonErrorKey : reason
                                   };
        *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToUpgrade userInfo:userInfo];
    }
    
    return NO;
}

static BOOL _isApplicationSuperficiallyValid(NSString *path, NSError **outError)
{
    struct stat sbuf = {0};

    // Check a handful of things about an application before we try to install it, just to avoid installing a completely broken app.
    // As with _findApplicationInDirectory:error:, we want to avoid indirectly using Carbon APIs here.
    // None of these tests should ever fail unless we've made an error packaging up the application for distribution, but we have been known to do that...
    
    if (stat([path fileSystemRepresentation], &sbuf) != 0) {
        OBErrorWithErrno(outError, errno, "stat", path, NSLocalizedStringFromTableInBundle(@"Could not read directory", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - we downloaded and unpacked an update, but now we can't read it"));
        return NO;
    }

    if (!S_ISDIR(sbuf.st_mode)) {
        return _makeInstallError(@"App bundle is not a directory", outError);
    }
    
    NSString *contentsPath = [path stringByAppendingPathComponent:@"Contents"];
    NSData *plistData = [NSData dataWithContentsOfFile:[contentsPath stringByAppendingPathComponent:@"Info.plist"] options:0 error:outError];
    if (!plistData) {
        // NSData set outError for us
        return NO;
    }

    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:outError];
    if (plist == nil) {
        // NSPropertyListSerialization set outError for us
        return NO;
    }

    if (![plist isKindOfClass:[NSDictionary class]] ||
        ![[plist objectForKey:(NSString *)kCFBundleIdentifierKey] isKindOfClass:[NSString class]] ||
        ![[plist objectForKey:(NSString *)kCFBundleExecutableKey] isKindOfClass:[NSString class]]) {
        return _makeInstallError(@"Info.plist does not contain necessary information", outError);
    }
    
    NSString *executableFilePath = [[contentsPath stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:[plist objectForKey:(NSString *)kCFBundleExecutableKey]];
    if (stat([executableFilePath fileSystemRepresentation], &sbuf) != 0) {
        OBErrorWithErrno(outError, errno, "stat", executableFilePath, NSLocalizedStringFromTableInBundle(@"Could not examine application", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - we downloaded and unpacked an update, but we can't stat its CFBundleExecutable file"));
        return NO;
    }
    
    if (!S_ISREG(sbuf.st_mode) || !(sbuf.st_mode & S_IXUSR) || (sbuf.st_size < 1024)) {
        return _makeInstallError([NSString stringWithFormat:@"Not an executable: %@", [plist objectForKey:(NSString *)kCFBundleExecutableKey]], outError);
    }
    
    // We didn't see anything obviously wrong, so it's probably OK
    return YES;
}
