// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class ODSFileItem;
@class OUIDocumentPreviewGenerator;

@protocol OUIDocumentPreviewGeneratorDelegate <NSObject>

// If YES, the preview generator won't bother generating a preview for this file item since the user is editing it
- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator isFileItemCurrentlyOpen:(ODSFileItem *)fileItem;

// If YES, the preview generator will pause updating previews
- (BOOL)previewGeneratorHasOpenDocument:(OUIDocumentPreviewGenerator *)previewGenerator;

- (void)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator performDelayedOpenOfFileItem:(ODSFileItem *)fileItem;

- (ODSFileItem *)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator preferredFileItemForNextPreviewUpdate:(NSSet *)fileItems;

// if preview generation is too expensive, return no, and we'll write zero length previews and stop trying
- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator shouldGeneratePreviewForURL:(NSURL *)fileURL;

// Takes a fileURL instead of the fileItem since (hypothetically) the file type could change between two different conflict versions (rtf -> rtfd, for example).
- (Class)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator documentClassForFileURL:(NSURL *)fileURL;

@end

/*
 Helps manage the set of preview generation needs, app backgrounding and contention with opening actual documents.
 */
@interface OUIDocumentPreviewGenerator : NSObject

+ (void)disablePreviewsForAnimation;
+ (void)enablePreviewsForAnimation;

@property(nonatomic,weak) id <OUIDocumentPreviewGeneratorDelegate> delegate;

- (void)enqueuePreviewUpdateForFileItemsMissingPreviews:(id <NSFastEnumeration>)fileItems;
- (void)applicationDidEnterBackground;

@property(nonatomic,readonly) ODSFileItem *fileItemToOpenAfterCurrentPreviewUpdateFinishes;
- (BOOL)shouldOpenDocumentWithFileItem:(ODSFileItem *)fileItem; // sets -fileItemToOpenAfterCurrentPreviewUpdateFinishes and returns NO if a preview is being generate

- (void)fileItemNeedsPreviewUpdate:(ODSFileItem *)fileItem;
- (void)documentClosed;

@end
