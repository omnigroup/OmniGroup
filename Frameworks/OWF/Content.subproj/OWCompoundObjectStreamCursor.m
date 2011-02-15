// Copyright 1997-2005, 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCompoundObjectStreamCursor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWObjectStreamCursor.h>

RCS_ID("$Id$")

@implementation OWCompoundObjectStreamCursor

- initFromCursor:aCursor
{
    OWCursor *copiedCursor;
    
    self = [super initFromCursor:aCursor];
    cursors = [[NSMutableArray alloc] initWithCapacity:2];
    cursorIndex = 0;

    copiedCursor = [aCursor copy];
    [self appendCursor:copiedCursor];
    [copiedCursor release];
    
    return self;
}

- initFromCursor:aCursor andCursor:anotherCursor
{
    OWCursor *copiedCursor;

    self = [self initFromCursor:aCursor];

    copiedCursor = [anotherCursor copy];
    [self appendCursor:copiedCursor];
    [copiedCursor release];

    return self;
}

- (void)dealloc
{
    [cursors release];
    [super dealloc];
}

- copyWithZone:(NSZone *)zone
{
    OWCompoundObjectStreamCursor *cpy;
    int subCursorIndex;
    
    cpy = [[[self class] allocWithZone:zone] initFromCursor:[cursors objectAtIndex:0]];
    for(subCursorIndex = 1; subCursorIndex < [cursors count]; subCursorIndex ++) {
        OWObjectStreamCursor *subCursorCopy = [[cursors objectAtIndex:subCursorIndex] copy];
        [cpy appendCursor:subCursorCopy];
        [subCursorCopy release];
    }
    
    return cpy;
}

- (OWContentType *)contentType;
{
    return [[cursors objectAtIndex:0] contentType];
}

- readObject;
{
    id obj;
    if (abortException)
        [abortException raise];

    obj = nil;
    while (!obj && cursorIndex < [cursors count]) {
        obj = [[cursors objectAtIndex:cursorIndex] readObject];
        if (!obj)
            cursorIndex ++;
    }

    return obj;
}

- (void)skipObjects:(int)count;
{
    [self seekToOffset:count fromPosition:OWCursorSeekFromCurrent];
}

- (void)ungetObject:anObject;
{
    /* NB. This won't work if you unget from one cursor to a previous
       one. You can always unget an object you've just read (since
       we don't advance the cursor index until necessary), but
       you can't necessarily unget two objects. */
    [[cursors objectAtIndex:cursorIndex] ungetObject:anObject];
}

- (NSUInteger)seekToOffset:(NSInteger)offset fromPosition:(OWCursorSeekPosition)position;
{
    if (abortException)
        [abortException raise];

    switch (position) {
        case OWCursorSeekFromCurrent:
            if (offset >= 0) {
                while (offset > 0) {
                    [self readObject];
                    offset--;
                }
                break;
            }
            [NSException raise:@"BadSeek" format:@"OWCompoundObjectStreamCursor: unable to seek<%d> offset=%d", position, offset];

        case OWCursorSeekFromEnd:
        case OWCursorSeekFromStart:
#warning -seekToOffset:fromPosition: should implemented non-current positions someday
            // These are implementable, but since they're not called by any existing code, I'm not going to worry about them right now
            [NSException raise:@"BadSeek" format:@"OWCompoundObjectStreamCursor: unable to seek<%d> offset=%d", position, offset];
    }

    return 0;
}

- (NSArray *)cursors
{
    return cursors;
}

- (int)cursorIndex
{
    return cursorIndex;
}

/* This holds on to and modifies the cursor it is given. */
- (void)appendCursor:(OWCursor *)interj
{
    if ([interj isMemberOfClass:[self class]]) {
        NSArray *otherCursors = [(OWCompoundObjectStreamCursor *)interj cursors];
        int otherCursorsIndex = [(OWCompoundObjectStreamCursor *)interj cursorIndex];
        int otherCursorsCount = [otherCursors count];
        int copyIndex = otherCursorsIndex;

        while(copyIndex < otherCursorsCount) {
            [self appendCursor:[otherCursors objectAtIndex:copyIndex]];
            copyIndex ++;
        }
        return;
    }

    [cursors addObject:interj];
}

- (void)prependCursor:(OWCursor *)interj
{
    if ([interj isMemberOfClass:[self class]]) {
        NSArray *otherCursors = [(OWCompoundObjectStreamCursor *)interj cursors];
        int otherCursorsIndex = [(OWCompoundObjectStreamCursor *)interj cursorIndex];
        int otherCursorsCount = [otherCursors count];
        int copyIndex = otherCursorsCount;

        while(copyIndex > otherCursorsIndex) {
            copyIndex --;
            [self prependCursor:[otherCursors objectAtIndex:copyIndex]];
        }
        return;
    }

    if ([cursors count])
        [cursors insertObject:interj atIndex:0];
    else
        [cursors addObject:interj];

    cursorIndex = 0;
}

@end
