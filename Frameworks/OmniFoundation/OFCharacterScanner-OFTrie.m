// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCharacterScanner-OFTrie.h>

#import <OmniFoundation/OFTrie.h>
#import <OmniFoundation/OFTrieBucket.h>
#import <OmniFoundation/OFTrieNode.h>

RCS_ID("$Id$")

@implementation OFCharacterScanner (OFTrie)

- (OFTrieBucket *)readLongestTrieElement:(OFTrie *)trie;
{
    return [self readLongestTrieElement:trie delimiterOFCharacterSet:nil];
}

- (OFTrieBucket *)readLongestTrieElement:(OFTrie *)trie delimiterOFCharacterSet:(OFCharacterSet *)delimiterOFCharacterSet;
{
    OFTrieNode *node = [trie headNode];
    if (trieChildCount(node) == 0)
	return nil;
    Class trieNodeClass = [node class];
    
    [self setRewindMark]; // Note that since we set this at the beginning of where we are scanning, we can just use setScanLocation: inside this loop, because we are guaranteed to have all data AFTER this point until we discard the rewind mark.
    
    OFTrieBucket *lastFoundBucket = nil;
    NSUInteger endOfTheLastBucketScanLocation = 0;
    unichar currentCharacter;
    while ((currentCharacter = scannerPeekCharacter(self)) != OFCharacterScannerEndOfDataCharacter) {
        
        node = trieFindChild(node, currentCharacter);
        if (node == nil)
            break;
        
        if ([node class] != trieNodeClass) {
            OFTrieBucket *bucket;
            unichar *lowerCheck, *upperCheck;
            
            bucket = (OFTrieBucket *)node;
            lowerCheck = bucket->lowerCharacters;
            upperCheck = bucket->upperCharacters;
            
            scannerSkipPeekedCharacter(self);
            while (*lowerCheck && ((currentCharacter = scannerPeekCharacter(self)) != OFCharacterScannerEndOfDataCharacter)) {
                if (currentCharacter != *lowerCheck && currentCharacter != *upperCheck)
                    break; // mismatch, so return last bucket that matched
                scannerSkipPeekedCharacter(self);
                lowerCheck++; upperCheck++;
            }
            if (*lowerCheck) // then we ran out of data, so return last bucket that matched
                break;
            else { // perfect match
                if (delimiterOFCharacterSet != nil) {
                    currentCharacter = scannerPeekCharacter(self); // this is really necessary, don't delete without talking to wjs
                    if (currentCharacter != OFCharacterScannerEndOfDataCharacter && !OFCharacterSetHasMember(delimiterOFCharacterSet, currentCharacter)) {
                        // Although we found a perfect match, the token's characters keep going beyond our trie, so we are going to consider this a failure and rewind. We want to do this in, for example, CSS, where if we are scanning "font-snorkle" and we have a node named "font", we DO NOT want to match "font" and leave our scanner on "-snorkle", we instead want to rewind so we can read "font-snorkle" as a string instead of as a node in the trie.
                        [self rewindToMark];
                        return nil;
                    }
                }
                [self discardRewindMark];
                return bucket;
            }
        } else if (!*trieCharacters(node)) {
            lastFoundBucket = OB_CHECKED_CAST(OFTrieBucket, trieChildAtIndex(node, 0));
            endOfTheLastBucketScanLocation = scannerScanLocation(self) + 1;
        }
        
        scannerSkipPeekedCharacter(self);
    }
    
    if (lastFoundBucket == nil) {
        // We never found any matches, so just back out as if we never touched the scanner.
        [self rewindToMark];
        return nil;
    }
    
    [self setScanLocation:endOfTheLastBucketScanLocation]; // Rewind to the end of the best bucket we found
    
    if (delimiterOFCharacterSet != nil) {
        currentCharacter = scannerPeekCharacter(self);
        if (currentCharacter != OFCharacterScannerEndOfDataCharacter && !OFCharacterSetHasMember(delimiterOFCharacterSet, currentCharacter)) {
            // Although we found an ok match, the token's characters keep going beyond our trie, so we are going to consider this a failure and rewind. We want to do this in, for example, CSS, where if we are scanning "font-snorkle" and we have a node named "font", we DO NOT want to match "font" and leave our scanner on "-snorkle", we instead want to rewind so we can read "font-snorkle" as a string instead of as a node in the trie.
            [self rewindToMark];
            return nil;
        }
    }
    // We found an OK match and it ends in a delimeter, so we're going to return it.
    [self discardRewindMark];
    return lastFoundBucket;
}

- (OFTrieBucket *)readShortestTrieElement:(OFTrie *)trie;
{
    OFTrieNode *node = [trie headNode];
    if (trieChildCount(node) == 0)
	return nil;
    
    Class trieNodeClass = [node class];
    unichar currentCharacter;
    while ((currentCharacter = scannerPeekCharacter(self)) != OFCharacterScannerEndOfDataCharacter) {
	if ((node = trieFindChild(node, currentCharacter))) {
	    if ([node class] != trieNodeClass) {
		OFTrieBucket *bucket = (OFTrieBucket *)node;
		unichar *lowerCheck = bucket->lowerCharacters;
		unichar *upperCheck = bucket->upperCharacters;
		
		while (*lowerCheck && ((currentCharacter = scannerPeekCharacter(self)) != OFCharacterScannerEndOfDataCharacter)) {
		    if (currentCharacter != *lowerCheck && currentCharacter != *upperCheck)
			break;
		    scannerSkipPeekedCharacter(self);
                    lowerCheck++; upperCheck++;
		}
		if (*lowerCheck) {
		    break;
		} else {
		    return bucket;
		}
	    } else if (!*trieCharacters(node)) {
		return trieChildAtIndex(node, 0);
	    }
	} else {
	    break;
	}
	scannerSkipPeekedCharacter(self);
    }
    return nil;
}

@end
