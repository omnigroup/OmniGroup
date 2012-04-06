// Copyright 2002-2005, 2007-2008, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMultipleNumberFormatter.h>

#import <OmniFoundation/NSObject-OFExtensions.h>

RCS_ID("$Id$");

@interface OFMultipleNumberFormatter (Private)
@end

@implementation OFMultipleNumberFormatter

static NSCharacterSet *nonDigitOrSpaceSet;

+ (void)initialize;
{
    OBINITIALIZE;
    
    nonDigitOrSpaceSet = [[[NSCharacterSet characterSetWithCharactersInString:@"0123456789 "] invertedSet] retain];
}

- (NSString *)stringForObjectValue:(id)object;
{
    return [object componentsJoinedByString:@" "];
}

- (BOOL)getObjectValue:(out id *)anObject forString:(NSString *)string errorDescription:(out NSString **)error;
{    
    NSEnumerator *enumerator;
    NSMutableArray *result;
    
    if (!anObject)
        return YES;

    if (![string length]) {
        *anObject = nil;
        return YES;
    }

    if ([string rangeOfCharacterFromSet:nonDigitOrSpaceSet].length) {
        if (error)
            *error = NSLocalizedStringFromTableInBundle(@"Only enter numbers separated by spaces.", @"OmniFoundation", [OFMultipleNumberFormatter bundle], @"formatter input error");
        return NO;
    }
    
    enumerator = [[string componentsSeparatedByString:@" "] objectEnumerator];
    result = [NSMutableArray array];
    while ((string = [enumerator nextObject]))
        [result addObject:[NSNumber numberWithInt:[string intValue]]];
    *anObject = result;
    return YES;
}

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;
{
    NSMutableString *newEditingString = nil;
    NSRange range;
    
    while ((range = [partialString rangeOfCharacterFromSet:nonDigitOrSpaceSet]).length) {
        if (newEditingString == nil)
            newEditingString = [[partialString mutableCopy] autorelease];
        [newEditingString deleteCharactersInRange:range];
    }

    if (newEditingString == nil)
        return YES;

    *newString = newEditingString;
    return NO;
}

@end

@implementation OFMultipleNumberFormatter (Private)
@end
