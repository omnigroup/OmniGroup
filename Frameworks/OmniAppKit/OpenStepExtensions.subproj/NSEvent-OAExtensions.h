// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSEvent.h>

@interface NSEvent (OAExtensions)

- (BOOL)isUserCancel;
// Does this event represent a 'user cancel' event. Currently this is defined to be either the escape key being pressed, or command-period being pressed.

- (NSString *)charactersWithModifiers:(NSUInteger)modifierFlags;
// This returns what the current key event's key code would have returned if the passed in modifiers had been pressed.
// This does not correctly handle dead key processing from previous events however the returned value may be empty if this would be a dead key itself.

- (BOOL)isKeyDownWithUnmodifiedCharacter:(unichar)c;

// Always prefer to use the without: argument rather than calling checkFor{Any,All}ModiferFlags: twice. This is really more relevant to the class methods, because the keyboard state can change in between multiple calls to these methods.
- (BOOL)checkForAnyModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags; // Returns YES if the receiver's modifier flags include any of the desired flags AND do not include any of the prohibited flags (pass 0 if you have no flags to exclude)
+ (BOOL)checkForAnyModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags; // Same as above, but operates outside of the event stream

- (BOOL)checkForAllModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags; // Returns YES if the receiver's modifier flags include all the desired flags AND do not include any of the prohibited flags (pass 0 if you have no flags to exclude)
+ (BOOL)checkForAllModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags; // Same as instance method, but operates outside of the event stream

@end
