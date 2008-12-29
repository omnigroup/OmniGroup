// Copyright 2005-2007 Omni Development, Inc.  All rights reserved.
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

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSEvent-OAExtensions.m 93428 2007-10-25 16:36:11Z kc $");

@implementation NSEvent (OAExtensions)

- (NSString *)charactersWithModifiers:(unsigned int)modifierFlags;
{
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5  // Uses API deprecated on 10.5
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

    // check if the shifted version of this key would have made the font bigger...
    SInt16 currentKeyScript = GetScriptManagerVariable(smKeyScript);
    SInt16 currentKeyLayoutID = GetScriptVariable(currentKeyScript, smScriptKeys);
    UCKeyboardLayout **myKeyLayout = (UCKeyboardLayout **)GetResource('uchr', currentKeyLayoutID);
    // if there is a 'uchr' for the current keyboard layout, 
    // use it
    if (myKeyLayout != NULL) {
        UniCharCount actualStringLength;
        UInt32 deadKeyState = 0;
        UniChar unicodeInputString[255];
        
        //NSLog(@"keyLayout = %p", myKeyLayout);
        OSStatus status = UCKeyTranslate(*myKeyLayout, 
                                         [self keyCode], 
                                         kUCKeyActionDown,
                                         eventModifiers >> 8, 
                                         LMGetKbdType(), 
                                         kUCKeyTranslateNoDeadKeysMask,
                                         &deadKeyState,
                                         255,
                                         &actualStringLength, 
                                         unicodeInputString);
        // now do something with status and unicodeInputString
        if (status == noErr) {
            //NSLog(@"unicodeInputString = %c", unicodeInputString[0]);
            return [NSString stringWithCharacters:unicodeInputString length:actualStringLength];
        } else {
            // NSLog(@"status = %d", status);
            return nil;
        }
    } else {
        // no 'uchr' resource, do something with 'KCHR'?
        //NSLog(@"myKeyboardLayout was null");
        const void **transData = (const void **)GetResource('KCHR', currentKeyLayoutID);
        UInt32 state = 0;
        if (transData != NULL) {
            UInt32 result = KeyTranslate(*transData,
                                         ([self keyCode] & 0x3F) | (eventModifiers & 0xFF00), 
                                         &state);
            //NSLog(@"result = %08llx", (long long)result);
            
            char macRomanChars[2];
            int length = 0;
            
            if (result & 0x00FF0000) {
                length = 2;
                macRomanChars[0] = (result & 0x00FF0000) >> 16;
                macRomanChars[1] = result & 0x000000FF;
            } else if (result & 0x000000FF) {
                length = 1;
                macRomanChars[0] = result & 0x000000FF;
            }
            return [[[NSString alloc] initWithData:[NSData dataWithBytes:macRomanChars length:length] encoding:NSMacOSRomanStringEncoding] autorelease];
        } else {
            // no 'KCHR' resource, punt!!!
            //NSLog(@"no 'KCHR' resource, punt!!!");
            return nil;
        }
    }
#else
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
#endif
}

@end

