// Copyright 2001-2015 Omni Development, Inc. All rights reserved.
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
{
    NSRegularExpression *_regularExpression;
    OFRegularExpressionMatch *_lastMatch;
    BOOL _isBackwards;
    NSInteger _selectedCaptureGroup;
    
    NSString *_replacementString;
}

- initWithPattern:(NSString *)pattern selectedCaptureGroup:(NSInteger)captureGroup backwards:(BOOL)backwards;
{
    if (!(self = [super init]))
        return nil;

    NSError *error;
    _regularExpression = [[NSRegularExpression alloc] initWithPattern:pattern options:0 error:&error];
    if (!_regularExpression) {
        NSLog(@"Error creating regular expression from pattern %@ --> %@", pattern, [error toPropertyList]);
    }
    
    _selectedCaptureGroup = captureGroup;
    _isBackwards = backwards;
    
    return self;
}

- (void)setReplacementString:(NSString *)aString;
{
    if (aString != _replacementString) {
        _replacementString = [aString copy];
    }
}

#pragma mark - OAFindPattern protocol

- (BOOL)findInString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;
{
    _lastMatch = nil;
    
    if (aString == nil)
        return NO;

    OFRegularExpressionMatch *match;
    if (!(match = [_regularExpression of_firstMatchInString:aString]))
        return NO;
        
    if (_isBackwards) {
        OFRegularExpressionMatch *next;
        while ((next = [match nextMatch]))
            match = next;
    }
        
    if (rangePtr != NULL) {
        if (_selectedCaptureGroup == SELECT_FULL_EXPRESSION)
            *rangePtr = [match matchRange];
        else
            *rangePtr = [match rangeOfCaptureGroupAtIndex:_selectedCaptureGroup];
    }
    
    _lastMatch = match;
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
    OBFinishPortingLater("Use the NSRegularExpression template replacement methods? These take $0 instead of \0");
    
    OFStringScanner *scanner;
    NSMutableString *interpolatedString = [NSMutableString string];
    
    scanner = [[OFStringScanner alloc] initWithString:_replacementString];
    while (scannerHasData(scanner)) {
        NSUInteger captureGroupIndex = 0;
        BOOL readNumber = NO;
        unichar c;

        [interpolatedString appendString:[scanner readFullTokenWithDelimiterCharacter:'\\']];
        if (scannerReadCharacter(scanner) != '\\')
            break;
        
        c = scannerPeekCharacter(scanner);
        if ((c >= '0') && (c <= '9')) {
            scannerSkipPeekedCharacter(scanner);
            captureGroupIndex = (c - '0');
            readNumber = YES;
        } else if (c == '{') {
            scannerSkipPeekedCharacter(scanner);
            while ((c = scannerPeekCharacter(scanner)) && (c >= '0') && (c <= '9')) {
                scannerSkipPeekedCharacter(scanner);
                captureGroupIndex *= 10;
                captureGroupIndex += (c - '0');
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
        
        if (readNumber && captureGroupIndex <= [_regularExpression numberOfCaptureGroups]) {
            NSString *subString;
            
            if (captureGroupIndex)
                subString = [_lastMatch captureGroupAtIndex:(captureGroupIndex - 1)];
            else	
                subString = [_lastMatch matchString];
            [interpolatedString appendString:subString];
        } 
    }
    return interpolatedString;
}

// Allow the caller to inspect the contents of the find pattern (very helpful when they cannot efficiently reduce their target content to a string)

- (NSString *)findPattern;
{
    return _regularExpression.pattern;
}

- (BOOL)isCaseSensitive;
{
    return NO;
}

- (BOOL)isBackwards;
{
    return _isBackwards;
}

- (BOOL)isRegularExpression;
{
    return YES;
}

@end
