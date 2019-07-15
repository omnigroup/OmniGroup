// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAContextPopUpButton.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAContextControl.h>

RCS_ID("$Id$");

@implementation OAContextPopUpButton
{
    NSMenuItem *gearItem;
    __weak id _weak_delegate;
}

+ (NSImage *)gearImage;
{
    static NSImage *gearImage = nil;
    if (gearImage == nil) {
        gearImage = OAImageNamed(@"OAGearTemplate", OMNI_BUNDLE);
        OBASSERT(gearImage != nil);
    }

    return gearImage;
}

- (void)_commonInit;
{
    gearItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    [gearItem setImage:[[self class] gearImage]];
    
    // First item is always the label
    [[self menu] addItem:gearItem];
    
    [self setToolTip:OAContextControlToolTip()];
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    
    [self _commonInit];
    
    return self;
}

- (id)initWithFrame:(NSRect)frameRect;
{
    return [self initWithFrame:frameRect pullsDown:NO];
}

- (id)initWithFrame:(NSRect)buttonFrame pullsDown:(BOOL)flag;
{
    if (!(self = [super initWithFrame:buttonFrame pullsDown:flag]))
        return nil;

    [self _commonInit];

    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    if ([self image] == nil) {
        [self setImage:[[self class] gearImage]];
    }
    if ([NSString isEmptyString:[self toolTip]])
        [self setToolTip:OAContextControlToolTip()];
}

#pragma mark - NSView subclass

- (void)mouseDown:(NSEvent *)event;
{
    if (![self isEnabled])
        return;

    id <OAContextControlDelegate> delegate = _weak_delegate;

    OAContextControlMenuAndView *menuAndView = OAContextControlGetMenu(delegate, self);
    NSView *targetView = menuAndView.targetView;
    NSMenu *menu = menuAndView.menu;

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

#pragma mark - API

@synthesize delegate = _weak_delegate;
- (void)setDelegate:(id<OAContextControlDelegate>)delegate;
{
    OBPRECONDITION(!delegate || [delegate conformsToProtocol:@protocol(OAContextControlDelegate)]);
    _weak_delegate = delegate;
}

/*" Returns the menu to be used, or nil if no menu can be found. "*/
- (NSMenu *)locateActionMenu;
{
    id <OAContextControlDelegate> delegate = _weak_delegate;
    return OAContextControlGetMenu(delegate, self).menu;
}

/*" Returns YES if the receiver can find a menu to pop up.  Useful if you have an instance in a toolbar and wish to validate whether it can pop up anything. "*/
- (BOOL)validate;
{
    return ([self locateActionMenu] != nil);
}

@end
