// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFByteSet.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSData;

#import <Foundation/NSString.h> // For unichar and NSStringEncoding
#import <OmniFoundation/OFByte.h>

#define OFByteSetBitmapRepLength ((1 << 8) >> 3)

@interface OFByteSet : OFObject
{
@public
    OFByte bitmapRep[OFByteSetBitmapRepLength];
}

- (BOOL)byteIsMember:(OFByte)aByte;
- (void)addByte:(OFByte)aByte;
- (void)removeByte:(OFByte)aByte;

- (void)addAllBytes;
- (void)removeAllBytes;

- (void)addBytesFromData:(NSData *)data;
- (void)addBytesFromString:(NSString *)string encoding:(NSStringEncoding)encoding;
- (void)removeBytesFromData:(NSData *)data;
- (void)removeBytesFromString:(NSString *)string encoding:(NSStringEncoding)encoding;

- (NSData *)data;
- (NSString *)stringUsingEncoding:(NSStringEncoding)encoding;

@end

@interface OFByteSet (PredefinedSets)
+ (OFByteSet *)whitespaceByteSet;
@end

static inline BOOL isByteInByteSet(OFByte aByte, OFByteSet *byteSet)
{
    return byteSet->bitmapRep[aByte >> 3] & (((unsigned)1) << (aByte & 7));
}

static inline BOOL isCharacterInByteSet(unichar ch, OFByteSet *byteSet)
{
    if (ch & 0xff00)
        return NO;
    return isByteInByteSet(ch, byteSet);
}

static inline void addByteToByteSet(OFByte aByte, OFByteSet *byteSet)
{
    byteSet->bitmapRep[aByte >> 3] |= (((unsigned)1) << (aByte & 7));
}

static inline void
removeByteFromByteSet(OFByte aByte, OFByteSet *byteSet)
{
    byteSet->bitmapRep[aByte >> 3] &= ~(((unsigned)1) << (aByte & 7));
}

