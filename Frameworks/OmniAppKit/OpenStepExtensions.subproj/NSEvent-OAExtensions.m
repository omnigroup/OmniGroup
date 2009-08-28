// Copyright 2005-2007, 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Carbon/Carbon.h> // For shiftKey, controlKey, etc.  Must be imported early so that IOGraphicsTypes.h knows that Point is already defined by Carbon's MacTypes.h.

#import "NSEvent-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$");

@implementation NSEvent (OAExtensions)

- (NSString *)charactersWithModifiers:(unsigned int)modifierFlags;
{
    UInt32 eventModifiers = 0;
    if (modifierFlags & NSShiftKeyMask)
        eventModifiers |= shiftKey;
    if (modifierFlags & NSControlKeyMask)
        eventModifiers |= controlKey;
    if (modifierFlags & NSAlphaShiftKeyMask)
        eventModifiers |= alphaLock;
    if (modifierFlags & NSAlternateKeyMask)
        eventModifiers |= optionKey;
    if (modifierFlags & NSCommandKeyMask)
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

@end

