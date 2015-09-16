// Copyright 2006-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "CIImage-OQExtensions.h"

#import <OmniAppKit/NSLayoutManager-OAExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>

#import "OQAlphaScaleFilter.h"

RCS_ID("$Id$");

const CGFloat OQMakeImageAsWideAsNeededToAvoidWrapping = -1.0f;

@implementation CIImage (OQExtensions)

+ (CIImage *)imageWithAttributedString:(NSAttributedString *)attributedString maxWidth:(CGFloat)width targetContext:(CGContextRef)targetContext backgroundColor:(NSColor *)backgroundColor;
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CIImage *image = nil;
    CGLayerRef layer = NULL;
    NSGraphicsContext *oldContext = nil;
    BOOL oldContextSet = NO;
    
    @try {
	NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
	[layoutManager setBackgroundLayoutEnabled:NO];
	
	CGFloat containerWidth = (width == OQMakeImageAsWideAsNeededToAvoidWrapping) ? 1e9f : width;
	NSTextContainer *textContainer = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(containerWidth, 1e9f)] autorelease];
	[textContainer setLineFragmentPadding:0.0f];
	[layoutManager addTextContainer:textContainer];
	
	NSTextStorage *textStorage = [[[NSTextStorage alloc] initWithAttributedString:attributedString] autorelease];
	[textStorage addLayoutManager:layoutManager];

	// The fraction-of-a-pixel fudge factor is necessary on 10.7 and above. Not sure why. (bug #79474) TODO: Figure out if we're actually doing something wrong in -widthOfLongestLine, or if AppKit is just being inconsistent.
        width = (CGFloat)ceil([layoutManager widthOfLongestLine] + 0.125);
        [textContainer setContainerSize:NSMakeSize(width, 1e9f)];
	
	CGFloat height = (CGFloat)ceil([layoutManager totalHeightUsed]);
	
	layer = CGLayerCreateWithContext(targetContext, CGSizeMake(width, height), NULL);
	
	CGContextRef cgContext = CGLayerGetContext(layer);
	NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithGraphicsPort:cgContext flipped:YES];
	
	oldContext = [[[NSGraphicsContext currentContext] retain] autorelease];
	oldContextSet = YES;
	
	[NSGraphicsContext setCurrentContext:context];
	
	// Flip
	CGContextScaleCTM(cgContext, 1, -1);
	CGContextTranslateCTM(cgContext, 0, -height);
	
	if (backgroundColor) {
	    [backgroundColor set];
	    NSRectFill(NSMakeRect(0, 0, width, height));
	}
	
	NSRange glyphRange = NSMakeRange(0, [layoutManager numberOfGlyphs]);
	if (glyphRange.length) {
	    [layoutManager drawBackgroundForGlyphRange:glyphRange atPoint:NSZeroPoint];
	    [layoutManager drawGlyphsForGlyphRange:glyphRange atPoint:NSZeroPoint];
	}
	
	image = [[CIImage alloc] initWithCGLayer:layer];
    } @finally {
	if (oldContextSet) // oldContext might validly be nil
	    [NSGraphicsContext setCurrentContext:oldContext];
	CGLayerRelease(layer);
	[pool release];
    }
    
    return [image autorelease];
}

+ (CIImage *)imageWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color maxWidth:(CGFloat)width targetContext:(CGContextRef)targetContext backgroundColor:(NSColor *)backgroundColor;
{
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (font)
	[attributes setObject:font forKey:NSFontAttributeName];
    if (color)
	[attributes setObject:color forKey:NSForegroundColorAttributeName];
    
    NSAttributedString *attributedString = [[[NSAttributedString alloc] initWithString:string attributes:attributes] autorelease];
    
    return [self imageWithAttributedString:attributedString maxWidth:width targetContext:targetContext backgroundColor:backgroundColor];
}

// There is a private version of +imageWithColor:.  Radar #4532954 asks that it be made public.
+ (CIImage *)oci_imageWithColor:(CIColor *)color;
{
    OBPRECONDITION(color);
    
    CIFilter *constantColorGenerator = [CIFilter filterWithName:@"CIConstantColorGenerator"];
    [constantColorGenerator setValue:color forKey:@"inputColor"];
    
    return [constantColorGenerator valueForKey:@"outputImage"];
}

+ (CIImage *)oci_imageWithColor:(CIColor *)color extent:(CGRect)extent;
{
    return [[self oci_imageWithColor:color] imageByCroppingToExtent:extent];
}

- (CIImage *)imageByCroppingToExtent:(CGRect)extent;
{
    CIFilter *cropFilter = [CIFilter filterWithName:@"CICrop"];
    [cropFilter setValue:self forKey:@"inputImage"];
    [cropFilter setValue:[CIVector vectorWithX:CGRectGetMinX(extent) Y:CGRectGetMinY(extent) Z:CGRectGetWidth(extent) W:CGRectGetHeight(extent)] forKey:@"inputRectangle"];
    
    return [cropFilter valueForKey:@"outputImage"];
}

- (CIImage *)flippedImage;
{
    CGRect extent = [self extent];
    
    // We'd need to do a different affine transform if we wanted to preserve this, I think.
    OBASSERT(extent.origin.x == 0.0);
    OBASSERT(extent.origin.y == 0.0);
    
    // Flip the result
    CIFilter *flipFilter = [CIFilter filterWithName:@"CIAffineTransform"];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleXBy:1.0f yBy:-1.0f];
    [transform translateXBy:0.0f yBy:-extent.size.height];
    [flipFilter setValue:transform forKey:@"inputTransform"];
    [flipFilter setValue:self forKey:@"inputImage"];
    
    return [flipFilter valueForKey:@"outputImage"];
}

- (CIImage *)imageByScalingAlphaBy:(CGFloat)alphaScale;
{
    NSLog(@"filters = %@", [CIFilter filterNamesInCategories:[NSArray array]]);
	  
    OQAlphaScaleFilter *filter = [[OQAlphaScaleFilter alloc] init];
    
    [filter setValue:self forKey:@"inputImage"];
    [filter setValue:[NSNumber numberWithCGFloat:alphaScale] forKey:@"inputScale"];
    
    CIImage *outputImage = [filter valueForKey:@"outputImage"];
    [filter release];
    
    return outputImage;
}

- (CIImage *)imageBySourceOverCompositingWithBackgroundImage:(CIImage *)backgroundImage;
{    
    CIFilter *filter = [CIFilter filterWithName:@"CISourceOverCompositing"];
    
    [filter setValue:self forKey:@"inputImage"];
    [filter setValue:backgroundImage forKey:@"inputBackgroundImage"];
    
    return [filter valueForKey:@"outputImage"];
}

- (CIImage *)imageBySourceAtopCompositingWithBackgroundImage:(CIImage *)backgroundImage;
{    
    CIFilter *filter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    
    [filter setValue:self forKey:@"inputImage"];
    [filter setValue:backgroundImage forKey:@"inputBackgroundImage"];
    
    return [filter valueForKey:@"outputImage"];
}

- (CIImage *)imageByScalingToSize:(CGSize)size;
{
    CGRect extent = [self extent];
    OBASSERT(extent.origin.x == 0); // we'd need to do extra work to deal with non-zero origins when scaling
    OBASSERT(extent.origin.y == 0);
    
    CGFloat xScale = size.width / extent.size.width;
    CGFloat yScale = size.height / extent.size.height;
    
    CIFilter *scaleFilter = [CIFilter filterWithName:@"CIAffineTransform"];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleXBy:xScale yBy:yScale];
    [scaleFilter setValue:transform forKey:@"inputTransform"];
    [scaleFilter setValue:self forKey:@"inputImage"];
    
    return [scaleFilter valueForKey:@"outputImage"];
}

- (CIImage *)imageByTranslating:(CGPoint)offset;
{
    CIFilter *filter = [CIFilter filterWithName:@"CIAffineTransform"];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:offset.x yBy:offset.y];
    [filter setValue:transform forKey:@"inputTransform"];
    [filter setValue:self forKey:@"inputImage"];
    
    return [filter valueForKey:@"outputImage"];
}

- (CIImage *)imageByScaling:(CGSize)size;
{
    CIFilter *filter = [CIFilter filterWithName:@"CIAffineTransform"];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleXBy:size.width yBy:size.height];
    [filter setValue:transform forKey:@"inputTransform"];
    [filter setValue:self forKey:@"inputImage"];
    
    return [filter valueForKey:@"outputImage"];
}

- (CIImage *)imageByRotatingByRadians:(CGFloat)radians;
{
    CIFilter *filter = [CIFilter filterWithName:@"CIAffineTransform"];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform rotateByRadians:radians];
    [filter setValue:transform forKey:@"inputTransform"];
    [filter setValue:self forKey:@"inputImage"];
    
    return [filter valueForKey:@"outputImage"];
}

@end
