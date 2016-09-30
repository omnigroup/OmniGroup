// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCompoundObjectStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWObjectStreamCursor.h>

RCS_ID("$Id$")


@implementation OWCompoundObjectStream

+ (OWObjectStreamCursor *)cursorAtCursor:(OWObjectStreamCursor *)aCursor beforeStream:(OWAbstractObjectStream *)interjectMe;
{
    OWCompoundObjectStream *newStream;
    OWAbstractObjectStream *frame, *interject;
    OWObjectStreamCursor *newCursor;
    NSUInteger interjectWhere, newCursorPosition;

    frame = [aCursor objectStream];
    interject = interjectMe;
    interjectWhere = [aCursor streamIndex];

    newStream = [[self alloc] initWithStream:frame interjectingStream:interject atIndex:interjectWhere];

    newCursor = [newStream createCursor];


    if (interjectWhere > 0)
        newCursorPosition = [newStream translateIndex:interjectWhere - 1 fromStream:frame] + 1;
    else
        newCursorPosition = 0;
    
    [newCursor seekToOffset:newCursorPosition fromPosition:OWCursorSeekFromStart];

    return newCursor;
}

- initWithStream:(OWAbstractObjectStream *)aStream interjectingStream:(OWAbstractObjectStream *)anotherStream atIndex:(NSUInteger)index;
{
    self = [super init];
    framingStream = aStream;
    interjectedStream = anotherStream;
    interjectedAtIndex = index;

    return self;
}

- (id)objectAtIndex:(NSUInteger)index;
{
    id anItem;
    
    if (index < interjectedAtIndex)
        return [framingStream objectAtIndex:index];


    anItem = [interjectedStream objectAtIndex:(index - interjectedAtIndex)];
    if (anItem)
        return anItem;

    return [framingStream objectAtIndex:(index - [interjectedStream objectCount])];
}

- (NSUInteger)objectCount;
{
    NSUInteger count = [framingStream objectCount];

    if (count >= interjectedAtIndex)
        count += [interjectedStream objectCount];

    return count;
}

- (NSUInteger)translateIndex:(NSUInteger)index fromStream:(OWAbstractObjectStream *)aStream;
{
    if (aStream == self)
        return index;

    if (aStream == framingStream) {
        if (index < interjectedAtIndex) {
            return index;
        } else {
            return index + [interjectedStream objectCount];
        }
    }

    if (aStream == interjectedStream)
        return index + interjectedAtIndex;

    if ([framingStream respondsToSelector:_cmd]) {
        NS_DURING {
            NSUInteger framingIndex = [(OWCompoundObjectStream *)framingStream translateIndex:index fromStream:aStream];

            if (framingIndex >= interjectedAtIndex)
                framingIndex += [interjectedStream objectCount];

            NS_VALUERETURN(framingIndex, unsigned int);
        } NS_HANDLER {
            if (![[localException name] isEqualToString:@"UnknownStream"])
                [localException raise];
        } NS_ENDHANDLER;
    }

    if ([interjectedStream respondsToSelector:_cmd]) {
        NSUInteger interjectedIndex = [(OWCompoundObjectStream *)interjectedStream translateIndex:index fromStream:aStream];

        // TODO: Should we check that the returned index is less than [interjectedStream objectCount]? Doing so might cause an unnecessary block for end of data in -objectCount.
        
        return interjectedIndex + interjectedAtIndex;
    }

    // This is only a real internal error if we don't catch it. In the places compound streams are used right now, I don't think this will ever get raised in the first place.
    [NSException raise:@"UnknownStream" reason:@"Internal error: unknown stream in -[OWCompoundObjectStream translateIndex:fromStream:]"];
    return NSNotFound; // make the compiler happy
}

- (void)waitForDataEnd;
{
    [interjectedStream waitForDataEnd];
    [framingStream waitForDataEnd];
}

@end
