// Copyright 1998-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTelephoneFormatter.h>

#import <OmniFoundation/NSObject-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFTelephoneFormatter

- (NSString *)stringForObjectValue:(id)object;
{
    return object;
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error;
{
    if (!anObject)
        return YES;

    if (![string length]) {
        *anObject = nil;
        return YES;
    } else if ([string length] < 14) {
        if (error)
            *error = NSLocalizedStringFromTableInBundle(@"That is not a valid phone number.", @"OmniFoundation", [OFTelephoneFormatter bundle], @"formatter input error");
        *anObject = nil;
        return NO;
    } else if ([string length] < 17) {
        *anObject = [string substringToIndex:14];
    } else {
        *anObject = string;
    }
    return YES;
}

enum PhoneState {
    ScanOpenParen, ScanAreaCode, ScanCloseParen, ScanExchangeSpace, ScanExchange, ScanDash, ScanNumber, ScanExtensionSpace, ScanX, ScanExtension, Done
};

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;
{
    unsigned int length = [partialString length];
    unsigned int characterIndex;
    unsigned int digits = 0;
    enum PhoneState state = ScanOpenParen;
    unichar result[20];
    unichar *resultPtr = result;
    unichar c;
    BOOL changed = NO;

    for (characterIndex = 0; characterIndex < length; characterIndex++) {
	changed = NO;
        c = [partialString characterAtIndex:characterIndex];

        switch(state) {
            case ScanOpenParen:
                if (c == '(') {
                    *resultPtr++ = c;
                    state = ScanAreaCode;
                    digits = 0;
                } else if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = '(';
                    *resultPtr++ = c;
                    state = ScanAreaCode;
                    digits = 1;
                    changed = YES;
                } else {
                    changed = YES;
                }
                break;
            case ScanAreaCode:
                if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = c;
                    if (++digits == 3)
                        state = ScanCloseParen;
                } else {
                    changed = YES;
                }
                break;
            case ScanCloseParen:
                if (c == ')') {
                    *resultPtr++ = c;
                    state = ScanExchangeSpace;
                } else if (c == ' ') {
                    *resultPtr++ = ')';
                    *resultPtr++ = ' ';
                    state = ScanExchange;
                    digits = 0;
                    changed = YES;
                } else if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = ')';
                    *resultPtr++ = ' ';
                    *resultPtr++ = c;
                    state = ScanExchange;
                    digits = 1;
                    changed = YES;
                } else {
                    changed = YES;
                }
                break;
            case ScanExchangeSpace:
                if (c == ' ') {
                    *resultPtr++ = c;
                    state = ScanExchange;
                    digits = 0;
                } else if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = ' ';
                    *resultPtr++ = c;
                    state = ScanExchange;
                    digits = 1;
                    changed = YES;
                } else {
                    changed = YES;
                }
                break;
            case ScanExchange:
                if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = c;
                    if (++digits == 3)
                        state = ScanDash;
                } else {
                    changed = YES;
                }                
                break;
            case ScanDash:
                if (c == '-') {
                    *resultPtr++ = c;
                    state = ScanNumber;
                    digits = 0;
                } else if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = '-';
                    *resultPtr++ = c;
                    state = ScanNumber;
                    digits = 1;
                    changed = YES;
                } else {
                    changed = YES;
                }
                break;
            case ScanNumber:
                if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = c;
                    if (++digits == 4)
                        state = ScanExtensionSpace;
                } else {
                    changed = YES;
                }                
                break;
            case ScanExtensionSpace:
                if (c == ' ') {
                    *resultPtr++ = c;
                    state = ScanX;
                } else if (c == 'x') {
                    *resultPtr++ = ' ';
                    *resultPtr++ = c;
                    state = ScanExtension;
                    digits = 0;
                    changed = YES;
                } else if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = ' ';
                    *resultPtr++ = 'x';
                    *resultPtr++ = c;
                    state = ScanExtension;
                    digits = 1;
                    changed = YES;
                } else {
                    changed = YES;
                }                
                break;
            case ScanX:
                if (c == 'x') {
                    *resultPtr++ = c;
                    state = ScanExtension;
                    digits = 0;
                } else if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = 'x';
                    *resultPtr++ = c;
                    state = ScanExtension;
                    digits = 1;
                    changed = YES;
                } else {
                    changed = YES;
                }
                break;
            case ScanExtension:
                if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = c;
                    if (++digits == 4)
                        state = Done;
                } else {
                    changed = YES;
                }                
                break;
            case Done:
                changed = YES;
                break;
        }
    }
    if (changed)
        *newString = [NSString stringWithCharacters:result length:(resultPtr - result)];
    return !changed;
}

@end
