// Copyright 2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFRationalNumber.h>
#import <OmniFoundation/OFUnit.h>

@interface OFDimensionedValue : NSObject
{
    NSNumber *value;
    OFUnit *dimension;
}

+ (OFDimensionedValue *)valueWithDimension:(OFUnit *)dim integerValue:(int)i;
+ (OFDimensionedValue *)valueWithDimension:(OFUnit *)dim value:(NSNumber *)r;
- initWithDimension:(OFUnit *)dim value:(NSNumber *)r;

- (NSNumber *)value;
- (OFUnit *)dimension;

@end

