// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSOperation.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFAsynchronousOperation.h>

@interface OUICertificateTrustAlert : OFAsynchronousOperation <OFCertificateTrustDisposition>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initForChallenge:(NSURLAuthenticationChallenge *)challenge NS_DESIGNATED_INITIALIZER;
- (instancetype)initForError:(NSError *)error NS_DESIGNATED_INITIALIZER;

/* Tells OUICertificateTrustAlert what view controller to present the alert from. This block will be invoked on the main thread right before the alert is to be shown. */
- (void)findViewController:(UIViewController *(^)(void))finder;

@property (readonly) SecTrustRef serverTrust;

@property (copy, nonatomic) void (^cancelBlock)(void);
@property (copy, nonatomic) void (^trustBlock)(OFCertificateTrustDuration duration);
@property (assign, nonatomic) BOOL shouldOfferTrustAlwaysOption;

// These interact with the certificate trust exception list maintained in OmniFoundation.
@property (assign, nonatomic) BOOL shortCircuitIfTrusted;  // Checks OFHasTrustForChallenge() before prompting the user. Does not call cancelBlock if it short-circuits.
@property (assign, nonatomic) BOOL storeResult;            // Calls OFAddTrustForChallenge() on completion/acceptance

@property (readwrite,nonatomic) OFCertificateTrustDuration result;

@end

