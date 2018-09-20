// Copyright 2003-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATestController.h"

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniAppKit/OAApplication.h>

RCS_ID("$Id$");

@implementation OATestController

- (void)becameSharedController;
{
    [super becameSharedController];
    
    NSApplication *app = [OAApplication sharedApplication];
    [app setDelegate:self];
}

- (BOOL)exceptionHandler:(NSExceptionHandler *)sender shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;
{
    // if we are in a shouldRaise or shouldNotRaise, we don't want to get spammed by backtraces.  if we are supposed to raise, that'll be checked and it's "valid".  If we aren't supposed to raise, otest will catch this.
    return NO;
}

@end

#endif
