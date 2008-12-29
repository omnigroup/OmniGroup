// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/OWObjectTreeNode.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class OWObjectTree;
@class NSMutableArray;

@interface OWObjectTreeNode : OFObject
{
    OWObjectTreeNode *nonretainedParent;
    OWObjectTree *nonretainedRoot;
    id <NSObject> representedObject;
    NSMutableArray *children;
    BOOL isComplete;
}

- (void)addChild:(OWObjectTreeNode *)aChild;
- (void)childrenEnd;

- (OWObjectTreeNode *)parent;
- (OWObjectTree *)root;
- (id <NSObject>)representedObject;
- (NSEnumerator *)childEnumerator;
- (unsigned int)childCount;
- (OWObjectTreeNode *)childAtIndex:(unsigned int)index;

- (void)waitForChildren;

@end

@interface OWObjectTreeNode (OWPrivateInitializer)
- initWithParent:(OWObjectTreeNode *)parent representedObject:(id <NSObject>)object;
@end
