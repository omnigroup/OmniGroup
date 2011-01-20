// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUICertificateTrustAlert.h"

RCS_ID("$Id$");

@implementation OUICertificateTrustAlert

- initWithDelegate:(id <OUICertificateTrustAlertDelegate>)delegate forChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (!(self = [super init]))
        return nil;
    
    _nonretained_delegate = delegate;
    _challenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:[challenge sender]];
    
    
    return self;
}

- (void)dealloc;
{
    [_challenge release];
    
    [super dealloc];
}

- (void)show;
{
    NSError *error = [_challenge error];
    OBASSERT([[error domain] isEqualToString:NSURLErrorDomain]);
#if !TARGET_OS_IPHONE && (MAC_OS_X_VERSION_MIN_REQUIRED >= 1060) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
    NSString *failedURLString = [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey];
#else
    NSString *failedURLString = [[error userInfo] objectForKey:NSErrorFailingURLStringKey];
#endif
    
    if (!failedURLString)
        failedURLString = [[_challenge protectionSpace] host];
    
    NSString *prompt = nil;
    switch ([error code]) {
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
                                                    NSLocalizedStringFromTableInBundle(@"Trust Always", @"OmniUI", OMNI_BUNDLE, @"Certificate trust alert button title"), nil];
    [_alertView show];
    [_alertView release];
}

#pragma mark -
#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex;
{
    [_nonretained_delegate certificateTrustAlert:self didDismissWithButtonIndex:buttonIndex challenge:_challenge];
}

@end
