// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/NSString-OFUnicodeCharacters.h>


@interface NSString (OFUnicodeCharacters)

+ (NSString *)stringWithCharacter:(unsigned int)aCharacter; /* Returns a string containing the given Unicode character. Will generate a surrogate pair for characters > 0xFFFF (which cannot be represented by a single unichar). */

// These methods return strings containing the indicated character

+ (NSString *)horizontalEllipsisString; // '...'
+ (NSString *)leftPointingDoubleAngleQuotationMarkString; // '<<'
+ (NSString *)rightPointingDoubleAngleQuotationMarkString; // '>>'
+ (NSString *)emdashString; // '---'
+ (NSString *)endashString; // '--'
+ (NSString *)commandKeyIndicatorString;
+ (NSString *)controlKeyIndicatorString;
+ (NSString *)alternateKeyIndicatorString;
+ (NSString *)shiftKeyIndicatorString;

@end
