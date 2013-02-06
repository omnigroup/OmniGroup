// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIEditMenuController.h"

#import <UIKit/UIView.h>

#import <OmniUI/OUIEditableFrameDelegate.h>
#import <OmniUI/OUIEditableFrame.h>
#import <OmniUI/UIView-OUIExtensions.h>
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

@implementation OUIEditMenuController
{
    // Cached information about what our delegate can to, avoiding repeated introspection.
    BOOL delegateRespondsToCanShowContextMenu;
    BOOL delegateRespondsToCanPerformEditingAction;
    
    // The state of our menu.
    BOOL wantMainMenuDisplay;
    
    NSMutableSet *inhibitions;
    OUIEditableFrame *unretained_editor;
    
    NSArray *extraMainMenuItems;
    NSArray *extraMenuItemsSelectors;
    
    BOOL needsToShowMainMenuAfterCurrentMenuFinishesHiding;
    BOOL didRegisterForNotifications;
}

- (id)initWithEditableFrame:(OUIEditableFrame *)editableFrame;
{
    self = [super init];
    if (self) {
        // Initialization code here.
        inhibitions = [[NSMutableSet alloc] init];
        unretained_editor = editableFrame;
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

- (void)invalidate;
{
    unretained_editor = nil;
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
    
    [self _updateMainMenuVisibility];
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
    
    [self _updateMainMenuVisibility];
}

- (void)toggleMenuVisibility;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    if (wantMainMenuDisplay)
        [self hideMenu];
    else
        [self showMainMenu];
}

- (void)inhibitMenuFor:(NSString *)cause;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    DEBUG_MENU(@"Inhibiting for: %@", cause);
        
    OBASSERT([inhibitions member:cause] == nil);
    [inhibitions addObject:cause];

    [self _updateMainMenuVisibility];
}

- (void)uninhibitMenuFor:(NSString *)cause;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    DEBUG_MENU(@"Overcoming inhibition for: %@", cause);
    
    OBASSERT([inhibitions member:cause] != nil);
    [inhibitions removeObject:cause];
    
    [self _updateMainMenuVisibility];
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

// We're showing/hiding the edit contextual menu immediately when needed. Unfortunately, the frameworks seem to knock it down sometimes, for example, after choosing Select All from the menu. This is a hack to force the state to match what we think it should be.
- (void)_updateMainMenuVisibility;
{
    DEBUG_MENU(@"_updateMainMenuVisibility");
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    
    BOOL shouldBeVisible = wantMainMenuDisplay;
    
    if (shouldBeVisible) {
        if (inhibitions.count > 0) {
            DEBUG_MENU(@"  inhibited");
            shouldBeVisible = NO;
        }
    }
    
    if (shouldBeVisible) {
        BOOL suppressEditMenu = [unretained_editor shouldSuppressEditMenu];
        OBASSERT(suppressEditMenu == NO); // We shouldn't be asking for our menu to show if this is false.

        BOOL shouldSuppress = suppressEditMenu || (delegateRespondsToCanShowContextMenu && ![delegate textViewCanShowContextMenu:unretained_editor]);
        
        shouldBeVisible = !shouldSuppress && wantMainMenuDisplay;
        if (!shouldBeVisible) {
            DEBUG_MENU(@"  suppressed");
        }
    }

    if (shouldBeVisible) {
        CGRect targetRect = [self _clippedRectForTargetRect:[unretained_editor targetRectangleForEditMenu]];
        if (CGRectIsEmpty(targetRect)) {
            shouldBeVisible = NO;
            DEBUG_MENU(@"  clipped");
        } else {
            [menuController setTargetRect:targetRect inView:unretained_editor];
            if (![menuController.menuItems isEqualToArray:[self _extraMenuItemsForCurrentState]]) {
                [menuController setMenuVisible:NO animated:NO];
                menuController.menuItems = [self _extraMenuItemsForCurrentState];            
            }
            
            // We can't depend on UIMenuControllerArrowDefault to avoid the top toolbar (Radar 11518111: UIMenuControllerArrowDefault not terribly useful) and we can't use the menuFrame property easily to perform the computation ourselves (Radar 11517886: UIMenuController menuFrame property incorrect while not visible). Thus, this code is more terrible than it should be.
            
            // Find a containing scroll view to clip against
            UIScrollView *scrollView = [unretained_editor containingViewMatching:^BOOL(UIView *view){
                if (![view isKindOfClass:[UIScrollView class]])
                    return NO;
                
                UIScrollView *candidateScrollView = (UIScrollView *)view;
                if (!candidateScrollView.scrollEnabled)
                    return NO; // Maybe embedded in a table view that is full-height in an inspector slice that is then in a scroll view
                
                return candidateScrollView.clipsToBounds;
            }];

            // If the top edge of our target rect is within some fudged contanst of the top edge of the scroll view, put the menu below.
            if (CGRectGetMinY([scrollView convertRect:targetRect fromView:unretained_editor]) < CGRectGetMinY(scrollView.bounds) + 50)
                menuController.arrowDirection = UIMenuControllerArrowUp;
            else
                menuController.arrowDirection = UIMenuControllerArrowDown;
        }
    }

    if ([menuController isMenuVisible] != shouldBeVisible) {
        DEBUG_MENU(@"  setMenuVisible: %d", shouldBeVisible);
        [menuController setMenuVisible:shouldBeVisible animated:YES];
    }
}

- (void)_menuDidHideHandler:(NSNotification *)notification;
{
    DEBUG_MENU(@"%s: %@", __func__, self);
    if (needsToShowMainMenuAfterCurrentMenuFinishesHiding) {
        needsToShowMainMenuAfterCurrentMenuFinishesHiding = NO;
        [self performSelector:@selector(showMainMenu) withObject:nil afterDelay:0.1];
    }
}

- (CGRect)_clippedRectForTargetRect:(CGRect)targetRect;
{
    // Intersects the target rectangle for the menu with all the clipping views above us, then converts back to the editor's coordinate system for passing to the menu controller.
    CGRect result = targetRect;
    UIView *currentView = unretained_editor;
    for (;;) {
        if ([currentView clipsToBounds])
            result = CGRectIntersection(result, currentView.bounds);
        UIView *nextView = currentView.superview;
        if (nextView == nil)
            break;
        result = [currentView convertRect:result toView:nextView];
        currentView = nextView;
    }
    return [currentView convertRect:result toView:unretained_editor];
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
