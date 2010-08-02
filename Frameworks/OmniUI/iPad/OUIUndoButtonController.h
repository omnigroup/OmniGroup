// Copyright 2010 The Omni Group.  All rights reserved.
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
{
@private
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
    
    UIButton *_undoButton;
    UIButton *_redoButton;
    
    id <OUIUndoBarButtonItemTarget> undoBarButtonItemTarget;
}

@property(retain) IBOutlet UIButton *undoButton;
@property(retain) IBOutlet UIButton *redoButton;

- (IBAction)undoButtonAction:(id)sender;
- (IBAction)redoButtonAction:(id)sender;
- (void)showUndoMenuFromItem:(OUIUndoBarButtonItem *)item;
- (BOOL)dismissUndoMenu;

@property (nonatomic, assign) id <OUIUndoBarButtonItemTarget> undoBarButtonItemTarget;

@end
