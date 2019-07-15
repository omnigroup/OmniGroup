// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSImage-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <pthread.h>
#import <CoreImage/CIContext.h>

#import <OmniAppKit/OAVersion.h>

#include <stdlib.h>
#include <memory.h>


RCS_ID("$Id$")

NSString * const OADropDownTriangleImageName = @"OADropDownTriangle";
NSString * const OAInfoTemplateImageName = @"OAInfoTemplate";

@interface _OATintedImage : NSImage
@end

NSImage *OAImageNamed(NSString *name, NSBundle *bundle)
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(![NSString isEmptyString:name]);
    
    // If we get asked for an image in the app wrapper (or unspecified bundle, which we take to mean the app wrapper), just let +imageNamed: do its thing.
    if ((bundle == nil) || (bundle == [NSBundle mainBundle])) {
        return [NSImage imageNamed:name];
    }
    
    // +imageForResource: is documented to not cache. We used to use the +imageNamed: cache by setting our cache key as the name of the image so that future lookups would work. But, this makes xib loading unable to find the image. <bug:///86682> (Unassigned: Could not find image named 'OACautionIcon')
    static NSCache *imageCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageCache = [[NSCache alloc] init];
        imageCache.name = @"com.omnigroup.OmniAppKit.imageNamed_inBundle";
    });
    
    NSString *imageNameInCache = [NSString stringWithFormat:@"%@.%@", [bundle bundleIdentifier], name];
    NSImage *image = [imageCache objectForKey:imageNameInCache];
    if (![image isValid]) {
        // If we didn't find the image in the cache, actually try to load it from the bundle (using the original, unmangled name, which is the actual name of the resource), then name it, using our bundle-specific mangled name so that it will be cached without conflicting with any identically-named images in the app wrapper (or in other bundles).
        image = [bundle imageForResource:name];
        if (image) {
            [imageCache setObject:image forKey:imageNameInCache];
        }
    }

    return image;
}


@implementation NSImage (OAExtensions)

#ifdef DEBUG

// Photoshop likes to save files with non-integral DPI.  This can cause hard to find bugs later on, so lets just find out about this right away.
static id (*original_initWithContentsOfFile)(id __attribute((ns_consumed)) self, SEL _cmd, NSString *fileName);
static id (*original_initByReferencingFile)(id __attribute((ns_consumed)) self, SEL _cmd, NSString *fileName);
#ifdef DEBUG_NONINTEGRAL_IMAGE_SIZE
static id (*original_initWithSize)(id __attribute((ns_consumed)) self, SEL _cmd, NSSize size);
static id (*original_setSize)(id __attribute((ns_consumed)) self, SEL _cmd, NSSize size);
#endif

OBPerformPosing(^{
    Class self = objc_getClass("NSImage");
    original_initByReferencingFile = (typeof(original_initWithContentsOfFile))OBReplaceMethodImplementationWithSelector(self, @selector(initByReferencingFile:), @selector(_initByReferencingFile_replacement:));
    original_initWithContentsOfFile = (typeof(original_initWithContentsOfFile))OBReplaceMethodImplementationWithSelector(self, @selector(initWithContentsOfFile:), @selector(_initWithContentsOfFile_replacement:));
#ifdef DEBUG_NONINTEGRAL_IMAGE_SIZE
    original_initWithSize = (typeof(original_initWithSize))OBReplaceMethodImplementationWithSelector(self, @selector(initWithSize:), @selector(replacement_initWithSize:));
    original_setSize = (typeof(original_setSize))OBReplaceMethodImplementationWithSelector(self, @selector(setSize:), @selector(replacement_setSize:));
#endif
});

// If you run into these assertions, consider running the OAMakeImageSizeIntegral command line tool in your image (probably only reasonable for TIFF right now).

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (id)_initWithContentsOfFile_replacement:(NSString *)fileName;
{
    self = original_initWithContentsOfFile(self, _cmd, fileName);

    if (self == nil) {
        NSLog(@"%@: image unreadable", fileName);
        return nil;
    }
    
    NSSize size = [self size];

    if (size.width != rint(size.width) || size.height != rint(size.height))
        NSLog(@"Image %@ has non-integral size %@", fileName, NSStringFromSize(size));

    OBASSERT_IF(OFURLContainsURL([[NSBundle mainBundle] bundleURL], [NSURL fileURLWithPath:fileName]), size.width == rint(size.width) && size.height == rint(size.height), "Our resources should be integral-sized");
    return self;
}

// Called by +[NSImage imageNamed:]
- (id)_initByReferencingFile_replacement:(NSString *)fileName;
{
    if (fileName == nil) {
        return nil;
    }
    
    self = original_initByReferencingFile(self, _cmd, fileName);

    if (self == nil) {
        NSLog(@"%@: image unreadable", fileName);
        return nil;
    }

    NSSize size = [self size];

    if (size.width != rint(size.width) || size.height != rint(size.height))
        NSLog(@"Image %@ has non-integral size %@", fileName, NSStringFromSize(size));

    OBPOSTCONDITION(size.width == rint(size.width));
    OBPOSTCONDITION(size.height == rint(size.height));
    return self;
}
#pragma clang diagnostic pop

#ifdef DEBUG_NONINTEGRAL_IMAGE_SIZE
- (id)replacement_initWithSize:(NSSize)size;
{
    OBPRECONDITION(size.width == rint(size.width));
    OBPRECONDITION(size.height == rint(size.height));
    return original_initWithSize(self, _cmd, size);
}

- (void)replacement_setSize:(NSSize)size;
{
    OBPRECONDITION(size.width == rint(size.width));
    OBPRECONDITION(size.height == rint(size.height));
    original_setSize(self, _cmd, size);
}
#endif

#endif

+ (NSImage *)imageNamed:(NSString *)imageName inBundle:(NSBundle *)bundle;
{
    return OAImageNamed(imageName, bundle);
}

+ (NSImage *)imageNamed:(NSString *)imageStem withTint:(NSControlTint)imageTint inBundle:(NSBundle *)aBundle allowingNil:(BOOL)allowNil;
{
    NSString *tintSuffix;
    
    switch (imageTint) {
        case NSGraphiteControlTint:
            tintSuffix = OAGraphiteImageTintSuffix;
            break;
        case NSBlueControlTint:
            tintSuffix = OAAquaImageTintSuffix;
            break;
        case NSClearControlTint:
            tintSuffix = OAClearImageTintSuffix;
            break;
        default:
            tintSuffix = nil;
            break;
    }
    
    if (tintSuffix) {
        NSImage *tinted;
        
        tinted = OAImageNamed([NSString stringWithStrings:imageStem, @"-", tintSuffix, nil], aBundle);
        if (tinted)
            return tinted;
        tinted = OAImageNamed([imageStem stringByAppendingString:tintSuffix], aBundle);
        if (tinted)
            return tinted;
    }
    
    NSImage *baseImage = OAImageNamed(imageStem, aBundle);

    if (baseImage == nil && !allowNil)
        [NSException raise:NSInvalidArgumentException format:@"Internal error: Unable to find image named '%@' in bundle %@", imageStem, aBundle];

    return baseImage;
}

+ (NSImage *)imageNamed:(NSString *)imageStem withTint:(NSControlTint)imageTint inBundle:(NSBundle *)aBundle;
{
    return [self imageNamed:imageStem withTint:imageTint inBundle:aBundle allowingNil:NO];
}

+ (NSImage *)tintedImageNamed:(NSString *)imageStem inBundle:(NSBundle *)aBundle allowingNil:(BOOL)allowNil;
{
    NSImage *defaultImage = [self imageNamed:imageStem withTint:NSDefaultControlTint inBundle:aBundle allowingNil:allowNil];
    NSImage *graphiteImage = [self imageNamed:imageStem withTint:NSGraphiteControlTint inBundle:aBundle allowingNil:allowNil];
    
    if (graphiteImage == defaultImage)
        return defaultImage;
    
    OBASSERT(!graphiteImage.isTemplate, "Template tinted images aren't supported");
    if (defaultImage.isTemplate)
        return defaultImage;

    NSImage *tintedImage = [self tintedImageWithSize:defaultImage.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        NSRect srcRect = { .origin = NSZeroPoint, .size = defaultImage.size };
        NSImage *sourceImage;
        switch ([NSColor currentControlTint]) {
            case NSGraphiteControlTint:
                sourceImage = graphiteImage;
                break;
            default:
                sourceImage = defaultImage;
                break;
        }

        [sourceImage drawInRect:dstRect fromRect:srcRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:NO hints:nil];
        return YES;
    }];

    return tintedImage;
}

+ (NSImage *)tintedImageNamed:(NSString *)imageStem inBundle:(NSBundle *)aBundle;
{
    return [self tintedImageNamed:imageStem inBundle:aBundle allowingNil:NO];
}

+ (NSImage *)tintedImageWithSize:(NSSize)size flipped:(BOOL)drawingHandlerShouldBeCalledWithFlippedContext drawingHandler:(BOOL (^)(NSRect dstRect))drawingHandler;
{
    return [_OATintedImage imageWithSize:size flipped:drawingHandlerShouldBeCalledWithFlippedContext drawingHandler:drawingHandler];
}

+ (NSImage *)imageForFileType:(NSString *)fileType;
    // It turns out that -[NSWorkspace iconForFileType:] doesn't cache previously returned values, so we cache them here.
{
    if (fileType == nil)
        return nil;

    static NSMutableDictionary *imageDictionary;
    static NSLock *imageDictionaryLock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageDictionary = [[NSMutableDictionary alloc] init];
        imageDictionaryLock = [[NSLock alloc] init];
    });

    id image; // NSImage or NSNull

    @try {
        [imageDictionaryLock lock];
        image = [imageDictionary objectForKey:fileType];
        if (image == nil) {
            image = [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
            if (image == nil)
                image = [NSNull null];
            [imageDictionary setObject:image forKey:fileType];
        }
    } @finally {
        [imageDictionaryLock unlock];
    }

    return image != [NSNull null] ? image : nil;
}

/* Checks whether the given file has a custom image specified.  If so, it uses NSWorkspace to get said image.  Otherwise, it tries to use the file extension to get a shared version of the image.  This method will not returned uniqued results for files *with* custom images, but hopefully that calling pattern is rare. */
+ (NSImage *)imageForFile:(NSString *)path;
{
    // <bug:///89030> (Rewrite +[NSImage(OAExtensions) imageForFile:] to not use deprecated API)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // The 'isDirectory' only matters if we use this URL as the base for another relative URL.
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, false/*isDirectory*/);

    struct FSRef fsRef;
    Boolean success = CFURLGetFSRef(url, &fsRef);
    CFRelease(url);

    if (!success) {
        // Probably the file doesn't exist; so therefor it doesn't have a custom image
    } else {
        FSCatalogInfo catalogInfo;
        if (FSGetCatalogInfo(&fsRef, kFSCatInfoFinderInfo, &catalogInfo, NULL, NULL, NULL) == noErr)
            if ((((FileInfo *)(&catalogInfo.finderInfo))->finderFlags & kHasCustomIcon) == 0)
                return [[NSWorkspace sharedWorkspace] iconForFile:path];
    }

	NSString *extension = [path pathExtension];
	if ([extension length])
		return [self imageForFileType:extension];
	else
		return [[NSWorkspace sharedWorkspace] iconForFile:path];
#pragma clang diagnostic pop
}

#define X_SPACE_BETWEEN_ICON_AND_TEXT_BOX 2
#define X_TEXT_BOX_BORDER 2
#define Y_TEXT_BOX_BORDER 2
static NSDictionary *titleFontAttributes;

+ (NSImage *)draggingIconWithTitle:(NSString *)title andImage:(NSImage *)image;
{
    NSImage *drawImage;
    NSSize imageSize, totalSize;
    NSSize titleBoxSize;
    NSRect titleBox;
    NSPoint textPoint;
    
    if ([title length] == 0 && image != nil)
        return image;

    if (image == nil) 
        imageSize = NSMakeSize(-X_SPACE_BETWEEN_ICON_AND_TEXT_BOX, 0.0f);
    else
        imageSize = [image size];

    if (!titleFontAttributes)
        titleFontAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont systemFontOfSize:12.0f], NSFontAttributeName, [NSColor textColor], NSForegroundColorAttributeName, nil];
    
    if ([title length] > 0) {
        NSSize titleSize = [title sizeWithAttributes:titleFontAttributes];
        titleBoxSize = NSMakeSize(titleSize.width + 2.0f * X_TEXT_BOX_BORDER, titleSize.height + Y_TEXT_BOX_BORDER);
    } else {
        titleBoxSize = NSMakeSize(8.0f, 8.0f); // a random empty box size
    }

    totalSize.width = (CGFloat)ceil(imageSize.width + X_SPACE_BETWEEN_ICON_AND_TEXT_BOX + titleBoxSize.width);
    totalSize.height = (CGFloat)ceil(MAX(imageSize.height, titleBoxSize.height));

    drawImage = [[NSImage alloc] initWithSize:totalSize];

    [drawImage lockFocus];

    // Draw transparent background
    [[NSColor colorWithDeviceWhite:1.0f alpha:0.0f] set];
    NSRectFill(NSMakeRect(0, 0, totalSize.width, totalSize.height));

    // Draw icon
    [image drawAtPoint:NSMakePoint(0.0f, totalSize.height - (CGFloat)rint(totalSize.height / 2.0f + imageSize.height / 2.0f)) fromRect:(CGRect){CGPointZero, imageSize} operation:NSCompositingOperationSourceOver fraction:1.0];
    
    // Draw box around title
    titleBox.origin.x = imageSize.width + X_SPACE_BETWEEN_ICON_AND_TEXT_BOX;
    titleBox.origin.y = (CGFloat)floor( (totalSize.height - titleBoxSize.height)/2.0f );
    titleBox.size = titleBoxSize;
    [[[NSColor selectedTextBackgroundColor] colorWithAlphaComponent:0.5f] set];
    NSRectFill(titleBox);

    // Draw title
    textPoint = NSMakePoint(imageSize.width + X_SPACE_BETWEEN_ICON_AND_TEXT_BOX + X_TEXT_BOX_BORDER, Y_TEXT_BOX_BORDER - 1);

    [title drawAtPoint:textPoint withAttributes:titleFontAttributes];

    [drawImage unlockFocus];

    return drawImage;
}

- (NSImage *)imageByTintingWithColor:(NSColor *)tintColor;
{
    OBPRECONDITION(tintColor != nil);
    
    NSImage *image = [self copy];
    NSImage *tintedImage = [NSImage imageWithSize:self.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        NSRect srcRect = { .origin = NSZeroPoint, .size = image.size };
        [image drawInRect:dstRect fromRect:srcRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:NO hints:nil];
        [tintColor set];
        NSRectFillUsingOperation(dstRect, NSCompositingOperationSourceIn);
        return YES;
    }];
    
    return tintedImage;
}

//

- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta;
{
    /*
     There are two reasons for this method.
     One, to invert the Y-axis so we can draw the image flipped.
     Two, to deal with the crackheaded behavior of NSCachedImageRep (RADAR #4985046) where it snaps its drawing bounds to integer coordinates *in the current user space*. This means that if your coordinate system is scaled from the default you get screwy results (OBS #35894).
     */
        
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(context); {
        CGContextTranslateCTM(context, NSMinX(rect), NSMaxY(rect));
        if (sourceRect.size.width == 0 && sourceRect.size.height == 0)
            sourceRect.size = [self size];
        CGContextScaleCTM(context,rect.size.width/sourceRect.size.width, -1 * ( rect.size.height/sourceRect.size.height ));
        
        rect.origin.x = rect.origin.y = 0; // We've translated ourselves so it's zero
        rect.size = sourceRect.size;  // We've scaled ourselves to match
        [self drawInRect:rect fromRect:sourceRect operation:op fraction:delta];
    } CGContextRestoreGState(context);

    /*
        NSAffineTransform *flipTransform;
        NSPoint transformedPoint;
        NSSize transformedSize;
        NSRect transformedRect;

        flipTransform = [[NSAffineTransform alloc] init];
        [flipTransform scaleXBy:1.0 yBy:-1.0];

        transformedPoint = [flipTransform transformPoint:rect.origin];
        transformedSize = [flipTransform transformSize:rect.size];
        [flipTransform concat];
        transformedRect = NSMakeRect(transformedPoint.x, transformedPoint.y + transformedSize.height, transformedSize.width, -transformedSize.height);
        [anImage drawInRect:transformedRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
        [flipTransform concat];
        [flipTransform release];
     */
}

- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op;
{
    [self drawFlippedInRect:rect fromRect:sourceRect operation:op fraction:1.0f];
}

- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op fraction:(CGFloat)delta;
{
    [self drawFlippedInRect:rect fromRect:NSZeroRect operation:op fraction:delta];
}

- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op;
{
    [self drawFlippedInRect:rect operation:op fraction:1.0f];
}

- (NSImageRep *)imageRepOfClass:(Class)imageRepClass;
{
    for (NSImageRep *rep in [self representations])
        if ([rep isKindOfClass:imageRepClass])
            return rep;
    return nil;
}

- (NSImageRep *)imageRepOfSize:(NSSize)aSize;
{
    for (NSImageRep *rep in [self representations])
        if (NSEqualSizes([rep size], aSize))
            return rep;
    return nil;
    
}

- (NSImage *)scaledImageOfSize:(NSSize)aSize;
{
    NSImage *scaledImage = [[NSImage alloc] initWithSize:aSize];
    [scaledImage lockFocus];
    NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];
    NSImageInterpolation savedInterpolation = [currentContext imageInterpolation];
    [currentContext setImageInterpolation:NSImageInterpolationHigh];
    [self drawInRect:NSMakeRect(0.0f, 0.0f, aSize.width, aSize.height) fromRect:(NSRect){ { 0, 0 }, [self size] } operation:NSCompositingOperationSourceOver fraction:1.0f];
    [currentContext setImageInterpolation:savedInterpolation];
    [scaledImage unlockFocus];
    return scaledImage;
}

static NSData *_imageDataWithFileType(NSImage *self, NSBitmapImageFileType imageType, CFStringRef imageFileType)
{
    NSBitmapImageRep *bitmapImageRep = (id)[self imageRepOfClass:[NSBitmapImageRep class]];
    if (bitmapImageRep != nil) {
        NSData *data = [bitmapImageRep representationUsingType:imageType properties:@{}];
        if (data != nil) // On Yosemite, this can fail with "ImageIO: PNG gamma value does not match sRGB"
            return data;
    }

    // This will log CG errors if there is just a "NSCGImageSnapshotRep", which is what you get if you've drawn into an image via -lockFocus.
#if 0
    // Not sure what this does with there are multiples.  Does it write multi-resolution TIFF? What does it do for PNG?
    NSData *result = [NSBitmapImageRep representationOfImageRepsInArray:[self representations] usingType:imageType properties:nil];
    if (result)
        return result;
#endif

    CGImageRef imageRef = [self CGImageForProposedRect:NULL context:nil hints:nil];
    if (imageRef) {
        do {
            NSMutableData *data = [NSMutableData data];
            CGImageDestinationRef destination = CGImageDestinationCreateWithData((OB_BRIDGE CFMutableDataRef)data, imageFileType, 1, NULL);
            if (!destination) {
                OBASSERT(destination);
                break;
            }
            CGImageDestinationAddImage(destination, imageRef, nil);
            if (!CGImageDestinationFinalize(destination)) {
                CFRelease(destination);
                OBASSERT_NOT_REACHED("Failed to archive image");
                break;
            }

            CFRelease(destination);
            return data;
        } while (0);
    }

    return nil;
}
- (NSData *)bmpData;
{
    return [self bmpDataWithBackgroundColor:nil];
}

- (NSData *)bmpDataWithBackgroundColor:(NSColor *)backgroundColor;
{
    NSImage *image;
    if (backgroundColor != nil) {
        image = [NSImage imageWithSize:self.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
            [backgroundColor set];
            NSRectFill(dstRect);

            [self drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0f];
            return YES;
        }];
    } else {
        image = self;
    }

    return _imageDataWithFileType(image, NSBitmapImageFileTypeBMP, kUTTypeBMP);
}


- (NSData *)pngData;
{
    return _imageDataWithFileType(self, NSBitmapImageFileTypePNG, kUTTypePNG);
}

+ (NSImage *)documentIconWithContent:(NSImage *)contentImage;
{
    NSImage *templateImage, *contentMask;

    templateImage = [NSImage imageNamed:@"DocumentIconTemplate"];
    contentMask = [NSImage imageNamed:@"DocumentIconMask"];
    return [self documentIconWithTemplate:templateImage content:contentImage contentMask:contentMask];
}

#define ICON_SIZE_LARGE NSMakeSize(128.0f, 128.0f)
#define ICON_SIZE_SMALL NSMakeSize(32.0f, 32.0f)
#define ICON_SIZE_TINY NSMakeSize(16.0f, 16.0f)

+ (NSImage *)documentIconWithTemplate:(NSImage *)templateImage content:(NSImage *)contentImage contentMask:(NSImage *)contentMask;
{
    NSImage *newImage;
    NSImage *largeImage, *smallImage, *tinyImage;
    NSRect bounds;

    largeImage = [[NSImage alloc] initWithSize:ICON_SIZE_LARGE];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_LARGE};
    [largeImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_LARGE] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationDestinationIn fraction:1.0f];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationDestinationAtop fraction:1.0f];
    }
    [largeImage unlockFocus];

    smallImage = [[NSImage alloc] initWithSize:ICON_SIZE_SMALL];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_SMALL};
    [smallImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_SMALL] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationDestinationIn fraction:1.0f];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationDestinationAtop fraction:1.0f];
    }
    [smallImage unlockFocus];

    tinyImage = [[NSImage alloc] initWithSize:ICON_SIZE_TINY];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_TINY};
    [tinyImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_TINY] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationDestinationIn fraction:1.0f];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationDestinationAtop fraction:1.0f];
    }
    [tinyImage unlockFocus];

    newImage = [[NSImage alloc] initWithSize:ICON_SIZE_SMALL]; // prefer 32x32, to be consistent with icons returned by NSWorkspace methods
    [newImage addRepresentation:[[largeImage representations] objectAtIndex:0]];
    [newImage addRepresentation:[[smallImage representations] objectAtIndex:0]];
    [newImage addRepresentation:[[tinyImage representations] objectAtIndex:0]];

    return newImage;
}

//
// System Images
//

static NSImage *getSystemImage(OSType fourByteCode, BOOL flip)
{
    IconRef iconRef = 0; /* 0 is documented to be the invalid value for an IconRef */
    OSErr result = GetIconRef(kOnSystemDisk, kSystemIconsCreator, fourByteCode, &iconRef);
    if (result != noErr || iconRef == 0)
        return nil;
    
    NSImage *iconImage = [[NSImage alloc] initWithIconRef:iconRef];
    
    ReleaseIconRef(iconRef);

    return iconImage;
}

#define OA_SYSTEM_IMAGE(x, flip) \
do { \
    static NSImage *image = nil; \
    if (image != nil) return image; \
    image = getSystemImage(x, flip); \
    return image; \
} while(0)

+ (NSImage *)httpInternetLocationImage;
{
    OA_SYSTEM_IMAGE(kInternetLocationHTTPIcon, NO);
}

+ (NSImage *)ftpInternetLocationImage;
{
    OA_SYSTEM_IMAGE(kInternetLocationFTPIcon, NO);
}

+ (NSImage *)mailInternetLocationImage;
{
    OA_SYSTEM_IMAGE(kInternetLocationMailIcon, NO);
}

+ (NSImage *)newsInternetLocationImage;
{
    OA_SYSTEM_IMAGE(kInternetLocationNewsIcon, NO);
}

+ (NSImage *)genericInternetLocationImage;
{
    OA_SYSTEM_IMAGE(kInternetLocationGenericIcon, NO);
}

+ (NSImage *)aliasBadgeImage;
{
    OA_SYSTEM_IMAGE(kAliasBadgeIcon, YES);
}

static pthread_once_t setupTintTableOnce = PTHREAD_ONCE_INIT;
static OFEnumNameTable *tintTable;
static void setupTintTable(void)
{
    OBPRECONDITION(tintTable == nil);
    
    tintTable = [[OFEnumNameTable alloc] initWithDefaultEnumValue:NSDefaultControlTint];
    [tintTable setName:[OAAquaImageTintSuffix lowercaseString] forEnumValue:NSBlueControlTint];
    [tintTable setName:[OAGraphiteImageTintSuffix lowercaseString] forEnumValue:NSGraphiteControlTint];
    [tintTable setName:[OAClearImageTintSuffix lowercaseString] forEnumValue:NSClearControlTint];
    [tintTable setName:@"default" forEnumValue:NSDefaultControlTint];
}

+ (OFEnumNameTable *)tintNameEnumeration;
{
    pthread_once(&setupTintTableOnce, setupTintTable);
    return tintTable;
}

@end

@implementation _OATintedImage

- (instancetype)initWithSize:(NSSize)aSize;
{
    self = [super initWithSize:aSize];
    if (self == nil) {
        return nil;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateTintedImage) name:NSControlTintDidChangeNotification object:nil];
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_updateTintedImage;
{
    [self recache];
}

@end
