// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OFTrieBucket, OFTrieNode;

@interface OFTrie : OFObject
{
    OFTrieNode *head;
    BOOL caseSensitive;
}

- initCaseSensitive:(BOOL)shouldBeCaseSensitive;
- (NSEnumerator *)objectEnumerator;
- (BOOL)isCaseSensitive;
- (void)addBucket:(OFTrieBucket *)bucket forString:(NSString *)aString;
- (OFTrieBucket *)bucketForString:(NSString *)aString;
- (OFTrieNode *)headNode;

@end
