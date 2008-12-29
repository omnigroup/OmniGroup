// Copyright 2002-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableSet-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSMutableSet-OFExtensions.m 104166 2008-08-19 22:47:53Z wiml $");

@implementation NSMutableSet (OFExtensions)

- (void) removeObjectsFromArray: (NSArray *) objects;
{
    unsigned int objectIndex;
    
    objectIndex = [objects count];
    while (objectIndex--)
        [self removeObject: [objects objectAtIndex: objectIndex]];
}

- (void) exclusiveDisjoinSet: (NSSet *) otherSet;
{
    /* special case: avoid modifying set while enumerating over it */
    if (otherSet == self) {
        [self removeAllObjects];
        return;
    }

    /* general case */
    for (id otherElement in otherSet) {
        if ([self containsObject:otherElement])
            [self removeObject:otherElement];
        else
            [self addObject:otherElement];
    }
}


@end
