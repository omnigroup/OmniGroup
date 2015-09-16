// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIActionViewController.h>

RCS_ID("$Id$");

@implementation OUIActionViewController
{
    NSTimeInterval _displayTime;
    NSTimeInterval _minimumDisplayInterval;
}

- (void)finishWithError:(NSError *)error;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_finished); // Shouldn't use this more than once.

    // Avoid view controllers that come on screen very quickly and the disappear (in particular, things that are showing progress).
    NSTimeInterval minimumDisplayInterval = _minimumDisplayInterval;
    if (minimumDisplayInterval < 1)
        minimumDisplayInterval = 1;
    
    NSDate *displayEnd = [NSDate dateWithTimeIntervalSinceReferenceDate:_displayTime + minimumDisplayInterval];
    while ([displayEnd timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:displayEnd];

    // Break retain cycles
    typeof(_finished) finished = _finished;
    _finished = nil;

    if (finished) {
        finished(self, error);
    }
}

- (void)cancel;
{
    [self finishWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}

#pragma mark - UIViewController

- (void)viewDidAppear:(BOOL)animated;
{
    _displayTime = [NSDate timeIntervalSinceReferenceDate];

    [super viewDidAppear:animated];
}

@end
