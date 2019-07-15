// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerItemView.h>

@class OUIDocumentPreview, OUIDocumentPreviewView, OUIDocumentPreviewLoadOperation;

@interface OUIDocumentPickerItemView (/*Internal*/)

- (void)startObservingItem:(id)item;
- (void)stopObservingItem:(id)item;

- (void)itemChanged;

@property(nonatomic,readonly) NSArray *previewedItems; // Subclasses need to implemenent to return the items for which they need previews
- (void)previewedItemsChanged; // ... and call this when that answer changes

- (void)loadPreviews;
- (void)discardCurrentPreviews;
- (void)previewsUpdated;
- (NSArray *)loadedPreviews;

@property(nonatomic,assign) BOOL shrunken; // Only for files

@end

