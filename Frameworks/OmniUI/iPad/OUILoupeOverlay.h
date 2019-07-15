// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>
#import <OmniUI/OUILoupeOverlaySubject.h>

typedef enum {
    OUILoupeOverlayNone,
    OUILoupeOverlayCircle,
    OUILoupeOverlayRectangle,
} OUILoupeMode;

@class OUIScalingView;

@interface OUILoupeOverlay : UIView

@property(readwrite,nonatomic,assign) CGPoint touchPoint;
@property(readwrite,nonatomic,assign) OUILoupeMode mode;
@property(readwrite,nonatomic,assign) CGFloat scale;
@property(readwrite,nonatomic,weak) OUIScalingView <OUILoupeOverlaySubject> *subjectView;

@end
