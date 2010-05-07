// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <SenTestingKit/SenTestingKit.h>

@interface OBTestCase : SenTestCase
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
    STAssertFalse(hadError, (id)CFSTR(#expr)); \
} while (0);

// Like STAssertThrows execept it marks the exception as unused to avoid clang warnings.
// Radar 7935453: clang-sa with llvm 2.7 reports unused variable for STAssertThrows
#define OBAssertThrows(expr, description, ...) \
do { \
    BOOL __caughtException = NO; \
    @try { \
        (expr);\
    } \
    @catch (id anException) { \
        OB_UNUSED_VALUE(anException); \
        __caughtException = YES; \
    }\
    if (!__caughtException) { \
        [self failWithException:([NSException failureInRaise:[NSString stringWithUTF8String:#expr] \
        exception:nil \
        inFile:[NSString stringWithUTF8String:__FILE__] \
        atLine:__LINE__ \
        withDescription:@"%@", STComposeString(description, ##__VA_ARGS__)])]; \
    } \
} while (0)
