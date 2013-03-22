// Copyright 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <UIKit/UIPopoverController.h>
#import <OmniUI/OUIUndoBarButtonItem.h>

@protocol OUIUndoButtonTarget, OUIUndoBarButtonItem;

@interface OUIUndoButtonController : UIViewController <UIPopoverControllerDelegate>

@property(nonatomic,retain) IBOutlet UIButton *undoButton;
@property(nonatomic,retain) IBOutlet UIButton *redoButton;

- (IBAction)undoButtonAction:(id)sender;
- (IBAction)redoButtonAction:(id)sender;
- (void)showUndoMenuFromItem:(OUIUndoBarButtonItem *)item;
- (BOOL)dismissUndoMenu;
- (BOOL)isMenuVisible;

@property(nonatomic,assign) id <OUIUndoBarButtonItemTarget> undoBarButtonItemTarget;

@end
