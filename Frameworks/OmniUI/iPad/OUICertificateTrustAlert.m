// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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

- (void)showFromViewController:(UIViewController *)viewController;
{
    OBStrongRetain(self);

    NSString *prompt = OFCertificateTrustPromptForChallenge(_challenge);

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Certificate Trust", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert title") message:prompt preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"cancel button title") style:UIAlertActionStyleCancel handler:^(UIAlertAction * __nonnull action) {
        if (_cancelBlock != NULL)
            _cancelBlock();
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Continue", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
        if (_trustBlock != NULL)
            _trustBlock(OFCertificateTrustDurationSession);
    }]];

    if (_shouldOfferTrustAlwaysOption) {
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Trust Always", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
            if (_trustBlock != NULL)
                _trustBlock(OFCertificateTrustDurationAlways);
        }]];
    }

    [viewController presentViewController:alertController animated:YES completion:^{
        OBAutorelease(self);
    }];
}

@end
