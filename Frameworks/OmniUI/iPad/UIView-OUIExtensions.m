// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUILoadedImage.h>
#import <OmniQuartz/OQDrawing.h>
#import <UIKit/UIView.h>

RCS_ID("$Id$");

@implementation UIView (OUIExtensions)

- (UIImage *)snapshotImage;
{
    UIImage *image;
    CGRect bounds = self.bounds;
    
    UIGraphicsBeginImageContext(bounds.size);
    {
        [self drawRect:bounds];
        image = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();
    
    return image;
}

- (UIView *)containingViewOfClass:(Class)cls; // can return self
{
    UIView *view = self;
    while (view) {
        if ([view isKindOfClass:cls])
            return view;
        view = view.superview;
    }
    return nil;
}

@end

#ifdef DEBUG // Uses private API
UIResponder *OUIWindowFindFirstResponder(UIWindow *window)
{
    return [window valueForKey:@"firstResponder"];
}

static void _OUIAppendViewTreeDescription(NSMutableString *str, UIView *view, NSUInteger indent)
{
    for (NSUInteger i = 0; i < indent; i++)
        [str appendString:@"  "];
    [str appendString:[view shortDescription]];
    
    for (UIView *subview in view.subviews)
        _OUIAppendViewTreeDescription(str, subview, indent + 1);
}

void OUILogViewTree(UIView *root)
{
    NSMutableString *str = [NSMutableString string];
    _OUIAppendViewTreeDescription(str, root, 0);
    
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    fwrite([data bytes], 1, [data length], stderr);
    fputc('\n', stderr);
}

#endif

static const CGFloat kPreviewShadowOffset = 4;
static const CGFloat kPreviewShadowRadius = 12;

static struct {
    OUILoadedImage top;
    OUILoadedImage bottom;
    OUILoadedImage left;
    OUILoadedImage right;
} ShadowImages;

static void LoadShadowImages(void)
{
    if (ShadowImages.top.image)
        return;
    
#if 0 && defined(DEBUG)
    // Code to make the shadow image (which I'll then dice up by hand into pieces).
    {
        CGColorSpaceRef graySpace = CGColorSpaceCreateDeviceGray();
        CGFloat totalShadowSize = kPreviewShadowOffset + kPreviewShadowRadius; // worst case; less on sides and top.
        CGSize imageSize = CGSizeMake(8*totalShadowSize, 8*totalShadowSize);
        
        CGFloat shadowComponents[] = {0, 0.5};
        CGColorRef shadowColor = CGColorCreate(graySpace, shadowComponents);
        UIImage *shadowImage;
        
        UIGraphicsBeginImageContext(imageSize);
        {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            
            CGRect imageBounds = CGRectMake(0, 0, imageSize.width, imageSize.height);
            OQFlipVerticallyInRect(ctx, imageBounds);
            
            CGRect boxRect = CGRectInset(imageBounds, totalShadowSize, totalShadowSize);
            
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, kPreviewShadowOffset), kPreviewShadowRadius, shadowColor);
            
            CGFloat whiteComponents[] = {1.0, 1.0};
            CGColorRef white = CGColorCreate(graySpace, whiteComponents);
            CGContextSetFillColorWithColor(ctx, white);
            CGColorRelease(white);

            CGContextFillRect(ctx, boxRect);
            
            shadowImage = UIGraphicsGetImageFromCurrentImageContext();
        }
        UIGraphicsEndImageContext();
        
        CGColorRelease(shadowColor);
        CFRelease(graySpace);

        NSData *shadowImagePNGData = UIImagePNGRepresentation(shadowImage);
        NSError *error = nil;
        NSString *path = [@"~/Documents/shadow.png" stringByExpandingTildeInPath];
        if (![shadowImagePNGData writeToFile:path options:0 error:&error])
            NSLog(@"Unable to write %@: %@", path, [error toPropertyList]);
        else
            NSLog(@"Wrote %@", path);
    }
#endif
    
    OUILoadImage(@"OUIShadowBorderBottom.png", &ShadowImages.bottom);
    OUILoadImage(@"OUIShadowBorderTop.png", &ShadowImages.top);
    OUILoadImage(@"OUIShadowBorderLeft.png", &ShadowImages.left);
    OUILoadImage(@"OUIShadowBorderRight.png", &ShadowImages.right);
    
}

static void _addShadowEdge(UIView *self, const OUILoadedImage *imageInfo, NSMutableArray *edges)
{
    UIView *edge = [[UIView alloc] init];
    edge.layer.needsDisplayOnBoundsChange = NO;
    [self addSubview:edge];
    
    edge.layer.contents = (id)[imageInfo->image CGImage];
    
    // Exactly one dimension should have an odd pixel count. This center column or row will get stretched via the contentsCenter property on the layer.
#ifdef OMNI_ASSERTIONS_ON
    CGSize imageSize = imageInfo->size;
#endif
    OBASSERT(imageSize.width == rint(imageSize.width));
    OBASSERT(imageSize.height == rint(imageSize.height));
    OBASSERT(((int)imageSize.width & 1) ^ ((int)imageSize.height & 1));
    
    /*
     contentsCenter is in normalized [0,1] coordinates, but the header also says:
     
     "As a special case, if the width or height is zero, it is implicitly adjusted to the width or height of a single source pixel centered at that position."
     
     */
    edge.layer.contentsCenter = CGRectMake(0.5, 0.5, 0, 0);
    
    [edges addObject:edge];
    [edge release];
}

NSArray *OUIViewAddShadowEdges(UIView *self)
{
    NSMutableArray *edges = [NSMutableArray array];
    
    LoadShadowImages();
    
    _addShadowEdge(self, &ShadowImages.bottom, edges);
    _addShadowEdge(self, &ShadowImages.top, edges);
    _addShadowEdge(self, &ShadowImages.left, edges);
    _addShadowEdge(self, &ShadowImages.right, edges);
    
    return edges;
}

void OUIViewLayoutShadowEdges(UIView *self, NSArray *shadowEdges, BOOL flipped)
{
    if ([shadowEdges count] != 4) {
        OBASSERT_NOT_REACHED("What sort of crazy geomtry is this?");
        return;
    }
    
    struct {
        UIView *bottom;
        UIView *top;
        UIView *left;
        UIView *right;
    } edges;
    
    [shadowEdges getObjects:(id *)&edges];
    
    
    CGRect bounds = self.bounds;
    

    // TODO: We'll want one or more multi-part images that have the shadow pre rendered and offset.
    static const CGFloat kShadowSize = 8;
    
    CGRect topRect = CGRectMake(CGRectGetMinX(bounds) - kShadowSize, CGRectGetMaxY(bounds), CGRectGetWidth(bounds) + 2*kShadowSize, kShadowSize);
    CGRect bottomRect = CGRectMake(CGRectGetMinX(bounds) - kShadowSize, CGRectGetMinY(bounds) - kShadowSize, CGRectGetWidth(bounds) + 2*kShadowSize, kShadowSize);
    
    if (flipped)
        SWAP(topRect, bottomRect);
    
    // These cover the corners too.
    edges.bottom.frame = bottomRect;
    edges.top.frame = topRect;
    
    edges.left.frame = CGRectMake(CGRectGetMinX(bounds) - kShadowSize, CGRectGetMinY(bounds), kShadowSize, CGRectGetHeight(bounds));
    edges.right.frame = CGRectMake(CGRectGetMaxX(bounds), CGRectGetMinY(bounds), kShadowSize, CGRectGetHeight(bounds));
}
