// Copyright 2003-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h>
#else
#import <CoreGraphics/CGGeometry.h>
#endif

@class NSMutableDictionary, NSDictionary;

@interface OFPoint : NSObject <NSCopying /*, NSCoding*/>
{
@private
    CGPoint _value;
}

+ (OFPoint *)pointWithPoint:(CGPoint)point;

- initWithPoint:(CGPoint)point;
- initWithString:(NSString *)string;

- (CGPoint)point;

- (NSMutableDictionary *)propertyListRepresentation;
+ (OFPoint *)pointFromPropertyListRepresentation:(NSDictionary *)dict;

@end

// Value transformer
extern NSString * const OFPointToPropertyListTransformerName;
