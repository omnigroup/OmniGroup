// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniUI/OUIKeyboardLock.h>

#import <OmniUI/OUIAppController.h>
#import <UIKit/UITextField.h>
#import <UIKit/UITextInputTraits.h> // for UIKeyboardType
#import <UIKit/UIView.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define DEBUG_KEYBOARD(format, ...) NSLog(@"KEYBOARD LOCK: " format, ## __VA_ARGS__)
#else
#define DEBUG_KEYBOARD(format, ...)
#endif

@interface OUIKeyboardLock () <UITextFieldDelegate> {
    UITextField *hackTextField;
}

@end

#pragma mark -

@implementation OUIKeyboardLock

+ (OUIKeyboardLock *)keyboardLockForView:(UIView *)parentView keyboardType:(UIKeyboardType)keyboardType;
{
    return [[self alloc] initWithParentView:parentView keyboardType:keyboardType];
}

- (id)initWithParentView:(UIView *)parentView keyboardType:(UIKeyboardType)keyboardType;
{
    self = [super init];
    if (self) {
        DEBUG_KEYBOARD(@"Created for superview %@, type %ld", OBShortObjectDescription(parentView), keyboardType);

        hackTextField = [[UITextField alloc] initWithFrame:CGRectZero];
        hackTextField.delegate = self;
        hackTextField.keyboardType = keyboardType;
        hackTextField.keyboardAppearance = [OUIAppController controller].defaultKeyboardAppearance;
        [parentView addSubview:hackTextField];
        if (![hackTextField becomeFirstResponder]) {
            OBASSERT_NOT_REACHED("Expect the hidden text field to accept first responder");
        }
    }
    return self;
}

- (void)dealloc
{
    OBPRECONDITION(![hackTextField isFirstResponder]);
    OBPRECONDITION(hackTextField.superview == nil); // call unlock after setting new first responder
}

- (BOOL)isFirstResponder;
{
    return [hackTextField isFirstResponder];
}

- (void)unlock;
{
    OBPRECONDITION(![hackTextField isFirstResponder]);
    [hackTextField removeFromSuperview];
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    DEBUG_KEYBOARD(@"Will end");
    return YES;
}

@end
