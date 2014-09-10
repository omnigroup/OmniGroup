// Copyright 1997-2005, 2007-2008, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFDictionary-OFExtensions.h>

#import <XCTest/XCTest.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFLowerCaseTests : XCTestCase
{
}

@end

@implementation OFLowerCaseTests

- (void)testCaseInsensitiveDictionary
{
    CFMutableDictionaryRef dict;

    dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFCaseInsensitiveStringKeyDictionaryCallbacks, &kCFTypeDictionaryValueCallBacks);
    
    CFDictionaryAddValue(dict, @"foo key", @"foo value");
    XCTAssertEqualObjects((id)CFDictionaryGetValue(dict, @"FOO KEY"), @"foo value");
    XCTAssertNil((id)CFDictionaryGetValue(dict, @"FOOKEY"));
    XCTAssertEqualObjects((id)CFDictionaryGetValue(dict, @"fOo KeY"), @"foo value");

    CFRelease(dict);
}

@end
