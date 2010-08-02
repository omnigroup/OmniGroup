// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class UITouch, UIImage;
@class NSData;

@interface OUIScalingView : UIView
{
    CGFloat _scale;
    BOOL _rotating;
    
    BOOL _wantsShadowEdges;
    NSArray *_shadowEdgeViews;
}

// DO NOT set this directly for now. Only should be mucked with via GraphViewController and its UIScrollView (or code needs rearranging to support direct mucking)
@property(assign,nonatomic) CGFloat scale;

// For subclasses;
- (void)scaleChanged;

@property(assign,nonatomic) BOOL rotating; // Managed by OUIScalingViewController; you can look, but don't touch.

@property(readonly) BOOL wantsUnflippedCoordinateSystem;

// Conversion to/from device space (for UIView positioning/scrolling, UITouch coordinates) and RSDataMapper's "view" space.
- (CGPoint)viewPointForTouchPoint:(CGPoint)point;
- (CGPoint)viewPointForTouch:(UITouch *)touch;

// These methods are confusingly named; -transformToRenderingSpace actually returns a transform that will take you *from* rendering space to UIKit's  view coordinate system, but that's the transform you want to concat with the CTM in order to "be in" rendering space when you draw (that is, to "go to rendering space"). Likewise -transformFromRenderingSpace returns a transform that will convert a point's coordinates in UIKit's space *to* the same point's coordinates in rendering space.
- (CGAffineTransform)transformToRenderingSpace;
- (CGAffineTransform)transformFromRenderingSpace;

- (CGRect)convertRectFromRenderingSpace:(CGRect)rect;
- (CGRect)convertRectToRenderingSpace:(CGRect)rect;
- (CGPoint)convertPointFromRenderingSpace:(CGPoint)point;
- (CGPoint)convertPointToRenderingSpace:(CGPoint)point;
- (void)establishTransformToRenderingSpace:(CGContextRef)ctx;
- (CGRect)viewRectWithCenter:(CGPoint)center size:(CGSize)size;

// Subclass this to draw w/in a scaled (and possibly flipped) coordinate system.
- (void)drawScaledContent:(CGRect)rect;

- (NSData *)pdfData;

@property (assign, nonatomic) BOOL wantsShadowEdges;  // Set to YES if you want shadows on the edges
- (void)updateShadowEdgeViews;
- (void)setShadowEdgeViewVisibility:(BOOL)visible;

@end
