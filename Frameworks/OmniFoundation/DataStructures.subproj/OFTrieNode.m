// Copyright 1997-2005, 2007-2008, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTrieNode.h>

#import <OmniFoundation/NSString-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFTrieNode
{
    NSUInteger childCount;
    unichar *characters;
    
    // We tell the compiler to not do any reference counting here and we do it manually. This is important so that we can realloc() the array and not get garbage in the new slots that would get sent -release when overwitten in ARC. Alternatively, we could have helpers that return a resized '__strong id *', but we'd then waste time zeroing out slots up front and we'd waste time doing pointless retain/release while inserting children into the middle of our children list.
    __unsafe_unretained id *_children;
}

// Init and dealloc

- (void)dealloc;
{
    for (NSUInteger childIndex = 0; childIndex < childCount; childIndex++) {
        OBStrongRelease(_children[childIndex]);
    }
    free(_children);

    free(characters);
    
    [super dealloc];
}

// API

- (void)addChild:(id)aChild withCharacter:(unichar)aCharacter;
{
    if (childCount == 0) {
        characters = (unichar *)malloc(sizeof(unichar));
        _children = (__unsafe_unretained id *)malloc(sizeof(*_children));
        *characters = aCharacter;
        
        OBStrongRetain(aChild);
        *_children = aChild;
        
        childCount = 1;
    } else {
        NSUInteger foundIndex = trieFindIndex(self, aCharacter);
        if (foundIndex < childCount && characters[foundIndex] == aCharacter) {
            id foundChild;

            foundChild = _children[foundIndex];
            if (foundChild == aChild)
                return; // Already have this child at this character
            [foundChild release];
        } else {
            characters = (unichar *)realloc(characters, sizeof(unichar) * (childCount + 1));
            _children = (__unsafe_unretained id *)realloc(_children, sizeof(*_children) * (childCount + 1));
            for (NSUInteger childIndex = childCount; childIndex > foundIndex; childIndex--) {
                characters[childIndex] = characters[childIndex - 1];
                _children[childIndex] = _children[childIndex - 1];
            }
            childCount++;
            characters[foundIndex] = aCharacter;
        }
        
        OBStrongRetain(aChild);
        _children[foundIndex] = aChild;
    }
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    [debugDictionary removeObjectForKey:@"__self__"];
    for (NSUInteger childIndex = 0; childIndex < childCount; childIndex++) {
        [debugDictionary setObject:_children[childIndex] forKey:[NSString stringWithFormat:@"%ld. '%@'", childIndex, [NSString stringWithCharacter:characters[childIndex]]]];
    }
    return debugDictionary;
}


NSUInteger trieFindIndex(OFTrieNode *node, unichar aCharacter)
{
    NSUInteger low = 0;
    NSUInteger range = 1;
    NSUInteger test = 0;
    
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

NSUInteger trieChildCount(OFTrieNode *node)
{
    return node->childCount;
}

id trieChildAtIndex(OFTrieNode *node, NSUInteger childIndex)
{
    OBPRECONDITION(childIndex < node->childCount);
    return node->_children[childIndex];
}

id trieFindChild(OFTrieNode *node, unichar aCharacter)
{
    NSUInteger foundIndex = trieFindIndex(node, aCharacter);
    if (foundIndex < node->childCount && node->characters[foundIndex] == aCharacter)
	return node->_children[foundIndex];
    else
	return nil;
}

const unichar *trieCharacters(OFTrieNode *node)
{
    return node->characters;
}


@end
