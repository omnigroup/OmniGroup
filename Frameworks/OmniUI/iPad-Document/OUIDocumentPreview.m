// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPreview.h>

#import <ImageIO/CGImageSource.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSLocalDirectoryScope.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIImages.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

RCS_ID("$Id$");

static OFDeclareDebugLogLevel(OUIDocumentPreviewDebug)
#define DEBUG_PREVIEW(level, format, ...) do { \
    if (OUIDocumentPreviewDebug >= (level)) \
        NSLog(@"PREVIEW: " format, ## __VA_ARGS__); \
    } while (0)

@interface OUIDocumentPreview ()
@property(nonatomic,readwrite) CGImageRef image; // Always set if we are loaded (set to a placeholder if there is no real preview)
@property(nonatomic,readonly) BOOL exists;
@property(nonatomic,readonly) BOOL empty;
@end

static NSString *AreaNames[] = {
    [OUIDocumentPreviewAreaLarge] = @"large",
    [OUIDocumentPreviewAreaMedium] = @"medium",
    [OUIDocumentPreviewAreaSmall] = @"small",
};
static NSString *AreaCacheSuffix[] = {
    [OUIDocumentPreviewAreaLarge] = @"L",
    [OUIDocumentPreviewAreaMedium] = @"M",
    [OUIDocumentPreviewAreaSmall] = @"S",
};

@implementation OUIDocumentPreview
{
    NSURL *_previewURL;
    NSUInteger _displayCount;
    NSOperation *_loadOperation;
}

static dispatch_queue_t PreviewCacheOperationQueue; // Serial background queue for general operations; GCD so we can use async/sync/barrier
static NSOperationQueue *PreviewPreparationQueue; // Serial queue for pre-flighting operations for generating previews
static NSOperationQueue *PreviewCacheReadWriteQueue; // Concurrent background queue for loading/saving/decoding preview images

#ifdef OMNI_ASSERTIONS_ON
// dispatch_get_current_queue() is deprecated, but we only use it in debug builds.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static BOOL IsOnQueue(dispatch_queue_t queue) {
    return (dispatch_get_current_queue() == queue);
}
#pragma clang diagnostic pop
#endif

// A cache of preview file name -> OUIDocumentPreview instances and temporary aliases for in-flight moves/copies. Only usable inside PreviewCacheOperationQueue.
static NSMutableDictionary *PreviewFileNameToPreview;
static NSMutableDictionary *PreviewDestinationPathToSourcePreview;

// A cache of placeholder images badged onto white rectangles for use when we are still generating a preview. Should only be touched on the associated queue.
static NSOperationQueue *PreviewPlaceholderOperationQueue;
static CFMutableDictionaryRef BadgedPlaceholderPreviewImageCache;

static NSTimer *DiscardHiddenPreviewsTimer;

static const CFDictionaryValueCallBacks CFTypeDictionaryValueCallbacks = {
    .retain = OFCFTypeRetain,
    .release = OFCFTypeRelease,
    .copyDescription = OFCFTypeCopyDescription,
    .equal = OFCFTypeIsEqual
};

+ (void)initialize;
{
    OBINITIALIZE;
    
    /*
     Use a concurrent queue for operations to run in parallel and a serial queue to allow barriers. This requires that any operations on the concurrent queue be dependencies of some completion operation on the serial queue.
     */
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PreviewCacheOperationQueue = dispatch_queue_create("com.omnigroup.OmniUI.OUIDocumentPreview.operations", DISPATCH_QUEUE_SERIAL);
        
        PreviewPreparationQueue = [[NSOperationQueue alloc] init];
        PreviewPreparationQueue.name = @"com.omnigroup.OmniUI.OUIDocumentPreview.preparation";

        PreviewCacheReadWriteQueue = [[NSOperationQueue alloc] init];
        PreviewCacheReadWriteQueue.name = @"com.omnigroup.OmniUI.OUIDocumentPreview.readwrite";
        
        PreviewPlaceholderOperationQueue = [[NSOperationQueue alloc] init];
        PreviewPlaceholderOperationQueue.name = @"com.omnigroup.OmniUI.OUIDocumentPreview.placeholders";
        PreviewPlaceholderOperationQueue.maxConcurrentOperationCount = 1;
    });
}

static NSURL *_normalizeURL(NSURL *url)
{
    // Sadly, this doesn't work if the URL doesn't exist. We could look for an ancestor directory that exists, normalize that, and then tack on the suffix again.
//    OBPRECONDITION([url isFileURL]);
//    OBPRECONDITION([[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:NULL]);
    
    // Need consistent mapping of /private/var/mobile vs /var/mobile.
    return [[url URLByResolvingSymlinksInPath] URLByStandardizingPath];
}

static NSURL *_previewURLWithFilename(NSString *filename)
{
    NSURL *previewURL = [[[OUIDocumentPreview _previewDirectoryURL] URLByAppendingPathComponent:filename isDirectory:NO] absoluteURL];
    DEBUG_PREVIEW(2, @"filename %@ -> previewURL %@", filename, previewURL);
    
    // The normalization is too slow to do here, but we shouldn't need to since +_previewDirectoryURL returns a normalized base URL and nothing we append should mess it up.
    OBPOSTCONDITION([previewURL isEqual:_normalizeURL(previewURL)]);
    
    return previewURL;
}

static CGImageRef _loadImageFromURL(NSURL *imageURL) CF_RETURNS_RETAINED;
static CGImageRef _loadImageFromURL(NSURL *imageURL)
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             (id)kUTTypeJPEG, (id)kCGImageSourceTypeIdentifierHint,
                             nil];

    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)imageURL, (__bridge CFDictionaryRef)options);
    if (!imageSource) {
        NSLog(@"Error loading preview image from %@: Unable to create image source", imageURL);
        return NULL;
    }
    
    if (CGImageSourceGetCount(imageSource) < 1) {
        NSLog(@"Error loading preview image from %@: No images found in source", imageURL);
        CFRelease(imageSource);
        return NULL;
    }
    
    CGImageRef image = CGImageSourceCreateImageAtIndex(imageSource, 0/*index*/, (CFDictionaryRef)NULL/*options*/);
    CFRelease(imageSource);
    
    if (!image) {
        NSLog(@"Error loading preview image from %@: Unable to create image from source", imageURL);
        return NULL;
    }
    
    // Force decoding of the JPEG data up front so that scrolling in the document picker doesn't chug the first time an image comes on screen
    CGImageRef flattenedImage = OQCopyFlattenedImage(image);
    if (flattenedImage) {
        CFRelease(image);
        image = flattenedImage;
    }

    return image;
}

static void _populatePreview(Class self, NSSet *existingPreviewFileNames, OFFileEdit *fileEdit, OUIDocumentPreviewArea area)
{
    OBPRECONDITION(fileEdit);
    
    NSString *previewFilename = [self _filenameForPreviewOfFileWithEditIdentifier:fileEdit.uniqueEditIdentifier withArea:area];
    
    OUIDocumentPreview *preview = [PreviewFileNameToPreview objectForKey:previewFilename];
    if (preview)
        return;
    
    NSURL *previewURL = _previewURLWithFilename(previewFilename);
    // We hash the file names instead of full NSURLs to avoid possible issues with normalization (which we've hit) or NSURL otherwise being -hash/-isEqual: funky.
    BOOL exists = ([existingPreviewFileNames member:previewFilename] != nil);
    BOOL empty;
    if (exists) {
        __autoreleasing NSError *attributesError = nil;
        
        // Don't ask the URL via getResourceValue:forKey:error: since that can return a cached value. We might have just written the image during preview generation after previously having looked up the empty placeholder that is written prior to preview generation.
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[previewURL absoluteURL] path] error:&attributesError];
        if (!attributes) {
            NSLog(@"Error getting atrributes of preview image %@: %@", previewFilename, [attributesError toPropertyList]);
        }
        empty = ([attributes fileSize] == 0);
    } else {
        empty = YES;
    }
    
    if (!PreviewFileNameToPreview)
        PreviewFileNameToPreview = [[NSMutableDictionary alloc] init];
    
    preview = [[self alloc] _initWithFileURL:fileEdit.originalFileURL fileEdit:fileEdit area:area previewURL:previewURL exists:exists empty:empty];
    _registerPreview(preview, [previewURL lastPathComponent]);
    DEBUG_PREVIEW(1, @"Populated preview %@=%p (exists:%d, empty:%d) for %@ area:%lu", [previewURL lastPathComponent], preview, exists, empty, [fileEdit shortDescription], area);
}

+ (void)populateCacheForFileItems:(id <NSFastEnumeration>)fileItems completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    DEBUG_PREVIEW(1, @"Queuing cache population request");

    if (!fileItems)
        return;
    
    completionHandler = [completionHandler copy]; // capture scope

    DEBUG_PREVIEW(1, @"Queuing cache population operation, fileItems = %@", fileItems);

    // Capture snapshots before leaving the main thread
    NSMutableArray *fileEdits = [NSMutableArray array];
    for (ODSFileItem *fileItem in fileItems) {
        OFFileEdit *fileEdit = fileItem.fileEdit;
        if (fileEdit)
            [fileEdits addObject:fileEdit];
    }

    dispatch_async(PreviewCacheOperationQueue, ^{
        DEBUG_PREVIEW(1, @"Performing cache population request");

        [self _populateCacheWithFileEdits:fileEdits];
                
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{            
            DEBUG_PREVIEW(1, @"Finishing cache population request");
            if (completionHandler)
                completionHandler();
        }];
    });
}

+ (void)_populateCacheWithFileEdits:(id <NSFastEnumeration>)fileEdits;
{
    OBPRECONDITION(IsOnQueue(PreviewCacheOperationQueue));
    
    // Do a bulk lookup of what preview URLs exist (we expect that this method is called few times with all the known file items)
    NSSet *existingPreviewFileNames;
    {
        __autoreleasing NSError *error = nil;
        NSURL *previewDirectoryURL = [self _previewDirectoryURL];
        NSArray *previewURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:previewDirectoryURL
                                                             includingPropertiesForKeys:[NSArray arrayWithObjects:NSURLFileSizeKey, nil]
                                                                                options:0
                                                                                  error:&error];
        if (!previewURLs) {
            NSLog(@"Error scanning preview directory %@: %@", previewDirectoryURL, [error toPropertyList]);
            return;
        }
        
        NSMutableSet *previewFileNames = [[NSMutableSet alloc] init];
        for (NSURL *previewURL in previewURLs)
            [previewFileNames addObject:[previewURL lastPathComponent]];
        existingPreviewFileNames = [previewFileNames copy];
    }
    
    for (OFFileEdit *fileEdit in fileEdits) {
        _populatePreview(self, existingPreviewFileNames, fileEdit, OUIDocumentPreviewAreaLarge);
        _populatePreview(self, existingPreviewFileNames, fileEdit, OUIDocumentPreviewAreaMedium);
        _populatePreview(self, existingPreviewFileNames, fileEdit, OUIDocumentPreviewAreaSmall);
    }
}

+ (void)discardHiddenPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // We need to call -_discardPreviewIfHidden on the main queue, but we don't want to block the main queue here. So we collect all the previews and bounce back to the main queue.
    NSMutableArray *previews = [NSMutableArray new];
    
    // This used to use dispatch_barrier_sync, but it isn't clear that it needs to be. If there is a preview running, this would block the main queue.
    dispatch_async(PreviewCacheOperationQueue, ^{
        [PreviewFileNameToPreview enumerateKeysAndObjectsUsingBlock:^(NSString *filename, OUIDocumentPreview *preview, BOOL *stop) {
            [previews addObject:preview];
        }];
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            __block NSUInteger keptPreviews = 0;
            __block NSUInteger discardedPreviews = 0;
            
            for (OUIDocumentPreview *preview in previews) {
                if ([preview _discardPreviewIfHidden]) {
                    discardedPreviews++;
                }
                if (preview->_image)
                    keptPreviews++;
            }
            DEBUG_PREVIEW(1, @"Cleaned up %ld hidden previews, kept %ld", discardedPreviews, keptPreviews);
        }];
        
    });
    
}

+ (void)flushPreviewImageCache;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_PREVIEW(1, @"Flushing preview cache");

    // Make sure image saving/loading has finished -- this doesn't dispatch back to the main queue
    [PreviewCacheReadWriteQueue waitUntilAllOperationsAreFinished];

    // Make sure any serial operations are finished
    dispatch_barrier_sync(PreviewCacheOperationQueue, ^{
        PreviewFileNameToPreview = nil;
    });
    
    // And finally, clear the placeholders
    [PreviewPlaceholderOperationQueue addOperationWithBlock:^{
        if (BadgedPlaceholderPreviewImageCache) {
            CFRelease(BadgedPlaceholderPreviewImageCache);
            BadgedPlaceholderPreviewImageCache = nil;
        }
    }];
}

+ (void)invalidateDocumentPreviewsWithCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    NSLog(@"Removing all previews!");

    // Make sure any I/O is done
    [self afterAsynchronousPreviewOperation:^{
        NSURL *previewDirectoryURL = [self _previewDirectoryURL];
        
        __autoreleasing NSError *removeError;
        if (![[NSFileManager defaultManager] removeItemAtURL:previewDirectoryURL error:&removeError])
            NSLog(@"Unable to remove preview directory: %@", [removeError toPropertyList]);
        
        [OUIDocumentPreview flushPreviewImageCache];

        __autoreleasing NSError *createError;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:previewDirectoryURL withIntermediateDirectories:NO attributes:nil error:&createError])
            NSLog(@"Unable to create preview directory: %@", [createError toPropertyList]);
        if (completionHandler)
            completionHandler();
    }];
}

// This method lets documents synchronously update the cache with one or more just-generated preview images (rather than doing a full async rescan).
+ (void)cachePreviewImages:(void (^)(OUIDocumentPreviewCacheImage cacheImage))cachePreviews;
{
    [self _cachePreviewImages:cachePreviews andWriteImages:YES];
}

static void _registerPreview(OUIDocumentPreview *preview, NSString *previewFilename)
{
    OBPRECONDITION(IsOnQueue(PreviewCacheOperationQueue));
#ifdef OMNI_ASSERTIONS_ON
    {
        // If the incomming image is not nil, we should either have nothing in our cache, or should have some form of placeholder. We shouldn't be replacing valid previews (those should get a new date and thus a new cache key).
        OBASSERT(PreviewFileNameToPreview, "Looking up previews while the cache isn't loaded.");
        OUIDocumentPreview *existingPreview = PreviewFileNameToPreview[previewFilename];
        OBASSERT_IF(preview.exists,
                    (existingPreview == nil || // nothing in the cache
                     existingPreview.exists == NO || // cached missing value
                     existingPreview.empty || // cached empty file

                     // We Noticed a preview file that exists on disk, but haven't load it, and the new preview is loaded already.
                     // This is a race between noticing new previews and the document closing path saving them. There is no big performance issue if the preview we have hasn't been loaded.
                     // See bug:///137636 (iOS-OmniGraffle Crasher: assertion fails sometimes saving document preview on close)
                     (existingPreview.fileEdit == preview.fileEdit && existingPreview->_image == NULL && existingPreview->_loadOperation == nil && preview->_image != NULL)),
                    @"We should not have an existing preview for a file/date with an image if we are caching a new preview with an image. bug:///142473 (Frameworks-iOS Unassigned: Assertion failure caching previews: redundant preview when opening a file from iCloud Drive, closing without editing)");
    }
#endif
    PreviewFileNameToPreview[previewFilename] = preview;
}

+ (void)_registerPreview:(OUIDocumentPreview *)preview withFilename:(NSString *)previewFilename;
{
    dispatch_async(PreviewCacheOperationQueue, ^{
        _registerPreview(preview, previewFilename);

        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // If we new document has just been downloaded or added via iTunes, we might be transitioning from a placeholder, to an empty preview and then to a real preview. We'd like to only keep the real CGImageRef in memory if the original preview was in view (_displayCount > 0), but we lose this information when we update from placeholder preview to empty preview. We could maybe bring it along in some form, or we could make OUIDocumentPreview instances mutable. On the other hand, there are other race conditions where we can end up with a CGImageRef loaded and a _displayCount==0 (for example, when async image loading sets _image after the preview has scrolled off screen -- though that shouldn't happen since we currently wait for async image loading when calling -image). At any rate, we'll have a separate cleanup pass for previews that end up not being shown in screen.
            if (DiscardHiddenPreviewsTimer == nil) {
                DiscardHiddenPreviewsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_discardHiddenPreviewsTimerFired:) userInfo:nil repeats:NO];
            }
        }];
    });
}

+ (void)_cachePreviewImage:(CGImageRef)fullImage fileEdit:(OFFileEdit *)fileEdit area:(OUIDocumentPreviewArea)area andWriteImages:(BOOL)writeImages;
{
    OBPRECONDITION(fileEdit);
    OBPRECONDITION([NSThread isMainThread]); // Actually -- now that we take an immutable ODSFileItem snapshot as input, we might be able to run on a background queue.
    
    NSURL *previewURL = [self fileURLForPreviewOfFileEdit:fileEdit withArea:area];
    NSString *previewFilename = [previewURL lastPathComponent];
    
    // Do scaling, JPEG compression, and file writing on a background queue. If there is an error writing the image, this means we will cache the passed in version which won't have been written, though.
    // An image of NULL means to cache a "no image" result.
    CGImageRetain(fullImage); // Nail this down while we wait for the writing to finish
    
    // Allow caching negative results for when there is an error generating previews (maybe the document couldn't be read, for example).
    // Avoid reloading the image state from disk (and the I/O probably won't be finished).
    OUIDocumentPreview *preview = [[OUIDocumentPreview alloc] _initWithFileURL:fileEdit.originalFileURL fileEdit:fileEdit area:area previewURL:previewURL exists:YES empty:(fullImage == NULL)];
    DEBUG_PREVIEW(1, @"Generated preview %@=%p for %@ %@ area:%lu", [previewURL lastPathComponent], preview, fileEdit.originalFileURL, fileEdit.uniqueEditIdentifier, area);

    [PreviewCacheReadWriteQueue addOperationWithBlock:^{
        NSData *jpgData = nil;
        if (fullImage) {
            // Shrink the image to the desired size
            CGFloat edgeSize = [OUIDocumentPreview previewSizeForArea:area];
            CGSize imageSize = CGSizeMake(edgeSize, edgeSize);
            CGFloat scale = [OUIDocumentPreview previewImageScale];
            
            imageSize.width = floor(imageSize.width * scale);
            imageSize.height = floor(imageSize.height * scale);
            
            CGImageRef scaledImage = OQCreateImageWithSize(fullImage, imageSize, kCGInterpolationHigh);
            CFRelease(fullImage);
        
            preview.image = scaledImage;
            DEBUG_PREVIEW(1, @"  yielded generated image to preview");

            if (writeImages) {
                UIImage *uiImage = [UIImage imageWithCGImage:scaledImage]; // ... could maybe use CGImageIO directly
                jpgData = UIImageJPEGRepresentation(uiImage, 0.8/* 0(most)..1(least) compression */);
            }
            
            CFRelease(scaledImage);
        }
        
        if (writeImages) {
            if (!jpgData)
                jpgData = [NSData data];
            
            __autoreleasing NSError *writeError = nil;
            DEBUG_PREVIEW(1, @"  writing JPG data of length %ld", [jpgData length]);
            if (![jpgData writeToURL:previewURL options:NSDataWritingAtomic error:&writeError]) {
                NSLog(@"Error writing preview to %@: %@", previewURL, [writeError toPropertyList]);
            }
        }

        // Waiting to register this until it is written to disk so that lookups don't see a preview image URL that isn't yet on disk.
        [self _registerPreview:preview withFilename:previewFilename];
    }];
}

+ (void)_cachePreviewImages:(void (^)(OUIDocumentPreviewCacheImage cacheImage))cachePreviews andWriteImages:(BOOL)writeImages;
{
    OBPRECONDITION(cachePreviews);
    OBPRECONDITION([NSThread isMainThread]);
    
    cachePreviews(^(OFFileEdit *fileEdit, CGImageRef image){
        [self _cachePreviewImage:image fileEdit:fileEdit area:OUIDocumentPreviewAreaLarge andWriteImages:writeImages];
        [self _cachePreviewImage:image fileEdit:fileEdit area:OUIDocumentPreviewAreaMedium andWriteImages:writeImages];
        [self _cachePreviewImage:image fileEdit:fileEdit area:OUIDocumentPreviewAreaSmall andWriteImages:writeImages];
    });
}

+ (void)_discardHiddenPreviewsTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION(DiscardHiddenPreviewsTimer == timer);
    
    DiscardHiddenPreviewsTimer = nil;
    
    [self discardHiddenPreviews];
}

+ (void)performAsynchronousPreviewPreparation:(void (^)(void))block;
{
    OBASSERT([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]);
    
    [PreviewPreparationQueue addOperationWithBlock:block];
}

+ (void)afterAsynchronousPreviewOperation:(void (^)(void))block;
{
    NSOperationQueue *callingQueue = [NSOperationQueue currentQueue];
    OBASSERT(callingQueue != PreviewCacheReadWriteQueue);
    OBASSERT(!IsOnQueue(PreviewCacheOperationQueue));

    // This is lame, but since this queue is concurrent, we can't add an operation and daisy chain the main queue callback off that.
    [PreviewCacheReadWriteQueue waitUntilAllOperationsAreFinished];
    
    block = [block copy];
    
    if (block) {
        dispatch_async(PreviewCacheOperationQueue, ^{
            [callingQueue addOperationWithBlock:block];
        });
    }
}

+ (BOOL)hasPreviewsForFileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION([NSThread isMainThread]);
    if (fileEdit == nil) {
        return YES; // we can't be missing any previews for an edit that doesn't exist.
    }
    
    __block BOOL hasPreviews = NO;
    
    dispatch_sync(PreviewCacheOperationQueue, ^{
        if (!PreviewFileNameToPreview) {
            OBASSERT_NOT_REACHED("Asking about previews before the cache is loaded?");
            return;
        }
        
        BOOL (^checkArea)(OUIDocumentPreviewArea area) = ^(OUIDocumentPreviewArea area){
            NSString *previewFilename = [self _filenameForPreviewOfFileWithEditIdentifier:fileEdit.uniqueEditIdentifier withArea:area];
            OUIDocumentPreview *preview = PreviewFileNameToPreview[previewFilename];
            return preview.exists;
        };
        
        hasPreviews = checkArea(OUIDocumentPreviewAreaLarge) && checkArea(OUIDocumentPreviewAreaMedium) && checkArea(OUIDocumentPreviewAreaSmall);
    });
    
    return hasPreviews;
}

+ (void)deletePreviewsNotUsedByFileItems:(id <NSFastEnumeration>)fileItems;
{
    NSURL *previewDirectoryURL = [self _previewDirectoryURL];
    __autoreleasing NSError *error = nil;
    NSArray *existingPreviewURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:previewDirectoryURL includingPropertiesForKeys:[NSArray array] options:0 error:&error];
    if (!existingPreviewURLs) {
        NSLog(@"Error finding existing previews: %@", [error toPropertyList]);
        return;
    }
    
    // Don't insert NSURLs directly since we don't want to call its -hash/-isEqual:.
    NSMutableSet *unusedPreviewFilenames = [NSMutableSet set];
    for (NSURL *existingPreviewURL in existingPreviewURLs) {
        // NSFileManager can return non-normalized URLs when we ask it for the contents of a directory.
        [unusedPreviewFilenames addObject:[existingPreviewURL lastPathComponent]];
    }
    
    for (ODSFileItem *fileItem in fileItems) {
        void (^removeForArea)(OUIDocumentPreviewArea area) = ^(OUIDocumentPreviewArea area){
            OFFileEdit *fileEdit = fileItem.fileEdit;
            if (fileEdit) {
                NSString *previewFilename;
                if ((previewFilename = [self _filenameForPreviewOfFileWithEditIdentifier:fileEdit.uniqueEditIdentifier withArea:area]))
                    [unusedPreviewFilenames removeObject:previewFilename];
            }
        };
        removeForArea(OUIDocumentPreviewAreaLarge);
        removeForArea(OUIDocumentPreviewAreaMedium);
        removeForArea(OUIDocumentPreviewAreaSmall);
    }
    
    DEBUG_PREVIEW(1, @"Removing unused previews: %@", unusedPreviewFilenames);
    
    for (NSString *previewFilename in unusedPreviewFilenames) {
        __autoreleasing NSError *removeError = nil;
        NSURL *unusedPreviewURL = [previewDirectoryURL URLByAppendingPathComponent:previewFilename];
        if (![[NSFileManager defaultManager] removeItemAtURL:unusedPreviewURL error:&removeError])
            NSLog(@"Error removing %@: %@", [unusedPreviewURL absoluteString], [removeError toPropertyList]);
    }
}

static NSString *attemptCacheKeyForFileURLWithPossibleContainer(NSURL *fileURL, NSURL *containerURL, NSString *prefix)
{
    if (!OFURLContainsURL(containerURL, fileURL))
        return nil;
    
    NSString *relativePath = OFFileURLRelativePath(containerURL, fileURL);
    OBASSERT(![NSString isEmptyString:relativePath]);
    return [NSString stringWithFormat:@"%@/%@", prefix, relativePath];
}

static NSString *cacheKeyForFileURL(NSURL *fileURL)
{
    // We used to use the full URL here as an easy way to deal with files with the same relative path between two different containers or (even folders). But in iOS 8, each time the application is updated, the base container URL changes (it seems). This would cause document previews to be regenerated when not needed. Instead, we want to include enough of the prefix that we have a unique scope prefix for the file, as well as the document's relative path within the scope.
    // Use something that doesn't look like a path component for the prefix so that we don't trick ourselves into thinking it really is.
    
    NSString *cacheKey;
    
    if ((cacheKey = attemptCacheKeyForFileURLWithPossibleContainer(fileURL, [ODSLocalDirectoryScope userDocumentsDirectoryURL], @"DOC")))
        return cacheKey;
    
    if ((cacheKey = attemptCacheKeyForFileURLWithPossibleContainer(fileURL, [ODSLocalDirectoryScope trashDirectoryURL], @"TRASH")))
        return cacheKey;

    // Document templates, for example.
    if ((cacheKey = attemptCacheKeyForFileURLWithPossibleContainer(fileURL, [[NSBundle mainBundle] bundleURL], @"APP")))
        return cacheKey;

    static dispatch_once_t onceToken;
    static NSURL *applicationSupportDirectoryURL = nil;
    dispatch_once(&onceToken, ^{
        __autoreleasing NSError *error;
        applicationSupportDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
        if (!applicationSupportDirectoryURL)
            [error log:@"Unable to locate application support directory."];
    });

    if ((cacheKey = attemptCacheKeyForFileURLWithPossibleContainer(fileURL, applicationSupportDirectoryURL, @"APP_SUPPORT")))
        return cacheKey;

    // Fall through to the old approach of using the full URL.
    OBASSERT_NOT_REACHED("Unknown container for file at %@", fileURL);
    
    // Normalization is too slow to do here, but we can get both /private/mobile and /var/private/mobile.
    NSString *urlString = [fileURL absoluteString];
    static NSString * const BadVarMobilePrefix = @"file://localhost/private/var/mobile/";
    static NSString * const GoodVarMobilePrefix = @"file://localhost/var/mobile/";
    if ([urlString hasPrefix:BadVarMobilePrefix]) {
        NSMutableString *fixedString = [urlString mutableCopy];
        [fixedString replaceCharactersInRange:NSMakeRange(0, [BadVarMobilePrefix length]) withString:GoodVarMobilePrefix];
        urlString = fixedString;
    }
    
    // Finally, map directories to the same thing no matter if they have the slash or not.
    if ([urlString hasSuffix:@"/"])
        urlString = [urlString stringByRemovingSuffix:@"/"];
    
    return urlString;
}

+ (NSString *)_filenameForPreviewOfFileWithEditIdentifier:(NSString *)fileEditIdentifier withArea:(OUIDocumentPreviewArea)area;
{
    return [[NSString stringWithFormat:@"%@-%@", fileEditIdentifier, AreaNames[area]] stringByAppendingPathExtension:@"jpg"];
}

+ (NSURL *)fileURLForPreviewOfFileEdit:(OFFileEdit *)fileEdit withArea:(OUIDocumentPreviewArea)area;
{
    OBPRECONDITION(fileEdit);

    NSString *filename = [self _filenameForPreviewOfFileWithEditIdentifier:fileEdit.uniqueEditIdentifier withArea:area];
    return _previewURLWithFilename(filename);
}

+ (void)writeEmptyPreviewsForFileEdit:(OFFileEdit *)fileEdit;
{
    for (OUIDocumentPreviewArea area = OUIDocumentPreviewAreaLarge; area <= OUIDocumentPreviewAreaSmall; area++) {
        NSURL *previewURL = [OUIDocumentPreview fileURLForPreviewOfFileEdit:fileEdit withArea:area];
        __autoreleasing NSError *error = nil;
        if (![[NSData data] writeToURL:previewURL options:0 error:&error])
            NSLog(@"Error writing empty data for preview to %@: %@", previewURL, [error toPropertyList]);
    }
}

+ (void)writeEncryptedEmptyPreviewsForFileEdit:(OFFileEdit *)fileEdit fileURL:(NSURL *)fileURL;
{
    for (OUIDocumentPreviewArea area = OUIDocumentPreviewAreaLarge; area <= OUIDocumentPreviewAreaSmall; area++) {
        Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:fileURL];
        CGImageRef imageRef = _copyPlaceholderPreviewImage([self class], documentClass, fileURL, YES, area); // returns +1 CF
        [OUIDocumentPreview cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage){
            cacheImage(fileEdit, imageRef);
            CGImageRelease(imageRef);
        }];
    }
}

static CGImageRef _copyPlaceholderPreviewImage(Class self, Class documentClass, NSURL *fileURL, BOOL isEncrypted, OUIDocumentPreviewArea area) CF_RETURNS_RETAINED;
static CGImageRef _copyPlaceholderPreviewImage(Class self, Class documentClass, NSURL *fileURL, BOOL isEncrypted, OUIDocumentPreviewArea area)
{
    OUIImageLocation *placeholderImage;

    if (!documentClass) {
        // This can happen for file types that we have in the document browser, but can't actually open. We still need to show a preview for them somehow.
        documentClass = [OUIDocument class];
    }

    if (isEncrypted) {
        placeholderImage = [documentClass encryptedPlaceholderPreviewImageForFileURL:fileURL area:area];
    } else {
        placeholderImage = [documentClass placeholderPreviewImageForFileURL:fileURL area:area];
    }
    if (!placeholderImage) {
        OBASSERT_NOT_REACHED("No default preview image registered?");
        return NULL;
    }

    __block CGImageRef result = NULL;
    
    // We fiddle with global caches, so only one operation can be touching this at once
    [PreviewPlaceholderOperationQueue addOperationWithBlock:^{
        
        // Cache a single copy of the badged placeholder preview image in this orientation
        CGImageRef badgedImage;
        {
            NSString *cacheKey = [NSString stringWithFormat:@"%@-%@", AreaCacheSuffix[area], placeholderImage.name];
            
            if (BadgedPlaceholderPreviewImageCache)
                badgedImage = (CGImageRef)CFDictionaryGetValue(BadgedPlaceholderPreviewImageCache, (__bridge const void *)(cacheKey));
            else
                badgedImage = NULL;
            
            if (!badgedImage) {
                // Badge the placeholder image onto a white sheet of paper and cache that image.
                CGFloat edgeSize = [self previewSizeForArea:area];
                CGSize size = CGSizeMake(edgeSize, edgeSize);
                CGFloat scale = [OUIDocumentPreview previewImageScale];
                size.width = floor(size.width * scale);
                size.height = floor(size.height * scale);
                
                UIGraphicsBeginImageContextWithOptions(size, YES/*opaque*/, 0);
                {
                    CGRect paperRect = CGRectMake(0, 0, size.width, size.height);
                    
                    [[UIColor whiteColor] set];
                    UIRectFill(paperRect);
                    
                    CGImageRef previewImage = [placeholderImage.image CGImage];

                    if (!previewImage) {
                        // We'll just end up with a white rectangle in this case
                        OBASSERT_NOT_REACHED("No image found for default image name returned");
                    } else {
                        CGSize imageSize = CGSizeMake(CGImageGetWidth(previewImage), CGImageGetHeight(previewImage));
                        imageSize.width = floor(imageSize.width * scale);
                        imageSize.height = floor(imageSize.height * scale);
                        
                        CGRect targetImageRect = OQCenterAndFitIntegralRectInRectWithSameAspectRatioAsSize(paperRect, imageSize);
                        
                        CGContextRef ctx = UIGraphicsGetCurrentContext();
                        CGContextTranslateCTM(ctx, targetImageRect.origin.x, targetImageRect.origin.y);
                        targetImageRect.origin = CGPointZero;
                        
                        OQFlipVerticallyInRect(ctx, targetImageRect);
                        
                        CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
                        CGContextDrawImage(ctx, targetImageRect, previewImage);
                    }
                    
#ifdef DEBUG
                    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
                    [UIImageJPEGRepresentation(img, 1) writeToFile:@"/tmp/badged.jpg" atomically:YES];
#endif

                    badgedImage = [UIGraphicsGetImageFromCurrentImageContext() CGImage];
                }
                UIGraphicsEndImageContext();
                
                if (!BadgedPlaceholderPreviewImageCache)
                    BadgedPlaceholderPreviewImageCache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &CFTypeDictionaryValueCallbacks);
                
                CFDictionarySetValue(BadgedPlaceholderPreviewImageCache, (__bridge const void *)(cacheKey), badgedImage);
                DEBUG_PREVIEW(1, @"Built badged placeholder preview image %@ with \"%@\"", badgedImage, cacheKey);
            } else {
                DEBUG_PREVIEW(1, @"Using previously generated badged placeholder preview image with \"%@\"", cacheKey);
            }
        }
    
        result = badgedImage;
        if (result)
            CFRetain(result); // Will pass this ref back to the caller
    }];
    
    [PreviewPlaceholderOperationQueue waitUntilAllOperationsAreFinished];
    
    return result;
}

+ (OUIDocumentPreview *)makePreviewForDocumentClass:(Class)documentClass fileItem:(ODSFileItem *)fileItem withArea:(OUIDocumentPreviewArea)area;
{
    OBPRECONDITION([NSThread isMainThread]); // We might update PreviewImageByURL for placeholders (could fork just the cache update to the main thread if needed).

    __block OUIDocumentPreview *preview = nil;
    
    // Since file items are only updated on the main thread and since we do a dispatch sync here, we don't need to extract the state from the file item. But, we will anyway so that the API is written for it.
    OFFileEdit *fileEdit = fileItem.fileEdit; // Might be nil, if this file isn't downloaded.
    NSURL *fileURL = fileItem.fileURL;
    if (!fileEdit) {
        // Not downloaded, so use a placeholder preview.
        return [[self alloc] _initWithFileURL:fileURL fileEdit:nil area:area previewURL:nil exists:NO empty:YES];
    }
    
    dispatch_sync(PreviewCacheOperationQueue, ^{
        OBASSERT(PreviewFileNameToPreview, "Looking up previews before the cache is loaded?");

        NSString *previewFilename = [self _filenameForPreviewOfFileWithEditIdentifier:fileEdit.uniqueEditIdentifier withArea:area];
        preview = PreviewFileNameToPreview[previewFilename];
        
        if (!preview && PreviewDestinationPathToSourcePreview) {
            // Check our aliases for in-flight moves and copies. We register preview aliases on URL only since we don't know what the date will be for copied files when we see them.
            NSString *destinationKey = [cacheKeyForFileURL(fileEdit.originalFileURL) stringByAppendingFormat:@"-%@", AreaCacheSuffix[area]];
            preview = PreviewDestinationPathToSourcePreview[destinationKey];
            if (preview)
                DEBUG_PREVIEW(1, @"Looked up by alias %@ -> %@", destinationKey, preview);
        }
        
        if (!preview) {
            // This can happen when adding a new document from iTunes -- there may be an in flight async registration of the preview that hasn't finished yet. Just make up a placeholder.
            NSURL *previewURL = _previewURLWithFilename(previewFilename);
            
            preview = [[self alloc] _initWithFileURL:fileURL fileEdit:fileEdit area:area previewURL:previewURL exists:NO empty:YES];
        }
    });

    return preview;
}

+ (void)addAliasFromFileItemEdit:(ODSFileItemEdit *)fromFileItemEdit toFileWithURL:(NSURL *)toFileURL;
{
    OBPRECONDITION([NSThread isMainThread], "File items are updated on the main thread, so make sure we aren't racing with it");
    
    OFFileEdit *fileEdit = fromFileItemEdit.originalFileEdit;
    if (!fileEdit) {
        OBASSERT_NOT_REACHED("Can't make an alias from a non-downloaded file.");
        return;
    }
    
    NSString *fromEditIdentifier = fileEdit.uniqueEditIdentifier;
    toFileURL = _normalizeURL(toFileURL);

    dispatch_sync(PreviewCacheOperationQueue, ^{
        if (!PreviewDestinationPathToSourcePreview)
            PreviewDestinationPathToSourcePreview = [NSMutableDictionary new];
        
        void (^op)(OUIDocumentPreviewArea area) = ^(OUIDocumentPreviewArea area){

            NSString *destinationKey = [cacheKeyForFileURL(toFileURL) stringByAppendingFormat:@"-%@", AreaCacheSuffix[area]];
            OBASSERT(PreviewDestinationPathToSourcePreview[destinationKey] == nil);
            
            NSString *previewFilename = [self _filenameForPreviewOfFileWithEditIdentifier:fromEditIdentifier withArea:area];
            
            OBASSERT(PreviewFileNameToPreview, "Looking up previews while the cache isn't loaded.");
            OUIDocumentPreview *preview = PreviewFileNameToPreview[previewFilename];
            if (preview) {
                DEBUG_PREVIEW(1, @"Adding alias %@ -> %@", destinationKey, [preview shortDescription]);
                PreviewDestinationPathToSourcePreview[destinationKey] = preview;
            }
        };
        
        op(OUIDocumentPreviewAreaLarge);
        op(OUIDocumentPreviewAreaMedium);
        op(OUIDocumentPreviewAreaSmall);
    });
}

+ (void)removeAliasFromFileItemEdit:(ODSFileItemEdit *)fromFileItemEdit toFileWithURL:(NSURL *)toFileURL;
{
    OBPRECONDITION([NSThread isMainThread], "File items are updated on the main thread, so make sure we aren't racing with it");

#ifdef OMNI_ASSERTIONS_ON
    NSString *fromFileEditIdentifier = fromFileItemEdit.originalFileEdit.uniqueEditIdentifier;
#endif
    toFileURL = _normalizeURL(toFileURL);

    dispatch_sync(PreviewCacheOperationQueue, ^{
        void (^op)(OUIDocumentPreviewArea area) = ^(OUIDocumentPreviewArea area){
            NSString *destinationKey = [cacheKeyForFileURL(toFileURL) stringByAppendingFormat:@"-%@", AreaCacheSuffix[area]];
#ifdef OMNI_ASSERTIONS_ON
            OUIDocumentPreview *preview = PreviewDestinationPathToSourcePreview[destinationKey];
            OBASSERT(preview);
            OBASSERT_IF(preview, [preview.fileEditIdentifier isEqual:fromFileEditIdentifier]);
            OBASSERT_IF(preview, preview.area == area);
#endif
            DEBUG_PREVIEW(1, @"Removing alias %@ -> %@", destinationKey, PreviewDestinationPathToSourcePreview[destinationKey]);
            [PreviewDestinationPathToSourcePreview removeObjectForKey:destinationKey];
        };
        
        op(OUIDocumentPreviewAreaLarge);
        op(OUIDocumentPreviewAreaMedium);
        op(OUIDocumentPreviewAreaSmall);
    });
}

static void _copyPreview(Class self, OFFileEdit *sourceFileEdit, OFFileEdit *targetFileEdit, OUIDocumentPreviewArea area)
{
    OBPRECONDITION([NSThread isMainThread]);
    
    NSURL *sourcePreviewFileURL = [self fileURLForPreviewOfFileEdit:sourceFileEdit withArea:area];
    NSURL *targetPreviewFileURL = [self fileURLForPreviewOfFileEdit:targetFileEdit withArea:area];
    
    DEBUG_PREVIEW(1, @"copying preview %@ -> %@", sourcePreviewFileURL, targetPreviewFileURL);
    
    OBASSERT(PreviewFileNameToPreview, "Looking up previews while the cache isn't loaded.");
    OUIDocumentPreview *sourcePreview = PreviewFileNameToPreview[[sourcePreviewFileURL lastPathComponent]];
    // Need to check for nil here becuase of this bug. <bug:///98537> (Wrong date is bing used to generate preview filename)
    if (!sourcePreview || (sourcePreview->_type != OUIDocumentPreviewTypeRegular)) // -type asserts we've loaded the file, but we might not have loaded all the preview sizes. We just want to copy whatever is on disk.
        return; // Not a worthwhile thing to copy.
    
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    
    // Copy the file (if any)
    __autoreleasing NSError *copyError = nil;
    if (![defaultManager copyItemAtURL:sourcePreviewFileURL toURL:targetPreviewFileURL error:&copyError]) {
        if (![copyError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT] || // source gone missing
            ![copyError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST]) // destination generated somehow already
            NSLog(@"Error copying preview from %@ to %@: %@", sourcePreviewFileURL, targetPreviewFileURL, [copyError toPropertyList]);
    }
    
    // Register the new preview if the source had it loaded (most likely since the user is operating on it).
    OUIDocumentPreview *targetPreview = [[OUIDocumentPreview alloc] _initWithFileURL:targetFileEdit.originalFileURL fileEdit:targetFileEdit area:area previewURL:targetPreviewFileURL];
    
    if (sourcePreview->_image) // Don't force loading; just do it if already loaded
        targetPreview.image = sourcePreview->_image;

    if (!PreviewFileNameToPreview)
        PreviewFileNameToPreview = [[NSMutableDictionary alloc] init];
    _registerPreview(targetPreview, [targetPreviewFileURL lastPathComponent]);
}

+ (void)cachePreviewImagesForFileEdit:(OFFileEdit *)targetFileEdit
            byDuplicatingFromFileEdit:(OFFileEdit *)sourceFileEdit;
{
    DEBUG_PREVIEW(1, @"copying preview %@ / %@ -> %@ / %@",
                  [sourceFileEdit.fileModificationDate xmlString], sourceFileEdit.originalFileURL,
                  [targetFileEdit.fileModificationDate xmlString], targetFileEdit.originalFileURL);

    dispatch_sync(PreviewCacheOperationQueue, ^{
        _copyPreview(self, sourceFileEdit, targetFileEdit, OUIDocumentPreviewAreaLarge);
        _copyPreview(self, sourceFileEdit, targetFileEdit, OUIDocumentPreviewAreaMedium);
        _copyPreview(self, sourceFileEdit, targetFileEdit, OUIDocumentPreviewAreaSmall);
    });
}

+ (CGFloat)previewSizeForArea:(OUIDocumentPreviewArea)area;
{
    switch (area) {
        case OUIDocumentPreviewAreaMedium:
            return 100;
        case OUIDocumentPreviewAreaSmall:
            return 60;
        default:
            OBASSERT_NOT_REACHED("Unknown preview area");
            // fall through
        case OUIDocumentPreviewAreaLarge:
            return 220;
    }
}

// Returns the scale at which the preview image should be rendered when saving to disk, just the device scale for now.
+ (CGFloat)previewImageScale;
{
    return [[UIScreen mainScreen] scale];
}

- _initWithFileURL:(NSURL *)fileURL fileEdit:(OFFileEdit *)fileEdit area:(OUIDocumentPreviewArea)area previewURL:(NSURL *)previewURL exists:(BOOL)exists empty:(BOOL)empty;
{
    OBPRECONDITION(fileURL); // Needed for placeholders to get the proper image
    OBPRECONDITION(!fileEdit || OFURLEqualsURL(fileURL, fileEdit.originalFileURL));
    OBPRECONDITION(fileEdit || !exists);
    OBPRECONDITION(previewURL || !exists);
    
    if (!(self = [super init]))
        return nil;
    
    _fileURL = [fileURL copy]; // Needed in case this is a placeholder and fileEdit is nil
    _fileEdit = fileEdit;
    _area = area;
    _previewURL = previewURL;
    _exists = exists;
    _empty = empty;
    
    return self;
}

- _initWithFileURL:(NSURL *)fileURL fileEdit:(OFFileEdit *)fileEdit area:(OUIDocumentPreviewArea)area previewURL:(NSURL *)previewURL;
{
    // We look these up immediately so that +hasPreviewsForFileURL:date: can check our properties
    // Don't ask the URL via getResourceValue:forKey:error: since that can return a cached value. We might have just written the image during preview generation after previously having looked up the empty placeholder that is written prior to preview generation.

    BOOL exists = YES;
    __autoreleasing NSError *attributesError = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[previewURL absoluteURL] path] error:&attributesError];
    if (!attributes) {
        if ([attributesError causedByMissingFile]) {
            // No preview generated yet
        } else {
            NSLog(@"Error getting attributes of preview image %@: %@", previewURL, [attributesError toPropertyList]);
        }
        exists = NO; // either way, don't try to load the file
    }
    BOOL empty = ([attributes fileSize] == 0);
    
    return [self _initWithFileURL:fileURL fileEdit:fileEdit area:area previewURL:previewURL exists:exists empty:empty];
}

- (void)dealloc;
{
    if (_image)
        CFRelease(_image);
    
    OBASSERT(_displayCount == 0); // should have put a -retain on it.
    OBASSERT(!_loadOperation || [_loadOperation isFinished]);
}

- (void)_ensureLoaded;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (!_image) {
        if (!_loadOperation) {
            OBASSERT(_loadOperation, "Should have called -startLoadingPreview to hide some of the loading latency");
            [self startLoadingPreview];
        }
        
        // The background operation doesn't call back to the main queue, it just sets _image, so we can wait w/o deadlocking.
        [_loadOperation waitUntilFinished];
        OBASSERT(_image);
    }
}

- (NSString *)fileEditIdentifier;
{
    return _fileEdit.uniqueEditIdentifier;
}
- (NSDate *)date;
{
    return _fileEdit.fileModificationDate;
}

@synthesize type = _type;
- (OUIDocumentPreviewType)type;
{
    [self _ensureLoaded];
    return _type;
}

@synthesize image = _image;
- (CGImageRef)image;
{
    [self _ensureLoaded];
    return _image;
}
- (void)setImage:(CGImageRef)image;
{
    OBPRECONDITION(!_image, "This should only be called for newly created previews that are setting up the image to avoid reloading it needlessly");
    OBPRECONDITION(!_loadOperation);
    OBPRECONDITION(_empty == (image == NULL), "The caller should have set up the _empty property correctly");

    _image = image;
    if (_image)
        CFRetain(_image);
}

- (CGSize)size;
{
    if (!_image)
        return CGSizeZero;
    return CGSizeMake(CGImageGetWidth(_image), CGImageGetHeight(_image));
}

- (void)_loadPreview;
{
    if (_image) {
        OBASSERT_NOT_REACHED("Tried loading the preview a second time?");
        return;
    }
    
    if (_exists && !_empty) {
        _image = _loadImageFromURL(_previewURL); // Returns +1 CF
        if (_image) {
            DEBUG_PREVIEW(1, @"Loaded existing preview for %@ %lu -- %@", [_fileEdit shortDescription], _area, _previewURL);
            _type = OUIDocumentPreviewTypeRegular;
            return;
        }
        // fall through to create a placeholder
    }

    Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:_fileURL];
    
    if (_empty) {
        // There is a zero length file or was an error reading the image
        _type = OUIDocumentPreviewTypeEmpty;
        _image = _copyPlaceholderPreviewImage([self class], documentClass, _fileURL, NO, _area); // returns +1 CF
        if (_image) {
            DEBUG_PREVIEW(1, @"Caching badged placeholder for empty %@ %lu", [_fileEdit shortDescription], _area);
            return;
        }
        // fall through to create a placeholder
    }
    
    _type = OUIDocumentPreviewTypePlaceholder;
    _image = _copyPlaceholderPreviewImage([self class], documentClass, _fileURL, NO, _area); // returns +1 CF
    DEBUG_PREVIEW(1, @"Caching badged placeholder for missing %@ %lu", [_fileEdit shortDescription], _area);
    
    OBPOSTCONDITION(_image);
}

- (void)startLoadingPreview;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([[OUIDocumentAppController controller] document] == nil, "Don't load previews while we have an open document.  bug:///137636 (iOS-OmniGraffle Crasher: assertion fails sometimes saving document preview on close)"); 

    if (_image)
        return; // Already loaded!
    
    if (_loadOperation)
        return;
    
    DEBUG_PREVIEW(1, "Start loading image");

    _loadOperation = [NSBlockOperation blockOperationWithBlock:^{
        [self _loadPreview];
        
        // Clear reference cycle back to ourselves
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // Make sure another operation didn't get started somehow...
            if ([_loadOperation isFinished])
                _loadOperation = nil;
        }];
    }];
    
    [PreviewCacheReadWriteQueue addOperation:_loadOperation];
}

- (void)discardLoadedPreview;
{
    OBPRECONDITION([NSThread isMainThread]);

    // There might be a preview load in flight; we don't attempt to synchronize with it, but we do make a minimal attempt to stop it (might scrolling quickly). If the operation *does* load an image for us, the next call to -startLoadingPreview will just do nothing (our memory use will be higher than it should, though, so we may want to sign up for memory warnings to purge extra images).
    if (_loadOperation) {
        if (![_loadOperation isFinished] && ![_loadOperation isCancelled]) {
            DEBUG_PREVIEW(1, "Cancelling image load operation");
            [_loadOperation cancel];
        }
        _loadOperation = nil;
    }
    
    if (_image) {
        DEBUG_PREVIEW(1, "Discarding loaded image");

        // TODO: We race with the final retain as this is assigned? Do the retain into a local, barrier, and then assign to the property?
        CFRelease(_image);
        _image = NULL;
    }
}

- (void)incrementDisplayCount;
{
    if (_displayCount == 0) {
        [self startLoadingPreview];
    }
    _displayCount++;
    DEBUG_PREVIEW(2, "Increment display count %p, now %ld", self, _displayCount);
}

- (void)decrementDisplayCount;
{
    OBPRECONDITION(_displayCount > 0, "Missing call to -incrementDisplayCount");
    
    if (_displayCount > 0) {
        _displayCount--;
        if (_displayCount == 0)
            [self discardLoadedPreview];
    }
    DEBUG_PREVIEW(2, "Decrement display count %p, now %ld", self, _displayCount);
}

- (BOOL)_discardPreviewIfHidden;
{
    if (_image && _displayCount == 0) {
        [self discardLoadedPreview];
        return YES;
    }
    return NO;
}

#if 0
- (void)drawInRect:(CGRect)rect;
{
    OBPRECONDITION(rect.size.width >= 1);
    OBPRECONDITION(rect.size.height >= 1);
    
    if (!_image || rect.size.width < 1 || rect.size.height < 1)
        return;
    
    size_t width = CGImageGetWidth(_image);
    size_t height = CGImageGetHeight(_image);
    
    if (width == 0 || height == 0) {
        OBASSERT_NOT_REACHED("Degenerate image");
        return;
    }
    
    DEBUG_PREVIEW(1, @"Drawing scaled preview %@ -> %@", NSStringFromCGSize(CGSizeMake(width, height)), NSStringFromCGRect(rect));
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    {
        CGContextTranslateCTM(ctx, rect.origin.x, rect.origin.y);
        rect.origin = CGPointZero;
        
        OQFlipVerticallyInRect(ctx, rect);
        
        //CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
        CGContextDrawImage(ctx, rect, _image);
    }
    CGContextRestoreGState(ctx);
}
#endif

#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    NSString *typeString;
    switch (_type) {
        case OUIDocumentPreviewTypeRegular:
            typeString = @"regular";
            break;
        case OUIDocumentPreviewTypePlaceholder:
            typeString = @"placeholder";
            break;
        case OUIDocumentPreviewTypeEmpty:
            typeString = @"empty";
            break;
        default:
            typeString = @"UNKNOWN";
            break;
    }
    
    return [NSString stringWithFormat:@"<%@:%p item:%@ date:%@ image:%p area:%ld type:%@>", NSStringFromClass([self class]), self, [_fileURL absoluteString], [_fileEdit.fileModificationDate xmlString], _image, _area, typeString];
}

#pragma mark - Private

+ (NSURL *)_previewDirectoryURL;
{
    static NSURL *previewDirectoryURL = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        __autoreleasing NSError *error = nil;
        
        NSFileManager *manager = [NSFileManager defaultManager];
        NSURL *caches = [manager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
        if (caches) {
            previewDirectoryURL = _normalizeURL([caches URLByAppendingPathComponent:@"DocumentPreviews" isDirectory:YES]);
            
            // Support for cleaning out all previews on launch.
#if 0 && defined(DEBUG_bungi)
            static BOOL firstUpdate = YES;
            if (firstUpdate) {
                firstUpdate = NO;
                
                NSLog(@"Removing all previews!");
                __autoreleasing NSError *removeError;
                if (![manager removeItemAtURL:previewDirectoryURL error:&removeError]) {
                    if (![removeError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
                        NSLog(@"Unable to remove preview directory: %@", [removeError toPropertyList]);
                    }
                }
            }
#endif
            
            if (![manager createDirectoryAtURL:previewDirectoryURL withIntermediateDirectories:NO attributes:nil error:&error]) {
                if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST]) {
                    // All good
                } else {
                    previewDirectoryURL = nil;
                }
            }
        }
        
        // TODO: Validate the previews vs. the version number of the app, or maybe a preview version number? Might be nice to rebuild the previews in the case that the app gets a new look. OTOH, maybe iTunes will torch our caches directory automatically on a version update.
        
        if (!previewDirectoryURL) {
            OBASSERT_NOT_REACHED("Unable to create caches directory!");
            NSLog(@"Unable to create preview image directory: %@", [error toPropertyList]);
        }
    });
    
    return previewDirectoryURL;
}

@end
