// Copyright 2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ImageAttachmentCell.h"

#import <ImageIO/CGImageSource.h>

RCS_ID("$Id$");

@interface ImageAttachmentCell ()
- (void)_cacheImage;
@end

@implementation ImageAttachmentCell

- (void)dealloc;
{
    if (_image)
        CFRelease(_image);
    [super dealloc];
}

#pragma mark -
#pragma mark OATextAttachmentCell subclass

- (void)drawWithFrame:(CGRect)cellFrame inView:(UIView *)controlView;
{
    [self _cacheImage];
    if (!_image)
        return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextDrawImage(ctx, cellFrame, _image);
}

- (CGSize)cellSize;
{
    [self _cacheImage];
    return _image ? CGSizeMake(CGImageGetWidth(_image), CGImageGetHeight(_image)) : CGSizeZero;
}

#pragma mark -
#pragma mark Private

- (void)_cacheImage;
{
    if (_image)
        return;
    
    NSFileWrapper *fileWrapper = self.attachment.fileWrapper;
    OBASSERT(fileWrapper);
    OBASSERT([fileWrapper isRegularFile]);
    
    // The caller should make sure we don't get instantiated for something that isn't an image. Also, a real implementation would have a PDF specific path that would potentially draw via CGPDF* for printing instead of (or in addition to) caching a bitmap (for screen). We also might want to flush our image cache if we get scrolled off screen... Probably lots of room for optimization.
    
    CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)[fileWrapper regularFileContents]);
    if (!dataProvider) {
        OBASSERT_NOT_REACHED("Unable to create the data provider");
        return;
    }
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithDataProvider(dataProvider, NULL/*options*/);
    CFRelease(dataProvider);
    if (!imageSource) {
        OBASSERT_NOT_REACHED("Unable to create the image source");
        return;
    }

    size_t imageCount = CGImageSourceGetCount(imageSource);
    if (imageCount == 0) {
        CFRelease(imageSource);
        OBASSERT_NOT_REACHED("No images found");
        return;
    }

    _image = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL/*options*/);
    CFRelease(imageSource);

    OBPOSTCONDITION(_image);
}

@end
