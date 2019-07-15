// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Security/SecTrust.h>

NS_ASSUME_NONNULL_BEGIN

@class NSURLCredential, NSURLAuthenticationChallenge;

/*
 This is *one* way to make a service identifier, but not necessarily the only way. The important considerations for our needs are
 
 1) If the service issues a redirect, we'd like to store the original URL. This allows the back end to load balance users across servers w/o having to reenter credentials needlessly. This means that inside of a NSURLConnection authentication challenge, you should not pass the host of the NSURLProtectionSpace, but rather the original URL.
 2) You should be able to create multiple accounts on the same host w/o confusing credentials (so we use the whole original URL and username).
 3) We should try not to use credentials for site A on site B. We could just use a UUID for each service. But, if we do this then a user could enter valid credentials for a server and then change the URL to a totally different host and we'd start trying to use those credentials on the wrong server. This shouldn't leak credentials, but it is just messy.
 */
extern NSString *OFMakeServiceIdentifier(NSURL *originalURL, NSString *username, NSString *realm);

extern NSURLCredential * __nullable OFReadCredentialsForServiceIdentifier(NSString * __nullable serviceIdentifier, NSError * __autoreleasing *outError);
extern BOOL OFWriteCredentialsForServiceIdentifier(NSString *serviceIdentifier, NSString *userName, NSString *password, NSError * __autoreleasing *outError);
extern BOOL OFDeleteCredentialsForServiceIdentifier(NSString *serviceIdentifier, NSError * __autoreleasing *outError);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
extern NSURLCredential * __nullable OFReadCredentialsForLegacyHostPattern(NSString *hostPattern, NSString *username); // For importing legacy credentials on iOS
extern void OFDeleteAllCredentials(void); // For resetting demo builds or clearing bad keychains entries on platforms where Keychain Access.app doesn't exist to provide an escape hatch.
#endif

typedef enum {
    OFCertificateTrustDurationSession,
    OFCertificateTrustDurationAlways,
    OFCertificateTrustDurationNotEvenBriefly,
} OFCertificateTrustDuration;

#if DEBUG
extern NSString *OFCertificateTrustDurationName(OFCertificateTrustDuration);
#endif

@protocol OFCertificateTrustDisposition
- (SecTrustRef _Nullable)serverTrust;    // The trust ref we've evaluated and possibly modified
@property (nonatomic,readonly) OFCertificateTrustDuration result;
@end

// A per-session notation of trust. We'll get a challenge with an untrusted certificate and will want to prompt the user. We cannot block until the user makes a choice, so we continue w/o meeting the challenge in these cases and then try again later. If the user accepts the certificate, whatever UI they use can stash the trusted certificates here so that the next challenge will be met.
extern void OFAddTrustForChallenge(NSURLAuthenticationChallenge *challenge, OFCertificateTrustDuration duration);
// OFHasTrustForChallenge() looks through previously-stored user-confirmed exceptions, and sees if any apply to this challenge. If so, it updates the SecTrustRef to include the exception and re-evaluates it. Returns YES if the re-evaluation results in success ("Proceed"), NO otherwise.
extern BOOL OFHasTrustForChallenge(NSURLAuthenticationChallenge *challenge);
// Same as above, but operate directly on SecTrustRefs
extern void OFAddTrustExceptionForTrust(CFTypeRef trustRef, OFCertificateTrustDuration duration);
extern BOOL OFHasTrustExceptionForTrust(CFTypeRef trustRef);

// Helper for responding to NSURLAuthenticationMethodServerTrust challenges
extern NSURLCredential * __nullable OFTryApplyingTrustExceptions(NSURLAuthenticationChallenge *challenge, NSArray <NSData *> * __nullable storedExceptions);

// Helpers for configuring a SFCertificateTrustPanel
extern NSString *OFCertificateTrustPromptForChallenge(NSURLAuthenticationChallenge *challenge);
extern NSString * _Nullable OFCertificateTrustPromptForError(NSError * _Nullable error);

// Posted on the main queue after OFAddTrustForChallenge() makes a change.
extern NSString * const OFCertificateTrustUpdatedNotification;

extern NSString * const OFCredentialsErrorDomain;
extern NSString * const OFCredentialsSecurityErrorDomain; // The underlying error from the Security framework

enum {
    OFCredentialsErrorNone = 0,
    OFCredentialsErrorNotFound,
    
};

NS_ASSUME_NONNULL_END
