// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>
#import <OmniUI/OUIAppearance.h>

extern NSString * const OUIDocumentPickerItemViewPreviewsDidLoadNotification;

@class UITapGestureRecognizer;
@class ODSItem;
@class OUIDocumentPreviewView, OUIDocumentPickerItemMetadataView;

typedef enum {
    OUIDocumentPickerItemViewNoneDraggingState,
    OUIDocumentPickerItemViewSourceDraggingState,
    OUIDocumentPickerItemViewDestinationDraggingState,
} OUIDocumentPickerItemViewDraggingState;

/*
 A semi-concrete class that represents one of the scrollable items in the document picker, either a single file or a group of files.
 */
@interface OUIDocumentPickerItemView : UIControl

@property(retain,nonatomic) ODSItem *item; // either a file or group

@property(readonly) UIView *contentView; // Subclasses should add OUIDocumentPreviewView instances as subviews. Previews are assigned by tag; the lowest tag gets the first preview, etc. They can do this in -layoutSubviews, or in -init.

@property(readonly,nonatomic) OUIDocumentPickerItemMetadataView *metadataView;
@property(nonatomic,readonly) OUIDocumentPreviewArea previewArea;
@property(assign,nonatomic) OUIDocumentPickerItemViewDraggingState draggingState;

@property(nonatomic,retain) UIImage *statusImage;
@property(nonatomic,assign) BOOL showsProgress;
@property(nonatomic,assign) double progress;
@property(nonatomic,assign) BOOL isReadOnly;
@property(nonatomic,assign) BOOL isSmallSize;

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;

- (void)prepareForReuse;

- (void)startRenaming;

- (void)bounceDown;

@end
