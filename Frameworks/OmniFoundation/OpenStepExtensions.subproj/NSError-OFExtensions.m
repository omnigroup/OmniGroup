// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSError-OFExtensions.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation NSError (OFExtensions)

- (nullable NSError *)serverCertificateError;
{
    NSString *domain = self.domain;
    if ([domain isEqualToString:NSURLErrorDomain]) {
        NSInteger code = self.code;
        if (code == NSURLErrorServerCertificateHasBadDate ||
            code == NSURLErrorServerCertificateUntrusted ||
            code == NSURLErrorServerCertificateHasUnknownRoot ||
            code == NSURLErrorServerCertificateNotYetValid)
            return self;
    } else if ([domain isEqualToString:(__bridge NSString *)kCFErrorDomainCFNetwork]) {
        NSInteger code = self.code;
        if (code == kCFURLErrorServerCertificateHasBadDate ||
            code == kCFURLErrorServerCertificateUntrusted ||
            code == kCFURLErrorServerCertificateHasUnknownRoot ||
            code == kCFURLErrorServerCertificateNotYetValid)
            return self;
    }
    
    NSError *underlying = self.userInfo[NSUnderlyingErrorKey]; // May be nil
    return [underlying serverCertificateError];
}

- (NSError *)errorByAddingUserInfo:(NSDictionary *)userInfo;
{
    NSMutableDictionary *updatedUserInfo = [[self.userInfo mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
    [updatedUserInfo addEntriesFromDictionary:userInfo];
    NSError *updatedError = [NSError errorWithDomain:self.domain code:self.code userInfo:updatedUserInfo];
    return updatedError;
}

@end

NS_ASSUME_NONNULL_END
