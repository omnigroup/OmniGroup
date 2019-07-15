// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OFTrieBucket, OFTrieNode;

@interface OFTrie : NSObject

- initCaseSensitive:(BOOL)shouldBeCaseSensitive;

- (NSEnumerator *)objectEnumerator;

@property(nonatomic,readonly,getter = isCaseSensitive) BOOL caseSensitive;

- (void)addBucket:(OFTrieBucket *)bucket forString:(NSString *)aString;
- (OFTrieBucket *)bucketForString:(NSString *)aString;

@property(nonatomic,readonly) OFTrieNode *headNode;

@end
