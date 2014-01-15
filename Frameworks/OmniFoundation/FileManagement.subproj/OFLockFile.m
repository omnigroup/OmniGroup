// Copyright 2007-2013 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFLockFile.h>

#if OF_LOCK_FILE_AVAILABLE

#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSPropertyList.h>
#import <sys/sysctl.h>

#import <ApplicationServices/ApplicationServices.h>

RCS_ID("$Id$");

// Somewhat inspired by the NSFileManager(OFExtensions), but with a cleaner API and support for sandboxing.

static NSString * const LockFileShortUserNameKey = @"login";
static NSString * const LockFileLongUserNameKey = @"user";
static NSString * const LockFileHostNameKey = @"host";
static NSString * const LockFileHostIdentifierKey = @"host_id";
static NSString * const LockFileProcessNumberKey = @"pid";
static NSString * const LockFileProcessLaunchDateKey = @"launchDate";
static NSString * const LockFileProcessBundleIdentifierKey = @"process_bundle_identifier";
static NSString * const LockFileLockDateKey = @"date";

static BOOL DebugLockFile = NO;
#define DEBUG_LOCKFILE(format, ...) do { \
    if (DebugLockFile) NSLog((format), ## __VA_ARGS__); \
} while(0)

static NSString * OFLockFileCancelRecoveryOption = nil;
static NSString * OFLockFileOverrideLockRecoveryOption = nil;

static id <OFLockUnavailableHandler> OFLockFileLockUnavailableHandler = nil;

@implementation OFLockFile
{
    BOOL _ownsLock; // At least, last we knew -- someone else can force the lock.
    BOOL _invalidated; // Someone has obliterated our lock; the contents we protect are now suspect.
    NSDictionary *_currentLockFileContents; // As of the last time we checked.
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    DebugLockFile = [[NSUserDefaults standardUserDefaults] boolForKey:@"DebugLockFile"];

    NSString *recoveryOption = nil;
    
    recoveryOption = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniFoundation", OMNI_BUNDLE, @"OFLockFile recovery option");
    OFLockFileCancelRecoveryOption = [recoveryOption copy];
    
    recoveryOption = NSLocalizedStringFromTableInBundle(@"Override Lock", @"OmniFoundation", OMNI_BUNDLE, @"OFLockFile recovery option");
    OFLockFileOverrideLockRecoveryOption = [recoveryOption copy];
}

+ (id <OFLockUnavailableHandler>)defaultLockUnavailableHandler;
{
    return OFLockFileLockUnavailableHandler;
}

+ (void)setDefaultLockUnavailableHandler:(id <OFLockUnavailableHandler>)handler;
{
    OBPRECONDITION(!handler || [handler conformsToProtocol:@protocol(OFLockUnavailableHandler)]);
    if (OFLockFileLockUnavailableHandler != handler) {
        [OFLockFileLockUnavailableHandler release];
        OFLockFileLockUnavailableHandler = [handler retain];
    }
}

+ (NSString *)localizedCannotCreateLockErrorReason;
{
    NSString *localizedCannotCreateLockErrorReason = nil;
    
    id <OFLockUnavailableHandler> lockUnavailableHandler = [self defaultLockUnavailableHandler];
    if (lockUnavailableHandler != nil && [lockUnavailableHandler respondsToSelector:@selector(localizedCannotCreateLockErrorReason)]) {
        localizedCannotCreateLockErrorReason = [lockUnavailableHandler localizedCannotCreateLockErrorReason];
    }

    return localizedCannotCreateLockErrorReason;
}

- (id)initWithURL:(NSURL *)lockFileURL;
{
    OBPRECONDITION(lockFileURL);
    OBPRECONDITION([lockFileURL isFileURL]);
    OBPRECONDITION(![lockFileURL isFileReferenceURL]);
    
    if (!(self = [super init]))
        return nil;
        
    _URL = [lockFileURL copy];
    DEBUG_LOCKFILE(@"Creating lock file at '%@'", lockFileURL);
    
    [self _readCurrentLockContents];
    
    return self;
}

- (void)dealloc;
{
    [self unlockIfLocked];
    
    [_URL release];
    [_currentLockFileContents release];
    [_lockUnavailableHandler release];
    
    [super dealloc];
}

// NOTE: This will re-write the lock file each time it is obtained, which will keep the lock fresh...  Need an option to not do that.
- (BOOL)lockWithOptions:(OFLockFileLockOperationOptions)options error:(NSError **)outError;
{
    BOOL override = (options & OFLockFileLockOperationOverrideLockOption) != 0;
    
    // Make sure the intervening directories exist.  Have to preemptively do this so the lock can live next to where the document *would* be, even if the document hasn't been created yet.
    if (![[NSFileManager defaultManager] createDirectoryAtURL:[_URL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:outError])
        return NO;

    NSDictionary *localLock = [self _localLockFileContents];
    if (_ownsLock)
        // Check whether we've been invalidated by someone else forcing the lock.  This calls -_readCurrentLockContents, indirectly.
        [self _checkForLockInvalidation:localLock];
    else
        [self _readCurrentLockContents];
    
    if (_invalidated) {
        // We are totally dead and the contents we lock are possibly changed on disk.  We don't necessarily know who overrode our lock since they may have done so & then quit, removing their lock (the absense of our lock indicates something bad happened just as much as the incorrect contents).
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Another application has overridden the lock at \"%@\".", @"OmniFoundation", OMNI_BUNDLE, @"error reason"), _URL];
        OFError(outError, OFLockInvalidated,
                 NSLocalizedStringFromTableInBundle(@"Unable to lock document.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), reason);
        return NO;
    }
    
    while (_currentLockFileContents) {
        // Check if this is a lock file that *we* previously wrote; that is, allow re-locking to update the lock with a new timestamp indicating our continued activity.
        if ([self _lockMatches:localLock otherLock:_currentLockFileContents]) {
            DEBUG_LOCKFILE(@"Existing lock matches our lock already '%@'", _URL);
            // Ignore the lock file contents and re-write it.
            [_currentLockFileContents release];
            _currentLockFileContents = nil;
            break;
        }
        
        // Check if this is a process from this host that has died.
        if ([[localLock objectForKey:LockFileHostIdentifierKey] isEqualToString:[_currentLockFileContents objectForKey:LockFileHostIdentifierKey]] ||
            [[localLock objectForKey:LockFileHostNameKey] isEqualToString:[_currentLockFileContents objectForKey:LockFileHostNameKey]]) {
            pid_t processNumber = [[_currentLockFileContents objectForKey:LockFileProcessNumberKey] intValue];
            if (processNumber > 0) {
                if (![self _processExistsWithProcessIdentifier:processNumber]) {
                    DEBUG_LOCKFILE(@"Existing lock seems to be from a dead process on this machine '%@'", _URL);
                    // Ignore the lock file contents -- the writer is dead.
                    [_currentLockFileContents release];
                    _currentLockFileContents = nil;
                    break;
                }

                // If the process exists, but the bundle identifier doesn't match the one in the lock file, it is not the process which took out the lock
                NSString *lockBundleIdentifier = [localLock objectForKey:LockFileProcessBundleIdentifierKey];
                NSString *pidBundleIdentifier = [self _bundleIdentifierForPID:processNumber];
                if (lockBundleIdentifier && pidBundleIdentifier && ![lockBundleIdentifier isEqualToString:pidBundleIdentifier]) {
                    DEBUG_LOCKFILE(@"Existing lock seems to be from a dead process on this machine '%@'", _URL);
                    // Ignore the lock file contents -- the writer is dead.
                    [_currentLockFileContents release];
                    _currentLockFileContents = nil;
                    break;
                }
                
                // Process exists, and bundle identifiers match. Probably even us.
                // But there's a chance the process ids reset: if we've rebooted and if we launch processes in same order (auto login, launch at login), it's not unusual to get the same pid.  If the clock was also reset, it might even have a launch date before its lock date.
                // Let's compare the launch date archived in the lock with the launch date of the live process, and if they don't match we'll know it's not the same process.
                NSDate *currentLockLaunchDate = [_currentLockFileContents objectForKey:LockFileProcessLaunchDateKey];
                if (currentLockLaunchDate != nil) {
                    NSDate *launchDateForLiveProcess = [self _launchDateForPID:processNumber];
                    if (OFNOTEQUAL(launchDateForLiveProcess, currentLockLaunchDate)) {
                        DEBUG_LOCKFILE(@"Existing lock seems to be from a dead process on this machine '%@'", _URL);
                        // Ignore the lock file contents -- the writer is dead.
                        [_currentLockFileContents release];
                        _currentLockFileContents = nil;
                        break;
                    }
                }
            }
        }

        if (override) {
            DEBUG_LOCKFILE(@"OVERRIDING lock '%@'", _URL);
            // Manually blowing the lock; good luck!
            [_currentLockFileContents release];
            _currentLockFileContents = nil;
            break;
        }
        
        id <OFLockUnavailableHandler> lockUnavailableHandler = [self _currentLockUnavailableHandler];
        if (lockUnavailableHandler != nil) {
            NSError *localError = nil;
            if (outError == NULL) {
                outError = &localError;
            }

            *outError = [self _errorForLockOperationWithOptions:options lockUnavailableHandler:lockUnavailableHandler existingLock:_currentLockFileContents proposedLock:localLock];

            if ([lockUnavailableHandler handleLockUnavailableError:*outError]) {
                // The lockUnavailableHandler returns YES if error recovery is done.
                // Loop again and override the lock
                override = YES;
                continue;
            }
        }

        // Nothing allowed us to ignore the current lock.
        //
        // Return an NSError instance with code OFLockUnavailable and recovery options if appropriate, other return OFCannotCreateLock

        if (outError != NULL) {
            *outError = [self _errorForLockOperationWithOptions:options lockUnavailableHandler:nil existingLock:_currentLockFileContents proposedLock:localLock];
        }

        return NO;
    }

    if (![[NSFileManager defaultManager] createDirectoryAtURL:[_URL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:outError]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to create directory for lock file at \"%@\".", @"OmniFoundation", OMNI_BUNDLE, @"error reason"), _URL];
        OFError(outError, OFCannotCreateLock, NSLocalizedStringFromTableInBundle(@"Unable to lock document.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), reason);
        return NO;
    }
    
    // Serialize to an NSData since NSData has NSError API.
    NSString *errorString = nil;
    NSData *lockData = [NSPropertyListSerialization dataFromPropertyList:localLock format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorString];
    if (!lockData) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to serialize lock information.  %@", @"OmniFoundation", OMNI_BUNDLE, @"error reason"), errorString];
        OFError(outError, OFCannotCreateLock, NSLocalizedStringFromTableInBundle(@"Unable to lock document.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), reason);
        return NO;
    }

    if (![lockData writeToURL:_URL options:NSAtomicWrite error:outError]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to write lock file.  %@", @"OmniFoundation", OMNI_BUNDLE, @"error reason"), [*outError localizedDescription]];
        OFError(outError, OFCannotCreateLock, NSLocalizedStringFromTableInBundle(@"Unable to lock document.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), reason);
        return NO;
    }
    
    _ownsLock = YES;
    [_currentLockFileContents release];
    _currentLockFileContents = [localLock copy];
    DEBUG_LOCKFILE(@"Lock written to %@ with contents %@", _URL, _currentLockFileContents);
    
    return YES;
}

- (void)unlockIfLocked;
{
    if (!_ownsLock)
        return;
    
    DEBUG_LOCKFILE(@"Destroying lock file at %@", _URL);
    
    // Check for lock invalidation so we don't remove someone else's lock if they forced ours
    NSDictionary *localLock = [self _localLockFileContents];
    [self _checkForLockInvalidation:localLock];
    
    if (!_ownsLock || _invalidated)
        return;
    
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:[_URL path]]) {
        OBASSERT_NOT_REACHED("We just checked for invalidation by another process...");
        return;
    }
    
    NSError *error = nil;
    if ([[NSFileManager defaultManager] removeItemAtURL:_URL error:&error]) {
        _ownsLock = NO;
        [_currentLockFileContents release];
        _currentLockFileContents = nil;
    } else {
        [error log:@"Error removing lock file at %@", _URL];
    }
}

- (BOOL)invalidated;
{
    return _invalidated;
}

- (NSString *)ownerLogin;
{
    return [_currentLockFileContents objectForKey:LockFileShortUserNameKey];
}

- (NSString *)ownerName;
{
    return [_currentLockFileContents objectForKey:LockFileLongUserNameKey];
}

- (NSString *)ownerHost;
{
    return [_currentLockFileContents objectForKey:LockFileHostNameKey];
}

- (NSNumber *)ownerProcessNumber;
{
    return [_currentLockFileContents objectForKey:LockFileProcessNumberKey];
}

- (NSString *)ownerProcessBundleIdentifier;
{
    return [_currentLockFileContents objectForKey:LockFileProcessBundleIdentifierKey];
}

- (NSDate *)ownerLockDate;
{
    return [_currentLockFileContents objectForKey:LockFileLockDateKey];
}

#pragma mark - NSObject(NSErrorRecoveryAttempting)

- (void)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex delegate:(id)delegate didRecoverSelector:(SEL)didRecoverSelector contextInfo:(void *)contextInfo;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex;
{
    if ([[error domain] isEqualToString:OFErrorDomain] && [error code] == OFLockUnavailable) {
        NSString *recoveryOption = [[[error userInfo] objectForKey:NSLocalizedRecoveryOptionsErrorKey] objectAtIndex:recoveryOptionIndex];
        if ([recoveryOption isEqualToString:OFLockFileOverrideLockRecoveryOption]) {
            // Override the lock
            DEBUG_LOCKFILE(@"Selected override in error recovery");
            return YES;
        }
    }

    return NO;
}

#pragma mark - Private

- (id <OFLockUnavailableHandler>)_currentLockUnavailableHandler;
{
    if (_lockUnavailableHandler != nil) {
        return _lockUnavailableHandler;
    }
    
    return [[self class] defaultLockUnavailableHandler];
}

- (NSError *)_errorForLockOperationWithOptions:(OFLockFileLockOperationOptions)options lockUnavailableHandler:(id <OFLockUnavailableHandler>)lockUnavailableHandler existingLock:(NSDictionary *)existingLock proposedLock:(NSDictionary *)proposedLock;
{
    NSError *error = nil;
    
    if (((options & OFLockFileLockOperationAllowRecoveryOption) != 0) || lockUnavailableHandler != nil) {
        NSString *reasonFormat = NSLocalizedStringFromTableInBundle(@"This lock was taken by %@ using the computer \"%@\" on %@ at %@.\n\nYou may override this lock, but doing so may cause the other application to lose data if it is still running.", @"OmniFoundation", OMNI_BUNDLE, @"error reason");
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to lock document.", @"OmniFoundation", OMNI_BUNDLE, @"error description");
        NSString *reason = [self _lockUnavailableErrorReasonWithFormat:reasonFormat];
        NSArray *recoveryOptions = @[OFLockFileOverrideLockRecoveryOption, OFLockFileCancelRecoveryOption];
        
        OFErrorWithInfo(&error, OFLockUnavailable, description, reason,
                        NSLocalizedRecoveryOptionsErrorKey, recoveryOptions,
                        NSRecoveryAttempterErrorKey, self,
                        @"OFLockExistingLock", existingLock,
                        @"OFLockProposedLock", proposedLock,
                        nil);
    } else {
        NSString *reason = [[self class] localizedCannotCreateLockErrorReason];
        if ([NSString isEmptyString:reason]) {
            NSString *reasonFormat = NSLocalizedStringFromTableInBundle(@"This lock was taken by %@ using the computer \"%@\" on %@ at %@.", @"OmniFoundation", OMNI_BUNDLE, @"error reason");
            reason = [self _lockUnavailableErrorReasonWithFormat:reasonFormat];
        }
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to lock document.", @"OmniFoundation", OMNI_BUNDLE, @"error description");
        OFErrorWithInfo(&error, OFCannotCreateLock, description, reason,
                        @"OFLockExistingLock", existingLock,
                        @"OFLockProposedLock", proposedLock,
                        nil);
    }
    
    return error;
}

- (NSString *)_lockUnavailableErrorReasonWithFormat:(NSString *)format;
{
    OBPRECONDITION(![NSString isEmptyString:format]);

    NSString *dateString = nil;
    NSString *timeString = nil;
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];

    [formatter setDateStyle:NSDateFormatterShortStyle];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    dateString = [formatter stringFromDate:[self ownerLockDate]];
    
    [formatter setDateStyle:NSDateFormatterNoStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    timeString = [formatter stringFromDate:[self ownerLockDate]];
    
    return [NSString stringWithFormat:format, self.ownerName, self.ownerHost, dateString, timeString];
}

- (NSDictionary *)_localLockFileContents;
{
    NSMutableDictionary *contents = [NSMutableDictionary dictionary];
    
    [contents setObject:OFUniqueMachineIdentifier() forKey:LockFileHostIdentifierKey defaultObject:nil];
    [contents setObject:OFHostName() forKey:LockFileHostNameKey defaultObject:nil];
    [contents setObject:NSUserName() forKey:LockFileShortUserNameKey defaultObject:nil];
    [contents setObject:NSFullUserName() forKey:LockFileLongUserNameKey defaultObject:nil];
    [contents setObject:[[NSProcessInfo processInfo] processNumber] forKey:LockFileProcessNumberKey defaultObject:nil];
    [contents setObject:[[NSBundle mainBundle] bundleIdentifier] forKey:LockFileProcessBundleIdentifierKey defaultObject:nil];
    [contents setObject:[self _launchDateForPID:getpid()] forKey:LockFileProcessLaunchDateKey defaultObject:nil];
    [contents setObject:[NSDate date] forKey:LockFileLockDateKey];
    
    return contents;
}

- (BOOL)_lockMatches:(NSDictionary *)lock otherLock:(NSDictionary *)otherLock;
{    
    if (![[lock objectForKey:LockFileHostIdentifierKey] isEqual:[otherLock objectForKey:LockFileHostIdentifierKey]])
        return NO;
    if (![[lock objectForKey:LockFileShortUserNameKey] isEqual:[otherLock objectForKey:LockFileShortUserNameKey]])
        return NO;
    if (![[lock objectForKey:LockFileProcessNumberKey] isEqual:[otherLock objectForKey:LockFileProcessNumberKey]])
        return NO;
    
    return YES;
}

- (void)_readCurrentLockContents;
{
    [_currentLockFileContents release];
    _currentLockFileContents = nil;
    
    // TODO: Read via the NSData methods and check for ENOENT instead of probe/read, which race anyway.
    if ([[NSFileManager defaultManager] fileExistsAtPath:[_URL path]]) {
        _currentLockFileContents = [[NSDictionary alloc] initWithContentsOfFile:[_URL path]];
        if (!_currentLockFileContents)
            _currentLockFileContents = [[NSDictionary alloc] init]; // someone has a bogus lock out there, at any rate, it isn't our lock and someone tried to lock it.
    }
    
    DEBUG_LOCKFILE(@"Lock file contents at %@ is %@", _URL, _currentLockFileContents);
}

- (void)_checkForLockInvalidation:(NSDictionary *)localLock;
{
    // If we didn't obtain the lock at some point, we can't be invalidated.
    if (!_ownsLock)
        return;

    [self _readCurrentLockContents];
    
    // We don't require full dictionary equality (particularly the date).  Just the pid and host identifier are considered.
    if (!_currentLockFileContents || // someone might have overridden the lock and then removed it.
        OFNOTEQUAL([_currentLockFileContents objectForKey:LockFileProcessNumberKey], [localLock objectForKey:LockFileProcessNumberKey]) ||
        OFNOTEQUAL([_currentLockFileContents objectForKey:LockFileHostIdentifierKey], [localLock objectForKey:LockFileHostIdentifierKey])) {
        // We had the lock and now someone else does!
        _ownsLock = NO;
        _invalidated = YES;
        NSLog(@"Lock at '%@' invalidated.", _URL);
        NSLog(@"Expected: %@", localLock);
        NSLog(@"Found: %@", _currentLockFileContents);
    }
}

- (BOOL)_processExistsWithProcessIdentifier:(pid_t)pid;
{
    // We used to use kill(0) to signal the process. If we got back a return code of -1/ESRCH, we knew there was no process with that pid.
    //
    // Sending signals between processes is restricted when sandboxed.
    //
    // In practice, under the application sandbox:
    //
    //     kill returns -1/EPERM if the process is running and we are sandboxed
    //     kill returns 0 if the process is running and we are not sandboxed
    //
    // This is enough to determine if the process is running, but Apple has been pretty explicit about not relying on, or trying to infer much about state, from the result codes when an operation is denied by sandboxd.
    //
    // Since we can look up the process in the process table to determine if it exists, lets do that instead.
    //
    // If the process we find is a zombie, ignore it.
    // If we find a process in the exiting state, ignore it.
    
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid, 0};
    struct kinfo_proc kp = {};
    size_t length = sizeof(kp);
    
    int rc = sysctl((int *)mib, 4, &kp, &length, NULL, 0);
    if (rc != -1 && length == sizeof(kp)) {
        if (((kp.kp_proc.p_stat & SZOMB) != 0) || ((kp.kp_proc.p_flag & P_WEXIT) != 0)) {
            // This process is a zombie, or exiting (possibly a zombie).
            return NO;
        }
        return YES;
    }
    
    return NO;
}

- (NSString *)_bundleIdentifierForPID:(pid_t)pid;
{
#if 1
    ProcessSerialNumber psn = {0};
    
    OSStatus stat = GetProcessForPID(pid, &psn);
    if (stat != noErr) {
        NSLog(@"Error getting process info for pid %d: GetProcessForPID returned %d", pid, stat);
        return nil;
    }
    
    NSDictionary *infoDict = CFBridgingRelease(ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask));
    if (!infoDict) {
        NSLog(@"Error copying process info for pid %d: ProcessInformationCopyDictionary returned NULL", pid);
        return nil;
    }
    
    NSString *bundleIdentifier = infoDict[(OB_BRIDGE NSString *)kCFBundleIdentifierKey];
    if (!bundleIdentifier) {
        NSLog(@"ProcessInformationCopyDictionary returned a dictionary without a bundle identifier: %@", infoDict);
        return nil;
    }
    
    return bundleIdentifier;
#else
    NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    return [runningApplication bundleIdentifier];
#endif
}

- (NSDate *)_launchDateForPID:(pid_t)pid;
{
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid, 0};
    struct kinfo_proc kp = {};
    size_t length = sizeof(kp);
    
    int rc = sysctl((int *)mib, 4, &kp, &length, NULL, 0);
    if (rc != -1 && length == sizeof(kp)) {
        return [NSDate dateWithTimeIntervalSince1970:kp.kp_proc.p_starttime.tv_sec];
    }
    
    return nil;
}

@end

#endif // OF_LOCK_FILE_AVAILABLE
