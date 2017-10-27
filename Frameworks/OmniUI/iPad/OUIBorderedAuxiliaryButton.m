// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIBorderedAuxiliaryButton.h>

#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

@interface OUIBorderedAuxiliaryButton ()  {
  @private
    struct {
        NSUInteger isTableCellAccessoryView:1;
        NSUInteger isTrackingTouch:1;
    } _borderedButtonFlags;
}

- (void)OUIBorderedAuxiliaryButton_commonInit;

- (void)OUIBorderedAuxiliaryButton_touchDown;
- (void)OUIBorderedAuxiliaryButton_touchUp;

- (void)OUIBorderedAuxiliaryButton_updateTitleColor;

- (void)drawButtonBackgroundInClipRect:(CGRect)clipRect highlighted:(BOOL)highlighted;

@end

#pragma mark -

@implementation OUIBorderedAuxiliaryButton

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
        
    [self OUIBorderedAuxiliaryButton_commonInit];
        
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (!self)
        return nil;
        
    [self OUIBorderedAuxiliaryButton_commonInit];
        
    return self;
}

- (void)OUIBorderedAuxiliaryButton_commonInit;
{
    self.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    self.contentMode = UIViewContentModeRedraw;

    [self addTarget:self action:@selector(OUIBorderedAuxiliaryButton_touchDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(OUIBorderedAuxiliaryButton_touchUp) forControlEvents:(UIControlEventTouchCancel | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchDragExit)];
    
    [self OUIBorderedAuxiliaryButton_updateTitleColor];
}

- (void)didMoveToSuperview;
{
    [super didMoveToSuperview];

    UITableViewCell *enclosingTableViewCell = (UITableViewCell *)[self enclosingViewOfClass:[UITableViewCell class]];
    _borderedButtonFlags.isTableCellAccessoryView = [enclosingTableViewCell accessoryView] == self;
    [self setNeedsDisplay];
}

- (void)setHighlighted:(BOOL)highlighted;
{
    if (_borderedButtonFlags.isTableCellAccessoryView)
        highlighted &= _borderedButtonFlags.isTrackingTouch;

    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    if ([self isHighlighted]) {
        // Our superclass adjusts our title label's opacity on highlight.
        // We don't want that behavior, so we undo it here.
        self.titleLabel.alpha = 1.0;
    }
}

- (void)drawRect:(CGRect)clipRect;
{
    BOOL highlighted = [self isHighlighted];
    [self drawButtonBackgroundInClipRect:clipRect highlighted:highlighted];
}

- (void)drawButtonBackgroundInClipRect:(CGRect)clipRect highlighted:(BOOL)highlighted;
{
    CGRect borderRect = CGRectInset(self.bounds, 0.5, 0.5);
    UIBezierPath *borderPath = [UIBezierPath bezierPathWithRoundedRect:borderRect cornerRadius:4];
    borderPath.lineWidth = 1;
    
    [[self tintColor] set];

    if (highlighted) {
        [borderPath fill];
    } else {
        [borderPath stroke];
    }
}

- (void)tintColorDidChange;
{
    [super tintColorDidChange];
    
    [self OUIBorderedAuxiliaryButton_updateTitleColor];
    [self setNeedsDisplay];
}

- (void)OUIBorderedAuxiliaryButton_touchDown;
{   
    _borderedButtonFlags.isTrackingTouch = YES;
    [self setHighlighted:YES];
}

- (void)OUIBorderedAuxiliaryButton_touchUp;
{
    _borderedButtonFlags.isTrackingTouch = NO;
    [self setHighlighted:NO];
}

- (void)OUIBorderedAuxiliaryButton_updateTitleColor;
{
    [self setTitleColor:[self tintColor] forState:UIControlStateNormal];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
}

@end
