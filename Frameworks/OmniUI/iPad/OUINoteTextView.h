// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITextView.h>
#import <OmniUI/OUITextView.h>

@protocol OUINoteTextViewAppearanceDelegate;

@interface OUINoteTextView : OUITextView

@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic) BOOL drawsPlaceholder;
@property (nonatomic) CGFloat placeholderTopMargin; // Default is OUINoteTextViewPlacholderTopMarginAutomatic

@property (nonatomic) BOOL drawsBorder;

/// If set, called to get various appearance properties. If nil, default values are used
@property (nonatomic, weak) IBOutlet id <OUINoteTextViewAppearanceDelegate> appearanceDelegate;

- (void)appearanceDidChange;

// -------------------------------------------------------------------------
// Properties to communicate to subclasses when textStorage attributes are changing for internal reasons.
@property (nonatomic, readonly, getter=isConfiguringForEditing) BOOL configuringForEditing;
@property (nonatomic, readonly, getter=isChangingThemedAppearance) BOOL changingThemedAppearance;
@property (nonatomic, readonly, getter=isResigningFirstResponder) BOOL resigningFirstResponder;
// -------------------------------------------------------------------------

// Do not directly call -becomeFirstResponder if you want to begin text editing in this text view. Due to internal reasons related to our handling of links, that call will not work. Calling this method will flip the right internal levers and begin text editing if the current first responder can resign its first responder status.
- (void)beginTextEditing;

@property(nonatomic, readonly) BOOL wantsAccessibilityBeginEditingButton;

@end

@protocol OUINoteTextViewAppearanceDelegate <NSObject>

@optional
- (UIColor *)textColorForTextView:(OUINoteTextView *)textView;
- (UIColor *)placeholderTextColorForTextView:(OUINoteTextView *)textView;
- (UIColor *)borderColorForTextView:(OUINoteTextView *)textView;
- (UIKeyboardAppearance)keyboardAppearanceForTextView:(OUINoteTextView *)textView;
@end

#pragma mark -

extern const CGFloat OUINoteTextViewPlacholderTopMarginAutomatic;
