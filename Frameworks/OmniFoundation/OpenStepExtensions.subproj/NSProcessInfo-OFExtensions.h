// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSProcessInfo.h>

@class NSNumber;

@interface NSProcessInfo (OFExtensions)

- (NSNumber *)processNumber;
    // Returns a number uniquely identifying the current process among those running on the same host.

- (BOOL)isSandboxed;
    // Indicates whether the current process is sandboxed (either directly, or via a sandbox inherited from a parent process).

- (NSDictionary *)codeSigningInfoDictionary;
    // Various pieces of information extraced from the code signature for this process's main bundle.
    // See Security/SecCode.h for the dictionary keys

- (NSDictionary *)codeSigningEntitlements;
    // The code signing entitlements for this process for this process's main bundle.
    // These will not reflect any entitlements you've inherited from your parent process.

- (NSDictionary *)effectiveCodeSigningEntitlements:(NSError **)outError;
    // The effective code signing entitlements for this process.
    // If this process is running in an inherited sandbox, we'll try to grab the signing entitlements for the directly sandboxed parent.
    // This may not be possible if the parent process is no longer running.
    // rdar://problem/13255969 requests a direct way to inspect the effective signing entitlements for the current process.

@property(nonatomic,readonly) NSString *codeSigningTeamIdentifier;

@end
