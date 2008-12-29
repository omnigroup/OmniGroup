// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFPoint.h 98221 2008-03-04 21:06:19Z kc $

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@interface OFPoint : NSObject <NSCopying, NSCoding>
{
    NSPoint _value;
}

+ (OFPoint *)pointWithPoint:(NSPoint)point;

- initWithPoint:(NSPoint)point;
- initWithString:(NSString *)string;

- (NSPoint)point;

- (NSMutableDictionary *)propertyListRepresentation;
+ (OFPoint *)pointFromPropertyListRepresentation:(NSDictionary *)dict;

@end

// Value transformer
extern NSString * const OFPointToPropertyListTransformerName;
