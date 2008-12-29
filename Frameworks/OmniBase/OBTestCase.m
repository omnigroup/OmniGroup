// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OBTestCase.h"

#import <OmniBase/OmniBase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/OBTestCase.m 102866 2008-07-15 05:27:40Z bungi $")

@implementation OBTestCase

+ (void) initialize;
{
    OBINITIALIZE;
    [OBPostLoader processClasses];
}

+ (BOOL)shouldRunSlowUnitTests;
{
    return getenv("RunSlowUnitTests") != NULL;
}

@end
