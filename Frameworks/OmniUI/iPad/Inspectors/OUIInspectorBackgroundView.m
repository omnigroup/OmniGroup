// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorBackgroundView.h"

#import <QuartzCore/QuartzCore.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniAppKit/OAColor.h>

#import "OUIParameters.h"
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorAppearance.h>
#import <OmniUI/UILabel-OUITheming.h>

RCS_ID("$Id$");

@interface OUIInspectorBackgroundView ()
@property (nonatomic, strong, readwrite) UILabel *label;
@end

@implementation OUIInspectorBackgroundView

static id _commonInit(OUIInspectorBackgroundView *self)
{
    self.opaque = YES;
    self.backgroundColor = [OUIInspector backgroundColor];
    self.label = [[UILabel alloc] init];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.label applyStyle:OUILabelStyleInspectorSliceInstructionText];
    [self addSubview:self.label];
    
    [self.label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [self.label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    
    
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

- (void)willMoveToSuperview:(UIView *)superview;
{
    [super willMoveToSuperview:superview];
    
    if ([OUIInspectorAppearance inspectorAppearanceEnabled])
        [self themedAppearanceDidChange:[OUIInspectorAppearance appearance]];
}

- (UIColor *)inspectorBackgroundViewColor;
{
    return self.backgroundColor;
}

- (void)setFrame:(CGRect)frame;
{
    [super setFrame:frame];
    [self setNeedsLayout];
}

- (void)setBackgroundColor:(UIColor *)newValue;
{
    super.backgroundColor = newValue;
    [self containingInspectorBackgroundViewColorChanged];
}

#pragma mark - OUIThemedAppearanceClient

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);
    [super themedAppearanceDidChange:appearance];
    self.backgroundColor = appearance.InspectorBackgroundColor;
}

@end

@implementation UIView (OUIInspectorBackgroundView)

- (void)containingInspectorBackgroundViewColorChanged;
{
    [[self subviews] makeObjectsPerformSelector:_cmd];
}

@end
