// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectStreamCursor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAbstractObjectStream.h>

RCS_ID("$Id$")

@implementation OWObjectStreamCursor

// Init and dealloc

- initForObjectStream:(OWAbstractObjectStream *)anObjectStream;
{
    if (!(self = [super init]))
	return nil;

    objectStream = anObjectStream;
    [objectStream _adjustCursorCount:1];
    hint = NULL;
    streamIndex = 0;

    return self;
}

- (id)initFromCursor:(id)aCursor;
{
    OBPRECONDITION([aCursor class] == [self class]);
    return [self initForObjectStream:[(OWObjectStreamCursor *)aCursor objectStream]];
}

- (void)dealloc;
{
    [objectStream _adjustCursorCount:-1];
}

//

- (OWAbstractObjectStream *)objectStream;
{
    return objectStream;
}

- (NSUInteger)streamIndex;
{
    return streamIndex;
}

- (id)readObject;
{
    if (abortException)
	[abortException raise];
    return [objectStream objectAtIndex:streamIndex++ withHint:&hint];
}

- (void)skipObjects:(int)count;
{
    if (abortException)
	[abortException raise];
    [self seekToOffset:count fromPosition:OWCursorSeekFromCurrent];
}

- (void)ungetObject:(id)anObject;
{
    if (abortException)
	[abortException raise];
    OBASSERT([objectStream objectAtIndex:(streamIndex - 1) withHint:&hint] == anObject);
    streamIndex--;
}

// OWCursor subclass

- (NSUInteger)seekToOffset:(NSInteger)offset fromPosition:(OWCursorSeekPosition)position;
{
    if (abortException)
	[abortException raise];
    switch (position) {
        case OWCursorSeekFromCurrent:
            streamIndex += offset;
            break;
        case OWCursorSeekFromEnd:
            streamIndex = [objectStream objectCount] - offset;
            break;
        case OWCursorSeekFromStart:
            streamIndex = offset;
            break;
    }
    return streamIndex;
}

- (BOOL)isAtEOF;
{
    return [objectStream isIndexPastEnd:streamIndex];
}

- (void)scheduleInQueue:(OFMessageQueue *)aQueue invocation:(OFInvocation *)anInvocation
{
    OFInvocation *thisAgain = [[OFInvocation alloc] initForObject:self selector:_cmd withObject:aQueue withObject:anInvocation];
    BOOL rightNow = [objectStream _checkForAvailableIndex:streamIndex orInvoke:thisAgain];
    if (rightNow) {
        if (aQueue)
            [aQueue addQueueEntry:anInvocation];
        else
            [anInvocation invoke];
    }
}

// NSCopying protocol

- copyWithZone:(NSZone *)zone
{
    OWObjectStreamCursor *copyOfSelf = [[[self class] allocWithZone:zone] initForObjectStream:objectStream];
    copyOfSelf->streamIndex = streamIndex;
    return copyOfSelf;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (objectStream)
	[debugDictionary setObject:objectStream forKey:@"objectStream"];
    [debugDictionary setObject:[NSString stringWithFormat:@"%lu", streamIndex] forKey:@"streamIndex"];

    return debugDictionary;
}

@end
