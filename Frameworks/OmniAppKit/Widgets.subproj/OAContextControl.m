// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAContextControl.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSImage-OAExtensions.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OAContextControlMenuAndView

- (void)dealloc;
{
    [_menu release];
    [_targetView release];
    [super dealloc];
}

@end

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

OAContextControlMenuAndView *OAContextControlGetMenu(id <OAContextControlDelegate> delegate, NSControl *control)
{
    OAContextControlMenuAndView *result = [[[OAContextControlMenuAndView alloc] init] autorelease];

    if (delegate) {
        // The delegate must respond to both
        result.targetView = [delegate targetViewForContextControl:control];
        result.menu = [delegate menuForContextControl:control];
        return result;
    }

    // TODO: Check if any of the menu items in the resulting menu are valid?

    id <OAContextControlDelegate> target = [[NSApplication sharedApplication] targetForAction:@selector(menuForContextControl:)];
    if (target) {
        if ([target isKindOfClass:[NSView class]]) {
            // Only needs to implement the menu generating method (and we checked for that with -targetForAction:).
            NSView *targetView = (NSView *)target;
            result.targetView = targetView;
            result.menu = [(id <OAContextControlDelegate>)targetView menuForContextControl:control];
        } else {
            // Not a view, must respond to both
            result.targetView = [target targetViewForContextControl:control];
            result.menu = [target menuForContextControl:control];
        }
    } else if ((target = [[NSApplication sharedApplication] targetForAction:@selector(menu)])) {
        if ([target isKindOfClass:[NSView class]]) {
            NSView *targetView = (NSView *)target;
            result.targetView = targetView;
            result.menu = [targetView menu];
        } else {
            // This can happen when the responder we get to -menu is the shared NSApplication
        }
    }

    return result;
}

NS_ASSUME_NONNULL_END
