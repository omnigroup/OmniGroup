//
//  OUIUndoButtonController.h
//  OmniGraffle-iPad
//
//  Created by Ryan Patrick on 5/24/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//
// $Id$

#import <UIKit/UIKit.h>


@interface OUIUndoButtonController : UIViewController <UIPopoverControllerDelegate> {
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
    
    IBOutlet UIButton *undoButton;
    IBOutlet UIButton *redoButton;
}

- (void)showUndoMenu:(id)sender;
- (IBAction)undoButton:(id)sender;
- (IBAction)redoButton:(id)sender;

@end

@interface NSObject (OUIUndoButtonTarget)
- (void)undoButtonAction:(id)sender;
- (void)redoButtonAction:(id)sender;
@end
