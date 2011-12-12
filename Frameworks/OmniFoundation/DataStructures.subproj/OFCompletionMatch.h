// Copyright 2007-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray, NSString, NSMutableAttributedString;
@class OFIndexPath;

typedef NSString *(*OFCompletionMatchTransformSubstring)(NSString *substring);

@interface OFCompletionMatch : OFObject
{
    NSString *_string;
    OFIndexPath *_wordIndexPath;
    OFIndexPath *_characterIndexPath;
    int _score;
}

+ (OFCompletionMatch *)bestOfMatches:(NSArray *)matches;
+ (NSArray *)matchesForFilter:(NSString *)filter inArray:(NSArray *)candidates shouldSort:(BOOL)shouldSort shouldUnique:(BOOL)shouldUnique;
+ (NSArray *)matchesForFilter:(NSString *)filter inString:(NSString *)name;
+ (void)addMatchesForFilter:(NSString *)filter inString:(NSString *)name toResults:(NSMutableArray *)results;
+ (OFCompletionMatch *)completionMatchWithString:(NSString *)aString;

- (id)initWithString:(NSString *)aString wordIndexPath:(OFIndexPath *)anIndexPath characterIndexPath:(OFIndexPath *)anIndexPath score:(int)aScore;
- (OFCompletionMatch *)sequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(int)aScore;
- (OFCompletionMatch *)sequenceByAddingScore:(int)aScore;

- (NSString *)string;
- (OFIndexPath *)wordIndexPath;
- (OFIndexPath *)characterIndexPath;
- (int)score;

- (NSUInteger)lastWordIndex;
- (NSUInteger)lastCharacterIndex;

- (void)setAttributes:(NSDictionary *)attributes onAttributedString:(NSMutableAttributedString *)attributedString startingAtIndex:(int)start;

- (NSString *)stringBySurroundingMatchRangesWithPrefix:(NSString *)prefix suffix:(NSString *)suffix transformSubstrings:(OFCompletionMatchTransformSubstring)transformSubstrings;
- (NSString *)xmlStringWithMatchingSpanClass:(NSString *)className;
- (NSString *)debugString;

@end
