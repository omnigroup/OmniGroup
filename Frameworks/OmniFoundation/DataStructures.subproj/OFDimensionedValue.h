// Copyright 2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFDimensionedValue.h 71092 2005-12-13 18:43:42Z wiml $

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

