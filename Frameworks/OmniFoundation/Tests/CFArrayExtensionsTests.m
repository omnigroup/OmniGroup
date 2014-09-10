// Copyright 2006-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface CFArrayExtensionsTests :  OFTestCase
@end

@implementation CFArrayExtensionsTests

#define INT_TO_ID(x) ((__bridge __unsafe_unretained id)((void *)x))
- (void)testPointerArray;
{
    NSMutableArray *array = CFBridgingRelease(OFCreateNonOwnedPointerArray());
    [array addObject:INT_TO_ID(0xdeadbeef)];
    XCTAssertTrue([array count] == 1);
    XCTAssertTrue([array objectAtIndex:0] == INT_TO_ID(0xdeadbeef));
    XCTAssertTrue([array indexOfObject:INT_TO_ID(0xdeadbeef)] == 0);
    
    // This crashes; -[NSArray description] isn't the same, apparently
    //NSString *description = [array description];
    NSString *description = CFBridgingRelease(CFCopyDescription((__bridge CFArrayRef)array));
    
    XCTAssertTrue([description containsString:@"0xdeadbeef"]);
}

@end
