// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATestCase.h"

#import <OmniAppKit/NSFont-OAExtensions.h>

RCS_ID("$Id$");

@interface Panose : OATestCase
@end

@implementation Panose

#if 0
// Useful for observing output, but doesn't really test anything
- (void)testPanoseExtraction
{
    for (NSString *fontName in [[NSFontManager sharedFontManager] availableFonts]) {
        NSFont *aFont = [NSFont fontWithName:fontName size:16];
        NSLog(@"%@: %@", [aFont fontName], [aFont panose1String]);
    }
}
#endif

- (void)testKnownPanose
{
    // Test a handful of fonts on the system.
    // The PANOSE strings we're testing against here aren't canonical; they're just what my copies of these fonts have. (But theoretically they won't change.)
    STAssertEqualObjects([[NSFont fontWithName:@"LucidaGrande" size:16] panose1String],
                         @"2 11 6 0 4 5 2 2 2 4", @"PANOSE-1 string doesn't match expected value");
    STAssertEqualObjects([[NSFont fontWithName:@"LucidaGrande-Bold" size:16] panose1String],
                         @"2 11 7 0 4 5 2 2 2 4", @"PANOSE-1 string doesn't match expected value");
    STAssertEqualObjects([[NSFont fontWithName:@"HiraMaruPro-W4" size:16] panose1String],
                         @"2 15 4 0 0 0 0 0 0 0", @"PANOSE-1 string doesn't match expected value");
    STAssertEqualObjects([[NSFont fontWithName:@"ZapfDingbatsITC" size:16] panose1String],
                         @"5 2 1 2 1 7 4 2 6 9", @"PANOSE-1 string doesn't match expected value");
}

@end
