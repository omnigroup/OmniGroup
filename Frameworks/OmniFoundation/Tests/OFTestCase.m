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
    SEL method;
    NSMethodSignature *methodSignature;
    SenTestSuite *suite;
    unsigned caseIndex, caseCount;
    
    method = NSSelectorFromString([methodName stringByAppendingString:@":"]);
    if (method == NULL || ![self instancesRespondToSelector:method]) {
        [NSException raise:NSGenericException format:@"Unimplemented method -[%@ %@:] referenced in test case file", [self description], methodName];
    }
    methodSignature = [self instanceMethodSignatureForSelector:method];
    if (!methodSignature ||
        [methodSignature numberOfArguments] != 3 || /* 3 args: self, _cmd, and the test case */
        strcmp([methodSignature methodReturnType], "v") != 0) {
        [NSException raise:NSGenericException format:@"Method -[%@ %@:] referenced in test case file has incorrect signature", [self description], methodName];
    }
    
    suite = [[SenTestSuite alloc] initWithName:methodName];
    [suite autorelease];
    
    caseCount = [testCases count];
    for(caseIndex = 0; caseIndex < caseCount; caseIndex ++) {
        id testArguments = [testCases objectAtIndex:caseIndex];
        NSInvocation *testInvocation;
        OFTestCase *testCase;
        
        testInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [testInvocation setSelector:method];
        [testInvocation setArgument:&testArguments atIndex:2];
        [testInvocation retainArguments];
        
        testCase = [self testCaseWithInvocation:testInvocation];
        [suite addTest:testCase];
    }
    
    return suite;
} 

@end
