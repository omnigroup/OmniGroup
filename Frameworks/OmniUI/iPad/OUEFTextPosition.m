// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUEFTextPosition.h"

#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OUEFTextPosition : UITextPosition

- initWithIndex:(NSUInteger)ix
{
    [super init];
    index = ix;
    return self;
}

- copyWithZone:(NSZone *)z
{
    if (NSShouldRetainWithZone(self, z)) {
        return [self retain];
    } else {
        OUEFTextPosition *result = [[OUEFTextPosition allocWithZone:z] initWithIndex:index];
        result->generation = generation;
        return result;
    }
}

@synthesize index;
@synthesize generation;

- (NSComparisonResult)compare:other;
{
    assert([other isKindOfClass:[self class]]);
    
    NSUInteger mine = index;
    NSUInteger theirs = ((OUEFTextPosition *)other)->index;
    
    if (mine < theirs)
        return NSOrderedAscending;
    else if (mine == theirs)
        return NSOrderedSame;
    else
        return NSOrderedDescending;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%lu/%lu", (unsigned long)index, (unsigned int)generation];
}

@end

