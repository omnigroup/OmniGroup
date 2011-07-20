// Copyright 2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OUIEditableFrame;
@protocol OUIEditableFrameDelegate;

@interface OUIEditMenuController : NSObject
{
@private
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
@property(nonatomic,assign) id<OUIEditableFrameDelegate> delegate;

@property(nonatomic,retain) NSArray *extraMainMenuItems;
@property(nonatomic,retain) NSArray *extraMenuItemsSelectors;

- (id)initWithEditableFrame:(OUIEditableFrame *)editableFrame;

- (void)showMainMenu;
    // Display the main menu, calling back to the editor for the target rectangle

- (void)showMainMenuAfterCurrentMenuFinishesHiding;
    // Wait for current menu to finish hiding, then call showMainMenu. Useful for redisplaying the menu from a current menu item's action.

- (void)hideMenu;
    // Take down the menu and reset to the default menu state

- (void)toggleMenuVisibility;
    // If the menu is supposed to be hidden, then show the main menu. If a menu is supposed to be showing, then hide it.
- (void)forceCorrectMenuDisplay;
    // We're showing/hiding the edit contextual menu immediately when needed. Unfortunately, the frameworks seem to knock it down sometimes, for example, after choosing Select All from the menu. This is a hack to force the state to match what we think it should be.


// Allow client to inhibit display of the menu for things like scrolling or thumb movements, while still remembering which menu we were looking at.
- (void)inhibitMenuFor:(NSString *)cause;
- (void)uninhibitMenuFor:(NSString *)cause;

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;


@end
