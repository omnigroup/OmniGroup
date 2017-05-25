// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISendFeedbackURLCommand.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

@implementation OUISendFeedbackURLCommand

- (BOOL)skipsConfirmation;
{
    return YES;
}

- (void)invoke;
{
    [[OUIAppController sharedController] sendFeedbackWithSubject:nil body:nil];
}

@end
