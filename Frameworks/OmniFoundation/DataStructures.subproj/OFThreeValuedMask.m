// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFThreeValuedMask.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$");

@interface OFThreeValuedMask ()
@property (nonatomic, assign) NSUInteger matchMask;
@property (nonatomic, assign) NSUInteger careMask;
@property (nonatomic, copy) NSString *label;
@end

@implementation OFThreeValuedMask

+ (instancetype)maskWithSetBits:(NSUInteger)setBitMask label:(NSString *)label; // all other bits are "don't care"
{
    return [OFThreeValuedMask maskWithSetBits:setBitMask clearBits:0 label:label];
}

+ (instancetype)maskWithClearBits:(NSUInteger)clearBitMask label:(NSString *)label; // all other bits are "don't care"
{
    return [OFThreeValuedMask maskWithSetBits:0 clearBits:clearBitMask label:label];
}

+ (instancetype)maskWithSetBits:(NSUInteger)setBitMask clearBits:(NSUInteger)clearBitMask label:(NSString *)label;
{
    OBPRECONDITION((setBitMask & clearBitMask) == 0, @"Cannot request that the same bit be both set and cleared. Troublesome bits: 0x%02lx", (setBitMask & clearBitMask));
    NSUInteger careMask = setBitMask | clearBitMask;
    return [[[OFThreeValuedMask alloc] initWithMatchingMask:setBitMask consideringMask:careMask label:label] autorelease];
}

#ifdef OMNI_ASSERTIONS_ON
+ (void)checkPartition:(NSArray *)maskSet consideringBits:(NSUInteger)bitMaskToCheck; // checks that the set of OFThreeValuedMasks covers all bit pattern combinations without overlap
{
    OBPRECONDITION([maskSet count] > 0);
    // This is inefficient, but since it's assertions-only code...
    for (NSUInteger pattern = 0; pattern <= bitMaskToCheck; pattern++) {
        NSUInteger patternToCheck = pattern & bitMaskToCheck;
        BOOL covered = NO;
        for (OFThreeValuedMask *mask in maskSet) {
            if ([mask matches:patternToCheck]) {
                if (covered) {
                    // report duplicates
                    NSArray *duplicates = [maskSet select:^BOOL(id object) {
                        return [object matches:patternToCheck];
                    }];
                    OBASSERT(!covered, @"bit pattern 0x%02lx is matched by multiple masks: %@", patternToCheck, duplicates);
                }
                covered = YES;
            }
        }
        OBASSERT(covered, @"bit pattern 0x%02lx is not matched by any mask", patternToCheck);
    }
}
#endif

- (id)initWithMatchingMask:(NSUInteger)matchMask consideringMask:(NSUInteger)careMask label:(NSString *)label;
{
    self = [super init];
    if (self == nil)
        return nil;
    
    _matchMask = matchMask;
    _careMask = careMask;
    _label = [label copy];
    return self;
}

- (void)dealloc;
{
    [_label release];
    [super dealloc];
}

#pragma mark NSObject subclass

- (NSString *)description;
{
    return [NSString stringWithFormat:@"%@: %@ matching %@", [super description], self.label, [self _bitmaskRepresentation]];
}

- (NSString *)shortDescription;
{
    return [self _bitmaskRepresentation];
}

- (BOOL)isEqual:(id)object;
{
    if (![object isKindOfClass:[OFThreeValuedMask class]])
        return NO;
    
    OFThreeValuedMask *other = (OFThreeValuedMask *)object;
    
    return (self.matchMask == other.matchMask && self.careMask == other.careMask);
}

- (NSUInteger)hash;
{
    // Our -isEqual: implementation checks the matchMask and careMask, so we must derive the hash from both.
    // However, we anticipate that we'll only rarely use more than a few low-order bits in either - getting up to 32 or 64 conditions in a single three-valued mask is unlikely.
    // As such, we attempt to provide a more unique hash value for similar three-valued masks by rolling the matchMask around halfway, then XORing it with the careMask.
    // In the common case, this will generally return a bit sequence that contains the low-order half of matchMask followed by the low-order half of careMask.
    
    NSUInteger bitShift = (8 * sizeof(NSUInteger)) / 2;
    NSUInteger rolledMatchMask = (self.matchMask >> bitShift) | (self.matchMask << bitShift);
    return (self.careMask ^ rolledMatchMask);
}

#pragma mark Public API

- (BOOL)matches:(NSUInteger)bitMask;
{
    return (bitMask & self.careMask) == self.matchMask;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    // OFThreeValuedMask descends directly from NSObject - no need to call super
    return [[OFThreeValuedMask alloc] initWithMatchingMask:self.matchMask consideringMask:self.careMask label:self.label];
}

#pragma mark Private

- (NSString *)_bitmaskRepresentation;
{
    NSMutableString *bitMaskRepresentation = [[[NSMutableString alloc] init] autorelease];
    NSUInteger careMask = self.careMask;
    NSUInteger matchMask = self.matchMask;
    while (careMask != 0) {
        NSString *nextBit;
        if (careMask & 1UL) {
            nextBit = ((matchMask &1UL) ? @"1" : @"0");
        } else {
            nextBit = @"x"; // don't care
        }
        [bitMaskRepresentation insertString:nextBit atIndex:0];
        
        careMask >>= 1;
        matchMask >>= 1;
    }
    return bitMaskRepresentation;
}

@end
