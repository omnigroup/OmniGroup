// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFCredentials.h>

@class OUICertificateTrustAlert;

@interface OUICertificateTrustAlert : OFObject <UIAlertViewDelegate>

- (id)initForChallenge:(NSURLAuthenticationChallenge *)challenge;

@property (copy, nonatomic) void (^cancelBlock)(void);
@property (copy, nonatomic) void (^trustBlock)(OFCertificateTrustDuration duration);
@property (assign, nonatomic) BOOL shouldOfferTrustAlwaysOption;

- (void)show;

@end
