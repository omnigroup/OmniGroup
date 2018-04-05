// Copyright 2018 Omni Development, Inc. All rights reserved.
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
    return [NSImage imageNamed:@"OAActionImage" inBundle:OMNI_BUNDLE];
}

NSImage *OAGearTemplateImage(void)
{
    return [NSImage imageNamed:@"OAGearTemplate" inBundle:OMNI_BUNDLE];
}

NSImage *OAInfoTemplateImage(void)
{
    return [NSImage imageNamed:@"OAInfoTemplateImage" inBundle:OMNI_BUNDLE];
}

NSImage *OAMiniAction(void)
{
    return [NSImage imageNamed:@"OAMiniAction" inBundle:OMNI_BUNDLE];
}

NSImage *OAMiniRemove(void)
{
    return [NSImage imageNamed:@"OAMiniRemove" inBundle:OMNI_BUNDLE];
}
