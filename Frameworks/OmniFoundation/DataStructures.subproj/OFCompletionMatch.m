// Copyright 2007-2012 Omni Development, Inc. All rights reserved.
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

@interface OFCompletionMatch (/*Private*/)
- (id)initWithString:(NSString *)aString;
- (OFCompletionMatch *)_preretainedSequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(int)aScore NS_RETURNS_RETAINED;
- (OFCompletionMatch *)_preretainedSequenceByAddingScore:(int)aScore NS_RETURNS_RETAINED;
@end

@implementation OFCompletionMatch

static void filterScoreInit(void);

static BOOL calculateIndexesOfLastMatchesInName(
    NSUInteger filterStartIndex,
    NSUInteger filterLength,
    NSString *filter,
    NSUInteger nameCharacterStartIndex,
    NSUInteger nameLength,
    NSString *nameLowercase,
    NSUInteger *lastMatchIndexes);

static void filterIntoResults(NSUInteger filterIndex,
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

+ (OFCompletionMatch *)bestOfMatches:(NSArray *)matches;
{
    OFCompletionMatch *bestMatch = nil;
    NSUInteger matchIndex, matchCount = [matches count];
    for (matchIndex = 0; matchIndex < matchCount; matchIndex++) {
        OFCompletionMatch *match = [matches objectAtIndex:matchIndex];
        if (bestMatch == nil || [match score] > [bestMatch score])
            bestMatch = match;
    }
    return bestMatch;
}

static NSInteger sortByScore(id match1, id match2, void *context)
{
    int score1 = [match1 score];
    int score2 = [match2 score];
    if (score1 > score2)
	return NSOrderedAscending;
    else if (score1 < score2)
	return NSOrderedDescending;
    else
        return NSOrderedSame;
}

+ (NSArray *)matchesForFilter:(NSString *)filter inArray:(NSArray *)candidates shouldSort:(BOOL)shouldSort shouldUnique:(BOOL)shouldUnique;
{
    NSMutableArray *results = [NSMutableArray array];
    NSMutableArray *matches = shouldUnique ? [[NSMutableArray alloc] init] : nil;
    NSUInteger candidateIndex, candidateCount = [candidates count];
    for (candidateIndex = 0; candidateIndex < candidateCount; candidateIndex++) {
        NSString *candidate = [candidates objectAtIndex:candidateIndex];
        if (shouldUnique) {
	    [self addMatchesForFilter:filter inString:candidate toResults:matches];
            OFCompletionMatch *bestMatch = [self bestOfMatches:matches];
            if (bestMatch != nil)
                [results addObject:bestMatch];
	    [matches removeAllObjects];
        } else {
            [self addMatchesForFilter:filter inString:candidate toResults:results];
        }
    }
    [matches release];
    
    if (shouldSort)
        [results sortUsingFunction:sortByScore context:NULL];

    return results;
}

+ (NSArray *)matchesForFilter:(NSString *)filter inString:(NSString *)name;
{
    NSMutableArray *results = [NSMutableArray array];
    [self addMatchesForFilter:filter inString:name toResults:results];
    return results;
}

+ (void)addMatchesForFilter:(NSString *)filter inString:(NSString *)name toResults:(NSMutableArray *)results;
{
    filterScoreInit();
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

+ (OFCompletionMatch *)completionMatchWithString:(NSString *)aString;
{
    return [[[self alloc] initWithString:aString] autorelease];
}

- (id)initWithString:(NSString *)aString wordIndexPath:(OFIndexPath *)wordIndexPath characterIndexPath:(OFIndexPath *)characterIndexPath score:(int)aScore;
{
    _string = [aString retain];
    _wordIndexPath = [wordIndexPath retain];
    _characterIndexPath = [characterIndexPath retain];
    _score = aScore;
    return self;
}

- (id)initWithString:(NSString *)aString;
{
    OFIndexPath *emptyPath = [OFIndexPath emptyIndexPath];
    return [self initWithString:aString wordIndexPath:emptyPath characterIndexPath:emptyPath score:0];
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

- (OFCompletionMatch *)_preretainedSequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(int)aScore;
{
    return [[isa alloc] initWithString:_string wordIndexPath:[_wordIndexPath indexPathByAddingIndex:wordIndex] characterIndexPath:[_characterIndexPath indexPathByAddingIndex:characterIndex] score:_score + aScore];
}

- (OFCompletionMatch *)sequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(int)aScore;
{
    return [[[isa alloc] initWithString:_string wordIndexPath:[_wordIndexPath indexPathByAddingIndex:wordIndex] characterIndexPath:[_characterIndexPath indexPathByAddingIndex:characterIndex] score:_score + aScore] autorelease];
}

- (OFCompletionMatch *)_preretainedSequenceByAddingScore:(int)aScore;
{
    return [[isa alloc] initWithString:_string wordIndexPath:_wordIndexPath characterIndexPath:_characterIndexPath score:_score + aScore];
}

- (OFCompletionMatch *)sequenceByAddingScore:(int)aScore;
{
    return [[[isa alloc] initWithString:_string wordIndexPath:_wordIndexPath characterIndexPath:_characterIndexPath score:_score + aScore] autorelease];
}

- (NSString *)string;
{
    return _string;
}

- (OFIndexPath *)wordIndexPath;
{
    return _wordIndexPath;
}

- (OFIndexPath *)characterIndexPath;
{
    return _characterIndexPath;
}

- (int)score;
{
    return _score;
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

- (void)setAttributes:(NSDictionary *)attributes onAttributedString:(NSMutableAttributedString *)attributedString startingAtIndex:(int)start;
{
    NSUInteger indexIndex, indexCount = [_characterIndexPath length];
    NSUInteger *indexes = malloc(sizeof(NSUInteger) * indexCount);
    [_characterIndexPath getIndexes:indexes];
    for (indexIndex = 0; indexIndex < indexCount; indexIndex++)
        [attributedString setAttributes:attributes range:NSMakeRange(indexes[indexIndex] + start, 1)];
    free(indexes);
}

static NSString *_quoteNull(NSString *string)
{
    return string;
}

- (NSString *)stringBySurroundingMatchRangesWithPrefix:(NSString *)prefix suffix:(NSString *)suffix transformSubstrings:(OFCompletionMatchTransformSubstring)transformSubstrings;
{
    if (transformSubstrings == NULL)
        transformSubstrings = _quoteNull;
    
    NSUInteger indexCount = [_characterIndexPath length];
    if (indexCount == 0)
        return transformSubstrings(_string);
    
    BOOL inHighlight = NO;
    NSUInteger *indexes = malloc(sizeof(NSUInteger) * (indexCount + 1));
    [_characterIndexPath getIndexes:indexes];
    indexes[indexCount] = NSNotFound;
    NSUInteger indexIndex = 0, nextHighlightIndex = indexes[indexIndex++];
    
    NSMutableString *debugString = [NSMutableString string];
    NSUInteger stringIndex = 0, stringLength = [_string length];
    
    for (stringIndex = 0; stringIndex < stringLength; stringIndex++) {
        NSString *currentCharacterString = [_string substringWithRange:NSMakeRange(stringIndex, 1)];
        if (stringIndex == nextHighlightIndex) {
            nextHighlightIndex = indexes[indexIndex++];
            if (!inHighlight) {
                [debugString appendString:prefix];
                inHighlight = YES;
            }
        } else {
            if (inHighlight) {
                [debugString appendString:suffix];
                inHighlight = NO;
            }
        }
        [debugString appendString:transformSubstrings(currentCharacterString)];
    }
    if (inHighlight)
        [debugString appendString:suffix];
    free(indexes);
    return debugString;
}

static NSString *_quoteXML(NSString *string)
{
    return [OFXMLCreateStringWithEntityReferencesInCFEncoding(string, OFXMLBasicEntityMask, nil/*newlineReplacement*/, NSUTF8StringEncoding) autorelease];
}

- (NSString *)xmlStringWithMatchingSpanClass:(NSString *)className;
{
    return [self stringBySurroundingMatchRangesWithPrefix:[NSString stringWithFormat:@"<span class=\"%@\">", className] suffix:@"</span>" transformSubstrings:_quoteXML];
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
    }
    [debugDictionary setObject:_string forKey:@"_string" defaultObject:nil];
    [debugDictionary setObject:_wordIndexPath forKey:@"_wordIndexPath" defaultObject:nil];
    [debugDictionary setObject:_characterIndexPath forKey:@"_characterIndexPath" defaultObject:nil];
    [debugDictionary setObject:[NSNumber numberWithInt:_score] forKey:@"_score"];
    return debugDictionary;
}

static NSInteger CompletionScoreFullMatch, CompletionScorePhraseStart, CompletionScorePhraseEnd, CompletionScoreConsecutiveCharacter, CompletionScoreConsecutiveWord, CompletionScoreWordStart, CompletionScoreCapitalLetter;
static OFCharacterSet *whitespaceOFCharacterSet, *uppercaseLetterOFCharacterSet;

static void filterScoreInit(void)
{
    if (whitespaceOFCharacterSet != nil)
        return;

    whitespaceOFCharacterSet = [[OFCharacterSet whitespaceOFCharacterSet] retain];
    uppercaseLetterOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:[NSCharacterSet uppercaseLetterCharacterSet]];
    
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    CompletionScoreFullMatch = [preferences integerForKey:@"OFCompletionMatchScoreForFullMatch"];
    CompletionScorePhraseStart = [preferences integerForKey:@"OFCompletionMatchScoreForPhraseStart"];
    CompletionScorePhraseEnd = [preferences integerForKey:@"OFCompletionMatchScoreForPhraseEnd"];
    CompletionScoreConsecutiveCharacter = [preferences integerForKey:@"OFCompletionMatchScoreForConsecutiveCharacter"];
    CompletionScoreConsecutiveWord = [preferences integerForKey:@"OFCompletionMatchScoreForConsecutiveWord"];
    CompletionScoreWordStart = [preferences integerForKey:@"OFCompletionMatchScoreForWordStart"];
    CompletionScoreCapitalLetter = [preferences integerForKey:@"OFCompletionMatchScoreForCapitalLetter"];
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
    if (filterIndex == filterStartIndex)
        return YES; // We've matched all the characters in the filter

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

static void filterIntoResults(NSUInteger filterIndex,
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
        int bonusScore = 0;
        if (nameCharacterIndex == nameLength)
            bonusScore += CompletionScorePhraseEnd;

        if (filterLength == nameLength)
            bonusScore += CompletionScoreFullMatch;
	OFCompletionMatch *newMatch = [completionMatch _preretainedSequenceByAddingScore:bonusScore];
        [results addObject:newMatch];
	[newMatch release];
        return;
    }

    if (nameCharacterIndex == nameLength)
        return; // No more characters to search

    unichar nameChar = [nameLowercase characterAtIndex:nameCharacterIndex];
    unichar filterChar = [filter characterAtIndex:filterIndex];
    BOOL nowInWhitespace = OFCharacterSetHasMember(whitespaceOFCharacterSet, nameChar);
    NSUInteger lastMatchIndex = lastMatchIndexes[filterIndex];

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    while (nameCharacterIndex <= lastMatchIndex && [results count] < ALTERNATE_RESULT_LIMIT) {
        BOOL wordStart = wasInWhitespace && !nowInWhitespace;
        if (wordStart)
            nameWordIndex++;
        if (nameChar == filterChar) {
            int aScore = 0;
            if (nameCharacterIndex == 0) {
                aScore += CompletionScorePhraseStart;
            } else {
                OBASSERT(nameCharacterIndex > 0); // These tests rely on looking at previous characters
                if (filterIndex > 0) {
                    NSUInteger lastCharacterIndex = [completionMatch lastCharacterIndex];
                    if (lastCharacterIndex + 1 == nameCharacterIndex)
                        aScore += CompletionScoreConsecutiveCharacter;
                    if (wordStart) {
                        NSUInteger lastWordIndex = [completionMatch lastWordIndex];
                        if (lastWordIndex + 1 == nameWordIndex)
                            aScore += CompletionScoreConsecutiveWord;
                        else
                            aScore--; // Skipped a word
                    }
                }
                if (wordStart)
                    aScore += CompletionScoreWordStart;
            }
            if (OFCharacterSetHasMember(uppercaseLetterOFCharacterSet, [nameOriginalCase characterAtIndex:nameCharacterIndex]))
                aScore += CompletionScoreCapitalLetter;
	    
	    OFCompletionMatch *newMatch = [completionMatch _preretainedSequenceByAddingWordIndex:nameWordIndex characterIndex:nameCharacterIndex withScore:aScore];
            filterIntoResults(filterIndex + 1, filterLength, filter, lastMatchIndexes, nowInWhitespace, nameWordIndex, nameCharacterIndex + 1, nameLength, nameLowercase, nameOriginalCase, newMatch, results);
	    [newMatch release];
        }
        nameCharacterIndex++;
        if (nameCharacterIndex < nameLength) {
            nameChar = [nameLowercase characterAtIndex:nameCharacterIndex];
            wasInWhitespace = nowInWhitespace;
            nowInWhitespace = OFCharacterSetHasMember(whitespaceOFCharacterSet, nameChar);
        }
    }
    [pool drain];
}

@end
