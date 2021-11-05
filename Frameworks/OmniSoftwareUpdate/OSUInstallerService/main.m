// Copyright 2013-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <ServiceManagement/ServiceManagement.h>

#import <dirent.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

#import "OSUInstallerScript.h"
#import "OSUInstallerServiceProtocol.h"
#import "OSUInstallerPrivilegedHelperProtocol.h"
#import "OSUInstallerPrivilegedHelperRights.h"
#import "OSUErrors.h"
#import "OSUConnectionAudit.h"

#define ERROR_FILENAME_AND_NUMBER \
    ([[[NSFileManager defaultManager] stringWithFileSystemRepresentation:__FILE__ length:strlen(__FILE__)] stringByAppendingFormat:@":%d", __LINE__])

typedef NS_OPTIONS(NSUInteger, OSUInstallerServiceUpdateOptions) {
    OSUInstallerServiceUpdateOptionDryRun = 1 << 1
};

@interface OSUInstallerService : NSObject <OSUInstallerService, NSXPCListenerDelegate> {
  @private
     AuthorizationRef _authorizationToken;
}

@property (nonatomic) BOOL hasPerformedPreflight;
@property (nonatomic) BOOL preflightSuccessful;
@property (nonatomic, copy) NSError *preflightError;

@property (nonatomic, copy) NSString *trampolineToolPath;

@property (nonatomic) AuthorizationRef authorizationToken;
@property (nonatomic, copy) NSData *authorizationData;
@property (nonatomic, copy) NSString *unpackedPath;
@property (nonatomic, copy) NSString *installationDirectory;
@property (nonatomic, copy) NSString *installedVersionPath;
@property (nonatomic, copy) NSString *installationName;

@end

#pragma mark -

@implementation OSUInstallerService

- (void)dealloc;
{
    if (_authorizationToken != NULL) {
        AuthorizationFree(_authorizationToken, kAuthorizationFlagDefaults);
        _authorizationToken = NULL;
    }
}

#pragma mark Accessors

- (AuthorizationRef)authorizationToken;
{
    return _authorizationToken;
}

- (void)setAuthorizationToken:(AuthorizationRef)authorizationToken;
{
    if (_authorizationToken != NULL) {
        AuthorizationFree(_authorizationToken, kAuthorizationFlagDefaults);
        _authorizationToken = NULL;
    }
    
    _authorizationToken = authorizationToken;
}

#pragma mark OSUInstallerService XPC protocol

- (void)preflightUpdate:(NSDictionary *)arguments reply:(void (^)(BOOL success, NSError *error, NSData *authorizationData))reply;
{
    __autoreleasing NSError *unpackError = nil;
    
    self.hasPerformedPreflight = YES;
    self.preflightSuccessful = NO;
    
    if (![self _unpackInstallerArguments:arguments error:&unpackError]) {
        self.preflightSuccessful = NO;
        self.preflightError = unpackError;
        reply(NO, unpackError, nil);
        return;
    }
    
    reply = [reply copy];
    
    BOOL requiresPrivilegedInstall = NO;

    __autoreleasing NSError *installError;
    if (![self _installUpdateWithOptions:OSUInstallerServiceUpdateOptionDryRun requiresPrivilegedInstall:&requiresPrivilegedInstall error:&installError]) {
        reply(NO, installError, nil);
        return;
    }

    __block NSData *authorizationData = nil;
    void (^prepareTrampolineAndReply)(void) = ^{
        __autoreleasing NSError *prepareError;
        if (![self _prepareTrampolineTool:&prepareError]) {
            reply(NO, prepareError, nil);
        } else {
            self.preflightSuccessful = YES;
            reply(YES, nil, authorizationData);
        }
    };

    if (!requiresPrivilegedInstall) {
        prepareTrampolineAndReply();
        return;
    }

    NSLog(@"Preflight update with arguments %@", arguments);

    [self checkPrivilegedHelperToolVersionWithReply:^(BOOL versionMismatch, NSInteger installedToolVersion) {
        BOOL shouldInstallOrUpdateTool = versionMismatch;

        NSLog(@"Preflight finished with versionMismatch: %d, installedToolVersion: %ld", versionMismatch, installedToolVersion);

        // Update the authorization rights db in /etc/authorization if necessary
        OSUInstallerSetUpAuthorizationRights();

        // Pre-authorize for all the necessary rights in one pass.
        // If successful, install/update the tool if necessary.
        // If install/update is successful (or unnecessary), return success=YES to the caller with the rights.

        AuthorizationItem environtmentItems[2] = {};
        AuthorizationEnvironment environment = { .count = 0, .items = environtmentItems };

        NSString *bundleName = arguments[OSUInstallerBundleNameKey];
        if (![NSString isEmptyString:bundleName]) {
            NSString *format = NSLocalizedString(@"An update to %@ is ready to be installed.", @"Format for authorization prompt when installing an update");
            NSString *string = [NSString stringWithFormat:format, bundleName];
            const char *prompt = [string UTF8String];

            int index = environment.count++;
            AuthorizationItem *item = &environment.items[index];

            item->name = kAuthorizationEnvironmentPrompt;
            item->valueLength = strlen(prompt);
            item->value = (void *)prompt;
            item->flags = 0;
        }

        NSString *iconPath = arguments[OSUInstallerBundleIconPathKey];
        if (![NSString isEmptyString:bundleName]) {
            const char *path = [[NSFileManager defaultManager] fileSystemRepresentationWithPath:iconPath];

            int index = environment.count++;
            AuthorizationItem *item = &environment.items[index];

            item->name = kAuthorizationEnvironmentIcon;
            item->valueLength = strlen(path);
            item->value = (void *)path;
            item->flags = 0;
        }

        AuthorizationItem items[3] = {};
        AuthorizationRights rights = { .count = 0, .items = items};
        int index = 0;
        AuthorizationItem *item = NULL;

        // value is incorrectly marked as non-null by a blanked assume-non-null in Authorization.h in 7.3 beta (7D111g)
        // rdar://problem/24209238
        //
        // Ensure the array is zero filled now, and avoid assigning item->value = NULL
        memset(items, 0, sizeof(items));

        if (shouldInstallOrUpdateTool) {
            index = rights.count++;
            item = &rights.items[index];

            item->name = kSMRightBlessPrivilegedHelper;
            item->valueLength = 0;
            //              item->value = NULL;
            item->flags = 0;

            index = rights.count++;
            item = &rights.items[index];

            item->name = kSMRightModifySystemDaemons;
            item->valueLength = 0;
            //              item->value = NULL;
            item->flags = 0;
        }

        index = rights.count++;
        item = &rights.items[index];

        item->name = [OSUInstallUpdateRightName UTF8String];
        item->valueLength = 0;
        //          item->value = NULL;
        item->flags = 0;

        // We have to ask for the rights in the XPC service. AuthorizationCreate will return errAuthorizationDenied in a sandboxed application.
        // The downside of doing it here is that the authorization dialog will use the filesystem name of our bundle, which is required to match its bundle identifier.

        AuthorizationRef authorizationRef = NULL;
        AuthorizationFlags flags = (kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights | kAuthorizationFlagPreAuthorize);
        OSStatus status = AuthorizationCreate(&rights, &environment, flags, &authorizationRef);
        if (status != errAuthorizationSuccess) {
            NSDictionary *userInfo = @{
                                       OBFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
                                       };
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:userInfo];
            reply(NO, error, nil);
            return;
        }

        // Create the external authorization data to return to our client (and for internal use)

        AuthorizationExternalForm externalForm;
        status = AuthorizationMakeExternalForm(authorizationRef, &externalForm);
        if (status != errAuthorizationSuccess) {
            NSDictionary *userInfo = @{
                                       OBFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
                                       };
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:userInfo];
            reply(NO, error, nil);
            return;
        }

        authorizationData = [NSData dataWithBytes:&externalForm length:sizeof(externalForm)];

        // Hold on to our authorization token for the lifetime of this connection
        self.authorizationToken = authorizationRef;
        authorizationRef = NULL;

        // Install/update the tool if necessary

        __autoreleasing NSError *updateToolError;
        if (shouldInstallOrUpdateTool && ![self updatePrivilegedHelperToolWithAuthorizationData:authorizationData installedToolVersion:installedToolVersion error:&updateToolError]) {
            reply(NO, updateToolError, nil);
            return;
        }

        prepareTrampolineAndReply();
    }];
}

- (void)prepareTrampoline
{
}

- (void)installUpdate:(NSDictionary *)arguments reply:(void (^)(BOOL success, NSError *error))reply;
{
    if (!self.hasPerformedPreflight) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - preflight skipped");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"A necessary installation step was skipped.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - preflight skipped");
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : description,
            NSLocalizedFailureReasonErrorKey : reason,
            OBFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
        };
        NSError *error = [NSError errorWithDomain:OSUErrorDomain code:OSUPreflightNotPerformed userInfo:userInfo];
        reply(NO, error);
        return;
    }

    BOOL success = NO;
    __autoreleasing NSError *error = nil;

    if ([self _unpackInstallerArguments:arguments error:&error]) {
        success = [self _installUpdateWithOptions:0 requiresPrivilegedInstall:NULL error:&error];
    }

    reply(success, error);
}

- (void)launchApplicationAtURL:(NSURL *)applicationURL afterTerminationOfProcessWithIdentifier:(pid_t)pid reply:(void (^)(void))reply;
{
    // Spawn a tool which will wath for PID to exit, then launch the application at applicationURL.
    // We don't do that there because this XPC service's lifetime is loosely tied to that of the parent application.
    // Send the reply after we've spawned the tool so the caller knows it is OK to start its termination process.
    //
    // N.B. During preflight, we copied the trampoline tool out to a temporary directory since our bundle is deleted or moved to the trash before we get this message. The tool will unlink/remove itself before exiting.
    
    NSArray *arguments = @[
        [NSString stringWithFormat:@"%d", pid],
        [applicationURL path]
    ];
    
    [NSTask launchedTaskWithLaunchPath:self.trampolineToolPath arguments:arguments];

    reply();
}

#pragma mark Privileged Helper Installer

static void _afterDelayPerformBlockOnMainThread(NSTimeInterval delay, void (^block)(void));
static void _afterDelayPerformBlockOnMainThread(NSTimeInterval delay, void (^block)(void))
{
    block = [block copy];
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * 1e9) /* dispatch_time() takes nanoseconds */);
    dispatch_after(startTime, dispatch_get_main_queue(), block);
}

- (void)checkPrivilegedHelperToolVersionWithReply:(void (^)(BOOL versionMismatch, NSInteger installedToolVersion))reply;
{
    // We require that the installed tool have the same version as our embedded tool to ensure we have precisely compatible protocols.
    // SMJobBless automatically takes care of upgrading the tool if necessary (but only does so after forcing you to prompt for credentials.)
    // It doesn't handle the case of wanting to downgrade the tool (which we no longer do -- see -updatePrivilegedHelperToolWithAuthorizationData:installedToolVersion:error:).
    // SMJobCopyDictionary() is deprecated, so we poke the helper tool no matter what. If it isn't installed, we'll get back an error (NSCocoaErrorDomain/NSXPCConnectionInvalid).

#ifdef DEBUG_kc
        NSLog(@"DEBUG: OSUInstallerService: version check: checking %@", OSUInstallerPrivilegedHelperJobLabel);
#endif

    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:OSUInstallerPrivilegedHelperJobLabel options:NSXPCConnectionPrivileged];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUInstallerPrivilegedHelper)];
    [connection resume];
    
    reply = [reply copy];
    
    __block NSConditionLock *hasSentReplyLock = [[NSConditionLock alloc] initWithCondition:NO];
    __block void (^replyOnce)(BOOL versionMismatch, NSInteger installedToolVersion) = ^(BOOL versionMismatch, NSInteger installedToolVersion) {
        [hasSentReplyLock lock];
        if (!hasSentReplyLock.condition) {
            reply(versionMismatch, installedToolVersion);
        }
        [hasSentReplyLock unlockWithCondition:YES];
    };

    id <OSUInstallerPrivilegedHelper> remoteProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        OBASSERT([[error domain] isEqual:NSCocoaErrorDomain]);
        OBASSERT([error code] == NSXPCConnectionInvalid);
        [connection invalidate];
        NSLog(@"OSUInstallerService: connection invalid: %@", [error toPropertyList]);
        replyOnce(YES, 0);
    }];

    _afterDelayPerformBlockOnMainThread(10.0, ^{
        NSLog(@"OSUInstallerService: version check: timed out");
        replyOnce(YES, 0); // the old helper tool isn't responding, let's install a new one
    });

    [remoteProxy getVersionWithReply:^(NSUInteger version) {
        NSLog(@"OSUInstallerService: version check: installed is %@, expected is %@", @(version), @(OSUInstallerPrivilegedHelperVersion));
        [connection invalidate];
        replyOnce(version != OSUInstallerPrivilegedHelperVersion, version);
    }];
}

// As of protocol version 6, we only install the tool. Each version has the protocol version as the last path component of the install helper and once it is installed we leave it alone.
// This avoids flapping between multiple versions on disk if two apps are installed that want different versions and it avoids deprecated SMJob* functions.
- (BOOL)updatePrivilegedHelperToolWithAuthorizationData:(NSData *)authorizationData installedToolVersion:(NSInteger)installedToolVersion error:(NSError **)error;
{
    NSLog(@"Updating helper tool, installed version %ld ...", installedToolVersion);
    
    AuthorizationRef authorizationRef = [self createAuthorizationRefFromExternalAuthorizationData:authorizationData error:error];
    if (authorizationRef == NULL) {
        NSLog(@"  Create authorization failed");
        return NO;
    }

    CFErrorRef blessError = NULL;
    BOOL success = SMJobBless(kSMDomainSystemLaunchd, (__bridge CFStringRef)OSUInstallerPrivilegedHelperJobLabel, authorizationRef, &blessError);
    if (!success) {
        NSLog(@"  Job bless failed for %@: %@", OSUInstallerPrivilegedHelperJobLabel, [(__bridge NSError *)blessError toPropertyList]);
        AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
        authorizationRef = NULL;

        OB_CFERROR_TO_NS(error, blessError);
        
        return NO;
    }

    AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
    authorizationRef = NULL;
    
    NSLog(@"Update succeeded");
    return YES;
}

- (AuthorizationRef)createAuthorizationRefFromExternalAuthorizationData:(NSData *)authorizationData error:(NSError **)error;
{
    OSStatus status = noErr;
    AuthorizationRef authorizationRef = NULL;
    AuthorizationExternalForm authorizationExternalForm;
    
    if ([authorizationData length] != sizeof(authorizationExternalForm)) {
        if (error != NULL) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : @"AuthorizationExternalForm was the wrong length.",
                OBFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
            };
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errAuthorizationInvalidRef userInfo:userInfo];
        }
        return NULL;
    }
    
    [authorizationData getBytes:&authorizationExternalForm length:sizeof(authorizationExternalForm)];
    
    status = AuthorizationCreateFromExternalForm(&authorizationExternalForm, &authorizationRef);
    if (status != errAuthorizationSuccess) {
        if (error != NULL) {
            NSDictionary *userInfo = @{
                OBFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
            };
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:userInfo];
        }
        return NULL;
    }
    
    return authorizationRef;
}


#pragma mark Private

static BOOL _IsInGroupList(gid_t targetGID)
{
    if (targetGID == getgid()) {
        return YES;
    }
    
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

static BOOL _NeedsPrivilegedInstall_DestDir(NSString *installationDirectory)
{
    // There are two reasons we might need to elevate privileges in order to install.
    // One possibility is that we want to install as some other user (e.g., as 'root' or 'appowner' in a shared directory).
    // The other possibility is that we're trying to install in a directory which we don't have write access to.
    
    uid_t runningUID = getuid();
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Use access(), which handles groups, ACLs, blah blah.
    if(access([fileManager fileSystemRepresentationWithPath:installationDirectory], (R_OK | W_OK))) {
        if (errno == EACCES) {
            NSLog(@"Running user (id %u) cannot write to installation directory '%@'.  Will perform authenticated installation.", (unsigned)runningUID, installationDirectory);
            return YES;
        } else {
            NSLog(@"Warning: installation may fail; access(%@): %s", installationDirectory, strerror(errno));
        }
    }
    
    if (![fileManager isWritableFileAtPath:installationDirectory]) {
        NSLog(@"Installation folder '%@' is not writable.  Will perform authenticated installation.", installationDirectory);
        return YES;
    }
    
    return NO;
}

static BOOL _NeedsPrivilegedInstall_Ownership(uid_t destinationUID, gid_t destinationGID)
{
    // There are two reasons we might need to elevate privileges in order to install.
    // One possibility is that we want to install as some other user (e.g., as 'root' or 'appowner' in a shared directory).
    // The other possibility is that we're trying to install in a directory which we don't have write access to.
    
    uid_t runningUID = getuid();
    
    if (destinationUID != runningUID) {
        NSLog(@"Running user has uid %d but we want to install as owner uid %d.  Will perform authenticated installation.", runningUID, destinationUID);
        return YES;
    }
    
    // Directories with the sticky bit set, like /Applications, can result in installed applications having one of our supplementary GIDs.
    if (!_IsInGroupList(destinationGID)) {
        NSLog(@"Running user has gid %d but we want to install as group id %d.  Will perform authenticated installation.", getgid(), destinationGID);
        return YES;
    }
    
    return NO;
}

static BOOL _PerformNormalInstall(NSArray *installerArguments, NSError **outError);
static BOOL _PerformPrivilegedInstall(NSArray *installerArguments, NSData *authorizationData, NSError **outError);

static CSIdentityRef _CopyCSIdentityFromPosixID(id_t posixID, CSIdentityClass identityClass)
{
    CSIdentityRef result = NULL;
    CSIdentityQueryRef query = CSIdentityQueryCreateForPosixID(kCFAllocatorDefault, posixID, identityClass, CSGetDefaultIdentityAuthority());

    if (CSIdentityQueryExecute(query, kCSIdentityQueryIncludeHiddenIdentities, NULL)) {
        CFArrayRef identities = CSIdentityQueryCopyResults(query);
        if (CFArrayGetCount(identities) > 0) {
            result = (CSIdentityRef)CFArrayGetValueAtIndex(identities, 0);
            CFRetain(result);
        } else {
            result = NULL;
        }
        CFRelease(identities);
    }

    CFRelease(query);
    
    return result;
}

// Try to guess what uid and gid the user expects the installed version to be owned by.
// This is all pretty heuristic; what we mostly do is imitate the old version's ownership if it's owned by a system user, but if it's owned by a normal user, just install as us.
static void _CheckInstallAsOtherUser(const struct stat *sbuf, uid_t *as_uid, gid_t *as_gid)
{
    uid_t destinationUID = sbuf->st_uid;
    gid_t destinationGID = sbuf->st_gid;
    
    if (destinationUID != *as_uid) {
        // If it's owned by a special user, install the new version as that user. Otherwise, assume it should be owned by whoever installs it.
        CSIdentityRef owner = _CopyCSIdentityFromPosixID(destinationUID, kCSIdentityClassUser);
        if (owner != NULL && CSIdentityIsHidden(owner)) {
            *as_uid = destinationUID;
            *as_gid = destinationGID;  // TODO: Only do this if group matches owner? Need actual use case info
        }
        
        if (owner != NULL) {
            CFRelease(owner);
        }
    } else {
        // If it's owned by us, but by one of our supplementary group IDs, chown to the same supplementary gid when we install it.
        // (If it's owned by us but group-ownership is some group we're not in, don't bother elevating privs to install, just install as us)
        if (destinationUID == getuid()) {
            if (_IsInGroupList(destinationGID)) {
                *as_gid = destinationGID;
            }
        }
    }
}

static void _CheckInstallWithFlags(const char *posixPath, const struct stat *sbuf, BOOL *setImmutable, BOOL *authRequired)
{
    // Deal with the immutable flag (aka the Finder's "Locked" checkbox)
    if (sbuf->st_flags & (UF_IMMUTABLE|UF_APPEND|SF_IMMUTABLE|SF_APPEND)) {
        char *flagsstr = fflagstostr(sbuf->st_flags);
        NSLog(@"existing file's flags = %s", flagsstr);
        free(flagsstr);
        
        *setImmutable = YES;
        
        // Can we turn off the immutable bit ourselves? If so, no need to authenticate.
        if (chflags(posixPath, sbuf->st_flags & ~(UF_IMMUTABLE|UF_APPEND|SF_IMMUTABLE|SF_APPEND)) == 0) {
            // Hooray.
        } else {
            *authRequired = YES;
            NSLog(@"  (Will perform authenticated installation to change flags.)");
        }
    }
}

- (BOOL)_validateInstallerArguments:(NSDictionary *)arguments error:(NSError **)error;
{
    NSArray *keys = @[
        OSUInstallerUnpackedApplicationPathKey,
        OSUInstallerInstallationDirectoryPathKey,
        OSUInstallerCurrentlyInstalledVersionPathKey,
        OSUInstallerInstallationNameKey,
    ];
    
    for (NSString *key in keys) {
        id value = arguments[key];
        if ([NSString isEmptyString:value]) {
            NSString *format = NSLocalizedStringFromTableInBundle(@"\"%@\" is required, but was missing from the installer arguments.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error required argument is missing");
            NSString *description = [NSString stringWithFormat:format, key];
            OSUError(error, OSURequiredArgumentMissing, description, nil);
            return NO;
        }
    }

    return YES;
}

- (BOOL)_unpackInstallerArguments:(NSDictionary *)arguments error:(NSError **)error;
{
    if (![self _validateInstallerArguments:arguments error:error]) {
        return NO;
    }

    self.authorizationData = arguments[OSUInstallerInstallationAuthorizationDataKey];
    self.unpackedPath = arguments[OSUInstallerUnpackedApplicationPathKey];
    self.installationDirectory = arguments[OSUInstallerInstallationDirectoryPathKey];
    self.installedVersionPath = arguments[OSUInstallerCurrentlyInstalledVersionPathKey];
    self.installationName = arguments[OSUInstallerInstallationNameKey];
    
    return YES;
}

- (BOOL)_prepareTrampolineTool:(NSError **)error;
{
    OBPRECONDITION(self.trampolineToolPath == nil);
    if (self.trampolineToolPath != nil) {
        return YES;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *trampolineToolPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Helpers/OSULaunchTrampoline"];

    NSString *tempTrampolineToolPath = [temporaryDirectory stringByAppendingPathComponent:[trampolineToolPath lastPathComponent]];
    tempTrampolineToolPath = [fileManager uniqueFilenameFromName:tempTrampolineToolPath allowOriginal:YES create:NO error:error];
    
    if (![fileManager copyItemAtPath:trampolineToolPath toPath:tempTrampolineToolPath error:error]) {
        return NO;
    }
    
    self.trampolineToolPath = tempTrampolineToolPath;

    return YES;
}

- (BOOL)_installUpdateWithOptions:(OSUInstallerServiceUpdateOptions)options requiresPrivilegedInstall:(BOOL *)outRequiresPrivilegedInstall error:(NSError **)outError;
{
    OBPRECONDITION(_unpackedPath);
    OBPRECONDITION(_installationDirectory);
    OBPRECONDITION(_installationName);

    BOOL dryRun = (options & OSUInstallerServiceUpdateOptionDryRun) != 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (outRequiresPrivilegedInstall != NULL) {
        *outRequiresPrivilegedInstall = NO;
    }

#ifdef DEBUG
    NSLog(@"existingVersionPath = %@", _installedVersionPath);
    NSLog(@"unpackedPath = %@", _unpackedPath);
    NSLog(@"installationDirectory = %@", _installationDirectory);
    NSLog(@"installationName = %@", _installationName);
#endif
    
    // The path at which the new application will end up
    NSString *finalInstalledPath = [_installationDirectory stringByAppendingPathComponent:_installationName];
    
    // Are we going to rename something (an existing version)? If so, what are we renaming it to?
    // Are we going to keep the installed version? (Which may or may not be the existing version.)
    BOOL keepExistingVersion = NO;
    BOOL keepInstalledVersion = YES; 
    NSString *pathToArchive = nil;
    NSString *archivePath = nil;

    BOOL requiresPrivilegedInstall = NO;  // Are we going to need to authenticate/escalate privileges in order to install?
    
    // UID, GID, and uimmutable settings for the new application
    uid_t destinationUID = getuid();
    gid_t destinationGID = getgid();
    BOOL setImmutable = NO;
    
    // Our theory here is that if we're installing in the same directory as the existing version, we're "replacing" it and should imitate its ownership, otherwise we're just installing as us.
    if ([_installationDirectory isEqualToString:[_installedVersionPath stringByDeletingLastPathComponent]]) {
        struct stat dest_stat;
        bzero(&dest_stat, sizeof(dest_stat));
        const char *posixPath = [_installedVersionPath fileSystemRepresentation];
        
        if (stat(posixPath, &dest_stat) == 0) {
            // Decide whether we should chown the app to some other uid or gid
            _CheckInstallAsOtherUser(&dest_stat, &destinationUID, &destinationGID);
            _CheckInstallWithFlags(posixPath, &dest_stat, &setImmutable, &requiresPrivilegedInstall);
            
            pathToArchive = _installedVersionPath;
        }
    }
    
    if (![_installedVersionPath isEqualToString:finalInstalledPath]) {
        // Otherwise, check if we're *literally* replacing some file that *isn't* us.

        // Remove the installed version, since the new version is going to have a different name
        keepInstalledVersion = NO;

        // Since we aren't updating ourselves in place, keep/archive the existing version if finalInstalledPath already exists. It isn't us.
        if ([fileManager fileExistsAtPath:finalInstalledPath]) {
            keepExistingVersion = YES;
        }
        
        struct stat dest_stat;
        bzero(&dest_stat, sizeof(dest_stat));
        const char *posixPath = [finalInstalledPath fileSystemRepresentation];
        
        if (stat(posixPath, &dest_stat) == 0) {
            // Decide whether we should chown the app to some other uid or gid
            _CheckInstallAsOtherUser(&dest_stat, &destinationUID, &destinationGID);
            _CheckInstallWithFlags(posixPath, &dest_stat, &setImmutable, &requiresPrivilegedInstall);

            // Can we simply trash the other guy now? Can we, can we? Huh boss? Can we?
            BOOL doArchiveDance = YES;
            
            if (!keepExistingVersion) {
                if (dryRun) {
                    if ([fileManager isDeletableFileAtPath:finalInstalledPath]) {
                        doArchiveDance = NO;
                    }
                } else {
                    if (_PerformTrashFile(finalInstalledPath, @"other version", requiresPrivilegedInstall, self.authorizationData)) {
                        doArchiveDance = NO;
                    }
                }
            }
            
            if (doArchiveDance) {
                // Nah, gotta do the archive dance
                if (pathToArchive != nil && keepInstalledVersion) {
                    NSLog(@"OmniSoftwareUpdate: Not sure whether I should archive %@ or %@. Choosing %@.", [_installedVersionPath lastPathComponent], [finalInstalledPath lastPathComponent], [finalInstalledPath lastPathComponent]);
                }
                
                pathToArchive = finalInstalledPath;
            }
        }
    }
    
    // Choose a name for the file we're moving aside (archiving)
    if (pathToArchive) {
#ifdef DEBUG
        NSLog(@"pathToArchive = %@", pathToArchive);
#endif
        archivePath = [self _chooseAsideNameForFile:pathToArchive];
        archivePath = [fileManager uniqueFilenameFromName:archivePath allowOriginal:YES create:NO error:outError];
        if (archivePath == nil) {
            return NO;
        }
#ifdef DEBUG
        NSLog(@"archivePath = %@", archivePath);
#endif
    } else {
        archivePath = nil;
    }
    
    // Installer script arguments: what to install from, where to install it, and where to put stderr
    NSMutableArray *installerArguments = [NSMutableArray arrayWithObjects:_unpackedPath, finalInstalledPath, nil];
    
    // Note that the install script doesn't use a real getopt, so the ordering of all the arguments and options is fixed
    
    // If we want to change the ownership of the file, pass the -u flag
    NSString *ugid = (destinationUID == getuid())? @"" : [NSString stringWithFormat:@"%u", destinationUID];
    if (destinationGID != getgid()) {
        ugid = [ugid stringByAppendingFormat:@":%u", destinationGID];
    }
    
    if (![NSString isEmptyString:ugid]) {
        [installerArguments addObjects:@"-u", ugid, nil];
    }
    
    // Check for some other reasons we'll need to authenticate/escalate privileges.
    if (_NeedsPrivilegedInstall_DestDir(_installationDirectory)) {
        requiresPrivilegedInstall = YES;
    }

    if (_NeedsPrivilegedInstall_Ownership(destinationUID, destinationGID)) {
        requiresPrivilegedInstall = YES;
    }
    
    // If we want to archive the existing version, pass the -a flag
    if (pathToArchive != nil && archivePath != nil) {
        [installerArguments addObjects:@"-a", pathToArchive, archivePath, nil];
        
        // Even though we're just moving the old version, we'll need write permission in order to do so
        // (the UNIX reason for this is that we need access to modify the '..' entry in its directory but I'm guessing that that's just historical at this point)
        if (!requiresPrivilegedInstall && ![fileManager isWritableFileAtPath:pathToArchive]) {
            NSDictionary *movingAttributes = [fileManager attributesOfItemAtPath:pathToArchive error:NULL];
            BOOL unwritable = YES;
            
            if (movingAttributes != nil) {
                // Perhaps we can make it writable, move it aside, then restore its original permissions?
                NSUInteger oldMode = [movingAttributes filePosixPermissions];
                if ((oldMode & (S_IWUSR|S_IXUSR)) != (S_IWUSR|S_IXUSR) && [fileManager setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:(oldMode | (S_IWUSR|S_IXUSR))] forKey:NSFilePosixPermissions] ofItemAtPath:pathToArchive error:NULL]) {
                    [installerArguments addObjects:@"-am", [NSString stringWithFormat:@"0%o", (unsigned int)oldMode], nil];
                    unwritable = NO;
                } else {
                    unwritable = YES;
                }
            }
            
            if (unwritable) {
                NSLog(@"Installed path '%@' is not writable.  Will request privileges so that we can move it aside.", pathToArchive);
                requiresPrivilegedInstall = YES;
            }
        }
    }
    
    // If the user had the immutable flag set ("locked" file) then pass -f.
    // As a side effect this will tell the script to try unlocking the old version.
    if (setImmutable) {
        [installerArguments addObjects:@"-f", @"uchg", nil];
    }
    
#ifdef DEBUG
    NSLog(@"[%@auth%@] <INSTALLER_SCRIPT> %@", (dryRun ? @"dry-run " : @""), (requiresPrivilegedInstall ? @"" : @"no"), [installerArguments componentsJoinedByString:@" "]);
#endif
    
    BOOL success = NO;

    if (!dryRun) {
        if (requiresPrivilegedInstall) {
            success = _PerformPrivilegedInstall(installerArguments, self.authorizationData, outError);
        } else {
            success = _PerformNormalInstall(installerArguments, outError);
        }
        
        // If we moved something aside, but don't want to keep it, then move it to the trash now.
        if (success) {
            if (archivePath != nil && !keepExistingVersion) {
                _PerformTrashFile(archivePath, @"previous version", requiresPrivilegedInstall, self.authorizationData);
            }
            
            if ([fileManager fileExistsAtPath:_installedVersionPath] && !keepInstalledVersion) {
                _PerformTrashFile(_installedVersionPath, @"previous version", requiresPrivilegedInstall, self.authorizationData);
            }
        }
    } else {
        success = YES;
    }
    
    if (outRequiresPrivilegedInstall != NULL) {
        *outRequiresPrivilegedInstall = requiresPrivilegedInstall;
    }

    return success;
}

- (NSString *)_chooseAsideNameForFile:(NSString *)existingFile;
{
    if (existingFile == nil) {
        return nil;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *info = [fileManager attributesOfItemAtPath:existingFile error:NULL];
    if (info == nil) {
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
    NSBundle *bundle = [NSBundle bundleWithPath:self.installedVersionPath];
    NSDictionary *selfInfo = [fileManager attributesOfItemAtPath:[bundle bundlePath] error:NULL];
    NSDictionary *bundleInfoDictionary = nil;

    if (selfInfo != nil && [selfInfo isEqual:info]) {
        bundleInfoDictionary = [bundle infoDictionary];
    } else {
        // If the destination file isn't a valid bundle, this will set bundleVersion to nil, which is what we want.
        NSBundle *tryBundle = [NSBundle bundleWithPath:existingFile];
        bundleInfoDictionary = [tryBundle infoDictionary];
    }

    NSString *marketingVersion = [bundleInfoDictionary objectForKey:@"CFBundleShortVersionString"];
    if (![NSString isEmptyString:marketingVersion]) {
        bundleVersion = marketingVersion;
    } else {
        bundleVersion = [bundleInfoDictionary objectForKey:(NSString *)kCFBundleVersionKey];
    }
    
    NSString *newName = nil;
    NSString *oldName = [existingFile lastPathComponent];
    NSString *oldBasename = nil;
    NSString *oldExtension = nil;
    
    // Treat the .app extension specially (we should always have one of those).
    // We don't want to end up with .x.y.z.app in the case that there is already a version number there.

    if ([oldName hasSuffix:@".app"]) {
        oldBasename = [oldName substringToIndex:[oldName length] - 4];
        oldExtension = @"app";
    } else {
        OBASSERT_NOT_REACHED("Updating something without a .app suffix?");
        oldBasename = [oldName stringByDeletingPathExtension];
        oldExtension = [oldName pathExtension];
    }

    if (![NSString isEmptyString:bundleVersion]) {
        // If the old basename already has a version number appended to it, remove it before we append our version number
        __autoreleasing NSError *error = nil;
        NSString *patternString = @"\\s?(\\d+-)?\\d+[\\.\\d+]*$";
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:patternString options:NSRegularExpressionAnchorsMatchLines error:&error];
        if (regex != nil) {
            NSTextCheckingResult *result = [regex firstMatchInString:oldBasename options:0 range:NSMakeRange(0, [oldBasename length])];
            if (result != nil) {
                oldBasename = [oldBasename substringToIndex:result.range.location];
            }
        } else {
            NSLog(@"Error compiling regex: %@", error);
        }

        newName = [[oldBasename stringByAppendingFormat:@" %@", bundleVersion] stringByAppendingPathExtension:oldExtension];
    } else {
        // Our caller uniquifies the filename as needed. If we coudln't parse the version out of the bundle, return the old basename.
        OBASSERT_NOT_REACHED("Couldn't get the bundleVersion from the previously installed copy.");
        newName = oldBasename;
    }
    
    archivePath = [existingFileDir stringByAppendingPathComponent:newName];
    
    return archivePath;
}

static BOOL _PerformNormalInstall(NSArray *installerArguments, NSError **outError)
{
    NSBundle *localizationBundle = [NSBundle mainBundle];
    return [OSUInstallerScript runWithArguments:installerArguments localizationBundle:localizationBundle error:outError];
}

static BOOL _PerformPrivilegedInstall(NSArray *installerArguments, NSData *authorizationData, NSError **outError)
{
    __block BOOL installerSucceeded = NO;
    __block NSError *installerError = nil;
    __block BOOL hasReceivedResponseOrError = NO;
    
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:OSUInstallerPrivilegedHelperJobLabel options:NSXPCConnectionPrivileged];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUInstallerPrivilegedHelper)];
    [connection resume];
    
    id <OSUInstallerPrivilegedHelper> remoteProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        installerError = [error copy];
        hasReceivedResponseOrError = YES;
        [connection invalidate];
    }];
    
    NSURL *bundleURL = [[NSBundle mainBundle] bundleURL];
    [remoteProxy runInstallerScriptWithArguments:installerArguments localizationBundleURL:bundleURL authorizationData:authorizationData reply:^(BOOL success, NSError *error) {
        installerSucceeded = success;
        installerError = [error copy];
        hasReceivedResponseOrError = YES;
    }];
    
    // Block waiting for the installer to finish
    while (!hasReceivedResponseOrError) {
        NSTimeInterval pollInterval = 0.5;
        NSDate *limitDate = [NSDate dateWithTimeIntervalSinceNow:pollInterval];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:limitDate];
    }

    if (outError != nil) {
        *outError = [installerError copy];
    }
    
    [connection invalidate];
    
    return installerSucceeded;
}

static BOOL _PerformTrashFile(NSString *path, NSString *description, BOOL requiresPrivilegeEscallation, NSData *authorizationData)
{
    if (requiresPrivilegeEscallation) {
        return _PerformPrivilegedTrashFile(path, description, authorizationData);
    } else {
        __autoreleasing NSError *error = nil;
        NSString *basename = [path lastPathComponent];
        NSString *dirname = [path stringByDeletingLastPathComponent];
        NSURL *itemURL = [NSURL fileURLWithPath:path];

        if (![[NSFileManager defaultManager] trashItemAtURL:itemURL resultingItemURL:NULL error:&error]) {
            NSLog(@"Error moving %@ '%@' from '%@' to the trash: %@", description, basename, dirname, error);

            // The error will be NSCocoaErrorDomain/NSFeatureUnsupportedError if the volume doesn't have a trash can.
            // Try deleting it directly in this case.
            if (![[NSFileManager defaultManager] removeItemAtURL:itemURL error:&error]) {
                NSLog(@"Error trying to remove %@ at '%@': %@", description, [itemURL path], error);
                return NO;
            }
        }

        return YES;
    }
}

static BOOL _PerformPrivilegedTrashFile(NSString *path, NSString *description, NSData *authorizationData)
{
    __block BOOL trashFileSucceeded = NO;
    __block NSError *trashFileError = nil;
    __block BOOL hasReceivedResponseOrError = NO;
    
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:OSUInstallerPrivilegedHelperJobLabel options:NSXPCConnectionPrivileged];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUInstallerPrivilegedHelper)];
    [connection resume];
    
    id <OSUInstallerPrivilegedHelper> remoteProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        trashFileError = [error copy];
        hasReceivedResponseOrError = YES;
        [connection invalidate];
    }];
    
    NSURL *itemURL = [NSURL fileURLWithPath:path];

    __autoreleasing NSError *findURLError = nil;
    NSURL *trashDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:itemURL create:YES error:&findURLError];
    
    [remoteProxy removeItemAtURL:itemURL trashDirectoryURL:trashDirectoryURL authorizationData:authorizationData reply:^(BOOL success, NSError *error) {
        trashFileSucceeded = success;
        trashFileError = [error copy];
        hasReceivedResponseOrError = YES;
    }];
    
    // Block waiting for the operation to finish
    while (!hasReceivedResponseOrError) {
        NSTimeInterval pollInterval = 0.5;
        NSDate *limitDate = [NSDate dateWithTimeIntervalSinceNow:pollInterval];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:limitDate];
    }
    
    if (!trashFileSucceeded) {
        NSLog(@"Error trying to remove %@ at '%@': %@", description, path, trashFileError);
    }
    
    [connection invalidate];
    
    return trashFileSucceeded;
}

@end

#pragma mark -

@interface OSUInstallerServiceListener : NSObject <NSXPCListenerDelegate>

@end

#pragma mark -

@implementation OSUInstallerServiceListener

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection
{
    if (!OSUCheckConnectionAuditToken(connection)) {
        return NO;
    }

    // Each connection gets its own instance of an OSUInstallerService, since there is per instance data.
    // Typically, there is only ever one of these, and the host application will reuse a single connection. (Unless it was interrupted or invalidated.)
    OSUInstallerService *installerService = [[OSUInstallerService alloc] init];
    
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUInstallerService)];
    connection.exportedObject = installerService;
    [connection resume];

    return YES;
}

- (void)run;
{
    NSXPCListener *listener = [NSXPCListener serviceListener];
    listener.delegate = self;
    [listener resume];
}

@end

#pragma mark -

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        OSUInstallerServiceListener *listener = [[OSUInstallerServiceListener alloc] init];
        [listener run];
    }

    return 0;
}
