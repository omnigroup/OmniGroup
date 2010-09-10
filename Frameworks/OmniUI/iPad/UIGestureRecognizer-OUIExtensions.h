// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIGestureRecognizer.h>

// This uses method replacement that would get us rejected in app submission
#ifdef DEBUG
    #define OUI_GESTURE_RECOGNIZER_DEBUG 1
#else
    #define OUI_GESTURE_RECOGNIZER_DEBUG 0
#endif

@interface UIGestureRecognizer (OUIExtensions)

#if OUI_GESTURE_RECOGNIZER_DEBUG
+ (void)enableStateChangeLogging;
#endif

- (UIView *)nearestViewFromViews:(NSArray *)views relativeToView:(UIView *)comparisionView maximumDistance:(CGFloat)maximumDistance;


@end

