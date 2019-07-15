// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObjCRuntime.h> // NSUInteger and BOOL
#import <stddef.h> // For size_t

#ifdef DEBUG
#include <stdio.h>
#endif

typedef struct _OFBTree OFBTree;

typedef void *(*OFBTreeNodeAllocator)(struct _OFBTree *tree);
typedef void (*OFBTreeNodeDeallocator)(struct _OFBTree *tree, void *node);
typedef int  (*OFBTreeElementComparator)(const struct _OFBTree *tree, const void *elementA, const void *elementB);
typedef void (^OFBTreeEnumerator)(const struct _OFBTree *tree, void *element);


struct _OFBTree {
    // None of these fields should be written to (although they can be read if you like)
    union _OFBTreeChildPointer {
        struct _OFBTreeNode *node;
        struct _OFBTreeLeafNode *leaf;
    } root;
    unsigned height;
    size_t nodeSize;
    size_t elementSize;
    size_t elementsPerInternalNode, elementsPerLeafNode;
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

extern void OFBTreeInsert(OFBTree *tree, const void *value);
extern BOOL OFBTreeDelete(OFBTree *tree, void *value);
extern void *OFBTreeFind(const OFBTree *tree, const void *value);
extern void *OFBTreeFindNear(const OFBTree *tree, const void *value, int offset, BOOL afterMatch);
extern void OFBTreeDeleteAll(OFBTree *tree);

extern void OFBTreeEnumerate(const OFBTree *tree, OFBTreeEnumerator enumerator);

// This is not a terribly efficient API but it is reliable and does what I need
extern void *OFBTreePrevious(const OFBTree *tree, const void *value);
extern void *OFBTreeNext(const OFBTree *tree, const void *value);

#ifdef DEBUG
extern void OFBTreeDump(FILE *fp, const OFBTree *tree, void (*dumpValue)(FILE *fp, const OFBTree *btree, const void *value));
#endif
