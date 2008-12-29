// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>

#import <Foundation/NSString.h> // For unichar

@interface OFTrieNode : OBObject
{
@public
    unsigned int childCount;
    unichar *characters;
    id *children;
}

- (void)addChild:(id)aChild withCharacter:(unichar)aCharacter;

@end

static inline unsigned int
trieFindIndex(OFTrieNode *node, unichar aCharacter)
{
    unsigned int low = 0;
    unsigned int range = 1;
    unsigned int test = 0;

    while (node->childCount >= range) // range is the lowest power of 2 > childCount
        range <<= 1;

    while (range) {
        test = low + (range >>= 1);
        if (test >= node->childCount)
            continue;
        if (node->characters[test] < aCharacter)
            low = test+1;
    }
    return low;
}

static inline id
trieFindChild(OFTrieNode *node, unichar aCharacter)
{
    unsigned int foundIndex;
    
    foundIndex = trieFindIndex(node, aCharacter);
    if (foundIndex < node->childCount && node->characters[foundIndex] == aCharacter)
	return node->children[foundIndex];
    else
	return nil;
}
