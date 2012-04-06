// Copyright 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OBErrorTests.h"

#import <OmniBase/NSError-OBExtensions.h>

RCS_ID("$Id$")

@interface OBErrorTestsRecoveryAttempter : NSObject
@end
@implementation OBErrorTestsRecoveryAttempter
- (void)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex delegate:(id)delegate didRecoverSelector:(SEL)didRecoverSelector contextInfo:(void *)contextInfo;
{
    OBRejectUnusedImplementation(self, _cmd);
}
- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex;
{
    OBRejectUnusedImplementation(self, _cmd);
}
@end

@implementation OBErrorTests

static void _testRoundTrip(OBErrorTests *self, NSError *error1)
{
    NSDictionary *plist1 = [error1 toPropertyList];
    NSError *error2 = [[NSError alloc] initWithPropertyList:plist1];
    NSDictionary *plist2 = [error2 toPropertyList];
    
    STAssertEqualObjects(plist1, plist2, @"second convertion should be the same as the first");
}

- (void)testToPropertyList;
{
    NSError *error = nil;
    
    OBErrorWithErrno(&error, ENOENT, "open", @"foozle", @"Unable to open");
    NSDictionary *plist = [error toPropertyList];
    
    STAssertEqualObjects([plist objectForKey:@"domain"], NSPOSIXErrorDomain, @"domain should match");
    STAssertEqualObjects([plist objectForKey:@"code"], [NSNumber numberWithInt:2], @"code should match");
    
    NSDictionary *userInfo = [plist objectForKey:@"userInfo"];
    STAssertNotNil(userInfo, @"should have user info");
    
    STAssertEqualObjects([userInfo objectForKey:NSLocalizedDescriptionKey], @"Unable to open", @"Description should match");
    STAssertEqualObjects([userInfo objectForKey:NSLocalizedFailureReasonErrorKey], @"open: foozle: No such file or directory", @"Failure reason should match");
    
    _testRoundTrip(self, error);
}

- (void)testPropertyListSet;
{
    NSSet *set = [NSSet setWithObjects:@"a", @"b", @"c", nil];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:set forKey:@"set"];
    NSError *error = [NSError errorWithDomain:@"Domain" code:1 userInfo:userInfo];
    NSDictionary *plist = [error toPropertyList];
    
    userInfo = [plist objectForKey:@"userInfo"];
    NSArray *array = [userInfo objectForKey:@"set"];
    STAssertTrue([array isKindOfClass:[NSArray class]], @"Sets get transformed to arrays since NSSet isn't a plist type");
    STAssertTrue([array count] == 3, @"right number of objects");
    STAssertTrue([array indexOfObject:@"a"] != NSNotFound, @"contains right objects");
    STAssertTrue([array indexOfObject:@"b"] != NSNotFound, @"contains right objects");
    STAssertTrue([array indexOfObject:@"c"] != NSNotFound, @"contains right objects");

    _testRoundTrip(self, error);
}

- (void)testPropertyListUnderlyingError;
{
    NSDictionary *innerUserInfo = [NSDictionary dictionaryWithObject:@"value" forKey:@"key"];
    NSError *innerError = [NSError errorWithDomain:@"InnerDomain" code:1 userInfo:innerUserInfo];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:innerError forKey:NSUnderlyingErrorKey];
    NSError *error = [NSError errorWithDomain:@"Domain" code:2 userInfo:userInfo];
    NSDictionary *plist = [error toPropertyList];
    
    NSDictionary *underlyingPlist = [[plist objectForKey:@"userInfo"] objectForKey:NSUnderlyingErrorKey];
    STAssertNotNil(underlyingPlist, @"should have converted underlying error to a property list");
    STAssertEqualObjects([underlyingPlist objectForKey:@"domain"], @"InnerDomain", @"domain should match");
    STAssertEqualObjects([underlyingPlist objectForKey:@"code"], [NSNumber numberWithInt:1], @"code should match");
    STAssertTrue([underlyingPlist objectForKey:@"userInfo"] != innerUserInfo, @"shouldn't have just reused the object");
    STAssertEqualObjects([underlyingPlist objectForKey:@"userInfo"], innerUserInfo, @"userInfo should match");

    _testRoundTrip(self, error);
}

- (void)testPropertyListRecoveryAttempter;
{
    OBErrorTestsRecoveryAttempter *recoveryAttempter = [[OBErrorTestsRecoveryAttempter alloc] init];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:recoveryAttempter forKey:NSRecoveryAttempterErrorKey];
    NSError *error = [NSError errorWithDomain:@"Domain" code:1 userInfo:userInfo];
    NSDictionary *plist = [error toPropertyList];

    userInfo = [plist objectForKey:@"userInfo"];
    STAssertNotNil(userInfo, @"should convert the userInfo");
    STAssertTrue([userInfo count] == 1, @"the recovery attempter be converted");
    STAssertTrue([[userInfo objectForKey:NSRecoveryAttempterErrorKey] isKindOfClass:[NSString class]], @"should be converted to a string");
    
    // We can't round trip this error since we can't decode the recovery attempter and should drop it on decode.
    NSError *error2 = [[[NSError alloc] initWithPropertyList:plist] autorelease];
    STAssertNil([[error2 userInfo] objectForKey:NSRecoveryAttempterErrorKey], @"error recovery should be dropped when making a new error");
}

@end
