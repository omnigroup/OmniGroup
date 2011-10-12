// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

extern NSString * const OUIDocumentPickerItemViewPreviewsDidLoadNotification;

@class OUIDocumentStoreItem;

typedef enum {
    OUIDocumentPickerItemViewNoneDraggingState,
    OUIDocumentPickerItemViewSourceDraggingState,
    OUIDocumentPickerItemViewDestinationDraggingState,
} OUIDocumentPickerItemViewDraggingState;

/*
 A semi-concrete class that represents one of the scrollable items in the document picker, either a single file or a group of files.
 */
@interface OUIDocumentPickerItemView : UIView

@property(assign,nonatomic) BOOL landscape;
@property(retain,nonatomic) OUIDocumentStoreItem *item; // either a file or group

@property(readonly,nonatomic,getter=isLoadingPreviews) BOOL loadingPreviews;

@property(assign,nonatomic) OUIDocumentPickerItemViewDraggingState draggingState;

@property(assign,nonatomic,getter=isRenaming) BOOL renaming;

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;

- (void)prepareForReuse;

@end
