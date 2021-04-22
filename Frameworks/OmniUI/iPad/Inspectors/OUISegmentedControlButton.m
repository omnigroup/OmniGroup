// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISegmentedControlButton.h>
#import <OmniUI/OUISegmentedControl.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniBase/OmniBase.h>
#import <UIKit/UIImage.h>
#import <OmniUI/OUIInspector.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUISegmentedControlButton

static id _commonInit(OUISegmentedControlButton *self)
{
    self.adjustsImageWhenHighlighted = NO;
    self.imageView.contentMode = UIViewContentModeCenter;
    [self _updateTitleColor];
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

#pragma mark - API

- (void)setButtonPosition:(OUISegmentedControlButtonPosition)buttonPosition;
{
    OBASSERT_NONNEGATIVE(buttonPosition);
    OBPRECONDITION(buttonPosition < _OUISegmentedControlButtonPositionCount);
    if (buttonPosition >= _OUISegmentedControlButtonPositionCount)
        buttonPosition = OUISegmentedControlButtonPositionCenter;

    if (_buttonPosition == buttonPosition)
        return;
    _buttonPosition = buttonPosition;
}

- (void)setImage:(UIImage *)image;
{
    if (_image == image)
        return;
    _image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    
    [self setImage:_image forState:UIControlStateNormal];
}

- (void)addTarget:(id)target action:(SEL)action;
{
    [super addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - UIView subclass

- (UIColor *)backgroundColor;
{
    UIColor *color = nil;
    if (self.selected) {
        color = [self _borderColor];
    } else if (self.highlighted) {
        color = [[self _borderColor] colorWithAlphaComponent:0.2f];
    }
    return color;
}

- (void)drawRect:(CGRect)rect;
{
    UIBezierPath *borderPath = [self _borderPath];
    
    // Draw the background
    UIColor *backgroundColor = self.backgroundColor;
    if (backgroundColor != nil) {
        [backgroundColor set];
        [borderPath fill];
    }
    
    // Draw the border
    UIColor *borderColor = [self _borderColor];
    if (borderColor != nil) {
        [borderColor set];
        [borderPath stroke];
    }
    
    // Draw a separator between us and our neighbor to the left
    if (self.buttonPosition == OUISegmentedControlButtonPositionCenter
        || self.buttonPosition == OUISegmentedControlButtonPositionRight) {
        CGRect lineRect = self.bounds;
        lineRect.size.width = 1.0f;
        // don't draw over the top/bottom border - we might be a different color
        lineRect.origin.y += 1.0f;
        lineRect.size.height -= 2.0f;
        [[self _leftSeparatorColor] set];
        UIRectFill(lineRect);
    }
}

- (void)tintColorDidChange;
{
    [super tintColorDidChange];
    [self _updateTitleColor];
    [self setNeedsDisplay];
}

#pragma mark - UIControl subclass

- (void)setHighlighted:(BOOL)value;
{
    super.highlighted = value;
    [self setNeedsDisplay];
}

- (void)setSelected:(BOOL)selected;
{
    super.selected = selected;
    if (selected) {
        self.imageView.tintColor = [UIColor systemBackgroundColor];
    } else {
        self.imageView.tintColor = nil;
    }
    
    // If we changed our selection status, our neighbor to the right might need to redraw its separator line. It won't know that, so let's tell us
    NSUInteger segmentIndex = [(OUISegmentedControl *)self.superview indexOfSegment:self] + 1;
    NSUInteger segmentCount = [(OUISegmentedControl *)self.superview segmentCount];
    if (segmentIndex < segmentCount) {
        OUISegmentedControlButton *rightNeighbor = [(OUISegmentedControl *)self.superview segmentAtIndex:segmentIndex];
        OBASSERT(rightNeighbor != nil);
        [rightNeighbor setNeedsDisplay];
    }
}

#pragma mark - Private API

- (UIColor *)_borderColor;
{
    UIColor *color = self.tintColor;
    if (!self.enabled) {
        OAColor *strokeOAColor = [OAColor colorWithPlatformColor:color];
        OAColor *white = [OAColor colorWithPlatformColor:[UIColor whiteColor]];
        OAColor *blended = [strokeOAColor blendedColorWithFraction:0.5 ofColor:white];
        color = [blended toColor];
    }
    return color;
}

- (UIBezierPath *)_borderPath;
{
    UIEdgeInsets insets = {
        .top = 0.5f,
        .bottom = 0.5f,
        .left = 0.5f,
        .right = 0.5f,
    };
    UIRectCorner cornerMask = 0;
    switch (self.buttonPosition) {
        case OUISegmentedControlButtonPositionLeft:
            cornerMask |= (UIRectCornerTopLeft | UIRectCornerBottomLeft);
            insets.right = -0.5f;
            break;
        case OUISegmentedControlButtonPositionRight:
            cornerMask |= (UIRectCornerTopRight | UIRectCornerBottomRight);
            insets.left = -0.5f;
            break;
        default:
            insets.left = -0.5f;
            insets.right = -0.5f;
            break;
    }
    CGRect bounds = self.bounds;
    bounds = UIEdgeInsetsInsetRect(bounds, insets);
    return [UIBezierPath bezierPathWithRoundedRect:bounds byRoundingCorners:cornerMask cornerRadii:CGSizeMake(4.0f,4.0f)];
}

- (UIColor *)_leftSeparatorColor;
{
    UIColor *separatorColor = [self _borderColor];
    if (self.selected) {
        // If our left neighbor is also selected, we need to adjust the border color or there won't be a visible border between us and them.
        OUISegmentedControl *segmentedControl = (OUISegmentedControl *)self.superview;
        OBASSERT((segmentedControl != nil) && [segmentedControl isKindOfClass:[OUISegmentedControl class]]);
        NSUInteger segmentIndex = [segmentedControl indexOfSegment:self];
        if ((segmentIndex != NSNotFound) && (segmentIndex > 0)) {
            OUISegmentedControlButton *leftNeighbor = [segmentedControl segmentAtIndex:(segmentIndex - 1)];
            OBASSERT(leftNeighbor != nil);
            if (leftNeighbor.selected) {
                separatorColor = [separatorColor colorWithAlphaComponent:0.2f];
            }
        }
    }
    return separatorColor;
}

- (void)_updateTitleColor;
{
    [self setTitleColor:[self _borderColor] forState:UIControlStateNormal];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
}

@end
