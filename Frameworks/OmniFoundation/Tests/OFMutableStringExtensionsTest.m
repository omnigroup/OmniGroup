// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSMutableString-OFExtensions.h>

RCS_ID("$Id$");

@interface OFMutableStringExtensionsTest : OFTestCase
@end

@implementation OFMutableStringExtensionsTest

- (void)testReplace
{
    NSMutableString *reallyInterestingString = [@"MM/dd/yy HH:mm" mutableCopy];
    [reallyInterestingString replaceAllOccurrencesOfRegularExpressionString:@"[^y]*yy[^y]*" withString:@"yyyy"];
    XCTAssertEqualObjects(reallyInterestingString, @"yyyy");
}

@end
