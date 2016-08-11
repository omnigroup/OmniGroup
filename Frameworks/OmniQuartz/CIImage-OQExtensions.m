// Copyright 2006-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/CIImage-OQExtensions.h>

#import <OmniAppKit/NSLayoutManager-OAExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>

#import <OmniQuartz/OQAlphaScaleFilter.h>

RCS_ID("$Id$");

const CGFloat OQMakeImageAsWideAsNeededToAvoidWrapping = -1.0f;

@implementation CIImage (OQExtensions)

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
