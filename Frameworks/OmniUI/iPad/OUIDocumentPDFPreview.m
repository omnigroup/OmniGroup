// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPDFPreview.h>

// Only needed when enabling the debug code below.
//#import <OmniFoundation/CFData-OFExtensions.h>
//#import <OmniFoundation/NSData-OFEncoding.h>

#import <OmniUI/OUIDocumentProxyView.h>

RCS_ID("$Id$");

@implementation OUIDocumentPDFPreview

- initWithData:(NSData *)pdfData originalViewSize:(CGSize)originalViewSize;
{
    if (!(self = [super init]))
        return nil;
    
    //NSLog(@"creating PDF preview %@ from pdfData %@", [self shortDescription], [[(NSData *)OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)pdfData) autorelease] unadornedLowercaseHexString]);
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)pdfData);
    if (!provider) {
        [self release];
        return nil;
    }
    _document = CGPDFDocumentCreateWithProvider(provider);
    CFRelease(provider);
    
    if (!_document) {
        [self release];
        return nil;
    }
    
    size_t pageCount = CGPDFDocumentGetNumberOfPages(_document);
    OBASSERT(pageCount >= 1);
    if (pageCount < 1) { // In case the above assertion fails
        [self release];
        return nil;
    }
    
    _page = (CGPDFPageRef)CFRetain(CGPDFDocumentGetPage(_document, 1)); // 1-indexed. Sigh.
    OBASSERT(_page);
    if (!_page) {
        [self release];
        return nil;
    }
    
    _rect = CGPDFPageGetBoxRect(_page, kCGPDFMediaBox);
    if (CGRectIsEmpty(_rect)) {
        OBASSERT_NOT_REACHED("Should have a valid rect");
        [self release];
        return nil;
    }
    
    _originalViewSize = originalViewSize;
    
    return self;
}

- (void)dealloc;
{
    if (_document)
        CFRelease(_document);
    if (_page)
        CFRelease(_page);
    [_cachedImage release];
    [super dealloc];
}

// cxt should already have the appropriate transform set up.
- (void)drawInTransformedContext:(CGContextRef)ctx;
{
    CGContextDrawPDFPage(ctx, _page);
}

- (void)cacheImageOfSize:(CGSize)size;
{
    /****
     * UIKit's graphics contexts functions aren't thread safe in pre-4.2 (which some of our apps are still targetting).
     * In particular, UIGraphicsPushContext is documented to be thread-unsafe.
     * So, we have to use CG directly through all this code. No UIImage, UIColor, etc.
     ****/
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, size.width, size.height, 8, 4*size.width, rgbColorSpace, kCGImageAlphaPremultipliedFirst);
    CFRelease(rgbColorSpace);
    
    OUIDocumentProxyDrawPreview(ctx, self, CGRectMake(0, 0, size.width, size.height));
    CGImageRef imageRef = CGBitmapContextCreateImage(ctx);
    CFRelease(ctx);
    
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    
    self.cachedImage = image;
}
   
#pragma mark -
#pragma mark OUIDocumentPreview

- (BOOL)isScalable;
{
    return YES;
}

- (BOOL)isValidAtSize:(CGSize)targetSize;
{
    return CGSizeEqualToSize(targetSize, _originalViewSize);
}

- (CGAffineTransform)transformForTargetRect:(CGRect)targetRect;
{
    // We want our PDF to touch at least one pair of rect edges, but CGPDFPageGetDrawingTransform will not scale up.
    
    // Find out what CG would scale to, given this size (at a zero origin!)
    CGAffineTransform xform = CGPDFPageGetDrawingTransform(_page, kCGPDFMediaBox, CGRectMake(0, 0, targetRect.size.width, targetRect.size.height), 0/*rotate*/, true/*preserveAspectRatio*/);

    // If the source PDF's page rect is too small to fit in this area, CG won't scale it up and will instead center it.  Move to the origin in that case.
    CGRect transformedRect = CGRectApplyAffineTransform(_rect, xform);

    if (transformedRect.origin.x != 0)
        xform = CGAffineTransformTranslate(xform, -transformedRect.origin.x, 0);
    if (transformedRect.origin.y != 0)
        xform = CGAffineTransformTranslate(xform, 0, -transformedRect.origin.y);
    transformedRect.origin = CGPointZero;

    // Figure out how much space is left on the edges.
    CGFloat spaceX = targetRect.size.width - transformedRect.size.width;
    CGFloat spaceY = targetRect.size.height - transformedRect.size.height;
    
    // CG shouldn't make the output bigger than we asked for, allowing slop for FP.
    OBASSERT(spaceX > -0.0001);
    OBASSERT(spaceY > -0.0001);
    
    // If there is extra space on both axes, scale up as much as we can.
    if (spaceX > 1 && spaceY > 1) {
        CGFloat scaleX = targetRect.size.width / transformedRect.size.width;
        CGFloat scaleY = targetRect.size.height / transformedRect.size.height;
        CGFloat scale = MIN(scaleX, scaleY);

        xform = CGAffineTransformScale(xform, scale, scale);

        // Recompute the available space
        transformedRect = CGRectApplyAffineTransform(_rect, xform);
        spaceX = targetRect.size.width - transformedRect.size.width;
        spaceY = targetRect.size.height - transformedRect.size.height;
    }
    
    // If there is space available on one axis, center on that axis.
    if (spaceX > 0)
        xform = CGAffineTransformTranslate(xform, spaceX/2, 0);
    if (spaceY > 0)
        xform = CGAffineTransformTranslate(xform, 0, spaceY/2);

    return xform;
}

@synthesize untransformedPageRect = _rect;
@synthesize cachedImage = _cachedImage;

@end
