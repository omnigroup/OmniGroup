// Copyright 2011-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIGestureRecognizer.h>

@interface OUIRotationGestureRecognizer : OUIGestureRecognizer {
    
@private
    CGFloat _hysteresisAngle;
    BOOL _overcameHysteresis;
    
    CGPoint _centerTouchPoint;
    
    CGFloat _startAngle;    // in degrees
    CGFloat _rotation;      // in degrees
}   

// Settings
@property (nonatomic) CGFloat rotation;

@end
