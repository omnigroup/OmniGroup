// Copyright 1997-2005, 2007, 2010-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRegularExpressionMatch.h>

#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/OFRegularExpression.h>

#import <OmniBase/OmniBase.h>
#include <stdlib.h>

RCS_ID("$Id$")

@interface OFRegularExpressionMatch (privateUsedByOFRegularExpression)
- initWithExpression:(OFRegularExpression *)expression inScanner:(OFStringScanner *)scanner;
@end

@interface OFRegularExpression (Search)
- (BOOL)findMatch:(OFRegularExpressionMatch *)match withScanner:(OFStringScanner *)scanner;
@end

@implementation OFRegularExpressionMatch

- (void)dealloc;
{
    [expression release];
    [scanner release];
    if (subExpressionMatches)
        free(subExpressionMatches);
    [super dealloc];
}

- (NSRange)matchRange;
{
    return matchRange;
}

- (NSString *)matchString;
{
    NSUInteger location = [scanner scanLocation];
    [scanner setScanLocation:matchRange.location];
    NSString *result = [scanner readCharacterCount:matchRange.length];
    [scanner setScanLocation:location];
    return result;
}

- (NSRange)rangeOfSubexpressionAtIndex:(NSUInteger)subexpressionIndex;
{
    return subExpressionMatches[subexpressionIndex];
}

- (NSString *)subexpressionAtIndex:(NSUInteger)subexpressionIndex;
{
    NSRange range = subExpressionMatches[subexpressionIndex];
    if (range.location == INVALID_SUBEXPRESSION_LOCATION || range.length == INVALID_SUBEXPRESSION_LOCATION)
        return nil;
        
    NSUInteger location = [scanner scanLocation];
    [scanner setScanLocation:range.location];
    NSString *result = [scanner readCharacterCount:range.length];
    [scanner setScanLocation:location];
    return result;
}

- (BOOL)findNextMatch;
{
    BOOL result = [expression findMatch:self withScanner:scanner];

    // discard scanner rewind mark from the new match because we already have created an earlier one for ourselves...
    if (result)
        [scanner discardRewindMark];
    return result;
}

- (OFRegularExpressionMatch *)nextMatch;
{
    OFRegularExpressionMatch *result = [[OFRegularExpressionMatch allocWithZone:[self zone]] initWithExpression:expression inScanner:scanner];

    // discard scanner rewind mark from the new match because we already have created an earlier one for ourselves...
    if (result)
        [scanner discardRewindMark];
    return [result autorelease];
}

- (NSString *)description;
{
    unsigned int subexpressionIndex, subexpressionCount;

    NSMutableString *result = [NSMutableString string];
    subexpressionCount = [expression subexpressionCount];
    [result appendFormat:@"Match:%lu-%lu%c", matchRange.location, NSMaxRange(matchRange)-1, subexpressionCount ? '(' : ' '];
    for (subexpressionIndex = 0; subexpressionIndex < subexpressionCount; subexpressionIndex++) {
        [result appendFormat:@"%lu-%lu%c", subExpressionMatches[subexpressionIndex].location, NSMaxRange(subExpressionMatches[subexpressionIndex]) - 1, subexpressionIndex == subexpressionCount - 1 ? ')' : ','];
    }
    return result;
}

@end

@implementation OFRegularExpressionMatch (privateUsedByOFRegularExpression)

- initWithExpression:(OFRegularExpression *)anExpression inScanner:(OFStringScanner *)aScanner;
{
    if (!(self = [super init]))
        return nil;

    expression = [anExpression retain];
    scanner = [aScanner retain];
    
    unsigned int matchCount;
    if ((matchCount = [expression subexpressionCount])) {
        subExpressionMatches = OBAllocateCollectable(sizeof(NSRange) * matchCount, 0);
    } else
        subExpressionMatches = NULL;

    if (![expression findMatch:self withScanner:scanner]) {
        [self release];
        return nil;
    }
    return self;
}

@end
