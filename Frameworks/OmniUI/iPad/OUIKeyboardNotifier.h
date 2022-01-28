// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OUIKeyboardState) {
    OUIKeyboardStateUnknown = 0,
    OUIKeyboardStateAppearing,
    OUIKeyboardStateVisible,
    OUIKeyboardStateDisappearing,
    OUIKeyboardStateHidden
};

@interface OUIKeyboardNotifier : NSObject

@property(class,nonatomic,readonly) OUIKeyboardNotifier *sharedNotifier;

/// The last known height for the docked keyboard; avoid this height at the bottom of the screen when laying out in response to a keyboard notification. If a floating keyboard is displayed, this will return 0.
@property (nonatomic, readonly) CGFloat lastKnownKeyboardHeight;
@property (nonatomic, readonly, getter=isKeyboardVisible) BOOL keyboardVisible;

@property (nonatomic) OUIKeyboardState keyboardState;
@property (nonatomic) BOOL shouldPreserveLastKeyboardStateWhenSceneDeactivates;

@property(nonatomic,readonly) NSTimeInterval lastAnimationDuration;
@property(nonatomic,readonly) UIViewAnimationCurve lastAnimationCurve;
@property(nonatomic,readonly) UIViewAnimationOptions animationOptionsForLastKnownAnimationCurve; // Only includes curve details. This enum is required for the iOS 13+ block-based animation API.


- (void)addAccessoryToolbarView:(UIView *)view;
- (void)removeAccessoryToolbarView:(UIView *)view;

/// Returns the minimum Y coordinate of the last known keyboard rect, translated to the coordinate space of the given view. The return value for this method is useful in calculating visible areas for an arbitrarily deep view in the hierarchy (e.g. for avoiding the keyboard or updating scroll insets).
- (CGFloat)minimumYPositionOfLastKnownKeyboardInView:(UIView *)view;

@end

#pragma mark -

#ifdef DEBUG

@interface OUIKeyboardNotifier (Debug)

+ (BOOL)hasSharedNotifier;

@end

#endif

#pragma mark -

extern NSString * const OUIKeyboardNotifierKeyboardWillChangeFrameNotification;
extern NSString * const OUIKeyboardNotifierKeyboardDidChangeFrameNotification;

extern NSString * const OUIKeyboardNotifierKeyboardWillShowNotification;
extern NSString * const OUIKeyboardNotifierKeyboardDidShowNotification;
extern NSString * const OUIKeyboardNotifierKeyboardWillHideNotification;
extern NSString * const OUIKeyboardNotifierKeyboardDidHideNotification;

extern NSString * const OUIKeyboardNotifierOriginalUserInfoKey;
extern NSString * const OUIKeyboardNotifierLastKnownKeyboardHeightKey;

NS_ASSUME_NONNULL_END

