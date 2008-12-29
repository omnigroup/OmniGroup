// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/OBTestCase.h 102866 2008-07-15 05:27:40Z bungi $

#import <SenTestingKit/SenTestingKit.h>

@interface OBTestCase : SenTestCase
+ (BOOL)shouldRunSlowUnitTests;
@end

// Assumes a local variable called 'error'
#define OBShouldNotError(expr) \
do { \
    BOOL __value = (expr); \
    if (!__value) \
        NSLog(@"Error: %@", [error toPropertyList]); \
    STAssertTrue(__value, (id)CFSTR(#expr)); \
} while (0);
