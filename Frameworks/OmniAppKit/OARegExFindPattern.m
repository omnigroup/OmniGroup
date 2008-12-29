// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OARegExFindPattern.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OARegExFindPattern

- initWithString:(NSString *)aString selectedSubexpression:(int)subexpression backwards:(BOOL)backwards;
{
    [super init];
    regularExpression = [[OFRegularExpression alloc] initWithString:aString];
    selectedSubexpression = subexpression;
    isBackwards = backwards;
    return self;
}

- (void)setReplacementString:(NSString *)aString;
{
    if (aString != replacementString) {
        [replacementString release];
        replacementString = [aString retain];
    }
}

- (void)dealloc;
{
    [regularExpression release];
    [lastMatch release];
    [replacementString release];
    [super dealloc];
}

//
// OAFindPattern protocol
//

- (BOOL)findInString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;
{
    OFRegularExpressionMatch *match;
    
    [lastMatch release];
    lastMatch = nil;
    
    if (aString == nil)
        return NO;

    if (!(match = [regularExpression matchInString:aString]))
        return NO;
        
    if (isBackwards) {
        OFRegularExpressionMatch *next;

        while ((next = [match nextMatch]))
            match = next;
    }
        
    if (rangePtr != NULL) {
        if (selectedSubexpression == SELECT_FULL_EXPRESSION)
            *rangePtr = [match matchRange];
        else
            *rangePtr = [match rangeOfSubexpressionAtIndex:selectedSubexpression];
    }
    
    lastMatch = [match retain];
    return YES;
}

- (BOOL)findInRange:(NSRange)range ofString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;
{
    BOOL result;
    
    if (aString == nil)
        return NO;

    result = [self findInString:[aString substringWithRange:range] foundRange:rangePtr];
    if (rangePtr != NULL)
        rangePtr->location += range.location;
    return result;
}

- (NSString *)replacementStringForLastFind;
{
    OFStringScanner *scanner;
    NSMutableString *interpolatedString = [NSMutableString string];
    
    scanner = [[OFStringScanner alloc] initWithString:replacementString];
    while (scannerHasData(scanner)) {
        unsigned int subexpressionIndex = 0;
        BOOL readNumber = NO;
        unichar c;

        [interpolatedString appendString:[scanner readFullTokenWithDelimiterCharacter:'\\']];
        if (scannerReadCharacter(scanner) != '\\')
            break;
        
        c = scannerPeekCharacter(scanner);
        if ((c >= '0') && (c <= '9')) {
            scannerSkipPeekedCharacter(scanner);
            subexpressionIndex = (c - '0');
            readNumber = YES;
        } else if (c == '{') {
            scannerSkipPeekedCharacter(scanner);
            while ((c = scannerPeekCharacter(scanner)) && (c >= '0') && (c <= '9')) {
                scannerSkipPeekedCharacter(scanner);
                subexpressionIndex *= 10;
                subexpressionIndex += (c - '0');
                readNumber = YES;
            }
            if (c == '}')
                scannerSkipPeekedCharacter(scanner);
        } else if (c == 't') {
            scannerSkipPeekedCharacter(scanner);
            [interpolatedString appendString:@"\t"];
        } else if (c == 'n') {
            scannerSkipPeekedCharacter(scanner);
            [interpolatedString appendString:@"\n"];
        } else if (c == 'r') {
            scannerSkipPeekedCharacter(scanner);
            [interpolatedString appendString:@"\r"];
        } else if (c == '\\') {
            scannerSkipPeekedCharacter(scanner);
            [interpolatedString appendString:@"\\"];
        }
        
        if (readNumber && subexpressionIndex <= [regularExpression subexpressionCount]) {
            NSString *subString;
            
            if (subexpressionIndex)
                subString = [lastMatch subexpressionAtIndex:(subexpressionIndex - 1)];
            else	
                subString = [lastMatch matchString];
            [interpolatedString appendString:subString];
        } 
    }
    [scanner release];
    return interpolatedString;
}

// Allow the caller to inspect the contents of the find pattern (very helpful when they cannot efficiently reduce their target content to a string)

- (NSString *)findPattern;
{
    return [regularExpression patternString];
}

- (BOOL)isCaseSensitive;
{
    return NO;
}

- (BOOL)isBackwards;
{
    return isBackwards;
}

- (BOOL)isRegularExpression;
{
    return YES;
}

@end
