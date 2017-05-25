// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSAttributedString-OFExtensions.h>
#import <Foundation/Foundation.h>

RCS_ID("$Id$")

@implementation NSAttributedString (OFExtensions)

#ifdef DEBUG

static id (*_original_immutable_initWithString_attributes)(id self, SEL _cmd, NSString *string, NSDictionary *attributes) = NULL;
static id _replacement_immutable_initWithString_attributes(id self, SEL _cmd, NSString *string, NSDictionary *attributes)
{
    assert([string isKindOfClass:[NSString class]]);
    return _original_immutable_initWithString_attributes(self, _cmd, string, attributes);
}
static id (*_original_immutable_initWithString)(id self, SEL _cmd, NSString *string) = NULL;
static id _replacement_immutable_initWithString(id self, SEL _cmd, NSString *string)
{
    assert([string isKindOfClass:[NSString class]]);
    return _original_immutable_initWithString(self, _cmd, string);
}

static id (*_original_mutable_initWithString_attributes)(id self, SEL _cmd, NSString *string, NSDictionary *attributes) = NULL;
static id _replacement_mutable_initWithString_attributes(id self, SEL _cmd, NSString *string, NSDictionary *attributes)
{
    assert([string isKindOfClass:[NSString class]]);
    return _original_mutable_initWithString_attributes(self, _cmd, string, attributes);
}
static id (*_original_mutable_initWithString)(id self, SEL _cmd, NSString *string) = NULL;
static id _replacement_mutable_initWithString(id self, SEL _cmd, NSString *string)
{
    assert([string isKindOfClass:[NSString class]]);
    return _original_mutable_initWithString(self, _cmd, string);
}

OBPerformPosing(^{
    _original_immutable_initWithString_attributes = (typeof(_original_immutable_initWithString_attributes))OBReplaceMethodImplementation(NSClassFromString(@"NSConcreteAttributedString"), @selector(initWithString:attributes:), (IMP)_replacement_immutable_initWithString_attributes);
    _original_immutable_initWithString = (typeof(_original_immutable_initWithString))OBReplaceMethodImplementation(NSClassFromString(@"NSConcreteAttributedString"), @selector(initWithString:), (IMP)_replacement_immutable_initWithString);

    _original_mutable_initWithString_attributes = (typeof(_original_mutable_initWithString_attributes))OBReplaceMethodImplementation(NSClassFromString(@"NSConcreteMutableAttributedString"), @selector(initWithString:attributes:), (IMP)_replacement_mutable_initWithString_attributes);
    _original_mutable_initWithString = (typeof(_original_mutable_initWithString))OBReplaceMethodImplementation(NSClassFromString(@"NSConcreteMutableAttributedString"), @selector(initWithString:), (IMP)_replacement_mutable_initWithString);
});
#endif


+ (BOOL)isEmptyAttributedString:(NSAttributedString *)attributedString;
{
    return (attributedString == nil || [NSString isEmptyString:attributedString.string]);
}

- (id)initWithString:(NSString *)string attributeName:(NSString *)attributeName attributeValue:(id)attributeValue;
{
    NSAttributedString *returnValue;
    NSDictionary *attributes;
    
    OBPRECONDITION(attributeName != nil);
    OBPRECONDITION(attributeValue != nil);
    
    attributes = [[NSDictionary alloc] initWithObjects:&attributeValue forKeys:&attributeName count:1];

    // May return a different object
    returnValue = [self initWithString:string attributes:attributes];

    [attributes release];

    return returnValue;
}

- (NSArray *)componentsSeparatedByString:(NSString *)separator;
{
    NSString *string;
    NSRange range, separatorRange, componentRange;
    NSMutableArray *components;

    string = [self string];
    components = [NSMutableArray array];

    range = NSMakeRange(0, [string length]);
    
    do {
        separatorRange = [string rangeOfString:separator options:0 range:range];
        if (separatorRange.length) {
            componentRange = NSMakeRange(range.location, separatorRange.location - range.location);
            range.length -= (NSMaxRange(separatorRange) - range.location);
            range.location = NSMaxRange(separatorRange);
        } else {
            componentRange = range;
            range.length = 0;
        }
        [components addObject:[self attributedSubstringFromRange:componentRange]];
    } while (separatorRange.length);

    return components;
}

- (NSSet *)valuesOfAttribute:(NSString *)attributeName inRange:(NSRange)range;
{
    NSRange effectiveRange;
    
    id singleValue = nil;
    NSMutableSet *manyValues = nil;
    
    for (NSUInteger textIndex = range.location; textIndex < NSMaxRange(range); textIndex = NSMaxRange(effectiveRange)) {
        id spanValue = [self attribute:attributeName atIndex:textIndex effectiveRange:&effectiveRange];
        if (spanValue == nil)
            spanValue = [NSNull null];
        if (manyValues)
            [manyValues addObject:spanValue];
        else if (singleValue == nil)
            singleValue = spanValue;
        else if (![singleValue isEqual:spanValue]) {
            manyValues = [NSMutableSet set];
            [manyValues addObject:singleValue];
            [manyValues addObject:spanValue];
        }
    }
    
    if (manyValues)
        return manyValues;
    else if (singleValue)
        return [NSSet setWithObject:singleValue];  // very much the common case
    else
        return [NSSet set];
}

- (BOOL)hasAttribute:(NSString *)attributeName;
{
    NSUInteger location = 0, length = [self length];
    
    while (location < length) {
        NSRange effectiveRange;
        if ([self attribute:attributeName atIndex:location effectiveRange:&effectiveRange])
            return YES;
        location = NSMaxRange(effectiveRange);
    }
    
    return NO;
}

@end
