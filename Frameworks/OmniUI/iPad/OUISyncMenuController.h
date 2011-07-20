// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

enum {
    OUIMobileMeSync,
    OUIWebDAVSync,
    OUIiTunesSync,
    OUINumberSyncChoices,
    
    OUIOmniSync, /* still in beta */
}; 
typedef NSUInteger OUISyncType;

@interface OUISyncMenuController : UIViewController <UIPopoverControllerDelegate, UIActionSheetDelegate>
{
@private
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
    BOOL _isExporting;
}

+ (void)displayInSheet;

- (void)showMenuFromBarItem:(UIBarButtonItem *)barItem;

@property (nonatomic, assign) BOOL isExporting;
@end
