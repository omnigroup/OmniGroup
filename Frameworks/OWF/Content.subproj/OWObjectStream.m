// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWObjectStreamCursor.h>

RCS_ID("$Id$")

@interface OWObjectStream (Private)
- (void)_noMoreData;
@end

#define OWObjectStreamBuffer_BufferedObjectsLength 128

typedef struct _OWObjectStreamBuffer {
    unsigned int nextIndex;
    const void *objects[OWObjectStreamBuffer_BufferedObjectsLength];
    struct _OWObjectStreamBuffer *next;
} OWObjectStreamBuffer;

@implementation OWObjectStream
{
    const void **nextObjectInBuffer;
    const void **beyondBuffer;
    OWObjectStreamBuffer *first, *last;
    unsigned int count;
    BOOL endOfObjects;
    
    NSConditionLock *objectsLock;
    NSConditionLock *endOfDataLock;
}

enum {
    OBJECTS_AVAILABLE, READERS_WAITING
};
enum {
    MORE_DATA_POSSIBLE, DATA_ENDED
};

// Init and dealloc

- initWithName:(NSString *)aName;
{
    if (!(self = [super initWithName:aName]))
	return nil;
    first = last = malloc(sizeof(OWObjectStreamBuffer));
    last->nextIndex = OWObjectStreamBuffer_BufferedObjectsLength;
    last->next = NULL;
    nextObjectInBuffer = last->objects;
    beyondBuffer = last->objects + OWObjectStreamBuffer_BufferedObjectsLength;
    count = 0;
    endOfObjects = NO;
    objectsLock = [[NSConditionLock alloc] initWithCondition:OBJECTS_AVAILABLE];
    endOfDataLock = [[NSConditionLock alloc] initWithCondition:MORE_DATA_POSSIBLE];
    return self;
}

- (void)dealloc;
{
    while (first) {
        last = first->next;
        nextObjectInBuffer = first->objects;
        beyondBuffer = first->objects + OWObjectStreamBuffer_BufferedObjectsLength;
        if (first->nextIndex > count)
            beyondBuffer -= (first->nextIndex - count);
        while (nextObjectInBuffer < beyondBuffer)
            CFRelease(*nextObjectInBuffer++);
        free(first);
        first = last;
    }
}

//

- (void)writeObject:(id)anObject;
{
    if (!anObject)
	return;
    [objectsLock lock];
    *nextObjectInBuffer = CFRetain((__bridge CFTypeRef)(anObject));
    count++;
    if (++nextObjectInBuffer == beyondBuffer) {
        last->next = calloc(sizeof(OWObjectStreamBuffer), 1);
        last = last->next;
        last->nextIndex = count + OWObjectStreamBuffer_BufferedObjectsLength;
        last->next = NULL;
        nextObjectInBuffer = last->objects;
        beyondBuffer = last->objects + OWObjectStreamBuffer_BufferedObjectsLength;
    }
    [objectsLock unlockWithCondition:OBJECTS_AVAILABLE];
}

//

- (id)objectAtIndex:(NSUInteger)index withHint:(void **)hint;
{
    OWObjectStreamBuffer *buffer;
    
    if (index >= count && !endOfObjects) {
        [objectsLock lock];
        while (index >= count && !endOfObjects) {
            [objectsLock unlockWithCondition:READERS_WAITING];
            [objectsLock lockWhenCondition:OBJECTS_AVAILABLE];
        }
        [objectsLock unlockWithCondition:OBJECTS_AVAILABLE];
    }
    
    if (index >= count)
        return nil;

    buffer = *(OWObjectStreamBuffer **)hint;
    if (buffer == NULL || ((buffer->nextIndex - index) > OWObjectStreamBuffer_BufferedObjectsLength))
        buffer = first;
    while (buffer->nextIndex <= index)
        buffer = buffer->next;
    *(OWObjectStreamBuffer **)hint = buffer;
    
    return (__bridge id)(buffer->objects[index - (buffer->nextIndex - OWObjectStreamBuffer_BufferedObjectsLength)]);
}

- (id)objectAtIndex:(NSUInteger)index;
{
    void *ignored = NULL;

    return [self objectAtIndex:index withHint:&ignored];
}

- (NSUInteger)objectCount;
{
    [self waitForDataEnd];
    return count;
}

- (BOOL)isIndexPastEnd:(NSUInteger)anIndex
{
    if (anIndex >= count && !endOfObjects) {
        [objectsLock lock];
        while (anIndex >= count && !endOfObjects) {
            [objectsLock unlockWithCondition:READERS_WAITING];
            [objectsLock lockWhenCondition:OBJECTS_AVAILABLE];
        }
        [objectsLock unlockWithCondition:OBJECTS_AVAILABLE];
    }

    if (anIndex >= count)
        return NO;
    else
        return YES;
}

// OWObjectStream subclass

- (void)dataEnd;
{
    [self _noMoreData];
}

- (void)dataAbort;
{
    [self _noMoreData];
}

- (void)waitForDataEnd;
{
    [endOfDataLock lockWhenCondition: DATA_ENDED];
    [endOfDataLock unlock];
}

- (BOOL)endOfData;
{
    return endOfObjects;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (objectsLock)
	[debugDictionary setObject:objectsLock forKey:@"objectsLock"];
    [debugDictionary setObject:endOfObjects ? @"YES" : @"NO" forKey:@"endOfObjects"];
    // UNDONE: debug info for the buffers
    return debugDictionary;
}

@end

@implementation OWObjectStream (Private)

- (void)_noMoreData;
{
    [objectsLock lock];
    endOfObjects = YES;
    [objectsLock unlockWithCondition:OBJECTS_AVAILABLE];
    [endOfDataLock lock];
    [endOfDataLock unlockWithCondition: DATA_ENDED];
}

@end
