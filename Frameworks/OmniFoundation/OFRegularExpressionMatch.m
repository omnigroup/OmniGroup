// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRegularExpressionMatch.h>

#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <Foundation/NSTextCheckingResult.h>
#import <Foundation/NSRegularExpression.h>

RCS_ID("$Id$")

@implementation OFRegularExpressionMatch
{    
    NSString *_string; // Always set
    OFStringScanner *_stringScanner; // Might be set if we are operating with a scanner
}

- initWithTextCheckingResult:(NSTextCheckingResult *)textCheckingResult string:(NSString *)string;
{
    OBPRECONDITION(textCheckingResult);
    OBPRECONDITION(textCheckingResult.resultType == NSTextCheckingTypeRegularExpression);
    OBPRECONDITION(textCheckingResult.regularExpression);
    OBPRECONDITION(string);
    OBPRECONDITION(NSMaxRange(textCheckingResult.range) <= [string length]);
    
    if (!(self = [super init]))
        return nil;
    
    _textCheckingResult = [textCheckingResult retain];
    _string = [string copy];
    
    return self;
}

- initWithTextCheckingResult:(NSTextCheckingResult *)textCheckingResult stringScanner:(OFStringScanner *)stringScanner;
{
    OBPRECONDITION(stringScanner);
    
    if (!(self = [self initWithTextCheckingResult:textCheckingResult string:stringScanner.string]))
        return nil;
    
    _stringScanner = [stringScanner retain];
    
    return self;
}

- (void)dealloc;
{
    [_textCheckingResult release];
    [_string release];
    [_stringScanner release];
    [super dealloc];
}

- (NSRange)matchRange;
{
    return _textCheckingResult.range;
}

- (NSString *)matchString;
{
    return [_string substringWithRange:_textCheckingResult.range];
}

- (NSString *)captureGroupAtIndex:(NSUInteger)captureGroupIndex;
{
    OBPRECONDITION(captureGroupIndex + 1 < [_textCheckingResult numberOfRanges]);
    
    NSRange captureRange = [_textCheckingResult rangeAtIndex:captureGroupIndex + 1];
    if (captureRange.location == NSNotFound)
        // The capture group was optional and not matched
        return nil;
    
    return [_string substringWithRange:captureRange];
}

- (NSRange)rangeOfCaptureGroupAtIndex:(NSUInteger)captureGroupIndex;
{
    OBPRECONDITION(captureGroupIndex + 1 < [_textCheckingResult numberOfRanges]);
    return [_textCheckingResult rangeAtIndex:captureGroupIndex + 1];
}

- (OFRegularExpressionMatch *)nextMatch;
{
    NSRange matchRange = self.matchRange;
    NSRange searchRange;
    searchRange.location = matchRange.location + matchRange.length;
    searchRange.length = [_string length] - searchRange.location;
    
    if (_stringScanner)
        return [_textCheckingResult.regularExpression matchInScanner:_stringScanner];
    
    return [_textCheckingResult.regularExpression of_firstMatchInString:_string range:searchRange];
}

- (NSString *)description;
{
    NSMutableString *result = [NSMutableString string];

    NSUInteger rangeCount = [_textCheckingResult numberOfRanges];
    OBASSERT(rangeCount > 0, "range zero is the full range");
    
    NSRange fullRange = _textCheckingResult.range;
    [result appendFormat:@"Match:%lu-%lu", fullRange.location, NSMaxRange(fullRange)-1];

    BOOL hasCaptures = (rangeCount > 1);
    if (hasCaptures) {
        [result appendString:@"("];
        
        for (NSUInteger rangeIndex = 1; rangeIndex < rangeCount; rangeIndex++) {
            if (rangeIndex != 1)
                [result appendString:@","];
            
            NSRange captureRange = [_textCheckingResult rangeAtIndex:rangeIndex];
            [result appendFormat:@"%lu-%lu", captureRange.location, NSMaxRange(captureRange) - 1];
        }
        
        [result appendString:@")"];
    }
    
    
    return result;
}


@end
