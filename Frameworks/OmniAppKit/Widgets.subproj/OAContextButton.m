// Copyright 2003-2006, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
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

@implementation OAContextButton
{
    id _nonretained_delegate;
}

+ (NSImage *)actionImage;
{
    static NSImage *OAActionImage = nil;
    if (OAActionImage == nil) {
        OAActionImage = [[NSImage imageNamed:@"OAAction" inBundle:OMNI_BUNDLE] retain];
        OBASSERT(OAActionImage != nil);
    }

    return OAActionImage;
}

+ (NSImage *)miniActionImage;
{
    static NSImage *OAMiniActionImage = nil;
    if (OAMiniActionImage == nil) {
        OAMiniActionImage = [[NSImage imageNamed:@"OAMiniAction" inBundle:OMNI_BUNDLE] retain];
        OBASSERT(OAMiniActionImage != nil);
    }

    return OAMiniActionImage;
}

- (id)initWithFrame:(NSRect)frameRect;
{
    if (!(self = [super initWithFrame:frameRect]))
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
    [super awakeFromNib];
    
    NSImage *image = [self image];
    if (image == nil) {
        if ([[self cell] controlSize] == NSSmallControlSize)
            [self setImage:[OAContextButton miniActionImage]];
        else
            [self setImage:[OAContextButton actionImage]];
    } else {
	// IB will disable the size control if you use a flat image in the nib.  Sigh.
	// Need to have the control size set on the cell correctly for font calculation in -_popUpContextMenu
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
    [self _popUpContextMenu];
}

//
// API
//

@synthesize delegate = _nonretained_delegate;

/*" Returns the menu to be used, or nil if no menu can be found. "*/
- (NSMenu *)locateActionMenu;
{
    NSMenu *menu;
    OAContextControlGetMenu(_nonretained_delegate, self, &menu, NULL);
    return menu;
}

/*" Returns YES if the receiver can find a menu to pop up.  Useful if you have an instance in a toolbar and wish to validate whether it can pop up anything. "*/
- (BOOL)validate;
{
    return ([self locateActionMenu] != nil);
}

- (void)runMenu:(id)sender;
{
    [self _popUpContextMenu];
}

#pragma mark - Private

- (void)_popUpContextMenu;
{
    if (![self isEnabled])
        return;
    
    NSView *targetView;
    NSMenu *menu;
    OAContextControlGetMenu(_nonretained_delegate, self, &menu, &targetView);
    
    if (targetView == nil)
        menu = OAContextControlNoActionsMenu();
    
    NSRect bounds = self.bounds;
    NSPoint menuLocation;
    menuLocation.x = NSMinX(bounds);
    
    if ([self isFlipped])
        menuLocation.y = NSMaxY(bounds) + 3;
    else
        menuLocation.y = NSMinY(bounds) - 3;
    
    menu.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[[self cell] controlSize]]];

    [[self cell] setHighlighted:YES];
    [menu popUpMenuPositioningItem:nil atLocation:menuLocation inView:self];
    [[self cell] setHighlighted:NO];
}

@end
