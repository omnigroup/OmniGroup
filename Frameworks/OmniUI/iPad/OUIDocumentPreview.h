// Copyright 2010-2011 The Omni Group.  All rights reserved.
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

// Callback to add a single preview URL -> CGImageRef. Can be called multiple times from -cachePreviewImages: (once for landscape and once for portrait, typically).
typedef void (^OUIDocumentPreviewCacheImage)(CGImageRef image, NSURL *previewURL);

/*
This class maintains an in memory and disk cache of decoded preview images for use by the document picker. Instances represent a single entry in the cache. Each entry is uniqued by the document's fileURL and modification date.
*/
@interface OUIDocumentPreview : OFObject

+ (void)updatePreviewImageCacheWithCompletionHandler:(void (^)(void))completionHandler;
+ (void)flushPreviewImageCache;
+ (void)cachePreviewImages:(void (^)(OUIDocumentPreviewCacheImage cacheImage))cachePreviews; // Call from +[OUIDocument writePreviewsForDocument:error:]

+ (void)cachePreviewImagesForFileURL:(NSURL *)targetFileURL date:(NSDate *)targetDate
            byDuplicatingFromFileURL:(NSURL *)sourceFileURL date:(NSDate *)sourceDate;

// The preview might be a cached failure, but that is OK. The next time the date changes on the file item, a new preview will be attempted.
+ (BOOL)hasPreviewForFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;

+ (void)deletePreviewsNotUsedByFileItems:(id <NSFastEnumeration>)fileItems;
+ (NSURL *)fileURLForPreviewOfFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;

+ (OUIDocumentPreview *)makePreviewForDocumentClass:(Class)documentClass fileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;

+ (CGSize)maximumPreviewSizeForLandscape:(BOOL)landscape;
+ (CGFloat)previewImageScale;

@property(nonatomic,readonly) NSURL *fileURL;
@property(nonatomic,readonly) NSDate *date;
@property(nonatomic,readonly) CGImageRef image;
@property(nonatomic,readonly) CGSize size; // just image.size

@property(nonatomic,assign) BOOL superseded;

@property(nonatomic,readonly,getter=isLandscape) BOOL landscape;
@property(nonatomic,readonly) OUIDocumentPreviewType type;

- (void)drawInRect:(CGRect)rect;

@end
