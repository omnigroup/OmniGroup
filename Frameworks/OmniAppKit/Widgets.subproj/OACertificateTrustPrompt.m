// Copyright 2016 Omni Development, Inc.All rights reserved.
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

@implementation OACertificateTrustPrompt
{
    NSURLAuthenticationChallenge *_challenge;
    NSWindow *(^_findPresenter)(void);
    OFCertificateTrustDuration _result;
}

- (instancetype)initForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBINVARIANT([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]);

    if ((self = [super init]) != nil) {
        _challenge = challenge;
        _result = OFCertificateTrustDurationNotEvenBriefly;
    }
    return self;
}

@synthesize result = _result;

- (void)findParentWindow:(NSWindow *(^)(void))finder;
{
    _findPresenter = finder;
}

static OFCertificateTrustDuration _currentTrustDuration(NSURLAuthenticationChallenge *challenge)
{
    if (OFHasTrustForChallenge(challenge))
        return OFCertificateTrustDurationSession;
    
    SecTrustResultType tr = kSecTrustResultOtherError;
    if ((errSecSuccess == SecTrustEvaluate(challenge.protectionSpace.serverTrust, &tr)) &&
        (tr == kSecTrustResultProceed || tr == kSecTrustResultUnspecified)) {
        return OFCertificateTrustDurationAlways;
    }
    
    return OFCertificateTrustDurationNotEvenBriefly;
}

- (void)start
{
    [super start];
    
    if (self.cancelled) {
        _findPresenter = NULL;
        _result = _currentTrustDuration(_challenge);
        [self finish];
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        SFCertificateTrustPanel *trustPanel = [[SFCertificateTrustPanel alloc] init];
        SecTrustRef trust = [[_challenge protectionSpace] serverTrust];
        
        NSWindow *presentingWindow;
        
        if (_findPresenter) {
            presentingWindow = _findPresenter();
            _findPresenter = NULL;
        } else {
            presentingWindow = nil;
        }
        
        NSString *prompt = OFCertificateTrustPromptForChallenge(_challenge);
        
        [trustPanel setDefaultButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", OMNI_BUNDLE, @"button title for certificate trust warning/prompt - cancel the operation")];
        [trustPanel setAlternateButtonTitle:NSLocalizedStringFromTableInBundle(@"Continue", @"OmniAppKit", OMNI_BUNDLE, @"button title for certificate trust warning/prompt - continue with operation despite certificate problem")];
        [trustPanel setShowsHelp:YES];
        
        [trustPanel beginSheetForWindow:presentingWindow modalDelegate:self didEndSelector:@selector(_certPanelSheetDidEnd:returnCode:contextInfo:) contextInfo:NULL trust:trust message:prompt];
    });
}

- (void)_certPanelSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)userChoice contextInfo:(void *)contextInfo
{
    // Totally unclear what values we get in "userChoice", since the documented values are deprecated and the replacements have counterintuitive names (RADAR 25585645)
    // Experimentally, "default button" (which is "Cancel") produces NSModalResponseOK, and "alternate button" (which is "Continue") produces NSModalResponseCancel.
    if (userChoice == NSModalResponseCancel /* NSModalResponseCancel means "Continue" here */ ) {
        // The user might have used the UI in the SFCertificateTrustPanel to mark this certificate or host as always trusted. We could determine that by running trust evaluation again to avoid this. But if they didn't, the "OK" button means to trust for this session.
        _result = OFCertificateTrustDurationSession;
        // TODO: Chase recipient of this, call add trust etc.
    } else {
        _result = OFCertificateTrustDurationNotEvenBriefly;
    }
    
    [self finish];
}

- (SecTrustRef)serverTrust;
{
    return _challenge.protectionSpace.serverTrust;
}

#if 0
- (BOOL)certificatePanelShowHelp:(SFCertificatePanel *)sender;
{
    [[OAApplication sharedApplication] showHelpURL: ... ];
}
#endif

@end

