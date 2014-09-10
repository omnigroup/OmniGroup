// Copyright 2008, 2010-2011, 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <XCTest/XCTest.h>

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
