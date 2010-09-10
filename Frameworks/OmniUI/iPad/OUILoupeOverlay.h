// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>
#import <OmniUI/OUILoupeOverlaySubject.h>

typedef enum {
    OUILoupeOverlayNone,
    OUILoupeOverlayCircle,
    OUILoupeOverlayRectangle,
} OUILoupeMode;

@class OUIScalingView;

@interface OUILoupeOverlay : UIView
{
@private
    OUILoupeMode _mode;           // What kind of loupe we're displaying
    CGPoint _touchPoint;          // The point (in our subject view's bounds coordinates) to display
    CGFloat _scale;               // How much to magnify the subject view
    OUIScalingView <OUILoupeOverlaySubject> *subjectView;  // If not set, self.superview is used for the subject of display
    
    // These are updated based on the mode
    UIImage *loupeFrameImage;   // The border image to draw around the zoomed view region
    CGRect loupeFramePosition;  // The frame of the above image, expressed with (0,0) at the (unmagnified) touch point
    CGPathRef loupeClipPath;    // The clip-path into which to draw the zoomed view region, in our bounds coordinate system
    CGPoint loupeTouchPoint;    // The point in our bounds coordinate system at which (magnified) _touchPoint should be made to draw
}

@property(readwrite,nonatomic,assign) CGPoint touchPoint;
@property(readwrite,nonatomic,assign) OUILoupeMode mode;
@property(readwrite,nonatomic,assign) CGFloat scale;
@property(readwrite,nonatomic,assign) OUIScalingView <OUILoupeOverlaySubject> *subjectView;

@end

