// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>

#import <OmniBase/OBUtilities.h> // for OB_DEPRECATED_ATTRIBUTE

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OFReplacement)

- (NSString *)stringByRemovingPrefix:(NSString *)prefix;
- (NSString *)stringByRemovingSuffix:(NSString *)suffix;

- (NSString *)stringByRemovingSurroundingWhitespace;  // New code should probably use -stringByTrimmingCharactersInSet: instead
- (NSString *)stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace;

- (NSString *)stringByRemovingString:(NSString *)removeString;
// - (NSString *)stringByPaddingToLength:(unsigned int)aLength;  // Use Foundation's new -stringByPaddingToLength:withString:startingAtIndex: method.

- (NSString *)stringByReplacingCharactersInSet:(NSCharacterSet *)set withString:(NSString *)replaceString;

- (NSString *)stringByReplacingKeysInDictionary:(NSDictionary <NSString *, NSString *> *)keywordDictionary startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString removeUndefinedKeys: (BOOL) removeUndefinedKeys;
// Useful for turning $(NEXT_ROOT)/LocalLibrary into C:/Apple/LocalLibrary.  If removeUndefinedKeys is YES and there is no key in the source dictionary, then @"" will be used to replace the variable substring. Uses -stringByReplacingKeys:.
- (NSString *)stringByReplacingKeysInDictionary:(NSDictionary <NSString *, NSString *> *)keywordDictionary startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString;
// Calls -stringByReplacingKeysInDictionary:startingDelimiter:endingDelimiter:removeUndefinedKeys: with removeUndefinedKeys NO.

typedef NSString * _Nullable (^OFVariableReplacementBlock)(NSString *key);

- (NSString *)stringByReplacingKeysWithStartingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString usingBlock:(OFVariableReplacementBlock)replacer;

// The most generic form of variable replacement, letting you use your own replacer instead of providing a keyword dictionary

// Generalized replacement function, and a convenience cover.

typedef NSString * _Nullable (*OFSubstringReplacementFunction)(NSString *, NSRange *, void * _Nullable);
- (NSString *)stringByPerformingReplacement:(OFSubstringReplacementFunction)replacer
                               onCharacters:(NSCharacterSet *)replaceMe
                                    context:(void * _Nullable)context
                                    options:(NSStringCompareOptions)options
                                      range:(NSRange)touchMe;
- (NSString *)stringByPerformingReplacement:(OFSubstringReplacementFunction)replacer
                               onCharacters:(NSCharacterSet *)replaceMe;

typedef NSString * _Nullable (^OFSubstringReplacementBlock)(NSString *, NSRange *);
- (NSString *)stringByPerformingReplacement:(OFSubstringReplacementBlock)replacer
                               onCharacters:(NSCharacterSet *)replaceMe
                                    options:(NSStringCompareOptions)options
                                      range:(NSRange)touchMe;

@end

@interface NSMutableString (OFReplacement)
- (void)replaceAllOccurrencesOfCharactersInSet:(NSCharacterSet *)set withString:(NSString *)replaceString;
@end

NS_ASSUME_NONNULL_END
