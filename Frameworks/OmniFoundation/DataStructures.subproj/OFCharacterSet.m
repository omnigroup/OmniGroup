// Copyright 2001-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCharacterSet.h>

#import <OmniFoundation/NSString-OFUnicodeCharacters.h>
#import <OmniBase/OBObject.h>

RCS_ID("$Id$");

@implementation OFCharacterSet

+ (OFCharacterSet *)characterSetWithString:(NSString *)string;
{
    return [[[self alloc] initWithString:string] autorelease];
}

+ (OFCharacterSet *)whitespaceOFCharacterSet;
{
    static OFCharacterSet *whitespaceOFCharacterSet;

    // Potential multithreaded leak here, since we don't lock
    if (whitespaceOFCharacterSet == nil)
        whitespaceOFCharacterSet = [[OFCharacterSet alloc] initWithString:@" \t\r\n"];
    return whitespaceOFCharacterSet;
}

// Init and dealloc

- init;
{
    if ([super init] == nil)
        return nil;

    [self removeAllCharacters];
    return self;
}

- initWithCharacterSet:(NSCharacterSet *)characterSet;
{
    if ([self init] == nil)
        return nil;
        
    [self addCharactersFromCharacterSet:characterSet];
    
    return self;
}

- initWithOFCharacterSet:(OFCharacterSet *)ofCharacterSet;
{
    if ([self init] == nil)
        return nil;
        
    [self addCharactersFromOFCharacterSet:ofCharacterSet];
    return self;
}

- initWithString:(NSString *)string;
{
    if ([self init] == nil)
        return nil;
        
    [self addCharactersInString:string];
    return self;
}

- (void)dealloc;
{
    [super dealloc];
}


// API

- (BOOL)characterIsMember:(unichar)character;
{
    return OFCharacterSetHasMember(self, character);
}

- (void)addCharacter:(unichar)character;
{
    OFCharacterSetAddCharacter(self, character);
}

- (void)removeCharacter:(unichar)character;
{
    OFCharacterSetRemoveCharacter(self, character);
}

//

- (void)addCharactersInRange:(NSRange)characterRange;
{
    OBPRECONDITION(NSMaxRange(characterRange) <= USHRT_MAX); // Since OFCharacterSetAddCharacter takes a unichar.
    
    unsigned int character, endCharacter = (unichar)NSMaxRange(characterRange);
    for (character = (unsigned int)characterRange.location; character < endCharacter; character++) {
        OFCharacterSetAddCharacter(self, character);
    }
}

- (void)removeCharactersInRange:(NSRange)characterRange;
{
    OBPRECONDITION(NSMaxRange(characterRange) <= USHRT_MAX); // Since OFCharacterSetAddCharacter takes a unichar.

    unsigned int character, endCharacter = (unsigned int)NSMaxRange(characterRange);
    for (character = (unsigned int)characterRange.location; character < endCharacter; character++) {
        OFCharacterSetRemoveCharacter(self, character);
    }
}

//

- (void)addCharactersFromOFCharacterSet:(OFCharacterSet *)ofCharacterSet;
{
    unsigned int maskIndex;

    maskIndex = OFCharacterSetBitmapRepLength;
    while (maskIndex--) {
        bitmapRep[maskIndex] |= ofCharacterSet->bitmapRep[maskIndex];
    }
}

- (void)removeCharactersFromOFCharacterSet:(OFCharacterSet *)ofCharacterSet;
{
    unsigned int maskIndex;

    maskIndex = OFCharacterSetBitmapRepLength;
    while (maskIndex--) {
        bitmapRep[maskIndex] &= (~ofCharacterSet->bitmapRep[maskIndex]);
    }
}

- (void)addCharactersFromCharacterSet:(NSCharacterSet *)characterSet;
{
    unsigned int maskIndex;
    const OFByte *otherBitmap;
    
    otherBitmap = [[characterSet bitmapRepresentation] bytes];
    maskIndex = OFCharacterSetBitmapRepLength;
    while (maskIndex--) {
        bitmapRep[maskIndex] |= otherBitmap[maskIndex];
    }
}

- (void)removeCharactersFromCharacterSet:(NSCharacterSet *)characterSet;
{
    unsigned int maskIndex;
    const OFByte *otherBitmap;
    
    otherBitmap = [[characterSet bitmapRepresentation] bytes];
    maskIndex = OFCharacterSetBitmapRepLength;
    while (maskIndex--) {
        bitmapRep[maskIndex] &= (~otherBitmap[maskIndex]);
    }
}

- (void)addCharactersInString:(NSString *)string;
{
    CFStringInlineBuffer inlineBuffer;
    NSUInteger characterIndex, length = CFStringGetLength((CFStringRef)string);
    CFStringInitInlineBuffer((CFStringRef)string, &inlineBuffer, CFRangeMake(0, length));
    for (characterIndex = 0; characterIndex < length; characterIndex++)
        OFCharacterSetAddCharacter(self, CFStringGetCharacterFromInlineBuffer(&inlineBuffer, characterIndex));
}

- (void)removeCharactersInString:(NSString *)string;
{
    CFStringInlineBuffer inlineBuffer;
    NSUInteger characterIndex, length = CFStringGetLength((CFStringRef)string);
    CFStringInitInlineBuffer((CFStringRef)string, &inlineBuffer, CFRangeMake(0, length));
    for (characterIndex = 0; characterIndex < length; characterIndex++)
        OFCharacterSetRemoveCharacter(self, CFStringGetCharacterFromInlineBuffer(&inlineBuffer, characterIndex));
}

//

- (void)addAllCharacters;
{
    memset(bitmapRep, 0xff, OFCharacterSetBitmapRepLength);
}

- (void)removeAllCharacters;
{
    bzero(bitmapRep, OFCharacterSetBitmapRepLength);
}

- (void)invert;
{
    unsigned int maskIndex;
    
    maskIndex = OFCharacterSetBitmapRepLength;
    while (maskIndex--)
        bitmapRep[maskIndex] = ~bitmapRep[maskIndex];
}

// NSCopying protocol

- copy;
{
    OFCharacterSet *copy;

    copy = [[isa alloc] init];
    memcpy(copy->bitmapRep, bitmapRep, OFCharacterSetBitmapRepLength);
    return copy;
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    BOOL firstRange = YES;
    NSMutableString *ranges;
    NSMutableDictionary *debugDictionary;
    unsigned int characterIndex, characterCount;

    debugDictionary = [super debugDictionary];
    ranges = [[NSMutableString alloc] init];
    characterCount = 1 << 16;
    for (characterIndex = 0; characterIndex < characterCount; characterIndex++) {
        if (OFCharacterSetHasMember(self, (unichar)characterIndex)) {
            NSRange currentRange;

            currentRange.location = characterIndex;
            do {
                characterIndex++;
            } while (characterIndex < characterCount && OFCharacterSetHasMember(self, (unichar)characterIndex));
            currentRange.length = characterIndex - currentRange.location;
            if (firstRange) {
                firstRange = NO;
            } else {
                [ranges appendString:@", "];
            }
            
            OBASSERT(currentRange.location <= UINT_MAX); // UnicodeScalarValue is UInt32
            [ranges appendFormat:@"'%@'", [NSString stringWithCharacter:(UnicodeScalarValue)currentRange.location]];
            OBASSERT(currentRange.length != 0);
            if (currentRange.length != 1) {
                OBASSERT(NSMaxRange(currentRange) - 1 <= UINT_MAX); // UnicodeScalarValue is UInt32
                [ranges appendFormat:@" - '%@'", [NSString stringWithCharacter:(UnicodeScalarValue)(NSMaxRange(currentRange) - 1)]];
            }
        }
    }
    [debugDictionary setObject:ranges forKey:@"ranges"];
    [ranges release];
    return debugDictionary;
}

@end
