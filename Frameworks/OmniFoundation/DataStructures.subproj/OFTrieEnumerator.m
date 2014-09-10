// Copyright 1997-2005, 2007-2008, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTrieEnumerator.h>

#import <OmniFoundation/OFTrie.h>
#import <OmniFoundation/OFTrieNode.h>

RCS_ID("$Id$")

@implementation OFTrieEnumerator
{
    NSMutableArray *trieNodes;
    NSMutableArray *positions;
    BOOL isCaseSensitive;
}

static NSCharacterSet *uppercaseLetters;

+ (void)initialize;
{
    OBINITIALIZE;

    uppercaseLetters = [[NSCharacterSet uppercaseLetterCharacterSet] retain];
}

- initWithTrie:(OFTrie *)aTrie;
{
    if (!(self = [super init]))
        return nil;

    trieNodes = [[NSMutableArray alloc] init];
    positions = [[NSMutableArray alloc] init];
    [trieNodes addObject:[aTrie headNode]];
    [positions addObject:[NSNumber numberWithInt:0]];
    isCaseSensitive = [aTrie isCaseSensitive];
    return self;
}

- (void)dealloc;
{
    [trieNodes release];
    [positions release];
    
    [super dealloc];
}

- (id)nextObject;
{
    OFTrieNode *node = [trieNodes lastObject];
    NSUInteger position = [[positions lastObject] unsignedIntegerValue];
    while (1) {
        if (position >= trieChildCount(node)) {
            [trieNodes removeLastObject];
            [positions removeLastObject];
            if (![trieNodes count])
                return nil;
            node = [trieNodes lastObject];
            position = [[positions lastObject] intValue] + 1;
            continue;
        } else if (!isCaseSensitive && [uppercaseLetters characterIsMember:trieCharacters(node)[position]]) {
            position++;
            continue;
        }
        OFTrieNode *child = trieChildAtIndex(node, position);
        if ([child isKindOfClass:[OFTrieNode class]]) {
            [trieNodes addObject:child];
            [positions removeLastObject];
            [positions addObject:@(position)];
            [positions addObject:@(0)];
            node = child;
            position = 0;
            continue;
        } else {
            [positions removeLastObject];
            [positions addObject:@(++position)];
            return child;
        }
    }
}

@end
