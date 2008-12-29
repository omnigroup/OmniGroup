// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Tests/OFTestCase.h 103775 2008-08-06 00:17:59Z wiml $

#import "OBTestCase.h"

@interface OFTestCase : OBTestCase

+ (SenTest *)dataDrivenTestSuite;
+ (SenTest *)testSuiteForMethod:(NSString *)methodName cases:(NSArray *)testCases;

@end
