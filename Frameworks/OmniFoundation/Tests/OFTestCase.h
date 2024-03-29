// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OBTestCase.h"

NS_ASSUME_NONNULL_BEGIN

@interface OFTestCase : OBTestCase

+ (XCTest *)dataDrivenTestSuite;
+ (XCTest *)testSuiteForMethod:(NSString *)methodName cases:(NSArray *)testCases;
+ (XCTest *)testSuiteNamed:(NSString *)suiteName usingSelector:(SEL)testSelector cases:(NSArray *)testCases;

// Fixture directory driven test suites
+ (void)addFixtureDrivenTestsToSuite:(XCTestSuite *)suite fixturesURL:(NSURL *)fixturesURL processSelector:(SEL)processSelector;
@property(nonatomic,readonly,class) NSURL *fixturesURL;
+ (NSString *)nameForFixtureDrivenTestCase:(OFTestCase *)testCase;

@end

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define OFDataShouldBeEqual(expected, actual) XCTAssertEqualObjects(expected, actual)
#else
extern void OFDiffData(XCTestCase *testCase, NSData *expected, NSData *actual);
extern void OFDiffDataFiles(XCTestCase *testCase, NSString *expectedPath, NSString *actualPath);

#define OFDataShouldBeEqual(expected,actual) \
do { \
    BOOL dataEqual = [expected isEqual:actual]; \
    if (!dataEqual) { \
        OFDiffData(self, expected, actual); \
        XCTAssertTrue(dataEqual); \
    } \
} while (0)

#define OFFileDataShouldBeEqual(expected,expectedPath,actual,actualPath) \
do { \
    BOOL dataEqual = [expected isEqual:actual]; \
    if (!dataEqual) { \
        OFDiffDataFiles(self, expectedPath, actualPath); \
        XCTAssertTrue(dataEqual); \
    } \
} while (0)

#endif

typedef BOOL (^OFDiffFilesPathFilter)(NSString *relativePath);
typedef NSData * _Nonnull (^OFDiffFileTransformData)(NSString *relativePath, NSData *data);
typedef BOOL (^OFDiffFileCompareData)(NSString *relativePath1, NSData *data1,
                                      NSString *relativePath2, NSData *data2);

@interface OFDiffFileOperations : NSObject
@property(nonatomic,copy) OFDiffFilesPathFilter pathFilter;

 // Only used if the two data objects are not -isEqual:. This can do semantic comparisons (like unarchiving and comparing the unarchived versions).
@property(nonatomic,copy) OFDiffFileTransformData transformData;
@property(nonatomic,copy) OFDiffFileCompareData compareData;
@end

extern BOOL OFSameFiles(XCTestCase *testCase, NSString *path1, NSString *path2, OFDiffFileOperations * _Nullable operations); // query, not required
extern void OFDiffFiles(XCTestCase *testCase, NSString *path1, NSString *path2, OFDiffFileOperations * _Nullable operations); // fails if the files aren't the same

NS_ASSUME_NONNULL_END
