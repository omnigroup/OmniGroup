// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWImmutableObjectStream.h"

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/OWImmutableObjectStream.m 68913 2005-10-03 19:36:19Z kc $");

@implementation OWImmutableObjectStream

// Init and dealloc

- initWithObject:(NSObject *)anObject
{
    return [self initWithArray:[NSArray arrayWithObject:anObject]];
}

- initWithArray:(NSArray *)contents;
{
    if ([super init] == nil)
        return nil;

    objects = [contents retain];

    return self;
}

- (void)dealloc;
{
    [objects release];
    [super dealloc];
}


// API
- (id)objectAtIndex:(unsigned int)objectIndex;
{
    if (objectIndex >= [objects count])
        return nil;
    else
        return [objects objectAtIndex:objectIndex];
}

- (id)objectAtIndex:(unsigned int)objectIndex withHint:(void **)hint;
{
    if (objectIndex >= [objects count])
        return nil;
    else
        return [objects objectAtIndex:objectIndex];
}

- (unsigned int)objectCount
{
    return [objects count];
}

- (BOOL)isIndexPastEnd:(unsigned int)objectIndex
{
    return ( objectIndex >= [objects count] );
}

/* We inherit -waitForDataEnd and -endOfData from OWStream */

@end

