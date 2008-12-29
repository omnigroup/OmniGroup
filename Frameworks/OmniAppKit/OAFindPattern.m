// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAFindPattern.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@implementation OAFindPattern
 
- initWithString:(NSString *)aString ignoreCase:(BOOL)ignoreCase wholeWord:(BOOL)isWholeWord backwards:(BOOL)backwards;
{
    [super init];
    pattern = [aString retain];
    optionsMask = 0;
    if (ignoreCase)
        optionsMask |= NSCaseInsensitiveSearch;
    if (backwards)
        optionsMask |= NSBackwardsSearch;
    wholeWord = isWholeWord;
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
    [pattern release];
    [replacementString release];
    [super dealloc];
}

//
// OAFindPattern protocol
//

- (BOOL)findInString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;
{
    return [self findInRange:NSMakeRange(0, [aString length]) ofString:aString foundRange:rangePtr];
}

- (BOOL)findInRange:(NSRange)range ofString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;
{
    NSCharacterSet *wordSet;
    unsigned int stringLength;
    NSRange foundRange;

    if (aString == nil)
        return NO; // Patterns never match nil input strings
    wordSet = [NSCharacterSet letterCharacterSet];
    stringLength = [aString length];
    
    while (1) {
        foundRange = [aString rangeOfString:pattern options:optionsMask range:range];
        if (foundRange.length == 0)
            return NO;
        if (!wholeWord)
            break;

        if ((foundRange.location != 0 && [wordSet characterIsMember:[aString characterAtIndex:foundRange.location - 1]]) ||
            (NSMaxRange(foundRange) != stringLength && [wordSet characterIsMember:[aString characterAtIndex:NSMaxRange(foundRange)]])) {
            if (optionsMask & NSBackwardsSearch)
                range.length = foundRange.location - range.location;
            else {
                range.length = NSMaxRange(range) - NSMaxRange(foundRange);
                range.location = NSMaxRange(foundRange);
            }
            continue;
        }
        break;
    }
    if (rangePtr != NULL)
        *rangePtr = foundRange;
    return YES;
}

- (NSString *)replacementStringForLastFind;
{
    return replacementString;
}

// Allow the caller to inspect the contents of the find pattern (very helpful when they cannot efficiently reduce their target content to a string)

- (NSString *)findPattern;
{
    return pattern;
}

- (BOOL)isCaseSensitive;
{
    return (optionsMask & NSCaseInsensitiveSearch) == 0;
}

- (BOOL)isBackwards;
{
    return (optionsMask & NSBackwardsSearch) != 0;
}

- (BOOL)isRegularExpression;
{
    return NO;
}

@end
