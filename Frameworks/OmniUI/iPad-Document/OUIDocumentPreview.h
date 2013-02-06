// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

typedef enum {
    OUIDocumentPreviewTypeRegular, // Actual image that is based on document contents
    OUIDocumentPreviewTypePlaceholder, // There was no preview, so this is just a placeholder and we should try to make a real preview
    OUIDocumentPreviewTypeEmpty, // There was a zero-byte preview file, possibly indicating a problem with a previous attempt to generate a preview, so we should not try to generate a new preview
} OUIDocumentPreviewType;

// Callback to add a single preview URL -> CGImageRef. Can be called multiple times from -cachePreviewImages: (once for landscape and once for portrait, typically). This will write the image as a JPEG file to the proper URL as well as remembering the CGImageRef for use.
typedef void (^OUIDocumentPreviewCacheImage)(NSURL *fileURL, NSDate *date, BOOL landscape, CGImageRef image);

/*
This class maintains an in memory and disk cache of decoded preview images for use by the document picker. Instances represent a single entry in the cache. Each entry is uniqued by the document's fileURL and modification date.
*/
@interface OUIDocumentPreview : OFObject

+ (void)populateCacheForFileItems:(id <NSFastEnumeration>)fileItems completionHandler:(void (^)(void))completionHandler;

+ (void)discardHiddenPreviews;
+ (void)flushPreviewImageCache;
+ (void)invalidateDocumentPreviewsWithCompletionHandler:(void (^)(void))completionHandler;

+ (void)cachePreviewImages:(void (^)(OUIDocumentPreviewCacheImage cacheImage))cachePreviews; // Call from +[OUIDocument writePreviewsForDocument:completionHandler:]

+ (void)cachePreviewImagesForFileURL:(NSURL *)targetFileURL date:(NSDate *)targetDate
            byDuplicatingFromFileURL:(NSURL *)sourceFileURL date:(NSDate *)sourceDate;

+ (void)updateCacheAfterFileURL:(NSURL *)sourceFileURL withDate:(NSDate *)sourceDate didMoveToURL:(NSURL *)targetFileURL;


// This is provides access to a concurrent background queue for preview-related operations. Some of OUIDocumentPreview uses this, but none of the OUIDocumentPreview methods should be called within an operation. This is intended for things like thread-safe pre-flighting of document state that will be needed when generating previews, but that can be loaded while we are not on the main thread.
+ (void)performAsynchronousPreviewOperation:(void (^)(void))block;
+ (void)afterAsynchronousPreviewOperation:(void (^)(void))block;

// The preview might be a cached failure, but that is OK. The next time the date changes on the file item, a new preview will be attempted.
+ (BOOL)hasPreviewForFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;

+ (void)deletePreviewsNotUsedByFileItems:(id <NSFastEnumeration>)fileItems;
+ (NSURL *)fileURLForPreviewOfFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;

+ (OUIDocumentPreview *)makePreviewForDocumentClass:(Class)documentClass fileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;

+ (CGSize)maximumPreviewSizeForLandscape:(BOOL)landscape;
+ (CGFloat)previewImageScale;

@property(nonatomic,readonly) NSURL *fileURL;
@property(nonatomic,readonly) NSDate *date;

- (void)incrementDisplayCount;
- (void)decrementDisplayCount;

@property(nonatomic,readonly) CGImageRef image;
@property(nonatomic,readonly) CGSize size; // just image.size

@property(nonatomic,assign) BOOL superseded;

@property(nonatomic,readonly,getter=isLandscape) BOOL landscape;
@property(nonatomic,readonly) OUIDocumentPreviewType type;

@end
