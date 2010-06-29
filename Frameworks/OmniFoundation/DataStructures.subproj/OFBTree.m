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
"*/
typedef struct _OFBTreeNode {
    size_t elementCount;
    struct _OFBTreeNode *childZero;
    uint8_t contents[0];
} OFBTreeNode;

/*" OFBTreeCursor holds the path from the tree's root to a location in the tree. "*/
typedef struct _OFBTreeCursor {
    // These should probably be treated as private
    struct _OFBTreeNode *nodeStack[10];
    void *selectionStack[10];
    int nodeStackDepth;
} OFBTreeCursor;


#ifdef DEBUG
NSString *OFBTreeDescribeCursor(const OFBTree *tree, const OFBTreeCursor *cursor);
#endif

// Given a element count and size, how many bytes of the node have been used:
//    Size of the header
//  + Size of each element * number of elements
//  + Size of child pointer * (number of elements)
#define OFBT_SPACE_USED(elementSize,elementCount) \
( \
    sizeof(OFBTreeNode) + \
    (elementSize) * (elementCount) + \
    sizeof(OFBTreeNode *) * ((elementCount)) \
)

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
    tree->elementsPerNode = (nodeSize - sizeof(OFBTreeNode) - sizeof(OFBTreeNode *)) / (elementSize + sizeof(OFBTreeNode *));
    
    OBASSERT(tree->elementsPerNode > 2); // Our algorithms fail for really tiny "page" sizes
    
    tree->nodeAllocator = allocator;
    tree->nodeDeallocator = deallocator;
    tree->elementCompare = compare;
    
    // We always have at least one node
    tree->root = tree->nodeAllocator(tree);
    tree->root->elementCount = 0;
    tree->root->childZero = NULL;
}

static void _OFBTreeDeallocateChildren(OFBTree *tree, OFBTreeNode *node)
{
    void *childPointer = &( node->childZero );
    size_t elementStep = tree->elementSize + sizeof(OFBTreeNode *);
    for(size_t elementIndex = 0; elementIndex <= node->elementCount; elementIndex ++) {
        OFBTreeNode *childNode = *(OFBTreeNode **)childPointer;
        if (childNode) {
            _OFBTreeDeallocateChildren(tree, childNode);
            tree->nodeDeallocator(tree, childNode);
        }
        childPointer += elementStep;
    }
}

void OFBTreeDestroy(OFBTree *tree)
{
    _OFBTreeDeallocateChildren(tree, tree->root);
    tree->nodeDeallocator(tree, tree->root);
}

extern void OFBTreeDeleteAll(OFBTree *tree)
{
    _OFBTreeDeallocateChildren(tree, tree->root);
#if defined(__OBJC_GC__) && __OBJC_GC__
    // Scribble on the released elements so that the GC doesn't think any pointers are still live
    static const uint32_t badfood = 0xBAADF00D;
    memset_pattern4(tree->root->contents, &badfood, tree->root->elementCount * ( tree->elementSize + sizeof(OFBTreeNode *) ));
#endif
    tree->root->elementCount = 0;
    tree->root->childZero = NULL;
}

static inline void *_OFBTreeElementAtIndex(const OFBTree *btree, OFBTreeNode *node, NSUInteger elementIndex)
{
    return node->contents + elementIndex * (btree->elementSize + sizeof(OFBTreeNode *));
}

static inline OFBTreeNode *_OFBTreeValueLesserChildNode(const OFBTree *btree, void *value)
{
    return *(OFBTreeNode **)(value - sizeof(OFBTreeNode *));
}

static inline OFBTreeNode *_OFBTreeValueGreaterChildNode(const OFBTree *btree, void *value)
{
    return *(OFBTreeNode **)(value + btree->elementSize);
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
    OFBTreeNode *node;
    void *testValue;
    int testResult;
    
    node = cursor->nodeStack[cursor->nodeStackDepth];
    while(node->elementCount >= range) // range is the lowest power of 2 > count
        range <<= 1;

    while(range) {
        test = low + (range >>= 1);
        if (test >= node->elementCount)
            continue;
        testValue = _OFBTreeElementAtIndex(btree, node, test);
        testResult = btree->elementCompare(btree, value, testValue);
        if (!testResult) {
            cursor->selectionStack[cursor->nodeStackDepth] = testValue;
            return YES;
        } else if (testResult > 0) {
            low = test + 1;
        }
    }
    cursor->selectionStack[cursor->nodeStackDepth] = _OFBTreeElementAtIndex(btree, node, low);
    return NO;
}

/*" Internal find method.
 Initializes the cursor struct and searches for value.
 Returns YES if the value was found, or NO if not found (in which case the cursor points to the next value).
"*/
static BOOL _OFBTreeFind(const OFBTree *btree, OFBTreeCursor *cursor, const void *value)
{
    OFBTreeNode *childNode;
    
    cursor->nodeStack[0] = btree->root;
    cursor->nodeStackDepth = 0;
    while(1) {
        if (_OFBTreeScan(btree, cursor, value)) {
            return YES;
        } else if ((childNode = _OFBTreeValueLesserChildNode(btree, cursor->selectionStack[cursor->nodeStackDepth]))) {
            cursor->nodeStack[++cursor->nodeStackDepth] = childNode;
        } else {
            return NO;
        }
    }
}

/*" Internal find method. Sets the cursor to the first element in the tree, or returns NO if the tree is empty. "*/
static BOOL _OFBTreeFindFirst(const OFBTree *btree, OFBTreeCursor *cursor)
{
    int depth = 0;

    // The root is the only node that's allowed to have a zero element count
    if (!btree->root->elementCount)
        return NO;
    
    OFBTreeNode *node = btree->root;
    do {
        cursor->nodeStack[depth] = node;
        cursor->selectionStack[depth] = _OFBTreeElementAtIndex(btree, node, 0);
        depth ++;
        node = node->childZero;
    } while(node);
    cursor->nodeStackDepth = depth - 1;
    
    return YES;
}

/*" Internal find method. Sets the cursor to the last element in the tree, or returns NO if the tree is empty. "*/
static BOOL _OFBTreeFindLast(const OFBTree *btree, OFBTreeCursor *cursor)
{
    int depth = 0;
    
    // The root is the only node that's allowed to have a zero element count
    if (!btree->root->elementCount)
        return NO;
    
    OFBTreeNode *node = btree->root;
    do {
        cursor->nodeStack[depth] = node;
        cursor->selectionStack[depth] = _OFBTreeElementAtIndex(btree, node, node->elementCount);
        node = _OFBTreeValueLesserChildNode(btree, cursor->selectionStack[depth]);
        depth ++;
    } while(node);
    
    depth--;
    cursor->nodeStackDepth = depth;
    // Most of the selection stack points to the nonexistent element after the last child node pointer; the deepest entry points to an actual element.
    cursor->selectionStack[depth] -= ( btree->elementSize + sizeof(OFBTreeNode *) );
    OBASSERT(cursor->selectionStack[depth] >= _OFBTreeElementAtIndex(btree, cursor->nodeStack[depth], 0));
    
    return YES;
}

static void _OFBTreeSimpleAdd(OFBTree *btree, OFBTreeNode *node, void *insertionPoint, const void *value)
{
    const size_t entrySize = btree->elementSize + sizeof(OFBTreeNode *);
    void *end = (void *)node->contents + entrySize * node->elementCount;
    memmove(insertionPoint + entrySize, insertionPoint, end - insertionPoint);
    memcpy(insertionPoint, value, entrySize);
    node->elementCount++;
}

/*" Split the current node and promote the center.
"*/
static void _OFBTreeSplitAdd(OFBTree *btree, OFBTreeCursor *cursor, void *value)
{
    OFBTreeNode *node;
    void *insertionPoint;
    OFBTreeNode *right;
    NSUInteger insertionIndex;
    BOOL needsPromotion;
    const size_t entrySize = btree->elementSize + sizeof(OFBTreeNode *);

    node = cursor->nodeStack[cursor->nodeStackDepth];
    insertionPoint = cursor->selectionStack[cursor->nodeStackDepth];
    insertionIndex = (insertionPoint - (void *)node->contents) / entrySize;
    
    // build the new right hand side
    right = btree->nodeAllocator(btree);
    right->elementCount = node->elementCount / 2;
    node->elementCount -= right->elementCount;

    if (insertionIndex <= node->elementCount) {
        // the insertion point is in the center or left so just copy over the whole right side
        memcpy(right->contents, _OFBTreeElementAtIndex(btree, node, node->elementCount), right->elementCount * entrySize);
        
        if (insertionIndex == node->elementCount) {
            needsPromotion = NO;
        } else {
            // the insertion point isn't in the center so the value needs to be copied into the left side
            _OFBTreeSimpleAdd(btree, node, insertionPoint, value);
            needsPromotion = YES;
        }
    } else {
        // the insertion point is in the right side so copy before insertion, then new value, then after insertion
        memcpy(right->contents, _OFBTreeElementAtIndex(btree, node, node->elementCount), (insertionIndex - node->elementCount) * entrySize);
        insertionPoint = _OFBTreeElementAtIndex(btree, right, insertionIndex - node->elementCount);
        memcpy(insertionPoint, value, entrySize);
        memcpy(insertionPoint + entrySize, _OFBTreeElementAtIndex(btree, node, insertionIndex), (node->elementCount + right->elementCount - insertionIndex) * entrySize);
        right->elementCount++;
        needsPromotion = YES;
    }
    
    if (needsPromotion) {
        // the insertion point isn't in the center so the new promoted value needs to go into the buffer
        void *promotion = _OFBTreeElementAtIndex(btree, node, node->elementCount - 1);
        
        memcpy(value, promotion, entrySize);
        node->elementCount--;
    }
    
    // child zero on the right hand side is the greater side of the promoted value
    right->childZero = *(OFBTreeNode **)(value + btree->elementSize);
    // set the greater child on the promoted value to be the new right-hand side node
    *(OFBTreeNode **)(value + btree->elementSize) = right;
}

static BOOL _OFBTreeAdd(OFBTree *btree, OFBTreeCursor *cursor, void *value)
{
    OFBTreeNode *node;
    
    node = cursor->nodeStack[cursor->nodeStackDepth];

    if (node->elementCount < btree->elementsPerNode) {
        // Simple addition - add to the current node
        _OFBTreeSimpleAdd(btree, node, cursor->selectionStack[cursor->nodeStackDepth], value);
        return NO;
    } 
    
    // Otherwise split and return YES to tell the caller there is more work to do 
    _OFBTreeSplitAdd(btree, cursor, value);
    return YES;
}

/*"
Copies the bytes pointed to by value and puts them in the tree.
"*/
void OFBTreeInsert(OFBTree *btree, const void *value)
{
    void *promotionBuffer;
    const size_t entrySize = btree->elementSize + sizeof(OFBTreeNode *);
    OFBTreeCursor cursor;

    if (_OFBTreeFind(btree, &cursor, value))
        return; // the value is already in the tree
    
    promotionBuffer = alloca(entrySize);
    memcpy(promotionBuffer, value, btree->elementSize);
    *(OFBTreeNode **)(promotionBuffer + btree->elementSize) = NULL;
    
    while(_OFBTreeAdd(btree, &cursor, promotionBuffer)) {
        if (cursor.nodeStackDepth) {
            // if we're deep in the tree go up to the next higher level and try again
            cursor.nodeStackDepth--;
        } else {
            // otherwise we need a new root
            OFBTreeNode *newRoot;
            
            newRoot = btree->nodeAllocator(btree);
            newRoot->elementCount = 1;
            newRoot->childZero = btree->root;
            memcpy(newRoot->contents, promotionBuffer, entrySize);
            
            btree->root = newRoot;
            break;
        }
    }
}


/*"
Finds the element in the tree that compares the same to the given bytes and deletes it.  Returns YES if the element is found and deleted, NO otherwise.
"*/

BOOL OFBTreeDelete(OFBTree *btree, void *value)
{
    OFBTreeNode *node, *childNode;
    size_t fullLength;
    BOOL replacePointerWithGreaterChild;
    OFBTreeCursor cursor;
    
    if (!_OFBTreeFind(btree, &cursor, value))
        return NO;
        
    node = cursor.nodeStack[cursor.nodeStackDepth];
    value = cursor.selectionStack[cursor.nodeStackDepth];
    const size_t entrySize = btree->elementSize + sizeof(OFBTreeNode *);

    // if there is a lesser child
    if ((childNode = _OFBTreeValueLesserChildNode(btree, value))) {
        void *replacement;

        // walk down the right-most subtree to find the greatest value less than the original
        do {
            node = cursor.nodeStack[++cursor.nodeStackDepth] = childNode;
            replacement = _OFBTreeElementAtIndex(btree, node, node->elementCount - 1);
            cursor.selectionStack[cursor.nodeStackDepth] = replacement + btree->elementSize + sizeof(OFBTreeNode *);
        } while ((childNode = _OFBTreeValueGreaterChildNode(btree, replacement)));
        
        // Replace original with greater value
        memcpy(value, replacement, btree->elementSize);
        replacePointerWithGreaterChild = NO;
    } else {
        // Simple removal
        fullLength = entrySize * node->elementCount;
        memmove(value - sizeof(OFBTreeNode *), value + btree->elementSize, (((void *)node->contents + fullLength) - (value + btree->elementSize)));
        replacePointerWithGreaterChild = YES;
    }
    
    if (--node->elementCount == 0) {
        if (cursor.nodeStackDepth) {
            // if we removed the last element in this node and it isn't the root, deallocate it
            value = cursor.selectionStack[--cursor.nodeStackDepth];
            if (replacePointerWithGreaterChild)
                *(OFBTreeNode **)(value - sizeof(OFBTreeNode *)) = *(OFBTreeNode **)((void *)node->contents + btree->elementSize);
            else
                *(OFBTreeNode **)(value - sizeof(OFBTreeNode *)) = node->childZero;
            btree->nodeDeallocator(btree, node);
        } else if (node->childZero) {
            OBASSERT(node == btree->root);
            // the root is now empty, but there is content farther down, so move the root down
            btree->root = node->childZero;
            btree->nodeDeallocator(btree, node);
        } else {
            // the root is now empty, but it has no children; as a special case, we allow the root node to be empty.
        }
    } else {
#if defined(__OBJC_GC__) && __OBJC_GC__
        // Scribble on the removed object so that the GC doesn't think its pointers are still live
        static const uint32_t bad_data = 0xBAADDADA;
        // (We know that the _OFBTreeElementAtIndex() call here is within bounds since we just decremented node->elementCount, above)
        memset_pattern4(_OFBTreeElementAtIndex(btree, node, node->elementCount), &bad_data, btree->elementSize);
#endif
    }
    
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

static void _OFBTreeEnumerateNode(const OFBTree *tree, OFBTreeNode *node, OFBTreeEnumeratorCallback callback, void *arg)
{
    NSUInteger elementIndex;
    
    if (node->childZero)
        _OFBTreeEnumerateNode(tree, node->childZero, callback, arg);
    
    for (elementIndex = 0; elementIndex < node->elementCount; elementIndex++) {
        void *value;
        OFBTreeNode *child;
        
        value = _OFBTreeElementAtIndex(tree, node, elementIndex);
        callback(tree, value, arg);
        
        // This should be non-NULL for all but possibliy the last child, or if we are a leaf
        child = _OFBTreeValueGreaterChildNode(tree, value);
        if (child)
            _OFBTreeEnumerateNode(tree, child, callback, arg);
    }
}

void OFBTreeEnumerate(const OFBTree *tree, OFBTreeEnumeratorCallback callback, void *arg)
{
    _OFBTreeEnumerateNode(tree, tree->root, callback, arg);
}

#ifdef NS_BLOCKS_AVAILABLE
static void _invokeBlock(const struct _OFBTree *tree, void *element, void *arg)
{
    ((OFBTreeEnumeratorBlock)arg)(tree, element);
}
void OFBTreeEnumerateBlock(const OFBTree *tree, OFBTreeEnumeratorBlock callback)
{
    _OFBTreeEnumerateNode(tree, tree->root, _invokeBlock, callback);
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
    OFBTreeNode *childNode;
    
    int depth = cursor->nodeStackDepth;
    void *value = cursor->selectionStack[depth];
    
    if ((childNode = _OFBTreeValueLesserChildNode(btree, value))) {
        // if there is a lesser child node, get the greatest value in that subtree
        do {
            cursor->nodeStackDepth = ++depth;
            cursor->nodeStack[depth] = childNode;
            cursor->selectionStack[depth] = _OFBTreeElementAtIndex(btree, childNode, childNode->elementCount);
            value = _OFBTreeElementAtIndex(btree, childNode, childNode->elementCount - 1);
        } while((childNode = _OFBTreeValueGreaterChildNode(btree, value)));
        cursor->selectionStack[depth] = value;
        
        return value;
    } else {
        // else if there is a parent node and this is the first element in this node, walk up the tree
        while (depth && value == (void *)(cursor->nodeStack[depth]->contents)) {
            cursor->nodeStackDepth = --depth;
            value = cursor->selectionStack[depth];
        }
        
        // if we found a node that has a predecessor, it's the next highest value
        if (value != (void *)(cursor->nodeStack[depth]->contents)) {
            value -= ( btree->elementSize + sizeof(OFBTreeNode *) );
            cursor->selectionStack[depth] = value;
            return value;
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
    OFBTreeNode *childNode;
    
    int depth = cursor->nodeStackDepth;
    void *value = cursor->selectionStack[depth];
    
    if ((childNode = _OFBTreeValueGreaterChildNode(btree, value))) {
        // if there is a greater child node, get the least value in that subtree
        cursor->selectionStack[depth] = value + btree->elementSize + sizeof(OFBTreeNode *);
        do {
            ++depth;
            cursor->nodeStack[depth] = childNode;
            cursor->selectionStack[depth] = value = childNode->contents;
        } while((childNode = _OFBTreeValueLesserChildNode(btree, value)));
        cursor->nodeStackDepth = depth;

        return value;
    }
    
    OFBTreeNode *node = cursor->nodeStack[cursor->nodeStackDepth];
    
    if (value < _OFBTreeElementAtIndex(btree, node, node->elementCount - 1)) {
        // if there's no greater child node, but there is a next greater element, return that
        value += btree->elementSize + sizeof(OFBTreeNode *);
        cursor->selectionStack[depth] = value;
        return value;
    } else {
        // else, this is past the last element in this node, walk up the tree
        do {
            if (!depth) {
                // we've reached the root, can't walk up any farther
                // we were always past the end of the node so there's no successor
                return NULL;
            }
            
            node = cursor->nodeStack[--depth];
            value = cursor->selectionStack[depth];
        } while (value > _OFBTreeElementAtIndex(btree, node, node->elementCount - 1));

        cursor->nodeStackDepth = depth;
        return value; 
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
            if (!_OFBTreeFindLast(tree, &cursor))
                return NULL;
            offset ++;
        } else {
            if (!_OFBTreeFindFirst(tree, &cursor))
                return NULL;
            offset --;
        }
    }
    
    //NSLog(@"FindNear:    offset=%d cursor=%@", offset, OFBTreeDescribeCursor(tree, &cursor));
    
    void *result;
    
    if (offset < 0) {
        while (offset < 0) {
            result = _OFBTreeCursorLesserValue(tree, &cursor);
            offset ++;
            if (!result)
                return NULL;
            //NSLog(@"FindNear --> offset=%d cursor=%@", offset, OFBTreeDescribeCursor(tree, &cursor));
            OBINVARIANT(result == cursor.selectionStack[cursor.nodeStackDepth]);
        }
    } else if (offset > 0) {
        while (offset > 0) {
            result = _OFBTreeCursorGreaterValue(tree, &cursor);
            offset --;
            if (!result)
                return NULL;
            //NSLog(@"FindNear ++> offset=%d cursor=%@", offset, OFBTreeDescribeCursor(tree, &cursor));
            OBINVARIANT(result == cursor.selectionStack[cursor.nodeStackDepth]);
        }
    } else {
        result = cursor.selectionStack[cursor.nodeStackDepth];
    }
    
    return result;
}

#ifdef DEBUG

static void OFBTreeDumpNodes(FILE *fp, const OFBTree *btree, OFBTreeNode *node)
{
    fprintf(fp, "Node at %p: %" PRIuPTR " elements\n\tNode at %p\n", node, node->elementCount, node->childZero);
    NSUInteger eltIndex, byteIndex;
    for(eltIndex = 0; eltIndex < node->elementCount; eltIndex ++) {
        void *value = _OFBTreeElementAtIndex(btree, node, eltIndex);
        fprintf(fp, "\t[");
        for(byteIndex = 0; byteIndex < btree->elementSize; byteIndex ++) {
            fprintf(fp, " %02X", ((uint8_t *)value)[byteIndex]);
        }
        fprintf(fp, " ]\n\tNode at %p\n", _OFBTreeValueGreaterChildNode(btree, value));
    }
    
    if (node->childZero)
        OFBTreeDumpNodes(fp, btree, node->childZero);
    for(eltIndex = 0; eltIndex < node->elementCount; eltIndex ++) {
        OFBTreeNode *childN = _OFBTreeValueGreaterChildNode(btree, _OFBTreeElementAtIndex(btree, node, eltIndex));
        if (childN)
            OFBTreeDumpNodes(fp, btree, childN);
    }
}

void OFBTreeDump(FILE *fp, const OFBTree *tree)
{
    fprintf(fp, "OFBTree at %p: elt size = %"PRIdPTR", elts per node = %"PRIdPTR", root = %p\n", tree, tree->elementSize, tree->elementsPerNode, tree->root);
    OFBTreeDumpNodes(fp, tree, tree->root);
    fprintf(fp, "==============================\n\n");
}

NSString *OFBTreeDescribeCursor(const OFBTree *tree, const OFBTreeCursor *cursor)
{
    NSMutableString *buf = [NSMutableString string];
    int i, j;
    for(i = 0; i <= cursor->nodeStackDepth; i++) {
        if (i>0)
            [buf appendString:@" "];
        OFBTreeNode *node = cursor->nodeStack[i];
        void *seln = cursor->selectionStack[i];
        [buf appendFormat:@"%d:%p", i, node];
        const OFBTreeNode *shouldBe = ( i == 0 ? tree->root : _OFBTreeValueLesserChildNode(tree, cursor->selectionStack[i-1]) );
        if  (cursor->nodeStack[i] != shouldBe) {
            [buf appendFormat:@"<should be %p>", shouldBe];
        }
        
        for(j = 0; (unsigned)j <= tree->elementsPerNode; j++) {
            if (seln == _OFBTreeElementAtIndex(tree, node, j)) {
                [buf appendFormat:@"[%d]", j];
                break;
            }
        }
        if ((unsigned)j > tree->elementsPerNode)
            [buf appendFormat:@"[??? %p]", seln];
    }
    
    return buf;
}

#endif



