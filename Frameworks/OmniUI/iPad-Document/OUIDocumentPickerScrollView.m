// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerScrollView.h>

#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDirectTapGestureRecognizer.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerGroupItemView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUI/UINavigationController-OUIExtensions.h>

#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentRenameSession.h"
#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

NSString * const OUIDocumentPickerScrollViewItemsBinding = @"items";

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_LAYOUT(format, ...) NSLog(@"DOC LAYOUT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_LAYOUT(format, ...)
#endif

typedef struct LayoutInfo {
    CGFloat topControlsHeight;
    CGRect contentRect;
    CGSize itemSize;
    NSUInteger itemsPerRow;
    CGFloat verticalPadding;
    CGFloat horizontalPadding;
} LayoutInfo;

static LayoutInfo _updateLayout(OUIDocumentPickerScrollView *self);

// Items are laid out in a fixed size grid.
static CGRect _frameForPositionAtIndex(NSUInteger itemIndex, LayoutInfo layoutInfo)
{
    OBPRECONDITION(layoutInfo.itemSize.width > 0);
    OBPRECONDITION(layoutInfo.itemSize.height > 0);
    OBPRECONDITION(layoutInfo.itemsPerRow > 0);
    
    NSUInteger row = itemIndex / layoutInfo.itemsPerRow;
    NSUInteger column = itemIndex % layoutInfo.itemsPerRow;
  
    // If the item views plus their padding don't completely fill our layoutWidth, distribute the remaining space as margins on either sides of the scrollview.

    CGFloat sideMargin = (layoutInfo.contentRect.size.width - (layoutInfo.horizontalPadding + layoutInfo.itemsPerRow * (layoutInfo.itemSize.width + layoutInfo.horizontalPadding))) / 2;
    
    CGRect frame = (CGRect){
        .origin.x = layoutInfo.horizontalPadding + column * (layoutInfo.itemSize.width + layoutInfo.horizontalPadding) + sideMargin,
        .origin.y = layoutInfo.topControlsHeight + layoutInfo.verticalPadding + row * (layoutInfo.itemSize.height + layoutInfo.verticalPadding),
        .size = layoutInfo.itemSize};
    
    // CGRectIntegral can make the rect bigger when the size is integral but the position is fractional. We want the size to remain the same.
    CGRect integralFrame;
    integralFrame.origin.x = floor(frame.origin.x);
    integralFrame.origin.y = floor(frame.origin.y);
    integralFrame.size = frame.size;
    
    return CGRectIntegral(integralFrame);
}

static CGPoint _clampContentOffset(OUIDocumentPickerScrollView *self, CGPoint contentOffset)
{
    UIEdgeInsets contentInset = self.contentInset;
    OFExtent contentOffsetYExtent = OFExtentMake(-self.contentInset.top, MAX(0, self.contentSize.height - self.bounds.size.height + contentInset.top + self.contentInset.bottom));
    CGPoint clampedContentOffset = CGPointMake(contentOffset.x, MAX([self contentOffsetYToHideTopControls], OFExtentClampValue(contentOffsetYExtent, contentOffset.y)));
    return clampedContentOffset;
}

@interface OUIDocumentPickerScrollView (/*Private*/)

@property (nonatomic, copy) NSArray *currentSortDescriptors;
@property(nonatomic,readwrite) BOOL isUsingSmallItems;

- (CGSize)_gridSize;
- (CGFloat)_horizontalPadding;
- (CGFloat)_verticalPadding;
@end

@implementation OUIDocumentPickerScrollView
{    
    NSMutableSet *_items;
    NSArray *_sortedItems;
    id _draggingDestinationItem;
    
    NSMutableSet *_itemsBeingAdded;
    NSMutableSet *_itemsBeingRemoved;
    NSMutableSet *_itemsBeingObserved;
    NSMutableSet *_itemsIgnoredForLayout;
    NSDictionary *_fileItemToPreview; // For visible or nearly visible files
    
    struct {
        unsigned int isAnimatingRotationChange:1;
        unsigned int isEditing:1;
        unsigned int isAddingItems:1;
    } _flags;
    
    OUIDocumentPickerItemSort _itemSort;

    NSArray *_itemViewsForPreviousOrientation;
    NSArray *_fileItemViews;
    NSArray *_groupItemViews;
        
    NSTimeInterval _rotationDuration;
    
    NSMutableArray *_scrollFinishedCompletionHandlers;
}

static id _commonInit(OUIDocumentPickerScrollView *self)
{
    self->_items = [[NSMutableSet alloc] init];
    self->_itemsBeingAdded = [[NSMutableSet alloc] init];
    self->_itemsBeingRemoved = [[NSMutableSet alloc] init];
    self->_itemsBeingObserved = [[NSMutableSet alloc] init];
    self->_itemsIgnoredForLayout = [[NSMutableSet alloc] init];
    
    self.showsVerticalScrollIndicator = YES;
    self.showsHorizontalScrollIndicator = NO;
    self.alwaysBounceVertical = YES;
    self.isUsingSmallItems = YES;
  
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{    
    [_fileItemToPreview enumerateKeysAndObjectsUsingBlock:^(ODSStore *fileItem, OUIDocumentPreview *preview, BOOL *stop) {
        [preview decrementDisplayCount];
    }];
    
    for (ODSItem *item in _items) {
        [self _endObservingSortKeysForItem:item];
    }
}


- (void)setContentInset:(UIEdgeInsets)contentInset{
    BOOL topControlsWereHidden = self.topControls.alpha < 0.7;
    [super setContentInset:contentInset];
    if (topControlsWereHidden) {
        if (self.contentOffset.y < self.contentOffsetYToHideTopControls) {
            self.contentOffset = CGPointMake(self.contentOffset.x, self.contentOffsetYToHideTopControls);
        }
    }
}

- (id <OUIDocumentPickerScrollViewDelegate>)delegate;
{
    return (id <OUIDocumentPickerScrollViewDelegate>)[super delegate];
}

- (void)setDelegate:(id <OUIDocumentPickerScrollViewDelegate>)delegate;
{
    OBPRECONDITION(!delegate || [delegate conformsToProtocol:@protocol(OUIDocumentPickerScrollViewDelegate)]);

    [super setDelegate:delegate];
    
    // If the delegate changes, the sort descriptors can change also.
    [self _updateSortDescriptors];
}

static NSUInteger _itemViewsForGridSize(CGSize gridSize)
{
    OBPRECONDITION(gridSize.width == rint(gridSize.width));
    
    NSUInteger width = ceil(gridSize.width);
    NSUInteger height = ceil(gridSize.height + 1.0); // partial row scrolled off the top, partial row off the bottom
    
    return width * height;
}

static NSArray *_newItemViews(OUIDocumentPickerScrollView *self, Class itemViewClass, BOOL isReadOnly)
{
    OBASSERT(OBClassIsSubclassOfClass(itemViewClass, [OUIDocumentPickerItemView class]));
    OBASSERT(itemViewClass != [OUIDocumentPickerItemView class]);
    
    NSMutableArray *itemViews = [[NSMutableArray alloc] init];

    NSUInteger neededItemViewCount = _itemViewsForGridSize([self _gridSize]);
    while (neededItemViewCount--) {

        OUIDocumentPickerItemView *itemView = [[itemViewClass alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        itemView.isReadOnly = isReadOnly;
        
        [itemViews addObject:itemView];

        [itemView addTarget:self action:@selector(_itemViewTapped:) forControlEvents:UIControlEventTouchUpInside];
        if (![self.delegate respondsToSelector:@selector(documentPickerScrollViewShouldMultiselect:)] || [self.delegate documentPickerScrollViewShouldMultiselect:self])
        {
            [itemView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_itemViewLongpressed:)]];
        }
        
        itemView.hidden = YES;
        [self addSubview:itemView];
    }
    
    NSArray *result = [itemViews copy];
    return result;
}

- (BOOL)isShowingTitleLabel;
{
    BOOL currentlyInCompactWidth = (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);
    return currentlyInCompactWidth;
}

- (CGFloat)contentOffsetYToHideTopControls;
{
    // note that contentInset.top should match the height of the navigation bar, so a contentOffset.y of -contentInset.top should align the 0 y point with the bottom of the navigation bar.  more generally, visualOffset.y - contentInset.top should give the correct contentOffset.y
    CGFloat offset;
    if ([self isShowingTitleLabel]) {
        // the title view is overlaid on the top controls, so hide the top controls when the title view is at the top of the visible window
        offset = _titleViewForCompactWidth.frame.origin.y - [self _verticalPadding] - self.contentInset.top;
    } else {
        // the top controls should be invisible when they are fully off screen
        offset = CGRectGetMaxY(_topControls.frame) - self.contentInset.top;
    }
    return ceilf(offset);
}

- (CGFloat)contentOffsetYForTopControlsFullAlpha;
{
    CGFloat offset;
    if ([self isShowingTitleLabel]) {
        // the title view is overlaid on the top controls, so the top controls are fully hidden even when they are partially on screen
        // so don't show them fully until they are fully on screen
        offset = _topControls.frame.origin.y - self.contentInset.top;
    } else {
        // the top controls should be fully visible when they reach halfway on screen
        offset = CGRectGetMidY(_topControls.frame) - self.contentInset.top;
    }
    return ceilf(offset);
}

- (CGFloat)contentOffsetYToShowTopControls;
{
    CGFloat offset = _topControls.frame.origin.y - self.contentInset.top;
    return ceilf(offset);
}

- (void)retileItems;
{
    if (_flags.isAnimatingRotationChange) {
        OBASSERT(self.window);
        // We are on screen and rotating, so -willRotate should have been called. Still, we'll try to handle this reasonably below.
        OBASSERT(_fileItemViews == nil);
        OBASSERT(_groupItemViews == nil);
    } 
    
    // Figure out whether we should do the animation outside of the OUIWithoutAnimating block (else +areAnimationsEnabled will be trivially NO).
    BOOL shouldCrossFade = _flags.isAnimatingRotationChange && [UIView areAnimationsEnabled];

    BOOL isReadOnly = [self.delegate isReadyOnlyForDocumentPickerScrollView:self];
    // Make the new views (which will start out hidden).
    OUIWithoutAnimating(^{
        Class fileItemViewClass = [OUIDocumentPickerFileItemView class];
        [_fileItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        _fileItemViews = _newItemViews(self, fileItemViewClass, isReadOnly);
        
        [_groupItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        _groupItemViews = _newItemViews(self, [OUIDocumentPickerGroupItemView class], isReadOnly);
        
        if (shouldCrossFade) {
            for (OUIDocumentPickerItemView *itemView in _fileItemViews) {
                itemView.alpha = 0;
            }
            for (OUIDocumentPickerItemView *itemView in _groupItemViews) {
                itemView.alpha = 0;
            }
        }
    });
    
    // Now fade in the views (at least the ones that have their hidden flag cleared on the next layout).
    if (shouldCrossFade) {
        [UIView beginAnimations:nil context:NULL];
        {
            if (_rotationDuration > 0)
                [UIView setAnimationDuration:_rotationDuration];
            for (OUIDocumentPickerItemView *itemView in _fileItemViews) {
                itemView.alpha = 1;
            }
            for (OUIDocumentPickerItemView *itemView in _groupItemViews) {
                itemView.alpha = 1;
            }
        }
        [UIView commitAnimations];
    }
    
    _shouldHideTopControlsOnNextLayout = YES;
    
    [self setNeedsLayout];
}

@synthesize items = _items;

- (void)startAddingItems:(NSSet *)toAdd;
{
    OBPRECONDITION([toAdd intersectsSet:_items] == NO);
    OBPRECONDITION([toAdd intersectsSet:_itemsBeingAdded] == NO);

    [_items unionSet:toAdd];
    [_itemsBeingAdded unionSet:toAdd];
}

- (void)finishAddingItems:(NSSet *)toAdd;
{
    OBPRECONDITION([toAdd isSubsetOfSet:_items]);
    OBPRECONDITION([toAdd isSubsetOfSet:_itemsBeingAdded]);

    [_itemsBeingAdded minusSet:toAdd];
    
    for (ODSItem *item in toAdd) {
        [self _beginObservingSortKeysForItem:item];
        
        OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
        OBASSERT(!itemView || itemView.shrunken);
        itemView.shrunken = NO;
        itemView.isSmallSize = self.isUsingSmallItems;

    }
    
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

@synthesize itemsBeingAdded = _itemsBeingAdded;

- (void)startRemovingItems:(NSSet *)toRemove;
{
    OBPRECONDITION([toRemove isSubsetOfSet:_items]);
    OBPRECONDITION([toRemove intersectsSet:_itemsBeingRemoved] == NO);

    [_itemsBeingRemoved unionSet:toRemove];

    for (ODSItem *item in toRemove) {
        [self _endObservingSortKeysForItem:item];
        
        OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
        itemView.shrunken = YES;
    }
}

- (void)finishRemovingItems:(NSSet *)toRemove;
{
    OBPRECONDITION([toRemove isSubsetOfSet:_items]);
    OBPRECONDITION([toRemove isSubsetOfSet:_itemsBeingRemoved]);

    for (ODSItem *item in toRemove) {
        OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
        OBASSERT(!itemView || itemView.shrunken);
        itemView.shrunken = NO;
    }

    [_itemsBeingRemoved minusSet:toRemove];
    [_items minusSet:toRemove];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

@synthesize itemsBeingRemoved = _itemsBeingRemoved;

static void * ItemSortKeyContext = &ItemSortKeyContext;
- (void)_beginObservingSortKeysForItem:(ODSItem *)item;
{
    OBPRECONDITION([NSThread isMainThread]);
    if (![_itemsBeingObserved containsObject:item]) {
        for (NSSortDescriptor *sortDescriptor in self.currentSortDescriptors) {
            // Since not all sort descriptors are key-based (like block sort descriptors) we ignore the sort descriptor if it doesn't have a key. This isn't perfect, but it'll work for now.
            NSString *key = sortDescriptor.key;
            if (key) {
                [item addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew context:ItemSortKeyContext];
            }
        }
        [_itemsBeingObserved addObject:item];
    } else {
        OBASSERT_NOT_REACHED(@"Almost tried to add observer for item %@ when we weren't already observing it!", item);
    }
}

- (void)_endObservingSortKeysForItem:(ODSItem *)item;
{
    OBPRECONDITION([NSThread isMainThread]);
    if ([_itemsBeingObserved containsObject:item]) {
        for (NSSortDescriptor *sortDescriptor in self.currentSortDescriptors) {
            NSString *key = sortDescriptor.key;
            if (key) {
                [item removeObserver:self forKeyPath:key context:ItemSortKeyContext];
            }
        }
        [_itemsBeingObserved removeObject:item];
    } else {
        OBASSERT_NOT_REACHED(@"Almost tried to remove observer from item %@ when we weren't even observing it!", item);
    }
}

- (void)_updateSortDescriptors;
{
    NSArray *newSortDescriptors = nil;
    if ([[self delegate] respondsToSelector:@selector(sortDescriptorsForDocumentPickerScrollView:)]) {
        newSortDescriptors = [[self delegate] sortDescriptorsForDocumentPickerScrollView:self];
    }
    else {
        newSortDescriptors = [OUIDocumentPickerViewController sortDescriptors];
    }

    // Only refresh if the sort descriptors have actually changed.
    if (OFNOTEQUAL(newSortDescriptors, self.currentSortDescriptors)) {
        for (ODSItem *item in _items) {
            [self _endObservingSortKeysForItem:item];
        }
        
        self.currentSortDescriptors = newSortDescriptors;
        
        for (ODSItem *item in _items) {
            [self _beginObservingSortKeysForItem:item];
        }
    }
}

- (void)_sortItems:(BOOL)updateDescriptors;
{
    OBASSERT(_items);
    if (!_items) {
        return;
    }

    if (updateDescriptors) {
        [self _updateSortDescriptors];
    }
    
    NSArray *newSort = [[_items allObjects] sortedArrayUsingDescriptors:self.currentSortDescriptors];
    if (OFNOTEQUAL(newSort, _sortedItems)) {
        _sortedItems = [newSort copy];
        [self setNeedsLayout];
    }
}

- (void)sortItems;
{
    // This API was designed to ask it's delegate for the sort descriptors when -sortItems is called. We may want to move away from that design, but for now we need to leave it because external callers of this API might expect this.
    [self _sortItems:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    _flags.isEditing = editing;
    
    for (OUIDocumentPickerItemView *itemView in _fileItemViews)
        [itemView setEditing:editing animated:animated];
    for (OUIDocumentPickerItemView *itemView in _groupItemViews)
        [itemView setEditing:editing animated:animated];
}

- (void)setItemSort:(OUIDocumentPickerItemSort)_sort;
{
    _itemSort = _sort;
    [self _sortItems:YES];

    if (self.window != nil) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
            [self layoutIfNeeded];
        } completion:^(BOOL finished){
        }];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == ItemSortKeyContext) {
        OBASSERT([_items containsObject:object]);
        OBASSERT([_currentSortDescriptors first:^BOOL(NSSortDescriptor *desc){ return [desc.key isEqual:keyPath]; }]);
        
        [self _sortItems:NO];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@synthesize sortedItems = _sortedItems;
@synthesize itemSort = _itemSort;

@synthesize draggingDestinationItem = _draggingDestinationItem;
- (void)setDraggingDestinationItem:(id)draggingDestinationItem;
{
    if (_draggingDestinationItem == draggingDestinationItem)
        return;
    _draggingDestinationItem = draggingDestinationItem;
    
    [self setNeedsLayout];
}

static CGPoint _contentOffsetForCenteringItem(OUIDocumentPickerScrollView *self, CGRect itemFrame)
{
    UIEdgeInsets contentInset = self.contentInset;
    CGRect viewportRect = UIEdgeInsetsInsetRect(self.bounds, contentInset);
    return CGPointMake(-contentInset.left, floor(CGRectGetMinY(itemFrame) + CGRectGetHeight(itemFrame) - (CGRectGetHeight(viewportRect) / 2) - contentInset.top));
}

- (void)scrollItemToVisible:(ODSItem *)item animated:(BOOL)animated;
{
    [self scrollItemsToVisible:[NSArray arrayWithObjects:item, nil] animated:animated];
}

- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated;
{
    [self scrollItemsToVisible:items animated:animated completion:nil];
}

- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated completion:(void (^)(void))completion;
{
    [self layoutIfNeeded];
    
    CGRect itemsFrame = CGRectNull;
    for (ODSItem *item in items) {
        CGRect itemFrame = [self frameForItem:item];
        if (CGRectIsNull(itemFrame))
            itemsFrame = itemFrame;
        else
            itemsFrame = CGRectUnion(itemsFrame, itemFrame);
    }
    
    if ([self.delegate documentPickerScrollView:self rectIsFullyVisible:itemsFrame]) { // won't consider under the nav bar as visible
        // If all the rects are fully visible, nothing really to do.
        // If we have some pending handlers, calling this one first would mean we're calling handlers out of order with when they were specified. Likely this is a bug (but we have to call it anway)
        OBASSERT(_scrollFinishedCompletionHandlers == nil);
        if (completion)
            completion();
        return;
    }
    
    CGPoint contentOffset = self.contentOffset;
    if (completion) {
        if (!_scrollFinishedCompletionHandlers)
            _scrollFinishedCompletionHandlers = [NSMutableArray new];
        [_scrollFinishedCompletionHandlers addObject:[completion copy]];
    }
    
    CGPoint clampedContentOffset = _clampContentOffset(self, _contentOffsetForCenteringItem(self, itemsFrame));
    
    if (!CGPointEqualToPoint(contentOffset, clampedContentOffset)) {
        [self setContentOffset:clampedContentOffset animated:animated];
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }
}

- (void)performScrollFinishedHandlers;
{
    NSArray *handlers = _scrollFinishedCompletionHandlers;
    _scrollFinishedCompletionHandlers = nil;
    
    for (void (^handler)(void) in handlers)
        handler();
}

- (CGRect)frameForItem:(ODSItem *)item;
{
    LayoutInfo layoutInfo = _updateLayout(self);
    CGSize itemSize = layoutInfo.itemSize;

    if (itemSize.width <= 0 || itemSize.height <= 0) {
        // We aren't sized right yet
        OBASSERT_NOT_REACHED("Asking for the frame of an item before we are laid out.");
        return CGRectZero;
    }

    NSUInteger positionIndex;
    if ([_itemsIgnoredForLayout count] > 0) {
        positionIndex = NSNotFound;
        
        NSUInteger itemIndex = 0;
        for (ODSItem *sortedItem in _sortedItems) {
            if ([_itemsIgnoredForLayout member:sortedItem])
                continue;
            if (sortedItem == item) {
                positionIndex = itemIndex;
                break;
            }
            itemIndex++;
        }
    } else {
        positionIndex = [_sortedItems indexOfObjectIdenticalTo:item];
    }
    
    if (positionIndex == NSNotFound) {
        OBASSERT([_items member:item] == nil); // If we didn't find the positionIndex it should mean that the item isn't in _items or _sortedItems. If the item is in _items but not _sortedItems, its probably becase we havn't yet called -sortItems.
        OBASSERT_NOT_REACHED("Asking for the frame of an item that is unknown/ignored");
        return CGRectZero;
    }

    return _frameForPositionAtIndex(positionIndex, layoutInfo);
}

- (OUIDocumentPickerItemView *)itemViewForItem:(ODSItem *)item;
{
    for (OUIDocumentPickerFileItemView *itemView in _fileItemViews) {
        if (itemView.item == item)
            return itemView;
    }

    for (OUIDocumentPickerGroupItemView *itemView in _groupItemViews) {
        if (itemView.item == item)
            return itemView;
    }
    
    return nil;
}

- (OUIDocumentPickerFileItemView *)fileItemViewForFileItem:(ODSFileItem *)fileItem;
{
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if (fileItemView.item == fileItem)
            return fileItemView;
    }
    
    return nil;
}

// We don't use -[UIGestureRecognizer(OUIExtensions) hitView] or our own -hitTest: since while we are in the middle of dragging, extra item views will be added to us by the drag session.
static OUIDocumentPickerItemView *_itemViewHitByRecognizer(NSArray *itemViews, UIGestureRecognizer *recognizer)
{
    for (OUIDocumentPickerItemView *itemView in itemViews) {
        // The -hitTest:withEvent: below doesn't consider ancestor isHidden flags.
        if (itemView.hidden)
            continue;
        UIView *hitView = [itemView hitTest:[recognizer locationInView:itemView] withEvent:nil];
        if (hitView)
            return itemView;
    }
    return nil;
}

- (OUIDocumentPickerItemView *)itemViewHitByRecognizer:(UIGestureRecognizer *)recognizer;
{
    OUIDocumentPickerItemView *itemView = _itemViewHitByRecognizer(_fileItemViews, recognizer);
    if (itemView)
        return itemView;
    return _itemViewHitByRecognizer(_groupItemViews, recognizer);
}

// Used to pick file items that are visible for automatic download (if they are small and we are on wi-fi) or preview generation.
- (ODSFileItem *)preferredVisibleItemFromSet:(NSSet *)fileItemsNeedingPreviewUpdate;
{
    // Prefer to update items that are visible, and then among those, do items starting at the top-left.
    ODSFileItem *bestFileItem = nil;
    CGFloat bestVisiblePercentage = 0;
    CGPoint bestOrigin = CGPointZero;

    CGPoint contentOffset = self.contentOffset;
    CGRect bounds = self.bounds;
    
    CGRect contentRect;
    contentRect.origin = contentOffset;
    contentRect.size = bounds.size;

    OFExtent contentYExtent = OFExtentFromRectYRange(contentRect);
    if (contentYExtent.length <= 1)
        return nil; // Avoid divide by zero below.
    
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        ODSFileItem *fileItem = (ODSFileItem *)fileItemView.item;
        if ([fileItemsNeedingPreviewUpdate member:fileItem] == nil)
            continue;

        CGRect itemFrame = fileItemView.frame;
        CGPoint itemOrigin = itemFrame.origin;
        OFExtent itemYExtent = OFExtentFromRectYRange(itemFrame);

        OFExtent itemVisibleYExtent = OFExtentIntersection(itemYExtent, contentYExtent);
        CGFloat itemVisiblePercentage = itemVisibleYExtent.length / contentYExtent.length;
        
        if (itemVisiblePercentage > bestVisiblePercentage ||
            itemOrigin.y < bestOrigin.y ||
            (itemOrigin.y == bestOrigin.y && itemOrigin.x < bestOrigin.x)) {
            bestFileItem = fileItem;
            bestVisiblePercentage = itemVisiblePercentage;
            bestOrigin = itemOrigin;
        }
    }
    
    return bestFileItem;
}

- (void)previewsUpdatedForFileItem:(ODSFileItem *)fileItem;
{
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if (fileItemView.item == fileItem) {
            [fileItemView previewsUpdated];
            return;
        }
    }
    
    for (OUIDocumentPickerGroupItemView *groupItemView in _groupItemViews) {
        ODSFolderItem *groupItem = (ODSFolderItem *)groupItemView.item;
        if ([groupItem.childItems member:fileItem]) {
            [groupItemView previewsUpdated];
            return;
        }
    }
}

- (void)previewedItemsChangedForGroups;
{
    [_groupItemViews makeObjectsPerformSelector:@selector(previewedItemsChanged)];
}

- (void)startIgnoringItemForLayout:(ODSItem *)item;
{
    OBASSERT(!([_itemsIgnoredForLayout containsObject:item]));
    [_itemsIgnoredForLayout addObject:item];
}

- (void)stopIgnoringItemForLayout:(ODSItem *)item;
{
    OBASSERT([_itemsIgnoredForLayout containsObject:item]);
    [_itemsIgnoredForLayout removeObject:item];
}

- (void)setIsUsingSmallItems:(BOOL)useSmallItems;
{
    _isUsingSmallItems = useSmallItems;

    //also push this value down into our items so they can draw their labels properly.

    for (OUIDocumentPickerItemView *itemView in _fileItemViews) {
        if ([itemView respondsToSelector:@selector(setIsSmallSize:)]) {
            itemView.isSmallSize = useSmallItems;
        }
    }

    for (OUIDocumentPickerItemView *itemView in _groupItemViews) {
        if ([itemView respondsToSelector:@selector(setIsSmallSize:)]) {
            itemView.isSmallSize = useSmallItems;
        }
    }
}

#pragma mark - UIScrollView
- (void)setContentOffset:(CGPoint)contentOffset
{
    [super setContentOffset:contentOffset];
    // when the content offset changes, post a layout change. This will cause another -layoutSubviews to get called, setting up the previous/next rows for VoiceOver to scroll to for selection.
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

#pragma mark - UIView

static LayoutInfo _updateLayout(OUIDocumentPickerScrollView *self)
{
    CGSize gridSize = [self _gridSize];
    OBASSERT(gridSize.width >= 1);
    OBASSERT(gridSize.width == trunc(gridSize.width));
    OBASSERT(gridSize.height >= 1);
    
    if (_itemViewsForGridSize(gridSize) > self->_fileItemViews.count) {
        [self retileItems];
    }
        
    NSUInteger itemsPerRow = gridSize.width;
    CGSize layoutSize = self.bounds.size;
    CGSize itemSize = CGSizeMake(kOUIDocumentPickerItemNormalSize, kOUIDocumentPickerItemNormalSize);
;
    // For devices where screen sizes are too small for our preferred items, here's a smaller size
    if (layoutSize.width / gridSize.width < (itemSize.width + kOUIDocumentPickerItemSmallHorizontalPadding)) {
        itemSize = CGSizeMake(kOUIDocumentPickerItemSmallSize, kOUIDocumentPickerItemSmallSize);
        self.isUsingSmallItems = YES;
    } else {
        self.isUsingSmallItems = NO;
    }
    
    if (itemSize.width <= 0 || itemSize.height <= 0) {
        // We aren't sized right yet
        DEBUG_LAYOUT(@"  Bailing since we have zero size");
        LayoutInfo layoutInfo;
        memset(&layoutInfo, 0, sizeof(layoutInfo));
        return layoutInfo;
    }
    
    CGFloat topControlsHeight = CGRectGetMaxY(self->_topControls.frame);
    if ([self isShowingTitleLabel]) {
        self->_titleViewForCompactWidth.hidden = NO;
    }else{
        self->_titleViewForCompactWidth.hidden = YES;
    }
    
    CGRect contentRect;
    {
        NSUInteger itemCount = [self->_sortedItems count];
        NSUInteger rowCount = (itemCount / itemsPerRow) + ((itemCount % itemsPerRow) == 0 ? 0 : 1);
    
        CGRect bounds = self.bounds;
        CGSize contentSize = CGSizeMake(layoutSize.width, rowCount * (itemSize.height + [self _verticalPadding]) + topControlsHeight + [self _verticalPadding]);
        contentSize.height = MAX(contentSize.height, layoutSize.height);
        
        self.contentSize = contentSize;
        
        // Now, clamp the content offset. This can get out of bounds if we are scrolled way to the end in portait mode and flip to landscape.
        
        //        NSLog(@"self.bounds = %@", NSStringFromCGRect(bounds));
        //        NSLog(@"self.contentSize = %@", NSStringFromCGSize(contentSize));
        //        NSLog(@"self.contentOffset = %@", NSStringFromCGPoint(self.contentOffset));
        
        CGPoint contentOffset = self.contentOffset;
        CGPoint clampedContentOffset = _clampContentOffset(self, contentOffset);
        if (!CGPointEqualToPoint(contentOffset, clampedContentOffset))
            self.contentOffset = contentOffset; // Don't reset if it is the same, or this'll kill off any bounce animation
        
        contentRect.origin = contentOffset;
        contentRect.size = bounds.size;
        DEBUG_LAYOUT(@"contentRect = %@", NSStringFromCGRect(contentRect));
    }
    
    return (LayoutInfo){
        .topControlsHeight = topControlsHeight,
        .contentRect = contentRect,
        .itemSize = itemSize,
        .itemsPerRow = itemsPerRow,
        .horizontalPadding = [self _horizontalPadding],
        .verticalPadding = [self _verticalPadding],
    };
}

- (void)layoutSubviews;
{
    LayoutInfo layoutInfo = _updateLayout(self);
    CGSize itemSize = layoutInfo.itemSize;
    CGRect contentRect = layoutInfo.contentRect;
    
    if (itemSize.width <= 0 || itemSize.height <= 0) {
        // We aren't sized right yet
        DEBUG_LAYOUT(@"  Bailing since we have zero size");
        return;
    }
    
    [_renameSession layoutDimmingView];
    
    if (self.window) {  // otherwise, our width isn't set correctly yet and frame math goes wrong before it goes right, causing undesired animations
        if (_topControls) {
            if ([_topControls superview] != self){
                _topControls.alpha = 0;
                [self addSubview:_topControls];
            }
        }
        if (_titleViewForCompactWidth) {
            if ([_titleViewForCompactWidth superview] != self) {
                CGRect frame = _titleViewForCompactWidth.frame;
                frame.origin.x = (CGRectGetWidth(contentRect) / 2) - (frame.size.width / 2);
                frame.size.height = CGRectGetHeight(frame);
                frame.origin.y = CGRectGetMaxY(_topControls.frame) - frame.size.height;
                frame = CGRectIntegral(frame);
                _titleViewForCompactWidth.frame = frame;
                [self addSubview:_titleViewForCompactWidth];
            }
        }
        
        if (_topControls) {
            CGRect frame = _topControls.frame;
            frame.origin.x = (CGRectGetWidth(contentRect) / 2) - (frame.size.width / 2);
            frame.origin.y = fmax((CGRectGetHeight(_topControls.frame) / 2) - (frame.size.height / 2), [self _verticalPadding]);
            frame = CGRectIntegral(frame);
            _topControls.frame = frame;
        }
        
        if (_titleViewForCompactWidth) {
            
            CGRect possibleLayoutSizeForTitleLabel = self.bounds;
            NSStringDrawingContext *stringContext = [[NSStringDrawingContext alloc] init];
            stringContext.minimumScaleFactor = 1.0;
            CGRect frame = [_titleViewForCompactWidth.text boundingRectWithSize:possibleLayoutSizeForTitleLabel.size
                                                                        options:NSStringDrawingUsesLineFragmentOrigin
                                                                     attributes:@{NSFontAttributeName : _titleViewForCompactWidth.font}
                                                                        context:stringContext];
            frame.origin.x = (CGRectGetWidth(contentRect) / 2) - (frame.size.width / 2);
            frame.origin.y = fmax(CGRectGetMaxY(_topControls.frame) - frame.size.height, _topControls.frame.origin.y + [self _verticalPadding]) ;
            
            _titleViewForCompactWidth.frame = frame;
            
            if (CGRectGetMaxY(_topControls.frame) < CGRectGetMaxY(_titleViewForCompactWidth.frame)) {
                _topControls.frame = CGRectUnion(_topControls.frame, _titleViewForCompactWidth.frame);
            }
        }
        
        if (_topControls) {
            // Scroll past the top controls if they are visible and we are supposed to (coming on screen).
            if (_shouldHideTopControlsOnNextLayout) {
                _shouldHideTopControlsOnNextLayout = NO;
                
                CGPoint offset = self.contentOffset;
                offset.y = [self contentOffsetYToHideTopControls];
                
                if (offset.y > self.contentOffset.y) {
                    self.contentOffset = offset;
                }
            }
        }
    }

    // Expand the visible content rect to preload nearby previews
    CGRect previewLoadingRect = CGRectInset(contentRect, 0, -contentRect.size.height);
    
    // We don't need this for the scroller and calling it causes our item views to layout their contents out before we've adjusted their frames (and we don't even want to layout the hidden views).
    // [super layoutSubviews];
    
    // The newly created views need to get laid out the first time w/o animation on.
    OUIWithAnimationsDisabled(_flags.isAnimatingRotationChange, ^{
        // Keep track of which item views are in use by visible items
        NSMutableArray *unusedFileItemViews = [[NSMutableArray alloc] initWithArray:_fileItemViews];
        NSMutableArray *unusedGroupItemViews = [[NSMutableArray alloc] initWithArray:_groupItemViews];
        
        // Keep track of items that don't have views that need them.
        NSMutableArray *visibleItemsWithoutView = nil;
        NSUInteger positionIndex = 0;
        
        NSMutableDictionary *previousFileItemToPreview = [[NSMutableDictionary alloc] initWithDictionary:_fileItemToPreview];
        NSMutableDictionary *updatedFileItemToPreview = [[NSMutableDictionary alloc] init];
        
        // Build a item->view mapping once; calling -itemViewForItem: is too slow w/in this loop since -layoutSubviews is called very frequently.
        NSMutableDictionary *itemToView = [[NSMutableDictionary alloc] init];
        {
            for (OUIDocumentPickerFileItemView *itemView in _fileItemViews) {
                ODSFileItem *fileItem = (ODSFileItem *)itemView.item;
                if (fileItem)
                    [itemToView setObject:itemView forKey:fileItem];
            }
            
            for (OUIDocumentPickerGroupItemView *itemView in _groupItemViews) {
                ODSFolderItem *groupItem = (ODSFolderItem *)itemView.item;
                if (groupItem)
                    [itemToView setObject:itemView forKey:groupItem];
            }
        }
        
        for (ODSItem *item in _sortedItems) {        
            // Calculate the frame we would use for each item.
            DEBUG_LAYOUT(@"item (%ld,%ld) %@", row, column, [item shortDescription]);
            
            CGRect frame = _frameForPositionAtIndex(positionIndex, layoutInfo);
            
            // If the item is on screen, give it a view to use
            CGRect adjustedContentRect = contentRect;
            
            if (UIAccessibilityIsVoiceOverRunning()) {
                // make sure VoiceOver knows about the the items in the row above the on screen top row, and below the on screen bottom row.
                adjustedContentRect.size.height += itemSize.height;
            }
            
            BOOL itemVisible = CGRectIntersectsRect(frame, adjustedContentRect);
            
            BOOL shouldLoadPreview = CGRectIntersectsRect(frame, previewLoadingRect);
            
            if ([item isKindOfClass:[ODSFileItem class]]) {
                ODSFileItem *fileItem = (ODSFileItem *)item;
                OUIDocumentPreview *preview = [previousFileItemToPreview objectForKey:fileItem];
                
                if (shouldLoadPreview) {
                    if (!preview) {
                        Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:fileItem.fileURL];
                        preview = [OUIDocumentPreview makePreviewForDocumentClass:documentClass fileItem:fileItem withArea:OUIDocumentPreviewAreaLarge];
                        [preview incrementDisplayCount];
                    }
                    [updatedFileItemToPreview setObject:preview forKey:fileItem];
                } else {
                    if (preview)
                        [preview decrementDisplayCount];
                }
                
                [previousFileItemToPreview removeObjectForKey:fileItem];
            } else if ([item isKindOfClass:[ODSFolderItem class]]) {
                if (shouldLoadPreview) {
                    OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
                    [itemView loadPreviews];
                }
            }
            
            DEBUG_LAYOUT(@"  assigned frame %@, visible %d", NSStringFromCGRect(frame), itemVisible);
            
            if (itemVisible) {
                OUIDocumentPickerItemView *itemView = [itemToView objectForKey:item];

                // If it is visible and already has a view, let it keep the one it has.
                if (itemView) {
                    OBASSERT([unusedFileItemViews containsObjectIdenticalTo:itemView] ^ [unusedGroupItemViews containsObjectIdenticalTo:itemView]);
                    [unusedFileItemViews removeObjectIdenticalTo:itemView];
                    [unusedGroupItemViews removeObjectIdenticalTo:itemView];
                    itemView.frame = frame;
                    DEBUG_LAYOUT(@"  kept view %@", [itemView shortDescription]);
                } else {
                    // This item needs a view!
                    if (!visibleItemsWithoutView)
                        visibleItemsWithoutView = [NSMutableArray array];
                    [visibleItemsWithoutView addObject:item];
                }
            }
            
            if (!([_itemsIgnoredForLayout containsObject:item])) {
                positionIndex++;
            }
        }
        
        
        _fileItemToPreview = [updatedFileItemToPreview copy];
        
        [previousFileItemToPreview enumerateKeysAndObjectsUsingBlock:^(ODSFileItem *fileItem, OUIDocumentPreview *preview, BOOL *stop) {
            [preview decrementDisplayCount];
        }];
        
        // Now, assign views to visibile or nearly visible items that don't have them. First, union the two lists.
        for (ODSItem *item in visibleItemsWithoutView) {            
            
            NSMutableArray *itemViews = nil;
            if ([item isKindOfClass:[ODSFileItem class]]) {
                itemViews = unusedFileItemViews;
            } else {
                itemViews = unusedGroupItemViews;
            }
            OUIDocumentPickerItemView *itemView = [itemViews lastObject];
            
            if (itemView) {
                OBASSERT(itemView.superview == self); // we keep these views as subviews, just hide them.
                
                // Make the view start out at the "original" position instead of flying from where ever it was last left.
                [UIView performWithoutAnimation:^{
                    itemView.hidden = NO;
                    itemView.frame = [self frameForItem:item];
                    itemView.shrunken = ([_itemsBeingAdded member:item] != nil);
                    [itemView setEditing:_flags.isEditing animated:NO];
                    itemView.item = item;
                }];
                
                if ([self.delegate respondsToSelector:@selector(documentPickerScrollView:willDisplayItemView:)])
                    [self.delegate documentPickerScrollView:self willDisplayItemView:itemView];

                [itemViews removeLastObject];
                DEBUG_LAYOUT(@"Assigned view %@ to item %@", [itemView shortDescription], item.name);
            } else {
                DEBUG_LAYOUT(@"Missing view for item %@ at %@", item.name, NSStringFromCGRect([self frameForItem:item]));
                OBASSERT(itemView); // we should never run out given that we make enough up front
            }
        }
        
        // Update dragging state
        for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
            if (fileItemView.hidden) {
                fileItemView.draggingState = OUIDocumentPickerItemViewNoneDraggingState;
                continue;
            }
            
            ODSFileItem *fileItem = (ODSFileItem *)fileItemView.item;
            OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);
            
            OBASSERT(!fileItem.draggingSource || fileItem != _draggingDestinationItem); // can't be both the source and destination of a drag!
            
            if (fileItem == _draggingDestinationItem)
                fileItemView.draggingState = OUIDocumentPickerItemViewDestinationDraggingState;
            else if (fileItem.draggingSource)
                fileItemView.draggingState = OUIDocumentPickerItemViewSourceDraggingState;
            else
                fileItemView.draggingState = OUIDocumentPickerItemViewNoneDraggingState;        
        }
        
        // Any remaining unused item views should have no item and be hidden.
        for (OUIDocumentPickerFileItemView *view in unusedFileItemViews) {
            view.hidden = YES;
            [view prepareForReuse];
            if ([self.delegate respondsToSelector:@selector(documentPickerScrollView:willEndDisplayingItemView:)])
                [self.delegate documentPickerScrollView:self willEndDisplayingItemView:view];
            
        }
        for (OUIDocumentPickerGroupItemView *view in unusedGroupItemViews) {
            view.hidden = YES;
            [view prepareForReuse];
            if ([self.delegate respondsToSelector:@selector(documentPickerScrollView:willEndDisplayingItemView:)])
                [self.delegate documentPickerScrollView:self willEndDisplayingItemView:view];
        }
    });
}

#pragma mark - NSObject (OUIDocumentPickerItemMetadataView)

- (void)documentPickerItemNameStartedEditing:(id)sender;
{
    UIView *view = sender; // This is currently the private name+date view. Could hook this up better if this all works out (maybe making our item view publish a 'started editing' control event.
    OUIDocumentPickerItemView *itemView = [view containingViewOfClass:[OUIDocumentPickerItemView class]];
    
    // should be one of ours, not some other temporary animating item view
    OBASSERT([_fileItemViews containsObjectIdenticalTo:itemView] ^ [_groupItemViews containsObjectIdenticalTo:itemView]);

    [self.delegate documentPickerScrollView:self itemViewStartedEditingName:itemView];
}

- (void)documentPickerItemNameEndedEditing:(id)sender withName:(NSString *)name;
{
    UIView *view = sender; // This is currently the private name+date view. Could hook this up better if this all works out (maybe making our item view publish a 'started editing' control event.
    OUIDocumentPickerItemView *itemView = [view containingViewOfClass:[OUIDocumentPickerItemView class]];
    
    // should be one of ours, not some other temporary animating item view
    OBASSERT([_fileItemViews containsObjectIdenticalTo:itemView] ^ [_groupItemViews containsObjectIdenticalTo:itemView]);
    
    [self.delegate documentPickerScrollView:self itemView:itemView finishedEditingName:(NSString *)name];
}

#pragma mark - Private

- (void)_itemViewTapped:(OUIDocumentPickerItemView *)itemView;
{
    // should be one of ours, not some other temporary animating item view
    OBASSERT([_fileItemViews containsObjectIdenticalTo:itemView] ^ [_groupItemViews containsObjectIdenticalTo:itemView]);
        
    [self.delegate documentPickerScrollView:self itemViewTapped:itemView];
}

- (void)_itemViewLongpressed:(UIGestureRecognizer*)gesture
{
    if (gesture.state == UIGestureRecognizerStateBegan) {        
        OUIDocumentPickerItemView *itemView = OB_CHECKED_CAST(OUIDocumentPickerItemView, gesture.view);
        
        // should be one of ours, not some other temporary animating item view
        OBASSERT([_fileItemViews containsObjectIdenticalTo:itemView] ^ [_groupItemViews containsObjectIdenticalTo:itemView]);
        
        [self.delegate documentPickerScrollView:self itemViewLongpressed:itemView];
    }
}

// The size of the document prevew grid in items. That is, if gridSize.width = 4, then 4 items will be shown across the width.
// The width must be at least one and integral. The height must be at least one, but may be non-integral if you want to have a row of itemss peeking out.
- (CGSize)_gridSize;
{
    CGSize layoutSize = self.bounds.size;
    if (layoutSize.width <= 0 || layoutSize.height <= 0)
        return CGSizeMake(1,1); // placeholder because layoutSize not set yet

    // Adding a single kOUIDocumentPickerItemHorizontalPadding here because we want to compute the space for itemWidth*nItems + padding*(nItems-1), moving padding*1 to the other side of the equation simplifies everything else
    layoutSize.width += [self _horizontalPadding];
    
    CGFloat itemWidth = kOUIDocumentPickerItemNormalSize;
    CGFloat itemsAcross = floor(layoutSize.width / (itemWidth + [self _horizontalPadding]));
    CGFloat rotatedItemsAcross = floor(layoutSize.height / (itemWidth + [self _horizontalPadding]));

    if (itemsAcross < 3 || rotatedItemsAcross < 3) {
        itemWidth = kOUIDocumentPickerItemSmallSize;
        self.isUsingSmallItems = YES;
        itemsAcross = floor(layoutSize.width / (itemWidth + [self _horizontalPadding]));
    }
    return CGSizeMake(itemsAcross, layoutSize.height / (itemWidth + [self _verticalPadding]));
}

- (CGFloat)_horizontalPadding;
{
    if (self.isUsingSmallItems)
        return kOUIDocumentPickerItemSmallHorizontalPadding;
    else
        return kOUIDocumentPickerItemHorizontalPadding;
}

- (CGFloat)_verticalPadding;
{
    if (self.isUsingSmallItems)
        return kOUIDocumentPickerItemSmallVerticalPadding;
    else
        return kOUIDocumentPickerItemVerticalPadding;
}

@end
