// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#import <Security/SecCode.h> // For SecCodeCopySelf()
#import <Security/SecRequirement.h> // For SecRequirementCreateWithString()

#import <libproc.h>
#import <sys/sysctl.h>

// This is not included in OmniBase.h since system.h shouldn't be used except when covering OS specific behaviour
#import <OmniBase/system.h>
#import <OmniBase/assertions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/OFVersionNumber.h>

RCS_ID("$Id$")

@implementation NSProcessInfo (OFExtensions)

#ifdef OMNI_ASSERTIONS_ON

static NSString *(*_original_hostName)(NSProcessInfo *self, SEL _cmd) = NULL;
static NSString *_replacement_hostName(NSProcessInfo *self, SEL _cmd)
{
    OBASSERT_NOT_REACHED("Do not call -[NSProcessInfo hostName] as it may hang with a long timeout if reverse DNS entries for the host's IP aren't configured.  Use OFHostName() instead.");
    return _original_hostName(self, _cmd);
}
OBPerformPosing(^{
    Class self = objc_getClass("NSProcessInfo");
    _original_hostName = (typeof(_original_hostName))OBReplaceMethodImplementation(self, @selector(hostName), (IMP)_replacement_hostName);
});
#endif

- (NSNumber *)processNumber;
{
    // Don't assume the pid is 16 bits since it might be 32.
    return [NSNumber numberWithInt:getpid()];
}

- (NSURL *)_processBundleOrMainExecutableURL;
{
    // If this looks like a traditional bundle, return the main bundle's URL, otherwise return the main executable URL so that SecStaticCodeCreateWithPath does the right thing for command line tools
    static NSURL *url = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *mainExecutableURL = [[NSBundle mainBundle] executableURL];
        NSURL *executableContainer = [mainExecutableURL URLByDeletingLastPathComponent];
        if ([[executableContainer lastPathComponent] isEqualToString:@"MacOS"] && [[[executableContainer URLByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Contents"]) {
            url = [[[NSBundle mainBundle] bundleURL] copy];
        } else {
            url = [mainExecutableURL copy];
        }
    });

    return url;
}

- (BOOL)isSandboxed;
{
    // N.B. Using the method in our NSFileManager extensions could possibly return a different answer than using the SecCodeCopySelf that was previously here, but we likely don't care about those cases.
    static BOOL isSandboxed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSError *error = nil;
        NSURL *applicationURL = [self _processBundleOrMainExecutableURL];
        if (![[NSFileManager defaultManager] getSandboxed:&isSandboxed forApplicationAtURL:applicationURL error:&error]) {
            NSLog(@"Error determining if current process is sandboxed (assuming YES): %@", error);
            isSandboxed = YES;
        }
        
        if (!isSandboxed) {
            // If we aren't directly sandboxed, we may have inherited a sandbox (implicitly) from our parent process.
            // There is, unfortunately, no direct way to capture this information, so we look at the environment.
            isSandboxed = ([[self environment] objectForKey:@"APP_SANDBOX_CONTAINER_ID"] != nil);
        }
    });

    return isSandboxed;
}

- (NSDictionary *)codeSigningInfoDictionary;
{
    static NSDictionary *codeSigningInfoDictionary = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSError *error = nil;
        NSURL *applicationURL = [self _processBundleOrMainExecutableURL];
        NSDictionary *dict = [[NSFileManager defaultManager] codeSigningInfoDictionaryForURL:applicationURL error:&error];
        if (dict == nil) {
            NSLog(@"Error retrieving code signing information for current process: %@", error);
        } else {
            codeSigningInfoDictionary = [dict copy];
        }
    });

    return codeSigningInfoDictionary;
}

- (NSDictionary *)codeSigningEntitlements;
{
    static NSDictionary *codeSigningEntitlements = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSError *error = nil;
        NSURL *applicationURL = [self _processBundleOrMainExecutableURL];
        NSDictionary *entitlements = [[NSFileManager defaultManager] codeSigningEntitlementsForURL:applicationURL error:&error];
        if (entitlements == nil) {
            NSLog(@"Error retrieving code signing information for current process: %@", error);
        } else {
            codeSigningEntitlements = [entitlements copy];
        }
    });
    
    return codeSigningEntitlements;
}

static pid_t _GetParentProcessIdentifierForProcessIdentifier(pid_t pid, NSError **error)
{
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid, 0};
    struct kinfo_proc kp = {};
    size_t length = sizeof(kp);
    
    int rc = sysctl((int *)mib, 4, &kp, &length, NULL, 0);
    if (rc != -1 && length == sizeof(kp)) {
        return kp.kp_eproc.e_ppid;
    }
    
    if (error != NULL) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    }
    
    return -1;
}

static NSString * _GetProcessPathname(pid_t pid, NSError **error)
{
    static char buffer[PROC_PIDPATHINFO_MAXSIZE];
    int rc = proc_pidpath(pid, buffer, PROC_PIDPATHINFO_MAXSIZE);
    if (rc == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return nil;
    }

    return [[[NSString alloc] initWithBytes:buffer length:rc encoding:NSUTF8StringEncoding] autorelease];
}

static NSURL * _BundleOrMainExecutableURLFromProcessExecutablePath(NSString *executablePath)
{
    NSURL *url = nil;
    NSURL *mainExecutableURL = [NSURL fileURLWithPath:executablePath];
    NSURL *executableContainer = [mainExecutableURL URLByDeletingLastPathComponent];

    if ([[executableContainer lastPathComponent] isEqualToString:@"MacOS"] && [[[executableContainer URLByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Contents"]) {
        url = [[executableContainer URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]; // Drop "Contents/MacOS"
    } else {
        url = [[mainExecutableURL copy] autorelease];
    }

    return url;
}

static BOOL _IsInheritedSandbox(NSDictionary *entitlements)
{
    // This function assumes you aready know you are sandboxed.
    // The sandbox is inherited if there is an explicit com.apple.security.inherit=YES, or if com.apple.security.app-sandbox is missing.
    
    id value = nil;
    
    value = entitlements[@"com.apple.security.app-sandbox"];
    if (value == nil) {
        return YES;
    }

    value = entitlements[@"com.apple.security.inherit"];
    if ([value boolValue]) {
        return YES;
    }

    return NO;
}

- (NSDictionary *)effectiveCodeSigningEntitlements:(NSError **)outError;
{
    static NSDictionary *effectiveCodeSigningEntitlements = nil;
    static NSError *entitlementsError = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSError *error = nil;
        NSURL *applicationURL = [self _processBundleOrMainExecutableURL];
        NSDictionary *entitlements = [[NSFileManager defaultManager] codeSigningEntitlementsForURL:applicationURL error:&error];
        if (entitlements != nil) {
            if ([self isSandboxed]) {
                BOOL isInheritedSandbox = _IsInheritedSandbox(entitlements);
                pid_t pid = getpid();
                while (isInheritedSandbox) {
                    pid_t parentPID = _GetParentProcessIdentifierForProcessIdentifier(pid, &error);
                    if (parentPID == -1)
                        break;
                    
                    NSString *executablePath = _GetProcessPathname(parentPID, &error);
                    if (executablePath == nil)
                        break;
                    
                    NSURL *url = _BundleOrMainExecutableURLFromProcessExecutablePath(executablePath);
                    OBASSERT(url != nil);
                    entitlements = [[NSFileManager defaultManager] codeSigningEntitlementsForURL:url error:&error];
                    if (entitlements == nil)
                        break;

                    isInheritedSandbox = _IsInheritedSandbox(entitlements);
                    pid = parentPID;
                }
            }

            if (entitlements != nil) {
                effectiveCodeSigningEntitlements = [entitlements copy];
            } else {
                entitlementsError = [error copy];
            }
        }
    });
    
    if (effectiveCodeSigningEntitlements == nil && outError != NULL) {
        *outError = entitlementsError;
    }
    
    return effectiveCodeSigningEntitlements;
}

- (NSString *)codeSigningTeamIdentifier;
{
    return [self codeSigningInfoDictionary][(NSString *)kSecCodeInfoTeamIdentifier];
}

@end
