// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class UIView;

// There are occasions where some operation has to be delayed. For example, we might need to return to the run loop to close an existing undo group before an action that starts a new one. Returning to the run loop can begin animating the keyboard away. If the keyboard is displayed, and will need to be displayed for the next activity, we would get a bounce of the keyboard as it tries to exit then comes back. This class gives the keyboard a hidden text field to ponder for a moment.
// Usage: Construct a keyboard lock using the class method keyboardLockForView:keyboardType:. The lock's text field will become first responder before it is returned. Once you've established a first responder for your new activity, call the unlock method to clean up.
@interface OUIKeyboardLock : NSObject

+ (OUIKeyboardLock *)keyboardLockForView:(UIView *)parentView keyboardType:(UIKeyboardType)keyboardType NS_EXTENSION_UNAVAILABLE_IOS("Keyboard lock is not available in extensions");

- (id)initWithParentView:(UIView *)parentView keyboardType:(UIKeyboardType)keyboardType NS_EXTENSION_UNAVAILABLE_IOS("Keyboard lock is not available in extensions");

@property (nonatomic, readonly) BOOL isFirstResponder;

- (void)unlock NS_EXTENSION_UNAVAILABLE_IOS("Keyboard lock is not available in extensions");

@end
