// Copyright 2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniUI/OUIEditMenuController.h>

#import <OmniUI/OUIEditableFrameDelegate.h>
#import <OmniUI/OUIEditableFrame.h>
#import <OmniFoundation/NSArray-OFExtensions.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_MENU(format, ...) NSLog(@"MENU: " format, ## __VA_ARGS__)
    #define DEBUG_MENU_LOG_CALLER() OB_DEBUG_LOG_CALLER()
#else
    #define DEBUG_MENU(format, ...)
    #define DEBUG_MENU_LOG_CALLER()
#endif

NSString * const OUIKeyboardAnimationInhibition = @"OUIKeyboardAnimationInhibition";

@interface OUIEditMenuController ()
- (BOOL)_isDefaultSelector:(SEL)action;
- (NSArray *)_extraMenuItemsForCurrentState;
- (void)_setSharedMenuIsVisible:(BOOL)visible;
- (void)_menuDidHideHandler:(NSNotification *)notification;
- (void)_keyboardWillAnimate:(NSNotification *)notification;
- (void)_keyboardDidAnimate:(NSNotification *)notification;
@end

@implementation OUIEditMenuController

- (id)initWithEditableFrame:(OUIEditableFrame *)editableFrame;
{
    self = [super init];
    if (self) {
        // Initialization code here.
        inhibitions = [[NSMutableSet alloc] init];
        unretained_editor = [editableFrame retain];
        wantMainMenuDisplay = NO;
        needsToShowMainMenuAfterCurrentMenuFinishesHiding = NO;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillAnimate:) name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardDidAnimate:) name:UIKeyboardDidShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillAnimate:) name:UIKeyboardWillHideNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardDidAnimate:) name:UIKeyboardDidHideNotification object:nil];
    }
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [inhibitions release];
    [extraMainMenuItems release];
    [extraMenuItemsSelectors release];

    [super dealloc];
}

- (NSString *)description;
{
    return [NSString stringWithFormat:@"OUIEditMenuController: %@ %@ inhibitions: %@", (wantMainMenuDisplay ? @"wants main menu, " : @""), (needsToShowMainMenuAfterCurrentMenuFinishesHiding ? @"show again when hide finishes" : @""), inhibitions];
}

#pragma mark -
#pragma mark Public API

@synthesize delegate;

- (void)setDelegate:(id<OUIEditableFrameDelegate>)newDelegate;
{
    if (delegate == newDelegate)
        return;
    
    delegate = newDelegate;
    delegateRespondsToCanShowContextMenu = [newDelegate respondsToSelector:@selector(textViewCanShowContextMenu:)];
    delegateRespondsToCanPerformEditingAction = [newDelegate respondsToSelector:@selector(canPerformEditingAction:forTextView:withSender:)];
    
    if ([newDelegate respondsToSelector:@selector(customMenuItemsForTextView:)]) {
        NSArray *items = [newDelegate customMenuItemsForTextView:unretained_editor];
        self.extraMainMenuItems = items;
        self.extraMenuItemsSelectors = [items arrayByPerformingBlock:^(UIMenuItem *menuItem) {return NSStringFromSelector(menuItem.action);}];
    }
}

@synthesize extraMainMenuItems;
@synthesize extraMenuItemsSelectors;

- (void)showMainMenu;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    wantMainMenuDisplay = YES;
    if (inhibitions.count == 0)
        [self _setSharedMenuIsVisible:YES];
}

- (void)showMainMenuAfterCurrentMenuFinishesHiding;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    if (!wantMainMenuDisplay) {
        // If the menu wasn't showing, then it's not going to finish hiding. So, just show it now.
        [self showMainMenu];
        return;
    }
        
    needsToShowMainMenuAfterCurrentMenuFinishesHiding = YES;
    if (!didRegisterForNotifications) {
        didRegisterForNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_menuDidHideHandler:) name:UIMenuControllerDidHideMenuNotification object:[UIMenuController sharedMenuController]];
    }
}

- (void)hideMenu;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    DEBUG_MENU_LOG_CALLER();
    needsToShowMainMenuAfterCurrentMenuFinishesHiding = NO;
    wantMainMenuDisplay = NO;
    [self _setSharedMenuIsVisible:NO];
}

- (void)toggleMenuVisibility;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    if (wantMainMenuDisplay)
        [self hideMenu];
    else
        [self showMainMenu];
}

- (void)forceCorrectMenuDisplay;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    [self _setSharedMenuIsVisible:wantMainMenuDisplay];
}

- (void)inhibitMenuFor:(NSString *)cause;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    DEBUG_MENU(@"Inhibiting for: %@", cause);
    [inhibitions addObject:cause];
}

- (void)uninhibitMenuFor:(NSString *)cause;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    DEBUG_MENU(@"Overcoming inhibition for: %@", cause);
    [inhibitions removeObject:cause];
    [self forceCorrectMenuDisplay];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (wantMainMenuDisplay) {
        if ([self _isDefaultSelector:action]) {
            return [unretained_editor canPerformMainMenuAction:action withSender:sender];
        } else if ([self.extraMenuItemsSelectors containsObject:NSStringFromSelector(action)]) {
            return [delegate canPerformEditingAction:action forTextView:unretained_editor withSender:sender];
        }
    } 
    return [unretained_editor canSuperclassPerformAction:action withSender:sender];
}

#pragma mark -
#pragma mark Private API
- (BOOL)_isDefaultSelector:(SEL)action;
{
    // Selectors from UIResponderStandardEditActions informal protocol
    return action == @selector(copy:) || action == @selector(cut:) || action == @selector(delete:) || action == @selector(paste:) || action == @selector(select:) || action == @selector(selectAll:);
}

- (NSArray *)_extraMenuItemsForCurrentState;
{
    if (wantMainMenuDisplay)
        return extraMainMenuItems;
    else {
        OBASSERT_NOT_REACHED("Inconsistent internal state. Why are we displaying a menu if we don't know which menu to display?");
        return nil;
    }
}

- (void)_setSharedMenuIsVisible:(BOOL)wantVisible;
{
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    
    BOOL shouldBeVisible = NO;
    if (wantVisible) {
        BOOL shouldSuppress = [unretained_editor shouldSuppressEditMenu] || (delegateRespondsToCanShowContextMenu && ![delegate textViewCanShowContextMenu:unretained_editor]);
        shouldBeVisible = !shouldSuppress && wantMainMenuDisplay && inhibitions.count == 0;
    }

    if (shouldBeVisible) {
        [menuController setTargetRect:[unretained_editor targetRectangleForEditMenu] inView:unretained_editor];
        if (![menuController.menuItems isEqualToArray:[self _extraMenuItemsForCurrentState]]) {
            [menuController setMenuVisible:NO animated:NO];
            menuController.menuItems = [self _extraMenuItemsForCurrentState];            
        }
    }

    if ([menuController isMenuVisible] != shouldBeVisible) {
        [menuController setMenuVisible:shouldBeVisible animated:YES];
    }
}

- (void)_menuDidHideHandler:(NSNotification *)notification;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    if (needsToShowMainMenuAfterCurrentMenuFinishesHiding) {
        needsToShowMainMenuAfterCurrentMenuFinishesHiding = NO;
        [self performSelector:@selector(showMainMenu) withObject:nil afterDelay:0];
    }
}

- (void)_keyboardWillAnimate:(NSNotification *)notification;
{
    [self inhibitMenuFor:OUIKeyboardAnimationInhibition];
}

- (void)_keyboardDidAnimate:(NSNotification *)notification;
{
    [self uninhibitMenuFor:OUIKeyboardAnimationInhibition];    
}

@end
