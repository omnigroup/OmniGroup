// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <XCTest/XCTest.h>

#import <OmniBase/OmniBase.h>

@interface OBTestCase : XCTestCase
+ (BOOL)shouldRunSlowUnitTests;
@end

// Assumes a local variable called 'error'.  Clears the error, runs the expression and reports if an error occurs.
extern void _OBReportUnexpectedError(NSError *error);
#define OBShouldNotError(expr) \
do { \
    error = nil; \
    typeof(expr) __value = (expr); \
    BOOL hadError = NO; \
    if (!__value) { \
        _OBReportUnexpectedError(error); \
        hadError = YES; \
    } \
    XCTAssertFalse(hadError, @"%@", (id)CFSTR(#expr)); \
} while (0);

#define OBAssertMemEqual(buf1, buf2, buflen, ...)                       \
    ({                                                                  \
        const void *ptr1=(buf1);                                        \
        const void *ptr2=(buf2);                                        \
        size_t buflens=(buflen);                                        \
        if (memcmp(ptr1, ptr2, buflens) != 0) {                         \
            NSString *msg = [NSString stringWithFormat:@"memcmp(%s, %s, %lu) failed", #buf1, #buf2, (unsigned long)buflens]; \
            _XCTRegisterFailure(self, msg, __VA_ARGS__);                \
        }                                                               \
    })

// It isn't clear if XCTAssert{,Not}EqualObjects checks reflexivity.
#define OBAssertEqualObjects(a,b) do { \
    XCTAssertEqualObjects((a), (b)); \
    XCTAssertEqualObjects((b), (a)); \
} while(0)
#define OBAssertNotEqualObjects(a,b) do { \
    XCTAssertNotEqualObjects((a), (b)); \
    XCTAssertNotEqualObjects((b), (a)); \
} while(0)

