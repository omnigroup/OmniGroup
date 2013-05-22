// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUICertificateTrustAlert.h>

RCS_ID("$Id$");

@implementation OUICertificateTrustAlert
{
    NSURLAuthenticationChallenge *_challenge;
}

@synthesize cancelBlock = _cancelBlock, trustBlock = _trustBlock, shouldOfferTrustAlwaysOption = _shouldOfferTrustAlwaysOption;

- (id)initForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (!(self = [super init]))
        return nil;
    
    _challenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:[challenge sender]];

    return self;
}

- (void)dealloc;
{
    [_challenge release];
    [_cancelBlock release];
    [_trustBlock release];
    
    [super dealloc];
}

- (void)show;
{
    [self retain];

    NSString *prompt = OFCertificateTrustPromptForChallenge(_challenge);
    UIAlertView *_alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Certificate Trust", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert title")
                                            message:prompt delegate:self
                                  cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"cancel button title")
                                  otherButtonTitles:NSLocalizedStringFromTableInBundle(@"Continue", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert button title"),
                                                    (_shouldOfferTrustAlwaysOption ? NSLocalizedStringFromTableInBundle(@"Trust Always", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert button title") : nil),
                                                    nil];
    [_alertView show];
    [_alertView release];
}

#pragma mark -
#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex;
{
    OFCertificateTrustDuration trustDuration;

    switch (buttonIndex) {
        case 0: /* Cancel */
        default:
            if (_cancelBlock != NULL)
                _cancelBlock();
            return;
            
        case 1: /* Continue */
            if (_shouldOfferTrustAlwaysOption == NO) {
                // We only have two buttons in this case. Defaulting to OFCertificateTrustDurationSession is problematic since the code to show the alert later might not be set up (we might do this when preflighting a server). Still, we should handle this.
                // <bug:///85541> (Handler certificate invalidation after a server has been added)
                trustDuration = OFCertificateTrustDurationAlways;
            } else
                trustDuration = OFCertificateTrustDurationSession;
            break;

        case 2: /* Trust always */
            trustDuration = OFCertificateTrustDurationAlways;
            break;
    }

    if (_trustBlock != NULL)
        _trustBlock(trustDuration);

    [self autorelease];
}

@end
