// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSNumber-OFExtensions.h 70816 2005-12-01 00:33:56Z wiml $

#import <Foundation/NSValue.h>

@interface NSNumber (OFExtensions)
- initWithString:(NSString *)aString;


// Arithmetic using NSNumbers. This was originally written OO-style, as a method for each operation, but it turns out what we really need is some sort of polymorphic dispatch a la Common Lisp; there's no good way to represent that in ObjC. So, since we have to special-case all the polymorphism anyway, just make it a single fn. (The especial complication here is the need to support OFRationalNumbers.)
typedef enum {
    OFArithmeticOperation_Add,
    OFArithmeticOperation_Subtract,
    OFArithmeticOperation_Multiply,
    OFArithmeticOperation_Divide
} OFArithmeticOperation;

+ (NSNumber *)numberByPerformingOperation:(OFArithmeticOperation)op withNumber:(NSNumber *)v1 andNumber:(NSNumber *)v2;

- (BOOL)isExact;  // Returns YES for integers and (precise) rationals; returns NO for floating point

@end

// This class exists due to Radar #3478597 where NaN numbers aren't correctly compared.  This returns something that is truly 'Not a Number' and thus the CF comparison works out better.  Of course, it really isn't a NSNumber, so care must be taken that it isn't used as one.
@interface OFNaN : NSObject
+ (OFNaN *)sharedNaN;
@end

