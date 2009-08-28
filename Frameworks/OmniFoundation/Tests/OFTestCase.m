// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation OFTestCase

+ (SenTest *)dataDrivenTestSuite
{
    NSString *casesPath;
    NSDictionary *allTestCases;
    NSEnumerator *methodEnumerator;
    NSString *methodName;
    SenTestSuite *suite;
    
    casesPath = [[NSBundle bundleForClass:self] pathForResource:[self description] ofType:@"tests"];
    allTestCases = [NSDictionary dictionaryWithContentsOfFile:casesPath];
    if (!allTestCases) {
        [NSException raise:NSGenericException format:@"Unable to load test cases for class %@ from path: \"%@\"", [self description], casesPath];
        return nil;
    }
    
    suite = [[SenTestSuite alloc] initWithName:[casesPath lastPathComponent]];
    [suite autorelease];
    
    methodEnumerator = [allTestCases keyEnumerator];
    while( (methodName = [methodEnumerator nextObject]) != nil ) {
        [suite addTest:[self testSuiteForMethod:methodName cases:[allTestCases objectForKey:methodName]]];
    }
    
    return suite;
}

+ (SenTest *)testSuiteForMethod:(NSString *)methodName cases:(NSArray *)testCases
{
    SEL method = NSSelectorFromString([methodName stringByAppendingString:@":"]);
    if (method == NULL || ![self instancesRespondToSelector:method]) {
        [NSException raise:NSGenericException format:@"Unimplemented method -[%@ %@:] referenced in test case file", [self description], methodName];
    }
    
    return [self testSuiteNamed:methodName usingSelector:method cases:testCases];
}

+ (SenTest *)testSuiteNamed:(NSString *)suiteName usingSelector:(SEL)testSelector cases:(NSArray *)testCases;
{
    NSMethodSignature *methodSignature = [self instanceMethodSignatureForSelector:testSelector];
    if (!methodSignature ||
        [methodSignature numberOfArguments] != 3 || /* 3 args: self, _cmd, and the test case */
        strcmp([methodSignature methodReturnType], "v") != 0) {
        [NSException raise:NSGenericException format:@"Method -[%@ %@] referenced in test case file has incorrect signature", [self description], NSStringFromSelector(testSelector)];
    }
    
    SenTestSuite *suite = [[[SenTestSuite alloc] initWithName:suiteName] autorelease];
    
    for (id testArguments in testCases) {
        NSInvocation *testInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [testInvocation setSelector:testSelector];
        [testInvocation setArgument:&testArguments atIndex:2];
        [testInvocation retainArguments];
        
        OFTestCase *testCase = [self testCaseWithInvocation:testInvocation];
        [suite addTest:testCase];
    }
    
    return suite;
} 

@end

#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>

void OFDiffData(SenTestCase *testCase, NSData *expected, NSData *actual)
{
    NSString *name = [testCase name];
    
    NSError *error = nil;
    NSString *expectedPath = [[NSFileManager defaultManager] scratchFilenameNamed:[@"expected-" stringByAppendingString:name] error:&error];
    if (!expectedPath) {
        NSLog(@"Unable to create scratch path: %@", [error toPropertyList]);
        return;
    }
    
    NSString *actualPath = [[NSFileManager defaultManager] scratchFilenameNamed:[@"actual-" stringByAppendingString:name] error:&error];
    if (!actualPath) {
        NSLog(@"Unable to create scratch path: %@", [error toPropertyList]);
        return;
    }
    
    if (![expected writeToURL:[NSURL fileURLWithPath:expectedPath] options:0 error:&error]) {
        NSLog(@"Unable to write scratch file to %@: %@", expectedPath, [error toPropertyList]);
        return;
    }
    if (![actual writeToURL:[NSURL fileURLWithPath:actualPath] options:0 error:&error]) {
        NSLog(@"Unable to write scratch file to %@: %@", actualPath, [error toPropertyList]);
        return;
    }
    
    NSLog(@"Diffs:\nopendiff '%@' '%@'", expectedPath, actualPath);
    NSTask *diffTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/diff" arguments:[NSArray arrayWithObjects:@"-u", expectedPath, actualPath, nil]];
    [diffTask waitUntilExit]; // result should be 1 if they are different, so not worth checking
}

