// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPoint.h>

#import <OmniFoundation/NSDictionary-OFExtensions.h>

RCS_ID("$Id$");

/*
 A smarter wrapper for NSPoint than NSValue.  Used in OmniStyle's OSVectorStyleAttribute.  This also has some AppleScript hooks usable as a <record-type>.
*/

@implementation OFPoint

+ (OFPoint *)pointWithPoint:(NSPoint)point;
{
    return [[[self alloc] initWithPoint:point] autorelease];
}

- initWithPoint:(NSPoint)point;
{
    _value = point;
    return self;
}

- initWithString:(NSString *)string;
{
    _value = NSPointFromString(string);
    return self;
}

- (NSPoint)point;
{
    return _value;
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[OFPoint class]])
        return NO;
    return NSEqualPoints(_value, ((OFPoint *)otherObject)->_value);
}

- (NSString *)description;
{
    return NSStringFromPoint(_value);
}

//
// NSCopying
//
- (id)copyWithZone:(NSZone *)zone;
{
    // We are immutable!
    return [self retain];
}

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

#pragma mark -
#pragma mark Property list support

// These are used in AppleScript interfaces, so this can't be changed w/o considering the implications for scripting.
- (NSMutableDictionary *)propertyListRepresentation;
{
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithFloat:_value.x], @"x", 
        [NSNumber numberWithFloat:_value.y], @"y", 
        nil];
}

+ (OFPoint *)pointFromPropertyListRepresentation:(NSDictionary *)dict;
{
    NSPoint point;
    point.x = [dict floatForKey:@"x" defaultValue:0.0];
    point.y = [dict floatForKey:@"y" defaultValue:0.0];
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
