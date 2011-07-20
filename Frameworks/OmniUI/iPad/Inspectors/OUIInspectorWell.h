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
extern void OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect frame, BOOL rounded, BOOL innerShadow);
extern CGRect OUIInspectorWellInnerRect(CGRect frame);
extern void OUIInspectorWellStrokePathWithBorderColor(CGContextRef ctx);

typedef enum {
    OUIInspectorWellBackgroundTypeNormal, // Value holding well
    OUIInspectorWellBackgroundTypeButton,
} OUIInspectorWellBackgroundType;


// This just draws the background border/gradient with highlighting, font and color support methods for subclasses.
@interface OUIInspectorWell : UIControl

+ (CGFloat)fontSize;
+ (UIFont *)italicFormatFont;
+ (UIColor *)textColor;
+ (UIColor *)highlightedTextColor;
+ (UIImage *)navigationArrowImage;

@property(assign,nonatomic) BOOL rounded;
@property(readonly,nonatomic) BOOL shouldDrawHighlighted;
@property(nonatomic) OUIInspectorWellBackgroundType backgroundType;

@property(nonatomic,retain) UIView *leftView;
@property(nonatomic,retain) UIView *rightView;

@property(readonly,nonatomic) CGRect contentsRect; // Insets from the edges and avoids the navigation arrow if present.

- (void)setNavigationArrowRightView;
- (void)setNavigationTarget:(id)target action:(SEL)action; // Convenience to add a target and make a UIImageView as the rightView with +navigationArrowImage

// Subclassing points
- (UIColor *)textColor; // Returns the text color to use for the current state (defaulting to the class +textColor or +highlightedTextColor)
- (void)drawInteriorFillWithRect:(CGRect)rect; // Draws the interior gradient

@end
