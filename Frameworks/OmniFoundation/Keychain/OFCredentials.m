// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCredentials.h>

#import <Security/Security.h>
#import <Security/SecTrust.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <Foundation/NSURLCredential.h>
#import <Foundation/NSURLAuthenticationChallenge.h>
#import <Foundation/NSURLProtectionSpace.h>
#import <Foundation/NSURLError.h>

#import "OFCredentials-Internal.h"

RCS_ID("$Id$")

void _OFLogSecError(const char *caller, const char *function, OSStatus err)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // No SecCopyErrorMessageString on iOS, sadly.
    NSLog(@"%s: %s returned %"PRI_OSStatus"", caller, function, err);
#else
    CFStringRef errorMessage = SecCopyErrorMessageString(err, NULL/*reserved*/);
    NSLog(@"%s: %s returned \"%@\" (%"PRI_OSStatus")", caller, function, errorMessage, err);
    if (errorMessage)
        CFRelease(errorMessage);
#endif
}

NSURLCredential *_OFCredentialFromUserAndPassword(NSString *user, NSString *password)
{
    if (![NSString isEmptyString:user] && ![NSString isEmptyString:password]) {
        // We'd like to use NSURLCredentialPersistenceNone to force NSURLConnection to always ask us for credentials, but if we do then it doesn't ask us early enough to avoid a 401 on each round trip. The downside to persistent credentials is that some versions of iOS would not call our authenticaion challenge NSURLConnection delegate method when there were any cached credentials, but per-session at least will ask again on the next launch of the app.
        NSURLCredential *result = [NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceForSession];
        return result;
    }
    
    return nil;
}

NSString *OFMakeServiceIdentifier(NSURL *originalURL, NSString *username, NSString *realm)
{
    OBPRECONDITION(originalURL);
    OBPRECONDITION(![NSString isEmptyString:username]);
    OBPRECONDITION(![NSString isEmptyString:realm]);
    
    // Normalize the URL string to not have a trailing slash.
    NSString *urlString = [originalURL absoluteString];
    if ([urlString hasSuffix:@"/"])
        urlString = [urlString stringByRemovingSuffix:@"/"];
    
    return [NSString stringWithFormat:@"%@|%@|%@", urlString, username, realm];
}

SecTrustRef _OFTrustForChallenge(NSURLAuthenticationChallenge *challenge)
{
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    NSString *challengeMethod = [protectionSpace authenticationMethod];
    if (![challengeMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        OBASSERT_NOT_REACHED("Unexpected challenge method");
        return nil;
    }
    return [protectionSpace serverTrust];
}

NSData *_OFDataForLeafCertificateInChallenge(NSURLAuthenticationChallenge *challenge)
{
    SecTrustRef trustRef = _OFTrustForChallenge(challenge);
    if (!trustRef) {
        OBASSERT(trustRef);
        return nil;
    }

    if (SecTrustGetCertificateCount(trustRef) == 0) {
        OBASSERT(SecTrustGetCertificateCount(trustRef) > 0, "Malformed SecTrustRef?");
        return nil;
    }
    
    // Leaf is always at index 0
    SecCertificateRef leafCertificate = SecTrustGetCertificateAtIndex(trustRef, 0);
    CFDataRef certificateData = SecCertificateCopyData(leafCertificate);
    return CFBridgingRelease(certificateData);
}

NSString * const OFCertificateTrustUpdatedNotification = @"OFCertificateTrustUpdated";

static NSInteger _OFURLErrorCodeForTrustRef(NSURLAuthenticationChallenge *challenge)
{
    NSError *error = [[challenge error] underlyingErrorWithDomain:NSURLErrorDomain];
    if (error) {
        // NSURLAuthenticationChallenge often (always?) seems to not actually fill out this error
        return [error code];
    }
    
    // SecTrustCopyProperties is not defined on iOS
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    SecTrustRef trustRef = _OFTrustForChallenge(challenge);
    NSArray *trustProperties = CFBridgingRelease(SecTrustCopyProperties(trustRef));
    OBASSERT([trustProperties count] > 0, "Trust should have been evaluated already for us to get on this error handling path");
    
    for (NSDictionary *property in trustProperties) {
        NSString *errorReason = property[(NSString *)kSecPropertyTypeError];
        
        // Constants for these? For now, looking in <Security/cssmerr.h> for things that seem to map to the codes/strings we had already.
        if ([errorReason isEqualToString:@"CSSMERR_TP_INVALID_ANCHOR_CERT"])
            return NSURLErrorServerCertificateHasUnknownRoot;

        if ([errorReason isEqualToString:@"CSSMERR_TP_CERT_NOT_VALID_YET"])
            return NSURLErrorServerCertificateNotYetValid;
        
        if ([errorReason isEqualToString:@"CSSMERR_TP_CERT_EXPIRED"])
            return NSURLErrorServerCertificateHasBadDate;
        
        if (errorReason)
            NSLog(@"_OFURLErrorCodeForTrustRef -- unknown error reason \"%@\".", errorReason);
    }
#endif
    
    // Generic fallback...
    return NSURLErrorSecureConnectionFailed;
}

NSString *OFCertificateTrustPromptForChallenge(NSURLAuthenticationChallenge *challenge)
{
    NSError *error = [[challenge error] underlyingErrorWithDomain:NSURLErrorDomain];

    NSString *failedURLString = [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey];
    if ([NSString isEmptyString:failedURLString])
        failedURLString = [[challenge protectionSpace] host];

    NSInteger errorCode = _OFURLErrorCodeForTrustRef(challenge);
    
    switch (errorCode) {
        case NSURLErrorServerCertificateHasUnknownRoot:
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" is not signed by any root server. This site may not be trustworthy. Would you like to connect anyway?", @"OmniFoundation", OMNI_BUNDLE, @"server certificate has unknown root"), failedURLString];
            
        case NSURLErrorServerCertificateNotYetValid:
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" is not yet valid. This site may not be trustworthy. Would you like to connect anyway?", @"OmniFoundation", OMNI_BUNDLE, @"server certificate not yet valid"), failedURLString];
            
        case NSURLErrorServerCertificateHasBadDate:
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" has an invalid date. It may be expired, or not yet active. Would you like to connect anyway?", @"OmniFoundation", OMNI_BUNDLE, @"server certificate out of date"), failedURLString];
            
        case NSURLErrorServerCertificateUntrusted:
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" is signed by an untrusted root server. This site may not be trustworthy. Would you like to connect anyway?", @"OmniFoundation", OMNI_BUNDLE, @"server certificate untrusted"), failedURLString];
            
        case NSURLErrorClientCertificateRejected:
        default:
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" does not seem to be valid. This site may not be trustworthy. Would you like to connect anyway?", @"OmniFoundation", OMNI_BUNDLE, @"server certificate rejected"), failedURLString];
    }
}

