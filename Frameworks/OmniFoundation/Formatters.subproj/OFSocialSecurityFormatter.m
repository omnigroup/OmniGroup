// Copyright 1998-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFSocialSecurityFormatter.h>

#import <OmniFoundation/NSObject-OFExtensions.h>

@implementation OFSocialSecurityFormatter

- (NSString *)stringForObjectValue:(id)object;
{
    return object;
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error;
{
    BOOL isValid;
    NSString *newString = nil;

    if ([string length] == 0) {
        if (anObject)
            *anObject = nil;
        return YES;
    }

    isValid = [self isPartialStringValid:string newEditingString:&newString errorDescription:error];

    if (!anObject) {
        if (!isValid && error)
            *error = NSLocalizedStringFromTableInBundle(@"That is not a valid social security number.", @"OmniFoundation", [OFSocialSecurityFormatter bundle], @"formatter input error");
        return isValid;
    }

    if (!newString)
        newString = string;

    if ([newString length] < 11) {
        if (error)
            *error = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"'%@' is not a valid social security number.", @"OmniFoundation", [OFSocialSecurityFormatter bundle], @"formatter input error format"), string];
        *anObject = nil;
        return NO;
    } else {
        *anObject = newString;
    }
    return YES;
}

enum SocialSecurityState {
    ScanFirstPart, ScanSecondPart, ScanThirdPart, ScanDash, Done
};

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;
{
    unsigned int length = [partialString length];
    unsigned int characterIndex;
    unsigned int digits = 0;
    enum SocialSecurityState state = ScanFirstPart;
    enum SocialSecurityState previousState = -1;
    unichar result[20];
    unichar *resultPtr = result;
    unichar c;
    BOOL changed = NO;
    BOOL droppedCharacters = NO;

    for (characterIndex = 0; characterIndex < length; characterIndex++) {
        c = [partialString characterAtIndex:characterIndex];

        switch(state) {
            case ScanFirstPart:
                if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = c;
                    if (++digits == 3) {
                        state = ScanDash;
                        previousState = ScanFirstPart;
                    }
                } else {
                    changed = YES;
                    droppedCharacters = YES;
                }
                break;
            case ScanSecondPart:
                if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = c;
                    if (++digits == 2) {
                        state = ScanDash;
                        previousState = ScanSecondPart;
                    }
                } else {
                    changed = YES;
                    droppedCharacters = YES;
                }
                break;
            case ScanDash:
                if (c == '-') {
                    *resultPtr++ = c;
                    if (previousState == ScanFirstPart) {
                        state = ScanSecondPart;
                    } else {
                        state = ScanThirdPart;
                    }
                    previousState = ScanDash;
                    digits = 0;
                } else if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = '-';
                    *resultPtr++ = c;
                    if (previousState == ScanFirstPart) {
                        state = ScanSecondPart;
                    } else {
                        state = ScanThirdPart;
                    }
                    previousState = ScanDash;
                    digits = 1;
                    changed = YES;
                } else {
                    changed = YES;
                    droppedCharacters = YES;
                }
                break;
            case ScanThirdPart:
                if ((c >= '0') && (c <= '9')) {
                    *resultPtr++ = c;
                    if (++digits == 4) {
                        state = Done;
                        previousState = ScanThirdPart;
                    }
                } else {
                    changed = YES;
                    droppedCharacters = YES;
                }
                break;
            case Done:
                changed = YES;
                droppedCharacters = YES;
                break;
        }
    }
    if (changed)
        *newString = [NSString stringWithCharacters:result length:(resultPtr - result)];
    return !droppedCharacters;
}

@end
