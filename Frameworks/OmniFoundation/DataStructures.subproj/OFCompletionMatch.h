// Copyright 2007-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSArray;
@class NSAttributedString;
@class NSString;
@class OFIndexPath;

typedef NSString * (^OFCompletionMatchTransformSubstring)(NSString *string);

@interface OFCompletionMatch : NSObject

+ (OFCompletionMatch *)bestMatchFromMatches:(NSArray *)matches;
+ (NSArray *)matchesForFilter:(NSString *)filter inArray:(NSArray *)candidates shouldSort:(BOOL)shouldSort shouldUnique:(BOOL)shouldUnique;
+ (NSArray *)matchesForFilter:(NSString *)filter inString:(NSString *)name;
+ (void)addMatchesForFilter:(NSString *)filter inString:(NSString *)name toResults:(NSMutableArray *)results;
+ (OFCompletionMatch *)completionMatchWithString:(NSString *)string;

- (id)initWithString:(NSString *)string wordIndexPath:(OFIndexPath *)wordIndexPath characterIndexPath:(OFIndexPath *)characterIndexPath score:(NSInteger)score;

- (OFCompletionMatch *)sequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(NSInteger)score;
- (OFCompletionMatch *)sequenceByAddingScore:(NSInteger)score;

@property (nonatomic, readonly) NSString *string;
@property (nonatomic, readonly) OFIndexPath *wordIndexPath;
@property (nonatomic, readonly) OFIndexPath *characterIndexPath;
@property (nonatomic, readonly) NSInteger score;

@property (nonatomic, readonly) NSUInteger lastWordIndex;
@property (nonatomic, readonly) NSUInteger lastCharacterIndex;

- (NSAttributedString *)attributedStringWithTextAttributes:(NSDictionary *)textAttributes matchAttributes:(NSDictionary *)matchAttributes;

- (NSString *)stringBySurroundingMatchRangesWithPrefix:(NSString *)prefix suffix:(NSString *)suffix transformSubstrings:(OFCompletionMatchTransformSubstring)transformSubstrings;
- (NSString *)xmlStringWithMatchingSpanClass:(NSString *)className;
- (NSString *)debugString;

@end
