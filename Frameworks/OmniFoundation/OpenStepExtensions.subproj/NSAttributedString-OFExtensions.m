// Copyright 1997-2005,2007, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSAttributedString-OFExtensions.h>
#import <Foundation/Foundation.h>

RCS_ID("$Id$")

@implementation NSAttributedString (OFExtensions)

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
