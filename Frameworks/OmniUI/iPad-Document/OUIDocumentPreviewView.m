// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPreviewView.h>

#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniQuartz/CALayer-OQExtensions.h>

#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

void OUIDocumentPreviewViewSetNormalBorder(UIView *view)
{
    view.layer.borderColor = [[UIColor colorWithWhite:0.5 alpha:1.0] CGColor];
    view.layer.borderWidth = 1.0 / [view contentScaleFactor];
}

void OUIDocumentPreviewViewSetLightBorder(UIView *view)
{
    view.layer.borderColor = [[UIColor colorWithWhite:0.9 alpha:1.0] CGColor];
    view.layer.borderWidth = 1.0 / [view contentScaleFactor];
}

@implementation OUIDocumentPreviewView
{
    UIImageView *_imageView;
    BOOL _draggingSource;
    BOOL _highlighted;
    BOOL _downloadRequested;
}

static id _commonInit(OUIDocumentPreviewView *self)
{
    // Our containing OUIDocumentPickerItemView should get taps that hit us.
    self.userInteractionEnabled = NO;
    
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    imageView.hidden = YES;
    self->_imageView = imageView;
    [self addSubview:imageView];
    
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
    [_preview decrementDisplayCount];
}

@synthesize draggingSource = _draggingSource;
- (void)setDraggingSource:(BOOL)draggingSource;
{
    if (_draggingSource == draggingSource)
        return;
    
    _draggingSource = draggingSource;
    
    [self _updateAlpha];
}

@synthesize highlighted = _highlighted;
- (void)setHighlighted:(BOOL)highlighted;
{
    if (_highlighted == highlighted)
        return;
    
    _highlighted = highlighted;
    
    [self _updateAlpha];
}

@synthesize preview=_preview;
- (void)setPreview:(OUIDocumentPreview *)newPreview;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_PREVIEW_DISPLAY(@"%p setPreview: %@", self, [(id)newPreview shortDescription]);
    
    if (_preview == newPreview)
        return;
    
    [newPreview incrementDisplayCount];
    [_preview decrementDisplayCount];
    _preview = newPreview;
    
    // don't animate if we aren't in a window or if the ItemView containing us is hidden
    if (self.window != nil && !self.superview.superview.hidden && [UIView areAnimationsEnabled]) {
        [UIView transitionWithView:self duration:kOUIDocumentPreviewViewTransitionDuration options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionTransitionCrossDissolve animations:^{
            if (_preview) {
                _imageView.hidden = NO;
                _imageView.image = [UIImage imageWithCGImage:_preview.image];
            } else {
                _imageView.image = nil;
                _imageView.hidden = YES;
            }
        } completion:nil];
    } else {
        if (_preview) {
            _imageView.hidden = NO;
            _imageView.image = [UIImage imageWithCGImage:_preview.image];
        } else {
            _imageView.image = nil;
            _imageView.hidden = YES;
        }        
    }
}

- (void)drawLayer:(CALayer *)layer inVectorContext:(CGContextRef)ctx;
{
    [_imageView.image drawInRect:self.bounds];
    if (self.layer.borderWidth) {
        CGContextSetStrokeColorWithColor(ctx, self.layer.borderColor);
        CGContextStrokeRect(ctx, CGRectInset(self.bounds, 0.5, 0.5));
    }
}

@synthesize downloadRequested = _downloadRequested;
- (void)setDownloadRequested:(BOOL)downloadRequested;
{
    if (_downloadRequested == downloadRequested)
        return;
    
    _downloadRequested = downloadRequested;

    [self _updateAlpha];
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

- (void)_updateAlpha;
{
    CGFloat alpha = 1.0f;
    
    if (_highlighted || _downloadRequested)
        alpha = kOUIDocumentPreviewHighlightAlpha;
    
    self.layer.opacity = alpha;
}

@end

