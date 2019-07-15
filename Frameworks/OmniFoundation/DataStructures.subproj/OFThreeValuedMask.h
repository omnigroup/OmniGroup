// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniBase/assertions.h>

// A utility class for doing bit-mask comparisons. Instances track which bits we care about and what value those bits should have.
@interface OFThreeValuedMask : NSObject <NSCopying>
+ (instancetype)maskWithSetBits:(NSUInteger)setBitMask label:(NSString *)label; // all other bits are "don't care"
+ (instancetype)maskWithClearBits:(NSUInteger)clearBitMask label:(NSString *)label; // all other bits are "don't care"
+ (instancetype)maskWithSetBits:(NSUInteger)setBitMask clearBits:(NSUInteger)clearBitMask label:(NSString *)label;

#ifdef OMNI_ASSERTIONS_ON
+ (void)checkPartition:(NSArray *)maskSet consideringBits:(NSUInteger)bitMaskToCheck; // checks that the set of OFThreeValuedMasks covers all bit pattern combinations without overlap
#endif

- (id)initWithMatchingMask:(NSUInteger)matchMask consideringMask:(NSUInteger)careMask label:(NSString *)label;

- (BOOL)matches:(NSUInteger)bitMask;
@end
