// Copyright 2003-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATestCase.h"

#import <OmniAppKit/OAApplication.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OATestCase

+ (void) initialize;
{
    OBINITIALIZE;
    
    NSApplication *app = [OAApplication sharedApplication];
    
    OATestController *controller = [OATestController sharedController];
    
    // Set up your Info.plist in your unit test bundle appropriately.  OFController will look there when running unit tests.
    OBASSERT([controller isKindOfClass:[OATestController class]]);
    
    [app setDelegate:controller];
}

@end

@implementation OATestController

- (BOOL)exceptionHandler:(NSExceptionHandler *)sender shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;
{
    // if we are in a shouldRaise or shouldNotRaise, we don't want to get spammed by backtraces.  if we are supposed to raise, that'll be checked and it's "valid".  If we aren't supposed to raise, otest will catch this.
    return NO;
}

@end
