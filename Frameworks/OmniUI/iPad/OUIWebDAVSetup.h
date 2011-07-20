// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITableViewController.h>

#import "OUISyncMenuController.h"
#import "OUIEditableLabeledValueCell.h"

extern NSString * const OUIWebDAVLocation;
extern NSString * const OUIWebDAVUsername;
extern NSString * const OUIMobileMeUsername;
extern NSString * const OUIOmniSyncUsername;

@interface OUIWebDAVSetup : UITableViewController <OUIEditableLabeledValueCellDelegate>
{
@private 
    UITextField *_nonretainedAddressField;
    UITextField *_nonretainedPasswordField;
    UITextField *_nonretainedUsernameField;
    NSUInteger _syncType;
    BOOL _isExporting;
}

@property (nonatomic, assign) OUISyncType syncType;
@property (nonatomic, assign) BOOL isExporting;
@end
