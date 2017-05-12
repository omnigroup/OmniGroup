// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniAppKit/OAAppearance.h> // OUIDocumentPreviewArea
#import <OmniUI/OUIDocumentPreviewArea.h>

@class ODSFileItem, OFFileEdit, ODSFileItemEdit;

typedef NS_ENUM(NSUInteger, OUIDocumentPreviewType) {
    OUIDocumentPreviewTypeRegular, // Actual image that is based on document contents
    OUIDocumentPreviewTypePlaceholder, // There was no preview, so this is just a placeholder and we should try to make a real preview
    OUIDocumentPreviewTypeEmpty, // There was a zero-byte preview file, possibly indicating a problem with a previous attempt to generate a preview, so we should not try to generate a new preview
};

// Callback to add a single preview URL -> CGImageRef. This will scale down the image to the small and large sizes and will then write them as JPEG files to the proper URL.
typedef void (^OUIDocumentPreviewCacheImage)(OFFileEdit *fileEdit, CGImageRef image);

/*
This class maintains an in memory and disk cache of decoded preview images for use by the document picker. Instances represent a single entry in the cache. Each entry is uniqued by a file item's unique edit identifier (which each scope subclass must fill out).
*/
@interface OUIDocumentPreview : NSObject

+ (void)populateCacheForFileItems:(id <NSFastEnumeration>)fileItems completionHandler:(void (^)(void))completionHandler;

+ (void)discardHiddenPreviews;
+ (void)flushPreviewImageCache;
+ (void)invalidateDocumentPreviewsWithCompletionHandler:(void (^)(void))completionHandler;

// Call from +[OUIDocument writePreviewsForDocument:completionHandler:]. The fileEdit passed into cacheImage must be for the *new* state of the document or else the preview will be stored under the wrong filename.
+ (void)cachePreviewImages:(void (^)(OUIDocumentPreviewCacheImage cacheImage))cachePreviews;

// Temporary URL-only aliases for in-flight moves/copies.
+ (void)addAliasFromFileItemEdit:(ODSFileItemEdit *)fromFileItemEdit toFileWithURL:(NSURL *)toFileURL;
+ (void)removeAliasFromFileItemEdit:(ODSFileItemEdit *)fromFileItemEdit toFileWithURL:(NSURL *)toFileURL;

+ (void)cachePreviewImagesForFileEdit:(OFFileEdit *)targetFileEdit
            byDuplicatingFromFileEdit:(OFFileEdit *)sourceFileEdit;

// A background queue for preparing for preview generation. None of the OUIDocumentPreview methods should be called within an operation. This is intended for things like thread-safe pre-flighting of document state that will be needed when generating previews, but that can be loaded while we are not on the main thread.
+ (void)performAsynchronousPreviewPreparation:(void (^)(void))block;

// Waits for pending preview file I/O and other operations like cache population and flushing.
+ (void)afterAsynchronousPreviewOperation:(void (^)(void))block;

// The previews might be cached failures, but that is OK. The next time the date changes on the file item, a new preview will be attempted.
+ (BOOL)hasPreviewsForFileEdit:(OFFileEdit *)fileEdit;

+ (void)deletePreviewsNotUsedByFileItems:(id <NSFastEnumeration>)fileItems;
+ (NSURL *)fileURLForPreviewOfFileEdit:(OFFileEdit *)fileEdit withArea:(OUIDocumentPreviewArea)area;
+ (void)writeEmptyPreviewsForFileEdit:(OFFileEdit *)fileEdit;
+ (void)writeEncryptedEmptyPreviewsForFileEdit:(OFFileEdit *)fileEdit fileURL:(NSURL *)fileURL;

+ (OUIDocumentPreview *)makePreviewForDocumentClass:(Class)documentClass fileItem:(ODSFileItem *)fileItem withArea:(OUIDocumentPreviewArea)area;

+ (CGFloat)previewSizeForArea:(OUIDocumentPreviewArea)area;
+ (CGFloat)previewImageScale;

@property(nonatomic,readonly) OFFileEdit *fileEdit;
@property(nonatomic,readonly) NSString *fileEditIdentifier;
@property(nonatomic,readonly) NSURL *fileURL;
@property(nonatomic,readonly) NSDate *date;

- (void)incrementDisplayCount;
- (void)decrementDisplayCount;

@property(nonatomic,readonly) CGImageRef image;
@property(nonatomic,readonly) CGSize size; // just image.size

@property(nonatomic,assign) BOOL superseded;

@property(nonatomic,readonly) OUIDocumentPreviewArea area;
@property(nonatomic,readonly) OUIDocumentPreviewType type;

@end
