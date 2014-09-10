// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFTrie.h>
#import <OmniFoundation/OFTrieBucket.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFTrieTests : OFTestCase
@end

@interface OFTestTrieBucket : OFTrieBucket
- initWithWord:(NSString *)word;
@property(nonatomic,readonly) NSString *word;
@end

@implementation OFTestTrieBucket

- initWithWord:(NSString *)word;
{
    if (!(self = [super init]))
        return nil;
    _word = [word copy];
    return self;
}

@end

@implementation OFTrieTests

static NSArray *Words = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSString *wordsString = [[NSString alloc] initWithContentsOfFile:@"/usr/share/dict/words" encoding:NSUTF8StringEncoding error:NULL];
    assert(wordsString);
    
    Words = [[wordsString componentsSeparatedByString:@"\n"] copy];
}

- (void)testAddPrefixAfterLongerWord;
{
    NSArray *words = @[@"ab", @"a"];

    OFTrie *trie = [[OFTrie alloc] initCaseSensitive:NO];
    for (NSString *word in words) {
        OFTestTrieBucket *bucket = [[OFTestTrieBucket alloc] initWithWord:word];
        [trie addBucket:bucket forString:word];
    }
    
    // Make sure we can look up every word and get back the expected result
    for (NSString *word in words) {
        OFTestTrieBucket *bucket = OB_CHECKED_CAST(OFTestTrieBucket, [trie bucketForString:word]);
        XCTAssertEqualObjects(bucket.word, word, @"bucket for the original word should be found");
    }
}

- (void)testRandomInsertOrder;
{
    NSMutableArray *insertWords = [Words mutableCopy];
    OFTrie *trie = [[OFTrie alloc] init];
    
    // Insert all the words in random order
    NSUInteger wordCount = [insertWords count];
    while (wordCount > 0) {
        NSUInteger wordIndex = OFRandomNext64() % wordCount;
        NSString *word = insertWords[wordIndex];
        
        OFTestTrieBucket *bucket = [[OFTestTrieBucket alloc] initWithWord:word];
        [trie addBucket:bucket forString:word];

        // Avoid shuffling ~half the array around each time.
        [insertWords replaceObjectAtIndex:wordIndex withObject:[insertWords lastObject]]; // No-op if we are using the last word
        [insertWords removeLastObject];
        
        wordCount--;
    }
    
    // Make sure we can look up every word and get back the expected result
    for (NSString *word in Words) {
        OFTestTrieBucket *bucket = OB_CHECKED_CAST(OFTestTrieBucket, [trie bucketForString:word]);
        XCTAssertEqualObjects(bucket.word, word, @"bucket for the original word should be found");
    }

    // Enumerate the results and make sure we get everything out.
    NSMutableSet *missingWords = [[NSMutableSet alloc] initWithArray:Words];
    XCTAssertEqual([Words count], [missingWords count], @"Make sure the source list of words didn't have duplicates");
    
    NSEnumerator *e = [trie objectEnumerator];
    OFTestTrieBucket *bucket;
    while ((bucket = [e nextObject])) {
        XCTAssertTrue([missingWords containsObject:bucket.word]);
        [missingWords removeObject:bucket.word];
    }
    XCTAssertEqual([missingWords count], 0ULL);
}

@end
