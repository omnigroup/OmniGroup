// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPreview.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIDocument.h>
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

@interface OUIDocumentPreview ()
+ (NSURL *)_previewDirectoryURL;
- _initWithFileURL:(NSURL *)fileURL date:(NSDate *)date image:(CGImageRef)image landscape:(BOOL)landscape type:(OUIDocumentPreviewType)type;
@end

@implementation OUIDocumentPreview
{
    NSURL *_fileURL;
    NSDate *_date;
    CGImageRef _image;
    BOOL _landscape;
    OUIDocumentPreviewType _type;
    BOOL _superseded;
}

// Concurrent background queue for loading/decoding preview images
static dispatch_queue_t PreviewCacheQueue;

// A cache of normalized URL -> {CGImageRef, kOUIDocumentPreviewTypeEmptyMarker}. If a preview image file exists but is zero length or can't be read, there will be an entry with a value of kOUIDocumentPreviewTypeEmptyMarker.
// Main thread only.
static CFDictionaryRef PreviewImageByURL;

// A cache of placeholder images badged onto white rectangles for use when we are still generating a preview
// Main thread only.
static CFMutableDictionaryRef BadgedPlaceholderPreviewImageCache;

static const CFDictionaryValueCallBacks CFTypeDictionaryValueCallbacks = {
    .retain = OFCFTypeRetain,
    .release = OFCFTypeRelease,
    .copyDescription = OFCFTypeCopyDescription,
    .equal = OFCFTypeIsEqual
};

static CFStringRef kOUIDocumentPreviewTypeEmptyMarker = CFSTR("kOUIDocumentPreviewTypeEmptyMarker");

+ (void)initialize;
{
    OBINITIALIZE;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PreviewCacheQueue = dispatch_queue_create("com.omnigroup.OmniUI.OUIDocumentPreview.cache", DISPATCH_QUEUE_CONCURRENT);
    });
}

static NSURL *_normalizeURL(NSURL *url)
{
    // Need consistent mapping of /private/var/mobil vs /var/mobile.
    return [[url URLByResolvingSymlinksInPath] URLByStandardizingPath];
}

static CGImageRef _loadImageFromURL(NSURL *imageURL) CF_RETURNS_RETAINED;
static CGImageRef _loadImageFromURL(NSURL *imageURL)
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             (id)kUTTypeJPEG, (id)kCGImageSourceTypeIdentifierHint,
                             nil];

    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)imageURL, (CFDictionaryRef)options);
    if (!imageSource) {
        NSLog(@"Error loading preview image from %@: Unable to create image source", imageURL);
        return NULL;
    }
    
    if (CGImageSourceGetCount(imageSource) < 1) {
        NSLog(@"Error loading preview image from %@: No images found in source", imageURL);
        CFRelease(imageSource);
        return NULL;
    }
    
    options = [NSDictionary dictionaryWithObjectsAndKeys:
               (id)kCFBooleanTrue, (id)kCGImageSourceShouldCache,
               nil];
    
    CGImageRef image = CGImageSourceCreateImageAtIndex(imageSource, 0/*index*/, (CFDictionaryRef)options);
    CFRelease(imageSource);
    
    if (!image) {
        NSLog(@"Error loading preview image from %@: Unable to create image from source", imageURL);
        return NULL;
    }
    
    // Force decoding of the JPEG data up front so that scrolling in the document picker doesn't chug the first time an image comes on screen
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, 1, 1, 8/*bitsPerComponent*/, 4/*bytesPerRow*/, colorSpace, kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);
    
    OBASSERT(ctx);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), image);
        CGContextRelease(ctx);
    }
    
    return image;
}

+ (void)updatePreviewImageCacheWithCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    completionHandler = [[completionHandler copy] autorelease]; // capture scope
    
    // Gather the list of all preview URLs
    NSArray *previewURLs;
    {
        NSError *error = nil;
        NSURL *previewDirectoryURL = [self _previewDirectoryURL];
        
        previewURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:previewDirectoryURL
                                                    includingPropertiesForKeys:[NSArray arrayWithObjects:NSURLFileSizeKey, nil]
                                                                       options:0
                                                                         error:&error];
        if (!previewURLs) {
            NSLog(@"Error scanning preview directory %@: %@", previewDirectoryURL, [error toPropertyList]);
            if (completionHandler)
                completionHandler();
            return;
        }
    }
          
    CFMutableDictionaryRef updatedPreviewImageByURL = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &CFTypeDictionaryValueCallbacks);
    
    for (NSURL *previewURL in previewURLs) {
        // NSFileManager can return non-normalized URLs when we ask it for the contents of a directory.
        previewURL = _normalizeURL(previewURL);
        
        // Early out for previously cached images
        if (PreviewImageByURL) {
            CGImageRef existingImage = (CGImageRef)CFDictionaryGetValue(PreviewImageByURL, previewURL);
            if (existingImage) {
                OBASSERT(existingImage == (CGImageRef)kOUIDocumentPreviewTypeEmptyMarker || CFGetTypeID(existingImage) == CGImageGetTypeID());
                CFDictionaryAddValue(updatedPreviewImageByURL, previewURL, existingImage);
                continue;
            }
        }
        
        dispatch_async(PreviewCacheQueue, ^{
            CGImageRef image = NULL;
            
            // Handle zero length preview placeholders
            NSNumber *imageSize = nil;
            NSError *resourceError = nil;
            if (![previewURL getResourceValue:&imageSize forKey:NSURLFileSizeKey error:&resourceError]) {
                NSLog(@"Error getting file size of preview image %@: %@", previewURL, [resourceError toPropertyList]);
            }
            
            if ([imageSize unsignedLongLongValue] > 0)
                image = _loadImageFromURL(previewURL);
            
            // Finally, record our results
            main_async(^{
                CFTypeRef value = image ? (CFTypeRef)image : (CFTypeRef)kOUIDocumentPreviewTypeEmptyMarker;
                CFDictionaryAddValue(updatedPreviewImageByURL, previewURL, value);
                if (image)
                    CFRelease(image);
            });
        });
    }
    
    // Wait for all the background operations
    dispatch_barrier_async(PreviewCacheQueue, ^{
        // Wait for the last of the main async additions to the cache
        main_async(^{
            if (PreviewImageByURL)
                CFRelease(PreviewImageByURL);
            PreviewImageByURL = CFDictionaryCreateCopy(kCFAllocatorDefault, updatedPreviewImageByURL);
            CFRelease(updatedPreviewImageByURL);
            
            PREVIEW_DEBUG(@"Preview image cache now %@", PreviewImageByURL);
            
            if (completionHandler)
                completionHandler();
        });
    });
}

+ (void)flushPreviewImageCache;
{
    PREVIEW_DEBUG(@"Flushing preview cache");

    // Make sure any previous cache loading/clear has finished
    dispatch_barrier_async(PreviewCacheQueue, ^{
        main_async(^{
            if (PreviewImageByURL) {
                CFRelease(PreviewImageByURL);
                PreviewImageByURL = NULL;
            }
            
            if (BadgedPlaceholderPreviewImageCache) {
                CFRelease(BadgedPlaceholderPreviewImageCache);
                BadgedPlaceholderPreviewImageCache = nil;
            }
        });
    });
}

// This method lets documents synchronously update the cache with one or more just-generated preview images (rather than doing a full async rescan).
+ (void)cachePreviewImages:(void (^)(OUIDocumentPreviewCacheImage cacheImage))cachePreviews;
{
    OBPRECONDITION(cachePreviews);
    OBPRECONDITION([NSThread isMainThread]);

    CFMutableDictionaryRef updatedPreviews;
    if (PreviewImageByURL)
        updatedPreviews = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, PreviewImageByURL);
    else
        updatedPreviews = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &CFTypeDictionaryValueCallbacks);

    __block BOOL didAdd = NO;
    
    cachePreviews(^(CGImageRef image, NSURL *previewURL){
        OBASSERT([previewURL isEqual:_normalizeURL(previewURL)]);
#ifdef OMNI_ASSERTIONS_ON
        {
            // We should either have nothing in our cache, or should have some form of placeholder. We shouldn't be replacing valid previews (those should get a new date and thus a new cache key).
            CFTypeRef existingValue = (CFTypeRef)CFDictionaryGetValue(updatedPreviews, previewURL);
            OBASSERT(existingValue == NULL || existingValue == kOUIDocumentPreviewTypeEmptyMarker || (BadgedPlaceholderPreviewImageCache && CFDictionaryGetCountOfValue(BadgedPlaceholderPreviewImageCache, existingValue) == 1));
        }
#endif
        
        // Allow caching negative results for when there is an error writing previews.
        if (!image)
            image = (CGImageRef)kOUIDocumentPreviewTypeEmptyMarker;
        
        // CFDictionarySetValue since we might be replacing a placeholder.
        CFDictionarySetValue(updatedPreviews, previewURL, image);
        didAdd = YES;
    });

    if (didAdd) {
        if (PreviewImageByURL)
            CFRelease(PreviewImageByURL);
        PreviewImageByURL = CFDictionaryCreateCopy(kCFAllocatorDefault, updatedPreviews);
    }
    CFRelease(updatedPreviews);
}

+ (BOOL)hasPreviewForFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
{
    if (!PreviewImageByURL)
        return NO;
    
    NSURL *previewURL = [self fileURLForPreviewOfFileURL:fileURL date:date withLandscape:landscape];
    
    CFTypeRef value = CFDictionaryGetValue(PreviewImageByURL, previewURL);
    
    // Return YES even if this is a cached failure (empty file). We don't want to try to redo the preview generation until the file's date changes.
    return value != nil;
}

+ (void)deletePreviewsNotUsedByFileItems:(id <NSFastEnumeration>)fileItems;
{
    NSError *error = nil;
    NSArray *existingPreviewURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self _previewDirectoryURL] includingPropertiesForKeys:[NSArray array] options:0 error:&error];
    if (!existingPreviewURLs) {
        NSLog(@"Error finding existing previews: %@", [error toPropertyList]);
        return;
    }
    
    NSMutableSet *unusedPreviewURLs = [NSMutableSet set];
    for (NSURL *existingPreviewURL in existingPreviewURLs) {
        // NSFileManager can return non-normalized URLs when we ask it for the contents of a directory.
        [unusedPreviewURLs addObject:_normalizeURL(existingPreviewURL)];
    }
    
    for (OFSDocumentStoreFileItem *fileItem in fileItems) {
        NSURL *fileURL = fileItem.fileURL;
        NSDate *date = fileItem.date;
        
        NSURL *previewURL;
        
        if ((previewURL = [self fileURLForPreviewOfFileURL:fileURL date:date withLandscape:YES]))
            [unusedPreviewURLs removeObject:previewURL];
        if ((previewURL = [self fileURLForPreviewOfFileURL:fileURL date:date withLandscape:NO]))
            [unusedPreviewURLs removeObject:previewURL];
    }
    
    PREVIEW_DEBUG(@"Removing unused previews: %@", unusedPreviewURLs);
    
    for (NSURL *unusedPreviewURL in unusedPreviewURLs) {
        NSError *removeError = nil;
        if (![[NSFileManager defaultManager] removeItemAtURL:unusedPreviewURL error:&removeError])
            NSLog(@"Error removing %@: %@", [unusedPreviewURL absoluteString], [removeError toPropertyList]);
    }
}

+ (NSURL *)fileURLForPreviewOfFileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION(date);
    
    NSURL *directoryURL = [self _previewDirectoryURL];
    
    // We use the full URL here so that we can build previews for documents with the same name. For example, conflict versions will likely have the same path component and possibly the same date (since the date resolution on the iPad is low). Even if we did use the last path component, we would have to use the whole thing (for Foo.oo3 and Foo.opml).
    NSString *urlString = [fileURL absoluteString];
    if ([urlString hasSuffix:@"/"])
        urlString = [urlString stringByRemovingSuffix:@"/"];
    
    NSString *fileName = [[[urlString dataUsingEncoding:NSUTF8StringEncoding] sha1Signature] unadornedLowercaseHexString];
    
    // Unique it by date and size/landscape
    NSString *dateString = [date xmlString];
    fileName = [fileName stringByAppendingFormat:@"-%@-%@", dateString, landscape ? @"landscape" : @"portrait"];
    
    fileName = [fileName stringByAppendingPathExtension:@"jpg"];
    
    NSURL *previewURL = [[directoryURL URLByAppendingPathComponent:fileName] absoluteURL];
    PREVIEW_DEBUG(@"fileURL %@ -> previewURL %@", fileURL, previewURL);
    
    // The normalization is too slow to do here, but we shouldn't need to since +_previewDirectoryURL returns a normalized base URL and nothing we append should mess it up.
    OBPOSTCONDITION([previewURL isEqual:_normalizeURL(previewURL)]);
    
    return previewURL;
}

static CGImageRef _cachePlaceholderPreviewImage(Class self, Class documentClass, NSURL *fileURL, BOOL landscape, NSURL *previewURL)
{
    OBPRECONDITION([NSThread isMainThread]); // We fiddle with global caches

    NSString *placeholderImageName = [documentClass placeholderPreviewImageNameForFileURL:fileURL landscape:landscape];
    if (!placeholderImageName) {
        OBASSERT_NOT_REACHED("No default preview image registered?");
        return NULL;
    }
    
    // First, cache a single copy of the badged placeholder preview image in this orientation
    CGImageRef badgedImage;
    {
        NSString *cacheKey = [NSString stringWithFormat:@"%@-%@", landscape ? @"L" : @"P", placeholderImageName];
        
        if (BadgedPlaceholderPreviewImageCache)
            badgedImage = (CGImageRef)CFDictionaryGetValue(BadgedPlaceholderPreviewImageCache, cacheKey);
        else
            badgedImage = NULL;
        
        if (!badgedImage) {
            // Badge the placeholder image onto a white sheet of paper and cache that image.
            CGSize size = [self maximumPreviewSizeForLandscape:landscape];
            CGFloat scale = [OUIDocumentPreview previewImageScale];
            size.width = floor(size.width * scale);
            size.height = floor(size.height * scale);

            UIGraphicsBeginImageContext(size);
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
                    NSLog(@"imageSize = %@", NSStringFromCGSize(imageSize));
                    
                    CGRect targetImageRect = OQCenteredIntegralRectInRect(paperRect, imageSize);
                
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

            CFDictionarySetValue(BadgedPlaceholderPreviewImageCache, cacheKey, badgedImage);
            PREVIEW_DEBUG(@"Built badged placeholder preview image %@ with \"%@\" for %@", badgedImage, cacheKey, previewURL);
        } else {
            PREVIEW_DEBUG(@"Using previously generated badged placeholder preview image with \"%@\" for %@", cacheKey, previewURL);
        }
    }
    
    // Then register this badged image as the preview for this specific file (so we can only render the badged preview once).
    [self cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage) {
        cacheImage(badgedImage, previewURL);
    }];
    
    return badgedImage;
}

+ (OUIDocumentPreview *)makePreviewForDocumentClass:(Class)documentClass fileURL:(NSURL *)fileURL date:(NSDate *)date withLandscape:(BOOL)landscape;
{
    OBPRECONDITION([NSThread isMainThread]); // We might update PreviewImageByURL for placeholders (could fork just the cache update to the main thread if needed).

    NSURL *previewURL = [self fileURLForPreviewOfFileURL:fileURL date:date withLandscape:landscape];
    
    CGImageRef previewImage = NULL;
    if (PreviewImageByURL)
        previewImage = (CGImageRef)CFDictionaryGetValue(PreviewImageByURL, previewURL);
    
    OUIDocumentPreviewType type;
    if (!previewImage) {
        // No preview known.
        type = OUIDocumentPreviewTypePlaceholder;
        previewImage = _cachePlaceholderPreviewImage(self, documentClass, fileURL, landscape, previewURL);
    } else if (previewImage == (CGImageRef)kOUIDocumentPreviewTypeEmptyMarker) {
        // There is a zero length file or was an error reading the image
        type = OUIDocumentPreviewTypeEmpty;
        previewImage = _cachePlaceholderPreviewImage(self, documentClass, fileURL, landscape, previewURL);
    } else {
        type = OUIDocumentPreviewTypeRegular;
    }
    
    OBASSERT(previewImage); // even if the placeholder is missing we should get back a white rect image.
    
    return [[[self alloc] _initWithFileURL:fileURL date:date image:previewImage landscape:landscape type:type] autorelease];
}

static void _copyPreview(Class self, NSURL *sourceFileURL, NSDate *sourceDate, NSURL *targetFileURL, NSDate *targetDate, OUIDocumentPreviewCacheImage cacheImage, BOOL landscape)
{
    NSURL *sourcePreviewFileURL = [self fileURLForPreviewOfFileURL:sourceFileURL date:sourceDate withLandscape:landscape];
    NSURL *targetPreviewFileURL = [self fileURLForPreviewOfFileURL:targetFileURL date:targetDate withLandscape:landscape];
    
    PREVIEW_DEBUG(@"copying preview %@ -> %@", sourcePreviewFileURL, targetPreviewFileURL);
    
    // Copy the file (if any)
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtURL:sourcePreviewFileURL toURL:targetPreviewFileURL error:&copyError]) {
        if (![copyError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST])
            NSLog(@"Error copying preview from %@ to %@: %@", sourcePreviewFileURL, targetPreviewFileURL, [copyError toPropertyList]);
    }
    
    // Register the CGImageRef (if any)
    CGImageRef image = (CGImageRef)CFDictionaryGetValue(PreviewImageByURL, sourcePreviewFileURL);
    if (image) {
        cacheImage(image, targetPreviewFileURL);
        PREVIEW_DEBUG(@"  registering image %@", image);
    }
}

+ (void)cachePreviewImagesForFileURL:(NSURL *)targetFileURL date:(NSDate *)targetDate
            byDuplicatingFromFileURL:(NSURL *)sourceFileURL date:(NSDate *)sourceDate;
{
    [self cachePreviewImages:^(OUIDocumentPreviewCacheImage cacheImage){
        _copyPreview(self, sourceFileURL, sourceDate, targetFileURL, targetDate, cacheImage, YES/*landscape*/);
        _copyPreview(self, sourceFileURL, sourceDate, targetFileURL, targetDate, cacheImage, NO/*landscape*/);
    }];
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
    return 2.0;
}

- _initWithFileURL:(NSURL *)fileURL date:(NSDate *)date image:(CGImageRef)image landscape:(BOOL)landscape type:(OUIDocumentPreviewType)type;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION(date);
    OBPRECONDITION(image);
    
    if (!(self = [super init]))
        return nil;

    _fileURL = [fileURL retain];
    _date = [date copy];
    _landscape = landscape;
    _type = type;
    
    _image = image;
    if (_image)
        CFRetain(_image);
    
    return self;
}

- (void)dealloc;
{
    [_fileURL release];
    [_date release];
    if (_image)
        CFRelease(_image);
    [super dealloc];
}

@synthesize fileURL = _fileURL;
@synthesize date = _date;
@synthesize landscape = _landscape;
@synthesize type = _type;
@synthesize superseded = _superseded;

@synthesize image = _image;

- (CGSize)size;
{
    if (!_image)
        return CGSizeZero;
    return CGSizeMake(CGImageGetWidth(_image), CGImageGetHeight(_image));
}

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
    
    PREVIEW_DEBUG(@"Drawing scaled preview %@ -> %@", NSStringFromCGSize(CGSizeMake(width, height)), NSStringFromCGRect(rect));
    
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
    
    return [NSString stringWithFormat:@"<%@:%p item:%@ date:%f image:%p landscape:%d type:%@>", NSStringFromClass([self class]), self, [_fileURL absoluteString], [_date timeIntervalSinceReferenceDate], _image, _landscape, typeString];
}

#pragma mark -
#pragma mark Private

+ (NSURL *)_previewDirectoryURL;
{
    static NSURL *previewDirectoryURL = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        
        NSFileManager *manager = [NSFileManager defaultManager];
        NSURL *caches = [manager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
        if (caches) {
            previewDirectoryURL = [_normalizeURL([caches URLByAppendingPathComponent:@"DocumentPreviews"]) retain];
            
            // Support for cleaning out all previews on launch.
#if 0 && defined(DEBUG_bungi)
            static BOOL firstUpdate = YES;
            if (firstUpdate) {
                firstUpdate = NO;
                
                NSLog(@"Removing all previews!");
                NSError *removeError;
                if (![manager removeItemAtURL:previewDirectoryURL error:&removeError]) {
                    if (![error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
                        NSLog(@"Unable to remove preview directory: %@", [removeError toPropertyList]);
                    }
                }
            }
#endif
            
            if (![manager createDirectoryAtURL:previewDirectoryURL withIntermediateDirectories:NO attributes:nil error:&error]) {
                if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST]) {
                    // All good
                } else {
                    [previewDirectoryURL release];
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
