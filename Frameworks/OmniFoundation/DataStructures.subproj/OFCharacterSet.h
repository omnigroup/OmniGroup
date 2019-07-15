// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSCharacterSet;

#import <Foundation/NSString.h> // For unichar

#import <OmniFoundation/OFByte.h>

#define OFCharacterSetBitmapRepLength ((1 << 16) >> 3)

@interface OFCharacterSet : NSObject
{
@public
    OFByte bitmapRep[OFCharacterSetBitmapRepLength];
}

+ (OFCharacterSet *)characterSetWithString:(NSString *)string;
+ (OFCharacterSet *)whitespaceOFCharacterSet;

//
- initWithCharacterSet:(NSCharacterSet *)characterSet;
- initWithOFCharacterSet:(OFCharacterSet *)ofCharacterSet;
- initWithString:(NSString *)string;

// API
- (BOOL)characterIsMember:(unichar)character;
- (void)addCharacter:(unichar)character;
- (void)removeCharacter:(unichar)character;

- (void)addCharactersInRange:(NSRange)characterRange;
- (void)removeCharactersInRange:(NSRange)characterRange;

- (void)addCharactersFromOFCharacterSet:(OFCharacterSet *)ofCharacterSet;
- (void)removeCharactersFromOFCharacterSet:(OFCharacterSet *)ofCharacterSet;

- (void)addCharactersFromCharacterSet:(NSCharacterSet *)characterSet;
- (void)removeCharactersFromCharacterSet:(NSCharacterSet *)characterSet;

- (void)addCharactersInString:(NSString *)string;
- (void)removeCharactersInString:(NSString *)string;

- (void)addAllCharacters;
- (void)removeAllCharacters;

- (void)invert;

@end

static inline BOOL OFCharacterSetHasMember(OFCharacterSet *unicharSet, unichar character)
{
    return (unicharSet->bitmapRep[character >> 3] & (((unsigned)1) << (character & 7)))? YES : NO;
}

static inline void OFCharacterSetAddCharacter(OFCharacterSet *unicharSet, unichar character)
{
    unicharSet->bitmapRep[character >> 3] |= (((unsigned)1) << (character & 7));
}

static inline void OFCharacterSetRemoveCharacter(OFCharacterSet *unicharSet, unichar character)
{
    unicharSet->bitmapRep[character >> 3] &= ~(((unsigned)1) << (character & 7));
}
