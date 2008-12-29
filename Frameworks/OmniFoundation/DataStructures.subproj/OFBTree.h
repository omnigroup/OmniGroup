// Copyright 2001-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFBTree.h 102836 2008-07-15 02:13:52Z wiml $

#import <objc/objc.h> // For BOOL
#import <stddef.h> // For size_t

#ifdef DEBUG
#include <stdio.h>
#endif

typedef struct _OFBTree OFBTree;

typedef void *(*OFBTreeNodeAllocator)(struct _OFBTree *tree);
typedef void (*OFBTreeNodeDeallocator)(struct _OFBTree *tree, void *node);
typedef int  (*OFBTreeElementComparator)(struct _OFBTree *tree, const void *elementA, const void *elementB);
typedef void (*OFBTreeEnumeratorCallback)(struct _OFBTree *tree, void *element, void *arg);

struct _OFBTree {
    // None of these fields should be written to (although they can be read if you like)
    void *nodeStack[10];
    void *selectionStack[10];
    int nodeStackDepth;
    struct _OFBTreeNode *root;
    size_t nodeSize;
    size_t elementSize;
    unsigned int elementsPerNode;
    OFBTreeNodeAllocator nodeAllocator;
    OFBTreeNodeDeallocator nodeDeallocator;
    OFBTreeElementComparator elementCompare;
    
    // This can be modified at will
    void *userInfo;
};


extern void OFBTreeInit(OFBTree *tree,
                        size_t nodeSize,
                        size_t elementSize,
                        OFBTreeNodeAllocator allocator,
                        OFBTreeNodeDeallocator deallocator,
                        OFBTreeElementComparator compare);

extern void OFBTreeDestroy(OFBTree *tree);

extern void OFBTreeInsert(OFBTree *tree, void *value);
extern BOOL OFBTreeDelete(OFBTree *tree, void *value);
extern void *OFBTreeFind(OFBTree *tree, void *value);

extern void OFBTreeEnumerate(OFBTree *tree, OFBTreeEnumeratorCallback callback, void *arg);

// This is not a terribly efficient API but it is reliable and does what I need
extern void *OFBTreePrevious(OFBTree *tree, void *value);
extern void *OFBTreeNext(OFBTree *tree, void *value);

#ifdef DEBUG
extern void OFBTreeDump(FILE *fp, OFBTree *tree);
#endif
