// Copyright 2019 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFMultiValueDictionary.h>

RCS_ID("$Id$");

@interface OFMultiValueDictionaryTests : OFTestCase
@end

@implementation OFMultiValueDictionaryTests

/// Regression test for <bug:///172726> (iOS-OmniFocus Blocks User: 3.2.1 crash on launch [OFMultiValueDictionary copyWithZone:])
- (void)testDictionaryCopyable;
{
    OFMultiValueDictionary *original = [[OFMultiValueDictionary alloc] init];
    XCTAssertNoThrow([original copy]);
}

@end
