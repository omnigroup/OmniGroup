// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAController-OSUExtensions.h"

#import <OmniBase/OmniBase.h>

#import "OSUMessageOfTheDay.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OAController-OSUExtensions.m 94355 2007-11-09 21:51:45Z kc $")

@implementation OAController (OSUExtensions)

- (IBAction)showMessageOfTheDay:(id)sender;
{
    [[OSUMessageOfTheDay sharedMessageOfTheDay] showMessageOfTheDay:nil];
}

@end
