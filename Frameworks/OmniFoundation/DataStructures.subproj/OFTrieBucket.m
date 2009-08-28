// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTrieBucket.h>

RCS_ID("$Id$")

@implementation OFTrieBucket

- (void)setRemainingLower:(unichar *)lower upper:(unichar *)upper length:(NSUInteger)aLength;
{
    unichar *old = lowerCharacters;
    if (lower && upper && aLength > 0) {
        if (lower != upper) {
            lowerCharacters = (unichar *)malloc((aLength + aLength + 2) * sizeof(unichar));
        } else {
            lowerCharacters = (unichar *)malloc((aLength + 1) * sizeof(unichar));
        }
        memmove(lowerCharacters, lower, aLength * sizeof(unichar));
        lowerCharacters[aLength] = '\0';
        if (lower != upper) {
            upperCharacters = lowerCharacters + aLength + 1;
            memmove(upperCharacters, upper, aLength * sizeof(unichar));
            upperCharacters[aLength] = '\0';
        } else {
            // Share storage
            upperCharacters = lowerCharacters;
        }
    } else {
        lowerCharacters = (unichar *)malloc(sizeof(unichar));
	*lowerCharacters = '\0';
	upperCharacters = lowerCharacters; // Share storage for efficiency
    }
    if (old)
        free(old);
}

- (void)dealloc;
{
    if (lowerCharacters)
        free(lowerCharacters);
    [super dealloc];
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    if (lowerCharacters) {
        NSUInteger length;
        unichar *ptr;

        ptr = lowerCharacters;
        length = 0;
        while (*ptr++)
	    length++;

	[debugDictionary setObject:[NSString stringWithCharacters:lowerCharacters length:length] forKey:@"lowerCharacters"];
        if (upperCharacters != lowerCharacters)
            [debugDictionary setObject:[NSString stringWithCharacters:upperCharacters length:length] forKey:@"upperCharacters"];
    }
    return debugDictionary;
}

@end
