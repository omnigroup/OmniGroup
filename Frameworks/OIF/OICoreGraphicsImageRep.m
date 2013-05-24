// Copyright 2001-2005, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OIF/OICoreGraphicsImageRep.h>

#import <Foundation/Foundation.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OICoreGraphicsImageRep

+ (void)initialize
{
    OBINITIALIZE;

    [self registerImageRepClass:self];
}

// Init and dealloc

- initWithImageRef:(CGImageRef)myImage colorSpaceName:(NSString *)space;
{
    if (!(self = [super init]))
        return nil;

    cgImage = myImage;
    CGImageRetain(cgImage);
    colorSpaceName = [space copy];

    return self;
}

- (void)dealloc;
{
    if (cgImage != NULL)
        CGImageRelease(cgImage);
        
    [colorSpaceName release];
    [heldObject release];
    [super dealloc];
}


// API

- (void)setImage:(CGImageRef)newImage
{
    if (cgImage != newImage) {
        if (cgImage != NULL)
            CGImageRelease(cgImage);
        cgImage = CGImageRetain(newImage);
    }
    
    // mark self for redisplay ?
}

- (void)setColorSpaceHolder:(id <NSObject>)anObject
{
    // The reason for this is a little obscure. We never actually use the color space object (an OIICCProfile instance). It's mainly just a wrapper around a CGColorSpaceRef, and the CGImage holds on to that by itself. However, if we keep the OIICCProfile from being deallocated, it will maintain a map table entry which allows image processors to use the same CGColorSpace for identical color profiles read from different images. Is this actually a performance gain? I have no idea. It seems like it ought to be, though.
    [heldObject autorelease];
    heldObject = [anObject retain];
}

// NSImageRep attributes

- (NSInteger)bitsPerSample
{
    if (cgImage)
        return CGImageGetBitsPerComponent(cgImage);
    return 0;
}

- (NSString *)colorSpaceName
{
    return colorSpaceName;
}

- (BOOL)draw
{
    CGRect where;
    
    if (cgImage == NULL)
        return NO;
    
    where.origin.x = 0;
    where.origin.y = 0;
    where.size.width = CGImageGetWidth(cgImage);
    where.size.height = CGImageGetHeight(cgImage);
    
    CGContextDrawImage([[NSGraphicsContext currentContext] graphicsPort], where, cgImage);
    
    return YES;
}

- (BOOL)drawAtPoint:(NSPoint)aPoint
{
    CGRect where;
    
    if (cgImage == NULL)
        return NO;
    
    where.origin.x = aPoint.x;
    where.origin.y = aPoint.y;
    where.size.width = CGImageGetWidth(cgImage);
    where.size.height = CGImageGetHeight(cgImage);
    
    CGContextDrawImage([[NSGraphicsContext currentContext] graphicsPort], where, cgImage);
    
    return YES;
}

- (BOOL)drawInRect:(NSRect)rect
{
    CGRect where;
    
    if (cgImage == NULL)
        return NO;
    
    where.origin.x = rect.origin.x;
    where.origin.y = rect.origin.y;
    where.size.width = rect.size.width;
    where.size.height = rect.size.height;
    
    CGContextDrawImage([[NSGraphicsContext currentContext] graphicsPort], where, cgImage);
    
    return YES;
}

- (BOOL)hasAlpha
{
    if (cgImage == NULL)
        return NO;
    
    switch(CGImageGetAlphaInfo(cgImage)) {
	case kCGImageAlphaNone:
	case kCGImageAlphaNoneSkipLast:
	case kCGImageAlphaNoneSkipFirst:
            return NO;
            
        case kCGImageAlphaPremultipliedLast:
	case kCGImageAlphaPremultipliedFirst:
	case kCGImageAlphaLast:
	case kCGImageAlphaFirst:
	case kCGImageAlphaOnly:
	default:
            return YES;
    }
    
    return NO;
}

- (NSInteger)pixelsHigh
{
    if (cgImage)
        return CGImageGetHeight(cgImage);
    return 0;
}

- (NSInteger)pixelsWide
{
    if (cgImage)
        return CGImageGetWidth(cgImage);
    return 0;
}

@end
