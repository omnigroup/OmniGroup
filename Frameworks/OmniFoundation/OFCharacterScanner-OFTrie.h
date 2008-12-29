// Copyright 1997-2005,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/branches/Staff/bungi/OmniFocus-20080310-iPhoneFactor/OmniGroup/Frameworks/OmniFoundation/OFCharacterScanner.h 98499 2008-03-11 03:23:38Z bungi $

#import <OmniFoundation/OFCharacterScanner.h>

@class OFTrie, OFTrieBucket;

@interface OFCharacterScanner (OFTrie)
- (OFTrieBucket *)readLongestTrieElement:(OFTrie *)trie;
- (OFTrieBucket *)readLongestTrieElement:(OFTrie *)trie delimiterOFCharacterSet:(OFCharacterSet *)delimiterOFCharacterSet;
- (OFTrieBucket *)readShortestTrieElement:(OFTrie *)trie;
@end
