// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
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

@implementation NSImage (OAExtensions)

#ifdef DEBUG

// Photoshop likes to save files with non-integral DPI.  This can cause hard to find bugs later on, so lets just find out about this right away.
static id (*original_initWithContentsOfFile)(id __attribute((ns_consumed)) self, SEL _cmd, NSString *fileName);
static id (*original_initByReferencingFile)(id __attribute((ns_consumed)) self, SEL _cmd, NSString *fileName);
#ifdef DEBUG_NONINTEGRAL_IMAGE_SIZE
static id (*original_initWithSize)(id __attribute((ns_consumed)) self, SEL _cmd, NSSize size);
static id (*original_setSize)(id __attribute((ns_consumed)) self, SEL _cmd, NSSize size);
#endif

+ (void)performPosing;
{
    original_initByReferencingFile = (typeof(original_initWithContentsOfFile))OBReplaceMethodImplementationWithSelector(self, @selector(initByReferencingFile:), @selector(_initByReferencingFile_replacement:));
    original_initWithContentsOfFile = (typeof(original_initWithContentsOfFile))OBReplaceMethodImplementationWithSelector(self, @selector(initWithContentsOfFile:), @selector(_initWithContentsOfFile_replacement:));
#ifdef DEBUG_NONINTEGRAL_IMAGE_SIZE
    original_initWithSize = (typeof(original_initWithSize))OBReplaceMethodImplementationWithSelector(self, @selector(initWithSize:), @selector(replacement_initWithSize:));
    original_setSize = (typeof(original_setSize))OBReplaceMethodImplementationWithSelector(self, @selector(setSize:), @selector(replacement_setSize:));
#endif
}

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

    OBPOSTCONDITION(size.width == rint(size.width));
    OBPOSTCONDITION(size.height == rint(size.height));
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
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(![NSString isEmptyString:imageName]);
    
    // If we get asked for an image in the app wrapper (or unspecified bundle, which we take to mean the app wrapper), just let +imageNamed: do its thing.
    if ((bundle == nil) || (bundle == [NSBundle mainBundle])) {
        return [self imageNamed:imageName];
    }

    // +imageForResource: is documented to not cache. We used to use the +imageNamed: cache by setting our cache key as the name of the image so that future lookups would work. But, this makes xib loading unable to find the image. <bug:///86682> (Unassigned: Could not find image named 'OACautionIcon')
    static NSCache *imageCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageCache = [[NSCache alloc] init];
        imageCache.name = @"com.omnigroup.OmniAppKit.imageNamed_inBundle";
    });

    NSString *imageNameInCache = [NSString stringWithFormat:@"%@.%@", [bundle bundleIdentifier], imageName];
    NSImage *image = [imageCache objectForKey:imageNameInCache];
    if (![image isValid]) {
        // If we didn't find the image in the cache, actually try to load it from the bundle (using the original, unmangled name, which is the actual name of the resource), then name it, using our bundle-specific mangled name so that it will be cached without conflicting with any identically-named images in the app wrapper (or in other bundles).
        image = [bundle imageForResource:imageName];
        if (image)
            [imageCache setObject:image forKey:imageNameInCache];
    }
    return image;
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
        
        tinted = [self imageNamed:[NSString stringWithStrings:imageStem, @"-", tintSuffix, nil] inBundle:aBundle];
        if (tinted)
            return tinted;
        tinted = [self imageNamed:[imageStem stringByAppendingString:tintSuffix] inBundle:aBundle];
        if (tinted)
            return tinted;
    }
    
    NSImage *baseImage = [self imageNamed:imageStem inBundle:aBundle];

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
        [sourceImage drawInRect:dstRect fromRect:srcRect operation:NSCompositeSourceOver fraction:1.0 respectFlipped:NO hints:nil];
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
    static NSMutableDictionary *imageDictionary = nil;
    id image;

    ASSERT_IN_MAIN_THREAD(@"+imageForFileType: is not thread-safe; must be called from the main thread");
    // We could fix this by adding locks around imageDictionary

    if (!fileType)
        return nil;
        
    if (imageDictionary == nil)
        imageDictionary = [[NSMutableDictionary alloc] init];

    image = [imageDictionary objectForKey:fileType];
    if (image == nil) {
        image = [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
        if (image == nil)
            image = [NSNull null];
        [imageDictionary setObject:image forKey:fileType];
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
    [image drawAtPoint:NSMakePoint(0.0f, totalSize.height - (CGFloat)rint(totalSize.height / 2.0f + imageSize.height / 2.0f)) fromRect:(CGRect){CGPointZero, imageSize} operation:NSCompositeSourceOver fraction:1.0];
    
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
        [image drawInRect:dstRect fromRect:srcRect operation:NSCompositeSourceOver fraction:1.0 respectFlipped:NO hints:nil];
        [tintColor set];
        NSRectFillUsingOperation(dstRect, NSCompositeSourceIn);
        return YES;
    }];
    
    return tintedImage;
}

//

- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta;
{
    CGContextRef context;

    /*
     There are two reasons for this method.
     One, to invert the Y-axis so we can draw the image flipped.
     Two, to deal with the crackheaded behavior of NSCachedImageRep (RADAR #4985046) where it snaps its drawing bounds to integer coordinates *in the current user space*. This means that if your coordinate system is scaled from the default you get screwy results (OBS #35894).
     */
        
    context = [[NSGraphicsContext currentContext] graphicsPort];
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
        [anImage drawInRect:transformedRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
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

- (int)addDataToPasteboard:(NSPasteboard *)aPasteboard exceptTypes:(NSMutableSet *)notThese
{
    int count = 0;

    if (!notThese)
        notThese = [NSMutableSet set];

#define IF_ADD(typename, dataOwner) if( ![notThese containsObject:(typename)] && [aPasteboard addTypes:[NSArray arrayWithObject:(typename)] owner:(dataOwner)] > 0 )

#define ADD_CHEAP_DATA(typename, expr) IF_ADD(typename, nil) { [aPasteboard setData:(expr) forType:(typename)]; [notThese addObject:(typename)]; count ++; }
        
    /* If we have image representations lying around that already have data in some concrete format, add that data to the pasteboard. */
    for (NSImageRep *rep in self.representations) {
        if ([rep respondsToSelector:@selector(PDFRepresentation)]) {
            NSData *pdfRepresentation = [(NSPDFImageRep *)rep PDFRepresentation];
            ADD_CHEAP_DATA(NSPasteboardTypePDF, pdfRepresentation);
            ADD_CHEAP_DATA(NSPDFPboardType, pdfRepresentation); // As of 10.9 DP3, Mail and Preview and -[NSImage initWithPasteboard:] still don't accept NSPasteboardTypePDF ("com.adobe.pdf") but do accept NSPDFPboardType ("Apple PDF pasteboard type")
        }
    }
    
    /* Always offer to convert to PNG and TIFF. Do this lazily, though, since we probably have to extract it from a bitmap image rep. */
    IF_ADD(NSPasteboardTypePNG, self) {
        count ++;
    }

    IF_ADD(NSPasteboardTypeTIFF, self) {
        count ++;
    }

    return count;
}

- (void)pasteboard:(NSPasteboard *)aPasteboard provideDataForType:(NSString *)wanted
{
    if (OFTypeConformsTo(wanted, NSPasteboardTypePNG))
        [aPasteboard setData:[self pngData] forType:wanted];
    else if (OFTypeConformsTo(wanted, NSPasteboardTypeTIFF))
        [aPasteboard setData:[self TIFFRepresentation] forType:wanted];
}

//

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
    [self drawInRect:NSMakeRect(0.0f, 0.0f, aSize.width, aSize.height) fromRect:(NSRect){ { 0, 0 }, [self size] } operation:NSCompositeSourceOver fraction:1.0f];
    [currentContext setImageInterpolation:savedInterpolation];
    [scaledImage unlockFocus];
    return scaledImage;
}

- (NSData *)bmpData;
{
    return [self bmpDataWithBackgroundColor:nil];
}

- (NSData *)bmpDataWithBackgroundColor:(NSColor *)backgroundColor;
{
    /* 	This is a Unix port of the bitmap.c code that writes .bmp files to disk.
    It also runs on Win32, and should be easy to get to run on other platforms.
    Please visit my web page, http://www.ece.gatech.edu/~slabaugh and click on "c" and "Writing Windows Bitmaps" for a further explanation.  This code has been tested and works on HP-UX 11.00 using the cc compiler.  To compile, just type "cc -Ae bitmapUnix.c" at the command prompt.

    The Windows .bmp format is little endian, so if you're running this code on a big endian system it will be necessary to swap bytes to write out a little endian file.

    Thanks to Robin Pitrat for testing on the Linux platform.

    Greg Slabaugh, 11/05/01
    */


    // This pragma is necessary so that the data in the structures is aligned to 2-byte boundaries.  Some different compilers have a different syntax for this line.  For example, if you're using cc on Solaris, the line should be #pragma pack(2).
#pragma pack(2)

    // Default data types.  Here, uint16 is an unsigned integer that has size 2 bytes (16 bits), and uint32 is datatype that has size 4 bytes (32 bits).  You may need to change these depending on your compiler.
#define uint16 unsigned short
#define uint32 unsigned int

#define BI_RGB 0
#define BM 19778

    typedef struct {
        uint16 bfType;
        uint32 bfSize;
        uint16 bfReserved1;
        uint16 bfReserved2;
        uint32 bfOffBits;
    } BITMAPFILEHEADER;

    typedef struct {
        uint32 biSize;
        uint32 biWidth;
        uint32 biHeight;
        uint16 biPlanes;
        uint16 biBitCount;
        uint32 biCompression;
        uint32 biSizeImage;
        uint32 biXPelsPerMeter;
        uint32 biYPelsPerMeter;
        uint32 biClrUsed;
        uint32 biClrImportant;
    } BITMAPINFOHEADER;

    NSBitmapImageRep *bitmapImageRep = (id)[self imageRepOfClass:[NSBitmapImageRep class]];
    if (bitmapImageRep == nil || backgroundColor != nil) {
        NSRect imageBounds = {NSZeroPoint, [self size]};
        NSImage *newImage = [[NSImage alloc] initWithSize:imageBounds.size];
        [newImage lockFocus]; {
            [backgroundColor ? backgroundColor : [NSColor clearColor] set];
            NSRectFill(imageBounds);
            [self drawInRect:imageBounds fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
            bitmapImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:imageBounds];
        } [newImage unlockFocus];
    }

    // Can't export huge images; these are NSInteger
    OBASSERT([bitmapImageRep pixelsWide] < INT32_MAX);
    OBASSERT([bitmapImageRep pixelsHigh] < INT32_MAX);
    
    uint32 width = (uint32)[bitmapImageRep pixelsWide];
    uint32 height = (uint32)[bitmapImageRep pixelsHigh];
    unsigned char *image = [bitmapImageRep bitmapData];
    uint32 samplesPerPixel = (uint32)[bitmapImageRep samplesPerPixel];

    /*
     This function writes out a 24-bit Windows bitmap file that is readable by Microsoft Paint.
     The image data is a 1D array of (r, g, b) triples, where individual (r, g, b) values can
     each take on values between 0 and 255, inclusive.

     The input to the function is:
     uint32 width:					The width, in pixels, of the bitmap
     uint32 height:					The height, in pixels, of the bitmap
     unsigned char *image:				The image data, where each pixel is 3 unsigned chars (r, g, b)

     Written by Greg Slabaugh (slabaugh@ece.gatech.edu), 10/19/00
     */
    uint32 extrabytes = (4 - (width * 3) % 4) % 4;

    /* This is the size of the padded bitmap */
    uint32 bytesize = (width * 3 + extrabytes) * height;

    NSMutableData *mutableBMPData = [NSMutableData data];

    /* Fill the bitmap file header structure */
    BITMAPFILEHEADER bmpFileHeader;
    bmpFileHeader.bfType = NSSwapHostShortToLittle(BM);   /* Bitmap header */
    bmpFileHeader.bfSize = NSSwapHostIntToLittle(0);      /* This can be 0 for BI_RGB bitmaps */
    bmpFileHeader.bfReserved1 = NSSwapHostShortToLittle(0);
    bmpFileHeader.bfReserved2 = NSSwapHostShortToLittle(0);
    bmpFileHeader.bfOffBits = NSSwapHostIntToLittle(sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER));
    [mutableBMPData appendBytes:&bmpFileHeader length:sizeof(BITMAPFILEHEADER)];

    /* Fill the bitmap info structure */
    BITMAPINFOHEADER bmpInfoHeader;
    bmpInfoHeader.biSize = NSSwapHostIntToLittle(sizeof(BITMAPINFOHEADER));
    bmpInfoHeader.biWidth = NSSwapHostIntToLittle(width);
    bmpInfoHeader.biHeight = NSSwapHostIntToLittle(height);
    bmpInfoHeader.biPlanes = NSSwapHostShortToLittle(1);
    bmpInfoHeader.biBitCount = NSSwapHostShortToLittle(24);            /* 24 - bit bitmap */
    bmpInfoHeader.biCompression = NSSwapHostIntToLittle(BI_RGB);
    bmpInfoHeader.biSizeImage = NSSwapHostIntToLittle(bytesize);     /* includes padding for 4 byte alignment */
    bmpInfoHeader.biXPelsPerMeter = NSSwapHostIntToLittle(0);
    bmpInfoHeader.biYPelsPerMeter = NSSwapHostIntToLittle(0);
    bmpInfoHeader.biClrUsed = NSSwapHostIntToLittle(0);
    bmpInfoHeader.biClrImportant = NSSwapHostIntToLittle(0);
    [mutableBMPData appendBytes:&bmpInfoHeader length:sizeof(BITMAPINFOHEADER)];

    /* Allocate memory for some temporary storage */
    unsigned char *paddedImage = (unsigned char *)calloc(sizeof(unsigned char), bytesize);

    // This code does three things.  First, it flips the image data upside down, as the .bmp format requires an upside down image.  Second, it pads the image data with extrabytes number of bytes so that the width in bytes of the image data that is written to the file is a multiple of 4.  Finally, it swaps (r, g, b) for (b, g, r).  This is another quirk of the .bmp file format.

    uint32 row, column;
    for (row = 0; row < height; row++) {
        unsigned char *imagePtr = image + (height - 1 - row) * width * samplesPerPixel;
        unsigned char *paddedImagePtr = paddedImage + row * (width * 3 + extrabytes);
        for (column = 0; column < width; column++) {
            *paddedImagePtr = *(imagePtr + 2);
            *(paddedImagePtr + 1) = *(imagePtr + 1);
            *(paddedImagePtr + 2) = *imagePtr;
            imagePtr += samplesPerPixel;
            paddedImagePtr += 3;
        }
    }

    /* Write bmp data */
    [mutableBMPData appendBytes:paddedImage length:bytesize];

    free(paddedImage);

    return mutableBMPData;
}

- (NSData *)pngData;
{
    NSBitmapImageRep *bitmapImageRep = (id)[self imageRepOfClass:[NSBitmapImageRep class]];
    if (bitmapImageRep != nil) {
        NSData *pngData = [bitmapImageRep representationUsingType:NSPNGFileType properties:@{}];
        if (pngData != nil) // On Yosemite, this can fail with "ImageIO: PNG gamma value does not match sRGB"
            return pngData;
    }

    // This will log CG errors if there is just a "NSCGImageSnapshotRep", which is what you get if you've drawn into an image via -lockFocus.
#if 0
    // Not sure what this does with there are multiples.  Does it write multi-resolution TIFF? What does it do for PNG?
    NSData *result = [NSBitmapImageRep representationOfImageRepsInArray:[self representations] usingType:NSPNGFileType properties:nil];
    if (result)
        return result;
#endif
    
    CGImageRef imageRef = [self CGImageForProposedRect:NULL context:nil hints:nil];
    if (imageRef) {
        do {
            NSMutableData *data = [NSMutableData data];
            CGImageDestinationRef destination = CGImageDestinationCreateWithData((OB_BRIDGE CFMutableDataRef)data, kUTTypePNG, 1, NULL);
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
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0f];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationAtop fraction:1.0f];
    }
    [largeImage unlockFocus];

    smallImage = [[NSImage alloc] initWithSize:ICON_SIZE_SMALL];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_SMALL};
    [smallImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_SMALL] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0f];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationAtop fraction:1.0f];
    }
    [smallImage unlockFocus];

    tinyImage = [[NSImage alloc] initWithSize:ICON_SIZE_TINY];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_TINY};
    [tinyImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_TINY] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0f];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationAtop fraction:1.0f];
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
{
    id _tintObserver;
}

- (id)initWithSize:(NSSize)aSize;
{
    self = [super initWithSize:aSize];
    if (self == nil)
        return nil;

    [self _subscribeToTintNotifications];

    return self;
}

- (void)dealloc;
{
    if (_tintObserver != nil)
        [[NSNotificationCenter defaultCenter] removeObserver:_tintObserver];
}

- (void)_subscribeToTintNotifications;
{
    if (_tintObserver != nil)
        return;

    __weak _OATintedImage *weakSelf = self;
    _tintObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSControlTintDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        _OATintedImage *strongSelf = weakSelf;
        [strongSelf _updateTintedImage];
    }];
}

- (void)_updateTintedImage;
{
    [self recache];
}

@end
