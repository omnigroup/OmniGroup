// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIImportWebDAVAccountListViewController.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>

#import "OUIWebDAVSyncListController.h"

RCS_ID("$Id$");

@interface OUIImportWebDAVAccountListViewController ()

@property (nonatomic, strong) NSArray *validImportAccounts;

@end

@implementation OUIImportWebDAVAccountListViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.validImportAccounts = [OFXServerAccountRegistry defaultAccountRegistry].validImportExportAccounts;
        self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Import", @"OmniUIDocument", OMNI_BUNDLE, @"Import WebDAV server account list");
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.clearsSelectionOnViewWillAppear = NO;
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelButtonTapped:)];
}

- (void)cancelButtonTapped:(id)sender;
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.validImportAccounts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *accountCellId = @"accountCellId";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:accountCellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:accountCellId];
        cell.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.image = [UIImage imageNamed:@"OUIGenericWebDAV"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    OFXServerAccount *account = self.validImportAccounts[indexPath.row];
    
    cell.textLabel.text = account.importTitle;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (self.didSelectAccountAction) {
        OFXServerAccount *account = self.validImportAccounts[indexPath.row];
        self.didSelectAccountAction(account);
    }
}

@end
