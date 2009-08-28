// Copyright 1997-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
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
#import <QuartzCore/QuartzCore.h>


#import "OAImageManager.h"

RCS_ID("$Id$")

@implementation NSImage (OAExtensions)

#ifdef DEBUG

// Photoshop likes to save files with non-integral DPI.  This can cause hard to find bugs later on, so lets just find out about this right away.
static id (*original_initWithContentsOfFile)(id self, SEL _cmd, NSString *fileName);
static id (*original_initByReferencingFile)(id self, SEL _cmd, NSString *fileName);
static id (*original_initWithSize)(id self, SEL _cmd, NSSize size);
static id (*original_setSize)(id self, SEL _cmd, NSSize size);

+ (void)performPosing;
{
    original_initByReferencingFile = (typeof(original_initWithContentsOfFile))OBReplaceMethodImplementationWithSelector(self, @selector(initByReferencingFile:), @selector(replacement_initByReferencingFile:));
    original_initWithContentsOfFile = (typeof(original_initWithContentsOfFile))OBReplaceMethodImplementationWithSelector(self, @selector(initWithContentsOfFile:), @selector(replacement_initWithContentsOfFile:));
    original_initWithSize = (typeof(original_initWithSize))OBReplaceMethodImplementationWithSelector(self, @selector(initWithSize:), @selector(replacement_initWithSize:));
    original_setSize = (typeof(original_setSize))OBReplaceMethodImplementationWithSelector(self, @selector(setSize:), @selector(replacement_setSize:));
}

// If you run into these assertions, consider running the OAMakeImageSizeIntegral command line tool in your image (probably only reasonable for TIFF right now).

- (id)replacement_initWithContentsOfFile:(NSString *)fileName;
{
    OBPRECONDITION(fileName != nil);
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
- (id)replacement_initByReferencingFile:(NSString *)fileName;
{
    OBPRECONDITION(fileName != nil);
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

+ (NSImage *)imageNamed:(NSString *)imageName inBundleForClass:(Class)aClass;
{
    return [[OAImageManager sharedImageManager] imageNamed:imageName inBundle:[NSBundle bundleForClass:aClass]];
}

+ (NSImage *)imageNamed:(NSString *)imageName inBundle:(NSBundle *)aBundle;
{
    return [[OAImageManager sharedImageManager] imageNamed:imageName inBundle:aBundle];
}

+ (NSImage *)tintedImageNamed:(NSString *)imageStem inBundle:(NSBundle *)aBundle;
{
    return [self imageNamed:imageStem withTint:[NSColor currentControlTint] inBundle:aBundle];
}

+ (NSImage *)imageNamed:(NSString *)imageStem withTint:(NSControlTint)imageTint inBundle:(NSBundle *)aBundle;
{
    NSString *tintSuffix;
    
    switch(imageTint) {
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
    
    OAImageManager *imageMunger = [OAImageManager sharedImageManager];
    
    // OAImageManager caches lookup failures, and NSImage caches successes, so it's not a big problem if we try a few variations.
    if (tintSuffix) {
        NSImage *tinted;
        
        tinted = [imageMunger imageNamed:[NSString stringWithStrings:imageStem, @"-", tintSuffix, nil] inBundle:aBundle];
        if (tinted)
            return tinted;
        tinted = [imageMunger imageNamed:[imageStem stringByAppendingString:tintSuffix] inBundle:aBundle];
        if (tinted)
            return tinted;
    }
    
    return [imageMunger imageNamed:imageStem inBundle:aBundle];
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
#ifdef DEBUG
        // Make sure that our caching doesn't go insane (and that we don't ask it to cache insane stuff)
        NSLog(@"Caching workspace image for file type '%@'", fileType);
#endif
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
        imageSize = NSMakeSize(-X_SPACE_BETWEEN_ICON_AND_TEXT_BOX, 0.0);
    else
        imageSize = [image size];

    if (!titleFontAttributes)
        titleFontAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont systemFontOfSize:12.0], NSFontAttributeName, [NSColor textColor], NSForegroundColorAttributeName, nil];
    
    if ([title length] > 0) {
        NSSize titleSize = [title sizeWithAttributes:titleFontAttributes];
        titleBoxSize = NSMakeSize(titleSize.width + 2.0 * X_TEXT_BOX_BORDER, titleSize.height + Y_TEXT_BOX_BORDER);
    } else {
        titleBoxSize = NSMakeSize(8.0, 8.0); // a random empty box size
    }

    totalSize.width = ceil(imageSize.width + X_SPACE_BETWEEN_ICON_AND_TEXT_BOX + titleBoxSize.width);
    totalSize.height = ceil(MAX(imageSize.height, titleBoxSize.height));

    drawImage = [[NSImage alloc] initWithSize:totalSize];

    [drawImage lockFocus];

    // Draw transparent background
    [[NSColor colorWithDeviceWhite:1.0 alpha:0.0] set];
    NSRectFill(NSMakeRect(0, 0, totalSize.width, totalSize.height));

    // Draw icon
    [image compositeToPoint:NSMakePoint(0.0, totalSize.height - rint(totalSize.height / 2.0 + imageSize.height / 2.0)) operation:NSCompositeSourceOver];
    
    // Draw box around title
    titleBox.origin.x = imageSize.width + X_SPACE_BETWEEN_ICON_AND_TEXT_BOX;
    titleBox.origin.y = floor( (totalSize.height - titleBoxSize.height)/2.0 );
    titleBox.size = titleBoxSize;
    [[[NSColor selectedTextBackgroundColor] colorWithAlphaComponent:0.5] set];
    NSRectFill(titleBox);

    // Draw title
    textPoint = NSMakePoint(imageSize.width + X_SPACE_BETWEEN_ICON_AND_TEXT_BOX + X_TEXT_BOX_BORDER, Y_TEXT_BOX_BORDER - 1);

    [title drawAtPoint:textPoint withAttributes:titleFontAttributes];

    [drawImage unlockFocus];

    return [drawImage autorelease];
}

//

- (void)drawFlippedInRect:(NSRect)rect fromRect:(NSRect)sourceRect operation:(NSCompositingOperation)op fraction:(float)delta;
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
        
        // <bug://bugs/43240> (10.5/Leopard: Placed EPS and PDF images corrupted when opacity changed in Image Inspector), <bug://bugs/44518> (Copied and pasted PDFs rasterize when their opacity is changed) and RADAR 5586059 / 4766375 all involve PDF caching problems. The following seems to fix it even though I do not know why...
        OFForEachInArray([self representations], NSImageRep *, rep, {
            if ([rep isKindOfClass:[NSPDFImageRep class]] || [rep isKindOfClass:[NSEPSImageRep class]]) {
              CGContextSetAlpha(context, delta);
              delta = 1.0;
              break;
            }
        });
        
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
    [self drawFlippedInRect:rect fromRect:sourceRect operation:op fraction:1.0];
}

- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op fraction:(float)delta;
{
    [self drawFlippedInRect:rect fromRect:NSZeroRect operation:op fraction:delta];
}

- (void)drawFlippedInRect:(NSRect)rect operation:(NSCompositingOperation)op;
{
    [self drawFlippedInRect:rect operation:op fraction:1.0];
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
            ADD_CHEAP_DATA(NSPDFPboardType, [(NSPDFImageRep *)rep PDFRepresentation]);
        }

#if defined(MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6)
        // -PICTRepresentation is deprecated on 10.6
#else
        if ([rep respondsToSelector:@selector(PICTRepresentation)]) {
            ADD_CHEAP_DATA(NSPICTPboardType, [(NSPICTImageRep *)rep PICTRepresentation]);
        }

        if ([rep respondsToSelector:@selector(EPSRepresentation)]) {
            ADD_CHEAP_DATA(NSPostScriptPboardType, [(NSEPSImageRep *)rep EPSRepresentation]);
        }
#endif
    }
    
    /* Always offer to convert to TIFF. Do this lazily, though, since we probably have to extract it from a bitmap image rep. */
    IF_ADD(NSTIFFPboardType, self) {
        count ++;
    }

    return count;
}

- (void)pasteboard:(NSPasteboard *)aPasteboard provideDataForType:(NSString *)wanted
{
    if ([wanted isEqual:NSTIFFPboardType]) {
        [aPasteboard setData:[self TIFFRepresentation] forType:NSTIFFPboardType];
    }
}

//

- (NSImageRep *)imageRepOfClass:(Class)imageRepClass;
{
    NSArray *representations = [self representations];
    unsigned int representationIndex, representationCount = [representations count];
    for (representationIndex = 0; representationIndex < representationCount; representationIndex++) {
        NSImageRep *rep = [representations objectAtIndex:representationIndex];
        if ([rep isKindOfClass:imageRepClass]) {
            return rep;
        }
    }
    return nil;
}

- (NSImageRep *)imageRepOfSize:(NSSize)aSize;
{
    NSArray *representations = [self representations];
    unsigned int representationIndex, representationCount = [representations count];
    for (representationIndex = 0; representationIndex < representationCount; representationIndex++) {
        NSImageRep *rep = [representations objectAtIndex:representationIndex];
        if (NSEqualSizes([rep size], aSize)) {
            return rep;
        }
    }
    return nil;
    
}

- (NSImage *)scaledImageOfSize:(NSSize)aSize;
{
    NSImage *scaledImage = [[[NSImage alloc] initWithSize:aSize] autorelease];
    [scaledImage lockFocus];
    NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];
    NSImageInterpolation savedInterpolation = [currentContext imageInterpolation];
    [currentContext setImageInterpolation:NSImageInterpolationHigh];
    [self drawInRect:NSMakeRect(0.0, 0.0, aSize.width, aSize.height) fromRect:(NSRect){ { 0, 0 }, [self size] } operation:NSCompositeSourceOver fraction:1.0];
    [currentContext setImageInterpolation:savedInterpolation];
    [scaledImage unlockFocus];
    return scaledImage;
}

#include <stdlib.h>
#include <memory.h>

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


    typedef struct {
        unsigned char rgbBlue;
        unsigned char rgbGreen;
        unsigned char rgbRed;
        unsigned char rgbReserved;
    } RGBQUAD;


    NSBitmapImageRep *bitmapImageRep = (id)[self imageRepOfClass:[NSBitmapImageRep class]];
    if (bitmapImageRep == nil || backgroundColor != nil) {
        NSRect imageBounds = {NSZeroPoint, [self size]};
        NSImage *newImage = [[NSImage alloc] initWithSize:imageBounds.size];
        [newImage lockFocus]; {
            [backgroundColor ? backgroundColor : [NSColor clearColor] set];
            NSRectFill(imageBounds);
            [self drawInRect:imageBounds fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            bitmapImageRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:imageBounds] autorelease];
        } [newImage unlockFocus];
        [newImage release];
    }

    uint32 width = [bitmapImageRep pixelsWide];
    uint32 height= [bitmapImageRep pixelsHigh];
    unsigned char *image = [bitmapImageRep bitmapData];
    unsigned int samplesPerPixel = [bitmapImageRep samplesPerPixel];

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
    if (bitmapImageRep)
        return [bitmapImageRep representationUsingType:NSPNGFileType properties:nil];
    
    // Not sure what this does with there are multiples.  Does it write multi-resolution TIFF? What does it do for PNG?
    NSArray *representations = [self representations];
    OBASSERT([representations count] == 1);
    NSData *result = [NSBitmapImageRep representationOfImageRepsInArray:representations usingType:NSPNGFileType properties:nil];
    OBASSERT(result);
    return result;
}

+ (NSImage *)documentIconWithContent:(NSImage *)contentImage;
{
    NSImage *templateImage, *contentMask;

    templateImage = [NSImage imageNamed:@"DocumentIconTemplate"];
    contentMask = [NSImage imageNamed:@"DocumentIconMask"];
    return [self documentIconWithTemplate:templateImage content:contentImage contentMask:contentMask];
}

#define ICON_SIZE_LARGE NSMakeSize(128.0, 128.0)
#define ICON_SIZE_SMALL NSMakeSize(32.0, 32.0)
#define ICON_SIZE_TINY NSMakeSize(16.0, 16.0)

+ (NSImage *)documentIconWithTemplate:(NSImage *)templateImage content:(NSImage *)contentImage contentMask:(NSImage *)contentMask;
{
    NSImage *newImage;
    NSImage *largeImage, *smallImage, *tinyImage;
    NSRect bounds;

    largeImage = [[[NSImage alloc] initWithSize:ICON_SIZE_LARGE] autorelease];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_LARGE};
    [largeImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_LARGE] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationAtop fraction:1.0];
    }
    [largeImage unlockFocus];

    smallImage = [[[NSImage alloc] initWithSize:ICON_SIZE_SMALL] autorelease];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_SMALL};
    [smallImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_SMALL] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationAtop fraction:1.0];
    }
    [smallImage unlockFocus];

    tinyImage = [[[NSImage alloc] initWithSize:ICON_SIZE_TINY] autorelease];
    bounds = (NSRect){NSZeroPoint, ICON_SIZE_TINY};
    [tinyImage lockFocus];
    {
        [[contentImage imageRepOfSize:ICON_SIZE_TINY] drawInRect:bounds];
        [contentMask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0];
        [templateImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationAtop fraction:1.0];
    }
    [tinyImage unlockFocus];

    newImage = [[NSImage alloc] initWithSize:ICON_SIZE_SMALL]; // prefer 32x32, to be consistent with icons returned by NSWorkspace methods
    [newImage addRepresentation:[[largeImage representations] objectAtIndex:0]];
    [newImage addRepresentation:[[smallImage representations] objectAtIndex:0]];
    [newImage addRepresentation:[[tinyImage representations] objectAtIndex:0]];

    return [newImage autorelease];
}

//
// System Images
//

static NSImage *getSystemImage(OSType fourByteCode, BOOL flip, NSImage **buf)
{
    if (!*buf) {
        IconRef iconRef;
        
        iconRef = 0; /* 0 is documented to be the invalid value for an IconRef */
        OSErr result = GetIconRef(kOnSystemDisk, kSystemIconsCreator, fourByteCode, &iconRef);
        if (result != noErr || iconRef == 0)
            return nil;
        
        NSImage *iconImage = [[NSImage alloc] initWithIconRef:iconRef];
        
        ReleaseIconRef(iconRef);
        
        *buf = iconImage;
    }

    return *buf;
}

#define OA_SYSTEM_IMAGE(x, flip) \
do { \
    static NSImage *image = nil; \
    return getSystemImage(x, flip, &image); \
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

#pragma mark CoreImage

- (CIImage *)ciImageForContext:(CIContext *)ctxt;
{
    NSArray *reps = [self representations];
    unsigned repIndex, repCount = [reps count];
    
    /* Check to see if we have an image rep that's easily converted to a CIImage. */
    
    for(repIndex = 0; repIndex < repCount; repIndex ++) {
        NSImageRep *rep = [reps objectAtIndex:repIndex];
        if ([rep isKindOfClass:[NSCIImageRep class]])
            return [(NSCIImageRep *)rep CIImage];
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            CGImageRef cgImage = [(NSBitmapImageRep *)rep CGImage];
            if (cgImage != NULL)
                return [CIImage imageWithCGImage:cgImage];
        }
    }
    
    /* Fallback: render the image into a CGLayer and get a CIImage from that. */
    
    [NSGraphicsContext saveGraphicsState];
    NSSize mySize = [self size];
    CGLayerRef imageLayer = [ctxt createCGLayerWithSize:(CGSize){mySize.width, mySize.height} info:NULL];
    CGContextRef layerContext = CGLayerGetContext(imageLayer);
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:layerContext flipped:NO]];
    [self drawAtPoint:(NSPoint){0, 0}
             fromRect:(NSRect){{0, 0}, mySize}
            operation:NSCompositeCopy
             fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    
    CIImage *result = [CIImage imageWithCGLayer:imageLayer];
    CGLayerRelease(imageLayer);
    
    return result;
}

@end

