// Copyright 2010-2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIGestureRecognizer.h>   

NS_ASSUME_NONNULL_BEGIN;

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

/// An identifier attached to the gesture recognizer using an associated object. N.B., this is a no-op in Release builds.
///
/// - seeAlso: +enableStateChangeLogging, -[UIView logGestureRecognizers]
@property (nonatomic, copy, nullable) NSString *debugIdentifier;

- (nullable UIView *)hitView;
- (nullable UIView *)nearestViewFromViews:(NSArray *)views relativeToView:(UIView *)comparisionView maximumDistance:(CGFloat)maximumDistance;

@end

#if OUI_GESTURE_RECOGNIZER_DEBUG
@interface UIView (OUIGestureRecognizerExtensions)
/// Logs all the gesture recognizers attached to the current view and any subviews recursively.
- (void)logGestureRecognizers;
@end
#endif

NS_ASSUME_NONNULL_END;

