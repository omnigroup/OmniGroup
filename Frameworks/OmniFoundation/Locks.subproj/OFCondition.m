// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCondition.h>

RCS_ID("$Id$")

@implementation OFCondition

- init;
{
    if (![super init])
        return nil;

    lock = [[NSConditionLock alloc] init];
    flags.cleared = NO;

    return self;
}

- (void)dealloc;
{
    [lock release];
    [super dealloc];
}

- (void)waitForCondition;
{
    if (flags.cleared)
        return;
    [lock lockWhenCondition:1];
    if (!flags.cleared) {
        // TODO: If anyone else is waiting on this condition (say, if two data cursors are reading from the same data stream), they'll hang here until -clearCondition is called because we just reset their condition.
        [lock unlockWithCondition:0];
    } else {
        [lock unlock];
    }
}

- (void)signalCondition;
{
    [lock lock];
    [lock unlockWithCondition:1];
}

- (void)broadcastCondition;
{
    [lock lock];
    [lock unlockWithCondition:1];
}

- (void)clearCondition;
{
    flags.cleared = YES;
    [lock lock];
    [lock unlockWithCondition:1];
}

@end
