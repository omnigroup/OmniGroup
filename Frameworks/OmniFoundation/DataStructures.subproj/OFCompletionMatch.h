// Copyright 2007-2017 Omni Development, Inc. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

typedef NSString * _Nonnull (^OFCompletionMatchTransformSubstring)(NSString *string);

@interface OFCompletionMatch : NSObject

+ (nullable OFCompletionMatch *)bestMatchFromMatches:(NSArray<OFCompletionMatch *> *)matches;
+ (NSArray<OFCompletionMatch *> *)matchesForFilter:(NSString *)filter inArray:(NSArray<NSString *> *)candidates shouldSort:(BOOL)shouldSort shouldUnique:(BOOL)shouldUnique;
+ (NSArray<OFCompletionMatch *> *)matchesForFilter:(NSString *)filter inString:(NSString *)name;
+ (void)addMatchesForFilter:(NSString *)filter inString:(NSString *)name toResults:(NSMutableArray *)results;
+ (OFCompletionMatch *)completionMatchWithString:(NSString *)string;

- (id)init NS_UNAVAILABLE;
- (id)initWithString:(NSString *)string wordIndexPath:(OFIndexPath *)wordIndexPath characterIndexPath:(OFIndexPath *)characterIndexPath score:(NSInteger)score NS_DESIGNATED_INITIALIZER;

- (OFCompletionMatch *)sequenceByAddingWordIndex:(NSUInteger)wordIndex characterIndex:(NSUInteger)characterIndex withScore:(NSInteger)score;
- (OFCompletionMatch *)sequenceByAddingScore:(NSInteger)score;

@property (nonatomic, readonly) NSString *string;
@property (nonatomic, readonly) OFIndexPath *wordIndexPath;
@property (nonatomic, readonly) OFIndexPath *characterIndexPath;
@property (nonatomic, readonly) NSInteger score;

@property (nonatomic, readonly) NSUInteger lastWordIndex;
@property (nonatomic, readonly) NSUInteger lastCharacterIndex;

- (NSAttributedString *)attributedStringWithTextAttributes:(NSDictionary *)textAttributes matchAttributes:(NSDictionary *)matchAttributes;

- (NSString *)stringBySurroundingMatchRangesWithPrefix:(NSString *)prefix suffix:(NSString *)suffix transformSubstrings:(nullable OFCompletionMatchTransformSubstring)transformSubstrings;
- (NSString *)xmlStringWithMatchingSpanClass:(NSString *)className;
- (NSString *)debugString;

@end

NS_ASSUME_NONNULL_END
