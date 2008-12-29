// Copyright 1998-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFStateFormatter.h>

#import <OmniFoundation/NSObject-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFStateFormatter

// first letters must be in groups together, but alphabeticalness doesn't matter
static char *validStates[] = {
    "AA", "AE", "AP", "AL", "AK", "AS", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FM",
    "FL", "GA", "GU", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MH", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND",
    "MP", "OH", "OK", "OR", "PW", "PA", "PR", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
    "VI", "VA", "WA", "WV", "WI", "WY", NULL
};

- (NSString *)stringForObjectValue:(id)object;
{
    return object;
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error;
{
    if (!anObject)
        return YES;

    if (![string length]) {
        *anObject = nil;
    } else if ([string length] != 2) {
        if (error)
            *error = NSLocalizedStringFromTableInBundle(@"That is not a valid state abbreviation.", @"OmniFoundation", [OFStateFormatter bundle], @"formatter input error");
        *anObject = nil;
        return NO;
    } else {
        *anObject = string;
    }
    return YES;
}

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;
{
    char first, second = 0;
    char **ptr;
    BOOL changed = NO;

    if ([partialString length] > 0) {
        first = (char)[partialString characterAtIndex:0];
        if (islower(first)) {
            first = toupper(first);
            changed = YES;
        }

        for (ptr = validStates; *ptr; ptr++) {
            if (**ptr == first)
                break;                
        }
        if (!*ptr) {
            *newString = @"";
            return NO;
        }
    } else
        return YES;

    if ([partialString length] > 1) {
        second = (char)[partialString characterAtIndex:1];
        if (islower(second)) {
            second = toupper(second);
            changed = YES;
        }
        for (; *ptr && (**ptr == first); ptr++) {
            if ((*ptr)[1] == second)
                break;
        }
        if (!*ptr || (**ptr != first)) {
            *newString = [NSString stringWithCString:&first length:1];
            return NO;
        }
    }

    if (changed || ([partialString length] > 2)) {
        char new[3];

        new[0] = first;
        new[1] = second;
        new[2] = 0;
        *newString = [NSString stringWithCString:new];
        return NO;
    }
    return YES;
}

@end
