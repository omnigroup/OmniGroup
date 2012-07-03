// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorBackgroundView.h"

#import <QuartzCore/QuartzCore.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniQuartz/OQColor.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIInspectorBackgroundView

/*
 Only does evenly spaced top-to-bottom gradient right now.
 */

+ (Class)layerClass;
{
    return [CAGradientLayer class];
}

static id _commonInit(OUIInspectorBackgroundView *self)
{
    // Without this, OmniPlan hits <bug:///79908> (Can only scroll inspectors by dragging on content). Our other apps don't, and I've yet to narrow down exactly why this is happening. Touches inbetween widgets (that would presumably fall through to an instance of this class) provoke zero messages to objc_msgSend{,_stret,fpret,_noarg} in the Simulator. So, it seems like *maybe* the event system is doing some non-ObjC hit detection on the CALayer tree before dispatching the event, and maybe CAGradientLayers look transparent. Grasping a straws. So far no luck building a standalone test case...
    // Logged as Radar 11478441: CAGradientLayer-backed UIView can be untouchable
    self.backgroundColor = [UIColor blackColor];
    
    self.opaque = YES;
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
    [_colors release];
    [super dealloc];
}

static OUIInspectorBackgroundView *_topBackgroundView(OUIInspectorBackgroundView *backgroundView)
{
    UIView *view = backgroundView;
    while (view) {
        if ([view isKindOfClass:[OUIInspectorBackgroundView class]])
            backgroundView = (OUIInspectorBackgroundView *)view;
        view = view.superview;
    }
    
    return backgroundView;
}

- (UIColor *)colorForYPosition:(CGFloat)yPosition inView:(UIView *)view;
{
    CGPoint pt = [self convertPoint:CGPointMake(0, yPosition) fromView:view];
    OFExtent extent = OFExtentFromRectYRange(self.bounds);
    
    CGFloat fraction = OFExtentPercentForValue(extent, pt.y);
    OBASSERT(fraction >= 0 && fraction <= 1);

    OQLinearRGBA color = OQBlendLinearRGBAColors(kOUIInspectorBackgroundTopColor, kOUIInspectorBackgroundBottomColor, fraction);
    return [UIColor colorWithRed:color.r green:color.g blue:color.b alpha:color.a];
}

- (void)setFrame:(CGRect)frame;
{
    [super setFrame:frame];
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{    
    OUIInspectorBackgroundView *fullView = _topBackgroundView(self);
    OBASSERT(fullView); // should have at least been the given view itself.
    
    CGFloat startingFraction, endingFraction;
    
    if (!fullView || self == fullView) {
        startingFraction = 0;
        endingFraction = 1;
    } else {
        OFExtent fullExtent = OFExtentFromRectYRange(fullView.bounds);
        OFExtent rectExtent = OFExtentFromRectYRange([self convertRect:self.bounds toView:fullView]);
        
        startingFraction = OFExtentPercentForValue(fullExtent, OFExtentMin(rectExtent));
        OBASSERT(startingFraction >= 0 && startingFraction <= 1);
        endingFraction = OFExtentPercentForValue(fullExtent, OFExtentMax(rectExtent));
        OBASSERT(endingFraction >= 0 && endingFraction <= 1);
    }
    
    OQLinearRGBA startingColor = OQBlendLinearRGBAColors(kOUIInspectorBackgroundTopColor, kOUIInspectorBackgroundBottomColor, startingFraction);
    OQLinearRGBA endingColor = OQBlendLinearRGBAColors(kOUIInspectorBackgroundTopColor, kOUIInspectorBackgroundBottomColor, endingFraction);
    
    NSArray *colors = [NSArray arrayWithObjects:
                       (id)[[UIColor colorWithRed:startingColor.r green:startingColor.g blue:startingColor.b alpha:startingColor.a] CGColor],
                       (id)[[UIColor colorWithRed:endingColor.r green:endingColor.g blue:endingColor.b alpha:endingColor.a] CGColor],
                       nil];
    CAGradientLayer *layer = ((CAGradientLayer *)self.layer);
    
    if (OFNOTEQUAL(layer.colors, colors)) {
        layer.colors = colors;
    }
    
    [self containingInspectorBackgroundViewColorsChanged];
}

@end

@implementation UIView (OUIInspectorBackgroundView)

- (void)containingInspectorBackgroundViewColorsChanged;
{
    [[self subviews] makeObjectsPerformSelector:_cmd];
}

@end
