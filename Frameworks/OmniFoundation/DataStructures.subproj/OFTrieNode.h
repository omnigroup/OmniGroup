// Copyright 1997-2005, 2012, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniBase/macros.h>
#import <Foundation/NSString.h> // For unichar

@interface OFTrieNode : NSObject

- (void)addChild:(id)aChild withCharacter:(unichar)aCharacter;

@end

extern NSUInteger trieFindIndex(OFTrieNode *node, unichar aCharacter);
extern NSUInteger trieChildCount(OFTrieNode *node);
extern id trieChildAtIndex(OFTrieNode *node, NSUInteger childIndex);
extern id trieFindChild(OFTrieNode *node, unichar aCharacter);
extern const unichar *trieCharacters(OFTrieNode *node);
