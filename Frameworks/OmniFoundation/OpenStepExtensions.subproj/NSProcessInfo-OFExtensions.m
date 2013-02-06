// Copyright 1997-2005, 2007, 2010, 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#import <Security/SecCode.h> // For SecCodeCopySelf()
#import <Security/SecRequirement.h> // For SecRequirementCreateWithString()

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
+ (void)performPosing;
{
    _original_hostName = (typeof(_original_hostName))OBReplaceMethodImplementation(self, @selector(hostName), (IMP)_replacement_hostName);
}
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
        NSDictionary *dict = [[NSFileManager defaultManager] codeSigningEntitlementsForURL:applicationURL error:&error];
        if (dict == nil) {
            NSLog(@"Error retrieving code signing information for current process: %@", error);
        } else {
            codeSigningEntitlements = [dict copy];
        }
    });
    
    return codeSigningEntitlements;
}


@end
