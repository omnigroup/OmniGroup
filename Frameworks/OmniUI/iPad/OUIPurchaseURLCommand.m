// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPurchaseURLCommand.h>

RCS_ID("$Id$");

@interface OUIPurchaseURLCommand ()
// Radar 37952455: Regression: Spurious "implementing unavailable method" warning when subclassing
- (id)initWithURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier NS_DESIGNATED_INITIALIZER NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (BOOL)skipsConfirmation NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (void)invoke NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
@end

@implementation OUIPurchaseURLCommand

- (id)initWithURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier;
{
    if (!(self = [super initWithURL:url senderBundleIdentifier:senderBundleIdentifier])) {
        return nil;
    }
    
    NSString *queryString = [url query];
    _inAppPurchaseIdentifier = queryString;
    
    return self;
}

- (BOOL)skipsConfirmation;
{
    return YES;
}

- (void)invoke;
{
    OBRequestConcreteImplementation(self, _cmd); // We override this in a category
}

@end
