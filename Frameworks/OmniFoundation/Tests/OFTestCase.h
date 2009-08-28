// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OBTestCase.h"

@interface OFTestCase : OBTestCase

+ (SenTest *)dataDrivenTestSuite;
+ (SenTest *)testSuiteForMethod:(NSString *)methodName cases:(NSArray *)testCases;
+ (SenTest *)testSuiteNamed:(NSString *)suiteName usingSelector:(SEL)testSelector cases:(NSArray *)testCases;

@end

extern void OFDiffData(SenTestCase *testCase, NSData *expected, NSData *actual);

#define OFDataShouldBeEqual(expected,actual) \
do { \
    BOOL dataEqual = [expected isEqual:actual]; \
    if (!dataEqual) { \
        OFDiffData(self, expected, actual); \
        should(dataEqual); \
    } \
} while (0)
