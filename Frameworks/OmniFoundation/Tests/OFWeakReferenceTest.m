// Copyright 2012-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>

#import <OmniFoundation/OFWeakReference.h>

RCS_ID("$Id$");

@interface OFWeakReferenceTests :  OFTestCase
@end

@implementation OFWeakReferenceTests

- (void)testNullify;
{
    NSObject *obj = [[NSObject alloc] init];
    OFWeakReference *ref = [[OFWeakReference alloc] initWithObject:obj];
    obj = nil;
    
    XCTAssertNil(ref.object, @"Should be nullified");
}

@end
