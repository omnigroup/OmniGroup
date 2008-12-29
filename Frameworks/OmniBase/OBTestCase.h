// Copyright 2008 Omni Development, Inc.  All rights reserved.
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
#define OBShouldNotError(expr) \
do { \
    error = nil; \
    BOOL __value = (expr); \
    if (!__value) \
        NSLog(@"Error: %@", [error toPropertyList]); \
    STAssertTrue(__value, (id)CFSTR(#expr)); \
} while (0);
