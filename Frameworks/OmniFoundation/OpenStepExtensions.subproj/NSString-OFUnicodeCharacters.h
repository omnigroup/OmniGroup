// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFUnicodeCharacters.h>


@interface NSString (OFUnicodeCharacters)

+ (NSString *)stringWithCharacter:(UnicodeScalarValue)aCharacter; /* Returns a string containing the given Unicode character. Will generate a surrogate pair for characters > 0xFFFF (which cannot be represented by a single unichar). */

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

+ (NSCharacterSet *)invalidXMLCharacterSet;  // Characters forbidden in an XML document
+ (NSCharacterSet *)discouragedXMLCharacterSet;  // Characters discouraged in an XML document (a superset of -invalidXMLCharacterSet)

@end
