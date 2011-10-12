// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPickerScrollView.h>

#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDirectTapGestureRecognizer.h>
#import <OmniUI/OUIDocumentPickerFileItemView.h>
#import <OmniUI/OUIDocumentPickerGroupItemView.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUIDocumentStoreGroupItem.h>
#import <OmniUI/OUIMainViewController.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIDocumentPickerItemView-Internal.h"
#import "OUIDocumentPreviewView.h"
#import "OUIMainViewControllerBackgroundView.h"

RCS_ID("$Id$");

NSString * const OUIDocumentPickerScrollViewItemsBinding = @"items";

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_LAYOUT(format, ...) NSLog(@"DOC LAYOUT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_LAYOUT(format, ...)
#endif

// OUIDocumentPickerScrollViewDelegate
OBDEPRECATED_METHOD(-documentPickerView:didSelectProxy:);

@implementation OUIDocumentPickerScrollView
{
    BOOL _landscape;
    CGSize _gridSize;
    
    NSMutableSet *_items;
    NSArray *_sortedItems;
    id _draggingDestinationItem;
    
    struct {
        unsigned int isRotating:1;
        unsigned int isEditing:1;
    } _flags;
    
    OUIDocumentPickerItemSort _itemSort;

    NSArray *_itemViewsForPreviousOrientation;
    NSArray *_fileItemViews;
    NSArray *_groupItemViews;
}

static id _commonInit(OUIDocumentPickerScrollView *self)
{
    self.showsVerticalScrollIndicator = YES;
    self.showsHorizontalScrollIndicator = NO;
    
    self.alwaysBounceVertical = YES;
    
    return self;
}

static CGPoint _contentOffsetForCenteringItem(OUIDocumentPickerScrollView *self, OUIDocumentStoreItem *item)
{
    OBPRECONDITION(item);
    
    CGRect itemFrame = item.frame;
    return CGPointMake(0, floor(CGRectGetMidY(itemFrame) - self.bounds.size.height / 2));
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
    [_sortedItems release];
    [_items release];
    [_itemViewsForPreviousOrientation release];
    [_fileItemViews release];
    [_groupItemViews release];
    [_draggingDestinationItem release];
    
    [super dealloc];
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

static NSUInteger _itemViewsForGridSize(CGSize gridSize)
{
    NSUInteger width = ceil(gridSize.width);
    NSUInteger height = ceil(gridSize.height);
    
    return width * (height + 2); // nearby partial row above and below
}

static NSArray *_newItemViews(OUIDocumentPickerScrollView *self, Class itemViewClass)
{
    OBASSERT(OBClassIsSubclassOfClass(itemViewClass, [OUIDocumentPickerItemView class]));
    OBASSERT(itemViewClass != [OUIDocumentPickerItemView class]);
    
    NSMutableArray *itemViews = [[NSMutableArray alloc] init];

    NSUInteger neededItemViewCount = _itemViewsForGridSize(self->_gridSize);
    while (neededItemViewCount--) {
        OUIDocumentPickerItemView *itemView = [[itemViewClass alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        itemView.landscape = self->_landscape;
        
        [itemViews addObject:itemView];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_itemViewTapped:)];
        [itemView addGestureRecognizer:tap];
        [tap release];
        
        itemView.hidden = YES;
        [self addSubview:itemView];
        [itemView release];
    }
    
    NSArray *result = [itemViews copy];
    [itemViews release];
    return result;
}

@synthesize gridSize = _gridSize;
- (void)setLandscape:(BOOL)landscape gridSize:(CGSize)gridSize;
{
    if (_fileItemViews && _groupItemViews && _landscape == landscape && CGSizeEqualToSize(_gridSize, gridSize))
        return;
    
    _gridSize = gridSize;
    _landscape = landscape;
    
    // We should be new, or -willRotate should have been called. Still, we'll try to handle this reasonably below.
    OBASSERT(_fileItemViews == nil);
    OBASSERT(_groupItemViews == nil);
    
    [_fileItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [_fileItemViews release];
    _fileItemViews = _newItemViews(self, [OUIDocumentPickerFileItemView class]);
    
    [_groupItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [_groupItemViews release];
    _groupItemViews = _newItemViews(self, [OUIDocumentPickerGroupItemView class]);
    
    [self setNeedsLayout];
}

@synthesize items = _items;

- (NSArray *)_sortDescriptors;
{
    NSMutableArray *descriptors = [NSMutableArray array];
    
    if (_itemSort == OUIDocumentPickerItemSortByDate) {
        NSSortDescriptor *dateSort = [[NSSortDescriptor alloc] initWithKey:OUIDocumentStoreItemDateBinding ascending:NO];
        [descriptors addObject:dateSort];
        [dateSort release];
        
        // fall back to name sorting if the dates are equal
    }
    
    NSSortDescriptor *nameSort = [[NSSortDescriptor alloc] initWithKey:OUIDocumentStoreItemNameBinding ascending:YES selector:@selector(localizedStandardCompare:)];
    [descriptors addObject:nameSort];
    [nameSort release];
    
    return descriptors;
}

- (void)sortItems;
{
    OBASSERT(_items);
    if (!_items)
        return;
    
    NSArray *newSort = [[_items allObjects] sortedArrayUsingDescriptors:[self _sortDescriptors]];
    [_sortedItems release];
    _sortedItems = [newSort copy];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    _flags.isEditing = editing;
    
    for (OUIDocumentPickerItemView *itemView in _fileItemViews)
        [itemView setEditing:editing animated:animated];
    for (OUIDocumentPickerItemView *itemView in _groupItemViews)
        [itemView setEditing:editing animated:animated];
}

- (void)setItems:(NSSet *)items;
{
    [_items release];
    _items = [[NSMutableSet alloc] initWithSet:items];
    
    [self sortItems];
    
    [self setNeedsLayout];
}

- (void)setItemSort:(OUIDocumentPickerItemSort)_sort;
{
    _itemSort = _sort;
    
    if (_items != nil) {
        [self sortItems];
        [self setNeedsLayout];
    }
}

@synthesize sortedItems = _sortedItems;
@synthesize itemSort = _itemSort;

@synthesize draggingDestinationItem = _draggingDestinationItem;
- (void)setDraggingDestinationItem:(id)draggingDestinationItem;
{
    if (_draggingDestinationItem == draggingDestinationItem)
        return;
    [_draggingDestinationItem release];
    _draggingDestinationItem = [draggingDestinationItem retain];
    
    [self setNeedsLayout];
}

- (void)scrollItemToVisible:(OUIDocumentStoreItem *)item animated:(BOOL)animated;
{
    if (!item)
        return;
    
    [self layoutIfNeeded];

    CGRect itemFrame = item.frame;
    if (CGRectContainsRect(self.bounds, itemFrame))
        return;

    // TODO: We may now want a rect that does the minimal scrolling to get this item on screen.
    [self setContentOffset:_contentOffsetForCenteringItem(self, item) animated:animated];
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (OUIDocumentPickerItemView *)itemViewForItem:(OUIDocumentStoreItem *)item;
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

- (OUIDocumentPickerFileItemView *)fileItemViewForFileItem:(OUIDocumentStoreFileItem *)fileItem;
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

- (void)previewsUpdatedForFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if (fileItemView.item == fileItem) {
            [fileItemView previewsUpdated];
            return;
        }
    }
    
    for (OUIDocumentPickerGroupItemView *groupItemView in _groupItemViews) {
        OUIDocumentStoreGroupItem *groupItem = (OUIDocumentStoreGroupItem *)groupItemView.item;
        if ([groupItem.fileItems member:fileItem]) {
            [groupItemView previewsUpdated];
            return;
        }
    }
}

// Called by OUIDocumentPicker when the interface orientation changes.
- (void)willRotate;
{
    OBPRECONDITION(_flags.isRotating == NO);

    // This will cause us to discard speculatively loaded previews (and not rebuild them).
    _flags.isRotating = YES;
    [self layoutIfNeeded];

    // Fade out old item views, preparing for a whole new array in the -setGridSize:
    OBASSERT(_itemViewsForPreviousOrientation == nil);
    OBASSERT(_fileItemViews != nil);
    OBASSERT(_groupItemViews != nil);
    [_itemViewsForPreviousOrientation release];
    _itemViewsForPreviousOrientation = [[_fileItemViews arrayByAddingObjectsFromArray:_groupItemViews] retain];
    
    [_fileItemViews release];
    _fileItemViews = nil;
    [_groupItemViews release];
    _groupItemViews = nil;
    
    // Elevate the old previews above the new ones that will be made
    for (OUIDocumentPickerItemView *itemView in _itemViewsForPreviousOrientation) {
        itemView.gestureRecognizers = nil;
        itemView.layer.zPosition = 1;
    }

    // ... and fade them out, exposing the new ones
    [UIView beginAnimations:nil context:NULL];
    {
        for (OUIDocumentPickerItemView *itemView in _itemViewsForPreviousOrientation) {
            itemView.alpha = 0;
        }
    }
    [UIView commitAnimations];
}

- (void)didRotate;
{
    OBPRECONDITION(_flags.isRotating == YES);

    // Allow speculative preview loading.  Don't care if we lay out immediately.
    _flags.isRotating = NO;
    [self setNeedsLayout];
    
    // Ditch the old fully faded previews 
    OUIWithoutAnimating(^{
        for (OUIDocumentPickerItemView *view in _itemViewsForPreviousOrientation)
            [view removeFromSuperview];
        [_itemViewsForPreviousOrientation release];
        _itemViewsForPreviousOrientation = nil;
    });
}

- (void)prepareToDeleteFileItems:(NSSet *)fileItems;
{
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if ([fileItems member:fileItemView.item]) {
            OBFinishPortingLater("Shrink too/instead");
            fileItemView.alpha = 0;
        }
    }
}

- (void)finishedDeletingFileItems:(NSSet *)fileItems;
{
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if ([fileItems member:fileItemView.item]) {
            OBFinishPortingLater("Shrink too/instead");
            fileItemView.alpha = 1;
        }
    }
}

#pragma mark -
#pragma mark UIView

- (void)layoutSubviews;
{
    // Must be set by OUIDocumentPicker (according to the current device orientation) before we are laid out the first time.
    OBPRECONDITION(_gridSize.width >= 1);
    OBPRECONDITION(_gridSize.width == trunc(_gridSize.width));
    OBPRECONDITION(_gridSize.height >= 1);
    
    [super layoutSubviews];
    
    NSUInteger itemsPerRow = _gridSize.width;

    // Calculate the item size we'll use. The results of this can be non-integral, allowing for accumulated round-off
    const CGFloat kItemVerticalPadding = 27;
    const CGFloat kItemHorizontalPadding = 28;
    const UIEdgeInsets kEdgeInsets = UIEdgeInsetsMake(35/*top*/, 35/*left*/, 35/*bottom*/, 35/*right*/);
    
    // Don't compute the item size based off our bounds. If the keyboard comes up we don't want our items to get smaller!
    OUIMainViewController *mainViewController = [[OUISingleDocumentAppController controller] mainViewController];
    OUIMainViewControllerBackgroundView *layoutReferenceView = (OUIMainViewControllerBackgroundView *)mainViewController.view;
    CGRect layoutReferenceRect = [layoutReferenceView contentViewFullScreenBounds]; // Excludes the toolbar, but doesn't exclude the keyboard
    
    CGRect layoutRect = [self convertRect:layoutReferenceRect fromView:layoutReferenceView];
    CGSize layoutSize = CGSizeMake(layoutRect.size.width - kEdgeInsets.left - kEdgeInsets.right, layoutRect.size.height - kEdgeInsets.top); // Don't subtract kEdgeInsets.bottom since the previews scroll off the bottom of the screen
    CGSize itemSize;
    {
        itemSize.width = (layoutSize.width - (itemsPerRow - 1) * kItemHorizontalPadding) / _gridSize.width;
        itemSize.height = (layoutSize.height - (floor(_gridSize.height) * kItemVerticalPadding)) / _gridSize.height;
    }
    
    DEBUG_LAYOUT(@"%@ Laying out %ld items with size %@", [self shortDescription], [_items count], NSStringFromCGSize(itemSize));
    
    if (itemSize.width <= 0 || itemSize.height <= 0) {
        // We aren't sized right yet
        return;
    }

    const CGRect bounds = self.bounds;
    CGRect contentRect;
    contentRect.origin = self.contentOffset;
    contentRect.size = bounds.size;
    DEBUG_LAYOUT(@"contentRect = %@", NSStringFromCGRect(contentRect));

    // Keep track of which item views are in use by visible items
    NSMutableArray *unusedFileItemViews = [[NSMutableArray alloc] initWithArray:_fileItemViews];
    NSMutableArray *unusedGroupItemViews = [[NSMutableArray alloc] initWithArray:_groupItemViews];
    
    // Keep track of items that don't have views that need them.
    NSMutableArray *visibleItemsWithoutView = nil;
    NSMutableArray *nearlyVisibleItemsWithoutView = nil;
    
    NSUInteger row = 0, column = 0;
    
    CGRect firstItemFrame = CGRectZero, lastItemFrame = CGRectZero;
    
    for (OUIDocumentStoreItem *item in _sortedItems) {
        // Calculate the frame we would use for each item.
        DEBUG_LAYOUT(@"item (%ld,%ld) %@", row, column, [item shortDescription]);

        CGRect frame = CGRectMake(column * (itemSize.width + kItemHorizontalPadding), row * (itemSize.height + kItemVerticalPadding), itemSize.width, itemSize.height);
        
        // CGRectIntegral can make the rect bigger when the size is integral but the position is fractional. We want the size to remain the same.
        CGRect integralFrame;
        integralFrame.origin.x = floor(frame.origin.x);
        integralFrame.origin.y = floor(frame.origin.y);
        integralFrame.size = frame.size;
        frame = CGRectIntegral(integralFrame);

        // Store the frame on the item itself. We'll propagate it to an item view later if it is assigned one. This lets us do geometry queries on items that don't have their view loaded or scrolled into view.
        item.frame = frame;

        if (row == 0 && column == 0)
            firstItemFrame = frame;
        else
            lastItemFrame = frame;
        
        // If the item is on screen, give it a view to use
        BOOL itemVisible = CGRectIntersectsRect(frame, contentRect);
        
        // Optimization: build a pointer->pointer dictionary? We don't have many views, so this O(N*M) loop is probably not too bad...
        OUIDocumentPickerItemView *itemView = [self itemViewForItem:item];
        
        DEBUG_LAYOUT(@"  assigned frame %@, visible %d", NSStringFromCGRect(frame), itemVisible);

        if (!itemVisible) {
            OFExtent contentYExtent = OFExtentFromRectYRange(contentRect);
            OFExtent frameYExtent = OFExtentFromRectYRange(frame);

            CGFloat yDistanceOffScreen;
            
            if (OFExtentMin(contentYExtent) >= OFExtentMax(frameYExtent))
                yDistanceOffScreen = OFExtentMin(contentYExtent) - OFExtentMax(frameYExtent);
            else if (OFExtentMax(contentYExtent) <= OFExtentMin(frameYExtent))
                yDistanceOffScreen = OFExtentMin(frameYExtent) - OFExtentMax(contentYExtent);
            else {
                OBASSERT_NOT_REACHED("The item should be considered visible...");
                yDistanceOffScreen = 0;
            }
                
            BOOL nearlyVisible = (yDistanceOffScreen / itemSize.height < 0.5);
            
            if (nearlyVisible && !_flags.isRotating) {
                if (itemView) {
                    // keep the view for now...
                    OBASSERT([unusedFileItemViews containsObjectIdenticalTo:itemView] ^ [unusedGroupItemViews containsObjectIdenticalTo:itemView]);
                    [unusedFileItemViews removeObjectIdenticalTo:itemView];
                    [unusedGroupItemViews removeObjectIdenticalTo:itemView];
                    DEBUG_LAYOUT(@"  kept nearly visible view");
                } else {
                    // try to give this a view if we can so it can preload its preview
                    if (!nearlyVisibleItemsWithoutView)
                        nearlyVisibleItemsWithoutView = [NSMutableArray array];
                    [nearlyVisibleItemsWithoutView addObject:item];
                    DEBUG_LAYOUT(@"  is nearly visible");
                }
            } else {
                // If we aren't close to being visible and yet have a view, give it up.
                if (itemView) {
                    itemView.hidden = YES;
                    [itemView prepareForReuse];
                    DEBUG_LAYOUT(@"View %@ no longer used by item %@", [itemView shortDescription], item.name);
                }
            }
        } else {
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
        
        if (item.layoutShouldAdvance) {
            column++;
            if (column >= itemsPerRow) {
                column = 0;
                row++;
            }
        }
    }
    
    // Now, assign views to visibile or nearly visible items that don't have them. First, union the two lists.
    if (visibleItemsWithoutView || nearlyVisibleItemsWithoutView) {
        NSMutableArray *itemsNeedingView = [NSMutableArray array];
        if (visibleItemsWithoutView) {
            [itemsNeedingView addObjectsFromArray:visibleItemsWithoutView];
            DEBUG_LAYOUT(@"%ld visible items need views", [visibleItemsWithoutView count]);
        }
        if (nearlyVisibleItemsWithoutView) {
            [itemsNeedingView addObjectsFromArray:nearlyVisibleItemsWithoutView];
            DEBUG_LAYOUT(@"%ld nearly visible items need views", [nearlyVisibleItemsWithoutView count]);
        }
        
        for (OUIDocumentStoreItem *item in itemsNeedingView) {            
            
            NSMutableArray *itemViews = nil;
            if ([item isKindOfClass:[OUIDocumentStoreFileItem class]]) {
                itemViews = unusedFileItemViews;
            } else {
                itemViews = unusedGroupItemViews;
            }
            OUIDocumentPickerItemView *itemView = [itemViews lastObject];
            OBASSERT(itemView); // we should never run out given that we make enough up front
            
            if (itemView) {
                OBASSERT(itemView.superview == self); // we keep these views as subviews, just hide them.

                // Make the view start out at the "original" position instead of flying from where ever it was last left.
                OUIBeginWithoutAnimating
                {
                    itemView.hidden = NO;
                    itemView.frame = item.frame;
                    [itemView setEditing:_flags.isEditing animated:NO];
                }
                OUIEndWithoutAnimating;
                
                itemView.item = item;
                
                [itemViews removeLastObject];
                DEBUG_LAYOUT(@"Assigned view %@ to item %@", [itemView shortDescription], item.name);
            }
        }
        
    }
    
    // Update dragging state
    for (OUIDocumentPickerFileItemView *fileItemView in _fileItemViews) {
        if (fileItemView.hidden) {
            fileItemView.draggingState = OUIDocumentPickerItemViewNoneDraggingState;
            continue;
        }
        
        OUIDocumentStoreFileItem *fileItem = (OUIDocumentStoreFileItem *)fileItemView.item;
        OBASSERT([fileItem isKindOfClass:[OUIDocumentStoreFileItem class]]);
        
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
        view.item = nil;
    }
    for (OUIDocumentPickerGroupItemView *view in unusedGroupItemViews) {
        view.hidden = YES;
        view.item = nil;
    }

    [unusedFileItemViews release];
    [unusedGroupItemViews release];
    
    self.contentSize = CGSizeMake(layoutSize.width, CGRectGetMaxY(lastItemFrame) - CGRectGetMinY(firstItemFrame));
    self.contentInset = kEdgeInsets;
}

#pragma mark -
#pragma mark Private

- (void)_itemViewTapped:(UITapGestureRecognizer *)recognizer;
{
    if ([[OUIAppController controller] activityIndicatorVisible]) {
        OBASSERT_NOT_REACHED("Should have been blocked");
        return;
    }

    UIView *hitView = [recognizer hitView];
    OUIDocumentPickerItemView *itemView = [hitView containingViewOfClass:[OUIDocumentPickerItemView class]];
    if (itemView) {
        // should be one of ours, not some other temporary animating item view        
        OBASSERT([_fileItemViews containsObjectIdenticalTo:itemView] ^ [_groupItemViews containsObjectIdenticalTo:itemView]);
        OBASSERT(itemView.hidden == NO); // shouldn't be hittable if hidden
        OBASSERT(itemView.item); // should have an item if it is on screen/not hidden
        
        if ([hitView isDescendantOfView:itemView.previewView]) {
            [self.delegate documentPickerScrollView:self itemViewTapped:itemView inArea:OUIDocumentPickerItemViewTapAreaPreview];
        } else if ([hitView isDescendantOfView:itemView]) {
            [self.delegate documentPickerScrollView:self itemViewTapped:itemView inArea:OUIDocumentPickerItemViewTapAreaLabelAndDetails];
        } else {
            OBASSERT_NOT_REACHED("Should be fully covered by the subviews...");
        }
    }
}

@end
