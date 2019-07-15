// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAImages.h>

#import <OmniAppKit/NSImage-OAExtensions.h>

RCS_ID("$Id$")

NSImage *OAActionImage(void)
{
    return OAImageNamed(@"OAAction", OMNI_BUNDLE);
}

NSImage *OAActionNoBezelImage(void)
{
    return OAImageNamed(@"OAActionNoBezel", OMNI_BUNDLE);
}

NSImage *OAGearTemplateImage(void)
{
    return OAImageNamed(@"OAGearTemplate", OMNI_BUNDLE);
}

NSImage *OAInfoTemplateImage(void)
{
    return OAImageNamed(@"OAInfoTemplateImage", OMNI_BUNDLE);
}

NSImage *OAMiniAction(void)
{
    return OAImageNamed(@"OAMiniAction", OMNI_BUNDLE);
}

NSImage *OAMiniRemove(void)
{
    return OAImageNamed(@"OAMiniRemove", OMNI_BUNDLE);
}
