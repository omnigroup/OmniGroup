// Copyright 2005-2008, 2010, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFErrors.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFErrorExtensionTests : OFTestCase
@end

enum {
    // Zero typically means no error
    FooError = 1,
    BarError,
};

@implementation OFErrorExtensionTests

- (void)testSimpleError;
{
    __autoreleasing NSError *error = nil;
    
    OFError(&error, FooError, @"some reason", nil);
    XCTAssertTrue(error != nil);
    XCTAssertEqualObjects([error domain], @"com.omnigroup.framework.OmniFoundation.ErrorDomain");
    XCTAssertTrue([error code] == FooError);
    XCTAssertEqualObjects([error localizedDescription], @"some reason");
}

- (void)testUnderlyingError;
{
    __autoreleasing NSError *error = nil;
    
    OFErrorWithInfo(&error, FooError, nil, nil, nil);
    OFErrorWithInfo(&error, BarError, nil, nil, nil);
    
    XCTAssertTrue(error != nil);
    XCTAssertEqualObjects([error domain], @"com.omnigroup.framework.OmniFoundation.ErrorDomain");
    XCTAssertTrue([error code] == BarError);

    XCTAssertTrue([error userInfo] != nil);
    XCTAssertTrue([[error userInfo] count] == 2);
    XCTAssertTrue([[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] != nil);
    
    NSError *underlyingError = [[error userInfo] valueForKey:NSUnderlyingErrorKey];
    XCTAssertTrue(underlyingError != nil);
    XCTAssertEqualObjects([underlyingError domain], @"com.omnigroup.framework.OmniFoundation.ErrorDomain");
    XCTAssertTrue([underlyingError code] == FooError);
}

// First key is special in how it is handled
- (void)testSingleKeyValue;
{
    __autoreleasing NSError *error = nil;
    OFErrorWithInfo(&error, FooError, nil/*description*/, nil/*suggestion*/, @"MyKey", @"MyValue", nil);
    XCTAssertTrue([[error userInfo] count] == 2);
    XCTAssertTrue([[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] != nil);
    XCTAssertTrue([[[error userInfo] valueForKey:@"MyKey"] isEqual:@"MyValue"]);
}

- (void)testMultipleKeyValue;
{
    __autoreleasing NSError *error = nil;
    OFErrorWithInfo(&error, FooError, nil/*description*/, nil/*suggestion*/, @"MyKey1", @"MyValue1", @"MyKey2", @"MyValue2", nil);
    XCTAssertTrue([[error userInfo] count] == 3);
    XCTAssertTrue([[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] != nil);
    XCTAssertTrue([[[error userInfo] valueForKey:@"MyKey1"] isEqual:@"MyValue1"]);
    XCTAssertTrue([[[error userInfo] valueForKey:@"MyKey2"] isEqual:@"MyValue2"]);
}

- (void)testFileAndLineNumber;
{
    __autoreleasing NSError *error = nil;
    OFErrorWithInfo(&error, FooError, nil, nil, nil);
    NSString *expectedFileAndLineNumber = [NSString stringWithFormat:@"%s:%d", __FILE__, __LINE__-1];
    
    XCTAssertTrue([[[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] isEqual:expectedFileAndLineNumber]);
}

- (void)testCausedByUserCancelling_Not;
{
    __autoreleasing NSError *error = nil;
    OFErrorWithInfo(&error, FooError, nil, nil, nil);
    XCTAssertFalse([error causedByUserCancelling]);
}

- (void)testCausedByUserCancelling_Direct;
{
    __autoreleasing NSError *error = nil;
    OBUserCancelledError(&error);
    XCTAssertTrue([error causedByUserCancelling]);
}

- (void)testCausedByUserCancelling_Indirect;
{
    __autoreleasing NSError *error = nil;
    OBUserCancelledError(&error);
    OFErrorWithInfo(&error, BarError, nil, nil, nil);
    XCTAssertTrue([error causedByUserCancelling]);
}

@end
