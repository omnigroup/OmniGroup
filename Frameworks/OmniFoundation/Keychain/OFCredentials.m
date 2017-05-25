// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCredentials.h>

#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFCredentialChallengeDispositionProtocol.h>

@import Foundation;
@import Security;

#import "OFCredentials-Internal.h"

RCS_ID("$Id$")

NSString * const OFCredentialsErrorDomain = @"com.omnigroup.OmniFoundation.Credentials.ErrorDomain";
NSString * const OFCredentialsSecurityErrorDomain = @"com.omnigroup.OmniFoundation.Credentials.Security.ErrorDomain";

static NSString *_OFCertificateTrustPromptForErrorCode(NSInteger, NSString *);

void _OFSecError(const char *caller, const char *function, OSStatus code, NSError * __autoreleasing *outError)
{
    NSString *errorMessage;
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // No SecCopyErrorMessageString on iOS, sadly.
    errorMessage = [NSString stringWithFormat:@"%s: %s returned %"PRI_OSStatus"", caller, function, code];
#else
    errorMessage = CFBridgingRelease(SecCopyErrorMessageString(code, NULL/*reserved*/));
#endif
    NSLog(@"%@", errorMessage); // For backwards comptibility, this logs as well as passes out an error.
    
    if (outError) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey:errorMessage};
        *outError = [NSError errorWithDomain:OFCredentialsSecurityErrorDomain code:code userInfo:userInfo];
    }
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

NSData *_OFDataForLeafCertificateInTrust(SecTrustRef trustRef)
{
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

#if 0
// This was only ever called with the result of -underlyingErrorWithDomain:NSURLErrorDomain, meaning only the first if was taken
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
#endif

NSString *OFCertificateTrustPromptForChallenge(NSURLAuthenticationChallenge *challenge)
{
    NSError *error = [[challenge error] underlyingErrorWithDomain:NSURLErrorDomain];
    NSString *failedURLString = [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey];
    if ([NSString isEmptyString:failedURLString])
        failedURLString = [[challenge protectionSpace] host];
    
    return _OFCertificateTrustPromptForErrorCode([error code], failedURLString);
}

NSString *OFCertificateTrustPromptForError(NSError *error)
{
    error = [error underlyingErrorWithDomain:NSURLErrorDomain];
    NSString *failedURLString = [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey];
    if ([NSString isEmptyString:failedURLString]) {
        NSURL *url = [[error userInfo] objectForKey:NSURLErrorFailingURLErrorKey];
        failedURLString = [url host];
    }
    
    return _OFCertificateTrustPromptForErrorCode([error code], failedURLString);
}

static NSString *_OFCertificateTrustPromptForErrorCode(NSInteger errorCode, NSString *failedURLString)
{
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

NSURLCredential *OFTryApplyingTrustExceptions(NSURLAuthenticationChallenge *challenge, NSArray <NSData *> *storedExceptions)
{
    if (!storedExceptions)
        return nil;
    
    NSUInteger trustExceptionCount = storedExceptions.count;
    if (!trustExceptionCount)
        return nil;
    
    SecTrustRef trustRef = challenge.protectionSpace.serverTrust;
    SecTrustResultType trustEvaluationResult = -1;
    if (SecTrustEvaluate(trustRef, &trustEvaluationResult) != noErr) {
        // We can't even evaluate the trust ref. Something deeper is wrong than just an untrusted certificate.
        return nil;
    }
    
    // Check whether the trust status is one which we can't store exceptions for.
    if (trustEvaluationResult == kSecTrustResultProceed || trustEvaluationResult == kSecTrustResultUnspecified || trustEvaluationResult == kSecTrustResultFatalTrustFailure)
        return nil;
    
    // Give each of the exceptions a try.
    for (NSUInteger trustExceptionIndex = 0; trustExceptionIndex < trustExceptionCount; trustExceptionIndex ++) {
        if (SecTrustSetExceptions(trustRef, (__bridge CFDataRef)[storedExceptions objectAtIndex:trustExceptionIndex]) &&
            SecTrustEvaluate(trustRef, &trustEvaluationResult) == noErr) {
            // Did this work?
            if (trustEvaluationResult == kSecTrustResultProceed || trustEvaluationResult == kSecTrustResultDeny || trustEvaluationResult == kSecTrustResultUnspecified || trustEvaluationResult == kSecTrustResultFatalTrustFailure)
                return [NSURLCredential credentialForTrust:trustRef];
        }
    }
    
    return nil;
}

#if DEBUG
NSString *OFCertificateTrustDurationName(OFCertificateTrustDuration disposition)
{
    switch (disposition) {
        case OFCertificateTrustDurationSession: return @"TrustDurationSession";
        case OFCertificateTrustDurationAlways: return @"TrustDurationAlways";
        case OFCertificateTrustDurationNotEvenBriefly: return @"TrustDurationNotEvenBriefly";
//        case OFCertificateTrustSettingsModified: return @"TrustSettingsModified";
    }
    return [NSString stringWithFormat:@"<Unexpected TrustDuration %d>", (int)disposition];
}
#endif

@interface _OFImmediateCredentialOp : NSOperation <OFCredentialChallengeDisposition>
@property(readwrite,nonatomic) NSURLSessionAuthChallengeDisposition disposition;
@property(readwrite,retain,atomic) NSURLCredential *credential;
@end

@implementation _OFImmediateCredentialOp

- (void)dealloc;
{
    [_credential release];
    [super dealloc];
}

- (void)main
{
    /* nothing to do */
}

@end

NSOperation <OFCredentialChallengeDisposition> *OFImmediateCredentialResponse(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential)
{
    _OFImmediateCredentialOp *op = [[_OFImmediateCredentialOp alloc] init];
    op.disposition = disposition;
    op.credential = credential;
    [op start];
    return [op autorelease];
}
