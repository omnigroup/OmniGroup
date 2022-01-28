// Copyright 2007-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCompletionMatch.h>

#import <OmniFoundation/OFCharacterSet.h>
#import <OmniFoundation/OFIndexPath.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>

#import <Foundation/NSAttributedString.h>

RCS_ID("$Id$");

static NSInteger OFCompletionMatchScoreFullMatch = 0;
static NSInteger OFCompletionMatchScorePhraseStart = 0;
static NSInteger OFCompletionMatchScoreePhraseEnd = 0;
static NSInteger OFCompletionMatchScoreConsecutiveCharacter = 0;
static NSInteger OFCompletionMatchScoreConsecutiveWord = 0;
static NSInteger OFCompletionMatchScoreWordStart = 0;
static NSInteger OFCompletionMatchScoreCapitalLetter = 0;

static OFCharacterSet *_WhitespaceOFCharacterSet = nil;
static OFCharacterSet *_UppercaseLetterOFCharacterSet = nil;

const OFCompletionMatchingOptions OFCompletionMatchingDefaultOptions = (OFCompletionMatchingOptionCaseInsensitive | OFCompletionMatchingOptionDiacriticInsensitive);

@interface OFCompletionMatch ()

+ (nullable NSString *)_preretainedCanonicalStringForString:(nullable NSString *)string options:(OFCompletionMatchingOptions)options NS_RETURNS_RETAINED;

- (id)initWithString:(NSString *)string;
- (OFCompletionMatch *)_preretainedSequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(NSInteger)score NS_RETURNS_RETAINED;
- (OFCompletionMatch *)_preretainedSequenceByAddingScore:(NSInteger)score NS_RETURNS_RETAINED;

@end

@implementation OFCompletionMatch

static BOOL calculateIndexesOfLastMatchesInName(
                NSUInteger filterStartIndex,
                NSUInteger filterLength,
                NSString *filter, // Assumed to be in canonical form, and with transforms appropriate for the current options already to be applied to it
                NSUInteger nameCharacterStartIndex,
                NSUInteger nameLength,
                NSString *name, // Assumed to be in canonical form, and with the transforms appropriate for the current options already to be applied to it
                NSUInteger *lastMatchIndexes);

static void filterIntoResults(
                NSUInteger filterIndex,
                NSUInteger filterLength,
                NSString *filter, // Assumed to be in canonical form, and with transforms appropriate for the current options already to be applied to it
                NSUInteger *lastMatchIndexes,
                BOOL wasInWhitespace,
                NSUInteger nameWordIndex,
                NSUInteger nameCharacterIndex,
                NSUInteger nameLength,
                NSString *name, // Assumed to be in canonical form, and with the transforms appropriate for the current options already to be applied to it
                NSString *originalName,
                OFCompletionMatch *completionMatch,
                NSMutableArray<OFCompletionMatch *> *results);

+ (void)initialize;
{
    OBINITIALIZE;

    _WhitespaceOFCharacterSet = [[OFCharacterSet whitespaceOFCharacterSet] retain];
    _UppercaseLetterOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:[NSCharacterSet uppercaseLetterCharacterSet]];
    
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    OFCompletionMatchScoreFullMatch = [preferences integerForKey:@"OFCompletionMatchScoreForFullMatch"];
    OFCompletionMatchScorePhraseStart = [preferences integerForKey:@"OFCompletionMatchScoreForPhraseStart"];
    OFCompletionMatchScoreePhraseEnd = [preferences integerForKey:@"OFCompletionMatchScoreForPhraseEnd"];
    OFCompletionMatchScoreConsecutiveCharacter = [preferences integerForKey:@"OFCompletionMatchScoreForConsecutiveCharacter"];
    OFCompletionMatchScoreConsecutiveWord = [preferences integerForKey:@"OFCompletionMatchScoreForConsecutiveWord"];
    OFCompletionMatchScoreWordStart = [preferences integerForKey:@"OFCompletionMatchScoreForWordStart"];
    OFCompletionMatchScoreCapitalLetter = [preferences integerForKey:@"OFCompletionMatchScoreForCapitalLetter"];
}

static inline BOOL _isASCII(NSString *string)
{
    CFStringInlineBuffer buffer;
    CFIndex length = string.length;
    
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, length));
    
    for (CFIndex i = 0; i < length; i++) {
        UniChar ch = CFStringGetCharacterFromInlineBuffer(&buffer, i);
        if (ch > 0x7F) {
            return NO;
        }
    }

    return YES;
}

+ (nullable NSString *)_preretainedCanonicalStringForString:(nullable NSString *)string options:(OFCompletionMatchingOptions)options;
{
    if (string == nil) {
        return nil;
    }
    
    BOOL isASCII = _isASCII(string);
    if (isASCII && options == 0) {
        return [string retain];
    }
    
    NSMutableString *canonicalString = nil;
    
    if ((options & OFCompletionMatchingOptionCaseInsensitive) != 0) {
        canonicalString = [[string lowercaseStringWithLocale:nil] mutableCopy];
    } else {
        canonicalString = [string mutableCopy];
    }
    
    if (!isASCII && (options & OFCompletionMatchingOptionDiacriticInsensitive) != 0) {
        CFStringTransform((__bridge CFMutableStringRef)canonicalString, NULL, kCFStringTransformStripDiacritics, NO);
    }
    
    if (!isASCII) {
        CFStringNormalize((__bridge CFMutableStringRef)canonicalString, kCFStringNormalizationFormC);
    }
    
    return canonicalString;
}

+ (nullable NSString *)canonicalStringForString:(nullable NSString *)string options:(OFCompletionMatchingOptions)options;
{
    NSString *canonialString = [self _preretainedCanonicalStringForString:string options:options];
    return [canonialString autorelease];
}
    
+ (NSArray<NSString *> *)canonicalStringsArrayForStringsArray:(NSArray<NSString *> *)strings options:(OFCompletionMatchingOptions)options;
{
    NSMutableArray *results = [NSMutableArray array];
    
    for (NSString *string in strings) {
        NSString *canonicalString = [self _preretainedCanonicalStringForString:string options:options];
        [results addObject:canonicalString];
        [canonicalString release];
    }
    
    return results;
}

+ (OFCompletionMatch *)bestMatchFromMatches:(NSArray<OFCompletionMatch *> *)matches;
{
    OFCompletionMatch *bestMatch = nil;
    
    for (OFCompletionMatch *match in matches) {
        if (bestMatch == nil || [match score] > [bestMatch score]) {
            bestMatch = match;
        }
    }

    return bestMatch;
}

const OFCompletionMatchComparator OFDefaultCompletionMatchComparator = ^(OFCompletionMatch *match1, OFCompletionMatch *match2){
    NSInteger score1 = match1.score;
    NSInteger score2 = match2.score;

    if (score1 > score2) {
        return NSOrderedAscending;
    } else if (score1 < score2) {
        return NSOrderedDescending;
    }

    return [match1.string localizedStandardCompare:match2.string];
};

+ (NSArray<OFCompletionMatch *> *)matchesForFilter:(NSString *)filter inArray:(NSArray<NSString *> *)candidates options:(OFCompletionMatchingOptions)options shouldSort:(BOOL)shouldSort shouldUnique:(BOOL)shouldUnique;
{
    NSMutableArray<OFCompletionMatch *> *results = [NSMutableArray array];
    NSMutableArray<OFCompletionMatch *> *matches = shouldUnique ? [[NSMutableArray alloc] init] : nil;
    NSString *canonicalFilter = [self _preretainedCanonicalStringForString:filter options:options];

    for (NSString *candidate in candidates) {
        if (shouldUnique) {
            [self _addMatchesForPreCanonicalizedFilter:canonicalFilter inString:candidate options:options toResults:matches];
            OFCompletionMatch *bestMatch = [self bestMatchFromMatches:matches];
            if (bestMatch != nil) {
                [results addObject:bestMatch];
            }
	    [matches removeAllObjects];
        } else {
            [self addMatchesForFilter:filter inString:candidate options:options toResults:results];
        }
    }

    [matches release];
    [canonicalFilter release];
    
    if (shouldSort) {
        [results sortUsingComparator:OFDefaultCompletionMatchComparator];
    }

    return results;
}

+ (NSArray<OFCompletionMatch *> *)matchesForFilter:(NSString *)filter inString:(NSString *)name options:(OFCompletionMatchingOptions)options;
{
    NSMutableArray<OFCompletionMatch *> *results = [NSMutableArray array];
    [self addMatchesForFilter:filter inString:name options:options toResults:results];
    return results;
}

+ (void)addMatchesForFilter:(NSString *)filter inString:(NSString *)name options:(OFCompletionMatchingOptions)options toResults:(NSMutableArray<OFCompletionMatch *> *)results;
{
    NSString *canonicalizedFilter = [self _preretainedCanonicalStringForString:filter options:options];
    
    [self _addMatchesForPreCanonicalizedFilter:canonicalizedFilter inString:name options:options toResults:results];
    
    [canonicalizedFilter release];
}

+ (void)_addMatchesForPreCanonicalizedFilter:(NSString *)filter inString:(NSString *)name options:(OFCompletionMatchingOptions)options toResults:(NSMutableArray<OFCompletionMatch *> *)results;
{
    NSUInteger filterLength = filter.length;
    NSUInteger lastMatchIndexes[filterLength];
    NSString *normalizedName = [self _preretainedCanonicalStringForString:name options:0]; // just normalization
    NSString *canonicalName = [self _preretainedCanonicalStringForString:name options:options];
    NSUInteger canonicalNameLength = canonicalName.length;

    if (calculateIndexesOfLastMatchesInName(0, filterLength, filter, 0, canonicalNameLength, canonicalName, lastMatchIndexes)) {
	OFCompletionMatch *newMatch = [[OFCompletionMatch alloc] initWithString:normalizedName];
        filterIntoResults(0, filterLength, filter, lastMatchIndexes, YES, 0, 0, canonicalNameLength, canonicalName, normalizedName, newMatch, results);
	[newMatch release];
    }
    
    [normalizedName release];
    [canonicalName release];
}

+ (OFCompletionMatch *)completionMatchWithString:(NSString *)string;
{
    return [[[self alloc] initWithString:string] autorelease];
}

- (id)initWithString:(NSString *)string wordIndexPath:(OFIndexPath *)wordIndexPath characterIndexPath:(OFIndexPath *)characterIndexPath score:(NSInteger)score;
{
    self = [super init];

    _string = [string retain];
    _wordIndexPath = [wordIndexPath retain];
    _characterIndexPath = [characterIndexPath retain];
    _score = score;
    return self;
}

- (id)initWithString:(NSString *)string;
{
    OFIndexPath *emptyPath = [OFIndexPath emptyIndexPath];
    return [self initWithString:string wordIndexPath:emptyPath characterIndexPath:emptyPath score:0];
}

- (id)init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (void)dealloc;
{
    [_string release];
    [_wordIndexPath release];
    [_characterIndexPath release];

    [super dealloc];
}

- (OFCompletionMatch *)_preretainedSequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(NSInteger)score;
{
    return [[[self class] alloc] initWithString:_string wordIndexPath:[_wordIndexPath indexPathByAddingIndex:wordIndex] characterIndexPath:[_characterIndexPath indexPathByAddingIndex:characterIndex] score:_score + score];
}

- (OFCompletionMatch *)sequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(NSInteger)score;
{
    return [[[[self class] alloc] initWithString:_string wordIndexPath:[_wordIndexPath indexPathByAddingIndex:wordIndex] characterIndexPath:[_characterIndexPath indexPathByAddingIndex:characterIndex] score:_score + score] autorelease];
}

- (OFCompletionMatch *)_preretainedSequenceByAddingScore:(NSInteger)score;
{
    return [[[self class] alloc] initWithString:_string wordIndexPath:_wordIndexPath characterIndexPath:_characterIndexPath score:_score + score];
}

- (OFCompletionMatch *)sequenceByAddingScore:(NSInteger)score;
{
    return [[[[self class] alloc] initWithString:_string wordIndexPath:_wordIndexPath characterIndexPath:_characterIndexPath score:_score + score] autorelease];
}

- (NSUInteger)lastWordIndex;
{
    NSUInteger indexPathLength = [_wordIndexPath length];
    OBASSERT(indexPathLength > 0);
    return [_wordIndexPath indexAtPosition:indexPathLength - 1];
}

- (NSUInteger)lastCharacterIndex;
{
    NSUInteger indexPathLength = [_characterIndexPath length];
    OBASSERT(indexPathLength > 0);
    return [_characterIndexPath indexAtPosition:indexPathLength - 1];
}

- (NSAttributedString *)attributedStringWithTextAttributes:(NSDictionary *)textAttributes matchAttributes:(NSDictionary *)matchAttributes;
{
    OBPRECONDITION(textAttributes != NULL);
    OBPRECONDITION(matchAttributes != NULL);
    
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:self.string attributes:textAttributes];
    
    [_characterIndexPath enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        [attributedString addAttributes:matchAttributes range:range];
    }];
    
    return [attributedString autorelease];
}

- (NSString *)stringBySurroundingMatchRangesWithPrefix:(NSString *)prefix suffix:(NSString *)suffix transformSubstrings:(OFCompletionMatchTransformSubstring)transformSubstrings;
{
    if (transformSubstrings == NULL) {
        transformSubstrings = ^(NSString *string) {
            return string;
        };
    }
    
    NSUInteger indexCount = [_characterIndexPath length];
    if (indexCount == 0) {
        return transformSubstrings(_string);
    }
    
    BOOL inHighlight = NO;
    NSUInteger *indexes = malloc(sizeof(NSUInteger) * (indexCount + 1));
    [_characterIndexPath getIndexes:indexes];
    indexes[indexCount] = NSNotFound;
    NSUInteger indexIndex = 0, nextHighlightIndex = indexes[indexIndex++];
    
    NSMutableString *resultString = [NSMutableString string];
    NSUInteger stringIndex = 0, stringLength = [_string length];

    while (stringIndex < stringLength) {
        NSRange currentCharacterRange = [_string rangeOfComposedCharacterSequenceAtIndex:stringIndex];
        NSString *currentCharacterString = [_string substringWithRange:currentCharacterRange];
        if (stringIndex == nextHighlightIndex) {
            nextHighlightIndex = indexes[indexIndex++];
            if (!inHighlight) {
                [resultString appendString:prefix];
                inHighlight = YES;
            }
        } else {
            if (inHighlight) {
                [resultString appendString:suffix];
                inHighlight = NO;
            }
        }
        [resultString appendString:transformSubstrings(currentCharacterString)];
        stringIndex = NSMaxRange(currentCharacterRange);
    }

    if (inHighlight) {
        [resultString appendString:suffix];
    }

    free(indexes);

    return resultString;
}

- (NSString *)xmlStringWithMatchingSpanClass:(NSString *)className;
{
    OFCompletionMatchTransformSubstring transform = ^(NSString *string) {
        return [OFXMLCreateStringWithEntityReferencesInCFEncoding(string, OFXMLBasicEntityMask, nil/*newlineReplacement*/, kCFStringEncodingUTF8) autorelease];
    };

    return [self stringBySurroundingMatchRangesWithPrefix:[NSString stringWithFormat:@"<span class=\"%@\">", className] suffix:@"</span>" transformSubstrings:transform];
}
    
- (NSString *)debugString;
{
    return [self stringBySurroundingMatchRangesWithPrefix:@"[" suffix:@"]" transformSubstrings:NULL];
}

- (NSDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];

    @try {
        [debugDictionary setObject:[self debugString] forKey:@"debugString" defaultObject:nil];
    } @catch (NSException *exception) {
        NSLog(@"Exception caught in %s: %@", __func__, exception);
    }

    [debugDictionary setObject:_string forKey:@"_string" defaultObject:nil];
    [debugDictionary setObject:_wordIndexPath forKey:@"_wordIndexPath" defaultObject:nil];
    [debugDictionary setObject:_characterIndexPath forKey:@"_characterIndexPath" defaultObject:nil];
    [debugDictionary setObject:[NSNumber numberWithInteger:_score] forKey:@"_score"];

    return debugDictionary;
}

static BOOL calculateIndexesOfLastMatchesInName(
                NSUInteger filterStartIndex,
                NSUInteger filterLength,
                NSString *filter, // Assumed to be in canonical form, and with transforms appropriate for the current options already to be applied to it
                NSUInteger nameCharacterStartIndex,
                NSUInteger nameLength,
                NSString *name, // Assumed to be in canonical form, and with the transforms appropriate for the current options already to be applied to it
                NSUInteger *lastMatchIndexes)
{
    NSUInteger filterIndex = filterLength;
    NSUInteger nameCharacterIndex = nameLength;

checkFilter:
    if (filterIndex == filterStartIndex) {
        // We've matched all the characters in the filter
        return YES;
    }

    unichar filterChar = [filter characterAtIndex:--filterIndex];
    OBASSERT(filterIndex >= filterStartIndex);
    OBASSERT(nameCharacterIndex >= nameCharacterStartIndex);
    while (filterIndex - filterStartIndex < nameCharacterIndex - nameCharacterStartIndex) { // We're not trying to find more characters than we have left
        unichar nameChar = [name characterAtIndex:--nameCharacterIndex];
        if (nameChar == filterChar) {
            lastMatchIndexes[filterIndex] = nameCharacterIndex;
            goto checkFilter;
        }
        OBASSERT(nameCharacterIndex >= nameCharacterStartIndex);
    }

    // There aren't enough characters left in the name to match the remaining characters in the filter
    return NO;
}

#define ALTERNATE_RESULT_LIMIT 100 // Don't look for more than 100 possible scores for any particular name

static void filterIntoResults(
                NSUInteger filterIndex,
                NSUInteger filterLength,
                NSString *filter, // Assumed to be in canonical form, and with transforms appropriate for the current options already to be applied to it
                NSUInteger *lastMatchIndexes,
                BOOL wasInWhitespace,
                NSUInteger nameWordIndex,
                NSUInteger nameCharacterIndex,
                NSUInteger nameLength,
                NSString *nameLowercase, // Assumed to be in canonical form, and with the transforms appropriate for the current options already to be applied to it
                NSString *nameOriginalCase,
                OFCompletionMatch *completionMatch,
                NSMutableArray<OFCompletionMatch *> *results)
{
    if (filterIndex == filterLength) {
        // We've matched all the characters in the filter
        NSInteger bonusScore = 0;
        if (nameCharacterIndex == nameLength) {
            bonusScore += OFCompletionMatchScoreePhraseEnd;
        }

        if (filterLength == nameLength) {
            bonusScore += OFCompletionMatchScoreFullMatch;
        }

	OFCompletionMatch *newMatch = [completionMatch _preretainedSequenceByAddingScore:bonusScore];
        [results addObject:newMatch];
	[newMatch release];
        return;
    }

    if (nameCharacterIndex == nameLength) {
        // No more characters to search
        return;
    }

    unichar nameChar = [nameLowercase characterAtIndex:nameCharacterIndex];
    unichar filterChar = [filter characterAtIndex:filterIndex];
    BOOL nowInWhitespace = OFCharacterSetHasMember(_WhitespaceOFCharacterSet, nameChar);
    NSUInteger lastMatchIndex = lastMatchIndexes[filterIndex];

    @autoreleasepool {
        while (nameCharacterIndex <= lastMatchIndex && [results count] < ALTERNATE_RESULT_LIMIT) {
            BOOL wordStart = wasInWhitespace && !nowInWhitespace;
            if (wordStart) {
                nameWordIndex++;
            }

            if (nameChar == filterChar) {
                NSInteger score = 0;
                if (nameCharacterIndex == 0) {
                    score += OFCompletionMatchScorePhraseStart;
                } else {
                    OBASSERT(nameCharacterIndex > 0); // These tests rely on looking at previous characters
                    if (filterIndex > 0) {
                        NSUInteger lastCharacterIndex = [completionMatch lastCharacterIndex];
                        if (lastCharacterIndex + 1 == nameCharacterIndex) {
                            score += OFCompletionMatchScoreConsecutiveCharacter;
                        }

                        if (wordStart) {
                            NSUInteger lastWordIndex = [completionMatch lastWordIndex];
                            if (lastWordIndex + 1 == nameWordIndex) {
                                score += OFCompletionMatchScoreConsecutiveWord;
                            } else {
                                score--; // Skipped a word
                            }
                        }
                    }

                    if (wordStart) {
                        score += OFCompletionMatchScoreWordStart;
                    }
                }

                if (OFCharacterSetHasMember(_UppercaseLetterOFCharacterSet, [nameOriginalCase characterAtIndex:nameCharacterIndex])) {
                    score += OFCompletionMatchScoreCapitalLetter;
                }
                    
                OFCompletionMatch *newMatch = [completionMatch _preretainedSequenceByAddingWordIndex:nameWordIndex characterIndex:nameCharacterIndex withScore:score];
                filterIntoResults(filterIndex + 1, filterLength, filter, lastMatchIndexes, nowInWhitespace, nameWordIndex, nameCharacterIndex + 1, nameLength, nameLowercase, nameOriginalCase, newMatch, results);
                [newMatch release];
            }
            
            nameCharacterIndex++;

            if (nameCharacterIndex < nameLength) {
                nameChar = [nameLowercase characterAtIndex:nameCharacterIndex];
                wasInWhitespace = nowInWhitespace;
                nowInWhitespace = OFCharacterSetHasMember(_WhitespaceOFCharacterSet, nameChar);
            }
        }
    }
}

@end
