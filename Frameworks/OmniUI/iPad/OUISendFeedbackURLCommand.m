// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISendFeedbackURLCommand.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

@interface OUISendFeedbackURLCommand ()
// Radar 37952455: Regression: Spurious "implementing unavailable method" warning when subclassing
- (BOOL)skipsConfirmation NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (void)invoke NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
@end

@implementation OUISendFeedbackURLCommand

- (BOOL)skipsConfirmation;
{
    return YES;
}

- (void)invoke;
{
    // TODO: Ultimately we do know which scene is handling the URL command, and we should pass it through.
    [[OUIAppController sharedController] sendFeedbackWithSubject:nil body:nil inScene:nil completion:^{}];
}

@end
