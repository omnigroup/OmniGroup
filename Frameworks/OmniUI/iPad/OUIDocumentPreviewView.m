// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPreviewView.h>

#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQDrawing.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIDocumentPreviewView
{
    NSMutableArray *_previews;
    
    BOOL _group;
    BOOL _selected;
    BOOL _draggingSource;
    
    NSTimeInterval _animationDuration;
    UIViewAnimationCurve _animationCurve;

    UIImageView *_statusImageView;
    UIProgressView *_transferProgressView;
}

static id _commonInit(OUIDocumentPreviewView *self)
{
    self.opaque = NO;
    self.clearsContextBeforeDrawing = YES;
    self.contentMode = UIViewContentModeScaleAspectFit;
    
    self->_statusImageView = [[UIImageView alloc] initWithImage:nil];
    [self addSubview:self->_statusImageView];
    self->_statusImageView.hidden = YES;
    
    self->_transferProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [self addSubview:self->_transferProgressView];
    self->_transferProgressView.hidden = YES;
    
    // Flatten the status image and progress view into our buffer. This means that if we are in Edit mode and the doing a wiggle animation, the progress view (in particular) won't get ugly aliased edges.
    self.layer.shouldRasterize = YES;
    
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [_previews release];
    [_statusImageView release];
    [_transferProgressView release];
    [super dealloc];
}

@synthesize group = _group;
- (void)setGroup:(BOOL)group;
{
    if (_group == group)
        return;
    
    _group = group;
    [self setNeedsDisplay];
}

@synthesize selected = _selected;
- (void)setSelected:(BOOL)selected;
{
    if (_selected == selected)
        return;
    
    _selected = selected;
    
    [self.superview setNeedsLayout]; // -previewRectInFrame: changes based on the selection state
    [self setNeedsDisplay];
}

@synthesize draggingSource = _draggingSource;
- (void)setDraggingSource:(BOOL)draggingSource;
{
    if (_draggingSource == draggingSource)
        return;
    
    _draggingSource = draggingSource;
    [self setNeedsLayout]; // no shadow
    [self setNeedsDisplay]; // special image
}

@synthesize previews = _previews;

- (void)addPreview:(OUIDocumentPreview *)preview;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(preview);
    OBPRECONDITION(!_previews || [_previews indexOfObjectIdenticalTo:preview] == NSNotFound);
    
    OBFinishPortingLater("Maintain the previews the sorted order that our enclosing picker is using.");
    
    if (!_previews)
        _previews = [[NSMutableArray alloc] init];
    
    // Files should only have one preview. We might hold onto one while refreshing, though.
    if (!_group)
        [_previews removeAllObjects];
    [_previews addObject:preview];
    
    PREVIEW_DEBUG(@"%p addPreview: %@", self, [(id)preview shortDescription]);

    // Our frame gets set by our superview based on our preview size
    [self.superview setNeedsLayout];
    
    [self setNeedsDisplay];
}

- (void)discardPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);

    if ([_previews count] == 0)
        return;
    
    PREVIEW_DEBUG(@"%p discardPreviews", self);

    [_previews removeAllObjects];
    [self setNeedsDisplay];
}

#define kOUIDocumentPreviewViewNormalShadowInsets UIEdgeInsetsMake(ceil(kOUIDocumentPreviewViewNormalShadowBlur)/*top*/, ceil(kOUIDocumentPreviewViewNormalShadowBlur)/*left*/, ceil(kOUIDocumentPreviewViewNormalShadowBlur + 1)/*bottom*/, ceil(kOUIDocumentPreviewViewNormalShadowBlur)/*right*/)

static CGRect _outsetRect(CGRect rect, UIEdgeInsets insets)
{
    UIEdgeInsets outsets = {
        .top = -insets.top,
        .bottom = -insets.bottom,
        .left = -insets.left,
        .right = -insets.right,
    };
    return UIEdgeInsetsInsetRect(rect, outsets);
}

- (UIEdgeInsets)_edgeInsets;
{
    UIEdgeInsets insets;
    
    if (_selected) {
        // Room for the selection border image
        insets = kOUIDocumentPreviewViewBorderEdgeInsets;
    } else if (_draggingSource) {
        // No shadow
        insets = UIEdgeInsetsZero;
    } else {
        // Normal shadow
        insets = kOUIDocumentPreviewViewNormalShadowInsets;
    }
    
    // space for edge antialiasing    
    insets.top += 1;
    insets.bottom += 1;
    insets.left += 1;
    insets.right += 1;
    
    return insets;
}

// Could use -sizeThatFits:, but that would require the caller to center the size... just as easy to define our own API
- (CGRect)previewRectInFrame:(CGRect)frame;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_group) {
        return CGRectInset(frame, 16, 16); // ... or something
    } else {
        OUIDocumentPreview *preview = [_previews lastObject];
        
        CGRect previewFrame;
        if (preview)
            previewFrame = OQLargestCenteredIntegralRectInRectWithAspectRatioAsSize(frame, preview.size);
        else
            previewFrame = frame; // If we return CGRectNull here, and there is a bug where previews never load, you can't select the file to delete it.
        
        return _outsetRect(previewFrame, [self _edgeInsets]);
    }
}

@synthesize animationDuration = _animationDuration;
@synthesize animationCurve = _animationCurve;

- (UIImage *)statusImage;
{
    return _statusImageView.image;
}
- (void)setStatusImage:(UIImage *)image;
{
    if (self.statusImage == image)
        return;

    _statusImageView.image = image;
    _statusImageView.hidden = (image == nil);
    
    [self setNeedsLayout];
}

- (BOOL)showsProgress;
{
    return _transferProgressView.hidden == NO;
}
- (void)setShowsProgress:(BOOL)showsProgress;
{
    _transferProgressView.hidden = (showsProgress == NO);
}

- (double)progress;
{
    return _transferProgressView.progress;
}
- (void)setProgress:(double)progress;
{
    _transferProgressView.progress = progress;
}

#pragma mark -
#pragma mark UIView (OUIExtensions)

- (UIImage *)snapshotImage;
{
    if (_group) {
        OBFinishPortingLater("Want a special case for this?");
    } else if (!_draggingSource) {
        // If we have one, return the image we already have for the document picker open/close animation.
        // Note: this may have a tiny glitch due to the 1px inset to avoid edge aliasing issues.
        OBASSERT([_previews count] <= 1);
        OUIDocumentPreview *preview = [_previews lastObject];
        
        if (preview.type == OUIDocumentPreviewTypeRegular)
            return preview.image;
    }
    
    return [super snapshotImage];
}

#pragma mark -
#pragma mark UIView subclass

#ifdef OMNI_ASSERTIONS_ON
- (void)setFrame:(CGRect)frame;
{
    OBPRECONDITION(CGRectEqualToRect(frame, CGRectIntegral(frame)));
    [super setFrame:frame];
}
#endif

- (void)layoutSubviews;
{
    CGRect bounds = self.bounds;
    if (CGRectEqualToRect(bounds, CGRectZero))
        return; // Not configured yet.
    
    CGRect previewFrame = UIEdgeInsetsInsetRect(bounds, [self _edgeInsets]);

    UIImage *statusImage = _statusImageView.image;
    if (statusImage) {
        CGSize statusImageSize = statusImage.size;
        CGRect statusFrame = CGRectMake(CGRectGetMaxX(previewFrame) - statusImageSize.width, CGRectGetMinY(previewFrame), statusImageSize.width, statusImageSize.height);
        
        OUIWithoutAnimating(^{
            _statusImageView.frame = statusFrame;
            _statusImageView.hidden = NO;
        });
    } else {
        OUIWithoutAnimating(^{
            _statusImageView.hidden = YES;
        });
    }

    OUIWithoutAnimating(^{
        CGRect previewFrameInsetForProgress = CGRectInset(previewFrame, 16, 16);
        CGRect progressFrame = previewFrameInsetForProgress;
        
        progressFrame.size.height = [_transferProgressView sizeThatFits:progressFrame.size].height;
        progressFrame.origin.y = CGRectGetMaxY(previewFrameInsetForProgress) - progressFrame.size.height;
        
        _transferProgressView.frame = progressFrame;
    });
}

- (void)drawRect:(CGRect)rect;
{
    if (_group) {
        // Disabled for now since we get added to the view hierarchy and drawn once while we are hidden (during closing a document, for example), as previews are loading.
        //OBASSERT([_previews count] >= 1); // can have a group with 1 item

        // 3x3 grid of previews
        const CGFloat kPreviewPadding = 8;
        const NSUInteger kPreviewsPerRow = 3;
        const NSUInteger kPreviewRows = 3;
        
        CGRect bounds = self.bounds;
        CGSize previewSize = CGSizeMake((bounds.size.width - (kPreviewsPerRow + 1)*kPreviewPadding) / kPreviewsPerRow,
                                        (bounds.size.height - (kPreviewRows + 1)*kPreviewPadding) / kPreviewRows);
        
        [[UIColor blackColor] set];
        UIRectFill(bounds);
        
        NSUInteger previewCount = [_previews count];
        for (NSUInteger row = 0; row < kPreviewRows; row++) {
            for (NSUInteger column = 0; column < kPreviewsPerRow; column++) {
                NSUInteger previewIndex = row * kPreviewsPerRow + column;
                if (previewIndex >= previewCount)
                    break;
                
                CGPoint pt = bounds.origin;
                pt.x += ceil(column * previewSize.width + kPreviewPadding);
                pt.y += ceil(row * previewSize.height + kPreviewPadding);
                
                OUIDocumentPreview *preview = [_previews objectAtIndex:previewIndex];

                [preview drawInRect:CGRectMake(pt.x, pt.y, previewSize.width, previewSize.height)];
            }
        }
    } else {
        OBASSERT([_previews count] <= 1);
        
        CGRect previewRect = CGRectInset(self.bounds, 1, 1); // space for edge antialiasing
              
        if (_draggingSource) {
            OBFinishPortingLater("Do empty box look");
            
            [[UIColor blueColor] set];
            UIRectFill(previewRect);
            
        } else {
            OUIDocumentPreview *preview = [_previews lastObject];
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            
            BOOL drawingShadow = NO;
            
            if (_selected) {
                UIImage *image = [UIImage imageNamed:@"OUIDocumentPreviewViewSelectedBorder.png"];
                OBASSERT(image);
                
                image = [image resizableImageWithCapInsets:kOUIDocumentPreviewViewBorderEdgeInsets];
                [image drawInRect:previewRect];
                
                previewRect = UIEdgeInsetsInsetRect(previewRect, kOUIDocumentPreviewViewBorderEdgeInsets);
            } else if (_draggingSource) {
                // No shadow
            } else {
                // Normal preview
                drawingShadow = YES;
                CGContextSaveGState(ctx);
                
                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
                CGFloat shadowComponents[] = {kOUIDocumentPreviewViewNormalShadowWhiteAlpha.w, kOUIDocumentPreviewViewNormalShadowWhiteAlpha.a};
                CGColorRef shadowColor = CGColorCreate(colorSpace, shadowComponents);
                CGColorSpaceRelease(colorSpace);
                
                CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), kOUIDocumentPreviewViewNormalShadowBlur, shadowColor);
                CGColorRelease(shadowColor);
                
                // Leave room for the shadow
                previewRect = UIEdgeInsetsInsetRect(previewRect, kOUIDocumentPreviewViewNormalShadowInsets);
            }
            
            if (!preview || preview.type != OUIDocumentPreviewTypeRegular) {
                [[UIColor whiteColor] set];
                UIRectFill(previewRect);
            }
            
            [preview drawInRect:previewRect];

            if (drawingShadow) {
                CGContextRestoreGState(ctx);
            }
        }
    }
}

@end

