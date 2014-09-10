// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OmniBase.h>

#import "OFTestCase.h"

#import "OFOrderedMutableDictionary.h"

RCS_ID("$Id$");

@interface OFOrderedMutableDictionaryTest : OFTestCase

@end

@implementation OFOrderedMutableDictionaryTest

- (void)testSetObjectWithKeyAndIndexOutOfBounds;
{
    OFOrderedMutableDictionary *dict = [OFOrderedMutableDictionary dictionaryWithObjectsAndKeys:@0, @"foo", @1, @"bar", nil];
    XCTAssertThrows([dict setObject:@2 index:100 forKey:@"baz"], @"Expected exception inserting object past end of ordered dictionary");
}

@end
