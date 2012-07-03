// Copyright 2010-2012 The Omni Group. All rights reserved.
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

@property(nonatomic,assign) id<OUIEditableFrameDelegate> delegate;

@property(nonatomic,retain) NSArray *extraMainMenuItems;
@property(nonatomic,retain) NSArray *extraMenuItemsSelectors;

- (id)initWithEditableFrame:(OUIEditableFrame *)editableFrame;

- (void)invalidate; // Owning editable frame is discarding us.

- (void)showMainMenu;
    // Display the main menu, calling back to the editor for the target rectangle

- (void)showMainMenuAfterCurrentMenuFinishesHiding;
    // Wait for current menu to finish hiding, then call showMainMenu. Useful for redisplaying the menu from a current menu item's action.

- (void)hideMenu;
    // Take down the menu and reset to the default menu state

- (void)toggleMenuVisibility;
    // If the menu is supposed to be hidden, then show the main menu. If a menu is supposed to be showing, then hide it.

// Allow client to inhibit display of the menu for things like scrolling or thumb movements, while still remembering which menu we were looking at.
- (void)inhibitMenuFor:(NSString *)cause;
- (void)uninhibitMenuFor:(NSString *)cause;

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;


@end
