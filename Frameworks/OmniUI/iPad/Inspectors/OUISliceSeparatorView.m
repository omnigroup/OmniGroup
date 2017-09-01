// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISliceSeparatorView.h"
#import <OmniUI/OUIInspectorAppearance.h>

RCS_ID("$Id$")

@interface OUISliceSeparatorView ()
@property (readwrite,copy) UIColor *strokeColor;
@end

@implementation OUISliceSeparatorView

static id _commonInit(OUISliceSeparatorView *self)
{
    self.backgroundColor = [UIColor whiteColor];
    self.strokeColor = [UIColor colorWithWhite:0.9 alpha:1.0];
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

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    CGFloat contentScaleFactor = self.contentScaleFactor;
    if ((CGRectGetHeight(bounds) <= 0.0f) || (CGRectGetWidth(bounds) <= 0.0f))
        return; // Nothing to do here
    
    [self.backgroundColor set];
    UIRectFill(bounds);
    
    [self.strokeColor set];
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineWidth = 1.0f / contentScaleFactor;
    [path moveToPoint:(CGPoint){ .x = CGRectGetMinX(bounds), .y = CGRectGetMaxY(rect) - (path.lineWidth/2.0)}];
    [path addLineToPoint:(CGPoint){ .x = CGRectGetMinX(rect) + CGRectGetWidth(rect), .y = CGRectGetMaxY(rect) - (path.lineWidth/2.0)}];
    [path stroke];
}

- (void)willMoveToSuperview:(UIView *)superview;
{
    if ([OUIInspectorAppearance inspectorAppearanceEnabled]) {
        OUIInspectorAppearance *appearance = OUIInspectorAppearance.appearance;
        [self themedAppearanceDidChange:appearance];
    }
}

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);
    self.backgroundColor = appearance.TableCellBackgroundColor;
    self.strokeColor = appearance.InspectorSeparatorColor;
    
    [self setNeedsDisplay];
    
}

@end
