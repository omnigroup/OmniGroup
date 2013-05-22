// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniUI/OUIKeyboardLock.h>

#import <UIKit/UITextField.h>
#import <UIKit/UITextInputTraits.h> // for UIKeyboardType
#import <UIKit/UIView.h>

RCS_ID("$Id$");

@implementation OUIKeyboardLock

+ (OUIKeyboardLock *)keyboardLockForView:(UIView *)parentView keyboardType:(UIKeyboardType)keyboardType;
{
    return [[[self alloc] initWithParentView:parentView keyboardType:keyboardType] autorelease];
}

- (id)initWithParentView:(UIView *)parentView keyboardType:(UIKeyboardType)keyboardType;
{
    self = [super init];
    if (self) {
        hackTextField = [[UITextField alloc] initWithFrame:CGRectZero];
        hackTextField.keyboardType = keyboardType;
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
    
    [hackTextField release];
    
    [super dealloc];
}

- (void)unlock;
{
    OBPRECONDITION(![hackTextField isFirstResponder]);
    [hackTextField removeFromSuperview];
}

@end
