// Copyright 2002-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableSet-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@implementation NSMutableSet (OFExtensions)

- (void)addObjects:(id)firstObject, ...;
{
    if (firstObject == nil)
        return;
    
    [self addObject:firstObject];
    
    id next;
    va_list argList;
    
    va_start(argList, firstObject);
    while ((next = va_arg(argList, id)) != nil)
        [self addObject:next];
    va_end(argList);
}

- (void)removeObjectsFromArray:(NSArray *)objects;
{
    for (id object in objects)
        [self removeObject:object];
}

- (void)exclusiveDisjointSet:(NSSet *)otherSet;
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
