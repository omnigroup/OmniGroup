// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAController-OSUExtensions.h"

#import <OmniBase/OmniBase.h>

#import "OSUMessageOfTheDay.h"

RCS_ID("$Id$")

@implementation OAController (OSUExtensions)

- (IBAction)showMessageOfTheDay:(id)sender;
{
    [[OSUMessageOfTheDay sharedMessageOfTheDay] showMessageOfTheDay:nil];
}

@end
