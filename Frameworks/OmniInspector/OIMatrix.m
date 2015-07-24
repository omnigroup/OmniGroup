// Copyright 2007-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIMatrix.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation OIMatrix

// to ensure that this table view receives focus when clicked on.
- (BOOL)needsPanelToBecomeKey;
{
    return YES;
}

@end
