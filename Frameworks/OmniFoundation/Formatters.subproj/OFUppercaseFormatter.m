// Copyright 1998-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUppercaseFormatter.h>

RCS_ID("$Id$")

@implementation OFUppercaseFormatter

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;
{
    if (![super isPartialStringValid:partialString newEditingString:newString errorDescription:error])
        return NO;

    *newString = [partialString uppercaseString];
    return [*newString isEqualToString:partialString];
}

@end
