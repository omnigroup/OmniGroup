// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniBase/macros.h>
#import <Foundation/NSString.h> // For unichar

@interface OFTrieNode : NSObject

- (void)addChild:(id)aChild withCharacter:(unichar)aCharacter;

@end

extern NSUInteger trieFindIndex(OFTrieNode *node, unichar aCharacter) OB_HIDDEN;
extern NSUInteger trieChildCount(OFTrieNode *node) OB_HIDDEN;
extern id trieChildAtIndex(OFTrieNode *node, NSUInteger childIndex) OB_HIDDEN;
extern id trieFindChild(OFTrieNode *node, unichar aCharacter) OB_HIDDEN;
extern const unichar *trieCharacters(OFTrieNode *node) OB_HIDDEN;
