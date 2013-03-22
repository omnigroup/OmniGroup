// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerScrollView.h>

#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDirectTapGestureRecognizer.h>
#import <OmniUI/OUIDragGestureRecognizer.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerGroupItemView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIMainViewController.h>

#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIMainViewControllerBackgroundView.h"

RCS_ID("$Id$");

NSString * const OUIDocumentPickerScrollViewItemsBinding = @"items";

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_LAYOUT(format, ...) NSLog(@"DOC LAYOUT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_LAYOUT(format, ...)
#endif

static const CGFloat kItemVerticalPadding = 27;
static const CGFloat kItemHorizontalPadding = 28;
static const UIEdgeInsets kEdgeInsets = (UIEdgeInsets){35/*top*/, 35/*left*/, 35/*bottom*/, 35/*right*/};

typedef struct LayoutInfo {
    CGRect contentRect;
    CGSize itemSize;
    NSUInteger itemsPerRow;
} LayoutInfo;

static LayoutInfo _updateLayout(OUIDocumentPickerScrollView *self);

// Items are laid out in a fixed size grid.
static CGRect _frameForPositionAtIndex(NSUInteger itemIndex, CGSize itemSize, NSUInteger itemsPerRow)
{
    OBPRECONDITION(itemSize.width > 0);
    OBPRECONDITION(itemSize.height > 0);
    OBPRECONDITION(itemsPerRow > 0);
    
    NSUInteger row = itemIndex / itemsPerRow;
    NSUInteger column = itemIndex % itemsPerRow;
    
    CGRect frame = CGRectMake(column * (itemSize.width + kItemHorizontalPadding), row * (itemSize.height + kItemVerticalPadding), itemSize.width, itemSize.height);
    
    // CGRectIntegral can make the rect bigger when the size is integral but the position is fractional. We want the size to remain the same.
    CGRect integralFrame;
    integralFrame.origin.x = floor(frame.origin.x);
    integralFrame.origin.y = floor(frame.origin.y);
    integralFrame.size = frame.size;
    
    return CGRectIntegral(integralFrame);
}

static CGPoint _clampContentOffset(CGPoint contentOffset, CGRect bounds, CGSize contentSize)
{
    OFExtent contentOffsetYExtent = OFExtentMake(-kEdgeInsets.top, MAX(0, contentSize.height - bounds.size.height + kEdgeInsets.top + kEdgeInsets.bottom));
    CGPoint clampedContentOffset = CGPointMake(contentOffset.x, OFExtentClampValue(contentOffsetYExtent, contentOffset.y));
    return clampedContentOffset;
}

@interface OUIDocumentPickerScrollView (/*Private*/)
- (void)_itemViewTapped:(UITapGestureRecognizer *)recognizer;
+ (CGSize)_gridSizeForLandscape:(BOOL)landscape;
- (void)_startDragRecognizer:(OUIDragGestureRecognizer *)recognizer;
@end

@implementation OUIDocumentPickerScrollView
{
    BOOL _landscape;
    
    NSMutableSet *_items;
    NSArray *_sortedItems;
    id _draggingDestinationItem;
    
    NSMutableSet *_itemsBeingAdded;
    NSMutableSet *_itemsBeingRemoved;
    NSMutableSet *_itemsIgnoredForLayout;
    NSDictionary *_fileItemToPreview; // For visible or nearly visible files
    
    struct {
        unsigned int isAnimatingRotationChange:1;
        unsigned int isEditing:1;
    } _flags;
    
    OUIDocumentPickerItemSort _itemSort;

    NSArray *_itemViewsForPreviousOrientation;
    NSArray *_fileItemViews;
    NSArray *_groupItemViews;
    
    OUIDragGestureRecognizer *_startDragRecognizer;
    
    NSTimeInterval _rotationDuration;
}

static id _commonInit(OUIDocumentPickerScrollView *self)
{
    self->_items = [[NSMutableSet alloc] init];
    self->_itemsBeingAdded = [[NSMutableSet alloc] init];
    self->_itemsBeingRemoved = [[NSMutableSet alloc] init];
    self->_itemsIgnoredForLayout = [[NSMutableSet alloc] init];
    
    self.showsVerticalScrollIndicator = YES;
    self.showsHorizontalScrollIndicator = NO;
    
    self.alwaysBounceVertical = YES;
    
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
    [_fileItemToPreview enumerateKeysAndObjectsUsingBlock:^(OFSDocumentStore *fileItem, OUIDocumentPreview *preview, BOOL *stop) {
        [preview decrementDisplayCount];
    }];
    
    _startDragRecognizer.delegate = nil;
    _startDragRecognizer = nil;
}

- (id <OUIDocumentPickerScrollViewDelegate>)delegate;
{
    return (id <OUIDocumentPickerScrollViewDelegate>)[super delegate];
}

- (void)setDelegate:(id <OUIDocumentPickerScrollViewDelegate>)delegate;
{
    OBPRECONDITION(!delegate || [delegate conformsToProtocol:@protocol(OUIDocumentPickerScrollViewDelegate)]);

    [super setDelegate:delegate];
}

/*
 This and -didRotate can be called to perform an animated swap of item views between their current and new orientation (in -setLandscape:).
 If this is not called around a call to -setLandscape:, then the change is assumed to be taking place off screen and will be unanimated.
 */

- (void)willRotateWithDuration:(NSTimeInterval)duration;
{
    OBPRECONDITION(self.window); // No point in animating while off screen.
    OBPRECONDITION(_flags.isAnimatingRotationChange == NO);
    
    DEBUG_LAYOUT(@"willRotateWithDuration:%f", duration);
    
    _flags.isAnimatingRotationChange = YES;
    _rotationDuration = duration;
    
    // Fade out old item views, preparing for a whole new array in the -setGridSize:
    OBASSERT(_itemViewsForPreviousOrientation == nil);
    OBASSERT(_fileItemViews != nil);
    OBASSERT(_groupItemViews != nil);
    _itemViewsForPreviousOrientation = [_fileItemViews arrayByAddingObjectsFromArray:_groupItemViews];
    
    _fileItemViews = nil;
    _groupItemViews = nil;
    
    // Elevate the old previews above the new ones that will be made
    for (OUIDocumentPickerItemView *itemView in _itemViewsForPreviousOrientation) {
        itemView.gestureRecognizers = nil;
        itemView.layer.zPosition = 1;
    }
    
    // ... and fade them out, exposing the new ones
    [UIView beginAnimations:nil context:NULL];
    {
        if (_rotationDuration > 0)
            [UIView setAnimationDuration:_rotationDuration];
        for (OUIDocumentPickerItemView *itemView in _itemViewsForPreviousOrientation) {
            if (itemView.hidden == NO)
                itemView.alpha = 0;
        }
    }
    [UIView commitAnimations];
}

- (void)didRotate;
{
    OBPRECONDITION(self.window); // No point in animating while off screen.
    OBPRECONDITION(_flags.isAnimatingRotationChange == YES);
    
    DEBUG_LAYOUT(@"didRotate");
    
    // Tell the new views we are done with the rotation
    if (_flags.isAnimatingRotationChange) {
        for (OUIDocumentPickerItemView *itemView in _fileItemViews)
            itemView.animatingRotationChange = YES;
        for (OUIDocumentPickerItemView *itemView in _groupItemViews)
            itemView.animatingRotationChange = YES;
    }

    _flags.isAnimatingRotationChange = NO;
    
    // Ditch the old fully faded previews 
    OUIWithoutAnimating(^{
        for (OUIDocumentPickerItemView *view in _itemViewsForPreviousOrientation)
            [view removeFromSuperview];
        _itemViewsForPreviousOrientation = nil;
    });
}

static NSUInteger _itemViewsForGridSize(CGSize gridSize)
{
    OBPRECONDITION(gridSize.width == rint(gridSize.width));
    
    NSUInteger width = ceil(gridSize.width);
    NSUInteger height = ceil(gridSize.height + 1.0); // partial row scrolled off the top, partial row off the bottom
    
    return width * height;
}

static NSArray *_newItemViews(OUIDocumentPickerScrollView *self, Class itemViewClass)
{
    OBASSERT(OBClassIsSubclassOfClass(itemViewClass, [OUIDocumentPickerItemView class]));
    OBASSERT(itemViewClass != [OUIDocumentPickerItemView class]);
    
    NSMutableArray *itemViews = [[NSMutableArray alloc] init];

    NSUInteger neededItemViewCount = _itemViewsForGridSize([[self class] _gridSizeForLandscape:self->_landscape]);
    while (neededItemViewCount--) {
        OUIDocumentPickerItemView *itemView = [[itemViewClass alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        itemView.landscape = self->_landscape;
        
        [itemViews addObject:itemView];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_itemViewTapped:)];
        [itemView addGestureRecognizer:tap];
        
        itemView.hidden = YES;
        [self addSubview:itemView];
    }
    
    NSArray *result = [itemViews copy];
    return result;
}

@synthesize landscape = _landscape;
- (void)setLandscape:(BOOL)landscape;
{
    if (_fileItemViews && _groupItemViews && _landscape == landscape)
        return;
    
    DEBUG_LAYOUT(@"setLandscape:%d", landscape);

    _landscape = landscape;
    
    if (_flags.isAnimatingRotationChange) {
        OBASSERT(self.window);
        // We are on screen and rotating, so -willRotate should have been called. Still, we'll try to handle this reasonably below.
        OBASSERT(_fileItemViews == nil);
        OBASSERT(_groupItemViews == nil);
    } else {
        // The device was rotated while our view controller was off screen. It doesn't get told about the rotation in that case and we just get a landscape change. We might also have been covered by a modal view controller but are being revealed again.
        OBASSERT(self.window == nil);
    }
    
    // Figure out whether we should do the animation outside of the OUIWithoutAnimating block (else +areAnimationsEnabled will be trivially NO).
    BOOL shouldCrossFade = _flags.isAnimatingRotationChange && [UIView areAnimationsEnabled];
    
    // Make the new views (which will start out hidden).
    OUIWithoutAnimating(^{
        [_fileItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        _fileItemViews = _newItemViews(self, [OUIDocumentPickerFileItemView class]);
        
        [_groupItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        _groupItemViews = _newItemViews(self, [OUIDocumentPickerGroupItemView class]);
        
        // Tell the new views that they shouldn't animate layout, if we are rotating.
        // We do want to fade them in, though.
        if (shouldCrossFade) {
            for (OUIDocumentPickerItemView *itemView in _fileItemViews) {
                itemView.animatingRotationChange = YES;
                itemView.alpha = 0;
            }
            for (OUIDocumentPickerItemView *itemView in _groupItemViews) {
                itemView.animatingRotationChange = YES;
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
    
    [self setNeedsLayout];
}

@synthesize items = _items;

- (void)startAddingItems:(NSSet *)toAdd;
{
    OBPRECONDITION([toAdd intersectsSet:_items] == NO);
    OBPRECONDITION([toAdd intersectsSet:_itemsBeingAdded] == NO);

    [_items unionSet:toAdd];
    [_itemsBeingAdded unionSet:toAdd];
    
    [self sortItems];
    [self setNeedsLayout];
}

- (void)finishAddingItems:(NSSet *)toAdd;
{
    OBPRECONDITION([toAdd isSubsetOfSet:_items]);
    OBPRECONDITION([toAdd isSubsetOfSet:_itemsBeingAdded]);

    [_itemsBeingAdded minusSet:toAdd];
    
    for (OFSDocumentStoreItem *item in toAdd) {
        OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
        OBASSERT(!itemView || itemView.shrunken);
        itemView.shrunken = NO;
    }
    
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

@synthesize itemsBeingAdded = _itemsBeingAdded;

- (void)startRemovingItems:(NSSet *)toRemove;
{
    OBPRECONDITION([toRemove isSubsetOfSet:_items]);
    OBPRECONDITION([toRemove intersectsSet:_itemsBeingRemoved] == NO);

    [_itemsBeingRemoved unionSet:toRemove];

    for (OFSDocumentStoreItem *item in toRemove) {
        OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
        itemView.shrunken = YES;
    }
}

- (void)finishRemovingItems:(NSSet *)toRemove;
{
    OBPRECONDITION([toRemove isSubsetOfSet:_items]);
    OBPRECONDITION([toRemove isSubsetOfSet:_itemsBeingRemoved]);

    for (OFSDocumentStoreItem *item in toRemove) {
        OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
        OBASSERT(!itemView || itemView.shrunken);
        itemView.shrunken = NO;
    }

    [_itemsBeingRemoved minusSet:toRemove];
    [_items minusSet:toRemove];
    [self sortItems]; // The order hasn't changed, but w/o this the sorted array would still have the removed items
    
    [self setNeedsLayout];
    
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

@synthesize itemsBeingRemoved = _itemsBeingRemoved;

- (NSArray *)_sortDescriptors;
{
    NSMutableArray *descriptors = [NSMutableArray array];
    
    if (_itemSort == OUIDocumentPickerItemSortByDate) {
        NSSortDescriptor *dateSort = [[NSSortDescriptor alloc] initWithKey:OFSDocumentStoreItemUserModificationDateBinding ascending:NO];
        [descriptors addObject:dateSort];
        
        // fall back to name sorting if the dates are equal
    }
    
    NSSortDescriptor *nameSort = [[NSSortDescriptor alloc] initWithKey:OFSDocumentStoreItemNameBinding ascending:YES selector:@selector(localizedStandardCompare:)];
    [descriptors addObject:nameSort];
    
    return descriptors;
}

- (void)sortItems;
{
    OBASSERT(_items);
    if (!_items)
        return;
    
    NSArray *newSort = [[_items allObjects] sortedArrayUsingDescriptors:[self _sortDescriptors]];
    if (OFNOTEQUAL(newSort, _sortedItems)) {
        _sortedItems = [newSort copy];
        [self setNeedsLayout];
    }
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
    [self sortItems];
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
    return CGPointMake(-kEdgeInsets.left, floor(CGRectGetMidY(itemFrame) - self.bounds.size.height / 2));
}

- (void)scrollItemToVisible:(OFSDocumentStoreItem *)item animated:(BOOL)animated;
{
    return [self scrollItemsToVisible:[NSArray arrayWithObjects:item, nil] animated:animated];
}

- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated;
{
    [self layoutIfNeeded];

    CGPoint contentOffset = self.contentOffset;
    CGRect bounds = self.bounds;
    
    CGRect contentRect;
    contentRect.origin = contentOffset;
    contentRect.size = bounds.size;
    
    CGRect itemsFrame = CGRectNull;
    for (OFSDocumentStoreItem *item in items) {
        CGRect itemFrame = [self frameForItem:item];
        if (CGRectIsNull(itemFrame))
            itemsFrame = itemFrame;
        else
            itemsFrame = CGRectUnion(itemsFrame, itemFrame);
    }

    // If all the rects are fully visible, nothing to do.
    if (CGRectContainsRect(contentRect, itemsFrame))
        return;
    
    CGSize contentSize = self.contentSize;
    CGPoint clampedContentOffset = _clampContentOffset(_contentOffsetForCenteringItem(self, itemsFrame), bounds, contentSize);
    
    if (!CGPointEqualToPoint(contentOffset, clampedContentOffset)) {
        [self setContentOffset:clampedContentOffset animated:animated];
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }
}

- (CGRect)frameForItem:(OFSDocumentStoreItem *)item;
{
    LayoutInfo layoutInfo = _updateLayout(self);
    CGSize itemSize = layoutInfo.itemSize;
    NSUInteger itemsPerRow = layoutInfo.itemsPerRow;

    if (itemSize.width <= 0 || itemSize.height <= 0) {
        // We aren't sized right yet
        OBASSERT_NOT_REACHED("Asking for the frame of an item before we are laid out.");
        return CGRectZero;
    }

    NSUInteger positionIndex;
    if ([_itemsIgnoredForLayout count] > 0) {
        positionIndex = NSNotFound;
        
        NSUInteger itemIndex = 0;
        for (OFSDocumentStoreItem *sortedItem in _sortedItems) {
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

    return _frameForPositionAtIndex(positionIndex, itemSize, itemsPerRow);
}

- (OUIDocumentPickerItemView *)itemViewForItem:(OFSDocumentStoreItem *)item;
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

- (OUIDocumentPickerFileItemView *)fileItemViewForFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if (fileItemView.item == fileItem)
            return fileItemView;
    }
    
    return nil;
}

// We don't use -[UIGestureRecognizer(OUIExtensions) hitView] or our own -hitTest: since while we are in the middle of dragging, extra item views will be added to us by the drag session.
static OUIDocumentPickerItemView *_itemViewHitInPreviewAreaByRecognizer(NSArray *itemViews, UIGestureRecognizer *recognizer)
{
    for (OUIDocumentPickerItemView *itemView in itemViews) {
        // The -hitTest:withEvent: below doesn't consider ancestor isHidden flags.
        if (itemView.hidden)
            continue;
        OUIDocumentPreviewView *previewView = itemView.previewView;
        UIView *hitView = [previewView hitTest:[recognizer locationInView:previewView] withEvent:nil];
        if (hitView)
            return itemView;
    }
    return nil;
}

- (OUIDocumentPickerItemView *)itemViewHitInPreviewAreaByRecognizer:(UIGestureRecognizer *)recognizer;
{
    OUIDocumentPickerItemView *itemView = _itemViewHitInPreviewAreaByRecognizer(_fileItemViews, recognizer);
    if (itemView)
        return itemView;
    return _itemViewHitInPreviewAreaByRecognizer(_groupItemViews, recognizer);
}

- (OUIDocumentPickerFileItemView *)fileItemViewHitInPreviewAreaByRecognizer:(UIGestureRecognizer *)recognizer;
{
    return (OUIDocumentPickerFileItemView *)_itemViewHitInPreviewAreaByRecognizer(_fileItemViews, recognizer);
}

// Used to pick file items that are visible for automatic download (if they are small and we are on wi-fi) or preview generation.
- (OFSDocumentStoreFileItem *)preferredVisibleItemFromSet:(NSSet *)fileItemsNeedingPreviewUpdate;
{
    // Prefer to update items that are visible, and then among those, do items starting at the top-left.
    OFSDocumentStoreFileItem *bestFileItem = nil;
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
        OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)fileItemView.item;
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

- (void)previewsUpdatedForFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if (fileItemView.item == fileItem) {
            [fileItemView previewsUpdated];
            return;
        }
    }
    
    for (OUIDocumentPickerGroupItemView *groupItemView in _groupItemViews) {
        OFSDocumentStoreGroupItem *groupItem = (OFSDocumentStoreGroupItem *)groupItemView.item;
        if ([groupItem.fileItems member:fileItem]) {
            [groupItemView previewsUpdated];
            return;
        }
    }
}

- (void)startIgnoringItemForLayout:(OFSDocumentStoreItem *)item;
{
    OBASSERT(!([_itemsIgnoredForLayout containsObject:item]));
    [_itemsIgnoredForLayout addObject:item];
}

- (void)stopIgnoringItemForLayout:(OFSDocumentStoreItem *)item;
{
    OBASSERT([_itemsIgnoredForLayout containsObject:item]);
    [_itemsIgnoredForLayout removeObject:item];
}

#pragma mark -
#pragma mark UIView

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    [super willMoveToWindow:newWindow];
    
    if (newWindow && _startDragRecognizer == nil) {
        // UIScrollView has recognizers, but doesn't delcare that it is their delegate. Hopefully they are leaving this open for subclassers.
        OBASSERT([UIScrollView conformsToProtocol:@protocol(UIGestureRecognizerDelegate)] == NO);

        _startDragRecognizer = [[OUIDragGestureRecognizer alloc] initWithTarget:self action:@selector(_startDragRecognizer:)];
        _startDragRecognizer.delegate = self;
        _startDragRecognizer.holdDuration = 0.5; // taken from UILongPressGestureRecognizer.h
        _startDragRecognizer.requiresHoldToComplete = YES;
        
        [self addGestureRecognizer:_startDragRecognizer];
    } else if (newWindow == nil && _startDragRecognizer != nil) {
        [self removeGestureRecognizer:_startDragRecognizer];
        _startDragRecognizer.delegate = nil;
        _startDragRecognizer = nil;
    }
}

static LayoutInfo _updateLayout(OUIDocumentPickerScrollView *self)
{    
    CGSize gridSize = [[self class] _gridSizeForLandscape:self->_landscape];
    OBASSERT(gridSize.width >= 1);
    OBASSERT(gridSize.width == trunc(gridSize.width));
    OBASSERT(gridSize.height >= 1);
    
    NSUInteger itemsPerRow = gridSize.width;
    
    // Calculate the item size we'll use. The results of this can be non-integral, allowing for accumulated round-off
    
    // Don't compute the item size based off our bounds. If the keyboard comes up we don't want our items to get smaller!
    CGSize layoutSize;
    {
        OUIMainViewController *mainViewController = [[OUIDocumentAppController controller] mainViewController];
        OUIMainViewControllerBackgroundView *layoutReferenceView = (OUIMainViewControllerBackgroundView *)mainViewController.view;
        CGRect layoutRect = [layoutReferenceView contentViewFullScreenBounds]; // Excludes the toolbar, but doesn't exclude the keyboard
        
        // We can get asked to lay out before we are in the view hierarchy, which will cause assertions to fire in this conversion. We don't expect to ever have a scaling applied, so since we just want the size, this works. Still would be nice to do the convertRect:fromView:...
        //layoutRect = [self convertRect:layoutRect fromView:layoutReferenceView];
        
        layoutSize = CGSizeMake(layoutRect.size.width - kEdgeInsets.left - kEdgeInsets.right, layoutRect.size.height - kEdgeInsets.top); // Don't subtract kEdgeInsets.bottom since the previews scroll off the bottom of the screen
    }
    
    CGSize itemSize;
    {
        // We may need to accumulate partial pixels to make the spacing as even as possible in width, so we only ceil the height (which we don't need to do such accumulation and which we *do* need to be integral to make it easier to determine the full content size).
        itemSize.width = (layoutSize.width - (itemsPerRow - 1) * kItemHorizontalPadding) / gridSize.width;
        itemSize.height = ceil((layoutSize.height - (floor(gridSize.height) * kItemVerticalPadding)) / gridSize.height);
    }
    
    DEBUG_LAYOUT(@"%@ Laying out %ld items with size %@", [self shortDescription], [self->_items count], NSStringFromCGSize(itemSize));
    
    if (itemSize.width <= 0 || itemSize.height <= 0) {
        // We aren't sized right yet
        DEBUG_LAYOUT(@"  Bailing since we have zero size");
        LayoutInfo layoutInfo;
        memset(&layoutInfo, 0, sizeof(layoutInfo));
        return layoutInfo;
    }
    
    
    CGRect contentRect;
    {
        NSUInteger itemCount = [self->_sortedItems count];
        NSUInteger rowCount = (itemCount / itemsPerRow) + ((itemCount % itemsPerRow) == 0 ? 0 : 1);
        
        CGRect bounds = self.bounds;
        CGSize contentSize = CGSizeMake(layoutSize.width, itemSize.height * rowCount + kItemVerticalPadding * (rowCount - 1));
        
        self.contentSize = contentSize;
        self.contentInset = kEdgeInsets;
        
        // Now, clamp the content offset. This can get out of bounds if we are scrolled way to the end in portait mode and flip to landscape.
        
        //        NSLog(@"self.bounds = %@", NSStringFromCGRect(bounds));
        //        NSLog(@"self.contentSize = %@", NSStringFromCGSize(contentSize));
        //        NSLog(@"self.contentOffset = %@", NSStringFromCGPoint(self.contentOffset));
        
        CGPoint contentOffset = self.contentOffset;
        CGPoint clampedContentOffset = _clampContentOffset(contentOffset, bounds, contentSize);
        if (!CGPointEqualToPoint(contentOffset, clampedContentOffset))
            self.contentOffset = contentOffset; // Don't reset if it is the same, or this'll kill off any bounce animation
        
        contentRect.origin = contentOffset;
        contentRect.size = bounds.size;
        DEBUG_LAYOUT(@"contentRect = %@", NSStringFromCGRect(contentRect));
    }
    
    return (LayoutInfo){
        .contentRect = contentRect,
        .itemSize = itemSize,
        .itemsPerRow = itemsPerRow
    };
}

- (void)layoutSubviews;
{
    LayoutInfo layoutInfo = _updateLayout(self);
    CGSize itemSize = layoutInfo.itemSize;
    CGRect contentRect = layoutInfo.contentRect;
    NSUInteger itemsPerRow = layoutInfo.itemsPerRow;
    
    if (itemSize.width <= 0 || itemSize.height <= 0) {
        // We aren't sized right yet
        DEBUG_LAYOUT(@"  Bailing since we have zero size");
        return;
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
                OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)itemView.item;
                if (fileItem)
                    [itemToView setObject:itemView forKey:fileItem];
            }
            
            for (OUIDocumentPickerGroupItemView *itemView in _groupItemViews) {
                OFSDocumentStoreGroupItem *groupItem = (OFSDocumentStoreGroupItem *)itemView.item;
                if (groupItem)
                    ;//                    [itemToView setObject:itemView forKey:groupItem];
            }
        }
        
        for (OFSDocumentStoreItem *item in _sortedItems) {        
            // Calculate the frame we would use for each item.
            DEBUG_LAYOUT(@"item (%ld,%ld) %@", row, column, [item shortDescription]);
            
            CGRect frame = _frameForPositionAtIndex(positionIndex, itemSize, itemsPerRow);
            
            // If the item is on screen, give it a view to use
            BOOL itemVisible = CGRectIntersectsRect(frame, contentRect);
            
            BOOL shouldLoadPreview = CGRectIntersectsRect(frame, previewLoadingRect);
            if ([item isKindOfClass:[OFSDocumentStoreFileItem class]]) {
                OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)item;
                OUIDocumentPreview *preview = [previousFileItemToPreview objectForKey:fileItem];
                
                if (shouldLoadPreview) {
                    if (!preview) {
                        Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:fileItem.fileURL];
                        preview = [OUIDocumentPreview makePreviewForDocumentClass:documentClass fileURL:fileItem.fileURL date:fileItem.fileModificationDate withLandscape:_landscape];
                        [preview incrementDisplayCount];
                    }
                    [updatedFileItemToPreview setObject:preview forKey:fileItem];
                } else {
                    if (preview)
                        [preview decrementDisplayCount];
                }
                
                [previousFileItemToPreview removeObjectForKey:fileItem];
            } else {
                OBASSERT_NOT_REACHED("Load previews for the group members");
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
        
        [previousFileItemToPreview enumerateKeysAndObjectsUsingBlock:^(OFSDocumentStoreFileItem *fileItem, OUIDocumentPreview *preview, BOOL *stop) {
            [preview decrementDisplayCount];
        }];
        
        // Check if item views that are changing items are (probably) doing so because we are scrolling
        BOOL disableAnimationOnItemChange = self.dragging || self.decelerating;
        
        // Now, assign views to visibile or nearly visible items that don't have them. First, union the two lists.
        for (OFSDocumentStoreItem *item in visibleItemsWithoutView) {            
            
            NSMutableArray *itemViews = nil;
            if ([item isKindOfClass:[OFSDocumentStoreFileItem class]]) {
                itemViews = unusedFileItemViews;
            } else {
                itemViews = unusedGroupItemViews;
            }
            OUIDocumentPickerItemView *itemView = [itemViews lastObject];
            
            if (itemView) {
                OBASSERT(itemView.superview == self); // we keep these views as subviews, just hide them.
                
                // Make the view start out at the "original" position instead of flying from where ever it was last left.
                OUIBeginWithoutAnimating
                {
                    itemView.hidden = NO;
                    itemView.frame = [self frameForItem:item];
                    itemView.shrunken = ([_itemsBeingAdded member:item] != nil);
                    [itemView setEditing:_flags.isEditing animated:NO];
                }
                OUIEndWithoutAnimating;
                
                OUIWithAnimationsDisabled(disableAnimationOnItemChange, ^{
                    itemView.item = item;
                });
                
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
            
            OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)fileItemView.item;
            OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
            
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
        }
        for (OUIDocumentPickerGroupItemView *view in unusedGroupItemViews) {
            view.hidden = YES;
            [view prepareForReuse];
        }
        
        
    });
}

#pragma mark -
#pragma mark UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer;
{
    if (gestureRecognizer == _startDragRecognizer) {
        if (_startDragRecognizer.wasATap)
            return NO;
        
        // Only start editing and float up a preview if we hit a file preview
        return ([self fileItemViewHitInPreviewAreaByRecognizer:_startDragRecognizer] != nil);
    }
    
    return YES;
}

#pragma mark -
#pragma mark Private

- (void)_itemViewTapped:(UITapGestureRecognizer *)recognizer;
{
    UIView *hitView = [recognizer hitView];
    OUIDocumentPickerItemView *itemView = [hitView containingViewOfClass:[OUIDocumentPickerItemView class]];
    if (itemView) {
        // should be one of ours, not some other temporary animating item view        
        OBASSERT([_fileItemViews containsObjectIdenticalTo:itemView] ^ [_groupItemViews containsObjectIdenticalTo:itemView]);
        
        OUIDocumentPickerItemViewTapArea area;
        if ([itemView getHitTapArea:&area withRecognizer:recognizer])
            [self.delegate documentPickerScrollView:self itemViewTapped:itemView inArea:area];
    }
}

// The size of the document prevew grid in items. That is, if gridSize.width = 4, then 4 items will be shown across the width.
// The width must be at least one and integral. The height must be at least one, but may be non-integral if you want to have a row of itemss peeking out.
+ (CGSize)_gridSizeForLandscape:(BOOL)landscape;
{
    // We could maybe make this configurable via a plist entry or delegate callback, but it needs to be relatively static so we can cache preview images at the exact right size (scaling preview images after the fact varies from slow to ugly based on the size of the original preview image).
    if (landscape)
        return CGSizeMake(4, 3.2);
    else
        return CGSizeMake(3, 3.175);
}

- (void)_startDragRecognizer:(OUIDragGestureRecognizer *)recognizer;
{
    OBPRECONDITION(recognizer == _startDragRecognizer);
    [self.delegate documentPickerScrollView:self dragWithRecognizer:_startDragRecognizer];
}

@end
