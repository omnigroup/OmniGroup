// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIButton.h>

@interface OUIInspectorStepperButton : UIButton

+ (CGSize)stepperButtonSize;

@property(assign,nonatomic) BOOL flipped;

// Defaults to YES. If set, this will resend the UIControlEventTouchDown action while the button is held down.
@property(assign,nonatomic) BOOL repeats;

@property(copy,nonatomic) NSString *title;
@property(strong,nonatomic) UIFont *titleFont;
@property(strong,nonatomic) UIColor *titleColor;
@property(strong,nonatomic) UIImage *image;

@end
