// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITableViewController.h>

enum {
    SetUpSyncControllerHeadingSection = 0,
    SetUpSyncControllerNumHeadingRows = 1
};

// Note to Subclassers:
//
// Generally you should call super for any UITableView delegate and data source methods which a) are declared in the interface for this class and b) for cases you don't handle.
// In particular, the height of the heading section+row is specified by this class, which also provides the data cell.

@interface OUISetUpSyncBaseController : UITableViewController
{
@private
    UIBarButtonItem *_syncBarButtonItem;
    UILabel *_titleLabel;
    UIButton *_syncButton;
    UIButton *_cancelButton;
    UIView *_tableHeaderView;
    UIView *_tableFooterView;
    UIView *_footerView;
    NSString *_syncMethodText;
    NSString *_syncMethodDetailText;
    BOOL _showsSelectedModeCheckmark;
}

+ (UIView *)informativeViewWithText:(NSString *)text;
+ (UIView *)informativeViewWithText:(NSString *)text topMargin:(CGFloat)topMargin bottomMargin:(CGFloat)bottomMargin;

// Designated initializer
- (id)init;

@property (nonatomic, retain) IBOutlet UILabel *titleLabel;

@property (nonatomic, retain) IBOutlet UIButton *syncButton;
@property (nonatomic, retain) IBOutlet UIButton *cancelButton;

@property (nonatomic, retain) IBOutlet UIView *tableHeaderView;
@property (nonatomic, retain) IBOutlet UIView *tableFooterView;

@property (nonatomic, retain) IBOutlet UIView *footerView;

- (IBAction)cancel;
- (IBAction)saveSettingsAndSync;

// Auxillary nib subclass would like loaded at loadView time
@property (nonatomic, readonly) NSString *auxillaryNibName;

@property (nonatomic, copy) NSString *syncMethodText;
@property (nonatomic, copy) NSString *syncMethodDetailText;
@property (nonatomic) BOOL showsSelectedModeCheckmark;

// Subclasses should override this to return the union of super's return value, and all of their own text fields which must be non-empty for the sync button to be enabled.
- (NSSet *)textFieldsAffectingSyncButtonEnabledState;

// Subclassers should send -validateSyncButton if they do something which affects the enabled state of the sync button outside of any text fields covered by -textFieldsAffectingSyncButtonEnabledState. They should typically not override this method.
- (void)validateSyncButton;

// Subclassers can override this method to mix in additional logic as to whether the sync button should be enabled
- (BOOL)canSaveSettingsAndSync;

// Table view delegate/data source
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;

@end

@interface OUISetUpSyncBaseController (SubclassUtilities)

- (UITextField *)textFieldForEditableLabeledValueCellWithTag:(NSInteger)tag inRowAtIndexPath:(NSIndexPath *)indexPath;

@end

void SetUpSyncBadgeTableViewCellWithImage(UITableViewCell *cell, UIImage *image);
