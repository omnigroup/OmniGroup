// Copyright 2006-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <QuartzCore/CIImage.h>

@class NSAttributedString, NSColor, NSFont;

extern const CGFloat OAMakeImageAsWideAsNeededToAvoidWrapping;

@interface CIImage (OQExtensions)
+ (CIImage *)imageWithAttributedString:(NSAttributedString *)attributedString maxWidth:(CGFloat)width targetContext:(CGContextRef)targetContext backgroundColor:(NSColor *)backgroundColor;
+ (CIImage *)imageWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color maxWidth:(CGFloat)width targetContext:(CGContextRef)targetContext backgroundColor:(NSColor *)backgroundColor;

+ (CIImage *)oci_imageWithColor:(CIColor *)color;
+ (CIImage *)oci_imageWithColor:(CIColor *)color extent:(CGRect)extent;

- (CIImage *)imageByCroppingToExtent:(CGRect)extent;
- (CIImage *)flippedImage;
- (CIImage *)imageByScalingAlphaBy:(CGFloat)alphaScale;
- (CIImage *)imageBySourceOverCompositingWithBackgroundImage:(CIImage *)backgroundImage;
- (CIImage *)imageBySourceAtopCompositingWithBackgroundImage:(CIImage *)backgroundImage;
- (CIImage *)imageByScalingToSize:(CGSize)size;
- (CIImage *)imageByTranslating:(CGPoint)offset;
- (CIImage *)imageByScaling:(CGSize)size;
- (CIImage *)imageByRotatingByRadians:(CGFloat)radians;

@end
