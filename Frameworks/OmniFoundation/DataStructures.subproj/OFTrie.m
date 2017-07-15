// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTrie.h>

#import <OmniFoundation/OFTrieNode.h>
#import <OmniFoundation/OFTrieBucket.h>

#import <OmniFoundation/OFTrieEnumerator.h>

RCS_ID("$Id$")

@implementation OFTrie

// Init and dealloc

- (id)init;
{
    return [self initCaseSensitive:YES];
}

- initCaseSensitive:(BOOL)shouldBeCaseSensitive;
{
    if (!(self = [super init]))
        return nil;

    _headNode = [[OFTrieNode alloc] init];
    _caseSensitive = shouldBeCaseSensitive;

    return self;
}

- (void)dealloc;
{
    [_headNode release];
    [super dealloc];
}

//

- (NSEnumerator *)objectEnumerator;
{
    return [[[OFTrieEnumerator alloc] initWithTrie:self] autorelease];
}

#define SAFE_ALLOCA_SIZE (8 * 8192)

- (void)addBucket:(OFTrieBucket *)bucket forString:(NSString *)aString;
{
    OFTrieNode *to, *attachTo = _headNode;
    unichar *buffer, *upperBuffer, *ptr;

    NSUInteger length = [aString length];
    NSUInteger bufferSize = (length + 1) * sizeof(unichar);
    BOOL useMalloc = bufferSize * 2 >= SAFE_ALLOCA_SIZE;
    if (useMalloc) {
	buffer = (unichar *)malloc(bufferSize);
    } else {
        buffer = (unichar *)alloca(bufferSize);
    }
    if (!_caseSensitive) {
        if (useMalloc) {
            upperBuffer = (unichar *)malloc(bufferSize);
        } else {
            upperBuffer = (unichar *)alloca(bufferSize);
        }
    } else {
        upperBuffer = NULL; // Let's just ensure that nobody dereferences this
    }

    ptr = buffer;

    if (!_caseSensitive) {
#warning -addBucket:forString: assumes that -uppercaseString and -lowercaseString return strings of identical length as the original string
        // This isn't actually true for unicode.
        // Also, they assume that string equality is equivalent to having the same unichars in the same sequence, which isn't generally true for unicode.

        aString = [aString uppercaseString];
	[aString getCharacters:upperBuffer];
	upperBuffer[length] = '\0';
	aString = [aString lowercaseString];
    }
    [aString getCharacters:buffer];
    buffer[length] = '\0';
    Class trieNodeClass = [_headNode class];
    if (trieChildCount(_headNode) != 0) {
	while ((to = trieFindChild(attachTo, *ptr))) {
            if ([to class] != trieNodeClass) {
		OFTrieBucket *existingBucket;
		OFTrieNode *end;
		unichar *existingPtr;
		unichar *ptrPosition;

		if (!*ptr)
		    break;
		existingBucket = (OFTrieBucket *)to;
		end = attachTo;
		existingPtr = existingBucket->lowerCharacters - 1;
		ptrPosition = ptr;
                [existingBucket retain];
		do {
                    OFTrieNode *new;

                    new = [[OFTrieNode alloc] init];
		    [end addChild:new withCharacter:*ptr];
                    if (!_caseSensitive)
                        [end addChild:new withCharacter:upperBuffer[ptr - buffer]];
		    [new release];
		    end = new;
		    ptr++;
		    existingPtr++;
		} while (*ptr && *ptr == *existingPtr);

		if (*existingPtr || *ptr) {
                    NSUInteger offset;

                    offset = existingPtr - existingBucket->lowerCharacters;
		    if (*existingPtr) {
                        NSUInteger existingLength;

			[end addChild:existingBucket withCharacter:*existingPtr];
                        if (!_caseSensitive)
                            [end addChild:existingBucket withCharacter:existingBucket->upperCharacters[offset]];
		
                        existingLength = 0;
                        while (*++existingPtr != '\0')
                            existingLength++;
			offset++;
			[existingBucket setRemainingLower:existingBucket->lowerCharacters + offset upper:existingBucket->upperCharacters + offset length:existingLength];
		    } else {
			[end addChild:existingBucket withCharacter:0];
			offset++;
			[existingBucket setRemainingLower:existingBucket->lowerCharacters + offset upper:existingBucket->upperCharacters + offset length:0];
		    }
		    attachTo = end;
		} else {
		    ptr = ptrPosition;
		}
                [existingBucket release];
		break;
	    }
	    attachTo = to;
	    ptr++;	
	}
    }
    [attachTo addChild:bucket withCharacter:*ptr];
    if (_caseSensitive) {
        if (*ptr)
            ptr++;
	[bucket setRemainingLower:ptr upper:ptr length:length - (ptr - buffer)];
    } else {
        [attachTo addChild:bucket withCharacter:upperBuffer[ptr - buffer]];
        if (*ptr)
            ptr++;
	[bucket setRemainingLower:ptr upper:upperBuffer + (ptr - buffer) length:length - (ptr - buffer)];
    }

    if (useMalloc) {
	free(buffer);
        if (!_caseSensitive)
            free(upperBuffer);
    }
}

- (OFTrieBucket *)bucketForString:(NSString *)aString;
{
    unichar *buffer, *ptr;
    OFTrieNode *currentNode;
    Class trieNodeClass;

    if (trieChildCount(_headNode) == 0)
	return nil;

    NSUInteger length = [aString length];
    BOOL useMalloc = (length + 1) * sizeof(*buffer) >= SAFE_ALLOCA_SIZE;
    if (useMalloc)
	buffer = (unichar *)malloc((length + 1) * sizeof(*buffer));
    else
	buffer = (unichar *)alloca((length + 1) * sizeof(*buffer));
    [aString getCharacters:buffer];
    buffer[length] = 0;
    ptr = buffer;
    currentNode = _headNode;
    trieNodeClass = [_headNode class];
    while ((currentNode = trieFindChild(currentNode, *ptr++))) {
	if ([currentNode class] != trieNodeClass) {
	    OFTrieBucket *test;
	    unichar *lowerPtr, *upperPtr;

	    test = (OFTrieBucket *)currentNode;
	    lowerPtr = test->lowerCharacters;
	    upperPtr = test->upperCharacters;
	    if (!ptr[-1] && !*lowerPtr) {
		if (useMalloc)
		    free(buffer);
		return test;
	    }
	    while (*ptr) {
		if (*ptr != *lowerPtr && *ptr != *upperPtr)
                    goto freeBufferAndReturnNil;
                lowerPtr++; upperPtr++; ptr++;
	    }
	    if (useMalloc)
		free(buffer);
	    return *lowerPtr ? nil : test;
	}
    }

freeBufferAndReturnNil:
    if (useMalloc)
	free(buffer);
    return nil;
}

#pragma mark - Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    [debugDictionary setObject:_headNode forKey:@"_headNode"];
    return debugDictionary;
}

@end
