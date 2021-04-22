// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIHelpURLCommand.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIAppControllerSceneHelper.h>

@interface OUIHelpURLCommand ()
// Radar 37952455: Regression: Spurious "implementing unavailable method" warning when subclassing
- (BOOL)skipsConfirmation NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (void)invoke NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
@end

@implementation OUIHelpURLCommand

- (BOOL)skipsConfirmation;
{
    return YES;
}

- (void)invoke;
{
    OUIAppControllerSceneHelper *helper = [[OUIAppControllerSceneHelper alloc] init];
    helper.window = self.viewControllerForPresentation.view.window;
    [helper showOnlineHelp:nil];
}

@end
