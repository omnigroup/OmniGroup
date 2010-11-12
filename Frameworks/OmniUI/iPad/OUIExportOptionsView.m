// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsView.h"

#import <OmniUI/OUIInspectorWell.h>

RCS_ID("$Id$")

static NSUInteger maxChoices = 3;
static CGFloat labelHeight = 20;
static CGFloat border = 15;
static CGFloat imageSize = 128;

@interface OUIExportOptionsButton : UIButton
@end
@implementation OUIExportOptionsButton
- (CGRect)backgroundRectForBounds:(CGRect)bounds;
{
    bounds.size.height -= labelHeight;
    if (bounds.size.height > imageSize)
        bounds = CGRectInset(bounds, 0, (bounds.size.height-imageSize)/2);
    if (bounds.size.width > imageSize)
        bounds = CGRectInset(bounds, (bounds.size.width-imageSize)/2, 0);
    
    return CGRectIntegral(bounds);
}
@end

@implementation OUIExportOptionsView

static id _commonInit(OUIExportOptionsView *self)
{
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    
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

- (void)dealloc;
{
    [super dealloc];
}

/*
- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    OUIInspectorWellDrawOuterShadow(ctx, bounds, YES // rounded);
    CGContextSaveGState(ctx);
    {
        CGPoint start = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMinY(self.bounds));
        CGFloat startRadius = 0;
        CGPoint end = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMinY(self.bounds));
        CGFloat endRadius = 200;
        
        NSArray *gradientColors = [NSArray arrayWithObjects:(id)[[UIColor colorWithRed:0.867f green:0.882f blue:0.894f alpha:1] CGColor], (id)[[UIColor colorWithRed:0.749f green:0.773f blue:0.796f alpha:1] CGColor], nil];
        CGGradientRef gradient = CGGradientCreateWithColors(NULL, (CFArrayRef)gradientColors, NULL);
        CGContextDrawRadialGradient(ctx, gradient, start, startRadius, end, endRadius, kCGGradientDrawsBeforeStartLocation|kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
    }
    CGContextRestoreGState(ctx);
    
    OUIInspectorWellDrawBorderAndInnerShadow(ctx, bounds, YES // rounded);
}
*/

- (void)addChoiceToIndex:(NSUInteger)index image:(UIImage *)image label:(NSString *)label target:(id)target selector:(SEL)selector;
{
    OBASSERT(index<maxChoices); 
    
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat width = CGRectGetWidth(self.bounds) / maxChoices;
    
    CGRect choiceRect = CGRectMake(CGRectGetMinX(self.bounds)+index*width, CGRectGetMinY(self.bounds), width, height);
    choiceRect = CGRectInset(choiceRect, border, border);
    
    OUIExportOptionsButton *choice = [OUIExportOptionsButton buttonWithType: UIButtonTypeCustom];
    choice.frame = CGRectIntegral(choiceRect);
    [choice setBackgroundImage:image forState:UIControlStateNormal];
    [choice setTitle:label forState:UIControlStateNormal];
    [choice setTitleColor:[UIColor colorWithRed:0.196 green:0.224 blue:0.29 alpha:1] forState:UIControlStateNormal];
    [choice setTitleShadowColor:[UIColor colorWithWhite:1 alpha:.5] forState:UIControlStateNormal];
    choice.titleLabel.shadowOffset = CGSizeMake(0, 1);
    choice.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    choice.titleEdgeInsets = UIEdgeInsetsMake((CGRectGetHeight(choiceRect) - labelHeight), 0, 0, 0);    
    [choice addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];
    
    [self addSubview:choice];
}

- (void)layoutSubviews;
{
    NSUInteger numberSubviews = [self.subviews count];
    if (numberSubviews == maxChoices)
        return;
    
    // the subviews are sized appropriately in -addChoiceToIndex, here is an opportunity to space them out evenly
    CGFloat distanceToCenter = CGRectGetWidth(self.frame) / (numberSubviews+1);
    NSUInteger index = 0;
    for (UIView *subview in self.subviews) {
        CGFloat newXPosition = distanceToCenter + distanceToCenter*index - CGRectGetWidth(subview.frame)/2;
        CGPoint newOrigin = CGPointMake(newXPosition, subview.frame.origin.y);
        CGRect newFrame = (CGRect){newOrigin, subview.frame.size};
        subview.frame = CGRectIntegral(newFrame);
        index++;
    }
}

@end
