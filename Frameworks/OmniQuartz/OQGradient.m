// Copyright 2003-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQGradient.h>

RCS_ID("$Id$")

CGImageRef OQCreateVerticalGradientImage(CGGradientRef gradient, CFStringRef colorSpaceName, size_t height, BOOL opaque, BOOL flip)
{
    size_t width = 1;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(colorSpaceName);
    
    size_t componentCount = CGColorSpaceGetNumberOfComponents(colorSpace);
    CGImageAlphaInfo alphaInfo;
    
    if (opaque) {
        alphaInfo = kCGImageAlphaNone;
    } else {
        // gray+alpha isn't supported, but alpha-only is (seem to be {black,alpha}). Unclear if you can make it {white,alpha} or any generic color).  Sadly, at least in some cases alpha-only seems to have some weird issues (see OQHoleLayer). So, upsample to RGBA.
        CGColorSpaceRelease(colorSpace);
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
        componentCount = 4;
        alphaInfo = kCGImageAlphaPremultipliedFirst;
    }
    
    size_t bytesPerRow = componentCount * width;
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8/*bitsPerComponent*/, bytesPerRow, colorSpace, alphaInfo);
    CFRelease(colorSpace);
    
    CGRect bounds = CGRectMake(0, 0, width, height);
    CGContextAddRect(ctx, bounds);
    CGContextClip(ctx);
    
    CGPoint startPoint = bounds.origin;
    CGPoint endPoint = (CGPoint){ CGRectGetMinX(bounds), CGRectGetMaxY(bounds) };
    
    if (flip)
        SWAP(startPoint, endPoint);
    
    CGContextDrawLinearGradient(ctx, gradient, startPoint, endPoint, 0/*options*/);
    
    CGContextFlush(ctx);
    CGImageRef gradientImage = CGBitmapContextCreateImage(ctx);
    CFRelease(ctx);
    
    return gradientImage;
}

CGGradientRef OQCreateVerticalGrayGradient(CGFloat minGray, CGFloat maxGray)
{
    CGColorRef minGrayColorRef = CGColorCreateGenericGray(minGray, 1.0f);
    CGColorRef maxGrayColorRef = CGColorCreateGenericGray(maxGray, 1.0f);    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (CFArrayRef)[NSArray arrayWithObjects:(id)minGrayColorRef, (id)maxGrayColorRef, nil], NULL/*locations -> evenly spaced*/);
    CFRelease(minGrayColorRef);
    CFRelease(maxGrayColorRef);
    CFRelease(colorSpace);
    
    return gradient;
}


