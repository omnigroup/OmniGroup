// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITextView.h>

@protocol OUINoteTextViewAppearanceDelegate;

@interface OUINoteTextView : UITextView

@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic) BOOL drawsPlaceholder;
@property (nonatomic) CGFloat placeholderTopMargin; // Default is OUINoteTextViewPlacholderTopMarginAutomatic

@property (nonatomic) BOOL drawsBorder;

/// If set, called to get various appearance properties. If nil, default values are used
@property (nonatomic, weak) id <OUINoteTextViewAppearanceDelegate> appearanceDelegate;

- (void)appearanceDidChange;

@end

@protocol OUINoteTextViewAppearanceDelegate <NSObject>
- (UIColor *)textColorForTextView:(OUINoteTextView *)textView;
- (UIColor *)placeholderTextColorForTextView:(OUINoteTextView *)textView;
- (UIColor *)borderColorForTextView:(OUINoteTextView *)textView;
- (UIKeyboardAppearance)keyboardAppearanceForTextView:(OUINoteTextView *)textView;
@end

#pragma mark -

extern CGFloat OUINoteTextViewPlacholderTopMarginAutomatic;
