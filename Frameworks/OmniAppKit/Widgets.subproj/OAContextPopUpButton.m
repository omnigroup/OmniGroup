// Copyright 2004-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAContextPopUpButton.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSImage-OAExtensions.h"
#import "OAContextControl.h"

RCS_ID("$Id$");

@implementation OAContextPopUpButton

+ (NSImage *)gearImage;
{
    static NSImage *gearImage = nil;
    if (gearImage == nil) {
        gearImage = [[NSImage imageNamed:@"OAGear" inBundleForClass:[OAContextPopUpButton class]] retain];
        OBASSERT(gearImage != nil);
    }

    return gearImage;
}

- (id)initWithFrame:(NSRect)buttonFrame pullsDown:(BOOL)flag;
{
    if ([super initWithFrame:buttonFrame pullsDown:flag] == nil)
        return nil;

    gearItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    [gearItem setImage:[isa gearImage]];

    // First item is always the label
    [[self menu] addItem:gearItem];

    [self setToolTip:OAContextControlToolTip()];

    return self;
}

- (void)dealloc;
{
    [gearItem release];
    [super dealloc];
}

- (void)awakeFromNib
{
    if ([self image] == nil) {
        [self setImage:[isa gearImage]];
    }
    if ([NSString isEmptyString:[self toolTip]])
        [self setToolTip:OAContextControlToolTip()];
}

//
// NSView subclass
//
- (void)mouseDown:(NSEvent *)event;
{
    if (![self isEnabled])
        return;

    NSView *targetView;
    NSMenu *menu;
    OAContextControlGetMenu(delegate, self, &menu, &targetView);

    if (targetView == nil)
        menu = OAContextControlNoActionsMenu();

    // First item is always the label.  If we don't do this, the label will get reset
    [[gearItem menu] removeItem:gearItem];
    [menu insertItem:gearItem atIndex:0];
    
    [self setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[[self cell] controlSize]]]];
    
    [self setMenu:menu];
    [self setTarget:targetView];
    [super mouseDown:event];
    [self setMenu:nil];

    // Remove the item we stuck in the menu given to us (in case it get reused).
    [menu removeItemAtIndex:0];

    // We don't seem to need to reset our label
}

//
// API
//

/*" Returns the menu to be used, or nil if no menu can be found. "*/
- (NSMenu *)locateActionMenu;
{
    NSMenu *menu;
    OAContextControlGetMenu(delegate, self, &menu, NULL);
    return menu;
}

/*" Returns YES if the receiver can find a menu to pop up.  Useful if you have an instance in a toolbar and wish to validate whether it can pop up anything. "*/
- (BOOL)validate;
{
    return ([self locateActionMenu] != nil);
}

@end
