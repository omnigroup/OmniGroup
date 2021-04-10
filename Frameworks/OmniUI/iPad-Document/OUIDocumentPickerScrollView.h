// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

#import <OmniUIDocument/OUIDocumentPickerItemSort.h>
#import <OmniBase/OBUtilities.h>

extern NSString * const OUIDocumentPickerScrollViewItemsBinding;

@class OFPreference;
@class ODSItem, ODSFileItem;
@class OUIDocumentPickerItemView, OUIDocumentPickerFileItemView, OUIDocumentPickerScrollView;

@protocol OUIDocumentPickerScrollViewDelegate <UIScrollViewDelegate>
- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView OB_DEPRECATED_ATTRIBUTE;
- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewLongpressed:(OUIDocumentPickerItemView *)itemView OB_DEPRECATED_ATTRIBUTE;
- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView willDisplayItemView:(OUIDocumentPickerItemView *)itemView OB_DEPRECATED_ATTRIBUTE;
- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView willEndDisplayingItemView:(OUIDocumentPickerItemView *)itemView OB_DEPRECATED_ATTRIBUTE;

- (NSArray *)sortDescriptorsForDocumentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView OB_DEPRECATED_ATTRIBUTE;
- (BOOL)isReadyOnlyForDocumentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView OB_DEPRECATED_ATTRIBUTE;

- (BOOL)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView rectIsFullyVisible:(CGRect)rect OB_DEPRECATED_ATTRIBUTE;

@optional
- (BOOL)documentPickerScrollViewShouldMultiselect:(OUIDocumentPickerScrollView *)scrollView OB_DEPRECATED_ATTRIBUTE;

@end

@interface OUIDocumentPickerScrollView : UIScrollView <UIGestureRecognizerDelegate>

@property(nonatomic,assign) id <OUIDocumentPickerScrollViewDelegate> delegate;

@property(nonatomic,assign) BOOL shouldHideTopControlsOnNextLayout;
@property(nonatomic,readonly) BOOL isShowingTitleLabel;

- (CGFloat)contentOffsetYToHideTopControls;
- (CGFloat)contentOffsetYToHideCompactTitleBehindNavBar;
- (CGFloat)contentOffsetYForTopControlsFullAlpha;
- (CGFloat)contentOffsetYToShowTopControls;

- (void)retileItems;

@property(nonatomic,retain) UILabel *titleViewForCompactWidth;
@property(nonatomic,retain) UIView *topControls;

@property(nonatomic,readonly) NSSet *items;

- (void)startAddingItems:(NSSet *)toAdd;
- (void)finishAddingItems:(NSSet *)toAdd;
@property(nonatomic,readonly) NSSet *itemsBeingAdded;

- (void)startRemovingItems:(NSSet *)toRemove;
- (void)finishRemovingItems:(NSSet *)toRemove;
@property(nonatomic,readonly) NSSet *itemsBeingRemoved;

@property(nonatomic,readonly) NSArray *sortedItems;
@property(nonatomic,retain) id draggingDestinationItem;

- (void)scrollItemToVisible:(ODSItem *)item animated:(BOOL)animated;
- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated;
- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated completion:(void (^)(void))completion;

@property(nonatomic,readonly) BOOL hasScrollFinishedHandlers;
- (void)performScrollFinishedHandlers; // Called by the delegate when scrolling is done

- (void)sortItems;

- (CGRect)frameForItem:(ODSItem *)item;

/// - point: Expected to be in OUIDocumentPickerScrollView's coordinates.
- (OUIDocumentPickerItemView *)itemViewForPoint:(CGPoint)point;
- (OUIDocumentPickerItemView *)itemViewForItem:(ODSItem *)item;
- (OUIDocumentPickerFileItemView *)fileItemViewForFileItem:(ODSFileItem *)fileItem;
- (OUIDocumentPickerItemView *)itemViewHitByRecognizer:(UIGestureRecognizer *)recognizer;

- (void)previewsUpdatedForFileItem:(ODSFileItem *)fileItem;
- (void)previewedItemsChangedForGroups;

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;

@property(nonatomic) OUIDocumentPickerItemSort itemSort;

- (void)startIgnoringItemForLayout:(ODSItem *)item;
- (void)stopIgnoringItemForLayout:(ODSItem *)item;

@end
