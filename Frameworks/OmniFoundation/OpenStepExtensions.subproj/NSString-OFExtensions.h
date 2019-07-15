// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>

// Gather other extensions that have been factored out
#import <OmniFoundation/NSString-OFUnicodeCharacters.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFoundation/NSString-OFCharacterEnumeration.h>
#import <OmniBase/objc.h>

#import <Foundation/NSDate.h> // For NSTimeInterval

#import <CoreFoundation/CFString.h>  // for CFStringEncoding

@class NSRegularExpression;
@class OFCharacterSet;
@class OFRegularExpressionMatch;

/* A note on deferred string decoding.

A recurring problem in OmniWeb is dealing with strings whose encoding is unknown. Usually this is because a protocol or format was originally specified in terms of 7-bit ASCII, and has later been extended to support larger character sets by adding a character encoding field (in ASCII). This shows up in HTML (the <META> tag is often used to specify its own file's interpretation), FTP (the MLST/MLSD response includes a charset field, possibly different for each line of the response), XML (the charset attribute in the declaration element), etc.

One way to handle this would be to treat these as octet-strings rather than character-strings, until their encoding is known. However, keeping octet-strings in NSDatas would keep us from using the large library of useful routines which manipulate NSStrings.

Instead, OmniFoundation sets aside a range of 256 code points in the Supplementary Private Use Area A to represent bytes which have not yet been converted into characters. OFStringDecoder understands a new encoding, OFDeferredASCIISupersetStringEncoding, which interprets ASCII as ASCII but maps all apparently non-ASCII bytes into the private use area. Later, the original byte sequence can be recovered (including interleaved high-bit-clear bytes, since the ASCII->Unicode->ASCII roundtrip is lossless) and the correct string encoding can be applied.

It's intended that strings containing these private-use code points have as short a lifetime and as limited a scope as possible. We don't want our private-use characters getting out into the rest of the world and gumming up glyph generation or being mistaken for someone else's private-use characters. As soon as the correct string encoding is known, all strings should be re-encoded using -stringByApplyingDeferredCFEncoding: or an equivalent function.

Low-level functions for dealing with NSStrings containing "deferred" bytes/characters can be found in OFStringDecoder. In general, searching, splitting, and combining strings containing deferred characters can be done safely, as long as you don't split up any deferred multibyte characters. In addition, the following methods in this file understand deferred-encoding strings and will do the right thing:

   -stringByApplyingDeferredCFEncoding:
   -dataUsingCFEncoding:
   -dataUsingCFEncoding:allowLossyConversion:
   -dataUsingCFEncoding:allowLossyConversion:hexEscapes:
   -encodeURLString:asQuery:leaveSlashes:leaveColons:
   -encodeURLString:encoding:asQuery:leaveSlashes:leaveColons:
   -fullyEncodeAsIURI:

Currently the only way to create strings with deferred bytes/characters is using OFStringDecoder (possibly via OWDataStreamCharacterCursor/Scanner).

*/

@interface NSString (OFExtensions)
+ (CFStringEncoding)cfStringEncodingForDefaultValue:(NSString *)encodingName;
+ (NSString *)defaultValueForCFStringEncoding:(CFStringEncoding)anEncoding;
+ (NSString *)abbreviatedStringForBytes:(unsigned long long)bytes;
+ (NSString *)abbreviatedStringForHertz:(unsigned long long)hz;
+ (NSString *)approximateStringForTimeInterval:(NSTimeInterval)interval;
+ (NSString *)spacesOfLength:(NSUInteger)aLength;
+ (NSString *)stringWithStrings:(NSString *)first, ... NS_REQUIRES_NIL_TERMINATION;

- (BOOL)isPercentage;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
+ (NSString *)stringWithFourCharCode:(FourCharCode)code;
- (FourCharCode)fourCharCodeValue;
#endif

- (NSString *)stringByUppercasingAndUnderscoringCaseChanges;
- (NSString *)stringByRemovingWhitespace;
- (NSString *)stringByRemovingCharactersInOFCharacterSet:(OFCharacterSet *)removeSet;
- (NSString *)stringByRemovingReturns;
- (NSString *)stringByRemovingRegularExpression:(NSRegularExpression *)regularExpression;

enum {
    OFStringNormlizationOptionLowercase = 0x01,
    OFStringNormlizationOptionUppercase = 0x02,
    OFStringNormilzationOptionStripCombiningMarks = 0x04,
    OFStringNormilzationOptionStripPunctuation = 0x08
};

- (NSString *)stringByNormalizingWithOptions:(NSUInteger)options locale:(NSLocale *)locale;

- (NSString *)stringByPaddingToLength:(NSUInteger)aLength;

- (NSString *)stringByNormalizingPath;
    // Normalizes a path like /a/b/c/../../d to /a/d.
    // Note: Does not work properly on Windows at the moment because it is hardcoded to use forward slashes rather than using the native path separator.
- (unichar)firstCharacter;
- (unichar)lastCharacter;
- (NSString *)lowercaseFirst;
- (NSString *)uppercaseFirst;

- (NSString *)stringByApplyingDeferredCFEncoding:(CFStringEncoding)newEncoding;

- (NSString *)stringByReplacingAllOccurrencesOfRegularExpressionPattern:(NSString *)pattern withString:(NSString *)newString;
    // Note: Useful, but fairly expensive!
- (NSString *)stringByReplacingAllOccurrencesOfRegularExpression:(NSRegularExpression *)matchExpression withString:(NSString *)newString;
- (NSString *)stringByReplacingAllOccurrencesOfRegularExpression:(NSRegularExpression *)matchExpression withAction:(NSString *(^)(OFRegularExpressionMatch *))action;

- (NSString *)stringByReplacingOccurancesOfString:(NSString *)targetString withObjectsFromArray:(NSArray *)sourceArray;

- (NSString *)stringBySeparatingSubstringsOfLength:(NSUInteger)substringLength withString:(NSString *)separator startingFromBeginning:(BOOL)startFromBeginning;

- (NSString *)substringStartingWithString:(NSString *)startString;
- (NSString *)substringStartingAfterString:(NSString *)startString;
- (NSArray *)componentsSeparatedByString:(NSString *)separator maximum:(NSUInteger)atMost;
- (NSArray *)componentsSeparatedByCharactersFromSet:(NSCharacterSet *)delimiterSet;

typedef NS_OPTIONS(NSUInteger, OFComponentsSeparatedByStringOptions) {
    OFComponentsSeparatedByStringOptionsConsumeWhitespaceSurroundingDelimiter = 0x01,
};
- (NSArray *)componentsSeparatedByString:(NSString *)separator options:(OFComponentsSeparatedByStringOptions)options;
- (NSArray *)componentsSeparatedByRegularExpression:(NSRegularExpression *)expression;

- (NSString *)stringByIndenting:(NSInteger)spaces;
- (NSString *)stringByWordWrapping:(NSInteger)columns;
- (NSString *)stringByIndenting:(NSInteger)spaces andWordWrapping:(NSInteger)columns;
- (NSString *)stringByIndenting:(NSInteger)spaces andWordWrapping:(NSInteger)columns withFirstLineIndent:(NSInteger)firstLineSpaces;


- (NSRange)findString:(NSString *)string selectedRange:(NSRange)selectedRange options:(NSStringCompareOptions)options wrap:(BOOL)wrap;

- (NSRange)rangeOfCharactersAtIndex:(NSUInteger)pos
                        delimitedBy:(NSCharacterSet *)delim;
- (NSRange)rangeOfWordContainingCharacter:(NSUInteger)pos;
- (NSRange)rangeOfWordsIntersectingRange:(NSRange)range;

// Can we drop this and use something in OFXMLString instead?
#if 0
- (NSString *)htmlString;
#endif

/* Regular expression encoding */
- (NSString *)regularExpressionForLiteralString;

@property (readonly) BOOL isEmailAddress;

/* Mail header encoding according to RFCs 822 and 2047 */
- (NSString *)asRFC822Word;         /* Returns an 'atom' or 'quoted-string', or nil if not possible */
- (NSString *)asRFC2047EncodedWord; /* Returns an 'encoded-word' representing the receiver */
- (NSString *)asRFC2047Phrase;      /* Returns a sequence of atoms, quoted-strings, and encoded-words, as appropriate to represent the receiver in the syntax defined by RFC822 and RFC2047. */

- (NSString *)stringByTruncatingToMaximumLength:(NSUInteger)maximumLength atSpaceAfterMinimumLength:(NSUInteger)minimumLength;

/// Create a dictionary for use with CSLocalizedString (for example)
/// Adopted with ever so slight modification from here https://forums.developer.apple.com/thread/15943
/// Take note of the warning: """IMPORTANT This is crazy inefficient.  If you’re doing this for lots of strings, you’ll want to process the dictionaries in bulk and cache the results."""
+ (NSDictionary *)localizedStringDictionaryForKey:(NSString *)key table:(NSString *)tableName bundle:(NSBundle *)bundle;

@end

/* Creating an ASCII representation of a floating-point number, without using exponential notation. */
/* OFCreateDecimalStringFromDouble() formats a double into an NSString (which must be released by the caller, hence the word 'create' in the function name). This function will never return a value in exponential notation: it will always be in integer/decimal notation. If the returned string includes a decimal point, there will always be at least one digit on each side of the decimal point. */
extern NSString *OFCreateDecimalStringFromDouble(double value) NS_RETURNS_RETAINED;
/* OFASCIIDecimalStringFromDouble() returns a malloc()d buffer containing the decimal string, in ASCII. */
extern char *OFASCIIDecimalStringFromDouble(double value);
/* OFShortASCIIDecimalStringFromDouble() returns a malloc()d buffer containing the decimal string, in ASCII.
   eDigits indicates the number of significant digits of the number, in base e.
   allowExponential indicates that an exponential representation may be returned if it's shorter than the plain decimal representation.
   forceLeadingZero forces a digit before the decimal point (e.g. 0.1 instead of .1). */
extern char *OFShortASCIIDecimalStringFromDouble(double value, double eDigits, BOOL allowExponential, BOOL forceLeadingZero);
extern double OFFloatDigitsBaseE(void);
#define OF_FLT_DIGITS_E (OFFloatDigitsBaseE()) // How many digits to preserve from a float
