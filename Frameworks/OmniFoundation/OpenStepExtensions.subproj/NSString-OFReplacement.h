// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSString.h>

#import <OmniBase/OBUtilities.h> // for OB_DEPRECATED_ATTRIBUTE

@interface NSString (OFReplacement)

- (NSString *)stringByRemovingPrefix:(NSString *)prefix;
- (NSString *)stringByRemovingSuffix:(NSString *)suffix;

- (NSString *)stringByRemovingSurroundingWhitespace;  // New code should probably use -stringByTrimmingCharactersInSet: instead
- (NSString *)stringByRemovingString:(NSString *)removeString;
// - (NSString *)stringByPaddingToLength:(unsigned int)aLength;  // Use Foundation's new -stringByPaddingToLength:withString:startingAtIndex: method.

- (NSString *)stringByReplacingAllOccurrencesOfString:(NSString *)stringToReplace withString:(NSString *)replacement;
// Can be better than making a mutable copy and calling -[NSMutableString replaceOccurrencesOfString:withString:options:range:] -- if stringToReplace is not found in the receiver, then the receiver is retained, autoreleased, and returned immediately.

- (NSString *)stringByReplacingCharactersInSet:(NSCharacterSet *)set withString:(NSString *)replaceString;

- (NSString *)stringByReplacingKeysInDictionary:(NSDictionary *)keywordDictionary startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString removeUndefinedKeys: (BOOL) removeUndefinedKeys;
// Useful for turning $(NEXT_ROOT)/LocalLibrary into C:/Apple/LocalLibrary.  If removeUndefinedKeys is YES and there is no key in the source dictionary, then @"" will be used to replace the variable substring. Uses -stringByReplacingKeys:.
- (NSString *)stringByReplacingKeysInDictionary:(NSDictionary *)keywordDictionary startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString;
// Calls -stringByReplacingKeysInDictionary:startingDelimiter:endingDelimiter:removeUndefinedKeys: with removeUndefinedKeys NO.

typedef NSString *(*OFVariableReplacementFunction)(NSString *, void *);
- (NSString *)stringByReplacingKeys:(OFVariableReplacementFunction)replacer startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString context:(void *)context;
// The most generic form of variable replacement, letting you use your own replacer instead of providing a keyword dictionary

// Generalized replacement function, and a convenience cover.
typedef NSString *(*OFSubstringReplacementFunction)(NSString *, NSRange *, void *);
- (NSString *)stringByPerformingReplacement:(OFSubstringReplacementFunction)replacer
                               onCharacters:(NSCharacterSet *)replaceMe
                                    context:(void *)context
                                    options:(NSStringCompareOptions)options
                                      range:(NSRange)touchMe;
- (NSString *)stringByPerformingReplacement:(OFSubstringReplacementFunction)replacer
                               onCharacters:(NSCharacterSet *)replaceMe;

@end

@interface NSMutableString (OFReplacement)
- (void)replaceAllOccurrencesOfCharactersInSet:(NSCharacterSet *)set withString:(NSString *)replaceString;
@end
