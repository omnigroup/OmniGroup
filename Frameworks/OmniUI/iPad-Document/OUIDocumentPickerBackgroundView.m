// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerBackgroundView.h>

RCS_ID("$Id$");

static NSString * const EditingAnimation = @"OUIDocumentPickerBackgroundView.editing";

@implementation OUIDocumentPickerBackgroundView

static id _commonInit(OUIDocumentPickerBackgroundView *self)
{    
    CALayer *layer = self.layer;
    layer.edgeAntialiasingMask = 0;
    layer.needsDisplayOnBoundsChange = YES;
    layer.contentsGravity = kCAGravityBottom;
    layer.backgroundColor = [[UIColor blackColor] CGColor];
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
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

static UIImage *_imageForEditing(OUIDocumentPickerBackgroundView *self, BOOL editing)
{
    CGRect bounds = self.bounds;
    UIImage *image;
    
    if (bounds.size.width > bounds.size.height) {
        if (editing)
            image = [UIImage imageNamed:@"OUIFilePickerBackground-Hardboard-Horizontal-Editing.jpg"];
        else
            image = [UIImage imageNamed:@"OUIFilePickerBackground-Hardboard-Horizontal.jpg"];
    } else {
        if (editing)
            image = [UIImage imageNamed:@"OUIFilePickerBackground-Hardboard-Vertical-Editing.jpg"];
        else
            image = [UIImage imageNamed:@"OUIFilePickerBackground-Hardboard-Vertical.jpg"];
    }
    
    OBASSERT(image);
    return image;
}

@synthesize editing = _editing;
- (void)setEditing:(BOOL)editing;
{
    if (_editing == editing)
        return;
    
    if (![CATransaction disableActions]) {
        OBASSERT([self.layer animationForKey:EditingAnimation] == nil);
        
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"contents"];
        anim.fromValue = (id)[_imageForEditing(self, _editing) CGImage];
        anim.toValue = (id)[_imageForEditing(self, editing) CGImage];
        anim.fillMode = kCAFillModeForwards;
        [self.layer addAnimation:anim forKey:EditingAnimation];
    }
    
    _editing = editing;
    
    // Make sure the final version gets updated for when our animation is removed
    [self.layer setNeedsDisplay];
}

#pragma mark -
#pragma mark UIView

- (void)displayLayer:(CALayer *)layer;
{
    // Don't animate this implicitly; we want this to act like a synchronous drawing in UIView. We have an explicit animation above in -setEditing:
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanFalse forKey:(id)kCATransactionDisableActions];
    {
        UIImage *image = _imageForEditing(self, _editing);
        layer.contents = (id)[image CGImage];
        layer.contentsScale = [image scale];
    }
    [CATransaction commit];
}

@end
