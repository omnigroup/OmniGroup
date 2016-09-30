// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWImmutableObjectStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OWImmutableObjectStream
{
    NSArray *objects;
}

// Init and dealloc

- (instancetype)initWithObject:(NSObject *)anObject
{
    return [self initWithArray:@[anObject]];
}

- (instancetype)initWithArray:(NSArray *)contents;
{
    if (!(self = [super init]))
        return nil;

    objects = contents;

    return self;
}

// API
- (id)objectAtIndex:(NSUInteger)objectIndex;
{
    if (objectIndex >= [objects count])
        return nil;
    else
        return [objects objectAtIndex:objectIndex];
}

- (id)objectAtIndex:(NSUInteger)objectIndex withHint:(void **)hint;
{
    if (objectIndex >= [objects count])
        return nil;
    else
        return [objects objectAtIndex:objectIndex];
}

- (NSUInteger)objectCount
{
    return [objects count];
}

- (BOOL)isIndexPastEnd:(NSUInteger)objectIndex
{
    return ( objectIndex >= [objects count] );
}

/* We inherit -waitForDataEnd and -endOfData from OWStream */

@end

