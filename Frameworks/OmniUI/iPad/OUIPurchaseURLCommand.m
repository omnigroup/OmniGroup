// Copyright 2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPurchaseURLCommand.h>

#import <OmniUI/OUIAppController+InAppStore.h>

RCS_ID("$Id$");

@implementation OUIPurchaseURLCommand {
@private
    NSString *_inAppPurchaseIdentifier;
    
}

- (id)initWithURL:(NSURL *)url;
{
    if (!(self = [super initWithURL:url])) {
        return nil;
    }
    
    NSString *queryString = [url query];
    _inAppPurchaseIdentifier = ([NSString isEmptyString:queryString]) ? nil : queryString;
    
    return self;
}

- (BOOL)skipsConfirmation;
{
    return YES;
}

- (void)invoke;
{
    [[OUIAppController controller] showInAppPurchases:_inAppPurchaseIdentifier viewController:self.viewControllerForPresentation];
}

@end
