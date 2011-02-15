// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIControl.h>
#import <CoreGraphics/CGContext.h>

extern void OUIInspectorWellAddPath(CGContextRef ctx, CGRect frame, BOOL rounded);
extern void OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect frame, BOOL rounded);
extern void OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect frame, BOOL rounded);
extern CGRect OUIInspectorWellInnerRect(CGRect frame);
extern void OUIInspectorWellStrokePathWithBorderColor(CGContextRef ctx);

// This just draws the background border/gradient with highlighting, font and color support methods for subclasses.
@interface OUIInspectorWell : UIControl
{
@private    
    BOOL _rounded;
    BOOL _showNavigationArrow;
}

+ (CGFloat)fontSize;
+ (UIFont *)italicFormatFont;
+ (UIColor *)textColor;
+ (UIColor *)highlightedTextColor;

@property(assign,nonatomic) BOOL rounded;
@property(readonly,nonatomic) BOOL shouldDrawHighlighted;
@property(readonly,nonatomic) CGRect contentsRect; // Insets from the edges and avoids the navigation arrow if present.

- (UIImage *)navigationArrowImage;
@property(assign,nonatomic) BOOL showNavigationArrow;

- (void)setNavigationTarget:(id)target action:(SEL)action; // Convenience to add a target and turn on the navigation arrow

// Subclassing points
- (UIColor *)textColor; // Returns the text color to use for the current state (defaulting to the class +textColor or +highlightedTextColor)
- (void)drawInteriorFillWithRect:(CGRect)rect; // Draws the interior gradient

@end
