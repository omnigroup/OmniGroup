// Copyright 2014-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIChangeAppIconURLCommand.h"

@import OmniBase;
@import UIKit;

RCS_ID("$Id$");

@interface OUIChangeAppIconURLCommand ()
// Radar 37952455: Regression: Spurious "implementing unavailable method" warning when subclassing
- (id)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (BOOL)skipsConfirmation NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (void)invoke NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
@end

@implementation OUIChangeAppIconURLCommand
{
    NSString *_iconName;
}

- (id)initWithURL:(NSURL *)url;
{
    if (!(self = [super initWithURL:url])) {
        return nil;
    }

    NSString *queryString = [url query];
    _iconName = queryString;

    return self;
}

- (BOOL)skipsConfirmation;
{
    return YES;
}

- (void)invoke;
{
    UIApplication *sharedApplication = UIApplication.sharedApplication;
    if (!sharedApplication.supportsAlternateIcons)
        return;

    [sharedApplication setAlternateIconName:_iconName completionHandler:^(NSError *_Nullable error) {
        if (error != nil) {
            NSLog(@"Unable to switch app icon to %@: %@", _iconName, [error toPropertyList]);
        }
    }];
}

@end
