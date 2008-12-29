// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATabView.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OATabViewController.h"

RCS_ID("$Id$")


@interface OATabView (Private)
- (void)addController:(OATabViewController *)controller;
@end

@implementation OATabView

//
// NSNibAwaking informal protocol
//

- (void)awakeFromNib;
{
    if (flags.alreadyAwoke)
        return;
    flags.alreadyAwoke = YES;

    [self addController:controller1];
    [self addController:controller2];
    [self addController:controller3];
    [self addController:controller4];
    [self addController:controller5];
    [self addController:controller6];
    [self addController:controller7];
    [self addController:controller8];

    [self selectFirstTabViewItem:nil];
}

@end


@implementation OATabView (Private)

- (void)addController:(OATabViewController *)controller;
{
    NSWindow *scratchWindow;
    NSView *contentView;
    NSTabViewItem *tabViewItem;

    if (!controller)
        return;
    
    scratchWindow = [controller scratchWindow];
    contentView = [scratchWindow contentView];
    [contentView setAutoresizesSubviews:YES];
    [contentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    tabViewItem = [[NSTabViewItem alloc] initWithIdentifier:controller];
    [tabViewItem setLabel:[controller label]];
    [tabViewItem setView:contentView];
    [tabViewItem setInitialFirstResponder:[scratchWindow initialFirstResponder]];

    [self addTabViewItem:tabViewItem];
    [tabViewItem release];
}

@end

