// Copyright 2001-2005, 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBTree.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")


/*"
Each node in the btree has some non-zero number of elements (depending upon whether it is the root node or not different constraints apply).  If there are N elements, there are always N+1 pointers to children nodes.
 
 In a leaf node, all the child pointers will be NULL; since the majority of nodes are leaf nodes, it's worth optimizing this case by using a different struct for leaf nodes than for internal nodes, and omitting the child pointers.
"*/

/* A generic pointer to a leaf or internal node. */
/* This is a union rather than a (void *) to force me to explicitly think about the node type every time I dereference it. */
typedef union _OFBTreeChildPointer OFBTreeChildPointer;

/* An internal node */
typedef struct _OFBTreeNode {
    size_t elementCount;
    OFBTreeChildPointer childZero;
    uint8_t contents[0];
} OFBTreeNode;

/* A leaf node, without space for child pointers */
typedef struct _OFBTreeLeafNode {
    size_t elementCount;
    uint8_t contents[0];
} OFBTreeLeafNode;

/*" OFBTreeCursor holds the path from the tree's root to a location in the tree. "*/
typedef struct _OFBTreeCursor {
    OFBTreeChildPointer nodeStack[10];
    void *selectionStack[10];
    unsigned nodeStackDepth;
} OFBTreeCursor;


#ifdef DEBUG
NSString *OFBTreeDescribeCursor(const OFBTree *tree, const OFBTreeCursor *cursor);
#endif

#if defined(__OBJC_GC__) && __OBJC_GC__
// Scribble on the released elements so that the GC doesn't think any pointers are still live
// It's unclear how important or useful this actually is for GC performance, but it is helpful for debugging.
static const uint32_t badfood = 0xBAADF00D;
#define SCRIBBLE(addr, len) memset_pattern4(addr, &badfood, len)
#else
#define SCRIBBLE(addr, len) /* not needed */
#endif

void OFBTreeInit(OFBTree *tree,
                 size_t nodeSize,
                 size_t elementSize,
                 OFBTreeNodeAllocator allocator,
                 OFBTreeNodeDeallocator deallocator,
                 OFBTreeElementComparator compare)
{    
    memset(tree, 0, sizeof(*tree));
    tree->nodeSize = nodeSize;
    tree->elementSize = elementSize;
    
    // Compute the elements per node.  Take the node size and subtract the space for the header and the extra child pointer.  Finally, divide by the space per element (the element size itself and the pointer for children after it).
    tree->elementsPerInternalNode = (nodeSize - sizeof(OFBTreeNode)) / (elementSize + sizeof(OFBTreeChildPointer));
    tree->elementsPerLeafNode = (nodeSize - sizeof(OFBTreeLeafNode)) / (elementSize);
    
    OBASSERT(tree->elementsPerInternalNode > 2); // Our algorithms fail for really tiny "page" sizes
    
    tree->nodeAllocator = allocator;
    tree->nodeDeallocator = deallocator;
    tree->elementCompare = compare;
    
    // We always have at least one node
    // When the tree is small, our only node is a leaf node
    tree->root.leaf = tree->nodeAllocator(tree);
    tree->root.leaf->elementCount = 0;
    tree->height = 1;
}

static void _OFBTreeDeallocateChildren(OFBTree *tree, OFBTreeNode *node, unsigned height)
{
    void *childPointer = &( node->childZero );
    size_t elementStep = tree->elementSize + sizeof(OFBTreeChildPointer);
    for(size_t elementIndex = 0; elementIndex <= node->elementCount; elementIndex ++) {
        OFBTreeChildPointer childNode = *(OFBTreeChildPointer *)childPointer;
        if (height > 1) {
            _OFBTreeDeallocateChildren(tree, childNode.node, height-1);
            tree->nodeDeallocator(tree, childNode.node);
        } else {
            tree->nodeDeallocator(tree, childNode.leaf);
        }
        childPointer += elementStep;
    }
}

void OFBTreeDestroy(OFBTree *tree)
{
    if (tree->height > 1) {
        _OFBTreeDeallocateChildren(tree, tree->root.node, tree->height);
        tree->nodeDeallocator(tree, tree->root.node);
    } else {
        tree->nodeDeallocator(tree, tree->root.leaf);
    }
}

static inline BOOL _isAtLeafNode(const OFBTree *btree, const OFBTreeCursor *cursor)
{
    return (cursor->nodeStackDepth+1 >= btree->height);
}

static inline ptrdiff_t _OFBTreeValueStride(const OFBTree *btree, const OFBTreeCursor *cursor)
{
    if (_isAtLeafNode(btree, cursor)) {
        /* Leaf node, no child pointers */
#define LEAF_STRIDE(tree) (tree->elementSize)
        return LEAF_STRIDE(btree); 
    } else {
        /* Interior node, has child pointers */
#define NODE_STRIDE(tree) (tree->elementSize + sizeof(OFBTreeChildPointer))
        return NODE_STRIDE(btree);
    }
}
#define ELEMENT_AT_INDEX(node, stride, index) ( (void *)((node)->contents) + (index)*(stride) )

extern void OFBTreeDeleteAll(OFBTree *tree)
{
    if (tree->height > 1) {
        _OFBTreeDeallocateChildren(tree, tree->root.node, tree->height);
        tree->nodeDeallocator(tree, tree->root.node);
        tree->root.leaf = tree->nodeAllocator(tree);
        tree->root.leaf->elementCount = 0;
    } else {
        SCRIBBLE(tree->root.leaf->contents, tree->root.leaf->elementCount * LEAF_STRIDE(tree));
        tree->root.leaf->elementCount = 0;
    }
    tree->height = 1;
}

static inline OFBTreeChildPointer _OFBTreeValueLesserChildNode(const OFBTree *btree, void *value)
{
    return *(OFBTreeChildPointer *)(value - sizeof(OFBTreeChildPointer));
}

static inline OFBTreeChildPointer _OFBTreeValueGreaterChildNode(const OFBTree *btree, void *value)
{
    return *(OFBTreeChildPointer *)(value + btree->elementSize);
}

/*" Scan a node for the closest match greater than or equal to a value.
 If a match is found, returns YES and leaves the cursor positioned at that value.
 Otherwise, returns NO and leaves the cursor positioned at the first entry greater than the value.
"*/
static BOOL _OFBTreeScan(const OFBTree *btree, OFBTreeCursor *cursor, const void *value)
{
    NSUInteger low = 0;
    NSUInteger range = 1;
    NSUInteger test = 0;
    size_t elementCount;
    ptrdiff_t stride;
    void *element0;
    void *testValue;
    int testResult;
    
    OFBTreeChildPointer node = cursor->nodeStack[cursor->nodeStackDepth];
    if (_isAtLeafNode(btree, cursor)) {
        elementCount = node.leaf->elementCount;
        stride = LEAF_STRIDE(btree);
        element0 = node.leaf->contents;
    } else {
        elementCount = node.node->elementCount;
        stride = NODE_STRIDE(btree);
        element0 = node.node->contents;
    }
    
    while(elementCount >= range) // range is the lowest power of 2 > count
        range <<= 1;

    while(range) {
        test = low + (range >>= 1);
        if (test >= elementCount)
            continue;
        testValue = element0 + test * stride;
        testResult = btree->elementCompare(btree, value, testValue);
        if (!testResult) {
            cursor->selectionStack[cursor->nodeStackDepth] = testValue;
            return YES;
        } else if (testResult > 0) {
            low = test + 1;
        }
    }
    cursor->selectionStack[cursor->nodeStackDepth] = element0 + low * stride;
    return NO;
}

/*" Internal find method.
 Initializes the cursor struct and searches for value.
 Returns YES if the value was found, or NO if not found (in which case the cursor points to the next value).
"*/
static BOOL _OFBTreeFind(const OFBTree *btree, OFBTreeCursor *cursor, const void *value)
{
    OFBTreeChildPointer childNode;
    
    cursor->nodeStack[0] = btree->root;
    cursor->nodeStackDepth = 0;
    while(1) {
        if (_OFBTreeScan(btree, cursor, value)) {
            return YES;
        } else if (!_isAtLeafNode(btree, cursor)) {
            childNode = _OFBTreeValueLesserChildNode(btree, cursor->selectionStack[cursor->nodeStackDepth]);
            cursor->nodeStack[++cursor->nodeStackDepth] = childNode;
        } else {
            return NO;
        }
    }
}

/*" Internal find method. Sets the cursor to the first element in the subtree it currently points to, or returns NULL if the tree is empty. Unlike most _OFBTreeCursor methods this is given a cursor in a slightly inconsistent state: nodeStack[depth] is valid but selectionStack[depth] has not been initialized yet. "*/
static void *_OFBTreeSelectFirst(const OFBTree *btree, OFBTreeCursor *cursor)
{
    unsigned height = btree->height;
    unsigned depth;
    OFBTreeChildPointer node;

    depth = cursor->nodeStackDepth;
    node = cursor->nodeStack[depth];
    
    /* Traverse all the interior nodes */
    while (height > (depth+1)) {
        cursor->selectionStack[depth] = node.node->contents; /* element at index 0 */
        depth ++;
        node = node.node->childZero;
        cursor->nodeStack[depth] = node;
    };
    
    /* And end up at the leaf node */
    cursor->nodeStackDepth = depth;
    OBASSERT(_isAtLeafNode(btree, cursor));

    // The root is the only node that's allowed to have a zero element count
    // and even then, only if it's a leaf node
    if (depth == 0 && !node.leaf->elementCount)
        return NULL;
        
    cursor->selectionStack[depth] = node.leaf->contents; /* element at index 0 */
    
    return node.leaf->contents;
}

/*" Internal find method. Sets the cursor to the last element in the subtree it currently points to, or returns NULL if the tree is empty. Unlike most _OFBTreeCursor methods this is given a cursor in a slightly inconsistent state: nodeStack[depth] is valid but selectionStack[depth] has not been initialized yet. "*/
static void *_OFBTreeSelectLast(const OFBTree *btree, OFBTreeCursor *cursor)
{
    unsigned height = btree->height;
    unsigned depth;
    OFBTreeChildPointer node;
    
    depth = cursor->nodeStackDepth;
    node = cursor->nodeStack[depth];
    
    /* Traverse all the interior nodes */
    ptrdiff_t stride = NODE_STRIDE(btree); // interior node stride
    while (height > (depth+1)) {
        cursor->selectionStack[depth] = ELEMENT_AT_INDEX(node.node, stride, node.node->elementCount);
        node = _OFBTreeValueLesserChildNode(btree, cursor->selectionStack[depth]);
        depth ++;
        cursor->nodeStack[depth] = node;
    };
    
    /* And end up at the leaf node */
    cursor->nodeStackDepth = depth;
    OBASSERT(_isAtLeafNode(btree, cursor));
    
    // The root is the only node that's allowed to have a zero element count
    // and even then, only if it's a leaf node
    if (depth == 0 && !node.leaf->elementCount)
        return NULL;
    
    stride = LEAF_STRIDE(btree); // leaf node stride
    // Most of the selection stack points to the nonexistent element after the last child node pointer; the deepest entry points to an actual element.
    void *lastElement = ELEMENT_AT_INDEX(node.leaf, stride, node.leaf->elementCount - 1);
    cursor->selectionStack[depth] = lastElement;
    OBASSERT(cursor->selectionStack[depth] >= ELEMENT_AT_INDEX(node.leaf, stride, 0));
    
    return lastElement;
}

/*"
 Copies the bytes pointed to by value into the position indicated by the cursor.
 "*/
static void _OFBTreeSimpleAdd_Int(OFBTree *btree, OFBTreeNode *node, void *insertionPoint, const void *value)
{
    const size_t entrySize = NODE_STRIDE(btree);
    void *end = (void *)node->contents + entrySize * node->elementCount;
    memmove(insertionPoint + entrySize, insertionPoint, end - insertionPoint);
    memcpy(insertionPoint, value, entrySize);
    node->elementCount++;
}
/*"
 Copies the bytes pointed to by value into the position indicated by the cursor.
 "*/
static void _OFBTreeSimpleAdd_Leaf(OFBTree *btree, OFBTreeLeafNode *node, void *insertionPoint, const void *value)
{
    const size_t entrySize = LEAF_STRIDE(btree);
    void *end = (void *)node->contents + entrySize * node->elementCount;
    memmove(insertionPoint + entrySize, insertionPoint, end - insertionPoint);
    memcpy(insertionPoint, value, entrySize);
    node->elementCount++;
}

/*" Split the current node and promote the center.
"*/
static void _OFBTreeSplitAdd(OFBTree *btree, OFBTreeCursor *cursor, const void *value, void *promotionBuffer)
{
    void *insertionPoint;
    OFBTreeChildPointer rightptr;
    size_t leftElementCount, rightElementCount;
    ptrdiff_t entrySize;
    void *leftContents, *rightContents;
    
    // NSLog(@"SplitAdd: value=%d cursor=%@", *(const int *)value, OFBTreeDescribeCursor(btree, cursor));

    insertionPoint = cursor->selectionStack[cursor->nodeStackDepth];
    if (_isAtLeafNode(btree, cursor)) {
        OFBTreeLeafNode *node = cursor->nodeStack[cursor->nodeStackDepth].leaf;
        entrySize = LEAF_STRIDE(btree);
        
        // build the new right hand side
        OFBTreeLeafNode *right = btree->nodeAllocator(btree);
        rightptr.leaf = right;
        rightElementCount = right->elementCount = node->elementCount / 2;
        leftElementCount = node->elementCount = ( node->elementCount - rightElementCount );
        leftContents = node->contents;
        rightContents = right->contents;
    } else {
        OFBTreeNode *node = cursor->nodeStack[cursor->nodeStackDepth].node;
        entrySize = NODE_STRIDE(btree);

        // build the new right hand side
        OFBTreeNode *right = btree->nodeAllocator(btree);
        rightptr.node = right;
        right->elementCount = rightElementCount = node->elementCount / 2;
        node->elementCount = leftElementCount = ( node->elementCount - rightElementCount );
        leftContents = node->contents;
        rightContents = right->contents;
    }

    /* splitPoint points to the end of the data we're keeping in the left node (that is, it points to the first byte past the last entry) */
    void *splitPoint = leftContents + leftElementCount * entrySize;
    if (insertionPoint <= splitPoint) {
        // the insertion point is in the center or left so just copy over the whole right side
        memcpy(rightContents, splitPoint, rightElementCount * entrySize);
        
        if (insertionPoint == splitPoint) {
            // the value being inserted is exactly in the center, so it just ends up one level higher
            if (promotionBuffer != value)
                memcpy(promotionBuffer, value, entrySize);
        } else {
            // the insertion point isn't in the center so the value needs to be inserted into the left side
            memmove(insertionPoint + entrySize, insertionPoint, splitPoint - insertionPoint);
            memcpy(insertionPoint, value, entrySize);
            // and the center value (temporarily shifted by the above memmove()) gets put into the promotion buffer
            // we can't trivially avoid the memmove because it's possible to have value==promotionBuffer
            memcpy(promotionBuffer, splitPoint, entrySize);
        }
    } else {
        // the insertion point is in the right side so copy before insertion, then new value, then after insertion
        // (the data actually at splitPoint goes to the promotion buffer)
        ptrdiff_t bytesBeforeInsertion = insertionPoint - (splitPoint+entrySize);
        memcpy(rightContents, splitPoint + entrySize, bytesBeforeInsertion);
        memcpy(rightContents + bytesBeforeInsertion, value, entrySize);
        ptrdiff_t rightRemaining = (rightElementCount * entrySize) - (bytesBeforeInsertion + entrySize);
        memcpy(rightContents + bytesBeforeInsertion + entrySize, insertionPoint, rightRemaining);
        // and the center value gets put into the promotion buffer
        memcpy(promotionBuffer, splitPoint, entrySize);
    }
    
    OFBTreeChildPointer *promotedChildPointer = ( promotionBuffer + NODE_STRIDE(btree) ) - sizeof(OFBTreeChildPointer);
    if (!_isAtLeafNode(btree, cursor)) {
        // The center value we promoted carried with it its right-hand child node pointer
        // The pointer belongs in childZero of the new right-hand node
        rightptr.node->childZero = *promotedChildPointer;
        // and the promoted node should carry the new right-hand child node
        *promotedChildPointer = rightptr;
    } else {
        // The center value was promoted from a leaf, so it doesn't bring a child node pointer with it
        // But it will be inserted into an internal node, and needs to carry the new right-hand child
        *promotedChildPointer = rightptr;
    }
}

/*"
Copies the bytes pointed to by value and puts them in the tree.
"*/
void OFBTreeInsert(OFBTree *btree, const void *value)
{
    void *promotionBuffer;
    OFBTreeCursor cursor;

    if (_OFBTreeFind(btree, &cursor, value))
        return; // the value is already in the tree
    
    // The cursor must be left at a leaf node for the code below to work: if called on an internal node,_OFBTreeAdd expects its input buffer to contain a new child node pointer to insert along with the value. We won't have a new child node pointer to give it until after we've done a node split.
    {
        OBASSERT(_isAtLeafNode(btree, &cursor));
        OFBTreeLeafNode *node = cursor.nodeStack[cursor.nodeStackDepth].leaf;
        
        if (node->elementCount < btree->elementsPerLeafNode) {
            // Simple addition - add to the current node
            _OFBTreeSimpleAdd_Leaf(btree, node, cursor.selectionStack[cursor.nodeStackDepth], value);
            return;
        }
    }
        
    /* Otherwise, we must split the current node, resulting in new nodes and a new middle entry to insert in the parent node; repeat as needed. */
    
    promotionBuffer = alloca(NODE_STRIDE(btree)); // Promotion buffer holds value plus new child node.
    
    for(;;) {
        /* Simple insert failed; split the node */
        _OFBTreeSplitAdd(btree, &cursor, value, promotionBuffer);
        value = promotionBuffer;

        if (cursor.nodeStackDepth) {
            // if we're deep in the tree go up to the next higher level and try again
            cursor.nodeStackDepth--;
            
            OFBTreeNode *node = cursor.nodeStack[cursor.nodeStackDepth].node;
            if (node->elementCount < btree->elementsPerInternalNode) {
                // Simple addition - add to the current node
                _OFBTreeSimpleAdd_Int(btree, node, cursor.selectionStack[cursor.nodeStackDepth], value);
                break;
            }
            
            // continue the loop to split the parent node as well
        } else {
            // otherwise we need a new root
            OFBTreeNode *newRoot;
            
            newRoot = btree->nodeAllocator(btree);
            newRoot->elementCount = 1;
            newRoot->childZero = btree->root;
            memcpy(newRoot->contents, promotionBuffer, NODE_STRIDE(btree));
            
            btree->root.node = newRoot;
            btree->height ++;
            break;
        }
    }
}

static void _OFBTreeDidShrink(OFBTree *btree, OFBTreeCursor *cursor);

static void _OFBTreeRotate(OFBTree *btree, OFBTreeCursor *cursor)
{
    OFBTreeChildPointer left, right;
    void *apex;
    OFBTreeNode *apexNode;
    
    // NSLog(@"rotating:  cursor = %@", OFBTreeDescribeCursor(btree, cursor));
    
    // Can't rotate a leaf node!
    OBASSERT(!_isAtLeafNode(btree, cursor));
    
    apex = cursor->selectionStack[cursor->nodeStackDepth];
    apexNode = cursor->nodeStack[cursor->nodeStackDepth].node;
    left = _OFBTreeValueLesserChildNode(btree, apex);
    right = _OFBTreeValueGreaterChildNode(btree, apex);
    const size_t elementSize = btree->elementSize;
    size_t leftCount, rightCount, childMaxElts;
    ptrdiff_t apexStride, childStride;
    void *leftContents;
    
    apexStride = NODE_STRIDE(btree);
    
    BOOL childrenAreLeaves;
    if (btree->height > (cursor->nodeStackDepth+2)) {
        childrenAreLeaves = NO;
        leftCount = left.node->elementCount;
        leftContents = left.node->contents;
        rightCount = right.node->elementCount;
        childMaxElts = btree->elementsPerInternalNode;
        childStride = NODE_STRIDE(btree);
    } else {
        OBASSERT(cursor->nodeStackDepth+2 == btree->height);
        childrenAreLeaves = YES;
        leftCount = left.leaf->elementCount;
        leftContents = left.leaf->contents;
        rightCount = right.leaf->elementCount;
        childMaxElts = btree->elementsPerLeafNode;
        childStride = LEAF_STRIDE(btree);
    }
        
    size_t totalElements = leftCount + rightCount + 1;
    if (totalElements <= childMaxElts) {
        // NSLog(@"unsplitting: %d", (int)totalElements);
        // Both nodes and their intervening element can be packed into a single node ("unsplit" operation).
        // We'll pack everything into the left node and deallocate the right node.
        void *appendHere = leftContents + childStride * leftCount;
        memcpy(appendHere, apex, elementSize);
        appendHere += childStride;
        if (!childrenAreLeaves) {
            ((OFBTreeChildPointer *)appendHere)[-1] = right.node->childZero;
            memcpy(appendHere, right.node->contents, rightCount * childStride);
            left.node->elementCount = totalElements;
        } else {
            memcpy(appendHere, right.leaf->contents, rightCount * childStride);
            left.leaf->elementCount = totalElements;
        }

        // And remove the apex element and its right node pointer from the node it occupied
        apexNode->elementCount --;
        void *newApexNodeEnd = ELEMENT_AT_INDEX(apexNode, apexStride, apexNode->elementCount);
        memmove(apex, apex + apexStride, newApexNodeEnd - apex);
        SCRIBBLE(newApexNodeEnd, apexStride);
        // Deallocate the now-empty and unreferenced old right node.
        btree->nodeDeallocator(btree, right.node);

        _OFBTreeDidShrink(btree, cursor);
        return;
    } else {
        // We can't fit everything into one node, so redistribute the elements
        // more evenly in two nodes.
        size_t newLeftCount = ( totalElements - 1 ) / 2;
        size_t newRightCount = totalElements - newLeftCount - 1;
        if (leftCount < newLeftCount) {
            // NSLog(@"rotating left: %d -> %d,%d", (int)totalElements, (int)newLeftCount, (int)newRightCount);
            // The left node is emptier. Shift some elements over there.
            void *appendHere = leftContents + childStride * leftCount;
            size_t shifting = newLeftCount - leftCount;
            // the apex node gets shifted into the left node...
            memcpy(appendHere, apex, elementSize);
            appendHere += childStride;
            void *rightContents;
            size_t lagniappe;
            if (childrenAreLeaves) {
                rightContents = right.leaf->contents;
                lagniappe = 0;
            } else {
                rightContents = right.node->contents;
                lagniappe = sizeof(OFBTreeChildPointer);
            }
            // ... and if we're shifting more than one entry, some entries from the right node go to the left node
            memcpy(appendHere - lagniappe,
                   rightContents - lagniappe,
                   lagniappe + (shifting - 1) * childStride);
            // Copy the new intermediate node into the apex position
            // (apex entry's right child pointer is unaffected: it still points to the right child node)
            memcpy(apex, rightContents + (shifting - 1) * childStride, elementSize);
            // And shrink the right node
            memmove(rightContents - lagniappe,
                    rightContents - lagniappe + (shifting * childStride),
                    lagniappe + newRightCount * childStride);
            SCRIBBLE(rightContents + (newRightCount * childStride), shifting * childStride);
        } else if (rightCount < newRightCount) {
            // NSLog(@"rotating right: %d -> %d,%d", (int)totalElements, (int)newLeftCount, (int)newRightCount);
            // The right node is smaller. Shift some elements over there.
            size_t shifting = newRightCount - rightCount;
            
            // Move the existing contents of the right node over
            void *insertHere;
            ptrdiff_t copyAmount = rightCount * childStride;
            size_t lagniappe;
            if (childrenAreLeaves) {
                lagniappe = 0;
                insertHere = right.leaf->contents;
            } else {
                lagniappe = sizeof(OFBTreeChildPointer);
                insertHere = &(right.node->childZero);
                copyAmount += lagniappe;
            }
            memmove(insertHere + shifting * childStride, insertHere, copyAmount);
            
            // Copy the apex value into the right node
            if (childrenAreLeaves)
                memcpy(right.leaf->contents + ( shifting - 1 ) * childStride, apex, elementSize);
            else
                memcpy(right.node->contents + ( shifting - 1 ) * childStride, apex, elementSize);

            void *copyFromHere = leftContents + newLeftCount * childStride;
            // Copy the new intermediate node into the apex position
            memcpy(apex, copyFromHere, elementSize);
            
            // Copy the remaining data from the left node to the space we made in the right node
            memcpy(insertHere, copyFromHere + childStride - lagniappe,
                   lagniappe + ( shifting - 1 ) * childStride);
            SCRIBBLE(copyFromHere, shifting * childStride);
            // And shrink the left node
        } else {
            OBASSERT_NOT_REACHED("null rotation?");
        }
        
        if (childrenAreLeaves) {
            left.leaf->elementCount = newLeftCount;
            right.leaf->elementCount = newRightCount;
        } else {
            left.node->elementCount = newLeftCount;
            right.node->elementCount = newRightCount;
        }
    }
}

static void _OFBTreeDidShrink(OFBTree *btree, OFBTreeCursor *cursor)
{
    OFBTreeChildPointer shrunkNode = cursor->nodeStack[cursor->nodeStackDepth];
    size_t shrunkElementCount, elementsPerNode;
    BOOL atLeaf = _isAtLeafNode(btree, cursor);
    
    if (atLeaf) {
        shrunkElementCount = shrunkNode.leaf->elementCount;
    } else {
        shrunkElementCount = shrunkNode.node->elementCount;
    }
        
    if (cursor->nodeStackDepth == 0) {
        // It was the root node that shrank.
        
        if (atLeaf) {
            // We can't do anything about a small root leaf node, so just leave it alone.
            // (As a special case the root node can contain zero items.)
            OBINVARIANT(shrunkNode.leaf == btree->root.leaf);
            
            return;
        } else {
            OBINVARIANT(btree->height > 1);
            OBINVARIANT(shrunkNode.node == btree->root.node);
            
            if (shrunkElementCount == 0) {
                // The root node is empty (except for a single child pointer).
                // Reduce the height of the tree by one node.
                btree->root = shrunkNode.node->childZero;
                btree->nodeDeallocator(btree, shrunkNode.node);
                btree->height --;
            } else {
                // The root node wasn't completely empty.
                // It has no neighbors, though, so we can't do anything even if it's small.
            }
            return;
        }
    } else {
        // A non-root node shrank. Did it shrink to the point we want to adjust the tree?

        if (atLeaf) {
            elementsPerNode = btree->elementsPerLeafNode;
        } else {
            elementsPerNode = btree->elementsPerInternalNode;
        }
        
        // We'll rebalance if a node is only 1/3 full.
        // TODO: Check whether there's a better heuristic for triggering rotations.
        // Perhaps Knuth has something to say on the matter.
        if (shrunkElementCount < 1 || shrunkElementCount*3 < elementsPerNode) {
            // Find our smallest neighbor, to maximize probabilty of unsplit vs. rotation
            // The next element up in the selection stack points to the element after us.
            void *parentSelection = cursor->selectionStack[cursor->nodeStackDepth-1];
            OBINVARIANT(_OFBTreeValueLesserChildNode(btree, parentSelection).node == shrunkNode.node);
            
            // Our parent node is always an internal node, of course.
            size_t parentStride = NODE_STRIDE(btree);
            OFBTreeNode *parentNode = cursor->nodeStack[cursor->nodeStackDepth-1].node;
            OBINVARIANT(parentNode->elementCount > 0);
            
            if (shrunkNode.node == parentNode->childZero.node) {
                // We're the leftmost child of our parent, so try to combine with our right sibling.
                // Point the cursor at the element between us and our right sibling & call OFBTreeRotate().
                cursor->nodeStackDepth --;
                _OFBTreeRotate(btree, cursor);
            } else if (parentSelection == (parentNode->contents + parentStride * parentNode->elementCount)) {
                // We're the rightmost child of our parent, so try to combine with our left sibling.
                // Point the cursor at the element between us and our left sibling & call OFBTreeRotate().
                cursor->nodeStackDepth --;
                cursor->selectionStack[cursor->nodeStackDepth] = parentSelection - parentStride;
                _OFBTreeRotate(btree, cursor);
            } else {
                // We have both a left and a right sibling, so look for the smaller one.
                OFBTreeChildPointer rightSibling = _OFBTreeValueGreaterChildNode(btree, parentSelection);
                OFBTreeChildPointer leftSibling = _OFBTreeValueLesserChildNode(btree, parentSelection);
                BOOL rightIsSmaller;
                if (atLeaf)
                    rightIsSmaller = ( rightSibling.leaf->elementCount < leftSibling.leaf->elementCount );
                else
                    rightIsSmaller = ( rightSibling.node->elementCount < leftSibling.node->elementCount );
                if (rightIsSmaller) {
                    // Combine with our right sibling.
                    cursor->nodeStackDepth --;
                    _OFBTreeRotate(btree, cursor);
                } else {
                    // Combine with our left sibling.
                    cursor->nodeStackDepth --;
                    cursor->selectionStack[cursor->nodeStackDepth] = parentSelection - parentStride;
                    _OFBTreeRotate(btree, cursor);                    
                }
            }
            
            return;
        }
    }
    
    // If we reach here, we decided not to mess with the shape of the tree.
}


/*"
Finds the element in the tree that compares the same to the given bytes and deletes it.  Returns YES if the element is found and deleted, NO otherwise.
"*/

BOOL OFBTreeDelete(OFBTree *btree, void *value)
{
    OFBTreeCursor cursor;
    
    if (!_OFBTreeFind(btree, &cursor, value))
        return NO;
        
    value = cursor.selectionStack[cursor.nodeStackDepth];
    ptrdiff_t leafStride = LEAF_STRIDE(btree);
    OFBTreeLeafNode *reduced;
    
    // if there is a lesser child
    if (!_isAtLeafNode(btree, &cursor)) {
        void *replacement;

        // walk down the right-most subtree of our left child to find the greatest value less than the original
        cursor.nodeStack[++cursor.nodeStackDepth] = _OFBTreeValueLesserChildNode(btree, value);
        replacement = _OFBTreeSelectLast(btree, &cursor);
        
        // Replace original with greatest lesser value
        memcpy(value, replacement, btree->elementSize);
        
        // leaving the cursor at the (now short by one) node we took the value from
        reduced = cursor.nodeStack[cursor.nodeStackDepth].leaf;
    } else {
        // Simple removal
        size_t fullLength;
        reduced = cursor.nodeStack[cursor.nodeStackDepth].leaf;
        fullLength = leafStride * reduced->elementCount;
        memmove(value, value + leafStride, (((void *)reduced->contents + fullLength) - (value + leafStride)));
    }
    
    // The cursor is always pointing to a leaf node at this point
    OBASSERT(_isAtLeafNode(btree, &cursor));
    reduced->elementCount --;
    SCRIBBLE((void *)reduced->contents + (leafStride * reduced->elementCount), leafStride);
    
    _OFBTreeDidShrink(btree, &cursor);
    return YES;
}

/*"
Returns a pointer to the element in the tree that compares equal to the given value.  Any data in the returned pointer that is used in the element comparison function should not be modified (since that would invalidate its position in the tree).
"*/
void *OFBTreeFind(const OFBTree *btree, const void *value)
{
    OFBTreeCursor cursor;
    if (_OFBTreeFind(btree, &cursor, value))
        return cursor.selectionStack[cursor.nodeStackDepth];
    else
        return NULL;
}

/*"
Calls the supplied callback once for each element in the tree, passing the element and the argument passed to OFBTreeEnumerator().  Currently, this only does a forward enumeration of the tree.
"*/
// TODO:  Later we could have a version of this that takes a min element, max element (either of which can be NULL) and a direction.  We'd then find the path to the two elements that don't break the range (i.e., the given min/max elements might not actually be in the tree) and start the enumeration from the starting path, continuing until we hit the ending element.

static void _OFBTreeEnumerateNode(const OFBTree *tree, OFBTreeChildPointer p, OFBTreeEnumeratorCallback callback, void *arg, unsigned height)
{
    NSUInteger elementIndex;
    
    if (height <= 1) {
        /* Leaf node, no child pointers */
        OFBTreeLeafNode *node = p.leaf;
        void *element;
        ptrdiff_t stride = LEAF_STRIDE(tree);
        for (elementIndex = 0, element = node->contents;
             elementIndex < node->elementCount;
             elementIndex ++, element += stride) {
            callback(tree, element, arg);
        }
    } else {
        /* Internal node; child pointers between elements, all guaranteed non-NULL */
        OFBTreeNode *node = p.node;
        ptrdiff_t stride = NODE_STRIDE(tree);
        size_t count = node->elementCount;
        void *value;
        
        OBINVARIANT(count > 0);
        
        for (elementIndex = 0; elementIndex <= count; elementIndex++) {
            value = ELEMENT_AT_INDEX(node, stride, elementIndex);
            _OFBTreeEnumerateNode(tree, _OFBTreeValueLesserChildNode(tree, value), callback, arg, height-1);
            if (elementIndex == count)
                break;
            callback(tree, value, arg);
        }
    }
}

void OFBTreeEnumerate(const OFBTree *tree, OFBTreeEnumeratorCallback callback, void *arg)
{
    _OFBTreeEnumerateNode(tree, tree->root, callback, arg, tree->height);
}

#ifdef NS_BLOCKS_AVAILABLE
static void _invokeBlock(const struct _OFBTree *tree, void *element, void *arg)
{
    ((OFBTreeEnumeratorBlock)arg)(tree, element);
}
void OFBTreeEnumerateBlock(const OFBTree *tree, OFBTreeEnumeratorBlock callback)
{
    _OFBTreeEnumerateNode(tree, tree->root, _invokeBlock, callback, tree->height);
}
#endif

static void *_OFBTreeCursorLesserValue(const OFBTree *btree, OFBTreeCursor *cursor);
static void *_OFBTreeCursorGreaterValue(const OFBTree *btree, OFBTreeCursor *cursor);

/*"
Finds the element in the tree that compares the same to the given bytes and returns a pointer to the closest element that compares less than the given value.  If there is no such element, NULL is returned.  Any data in the returned pointer that is used in the element comparison function should not be modified (since that would invalidate its position in the tree).
"*/
void *OFBTreePrevious(const OFBTree *btree, const void *value)
{
    OFBTreeCursor cursor;
    
    if (!_OFBTreeFind(btree, &cursor, value))
        return NULL;
    
    return _OFBTreeCursorLesserValue(btree, &cursor);
}

/* Advances the cursor back one entry, returning the new entry. At the beginning of the tree, returns NULL and leaves the cursor in an inconsistent state. */
static void *_OFBTreeCursorLesserValue(const OFBTree *btree, OFBTreeCursor *cursor)
{
    unsigned depth = cursor->nodeStackDepth;
    void *value = cursor->selectionStack[depth];
    
    if (!_isAtLeafNode(btree, cursor)) {
        // if there is a lesser child node, get the greatest value in that subtree
        cursor->nodeStack[ ++ cursor->nodeStackDepth ] = _OFBTreeValueLesserChildNode(btree, value);
        return _OFBTreeSelectLast(btree, cursor);
    } else {
        // if there's a previous value in this node, select it
        OFBTreeLeafNode *node = cursor->nodeStack[depth].leaf;
        if (value != node->contents) {
            value -= LEAF_STRIDE(btree);
            cursor->selectionStack[depth] = value;
            return value;
        }
        
        // else if there is a parent node and this is the first element in this node, walk up the tree
        while (depth > 0) {
            depth --;
            OFBTreeNode *parent = cursor->nodeStack[depth].node;
            value = cursor->selectionStack[depth];
            /* selectionStack[] holds the value *after* the child node we just ascended from */
            if (value != parent->contents) {
                /* there is a vaule before the child node we just came from. return it */
                value -= NODE_STRIDE(btree);
                cursor->selectionStack[depth] = value;
                cursor->nodeStackDepth = depth;
                return value;
            }
        }
        
        // otherwise we reached the root and there was never a predecessor so there is no next
        return NULL; 
    }
}

/*"
Finds the element in the tree that compares the same to the given bytes and returns a pointer to the closest element that compares greater than the given value.  If there is no such element, NULL is returned.  Any data in the returned pointer that is used in the element comparison function should not be modified (since that would invalidate its position in the tree).
"*/
void *OFBTreeNext(const OFBTree *btree, const void *value)
{
    OFBTreeCursor cursor;

    if (!_OFBTreeFind(btree, &cursor, value))
        return NULL;
    
    return _OFBTreeCursorGreaterValue(btree, &cursor);
}

/* Advances the cursor forward one entry, returning the new entry. At the end of the tree, returns NULL and leaves the cursor in an inconsistent state. */
static void *_OFBTreeCursorGreaterValue(const OFBTree *btree, OFBTreeCursor *cursor)
{
    unsigned depth = cursor->nodeStackDepth;
    void *value = cursor->selectionStack[depth];

    if (!_isAtLeafNode(btree, cursor)) {
        // if there is a greater child node, get the least value in that subtree
        cursor->selectionStack[depth] = value + NODE_STRIDE(btree);
        cursor->nodeStackDepth = ++depth;
        cursor->nodeStack[depth] = _OFBTreeValueGreaterChildNode(btree, value);
        return _OFBTreeSelectFirst(btree, cursor);
    } else {
        OFBTreeLeafNode *node = cursor->nodeStack[cursor->nodeStackDepth].leaf;
        ptrdiff_t stride = LEAF_STRIDE(btree);
        if (value < ELEMENT_AT_INDEX(node, stride, node->elementCount-1)) {
            // if there's no greater child node, but there is a next greater element, return that
            value += stride;
            cursor->selectionStack[depth] = value;
            return value;
        } else {
            // else, this is past the last element in this node, walk up the tree
            OFBTreeNode *parent;
            stride = NODE_STRIDE(btree);
            do {
                if (!depth) {
                    // we've reached the root, can't walk up any farther
                    // we were always past the end of the node so there's no successor
                    return NULL;
                }
                
                parent = cursor->nodeStack[--depth].node;
                value = cursor->selectionStack[depth];
            } while (value > ELEMENT_AT_INDEX(parent, stride, parent->elementCount-1));
            
            cursor->nodeStackDepth = depth;
            return value; 
        }
    }
}

/*"
 Finds the element in the tree at an offset from a given value.
 If the exact value does not exist in the tree, then the cursor is positioned at a notional element where the value would have been, and walked forwards or backwards according to offset.
 If afterMatch is YES and the value is found, the function behaves as if a slightly greater, nonexistent value had been supplied: the cursor is positined at a notional element after the found element, then walked forwads or backwards.
 If the exact value is found and afterMatch is NO, then the cursor is adjusted from that position.
 Giving an offset of 0 and afterMatch=NO is equivalent to calling OFBTreeFind().
 As a special case, giving a value of NULL will return 'offset' elements from the beginning or the end of the tree, according to the sign of offset.
 "*/
void *OFBTreeFindNear(const OFBTree *tree, const void *value, int offset, BOOL afterMatch)
{
    OFBTreeCursor cursor;
    
    if (value != NULL) {
        BOOL foundMatch = _OFBTreeFind(tree, &cursor, value);
        
        if (foundMatch && afterMatch) {
            // The cursor is positioned at the match, but we want to act as if it were positioned at a nonexistent element after the match.
            // We've effectively walked backwards once already, so adjust the offset.
            if (offset == 0)
                return NULL;
            if (offset < 0)
                offset ++;
        }
        if (!foundMatch) {
            // The cursor is positioned at the first element greater than the requested value, which doesn't exist; we've effectively walked forward once already.
            if (offset == 0)
                return NULL;
            if (offset > 0)
                offset --;
        }
    } else {
        // Value is null: special case for searching from the beginning/end of the tree.
        if (offset == 0) {
            // We could remove this assert if it's actually useful for someone to be able to call (..., NULL, 0, ...) and get NULL.
            OBASSERT_NOT_REACHED("OFBTreeFindNear(..., NULL, 0, ...) makes no sense.");
            return NULL;
        }
        
        if (offset < 0) {
            cursor.nodeStackDepth = 0;
            cursor.nodeStack[0] = tree->root;
            if (!_OFBTreeSelectLast(tree, &cursor))
                return NULL;
            offset ++;
        } else {
            cursor.nodeStackDepth = 0;
            cursor.nodeStack[0] = tree->root;
            if (!_OFBTreeSelectFirst(tree, &cursor))
                return NULL;
            offset --;
        }
    }
    
    //NSLog(@"FindNear:    offset=%d cursor=%@", offset, OFBTreeDescribeCursor(tree, &cursor));
    
    void *result;
    
    if (offset < 0) {
        do {
            result = _OFBTreeCursorLesserValue(tree, &cursor);
            offset ++;
            if (!result)
                return NULL;
            //NSLog(@"FindNear --> offset=%d cursor=%@", offset, OFBTreeDescribeCursor(tree, &cursor));
            OBINVARIANT(result == cursor.selectionStack[cursor.nodeStackDepth]);
        } while (offset < 0);
    } else if (offset > 0) {
        do {
            result = _OFBTreeCursorGreaterValue(tree, &cursor);
            offset --;
            if (!result)
                return NULL;
            //NSLog(@"FindNear ++> offset=%d cursor=%@", offset, OFBTreeDescribeCursor(tree, &cursor));
            OBINVARIANT(result == cursor.selectionStack[cursor.nodeStackDepth]);
        } while (offset > 0);
    } else {
        result = cursor.selectionStack[cursor.nodeStackDepth];
    }
    
    return result;
}

#ifdef DEBUG

static void OFBTreeDumpElement(FILE *fp, const OFBTree *btree, const void *value)
{
    fprintf(fp, "[");
    for(unsigned byteIndex = 0; byteIndex < btree->elementSize; byteIndex ++) {
        fprintf(fp, " %02X", ((uint8_t *)value)[byteIndex]);
    }
    fprintf(fp, " ]");
}

static void OFBTreeDumpNodes(FILE *fp, const OFBTree *btree, void (*dumpValue)(FILE *fp, const OFBTree *btree, const void *value), OFBTreeChildPointer anode, unsigned height)
{
    if (height == 1) {
        OFBTreeLeafNode *node = anode.leaf;
        fprintf(fp, "Node at %p: %" PRIuPTR " elements (LEAF)\n", node, node->elementCount);
        for(unsigned eltIndex = 0; eltIndex < node->elementCount; eltIndex ++) {
            fprintf(fp, "\t");
            dumpValue(fp, btree, ELEMENT_AT_INDEX(node, LEAF_STRIDE(btree), eltIndex));
            fprintf(fp, "\n");
        }
    } else {
        OFBTreeNode *node = anode.node;
        fprintf(fp, "Node at %p: %" PRIuPTR " elements\n\tNode at %p\n", node, node->elementCount, node->childZero.node);
        for(unsigned eltIndex = 0; eltIndex < node->elementCount; eltIndex ++) {
            fprintf(fp, "\t");
            void *value = ELEMENT_AT_INDEX(node, NODE_STRIDE(btree), eltIndex);
            dumpValue(fp, btree, value);
            fprintf(fp, "\n\tNode at %p\n", _OFBTreeValueGreaterChildNode(btree, value).node);
        }
        
        OFBTreeDumpNodes(fp, btree, dumpValue, node->childZero, height-1);
        for(unsigned eltIndex = 0; eltIndex < node->elementCount; eltIndex ++) {
            OFBTreeChildPointer childN = _OFBTreeValueGreaterChildNode(btree, ELEMENT_AT_INDEX(node, NODE_STRIDE(btree), eltIndex));
            OFBTreeDumpNodes(fp, btree, dumpValue, childN, height-1);
        }
    }
}

void OFBTreeDump(FILE *fp, const OFBTree *tree, void (*dumpValue)(FILE *fp, const OFBTree *btree, const void *value))
{
    fprintf(fp, "OFBTree at %p: elt size = %"PRIdPTR", elts per node = %"PRIdPTR" / %"PRIdPTR", root = %p, height = %u\n", tree, tree->elementSize, tree->elementsPerInternalNode, tree->elementsPerLeafNode, tree->root.node, tree->height);
    if (!dumpValue)
        dumpValue = OFBTreeDumpElement;
    OFBTreeDumpNodes(fp, tree, dumpValue, tree->root, tree->height);
    fprintf(fp, "==============================\n\n");
}

NSString *OFBTreeDescribeCursor(const OFBTree *tree, const OFBTreeCursor *cursor)
{
    NSMutableString *buf = [NSMutableString string];
    for(unsigned i = 0; i <= cursor->nodeStackDepth; i++) {
        if (i>0)
            [buf appendString:@" "];
        OFBTreeChildPointer anode = cursor->nodeStack[i];
        BOOL leafy = ( i+1 >= tree->height );
        void *node = leafy? (void *)anode.leaf : (void *)anode.node;
        void *seln = cursor->selectionStack[i];
        [buf appendFormat:@"%d:%p", i, node];
        const OFBTreeChildPointer shouldBe = ( i == 0 ? tree->root : _OFBTreeValueLesserChildNode(tree, cursor->selectionStack[i-1]) );
        if  (cursor->nodeStack[i].node != shouldBe.node) {
            [buf appendFormat:@"<should be %p>", shouldBe];
        }
        
        unsigned int j;
        ptrdiff_t stride = leafy? LEAF_STRIDE(tree) : NODE_STRIDE(tree);
        void *contents = leafy? anode.leaf->contents : anode.node->contents;
        size_t maxelts = leafy? tree->elementsPerLeafNode : tree->elementsPerInternalNode;
        for(j = 0; j <= maxelts; j++) {
            if (seln == contents + stride*j) {
                [buf appendFormat:@"[%d]", j];
                break;
            }
        }
        if (j > maxelts)
            [buf appendFormat:@"[??? %p]", seln];
    }
    
    return buf;
}

#endif



