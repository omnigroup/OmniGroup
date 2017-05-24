// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class UITouch;
@class NSData;

@protocol OUIVisibleBoundsDelegate <NSObject>

/// The rect in view's coordinates that is unobstructed by any UINavigationControllers' navigationBars or toolbars
- (CGRect)unobstructedVisibleBoundsOfView:(UIView*)view;

/// The size of the viewport, not including any UINavigationControllers' navigationBars or toolbars
- (CGSize)sizeOfViewport;

@end

@interface OUIScalingView : UIView

// If this view is within a OUIScalingScrollView, then this property should be considered read-only and the scale should be adjusted via its methods.
@property(assign,nonatomic) CGFloat scale;
@property(assign,nonatomic) BOOL scaleEnabled;
@property (nonatomic, weak) IBOutlet NSObject<OUIVisibleBoundsDelegate> *visibleBoundsDelegate;

// For subclasses;
- (void)scaleChanged;
- (void)scrollPositionChanged;

@property(assign,nonatomic) BOOL rotating; // Managed by OUIScalingViewController; you can look, but don't touch.

@property(readonly) BOOL wantsUnflippedCoordinateSystem;

// Conversion to/from device space (for UIView positioning/scrolling, UITouch coordinates) and RSDataMapper's "view" space.
// TODO: remove these (more notes in .m file)
- (CGPoint)viewPointForTouchPoint:(CGPoint)point;
- (CGPoint)viewPointForTouch:(UITouch *)touch;

// These methods are confusingly named; -transformToViewSpace actually returns a transform that will take you *from* rendering space to UIKit's  view coordinate system, but that's the transform you want to concat with the CTM in order to "be in" rendering space when you draw (that is, to "go to rendering space"). Likewise -transformFromViewSpace returns a transform that will convert a point's coordinates in UIKit's space *to* the same point's coordinates in rendering space.
- (CGAffineTransform)transformFromViewSpaceToUnscaledSpace;

- (CGRect)convertRectFromViewSpaceToUnscaledSpace:(CGRect)rect;
- (CGRect)convertRectFromUnscaledSpaceToViewSpace:(CGRect)rect;
- (CGPoint)convertPointFromViewSpaceToUnscaledSpace:(CGPoint)point;
- (CGPoint)convertPointFromUnscaledSpaceToViewSpace:(CGPoint)point;
- (void)establishTransformFromViewSpaceToUnscaledSpace:(CGContextRef)ctx;

// Subclass this to draw w/in a scaled (and possibly flipped) coordinate system.
- (void)drawScaledContent:(CGRect)rect;

- (NSData *)pdfData;

@end
