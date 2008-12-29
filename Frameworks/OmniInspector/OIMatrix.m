// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIMatrix.h"

#import <OmniBase/rcsid.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIMatrix.m 89476 2007-08-01 23:59:32Z kc $")

@implementation OIMatrix

// to ensure that this table view receives focus when clicked on.
- (BOOL)needsPanelToBecomeKey;
{
    return YES;
}

@end
