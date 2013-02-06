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

    NSError *error = [_challenge error];
    int errorCode;
    if (error != nil && [[error domain] isEqualToString:NSURLErrorDomain])
        errorCode = [error code];
    else
        errorCode = NSURLErrorSecureConnectionFailed;

#if !TARGET_OS_IPHONE && (MAC_OS_X_VERSION_MIN_REQUIRED >= 1060) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
    NSString *failedURLString = [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey];
#else
    NSString *failedURLString = [[error userInfo] objectForKey:NSErrorFailingURLStringKey];
#endif
    
    if (failedURLString == nil)
        failedURLString = [[_challenge protectionSpace] host];
    
    NSString *prompt = nil;
    switch (errorCode) {
        case NSURLErrorServerCertificateHasUnknownRoot:
            prompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" is not signed by any root server. This site may not be trustworthy. Would you like to connect anyway?", @"OmniUI", OMNI_BUNDLE, @"server certificate has unknown root"), failedURLString];
            break;
        case NSURLErrorServerCertificateNotYetValid:
            prompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" is not yet valid. This site may not be trustworthy. Would you like to connect anyway?", @"OmniUI", OMNI_BUNDLE, @"server certificate not yet valid"), failedURLString];
            break;
        case NSURLErrorServerCertificateHasBadDate:
            prompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" has an invalid date. It may be expired, or not yet active. Would you like to connect anyway?", @"OmniUI", OMNI_BUNDLE, @"server certificate out of date"), failedURLString];
            break;
        case NSURLErrorServerCertificateUntrusted:
            prompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" is signed by an untrusted root server. This site may not be trustworthy. Would you like to connect anyway?", @"OmniUI", OMNI_BUNDLE, @"server certificate untrusted"), failedURLString];
            break;
        case NSURLErrorClientCertificateRejected:
        default:
            prompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The server certificate for \"%@\" does not seem to be valid. This site may not be trustworthy. Would you like to connect anyway?", @"OmniUI", OMNI_BUNDLE, @"server certificate rejected"), failedURLString];
            break;
    }
    
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
    OFHostTrustDuration trustDuration;

    switch (buttonIndex) {
        case 0: /* Cancel */
        default:
            if (_cancelBlock != NULL)
                _cancelBlock();
            return;
            
        case 1: /* Continue */
            if (_shouldOfferTrustAlwaysOption == NO) {
                // We only have two buttons in this case. Defaulting to OFHostTrustDurationSession is problematic since the code to show the alert later might not be set up (we might do this when preflighting a server). Still, we should handle this.
                // <bug:///85541> (Handler certificate invalidation after a server has been added)
                trustDuration = OFHostTrustDurationAlways;
            } else
                trustDuration = OFHostTrustDurationSession;
            break;

        case 2: /* Trust always */
            trustDuration = OFHostTrustDurationAlways;
            break;
    }

    if (_trustBlock != NULL)
        _trustBlock(trustDuration);

    [self autorelease];
}

@end
