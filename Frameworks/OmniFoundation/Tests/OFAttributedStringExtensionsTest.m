// Copyright 2005-2006, 2008, 2010, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSAttributedString-OFExtensions.h>

RCS_ID("$Id$");

@interface OFAttributedStringExtensionsTest : OFTestCase
@end

static void _testSeparate(id self, NSString *string, NSString *separator, NSArray *expectedStrings)
{
    NSAttributedString *sourceString = [[NSAttributedString alloc] initWithString:string attributes:nil];
    NSArray *components = [sourceString componentsSeparatedByString:separator];
    
    NSMutableArray *expectedAttributedStrings = [NSMutableArray array];
    for (NSString *s in expectedStrings)
        [expectedAttributedStrings addObject:[[NSAttributedString alloc] initWithString:s attributes:nil]];
    
    XCTAssertEqualObjects(components, expectedAttributedStrings);
}

@implementation OFAttributedStringExtensionsTest

- (void)testComponentsSeparatedByString;
{
    _testSeparate(self, @"bab", @"a", [NSArray arrayWithObjects:@"b", @"b", nil]);
    _testSeparate(self, @"ba", @"a", [NSArray arrayWithObjects:@"b", @"", nil]);
    _testSeparate(self, @"aaa", @"a", [NSArray arrayWithObjects:@"", @"", @"", @"", nil]);
}

@end


