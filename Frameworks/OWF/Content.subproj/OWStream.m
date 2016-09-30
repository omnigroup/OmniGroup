// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContentType.h>
#import <OWF/OWParameterizedContentType.h>

RCS_ID("$Id$")

@implementation OWStream

- initWithName:(NSString *)aName
{
    if ((self = [super initWithName:aName]) != nil) {
        _lock = [[NSLock alloc] init];
        issuedCursorsCount = 0;
    }
    return self;
}

- (void)dealloc;
{
    OBASSERT(issuedCursorsCount == 0);
}

- (id)createCursor;
{
    return nil;
}

//

- (void)dataEnd;
{
}

- (void)dataAbort;
{
}

//

- (void)waitForDataEnd;
{
}

- (BOOL)endOfData;
{
    return YES;
}

/*
- (void)scheduleInvocationAtEOF:(OFInvocation *)anInvocation inQueue:(OFMessageQueue *)aQueue;
{
    if (aQueue)
        [aQueue addQueueEntry:anInvocation];
    else
        [anInvocation invoke];
}
*/

- (BOOL)contentIsValid;
{
    return YES;
}

- (int)cursorCount
{
    return issuedCursorsCount;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
//    if (_parameterizedContentType)
//        [debugDictionary setObject:_parameterizedContentType forKey:@"_parameterizedContentType"];
    [debugDictionary setIntValue:issuedCursorsCount forKey:@"issuedCursorsCount"];

    return debugDictionary;
}

// Private method called by the abstract OWCursor class

- (void)_adjustCursorCount:(int)one
{
    [_lock lock];
    issuedCursorsCount += one;
    [_lock unlock];
}

@end
