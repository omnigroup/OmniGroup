// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OUIKeyboardNotifier : NSObject

@property (nonatomic, readonly) CGFloat lastKnownKeyboardHeight;
@property (nonatomic, readonly, getter = isKeyboardVisible) BOOL keyboardVisible;

@property(nonatomic,readonly) CGFloat lastAnimationDuration;
@property(nonatomic,readonly) UIViewAnimationCurve lastAnimationCurve;

@property (nonatomic, weak) UIView *accessoryToolbarView;

+ (instancetype)sharedNotifier;

@end

extern NSString * const OUIKeyboardNotifierKeyboardWillChangeFrameNotification;
extern NSString * const OUIKeyboardNotifierKeyboardDidChangeFrameNotification;
extern NSString * const OUIKeyboardNotifierOriginalUserInfoKey;
extern NSString * const OUIKeyboardNotifierLastKnownKeyboardHeightKey;
