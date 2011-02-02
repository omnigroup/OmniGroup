// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextColorInspectorWell.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation OUITextColorInspectorWell

@synthesize textForegroundColor, textBackgroundColor;

- (void)dealloc;
{
    [textForegroundColor release];
    [textBackgroundColor release];
}

- (void)setTextForegroundColor:(OQColor *)color;
{
    if (OFISEQUAL(textForegroundColor, color))
        return;
    [textForegroundColor release];
    textForegroundColor = [color copy];
    [self setNeedsDisplay];
}

- (void)setTextBackgroundColor:(OQColor *)color;
{
    if (OFISEQUAL(textBackgroundColor, color))
        return;
    [textBackgroundColor release];
    textBackgroundColor = [color copy];
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark OUIInspectorTextWell subclass

- (UIColor *)textColor;
{
    // Superclass has a highlighted variant. Should we?
    return [textForegroundColor toColor];
}

- (void)drawInteriorFillWithRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGFloat alpha = [textBackgroundColor alphaComponent];
    
    if (alpha < 0.01) {
        // Clearish -- text atop a fully checkerboarded background looks horrible.
        // To the two-triangle rendering for showing alpha instead?
        [[UIColor whiteColor] set];
        UIRectFill(rect);
    } else {
        if ([textBackgroundColor alphaComponent] < 1.0) {
            OUIDrawTransparentColorBackground(ctx, rect, CGSizeZero);
        }
        
        [[textBackgroundColor toColor] set];
        UIRectFillUsingBlendMode(rect, kCGBlendModeNormal);
    }
}

@end
