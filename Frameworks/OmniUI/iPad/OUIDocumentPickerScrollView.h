// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

extern NSString * const OUIDocumentPickerScrollViewItemsBinding;

@class OFPreference;
@class OUIDocumentStoreItem, OUIDocumentStoreFileItem, OUIDocumentPickerItemView, OUIDocumentPickerFileItemView, OUIDocumentPickerScrollView;

typedef enum {
    OUIDocumentPickerItemSortByDate,
    OUIDocumentPickerItemSortByName,
} OUIDocumentPickerItemSort;

typedef enum {
    OUIDocumentPickerItemViewTapAreaPreview,
    OUIDocumentPickerItemViewTapAreaLabelAndDetails,
} OUIDocumentPickerItemViewTapArea;

@protocol OUIDocumentPickerScrollViewDelegate <UIScrollViewDelegate>
- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView inArea:(OUIDocumentPickerItemViewTapArea)area;
@end

@interface OUIDocumentPickerScrollView : UIScrollView

@property(nonatomic,assign) id <OUIDocumentPickerScrollViewDelegate> delegate;

// The size of the document prevew grid in items. That is, if gridSize.width = 4, then 4 items will be shown across the width.
// The width must be at least one and integral. The height must be at least one, but may be non-integral if you want to have a row of itemss peeking out.
- (void)setLandscape:(BOOL)landscape gridSize:(CGSize)gridSize;
@property(nonatomic,readonly) CGSize gridSize;

@property(nonatomic,retain) NSSet *items;
@property(nonatomic,readonly) NSArray *sortedItems;
@property(nonatomic,retain) id draggingDestinationItem;

- (void)scrollItemToVisible:(OUIDocumentStoreItem *)item animated:(BOOL)animated;
- (void)sortItems;

- (OUIDocumentPickerItemView *)itemViewForItem:(OUIDocumentStoreItem *)item;
- (OUIDocumentPickerFileItemView *)fileItemViewForFileItem:(OUIDocumentStoreFileItem *)fileItem;
- (OUIDocumentPickerItemView *)itemViewHitInPreviewAreaByRecognizer:(UIGestureRecognizer *)recognizer;
- (OUIDocumentPickerFileItemView *)fileItemViewHitInPreviewAreaByRecognizer:(UIGestureRecognizer *)recognizer;

- (void)previewsUpdatedForFileItem:(OUIDocumentStoreFileItem *)fileItem;

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;

- (void)willRotate;
- (void)didRotate;

@property(nonatomic) OUIDocumentPickerItemSort itemSort;

- (void)prepareToDeleteFileItems:(NSSet *)fileItems;
- (void)finishedDeletingFileItems:(NSSet *)fileItems;

@end
