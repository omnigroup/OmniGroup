// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/Errors.h>

RCS_ID("$Id$");

NSString * const OFSErrorDomain = @"com.omnigroup.frameworks.OmniFileStore.ErrorDomain";

NSString * const OFSDAVHTTPErrorDomain = @"com.omnigroup.frameworks.OmniFileStore.DAVHTTP.ErrorDomain";
NSString * const OFSDAVHTTPErrorDataKey = @"errorData";
NSString * const OFSDAVHTTPErrorDataContentTypeKey = @"errorDataContentType";
NSString * const OFSDAVHTTPErrorStringKey = @"errorString";

// using the same values as those found in NSURLErrorFailingURLStringErrorKey and NSURLErrorFailingURLErrorKey
NSString * const OFSURLErrorFailingURLErrorKey = @"NSErrorFailingURLKey";          
NSString * const OFSURLErrorFailingURLStringErrorKey = @"NSErrorFailingURLStringKey";

BOOL OFSShouldOfferToReportError(NSError *error)
{
    if (error == nil)
        return NO; // There isn't an error, so don't report one

    if ([error causedByUnreachableHost])
        return NO; // Unreachable hosts cannot be solved by the app

    NSError *httpError = [error underlyingErrorWithDomain:OFSDAVHTTPErrorDomain];
    if (httpError != nil) {
        NSUInteger httpErrorCode = [httpError code];
        if (httpErrorCode >= 400 && httpErrorCode < 500)
            return NO; // Authorization issues cannot be resolved by the app
        if (httpErrorCode == OFS_HTTP_INSUFFICIENT_STORAGE)
            return NO; // Storage space issues cannot be resolved by the app
        if (httpErrorCode == OFS_HTTP_SERVICE_UNAVAILABLE && ![[[[httpError userInfo] objectForKey:OFSURLErrorFailingURLErrorKey] host] containsString:@"omnigroup.com"])
            return NO; // Service unavailable issue for some server that isn't ours
    }

    if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOSPC]) {
        // Local filesystem is out of space.
        return NO;
    }
    
    return YES; // Let's report everything else
}

@implementation NSError (OFSExtensions)

+ (NSError *)certificateTrustErrorForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // This error has no localized strings since it is intended to be caught and cause localized UI to be presented to the user to evaluate trust and possibly restart the operation.
    __autoreleasing NSError *error;
    OFSErrorWithInfo(&error, OFSCertificateNotTrusted, @"Untrusted certificate", @"Present UI to let the user pick", OFSCertificateTrustChallengeErrorKey, challenge, nil);
    return error;
}

- (BOOL)causedByPermissionFailure;
{
    if ([self hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_UNAUTHORIZED])
        return YES;
    if ([self hasUnderlyingErrorDomain:OFSErrorDomain code:OFSCertificateNotTrusted])
        return YES;
    
    return NO;
}

- (BOOL)causedByEncryptionFailure;
{
    if (![[self domain] isEqualToString:OFSErrorDomain]) {
        return NO;
    }
    
    NSInteger code = [self code];
    return (code >= OFSEncryptionMinimumErrorCode && code <= OFSEncryptionMaximumErrorCode);
}

@end
