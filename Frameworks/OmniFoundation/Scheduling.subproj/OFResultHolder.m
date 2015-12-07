// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFResultHolder.h>

RCS_ID("$Id$")

@implementation OFResultHolder
{
    id _result;
    NSConditionLock *_resultLock;
}

enum {RESULT_NOT_AVAILABLE, RESULT_AVAILABLE};

- init;
{
    if (!(self = [super init]))
        return nil;

    _resultLock = [[NSConditionLock alloc] initWithCondition:RESULT_NOT_AVAILABLE];
    return self;
}

- (void)dealloc;
{
    [_result release];
    [_resultLock release];
    [super dealloc];
}

- (void)setResult:(id)result;
{
    if ([result conformsToProtocol:@protocol(NSCopying)]) {
        result = [[result copy] autorelease];
    }

    [_resultLock lock];
    if (_result != result) {
        [_result release];
        _result = [result retain];
    }
    [_resultLock unlockWithCondition:RESULT_AVAILABLE];
}

- (id)result;
{
    id _resultSnapshot;

    [_resultLock lockWhenCondition:RESULT_AVAILABLE];
    _resultSnapshot = [_result retain];
    [_resultLock unlock];
    return [_resultSnapshot autorelease];
}

@end
