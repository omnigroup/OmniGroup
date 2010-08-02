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

@class UIBarButtonItem, UIPopoverController, UINavigationController, UITableView;

@interface OUIAppMenuController : UIViewController <UIPopoverControllerDelegate>
{
@private
    BOOL _needsReloadOfDocumentsItem;
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
}

- (void)showMenuFromBarItem:(UIBarButtonItem *)barItem;
- (void)dismiss;

@end

// These currently must all be implemented somewhere in the responder chain.
@interface NSObject (OUIAppMenuTarget)
- (void)showOnlineHelp:(id)sender;
- (void)sendFeedback:(id)sender;
- (void)showReleaseNotes:(id)sender;
- (void)runTests:(id)sender;
@end
