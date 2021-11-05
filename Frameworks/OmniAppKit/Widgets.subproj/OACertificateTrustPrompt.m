// Copyright 2016-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OACertificateTrustPrompt.h>
#import <SecurityInterface/SFCertificateTrustPanel.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")
OB_REQUIRE_ARC

NS_ASSUME_NONNULL_BEGIN

@implementation OACertificateTrustPrompt
{
    NSURLAuthenticationChallenge *_challenge;
    NSError *_error;

    OFCertificateTrustDuration _result;
}

- (instancetype)initForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBINVARIANT([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]);

    self = [super init];

    _challenge = challenge;
    _result = OFCertificateTrustDurationNotEvenBriefly;

    return self;
}

- (instancetype)initForError:(NSError *)error;
{
    self = [super init];

    while (error != nil) {
        NSDictionary *userInfo = error.userInfo;
        if ([userInfo valueForKey:NSURLErrorFailingURLPeerTrustErrorKey] || [userInfo objectForKey:(__bridge NSString *)kCFStreamPropertySSLPeerTrust]) {
            _error = error;
            break;
        }
        error = userInfo[NSUnderlyingErrorKey];
    }

    _result = OFCertificateTrustDurationNotEvenBriefly;

    return self;
}

@synthesize result = _result;

static OFCertificateTrustDuration _currentTrustDuration(SecTrustRef serverTrust)
{
    if (OFHasTrustExceptionForTrust(serverTrust))
        return OFCertificateTrustDurationSession;
    
    if (@available(macOS 10.15, *)) {
        if (SecTrustEvaluateWithError(serverTrust, NULL)) {
            return OFCertificateTrustDurationAlways;
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        SecTrustResultType tr = kSecTrustResultOtherError;
        if ((errSecSuccess == SecTrustEvaluate(serverTrust, &tr)) &&
            (tr == kSecTrustResultProceed || tr == kSecTrustResultUnspecified)) {
            return OFCertificateTrustDurationAlways;
        }
#pragma clang diagnostic pop
    }
    return OFCertificateTrustDurationNotEvenBriefly;
}

- (void)start
{
    [super start];
    
    if (self.cancelled) {
        _findParentWindowBlock = NULL;
        _result = _currentTrustDuration(self.serverTrust);
        [self finish];
        return;
    }

    __weak OACertificateTrustPrompt *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf _beginTrustSheet];
    });
}

- (void)_beginTrustSheet;
{
    SFCertificateTrustPanel *trustPanel = [[SFCertificateTrustPanel alloc] init];
    SecTrustRef trust = self.serverTrust;

    NSWindow *presentingWindow;

    if (_findParentWindowBlock) {
        presentingWindow = _findParentWindowBlock();
        _findParentWindowBlock = NULL;
    } else {
        presentingWindow = nil;
    }

    NSString *prompt = _challenge != nil ? OFCertificateTrustPromptForChallenge(_challenge) : OFCertificateTrustPromptForError(_error);
    [trustPanel setDefaultButtonTitle:NSLocalizedStringFromTableInBundle(@"Continue", @"OmniAppKit", OMNI_BUNDLE, @"button title for certificate trust warning/prompt - continue with operation despite certificate problem")];
    [trustPanel setAlternateButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", OMNI_BUNDLE, @"button title for certificate trust warning/prompt - cancel the operation")];
    [trustPanel setShowsHelp:YES];
    [trustPanel beginSheetForWindow:presentingWindow modalDelegate:self didEndSelector:@selector(_certPanelSheetDidEnd:returnCode:contextInfo:) contextInfo:NULL trust:trust message:prompt];
}

- (void)_certPanelSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)userChoice contextInfo:(void *)contextInfo
{
    if (userChoice == NSModalResponseOK) {
        // The user might have used the UI in the SFCertificateTrustPanel to mark this certificate or host as always trusted. We could determine that by running trust evaluation again to avoid this. But if they didn't, the "OK" button means to trust for this session.
        _result = OFCertificateTrustDurationSession;
        SecTrustRef trust = self.serverTrust;
        OFAddTrustExceptionForTrust(trust, _result); // Creates and stores the exception.
        OFHasTrustExceptionForTrust(trust); // Adds the exception to this trust object.
        if (_trustBlock != NULL) {
            _trustBlock(_result);
            _trustBlock = NULL;
        }
    } else {
        _result = OFCertificateTrustDurationNotEvenBriefly;
        if (_cancelBlock != NULL) {
            _cancelBlock();
            _cancelBlock = NULL;
        }
    }
    
    [self finish];
}

- (SecTrustRef _Nullable)serverTrust;
{
    if (_challenge != nil) {
        return _challenge.protectionSpace.serverTrust;
    } else if (_error != nil) {
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

#if 0
- (BOOL)certificatePanelShowHelp:(SFCertificatePanel *)sender;
{
    [[OAApplication sharedApplication] showHelpURL: ... ];
}
#endif

@end

NS_ASSUME_NONNULL_END
