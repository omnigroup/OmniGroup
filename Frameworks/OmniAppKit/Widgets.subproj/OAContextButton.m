// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAContextButton.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/OAContextControl.h>

RCS_ID("$Id$");

@interface OAContextButton () <NSAccessibility>
@property(nonatomic,readonly) NSMenu *shownMenu;
@end

@implementation OAContextButton
{
    __weak id _weak_delegate;
}

+ (Class)cellClass;
{
    return [OAContextButtonCell class];
}

+ (NSImage *)actionImage;
{
    return OAImageNamed(@"OAAction", OMNI_BUNDLE);
}

+ (NSImage *)miniActionImage;
{
    return OAImageNamed(@"OAMiniAction", OMNI_BUNDLE);
}

- (id)initWithFrame:(NSRect)frameRect;
{
    if (!(self = [super initWithFrame:frameRect]))
        return nil;

    [self setImagePosition:NSImageOnly];
    [self setBordered:NO];
    [self setButtonType:NSButtonTypeMomentaryPushIn];
    [self setImage:[OAContextButton actionImage]];
    [self setToolTip:OAContextControlToolTip()];
    
    _showsMenu = YES;

    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    OBASSERT([[self cell] isKindOfClass:[[self class] cellClass]], "Need to set the cell class in xib too");
    
    NSImage *image = [self image];
    if (image == nil) {
        if ([[self cell] controlSize] == NSControlSizeSmall)
            [self setImage:[OAContextButton miniActionImage]];
        else
            [self setImage:[OAContextButton actionImage]];
    } else {
	// IB will disable the size control if you use a flat image in the nib.  Sigh.
	// Need to have the control size set on the cell correctly for font calculation in -_popUpContextMenu
	if ([[image name] isEqualToString:@"OAMiniAction"])
	    [[self cell] setControlSize:NSControlSizeSmall];
    }
    
    if ([NSString isEmptyString:[self toolTip]])
        [self setToolTip:OAContextControlToolTip()];
    
    _showsMenu = YES;
}

#pragma mark - NSView subclass

- (void)mouseDown:(NSEvent *)event;
{
    if (!_showsMenu) {
        [super mouseDown:event];
        return;
    }
        
    [self _popUpContextMenu];
}

#pragma mark - Accessibility

// See also -accessibilityChildren and -accessibilityPerformShowMenu on our cell

- (NSString *)accessibilityRole;
{
    return NSAccessibilityMenuButtonRole;
}

- (id)accessibilityShownMenu;
{
    return _shownMenu;
}

- (BOOL)accessibilityPerformPress {
    if (_showsMenu) {
        [self _popUpContextMenu];
    }

    return YES;
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
    return !_showsMenu || ([self locateActionMenu] != nil);
}

#pragma mark - Private

- (void)_popUpContextMenu;
{
    if (![self isEnabled])
        return;
    
    id <OAContextControlDelegate> delegate = _weak_delegate;
    OAContextControlMenuAndView *menuAndView = OAContextControlGetMenu(delegate, self);
    NSMenu *menu = menuAndView.menu;
    NSView *targetView = menuAndView.targetView;
    
    if (targetView == nil)
        menu = OAContextControlNoActionsMenu();
    
    if (!menu) {
        NSBeep();
        return;
    }
        
    NSRect bounds = self.bounds;
    NSPoint menuLocation;
    menuLocation.x = NSMinX(bounds);
    
    if ([self isFlipped])
        menuLocation.y = NSMaxY(bounds) + 3;
    else
        menuLocation.y = NSMinY(bounds) - 3;
    
    menu.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[[self cell] controlSize]]];

    if (_shownMenu)
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMenuDidEndTrackingNotification object:_shownMenu];
    
    _shownMenu = menu;
    
    if (_shownMenu)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_shownMenuDidEndTracking:) name:NSMenuDidEndTrackingNotification object:_shownMenu];
    
    [[self cell] setHighlighted:YES];
    [_shownMenu popUpMenuPositioningItem:nil atLocation:menuLocation inView:self];
    [[self cell] setHighlighted:NO];
    
    NSAccessibilityPostNotification(_shownMenu, NSAccessibilityCreatedNotification);
}

- (void)_shownMenuDidEndTracking:(NSNotification *)note;
{
    OBPRECONDITION(_shownMenu == [note object]);

    NSAccessibilityPostNotification(_shownMenu, NSAccessibilityUIElementDestroyedNotification);

    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMenuDidEndTrackingNotification object:_shownMenu];
    _shownMenu = nil;
}

@end

@implementation OAContextButtonCell

// These two methods don't work (or even get called, if they are on the button).

- (NSArray *)accessibilityChildren;
{
    // Sadly, the AppleScript in System Events doesn't have a "shown menu" property on the "menu button" class. So, we'll report this in the children too.
    OAContextButton *button = OB_CHECKED_CAST(OAContextButton, self.controlView);
    NSMenu *menu = button.shownMenu;
    if (!menu)
        return @[];
    return @[menu];
}

- (BOOL)accessibilityPerformShowMenu;
{
    OAContextButton *button = OB_CHECKED_CAST(OAContextButton, self.controlView);
    
    // This is ugly. -[NSMenu popUpMenuPositioningItem:atLocation:inView:] starts a tracking loop unconditionally and takes several seconds to time out if there are no events in the queue. So, we simulate a single click.
    NSWindow *window = button.window;
    CGRect buttonRect = [button convertRect:button.bounds toView:nil];
    NSPoint buttonMiddle = CGPointMake(CGRectGetMidX(buttonRect), CGRectGetMidY(buttonRect));
    NSTimeInterval timestamp = [NSDate timeIntervalSinceReferenceDate];
    
    // If we post a matching up, the menu hides immediately.
    [[NSApplication sharedApplication] postEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:buttonMiddle modifierFlags:0 timestamp:timestamp windowNumber:[window windowNumber] context:nil eventNumber:-1 clickCount:1 pressure:1.0] atStart:NO];
    
    return YES;
}

@end

