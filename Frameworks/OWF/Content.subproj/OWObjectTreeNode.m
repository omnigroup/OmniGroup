// Copyright 1997-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectTreeNode.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWObjectTree.h>

RCS_ID("$Id$")

@interface OWObjectTreeNodeChildEnumerator : NSEnumerator
{
    unsigned int index;
    OWObjectTreeNode *node;
}

- initWithNode:(OWObjectTreeNode *)aNode;

@end



@implementation OWObjectTreeNodeChildEnumerator

- initWithNode:(OWObjectTreeNode *)aNode;
{
    [super init];
    node = [aNode retain];
    return self;
}

- (void)dealloc;
{
    [node release];
    [super dealloc];
}

- nextObject
{
    return [node childAtIndex:index++];
}

@end

@implementation OWObjectTreeNode

- (void)dealloc;
{
    [representedObject release];
    [children release];
    [super dealloc];
}

- (void)addChild:(OWObjectTreeNode *)aChild;
{
    os_unfair_lock *mutex = [nonretainedRoot mutex];
    OWObjectTreeNode *node;

    node = [[OWObjectTreeNode alloc] initWithParent:self representedObject:aChild];

    os_unfair_lock_lock(mutex);
    if (!children)
        children = [[NSMutableArray alloc] init];
    [children addObject:node];
    os_unfair_lock_unlock(mutex);

    [node release];
}

- (void)childrenEnd;
{
    isComplete = YES;
}

- (OWObjectTreeNode *)parent;
{
    return nonretainedParent;
}

- (OWObjectTree *)root;
{
    return nonretainedRoot;
}

- (id <NSObject>)representedObject;
{
    return representedObject;
}

- (NSEnumerator *)childEnumerator;
{
    return [[[OWObjectTreeNodeChildEnumerator alloc] initWithNode:self] autorelease];
}

- (unsigned int)childCount;
{
    [self waitForChildren];
    return [children count];
}

- (OWObjectTreeNode *)childAtIndex:(unsigned int)index;
{
    OWObjectTreeNode *result;
    os_unfair_lock *mutex = NULL;
    
    if (!isComplete) {
        mutex = [nonretainedRoot mutex];    

        while(1) {
            os_unfair_lock_lock(mutex);
            if (isComplete || [children count] > index)
                break;
            os_unfair_lock_unlock(mutex);
            sched_yield();
        }
    } 
    if ([children count] > index)
        result = [children objectAtIndex:index];
    else
        result = nil;
    if (mutex)
        os_unfair_lock_unlock(mutex);
    return result;
}

- (void)waitForChildren;
{
    while (!isComplete)
        sched_yield();
}

@end

@implementation OWObjectTreeNode (OWPrivateInitializer)

- initWithParent:(OWObjectTreeNode *)parent representedObject:(id <NSObject>)object;
{
    [super init];
    nonretainedParent = parent;
    representedObject = [object retain];
    nonretainedRoot = [parent root];
    children = nil;
    isComplete = NO;
    return self;
}

@end

