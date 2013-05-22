// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPreview.h>

#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <ImageIO/CGImageSource.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_PREVIEW_CACHE_DEFINED 1
    #define DEBUG_PREVIEW_CACHE(format, ...) NSLog(@"PREVIEW: " format, ## __VA_ARGS__)
#else
    #define DEBUG_PREVIEW_CACHE_DEFINED 0
    #define DEBUG_PREVIEW_CACHE(format, ...)
#endif

@interface OUIDocumentPreview ()
+ (NSURL *)_previewDirectoryURL;
+ (NSString *)_filenameForPreviewOfFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
- _initWithFileURL:(NSURL *)fileURL date:(NSDate *)date landscape:(BOOL)landscape previewURL:(NSURL *)previewURL exists:(BOOL)exists empty:(BOOL)empty;
- _initWithFileURL:(NSURL *)fileURL date:(NSDate *)date landscape:(BOOL)landscape previewURL:(NSURL *)previewURL;
- (void)_didMoveToFileURL:(NSURL *)fileURL date:(NSDate *)date previewURL:(NSURL *)previewURL;

@property(nonatomic,readwrite) CGImageRef image;
@property(nonatomic,readonly) BOOL exists;
@property(nonatomic,readonly) BOOL empty;

@end

@implementation OUIDocumentPreview
{
    NSURL *_fileURL;
    NSDate *_date;
    BOOL _landscape;

    NSURL *_previewURL;
    NSUInteger _displayCount;
    NSOperation *_loadOperation;
    CGImageRef _image; // Always set if we are loaded (set to a placeholder if there is no real preview)
    
    OUIDocumentPreviewType _type;
    BOOL _superseded;
}

static dispatch_queue_t PreviewCacheOperationQueue; // Serial background queue for general operations; GCD so we can use async/sync/barrier
static NSOperationQueue *PreviewCacheReadWriteQueue; // Concurrent background queue for loading/saving/decoding preview images

// A cache of preview file name -> OUIDocumentPreview isntances. Only usable inside PreviewCacheOperationQueue.
static NSMutableDictionary *PreviewFileNameToPreview;

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

static CFStringRef kOUIDocumentPreviewTypeEmptyMarker = CFSTR("kOUIDocumentPreviewTypeEmptyMarker");
static CFStringRef kOUIRemoveCacheEntryMarker = CFSTR("kOUIRemoveCacheEntryMarker");

+ (void)initialize;
{
    OBINITIALIZE;
    
    /*
     Use a concurrent queue for operations to run in parallel and a serial queue to allow barriers. This requires that any operations on the concurrent queue be dependencies of some completion operation on the serial queue.
     */
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PreviewCacheOperationQueue = dispatch_queue_create("com.omnigroup.OmniUI.OUIDocumentPreview.operations", DISPATCH_QUEUE_SERIAL);
        
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
    //DEBUG_PREVIEW_CACHE(@"fileURL %@ -> previewURL %@", fileURL, previewURL);
    
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

static void _populatePreview(Class self, NSSet *existingPreviewFileNames, OFSDocumentStoreFileItem *fileItem, BOOL landscape)
{
    NSURL *fileURL = fileItem.fileURL;
    NSDate *date = fileItem.fileModificationDate;
        
    NSString *previewFilename = [self _filenameForPreviewOfFileURL:fileURL date:date withLandscape:landscape];
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
    
    preview = [[self alloc] _initWithFileURL:fileURL date:date landscape:landscape previewURL:previewURL exists:exists empty:empty];
    [PreviewFileNameToPreview setObject:preview forKey:[previewURL lastPathComponent]];
    DEBUG_PREVIEW_CACHE(@"Populated preview %@=%p (exists:%d, empty:%d) for %@ %@ landscape:%d", [previewURL lastPathComponent], preview, exists, empty, fileURL, [date xmlString], landscape);
}

+ (void)populateCacheForFileItems:(id <NSFastEnumeration>)fileItems completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    DEBUG_PREVIEW_CACHE(@"Queuing cache population request");

    if (!fileItems)
        return;
    
    completionHandler = [completionHandler copy]; // capture scope

    DEBUG_PREVIEW_CACHE(@"Queuing cache population operation, fileItems = %@", fileItems);
    
    dispatch_async(PreviewCacheOperationQueue, ^{
        DEBUG_PREVIEW_CACHE(@"Performing cache population request");

        [self _populateCacheWithFileItems:fileItems];
                
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{            
            DEBUG_PREVIEW_CACHE(@"Finishing cache population request");
            if (completionHandler)
                completionHandler();
        }];
    });
}

+ (void)_populateCacheWithFileItems:(id <NSFastEnumeration>)fileItems;
{
    // dispatch_get_current_queue() is deprecated, sadly.
    // OBPRECONDITION(dispatch_get_current_queue() == PreviewCacheOperationQueue);
    
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
    
    for (OFSDocumentStoreFileItem *fileItem in fileItems) {
        _populatePreview(self, existingPreviewFileNames, fileItem, YES/*landscape*/);
        _populatePreview(self, existingPreviewFileNames, fileItem, NO/*landscape*/);
    }
}

+ (void)discardHiddenPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);
    
#if DEBUG_PREVIEW_CACHE_DEFINED
    __block NSUInteger keptPreviews = 0;
    __block NSUInteger discardedPreviews = 0;
#endif
    
    dispatch_barrier_sync(PreviewCacheOperationQueue, ^{
        [PreviewFileNameToPreview enumerateKeysAndObjectsUsingBlock:^(NSString *filename, OUIDocumentPreview *preview, BOOL *stop) {
            if ([preview _discardPreviewIfHidden]) {
#if DEBUG_PREVIEW_CACHE_DEFINED
                discardedPreviews++;
#endif
            }
#if DEBUG_PREVIEW_CACHE_DEFINED
            if (preview->_image)
                keptPreviews++;
#endif
        }];
    });
    
    DEBUG_PREVIEW_CACHE(@"Cleaned up %ld hidden previews, kept %ld", discardedPreviews, keptPreviews);
}

+ (void)flushPreviewImageCache;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_PREVIEW_CACHE(@"Flushing preview cache");

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

+ (void)_cachePreviewImages:(void (^)(OUIDocumentPreviewCacheImage cacheImage))cachePreviews andWriteImages:(BOOL)writeImages;
{
    OBPRECONDITION(cachePreviews);
    OBPRECONDITION([NSThread isMainThread]);
    
    cachePreviews(^(NSURL *fileURL, NSDate *date, BOOL landscape, CGImageRef image){
        OBASSERT([NSThread isMainThread]);
        
        NSURL *previewURL = [self fileURLForPreviewOfFileURL:fileURL date:date withLandscape:landscape];
        NSString *previewFilename = [previewURL lastPathComponent];
        
        if (writeImages) {
            // Do the JPEG compression and writing on a background queue. If there is an error writing the image, this means we will cache the passed in version which won't have been written, though.

            CGImageRetain(image); // Nail this down while we wait for the writing to finish
            
            [PreviewCacheReadWriteQueue addOperationWithBlock:^{
                NSData *jpgData = nil;
                if (image) {
                    UIImage *uiImage = [UIImage imageWithCGImage:image]; // ... could maybe use CGImageIO directly
                    CFRelease(image);
                    jpgData = UIImageJPEGRepresentation(uiImage, 0.5/* 0..1 compression */);
                }
                if (!jpgData)
                    jpgData = [NSData data];
                
                __autoreleasing NSError *writeError = nil;
                if (![jpgData writeToURL:previewURL options:NSDataWritingAtomic error:&writeError]) {
                    NSLog(@"Error writing preview to %@: %@", previewURL, [writeError toPropertyList]);
                }
            }];
        }
        
        // An image of NULL means to cache a "no image" result. kOUIRemoveCacheEntryMarker means to remove the cache entry.
        if (image == (CGImageRef)kOUIRemoveCacheEntryMarker) {
            dispatch_async(PreviewCacheOperationQueue, ^{
                OBASSERT([PreviewFileNameToPreview objectForKey:previewFilename]);
                [PreviewFileNameToPreview removeObjectForKey:previewFilename];
            });
        } else {
            // If we new document has just been downloaded or added via iTunes, we might be transitioning from a placeholder, to an empty preview and then to a real preview. We'd like to only keep the real CGImageRef in memory if the original preview was in view (_displayCount > 0), but we lose this information when we update from placeholder preview to empty preview. We could maybe bring it along in some form, or we could make OUIDocumentPreview instances mutable. On the other hand, there are other race conditions where we can end up with a CGImageRef loaded and a _displayCount==0 (for example, when async image loading sets _image after the preview has scrolled off screen -- though that shouldn't happen since we currently wait for async image loading when calling -image). At any rate, we'll have a separate cleanup pass for previews that end up not being shown in screen.
            if (DiscardHiddenPreviewsTimer == nil) {
                OBASSERT([NSThread isMainThread]); // checked above, but just in case that changes...
                DiscardHiddenPreviewsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_discardHiddenPreviewsTimerFired:) userInfo:nil repeats:NO];
            }
            
            CGImageRetain(image); // Nail this down while we wait for the preview cache operation to finish

            dispatch_async(PreviewCacheOperationQueue, ^{
#ifdef OMNI_ASSERTIONS_ON
                {
                    // If the incomming image is not nil, we should either have nothing in our cache, or should have some form of placeholder. We shouldn't be replacing valid previews (those should get a new date and thus a new cache key).
                    OUIDocumentPreview *existingPreview = [PreviewFileNameToPreview objectForKey:previewFilename];
                    OBASSERT_IF(image,
                                (existingPreview == nil || // nothing in the cache
                                 existingPreview.exists == NO || // cached missing value
                                 existingPreview.empty), // cached empty file
                                @"We should not have an existingPreview if we hav been giving an imageRef.");
                }
#endif
                
                // Allow caching negative results for when there is an error generating previews (maybe the document couldn't be read, for example).
                // Avoid reloading the image state from disk (and the I/O probably won't be finished).
                OUIDocumentPreview *preview = [[OUIDocumentPreview alloc] _initWithFileURL:fileURL date:date landscape:landscape previewURL:previewURL exists:YES empty:(image == NULL)];
                DEBUG_PREVIEW_CACHE(@"Generated preview %@=%p for %@ %@ landscape:%d", [previewURL lastPathComponent], preview, fileURL, [date xmlString], landscape);
                
                preview.image = image;
                DEBUG_PREVIEW_CACHE(@"  yielded generated image to preview");
            
                CGImageRelease(image);

                [PreviewFileNameToPreview setObject:preview forKey:previewFilename];
            });
        }
    });
}

+ (void)_discardHiddenPreviewsTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION(DiscardHiddenPreviewsTimer == timer);
    
    DiscardHiddenPreviewsTimer = nil;
    
    [self discardHiddenPreviews];
}

+ (void)performAsynchronousPreviewOperation:(void (^)(void))block;
{
    OBASSERT([NSOperationQueue currentQueue] != PreviewCacheReadWriteQueue);
    
    dispatch_async(PreviewCacheOperationQueue, block);
}

+ (void)afterAsynchronousPreviewOperation:(void (^)(void))block;
{
    NSOperationQueue *callingQueue = [NSOperationQueue currentQueue];
    OBASSERT(callingQueue != PreviewCacheReadWriteQueue);
    // dispatch_get_current_queue() is deprecated, sadly.
    //OBASSERT(dispatch_get_current_queue() != PreviewCacheOperationQueue);

    // This is lame, but since this queue is concurrent, we can't add an operation and daisy chain the main queue callback off that.
    [PreviewCacheReadWriteQueue waitUntilAllOperationsAreFinished];
    
    block = [block copy];
    
    if (block) {
        dispatch_async(PreviewCacheOperationQueue, ^{
            [callingQueue addOperationWithBlock:block];
        });
    }
}

+ (BOOL)hasPreviewForFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    __block OUIDocumentPreview *preview = nil;
    
    dispatch_sync(PreviewCacheOperationQueue, ^{
        if (!PreviewFileNameToPreview) {
            OBASSERT_NOT_REACHED("Asking about previews before the cache is loaded?");
            return;
        }
        NSString *previewFilename = [self _filenameForPreviewOfFileURL:fileURL date:date withLandscape:landscape];
        preview = [PreviewFileNameToPreview objectForKey:previewFilename];
    });
    
//    OBASSERT(preview.exists);
    return preview.exists;
}

static void _removeUsedPreviewFileURLs(Class self, NSMutableSet *unusedPreviewFilenames, NSURL *fileURL, NSDate *date)
{
    NSString *previewFilename;
    
    if ((previewFilename = [self _filenameForPreviewOfFileURL:fileURL date:date withLandscape:YES]))
        [unusedPreviewFilenames removeObject:previewFilename];
    if ((previewFilename = [self _filenameForPreviewOfFileURL:fileURL date:date withLandscape:NO]))
        [unusedPreviewFilenames removeObject:previewFilename];
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
    
    for (OFSDocumentStoreFileItem *fileItem in fileItems)
        _removeUsedPreviewFileURLs(self, unusedPreviewFilenames, fileItem.fileURL, fileItem.fileModificationDate);
    
    DEBUG_PREVIEW_CACHE(@"Removing unused previews: %@", unusedPreviewFilenames);
    
    for (NSString *previewFilename in unusedPreviewFilenames) {
        __autoreleasing NSError *removeError = nil;
        NSURL *unusedPreviewURL = [previewDirectoryURL URLByAppendingPathComponent:previewFilename];
        if (![[NSFileManager defaultManager] removeItemAtURL:unusedPreviewURL error:&removeError])
            NSLog(@"Error removing %@: %@", [unusedPreviewURL absoluteString], [removeError toPropertyList]);
    }
}

+ (NSString *)_filenameForPreviewOfFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
{
    // We use the full URL here so that we can build previews for documents with the same name. For example, conflict versions will likely have the same path component and possibly the same date (since the date resolution on the iPad is low). Even if we did use the last path component, we would have to use the whole thing (for Foo.oo3 and Foo.opml).
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
    
    // Make sure we got all the transformations needed
    // _normalizeURL() doesn't work on files that don't exist (and this is called after a file has moved).
    //OBASSERT([urlString isEqual:[[_normalizeURL(fileURL) absoluteString] stringByRemovingSuffix:@"/"]]);
    
    NSString *fileName = [[[urlString dataUsingEncoding:NSUTF8StringEncoding] sha1Signature] unadornedLowercaseHexString];
    
    // Unique it by date and size/landscape
    NSString *dateString = [date xmlString];
    fileName = [fileName stringByAppendingFormat:@"-%@-%@", dateString, landscape ? @"landscape" : @"portrait"];
    
    fileName = [fileName stringByAppendingPathExtension:@"jpg"];
    
    return fileName;
}

+ (NSURL *)fileURLForPreviewOfFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION(date);

    return _previewURLWithFilename([self _filenameForPreviewOfFileURL:fileURL date:date withLandscape:landscape]);
}

static CGImageRef _copyPlaceholderPreviewImage(Class self, Class documentClass, NSURL *fileURL, BOOL landscape, NSURL *previewURL) CF_RETURNS_RETAINED;
static CGImageRef _copyPlaceholderPreviewImage(Class self, Class documentClass, NSURL *fileURL, BOOL landscape, NSURL *previewURL)
{
    NSString *placeholderImageName = [documentClass placeholderPreviewImageNameForFileURL:fileURL landscape:landscape];
    if (!placeholderImageName) {
        OBASSERT_NOT_REACHED("No default preview image registered?");
        return NULL;
    }

    __block CGImageRef result = NULL;
    
    // We fiddle with global caches, so only one operation can be touching this at once
    [PreviewPlaceholderOperationQueue addOperationWithBlock:^{
        
        // Cache a single copy of the badged placeholder preview image in this orientation
        CGImageRef badgedImage;
        {
            NSString *cacheKey = [NSString stringWithFormat:@"%@-%@", landscape ? @"L" : @"P", placeholderImageName];
            
            if (BadgedPlaceholderPreviewImageCache)
                badgedImage = (CGImageRef)CFDictionaryGetValue(BadgedPlaceholderPreviewImageCache, (__bridge const void *)(cacheKey));
            else
                badgedImage = NULL;
            
            if (!badgedImage) {
                // Badge the placeholder image onto a white sheet of paper and cache that image.
                CGSize size = [self maximumPreviewSizeForLandscape:landscape];
                CGFloat scale = [OUIDocumentPreview previewImageScale];
                size.width = floor(size.width * scale);
                size.height = floor(size.height * scale);
                
                UIGraphicsBeginImageContextWithOptions(size, YES/*opaque*/, 0);
                {
                    CGRect paperRect = CGRectMake(0, 0, size.width, size.height);
                    
                    [[UIColor whiteColor] set];
                    UIRectFill(paperRect);
                    
                    CGImageRef previewImage = [[UIImage imageNamed:placeholderImageName] CGImage];
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
                    
                    badgedImage = [UIGraphicsGetImageFromCurrentImageContext() CGImage];
                }
                UIGraphicsEndImageContext();
                
                if (!BadgedPlaceholderPreviewImageCache)
                    BadgedPlaceholderPreviewImageCache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &CFTypeDictionaryValueCallbacks);
                
                CFDictionarySetValue(BadgedPlaceholderPreviewImageCache, (__bridge const void *)(cacheKey), badgedImage);
                DEBUG_PREVIEW_CACHE(@"Built badged placeholder preview image %@ with \"%@\" for %@", badgedImage, cacheKey, previewURL);
            } else {
                DEBUG_PREVIEW_CACHE(@"Using previously generated badged placeholder preview image with \"%@\" for %@", cacheKey, previewURL);
            }
        }
    
        result = badgedImage;
        if (result)
            CFRetain(result); // Will pass this ref back to the caller
    }];
    
    [PreviewPlaceholderOperationQueue waitUntilAllOperationsAreFinished];
    
    return result;
}

+ (OUIDocumentPreview *)makePreviewForDocumentClass:(Class)documentClass fileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
{
    OBPRECONDITION([NSThread isMainThread]); // We might update PreviewImageByURL for placeholders (could fork just the cache update to the main thread if needed).

    __block OUIDocumentPreview *preview = nil;
    
    dispatch_sync(PreviewCacheOperationQueue, ^{
        NSString *previewFilename = [self _filenameForPreviewOfFileURL:fileURL date:date withLandscape:landscape];
        preview = [PreviewFileNameToPreview objectForKey:previewFilename];
        
        if (!preview) {
            // This can happen when adding a new document from iTunes -- there may be an in flight async registration of the preview that hasn't finished yet. Just make up a placeholder.
            NSURL *previewURL = _previewURLWithFilename(previewFilename);
            preview = [[self alloc] _initWithFileURL:fileURL date:date landscape:landscape previewURL:previewURL exists:NO empty:YES];
        }
    });

    return preview;
}

static void _copyPreview(Class self, NSURL *sourceFileURL, NSDate *sourceDate, NSURL *targetFileURL, NSDate *targetDate, BOOL landscape)
{
    OBPRECONDITION([NSThread isMainThread]);
    
    NSURL *sourcePreviewFileURL = [self fileURLForPreviewOfFileURL:sourceFileURL date:sourceDate withLandscape:landscape];
    NSURL *targetPreviewFileURL = [self fileURLForPreviewOfFileURL:targetFileURL date:targetDate withLandscape:landscape];
    
    DEBUG_PREVIEW_CACHE(@"copying preview %@ -> %@", sourcePreviewFileURL, targetPreviewFileURL);
    
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    
    if ([defaultManager fileExistsAtPath:[sourcePreviewFileURL path]])
        return;
    
    // Copy the file (if any)
    __autoreleasing NSError *copyError = nil;
    if (![defaultManager copyItemAtURL:sourcePreviewFileURL toURL:targetPreviewFileURL error:&copyError]) {
        if (![copyError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST])
            NSLog(@"Error copying preview from %@ to %@: %@", sourcePreviewFileURL, targetPreviewFileURL, [copyError toPropertyList]);
    }
    
    // Register the new preview if the source had it loaded (most likely since the user is operating on it).
    OUIDocumentPreview *sourcePreview = [PreviewFileNameToPreview objectForKey:[sourcePreviewFileURL lastPathComponent]];
    OUIDocumentPreview *targetPreview = [[OUIDocumentPreview alloc] _initWithFileURL:targetFileURL date:targetDate landscape:landscape previewURL:targetPreviewFileURL];
    
    if (sourcePreview->_image) // Don't force loading; just do it if already loaded
        targetPreview.image = sourcePreview->_image;

    if (!PreviewFileNameToPreview)
        PreviewFileNameToPreview = [[NSMutableDictionary alloc] init];
    [PreviewFileNameToPreview setObject:targetPreview forKey:[targetPreviewFileURL lastPathComponent]];
}

+ (void)cachePreviewImagesForFileURL:(NSURL *)targetFileURL date:(NSDate *)targetDate
            byDuplicatingFromFileURL:(NSURL *)sourceFileURL date:(NSDate *)sourceDate;
{
    DEBUG_PREVIEW_CACHE(@"copying preview %@ / %@ -> %@ / %@", [sourceDate xmlString], sourceFileURL, targetFileURL, [targetDate xmlString]);

    targetFileURL = _normalizeURL(targetFileURL);
    sourceFileURL = _normalizeURL(sourceFileURL);
    
    dispatch_sync(PreviewCacheOperationQueue, ^{
        _copyPreview(self, sourceFileURL, sourceDate, targetFileURL, targetDate, YES/*landscape*/);
        _copyPreview(self, sourceFileURL, sourceDate, targetFileURL, targetDate, NO/*landscape*/);
    });
}

static void _movePreview(Class self, NSURL *sourceFileURL, NSDate *sourceDate, NSURL *targetFileURL, NSDate *targetDate, BOOL landscape)
{
    NSURL *sourcePreviewFileURL = [self fileURLForPreviewOfFileURL:sourceFileURL date:sourceDate withLandscape:landscape];
    NSURL *targetPreviewFileURL = [self fileURLForPreviewOfFileURL:targetFileURL date:targetDate withLandscape:landscape];
    
    DEBUG_PREVIEW_CACHE(@"moving preview from %@ %@ -- %@", sourceFileURL, [sourceDate xmlString], sourcePreviewFileURL);
    DEBUG_PREVIEW_CACHE(@"  to %@ %@ -- %@", targetFileURL, [targetDate xmlString], targetPreviewFileURL);
    
    // Move the file (if any)
    __autoreleasing NSError *moveError = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:sourcePreviewFileURL toURL:targetPreviewFileURL error:&moveError]) {
        if (![moveError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) // Preview not written yet? Maybe we have a rename of a file racing with writing a generated preview for the first name?
            NSLog(@"Error moving preview from %@ to %@: %@", sourcePreviewFileURL, targetPreviewFileURL, [moveError toPropertyList]);
    }
    
    // Move the preview in the cache
    NSString *sourcePreviewFilename = [sourcePreviewFileURL lastPathComponent];
    NSString *targetPreviewFilename = [targetPreviewFileURL lastPathComponent];
    
    OUIDocumentPreview *preview = [PreviewFileNameToPreview objectForKey:sourcePreviewFilename];
    if (preview) {
        if (!PreviewFileNameToPreview)
            PreviewFileNameToPreview = [[NSMutableDictionary alloc] init];
        
        [PreviewFileNameToPreview setObject:preview forKey:targetPreviewFilename];
        [PreviewFileNameToPreview removeObjectForKey:sourcePreviewFilename];
        
        [preview _didMoveToFileURL:targetFileURL date:targetDate previewURL:targetPreviewFileURL];
        
        DEBUG_PREVIEW_CACHE(@"  moved preview %p from key %@ to %@", preview, sourcePreviewFilename, targetPreviewFilename);
    }
}

+ (void)updateCacheAfterFileURL:(NSURL *)sourceFileURL withDate:(NSDate *)sourceDate didMoveToURL:(NSURL *)targetFileURL;
{
    sourceFileURL = _normalizeURL(sourceFileURL);
    targetFileURL = _normalizeURL(targetFileURL);
    
    dispatch_sync(PreviewCacheOperationQueue, ^{
        _movePreview(self, sourceFileURL, sourceDate, targetFileURL, sourceDate, YES/*landscape*/);
        _movePreview(self, sourceFileURL, sourceDate, targetFileURL, sourceDate, NO/*landscape*/);
    });
}

+ (CGSize)maximumPreviewSizeForLandscape:(BOOL)landscape;
{
    static CGSize kLandscapePreviewSize = (CGSize){186, 140}; // 1.3285 vs. 1024/768 = 1.3333
    static CGSize kPortraitPreviewSize = (CGSize){174, 225}; // 0.7733 vs 768/1024 = 0.7500
    
    return landscape ? kLandscapePreviewSize : kPortraitPreviewSize;
}

// Returns the scale at which the preview image should be rendered when saving to disk. It's on screen size must fit within +maximumPreviewSizeForLandscape:, but the image should be scaled up by this amount (and will be descaled when rendered at the normal magnification in the document picker).
+ (CGFloat)previewImageScale;
{
    return 2.0 * [[UIScreen mainScreen] scale];
}

- _initWithFileURL:(NSURL *)fileURL date:(NSDate *)date landscape:(BOOL)landscape previewURL:(NSURL *)previewURL exists:(BOOL)exists empty:(BOOL)empty;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION(date || !exists); // Might represent a non-downloaded cloud item.
    OBPRECONDITION(previewURL);
    
    if (!(self = [super init]))
        return nil;
    
    _fileURL = fileURL;
    _date = [date copy];
    _landscape = landscape;
    _previewURL = previewURL;
    _exists = exists;
    _empty = empty;
    
    return self;
}

- _initWithFileURL:(NSURL *)fileURL date:(NSDate *)date landscape:(BOOL)landscape previewURL:(NSURL *)previewURL;
{
    // We look these up immediately so that +hasPreviewForFileURL:date:withLandscape: can check our properties
    // Don't ask the URL via getResourceValue:forKey:error: since that can return a cached value. We might have just written the image during preview generation after previously having looked up the empty placeholder that is written prior to preview generation.

    BOOL exists = YES;
    __autoreleasing NSError *attributesError = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[previewURL absoluteURL] path] error:&attributesError];
    if (!attributes) {
        if ([attributesError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT] ||
            [attributesError hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError]) {
            // No preview generated yet
        } else {
            NSLog(@"Error getting attributes of preview image %@: %@", previewURL, [attributesError toPropertyList]);
        }
        exists = NO; // either way, don't try to load the file
    }
    BOOL empty = ([attributes fileSize] == 0);
    
    return [self _initWithFileURL:fileURL date:date landscape:landscape previewURL:previewURL exists:exists empty:empty];
}

- (void)dealloc;
{
    if (_image)
        CFRelease(_image);
    
    OBASSERT(_displayCount == 0); // should have put a -retain on it.
    OBASSERT(!_loadOperation || [_loadOperation isFinished]);
}

@synthesize fileURL = _fileURL;
@synthesize date = _date;
@synthesize landscape = _landscape;
@synthesize superseded = _superseded;

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

- (OUIDocumentPreviewType)type;
{
    [self _ensureLoaded];
    return _type;
}

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
            DEBUG_PREVIEW_CACHE(@"Loaded existing preview for %@ %@ %d -- %@", _fileURL, [_date xmlString], _landscape, _previewURL);
            _type = OUIDocumentPreviewTypeRegular;
            return;
        }
        // fall through to create a placeholder
    }

    Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:_fileURL];
    
    if (_empty) {
        // There is a zero length file or was an error reading the image
        _type = OUIDocumentPreviewTypeEmpty;
        _image = _copyPlaceholderPreviewImage([self class], documentClass, _fileURL, _landscape, _previewURL); // returns +1 CF
        if (_image) {
            DEBUG_PREVIEW_CACHE(@"Caching badged placeholder for empty %@ %@ %d -- %@", _fileURL, [_date xmlString], _landscape, _previewURL);
            return;
        }
        // fall through to create a placeholder
    }
    
    _type = OUIDocumentPreviewTypePlaceholder;
    _image = _copyPlaceholderPreviewImage([self class], documentClass, _fileURL, _landscape, _previewURL); // returns +1 CF
    DEBUG_PREVIEW_CACHE(@"Caching badged placeholder for missing %@ %@ %d -- %@", _fileURL, [_date xmlString], _landscape, _previewURL);
    
    OBPOSTCONDITION(_image);
}

- (void)startLoadingPreview;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_image)
        return; // Already loaded!
    
    if (_loadOperation)
        return;
    
    DEBUG_PREVIEW_CACHE("Start loading image");

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
            DEBUG_PREVIEW_CACHE("Cancelling image load operation");
            [_loadOperation cancel];
        }
        _loadOperation = nil;
    }
    
    if (_image) {
        DEBUG_PREVIEW_CACHE("Discarding loaded image");

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
    //DEBUG_PREVIEW_CACHE("Increment display count %p, now %ld", self, _displayCount);
}

- (void)decrementDisplayCount;
{
    OBPRECONDITION(_displayCount > 0, "Missing call to -incrementDisplayCount");
    
    if (_displayCount > 0) {
        _displayCount--;
        if (_displayCount == 0)
            [self discardLoadedPreview];
    }
    //DEBUG_PREVIEW_CACHE("Decrement display count %p, now %ld", self, _displayCount);
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
    
    DEBUG_PREVIEW_CACHE(@"Drawing scaled preview %@ -> %@", NSStringFromCGSize(CGSizeMake(width, height)), NSStringFromCGRect(rect));
    
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
    
    return [NSString stringWithFormat:@"<%@:%p item:%@ date:%@ image:%p landscape:%d type:%@>", NSStringFromClass([self class]), self, [_fileURL absoluteString], [_date xmlString], _image, _landscape, typeString];
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

- (void)_didMoveToFileURL:(NSURL *)fileURL date:(NSDate *)date previewURL:(NSURL *)previewURL;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION(date);
    OBPRECONDITION(previewURL);
    OBPRECONDITION([[[self class] fileURLForPreviewOfFileURL:fileURL date:date withLandscape:_landscape] isEqual:previewURL]);

    _fileURL = [[fileURL absoluteURL] copy];
    
    _date = date;
    
    _previewURL = [[_previewURL absoluteURL] copy];
}

@end
