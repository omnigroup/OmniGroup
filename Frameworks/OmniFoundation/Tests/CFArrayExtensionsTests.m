// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface CFArrayExtensionsTests :  OFTestCase
@end

@implementation CFArrayExtensionsTests

- (void)testPointerArray;
{
    NSMutableArray *array = OFCreateNonOwnedPointerArray();
    [array addObject:(id)0xdeadbeef];
    should([array count] == 1);
    should([array objectAtIndex:0] == (id)0xdeadbeef);
    should([array indexOfObject:(id)0xdeadbeef] == 0);
    
    // This crashes; -[NSArray description] isn't the same, apparently
    //NSString *description = [array description];
    NSString *description = [(id)CFCopyDescription(array) autorelease];
    
    should([description containsString:@"0xdeadbeef"]);
    [array release];
}

- (void)testIntegerArray;
{
    NSMutableArray *array = OFCreateIntegerArray();
    [array addObject:(id)6060842];
    should([array count] == 1);
    should([array objectAtIndex:0] == (id)6060842);
    should([array indexOfObject:(id)6060842] == 0);

    // This crashes; -[NSArray description] isn't the same, apparently
    //NSString *description = [array description];
    NSString *description = [(id)CFCopyDescription(array) autorelease];
    
    should([description containsString:@"6060842"]);
    [array release];
}

@end
