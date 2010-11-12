// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorOptionWheelItem.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIInspectorOptionWheelItem

- (void)dealloc;
{
    [_value release];
    [super dealloc];
}

@synthesize value = _value;

@end
