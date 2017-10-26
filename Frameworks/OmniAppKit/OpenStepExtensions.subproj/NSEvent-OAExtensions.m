// Copyright 2005-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Carbon/Carbon.h> // For shiftKey, controlKey, etc.  Must be imported early so that IOGraphicsTypes.h knows that Point is already defined by Carbon's MacTypes.h.

#import <OmniAppKit/NSEvent-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$");

@implementation NSEvent (OAExtensions)

- (BOOL)isUserCancel;
{
    if ([self type] != NSEventTypeKeyDown) {
        return NO;
    }
    
    NSUInteger modifierFlags = [self modifierFlags];
    NSString *characters = [self charactersIgnoringModifiers];
    
    if ([characters length] != 1) {
        return NO;
    }
    
    // Test for unmodified Escape
    if ((modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand)) == 0) {
        return [characters characterAtIndex:0] == 0x1B;
    }

    // Test for Command-Period
    if ((modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand)) == NSEventModifierFlagCommand) {
        return [characters isEqualToString:@"."];
    }

    return NO;
}

- (NSString *)charactersWithModifiers:(NSUInteger)modifierFlags;
{
    UInt32 eventModifiers = 0;
    if (modifierFlags & NSEventModifierFlagShift)
        eventModifiers |= shiftKey;
    if (modifierFlags & NSEventModifierFlagControl)
        eventModifiers |= controlKey;
    if (modifierFlags & NSEventModifierFlagCapsLock)
        eventModifiers |= alphaLock;
    if (modifierFlags & NSEventModifierFlagOption)
        eventModifiers |= optionKey;
    if (modifierFlags & NSEventModifierFlagCommand)
        eventModifiers |= cmdKey;

    // Check to see what character we would have gotten with the specified modifier flags.  (For example, would the Shift key have turned "=" into "+" for this key?)
    CFDataRef unicodeKeyLayoutData = TISGetInputSourceProperty(TISCopyCurrentKeyboardInputSource(), kTISPropertyUnicodeKeyLayoutData);
    const UCKeyboardLayout *keyboardLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(unicodeKeyLayoutData);

    UniCharCount actualStringLength;
    UInt32 deadKeyState = 0;
    UniChar unicodeString[255];
    
    OSStatus status = UCKeyTranslate(keyboardLayout, [self keyCode], kUCKeyActionDown, eventModifiers >> 8, LMGetKbdType(), kUCKeyTranslateNoDeadKeysMask, &deadKeyState, sizeof(unicodeString) / sizeof(*unicodeString), &actualStringLength, unicodeString);
    OBASSERT(status == noErr);
    if (status == noErr) {
        return [NSString stringWithCharacters:unicodeString length:actualStringLength];
    } else {
        return nil;
    }
}

- (BOOL)isKeyDownWithUnmodifiedCharacter:(unichar)c;
{
    if ([self type] != NSEventTypeKeyDown)
        return NO;
    
    NSString *string = [self charactersIgnoringModifiers];
    return ([string length] == 1) && [string characterAtIndex:0] == c;
}

static BOOL _checkModifierFlags(NSUInteger current, NSUInteger desired, NSUInteger prohibited, BOOL requireAll)
{
    OBPRECONDITION((desired & prohibited) == 0);
    
    current = current & NSEventModifierFlagDeviceIndependentFlagsMask; // Mask off extra info that gets stuffed into the modifier flags
    
    if (current & prohibited)
        return NO;
    
    if (requireAll)
        return (current & desired) == desired;
    else
        return (current & desired) != 0;
}

- (BOOL)checkForAnyModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags;
{
    return _checkModifierFlags([self modifierFlags], desiredFlags, prohibitedFlags, NO);
}

+ (BOOL)checkForAnyModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags;
{
    return _checkModifierFlags([self modifierFlags], desiredFlags, prohibitedFlags, NO);
}

- (BOOL)checkForAllModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags;
{
    return _checkModifierFlags([self modifierFlags], desiredFlags, prohibitedFlags, YES);
}

+ (BOOL)checkForAllModifierFlags:(NSUInteger)desiredFlags without:(NSUInteger)prohibitedFlags;
{
    return _checkModifierFlags([self modifierFlags], desiredFlags, prohibitedFlags, YES);
}

@end

