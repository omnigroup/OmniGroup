// Copyright 2001-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUConnectionAudit.h"

#import <Kernel/kern/cs_blobs.h>

// Based on <https://blog.obdev.at/what-we-have-learned-from-a-vulnerability/>

NS_ASSUME_NONNULL_BEGIN

@interface NSXPCConnection(PrivateAuditToken)

// This property exists, but it's private. Make it available:
@property (nonatomic, readonly) audit_token_t auditToken;

@end

BOOL OSUCheckConnectionAuditToken(NSXPCConnection *connection)
{
    audit_token_t auditToken = connection.auditToken;
    NSData *tokenData = [NSData dataWithBytes:&auditToken length:sizeof(audit_token_t)];
    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributeAudit : tokenData};
    OSStatus status;

    SecCodeRef code = NULL;

    status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &code);
    if (status != errSecSuccess) {
        NSLog(@"%s: SecCodeCopyGuestWithAttributes returned %d", __func__, status);
        return NO;
    }

    // Before checking the requirement make sure that code signing flags
    // CS_HARD and CS_KILL are set. Dynamic code signature checks can only
    // check the code pages already swapped into memory, so make sure that
    // no malicious code can be loaded at a later time. You may want to
    // disable this check in debug builds.
    CFDictionaryRef csInfo = NULL;
    status = SecCodeCopySigningInformation(code, kSecCSDynamicInformation, &csInfo);
    if (status != errSecSuccess) {
        NSLog(@"%s: SecCodeCopySigningInformation returned %d", __func__, status);
        return NO;
    } else {
        uint32_t csFlags = [((__bridge NSDictionary *)csInfo)[(__bridge NSString *)kSecCodeInfoStatus] intValue];
#ifdef DEBUG
        NSLog(@"%s: csInfo: %@", __func__, csInfo);
        NSLog(@"%s: csFlags: 0x%x", __func__, csFlags);
#endif

        CFRelease(csInfo);
//        const uint32_t cs_restrict = 0x800;     // prevent debugging
//        const uint32_t cs_require_lv = 0x2000;  // Library Validation
//        const uint32_t cs_runtime = 0x10000;    // hardened runtime
        if ((csFlags & (CS_HARD | CS_KILL)) != (CS_HARD | CS_KILL)) {
            // add all flags to check which are in your code signature!
            // In particular, we recommend cs_require_lv and cs_restrict.
            NSLog(@"%s: csFlags = 0x%x", __func__, csFlags);
#ifdef DEBUG
            // continue on
#else
            return NO;    // Not accepted because it can be tampered with
#endif
        }
    }

    NSString *requirementString = @"anchor apple generic and certificate leaf[subject.OU] = \"" OSU_DEVELOPMENT_TEAM "\"";
    SecRequirementRef requirement = NULL;

    // Check at least the peer's TeamID, e.g.
    // "anchor apple generic and certificate leaf[subject.OU] = MyTeamIdentifier"
    status = SecRequirementCreateWithString((__bridge CFStringRef)requirementString, kSecCSDefaultFlags, &requirement);
    if (status != errSecSuccess) {
        NSLog(@"%s: SecRequirementCreateWithString returned %d", __func__, status);
        abort(); // error in requirement string
    }

    status = SecCodeCheckValidityWithErrors(code, kSecCSDefaultFlags, requirement, NULL);
    CFRelease(code);
    CFRelease(requirement);
    if (status != errSecSuccess) {
        NSLog(@"%s: SecCodeCheckValidityWithErrors returned %d", __func__, status);
        return NO;
    }

    return YES;
}

NS_ASSUME_NONNULL_END

