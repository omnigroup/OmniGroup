// Copyright 2007-2017 Omni Development, Inc. All rights reserved.
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

@interface OFCompletionMatch ()

- (id)initWithString:(NSString *)string;
- (OFCompletionMatch *)_preretainedSequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(NSInteger)score NS_RETURNS_RETAINED;
- (OFCompletionMatch *)_preretainedSequenceByAddingScore:(NSInteger)score NS_RETURNS_RETAINED;

@end

@implementation OFCompletionMatch

static BOOL calculateIndexesOfLastMatchesInName(
                NSUInteger filterStartIndex,
                NSUInteger filterLength,
                NSString *filter,
                NSUInteger nameCharacterStartIndex,
                NSUInteger nameLength,
                NSString *nameLowercase,
                NSUInteger *lastMatchIndexes);

static void filterIntoResults(
                NSUInteger filterIndex,
                NSUInteger filterLength,
                NSString *filter,
                NSUInteger *lastMatchIndexes,
                BOOL wasInWhitespace,
                NSUInteger nameWordIndex,
                NSUInteger nameCharacterIndex,
                NSUInteger nameLength,
                NSString *nameLowercase,
                NSString *nameOriginalCase,
                OFCompletionMatch *completionMatch,
                NSMutableArray *results);

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

+ (NSArray<OFCompletionMatch *> *)matchesForFilter:(NSString *)filter inArray:(NSArray<NSString *> *)candidates shouldSort:(BOOL)shouldSort shouldUnique:(BOOL)shouldUnique;
{
    NSMutableArray *results = [NSMutableArray array];
    NSMutableArray *matches = shouldUnique ? [[NSMutableArray alloc] init] : nil;

    for (NSString *candidate in candidates) {
        if (shouldUnique) {
	    [self addMatchesForFilter:filter inString:candidate toResults:matches];
            OFCompletionMatch *bestMatch = [self bestMatchFromMatches:matches];
            if (bestMatch != nil) {
                [results addObject:bestMatch];
            }
	    [matches removeAllObjects];
        } else {
            [self addMatchesForFilter:filter inString:candidate toResults:results];
        }
    }

    [matches release];
    
    if (shouldSort) {
        [results sortUsingComparator:^NSComparisonResult(OFCompletionMatch *match1, OFCompletionMatch *match2) {
            NSInteger score1 = match1.score;
            NSInteger score2 = match2.score;

            if (score1 > score2) {
                return NSOrderedAscending;
            } else if (score1 < score2) {
                return NSOrderedDescending;
            }
            
            return NSOrderedSame;
        }];
    }

    return results;
}

+ (NSArray<OFCompletionMatch *> *)matchesForFilter:(NSString *)filter inString:(NSString *)name;
{
    NSMutableArray *results = [NSMutableArray array];
    [self addMatchesForFilter:filter inString:name toResults:results];
    return results;
}

+ (void)addMatchesForFilter:(NSString *)filter inString:(NSString *)name toResults:(NSMutableArray *)results;
{
    NSUInteger filterLength = [filter length];
    NSUInteger lastMatchIndexes[filterLength];
    NSUInteger nameLength = [name length];
    NSString *nameLowercase = [name lowercaseString];
    if (calculateIndexesOfLastMatchesInName(0, filterLength, filter, 0, nameLength, nameLowercase, lastMatchIndexes)) {
	OFCompletionMatch *newMatch = [[OFCompletionMatch alloc] initWithString:name];
        filterIntoResults(0, filterLength, filter, lastMatchIndexes, YES, 0, 0, nameLength, nameLowercase, name, newMatch, results);
	[newMatch release];
    }
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
    
    [_characterIndexPath enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        [attributedString addAttributes:matchAttributes range:NSMakeRange(index, 1)];
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
    
    for (stringIndex = 0; stringIndex < stringLength; stringIndex++) {
        NSString *currentCharacterString = [_string substringWithRange:NSMakeRange(stringIndex, 1)];
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
        return [OFXMLCreateStringWithEntityReferencesInCFEncoding(string, OFXMLBasicEntityMask, nil/*newlineReplacement*/, NSUTF8StringEncoding) autorelease];
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
                NSString *filter,
                NSUInteger nameCharacterStartIndex,
                NSUInteger nameLength,
                NSString *nameLowercase,
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
        unichar nameChar = [nameLowercase characterAtIndex:--nameCharacterIndex];
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
                NSString *filter,
                NSUInteger *lastMatchIndexes,
                BOOL wasInWhitespace,
                NSUInteger nameWordIndex,
                NSUInteger nameCharacterIndex,
                NSUInteger nameLength,
                NSString *nameLowercase,
                NSString *nameOriginalCase,
                OFCompletionMatch *completionMatch,
                NSMutableArray *results)
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
