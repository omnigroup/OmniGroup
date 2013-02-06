// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OUIDocumentPreview, OUIDocumentPreviewView, OUIDocumentPreviewLoadOperation, OUIDocumentPickerItemNameAndDateView;

@interface OUIDocumentPickerItemView (/*Internal*/)

@property(readonly,nonatomic) OUIDocumentPreviewView *previewView;
@property(readonly,nonatomic) OUIDocumentPickerItemNameAndDateView *nameAndDateView;

- (void)startObservingItem:(id)item;
- (void)stopObservingItem:(id)item;

- (void)itemChanged;

@property(nonatomic,readonly) NSSet *previewedFileItems; // Subclasses need to implemenent to return the file items for which they need previews
- (void)previewedFileItemsChanged; // ... and call this when that answer changes

- (void)loadPreviews;
- (void)discardCurrentPreviews;
- (void)previewsUpdated;
- (NSArray *)loadedPreviews;

- (OUIDocumentPreview *)currentPreview;

@property(nonatomic,assign) BOOL highlighted;

@property(nonatomic,assign) BOOL shrunken; // Only for files

@end

