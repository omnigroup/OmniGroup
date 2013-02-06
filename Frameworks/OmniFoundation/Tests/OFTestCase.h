// Copyright 2008, 2010-2013 Omni Development, Inc. All rights reserved.
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

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define OFDataShouldBeEqual(expected, actual) STAssertEquals(expected, actual, nil)
#else
extern void OFDiffData(SenTestCase *testCase, NSData *expected, NSData *actual);

#define OFDataShouldBeEqual(expected,actual) \
do { \
    BOOL dataEqual = [expected isEqual:actual]; \
    if (!dataEqual) { \
        OFDiffData(self, expected, actual); \
        STAssertTrue(dataEqual, nil); \
    } \
} while (0)

#endif

typedef BOOL (^OFDiffFilesPathFilter)(NSString *relativePath);
extern BOOL OFSameFiles(SenTestCase *testCase, NSString *path1, NSString *path2, OFDiffFilesPathFilter pathFilter); // query, not required
extern void OFDiffFiles(SenTestCase *testCase, NSString *path1, NSString *path2, OFDiffFilesPathFilter pathFilter); // fails if the files aren't the same

