// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTrieNode.h>

#import <OmniFoundation/NSString-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFTrieNode

// Init and dealloc

- (void)dealloc;
{
    unsigned int childIndex;
    NSZone *myZone;
    
    myZone = [self zone];
    for (childIndex = 0; childIndex < childCount; childIndex++)
        [children[childIndex] release];
    NSZoneFree(myZone, characters);
    NSZoneFree(myZone, children);
    [super dealloc];
}

// API

- (void)addChild:(id)aChild withCharacter:(unichar)aCharacter;
{
    if (childCount == 0) {
        NSZone *myZone;
        
        myZone = [self zone];
        characters = (unichar *)NSZoneMalloc(myZone, sizeof(unichar));
        children = (id *)NSZoneMalloc(myZone, sizeof(id));
        *characters = aCharacter;
        *children = [aChild retain];
        childCount = 1;
    } else {
        unsigned foundIndex;
        
        foundIndex = trieFindIndex(self, aCharacter);
        if (foundIndex < childCount && characters[foundIndex] == aCharacter) {
            id foundChild;

            foundChild = children[foundIndex];
            if (foundChild == aChild)
                return; // Already have this child at this character
            [foundChild release];
        } else {
            unsigned int childIndex;
            NSZone *myZone;

            myZone = [self zone];
            characters = (unichar *)NSZoneRealloc(myZone, characters, sizeof(unichar) * (childCount + 1));
            children = (id *)NSZoneRealloc(myZone, children, sizeof(id) * (childCount + 1));
            for (childIndex = childCount; childIndex > foundIndex; childIndex--) {
                characters[childIndex] = characters[childIndex - 1];
                children[childIndex] = children[childIndex - 1];
            }
            childCount++;
            characters[foundIndex] = aCharacter;
        }
        children[foundIndex] = [aChild retain]; 
    }
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;
    unsigned int childIndex;

    debugDictionary = [super debugDictionary];
    [debugDictionary removeObjectForKey:@"__self__"];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        [debugDictionary setObject:children[childIndex] forKey:[NSString stringWithFormat:@"%d. '%@'", childIndex, [NSString stringWithCharacter:characters[childIndex]]]];
    }
    return debugDictionary;
}

@end
