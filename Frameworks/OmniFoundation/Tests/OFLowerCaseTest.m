// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFDictionary-OFExtensions.h>

#import <SenTestingKit/SenTestingKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFLowerCaseTests : SenTestCase
{
}

@end

@implementation OFLowerCaseTests

- (void)testCaseInsensitiveDictionary
{
    CFMutableDictionaryRef dict;

    dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFCaseInsensitiveStringKeyDictionaryCallbacks, &kCFTypeDictionaryValueCallBacks);
    
    CFDictionaryAddValue(dict, @"foo key", @"foo value");
    STAssertEqualObjects((id)CFDictionaryGetValue(dict, @"FOO KEY"), @"foo value", nil);
    STAssertNil((id)CFDictionaryGetValue(dict, @"FOOKEY"), nil);
    STAssertEqualObjects((id)CFDictionaryGetValue(dict, @"fOo KeY"), @"foo value", nil);

    CFRelease(dict);
}

@end
