// Copyright 2005-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAToolbarWindowController-OIExtensions.h"
#import "OIColorInspector.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OAToolbarWindowController-OIExtensions.m 93428 2007-10-25 16:36:11Z kc $");

@implementation OAToolbarWindowController (OIExtensions)

// Actions

// For some reason we want our NSToolbarShowColorsItem to toggle instead of just orderFront:
- (IBAction)toggleFrontColorPanel:(id)sender;
{
    [[NSColorPanel sharedColorPanel] toggleWindow:nil];
}

// NSObject (NSToolbarNotifications)

- (void)toolbarWillAddItem:(NSNotification *)notification;
{
    NSToolbarItem *item = [[notification userInfo] objectForKey:@"item"];
    if ([[item itemIdentifier] isEqualToString:NSToolbarShowColorsItemIdentifier])
        [item setAction:@selector(toggleFrontColorPanel:)];
}

- (void)toolbarDidRemoveItem:(NSNotification *)notification;
{
    NSToolbarItem *item = [[notification userInfo] objectForKey:@"item"];
    if ([[item itemIdentifier] isEqualToString:NSToolbarShowColorsItemIdentifier])
	[item setAction:@selector(toggleFrontColorPanel:)];
}

@end
