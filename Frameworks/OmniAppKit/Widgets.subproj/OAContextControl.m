// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAContextControl.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSImage-OAExtensions.h"

RCS_ID("$Id$");

NSString *OAContextControlToolTip(void)
{
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.omnigroup.OmniAppKit"];
    OBASSERT(bundle);
    return NSLocalizedStringFromTableInBundle(@"Shortcuts for commonly used actions", @"OmniAppKit", bundle, @"context control tooltip");
}

NSMenu *OAContextControlNoActionsMenu(void)
{
    static NSMenu *noActionsMenu = nil;
    if (noActionsMenu == nil) {
        NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.omnigroup.OmniAppKit"];
        OBASSERT(bundle);
        
        NSString *title = NSLocalizedStringFromTableInBundle(@"No Actions Available", @"OmniAppKit", bundle, @"menu title");
        noActionsMenu = [[NSMenu alloc] initWithTitle:title];
        [noActionsMenu addItemWithTitle:title action:NULL keyEquivalent:@""];
    }
    return noActionsMenu;
}

void OAContextControlGetMenu(id delegate, NSControl *control, NSMenu **outMenu, NSView **outTargetView)
{
    NSMenu *menu = nil;
    NSView *targetView = nil;

    if (delegate) {
        // The delegate must respond to both
        targetView = [delegate targetViewForContextControl:control];
        menu       = [delegate menuForContextControl:control];
    } else {
        // TODO: Check if any of the menu items in the resulting menu are valid?

        id target = [NSApp targetForAction:@selector(menuForContextControl:)];
        if (target) {
            if ([target isKindOfClass:[NSView class]]) {
                targetView = target;
                menu       = [targetView menuForContextControl:control];
            } else {
                // Not a view, must respond to both
                targetView = [target targetViewForContextControl:control];
                menu       = [target menuForContextControl:control];
            }
        } else if ((target = [NSApp targetForAction:@selector(menu)])) {
            if ([target isKindOfClass:[NSView class]]) {
                targetView = target;
                menu       = [targetView menu];
            } else {
                // This can happen when the responder we get to -menu is NSApp
            }
        }
    }

    if (outMenu)
        *outMenu = menu;
    if (outTargetView)
        *outTargetView = targetView;
}
