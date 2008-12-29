// Copyright 2003-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAContextButton.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSImage-OAExtensions.h"
#import "OAContextControl.h"

RCS_ID("$Id$");

@interface OAContextButton (Private)
- (void)_popUpContextMenuWithEvent:(NSEvent *)simulatedEvent;
@end


@implementation OAContextButton

+ (NSImage *)actionImage;
{
    static NSImage *OAActionImage = nil;
    if (OAActionImage == nil) {
        OAActionImage = [[NSImage imageNamed:@"OAAction" inBundleForClass:[OAContextButton class]] retain];
        OBASSERT(OAActionImage != nil);
    }

    return OAActionImage;
}

+ (NSImage *)miniActionImage;
{
    static NSImage *OAMiniActionImage = nil;
    if (OAMiniActionImage == nil) {
        OAMiniActionImage = [[NSImage imageNamed:@"OAMiniAction" inBundleForClass:[OAContextButton class]] retain];
        OBASSERT(OAMiniActionImage != nil);
    }

    return OAMiniActionImage;
}

- (id)initWithFrame:(NSRect)frameRect;
{
    if ([super initWithFrame:frameRect] == nil)
        return nil;

    [self setImagePosition:NSImageOnly];
    [self setBordered:NO];
    [self setButtonType:NSMomentaryPushInButton];
    [self setImage:[OAContextButton actionImage]];
    [self setToolTip:OAContextControlToolTip()];
    
    return self;
}

- (void)awakeFromNib
{
    NSImage *image = [self image];
    if (image == nil) {
        if ([[self cell] controlSize] == NSSmallControlSize)
            [self setImage:[OAContextButton miniActionImage]];
        else
            [self setImage:[OAContextButton actionImage]];
    } else {
	// IB will disable the size control if you use a flat image in the nib.  Sigh.
	// Need to have the control size set on the cell correctly for font calculation in -_popUpContextMenuWithEvent:
	if ([[image name] isEqualToString:@"OAMiniAction"])
	    [[self cell] setControlSize:NSSmallControlSize];
    }
    
    if ([NSString isEmptyString:[self toolTip]])
        [self setToolTip:OAContextControlToolTip()];
    
    if ([self action] == NULL && [self target] == nil) {
        [self setTarget:self];
        [self setAction:@selector(runMenu:)];
    }
}

//
// NSView subclass
//
- (void)mouseDown:(NSEvent *)event;
{
    [self _popUpContextMenuWithEvent:event];
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

- (void)runMenu:(id)sender;
{
    NSEvent *event = [NSApp currentEvent];
    [self _popUpContextMenuWithEvent:event];
}

@end

@implementation OAContextButton (Private)

- (void)_popUpContextMenuWithEvent:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    
    NSView *targetView;
    NSMenu *menu;
    OAContextControlGetMenu(delegate, self, &menu, &targetView);
    
    if (targetView == nil)
        menu = OAContextControlNoActionsMenu();
    
    NSPoint eventLocation = [self frame].origin;
    eventLocation = [[self superview] convertPoint:eventLocation toView:nil];
    if ([[[self window] contentView] isFlipped])
        eventLocation.y += 3;
    else
        eventLocation.y -= 3;

    NSEvent *simulatedEvent;
    if ([event type] == NSLeftMouseDown) {
        simulatedEvent = [NSEvent mouseEventWithType:NSLeftMouseDown location:eventLocation modifierFlags:[event modifierFlags] timestamp:[event timestamp] windowNumber:[event windowNumber] context:[event context] eventNumber:[event eventNumber] clickCount:[event clickCount] pressure:[event pressure]];
    } else 
        simulatedEvent = [NSEvent mouseEventWithType:NSLeftMouseDown location:eventLocation modifierFlags:[event modifierFlags] timestamp:[event timestamp] windowNumber:[event windowNumber] context:[event context] eventNumber:0 clickCount:1 pressure:1.0];
    
    NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[[self cell] controlSize]]];

    [[self cell] setHighlighted:YES];
    [NSMenu popUpContextMenu:menu withEvent:simulatedEvent forView:targetView withFont:font];
    [[self cell] setHighlighted:NO];
}

@end
