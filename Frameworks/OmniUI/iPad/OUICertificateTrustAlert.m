// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUICertificateTrustAlert.h>

RCS_ID("$Id$");

@implementation OUICertificateTrustAlert
{
    /* Either _challenge or _error is non-nil */
    NSURLAuthenticationChallenge *_challenge;
    NSError *_error;
    
    UIViewController *(^_findPresenter)(void);
    OFCertificateTrustDuration _result;
    BOOL _shortCircuit;
    BOOL _storeResultingException;
}

@synthesize cancelBlock = _cancelBlock,
            trustBlock = _trustBlock,
            shouldOfferTrustAlwaysOption = _shouldOfferTrustAlwaysOption,
            shortCircuitIfTrusted = _shortCircuit,
            result = _result,
            storeResult = _storeResultingException;

- (void)findViewController:(UIViewController *(^)(void))finder;
{
    _findPresenter = finder;
}

- (id)initForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (!(self = [super init]))
        return nil;
    
    _challenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:[challenge sender]];
    _shortCircuit = YES;
    _result = OFCertificateTrustDurationNotEvenBriefly;

    return self;
}

- (id)initForError:(NSError *)error;
{
    if (!(self = [super init]))
        return nil;
    
    while (error) {
        NSDictionary *userInfo = error.userInfo;
        if ([userInfo valueForKey:NSURLErrorFailingURLPeerTrustErrorKey] || [userInfo objectForKey:(__bridge NSString *)kCFStreamPropertySSLPeerTrust]) {
            _error = error;
            break;
        }
        error = userInfo[NSUnderlyingErrorKey];
    }
    _shortCircuit = YES;
    _result = OFCertificateTrustDurationNotEvenBriefly;
    
    return self;
}

- (SecTrustRef)serverTrust;
{
    if (_challenge) {
        return _challenge.protectionSpace.serverTrust;
    } else if (_error) {
        NSDictionary *userInfo = _error.userInfo;
        id trustRef = [userInfo valueForKey:NSURLErrorFailingURLPeerTrustErrorKey];
        if (trustRef)
            return (__bridge SecTrustRef)trustRef;
        trustRef = [userInfo objectForKey:(__bridge NSString *)kCFStreamPropertySSLPeerTrust];
        if (trustRef)
            return (__bridge SecTrustRef)trustRef;
        return NULL;
    } else {
        OBASSERT_NOT_REACHED("Either challenge or error should be non-nil");
        return nil;
    }
}

- (UIAlertController *)_alertController;
{
    NSString *prompt = _challenge? OFCertificateTrustPromptForChallenge(_challenge) : OFCertificateTrustPromptForError(_error);
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Certificate Trust", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert title") message:prompt preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"cancel button title") style:UIAlertActionStyleCancel handler:^(UIAlertAction * __nonnull action) {
        _result = OFCertificateTrustDurationNotEvenBriefly;
        if (_cancelBlock != NULL) {
            _cancelBlock();
            _cancelBlock = NULL;
        }
        _trustBlock = NULL;
        [self finish];
    }]];
    
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Continue", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
        [self _accept:OFCertificateTrustDurationSession];
    }]];
    
    if (_shouldOfferTrustAlwaysOption) {
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Trust Always", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
            [self _accept:OFCertificateTrustDurationAlways];
        }]];
    }
    
    return alertController;
}

extern NSString *OFSummarizeTrustResult(SecTrustRef evaluationContext);

- (void)_accept:(OFCertificateTrustDuration)trustDuration;
{
    _result = trustDuration;
    // NSLog(@"Accepted: choice = %@", OFCertificateTrustDurationName(trustDuration));
    if (_storeResultingException) {
        SecTrustRef trust = [self serverTrust];
        // NSLog(@"Before adding trust: %@", OFSummarizeTrustResult(trust));
        OFAddTrustExceptionForTrust(trust, trustDuration);  // Creates and stores the exception.
        OFHasTrustExceptionForTrust(trust);                 // Adds the exception to this trust object.
    }
    // NSLog(@"When finishing: %@", OFSummarizeTrustResult(self.serverTrust));
    if (_trustBlock != NULL) {
        _trustBlock(trustDuration);
        _trustBlock = NULL;
    }
    _cancelBlock = NULL;
    [self finish];
}

// NSOperation/OFAsynchronousOperation implementation

- (void)start;
{
    [super start];
    
    if (self.cancelled) {
        _result = OFCertificateTrustDurationNotEvenBriefly;
        if (_cancelBlock != NULL)
            _cancelBlock();
        [self finish];
        return;
    }
    
    if (_shortCircuit) {
        if (OFHasTrustExceptionForTrust((CFTypeRef)self.serverTrust)) {
            _result = OFCertificateTrustDurationSession;
            [self finish];
            return;
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presentingController = _findPresenter();
        UIViewController *alertController = [self _alertController];
        
        [presentingController presentViewController:alertController animated:YES completion:NULL];
    });
}

@end

