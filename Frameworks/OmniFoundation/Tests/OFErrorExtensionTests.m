// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

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
    NSError *error = nil;
    
    OBError(&error, FooError, @"some reason");
    should(error != nil);
    shouldBeEqual([error domain], @"com.omnigroup.framework.OmniFoundation.UnitTests");
    should([error code] == FooError);
    shouldBeEqual([error localizedDescription], @"some reason");
}

- (void)testUnderlyingError;
{
    NSError *error = nil;
    
    OBErrorWithInfo(&error, FooError, nil);
    OBErrorWithInfo(&error, BarError, nil);
    
    should(error != nil);
    shouldBeEqual([error domain], @"com.omnigroup.framework.OmniFoundation.UnitTests");
    should([error code] == BarError);

    should([error userInfo] != nil);
    should([[error userInfo] count] == 2);
    should([[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] != nil);
    
    NSError *underlyingError = [[error userInfo] valueForKey:NSUnderlyingErrorKey];
    should(underlyingError != nil);
    shouldBeEqual([underlyingError domain], @"com.omnigroup.framework.OmniFoundation.UnitTests");
    should([underlyingError code] == FooError);
}

// First key is special in how it is handled
- (void)testSingleKeyValue;
{
    NSError *error = nil;
    OBErrorWithInfo(&error, FooError, @"MyKey", @"MyValue", nil);
    should([[error userInfo] count] == 2);
    should([[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] != nil);
    should([[[error userInfo] valueForKey:@"MyKey"] isEqual:@"MyValue"]);
}

- (void)testMultipleKeyValue;
{
    NSError *error = nil;
    OBErrorWithInfo(&error, FooError, @"MyKey1", @"MyValue1", @"MyKey2", @"MyValue2", nil);
    should([[error userInfo] count] == 3);
    should([[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] != nil);
    should([[[error userInfo] valueForKey:@"MyKey1"] isEqual:@"MyValue1"]);
    should([[[error userInfo] valueForKey:@"MyKey2"] isEqual:@"MyValue2"]);
}

- (void)testFileAndLineNumber;
{
    NSError *error = nil;
    OBErrorWithInfo(&error, FooError, nil);
    NSString *expectedFileAndLineNumber = [NSString stringWithFormat:@"%s:%d", __FILE__, __LINE__-1];
    
    should([[[error userInfo] valueForKey:OBFileNameAndNumberErrorKey] isEqual:expectedFileAndLineNumber]);
}

- (void)testCausedByUserCancelling_Not;
{
    NSError *error = nil;
    OBErrorWithInfo(&error, FooError, nil);
    shouldnt([error causedByUserCancelling]);
}

- (void)testCausedByUserCancelling_Direct;
{
    NSError *error = nil;
    OBErrorWithInfo(&error, FooError, OBUserCancelledActionErrorKey, [NSNumber numberWithBool:YES], nil);
    should([error causedByUserCancelling]);
}

- (void)testCausedByUserCancelling_Indirect;
{
    NSError *error = nil;
    OBErrorWithInfo(&error, FooError, OBUserCancelledActionErrorKey, [NSNumber numberWithBool:YES], nil);
    OBErrorWithInfo(&error, BarError, nil);
    should([error causedByUserCancelling]);
}

@end
