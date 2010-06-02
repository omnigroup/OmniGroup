// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPreviewLoadOperation.h"

#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIDocumentProxyView.h>
#import "OUIDocumentPDFPreview.h"

RCS_ID("$Id$");

@implementation OUIDocumentPreviewLoadOperation

- initWithProxy:(OUIDocumentProxy *)proxy size:(CGSize)size;
{
#ifdef IPAD_RETAIL_DEMO
    // Terrible terrible hack--I mean, this is the best!
    // Hack to fix <bug://bugs/61625> (Modifying welcome doc on first launch and going to picker only loads low-res preview)
    // For now, if we get the bogus small previous size let's just use a previous size of 584x730 instead (which is the largest preview size we're asked to render for the Welcome document).
    if (size.width == 444.0f && size.height == 345.0f) {
        size.width = 584.0f;
        size.height = 730.0f;
    }
#endif
    
    if (!(self = [super init]))
        return nil;
    
    _proxy = [proxy retain];
    _size = size;
    
    return self;
}

- (void)dealloc;
{
    [_proxy release];
    [super dealloc];
}

- (void)main;
{
    OBPRECONDITION(![NSThread isMainThread]);
    
    NSError *error = nil;
    NSData *pdfData = nil;
        
#if 0 && defined(DEBUG)
    sleep(1);
#endif
    
    if (![[_proxy class] getPDFPreviewData:&pdfData modificationDate:NULL fromURL:_proxy.url error:&error]) {
        NSLog(@"Unable to load preview from %@: %@", _proxy.url, [error toPropertyList]);
        [_proxy performSelectorOnMainThread:@selector(previewDidLoad:) withObject:error waitUntilDone:NO];
        return;
    }
    
    // Don't call -view here... probably just paranoia since the view should already be loaded, but we don't want to provoke view loading in the background.
    OUIDocumentPDFPreview *preview = pdfData ? [[OUIDocumentPDFPreview alloc] initWithData:pdfData originalViewSize:_size] : nil;
    
    /****
     * UIKit's graphics contexts functions aren't thread safe. In particular, UIGraphicsPushContext is documented to be thread-unsafe.
     * So, we have to use CG directly through all this code. No UIImage, UIColor, etc.
     ****/
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, _size.width, _size.height, 8, 4*_size.width, rgbColorSpace, kCGImageAlphaPremultipliedFirst);
    CFRelease(rgbColorSpace);

    OUIDocumentProxyDrawPreview(ctx, preview, CGRectMake(0, 0, _size.width, _size.height));
    CGImageRef imageRef = CGBitmapContextCreateImage(ctx);
    CFRelease(ctx);
    
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);

    preview.cachedImage = image;
    
    [_proxy performSelectorOnMainThread:@selector(previewDidLoad:) withObject:preview waitUntilDone:NO];
    [preview release];
}

@end
