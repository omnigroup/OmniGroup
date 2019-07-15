// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController+SpecialURLHandling.h>

/*!
 Concrete special URL command handler for purchase URLs (of the form <app name>:///purchase?<purchase_id>). When invoked, this command prompts for confirmation as usual, but then attempts to present a purchase sheet for the given purchase_id.
 */
@interface OUIPurchaseURLCommand : OUISpecialURLCommand
@property (nonatomic, copy) NSString *inAppPurchaseIdentifier;
@end
