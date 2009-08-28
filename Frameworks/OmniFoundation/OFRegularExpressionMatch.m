// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRegularExpressionMatch.h>

#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/OFRegularExpression.h>

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
        NSZoneFree([self zone], subExpressionMatches);
    [super dealloc];
}

- (NSRange)matchRange;
{
    return matchRange;
}

- (NSString *)matchString;
{
    NSString *result;
    unsigned int location;

    location = [scanner scanLocation];
    [scanner setScanLocation:matchRange.location];
    result = [scanner readCharacterCount:matchRange.length];
    [scanner setScanLocation:location];
    return result;
}

- (NSRange)rangeOfSubexpressionAtIndex:(unsigned int)subexpressionIndex;
{
    return subExpressionMatches[subexpressionIndex];
}

- (NSString *)subexpressionAtIndex:(unsigned int)subexpressionIndex;
{
    NSString *result;
    NSRange range = subExpressionMatches[subexpressionIndex];
    unsigned int location;

    if (range.location == INVALID_SUBEXPRESSION_LOCATION || range.length == INVALID_SUBEXPRESSION_LOCATION)
        return nil;
        
    location = [scanner scanLocation];
    [scanner setScanLocation:range.location];
    result = [scanner readCharacterCount:range.length];
    [scanner setScanLocation:location];
    return result;
}

- (BOOL)findNextMatch;
{
    BOOL result;
    
    result = [expression findMatch:self withScanner:scanner];

    // discard scanner rewind mark from the new match because we already have created an earlier one for ourselves...
    if (result)
        [scanner discardRewindMark];
    return result;
}

- (OFRegularExpressionMatch *)nextMatch;
{
    OFRegularExpressionMatch *result;

    result = [[OFRegularExpressionMatch allocWithZone:[self zone]] initWithExpression:expression inScanner:scanner];

    // discard scanner rewind mark from the new match because we already have created an earlier one for ourselves...
    if (result)
        [scanner discardRewindMark];
    return [result autorelease];
}

- (NSString *)description;
{
    NSMutableString *result;
    unsigned int subexpressionIndex, subexpressionCount;

    result = [NSMutableString string];
    subexpressionCount = [expression subexpressionCount];
    [result appendFormat:@"Match:%d-%d%c", matchRange.location, NSMaxRange(matchRange)-1, subexpressionCount ? '(' : ' '];
    for (subexpressionIndex = 0; subexpressionIndex < subexpressionCount; subexpressionIndex++) {
        [result appendFormat:@"%d-%d%c", subExpressionMatches[subexpressionIndex].location, NSMaxRange(subExpressionMatches[subexpressionIndex]) - 1, subexpressionIndex == subexpressionCount - 1 ? ')' : ','];
    }
    return result;
}

@end

@implementation OFRegularExpressionMatch (privateUsedByOFRegularExpression)

- initWithExpression:(OFRegularExpression *)anExpression inScanner:(OFStringScanner *)aScanner;
{
    unsigned int matchCount;
    
    if (![super init])
        return nil;

    expression = [anExpression retain];
    scanner = [aScanner retain];
    if ((matchCount = [expression subexpressionCount]))
        subExpressionMatches = NSZoneMalloc([self zone], sizeof(NSRange) * matchCount);
    else
        subExpressionMatches = NULL;

    if (![expression findMatch:self withScanner:scanner]) {
        [self release];
        return nil;
    }
    return self;
}

@end
