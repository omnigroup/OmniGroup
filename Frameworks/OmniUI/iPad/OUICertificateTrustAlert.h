// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OUICertificateTrustAlert;

@protocol OUICertificateTrustAlertDelegate
- (void)certificateTrustAlert:(OUICertificateTrustAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex challenge:(NSURLAuthenticationChallenge *)challenge;
@end

@interface OUICertificateTrustAlert : OFObject <UIAlertViewDelegate> {
@private
    id <OUICertificateTrustAlertDelegate> _nonretained_delegate;
    NSURLAuthenticationChallenge *_challenge;
}
- initWithDelegate:(id <OUICertificateTrustAlertDelegate>)delegate forChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)show;

@end
