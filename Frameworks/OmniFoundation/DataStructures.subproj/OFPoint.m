// Copyright 2003-2008, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPoint.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <Foundation/NSValueTransformer.h>

#import <OmniBase/OmniBase.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIGeometry.h>
#endif


RCS_ID("$Id$");

/*
 A smarter wrapper for CGPoint than NSValue.  Used in OmniStyle's OSVectorStyleAttribute.  This also has some AppleScript hooks usable as a <record-type>.
*/

@implementation OFPoint

+ (OFPoint *)pointWithPoint:(CGPoint)point;
{
    return [[[self alloc] initWithPoint:point] autorelease];
}

- initWithPoint:(CGPoint)point;
{
    if (!(self = [super init]))
        return nil;

    _value = point;
    return self;
}

- initWithString:(NSString *)string;
{
    if (!(self = [super init]))
        return nil;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    _value = NSPointFromString(string);
#else
    _value = CGPointFromString(string);
#endif
    return self;
}

- (CGPoint)point;
{
    return _value;
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[OFPoint class]])
        return NO;
    return CGPointEqualToPoint(_value, ((OFPoint *)otherObject)->_value);
}

- (NSString *)description;
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    return NSStringFromPoint(_value);
#else
    return NSStringFromCGPoint(_value);
#endif
}

//
// NSCopying
//
- (id)copyWithZone:(NSZone *)zone;
{
    // We are immutable!
    return [self retain];
}

// If we do support coding, we need to handle 64-bit difference in CGFloat
#if 0
//
// NSCoding
//

- (void)encodeWithCoder:(NSCoder *)aCoder;
{
    [aCoder encodeValueOfObjCType:@encode(typeof(_value)) at:&_value];
}

- (id)initWithCoder:(NSCoder *)aCoder;
{
    [aCoder decodeValueOfObjCType:@encode(typeof(_value)) at:&_value];
    return self;
}
#endif

#pragma mark -
#pragma mark Property list support

// These are used in AppleScript interfaces, so this can't be changed w/o considering the implications for scripting.
- (NSMutableDictionary *)propertyListRepresentation;
{
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithDouble:_value.x], @"x", 
        [NSNumber numberWithDouble:_value.y], @"y", 
        nil];
}

+ (OFPoint *)pointFromPropertyListRepresentation:(NSDictionary *)dict;
{
    CGPoint point;
    point.x = (CGFloat)[dict doubleForKey:@"x" defaultValue:0.0];
    point.y = (CGFloat)[dict doubleForKey:@"y" defaultValue:0.0];
    return [OFPoint pointWithPoint:point];
}

@end


// Value transformer
NSString * const OFPointToPropertyListTransformerName = @"OFPointToPropertyListTransformer";

@interface OFPointToPropertyListTransformer : NSValueTransformer
@end

@implementation OFPointToPropertyListTransformer

+ (void)didLoad;
{
    OFPointToPropertyListTransformer *instance = [[self alloc] init];
    [NSValueTransformer setValueTransformer:instance forName:OFPointToPropertyListTransformerName];
    [instance release];
}

+ (Class)transformedValueClass;
{
    return [NSDictionary class];
}

+ (BOOL)allowsReverseTransformation;
{
    return YES;
}

- (id)transformedValue:(id)value;
{
    if ([value isKindOfClass:[OFPoint class]])
	return [(OFPoint *)value propertyListRepresentation];
    return nil;
}

- (id)reverseTransformedValue:(id)value;
{
    if ([value isKindOfClass:[NSDictionary class]])
	return [OFPoint pointFromPropertyListRepresentation:value];
    return nil;
}

@end
