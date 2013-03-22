// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIServerAccountSetupViewController.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIEditableLabeledTableViewCell.h>
#import <OmniUI/OUIEditableLabeledValueCell.h>

#import "OUIServerAccountValidationViewController.h"

RCS_ID("$Id$")

@interface OUIServerAccountSetupViewControllerSectionLabel : UILabel
@end

@implementation OUIServerAccountSetupViewControllerSectionLabel
const CGFloat OUIServerAccountSetupViewControllerSectionLabelIndent = 32;    // default grouped, table row indent
// it would be more convenient to use -textRectForBounds:limitedToNumberOfLines: but that is not getting called
- (void)drawTextInRect:(CGRect)rect;
{
    rect.origin.x += 2*OUIServerAccountSetupViewControllerSectionLabelIndent;
    rect.size.width -= 3*OUIServerAccountSetupViewControllerSectionLabelIndent;
    
    [super drawTextInRect:rect];
}

@end

typedef enum {
    ServerAccountDescriptionSection,
    ServerAccountAddressSection,
    ServerAccountCredentialsSection,
    ServerAccountCloudSyncEnabledSection,
    ServerAccountSectionCount,
} ServerAccountSections;

typedef enum {
    ServerAccountCredentialsUsernameRow,
    ServerAccountCredentialsPasswordRow,
    ServerAccountCredentialsCount,
} ServerAccountCredentialRows;

#define CELL_AT(section,row) ((OUIEditableLabeledTableViewCell *)[_tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]])
#define TEXT_AT(section,row) CELL_AT(section,row).editableValueCell.valueField.text

@interface OUIServerAccountSetupViewController () <OUIEditableLabeledValueCellDelegate, UITableViewDataSource, UITableViewDelegate>
@end


@implementation OUIServerAccountSetupViewController
{
    UITableView *_tableView;
    OFXServerAccountType *_accountType;
    UIButton *_accountInfoButton;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (id)initWithAccount:(OFXServerAccount *)account ofType:(OFXServerAccountType *)accountType;
{
    OBPRECONDITION(accountType);
    OBPRECONDITION(!account || account.type == accountType);

    if (!(self = [self initWithNibName:nil bundle:nil]))
        return nil;
    
    _account = account;
    _accountType = accountType;
    
    return self;
}


#pragma mark - Actions

- (void)saveSettingsAndSync:(id)sender;
{
    NSString *displayName = TEXT_AT(ServerAccountDescriptionSection, 0);
    
    NSURL *serverURL = nil;
    if (_accountType.requiresServerURL)
        serverURL = [self _signinURLFromWebDAVString:TEXT_AT(ServerAccountAddressSection, 0)];
                     
    NSString *username = nil;
    if (_accountType.requiresUsername)
        username = TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow);
    
    NSString *password = nil;
    if (_accountType.requiresPassword)
        password = TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow);
    
    BOOL isCloudSyncEnabled = ((UISwitch *)(CELL_AT(ServerAccountCloudSyncEnabledSection, 0).accessoryView)).on;

    // Remember if this is a new account or if we are changing the configuration on an existing one.
    if (!_account) {
        NSURL *remoteBaseURL = OFSURLWithTrailingSlash([_accountType baseURLForServerURL:serverURL username:username]);
        
        NSError *error = nil;
        NSURL *documentsURL = [OFXServerAccount generateLocalDocumentsURLForNewAccount:&error];
        if (!documentsURL) {
            [self finishWithError:error];
            OUI_PRESENT_ALERT(error);
            return;
        }
        
        _account = [[OFXServerAccount alloc] initWithType:_accountType remoteBaseURL:remoteBaseURL localDocumentsURL:documentsURL]; // New account instead of editing one.
    }

    // Let us rename existing accounts even if their credentials aren't currently valid
    _account.displayName = displayName;
    _account.isCloudSyncEnabled = isCloudSyncEnabled;

    OUIServerAccountValidationViewController *validationViewController = [[OUIServerAccountValidationViewController alloc] initWithAccount:_account username:username password:password];

    validationViewController.finished = ^(OUIServerAccountValidationViewController *vc, NSError *errorOrNil){
        if (errorOrNil) {
            _account = nil; // Make a new instance if this one failed and wasn't added to the registry
            [self.navigationController popToViewController:self animated:YES];
            
            if ([errorOrNil causedByUserCancelling] == NO) {
                OUIAlert *alert = [[OUIAlert alloc] initWithTitle:errorOrNil.localizedDescription message:errorOrNil.localizedFailureReason cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"Alert button title") cancelAction:nil];
                
                [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Email Details", @"OmniUIDocument", OMNI_BUNDLE, @"Alert button title") action:^{
                    NSString *body = [NSString stringWithFormat:@"\n%@\n\n%@\n", [[OUIAppController controller] fullReleaseString], [errorOrNil toPropertyList]];
                    [[OUIAppController controller] sendFeedbackWithSubject:@"WebDAV conformance test failure" body:body];
                }];
                [alert show];
            }
        } else
            [self finishWithError:errorOrNil];
    };
    [self.navigationController pushViewController:validationViewController animated:YES];
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    
    _tableView.scrollEnabled = NO;
    
    self.view = _tableView;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [_tableView reloadData];
    
    if (self.navigationController.viewControllers[0] == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancel:)];
    }
    
    NSString *syncButtonTitle = NSLocalizedStringFromTableInBundle(@"Connect", @"OmniUIDocument", OMNI_BUNDLE, @"Account setup toolbar button title to save account settings");
    UIBarButtonItem *syncBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleDone target:self action:@selector(saveSettingsAndSync:)];
    self.navigationItem.rightBarButtonItem = syncBarButtonItem;
    
    self.navigationItem.title = _accountType.setUpAccountTitle;
    
    [self _validateSignInButton];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    OBFinishPortingLater("This isn't reliable -- it works in the WebDAV case, but not OSS, for whatever reason (likely because our UITableView isn't in the window yet");
    [_tableView layoutIfNeeded];
    
    if (_accountType.requiresServerURL)
        [CELL_AT(ServerAccountAddressSection, 0).editableValueCell.valueField becomeFirstResponder];
    else if (_accountType.requiresUsername)
        [CELL_AT(ServerAccountCredentialsSection, 0).editableValueCell.valueField becomeFirstResponder];
    
#ifdef DEBUG_bungi
    // Speedy account creation
    if (_account == nil) {
        CELL_AT(ServerAccountAddressSection, 0).editableValueCell.valueField.text = @"https://crispy.local:8001/test";
        CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow).editableValueCell.valueField.text = @"test";
        CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow).editableValueCell.valueField.text = @"password";
        [self _validateSignInButton];
    }
#endif
    
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return ServerAccountSectionCount;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    switch (section) {
        case ServerAccountDescriptionSection:
            return 1;
        case ServerAccountAddressSection:
            return _accountType.requiresServerURL ? 1 : 0;
        case ServerAccountCredentialsSection:
            OBASSERT(_accountType.requiresUsername);
            OBASSERT(_accountType.requiresPassword);
            return 2;
        case ServerAccountCloudSyncEnabledSection:
            return 1;
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            return 0;
    }
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == ServerAccountCloudSyncEnabledSection) {
        static NSString * const switchIdentifier = @"OUIServerAccountSetupViewControllerSwitch";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:switchIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UISwitch *accessorySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
            [accessorySwitch addTarget:self action:@selector(_validateSignInButton) forControlEvents:UIControlEventValueChanged];
            [accessorySwitch sizeToFit];
            cell.accessoryView = accessorySwitch;
        }

        NSString *title = NSLocalizedStringFromTableInBundle(@"OmniPresence", @"OmniUIDocument", OMNI_BUNDLE, @"for WebDAV OmniPresence edit field");

        cell.textLabel.text = title;

        UISwitch *accessorySwitch = (UISwitch *)cell.accessoryView;
        [accessorySwitch setOn:_account != nil ? _account.isCloudSyncEnabled : YES];
        
        return cell;
    }

    static NSString * const CellIdentifier = @"Cell";
    
    OUIEditableLabeledTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[OUIEditableLabeledTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        OUIEditableLabeledValueCell *contents = cell.editableValueCell;
        contents.valueField.autocorrectionType = UITextAutocorrectionTypeNo;
        contents.valueField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        contents.delegate = self;
        
        contents.valueField.returnKeyType = UIReturnKeyGo;
        contents.valueField.enablesReturnKeyAutomatically = YES;
    }
    
    OUIEditableLabeledValueCell *contents = cell.editableValueCell;

    NSInteger section = indexPath.section;
    switch (section) {
        case ServerAccountDescriptionSection:
            contents.label = NSLocalizedStringFromTableInBundle(@"Description", @"OmniUIDocument", OMNI_BUNDLE, @"for WebDAV address edit field");
            contents.value = _account.displayName;
            contents.valueField.placeholder = _accountType.displayName;
            contents.valueField.keyboardType = UIKeyboardTypeDefault;
            contents.valueField.secureTextEntry = NO;
            break;

        case ServerAccountAddressSection:
            OBFinishPortingLater("Should not allow editing existing remote URL / local directory pairs");
            contents.label = NSLocalizedStringFromTableInBundle(@"Address", @"OmniUIDocument", OMNI_BUNDLE, @"for WebDAV address edit field");
            contents.value = [_account.remoteBaseURL absoluteString];
            contents.valueField.placeholder = @"https://example.com/user/";
            contents.valueField.keyboardType = UIKeyboardTypeURL;
            contents.valueField.secureTextEntry = NO;
            break;

        case ServerAccountCredentialsSection: {
            switch (indexPath.row) {
                case ServerAccountCredentialsUsernameRow:
                    contents.label = NSLocalizedStringFromTableInBundle(@"Username", @"OmniUIDocument", OMNI_BUNDLE, @"for WebDAV username edit field");
                    contents.value = _account.credential.user;
                    contents.valueField.placeholder = nil;
                    contents.valueField.keyboardType = UIKeyboardTypeDefault;
                    contents.valueField.secureTextEntry = NO;
                    break;
                    
                case ServerAccountCredentialsPasswordRow:
                    contents.label = NSLocalizedStringFromTableInBundle(@"Password", @"OmniUIDocument", OMNI_BUNDLE, @"for WebDAV password edit field");
                    contents.value = _account.credential.password;
                    contents.valueField.placeholder = nil;
                    contents.valueField.secureTextEntry = YES;
                    contents.valueField.keyboardType = UIKeyboardTypeDefault;
                    break;
                    
                default:
                    OBASSERT_NOT_REACHED("Unknown credential row");
                    break;
            }
            break;
        }
        case ServerAccountSectionCount:
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            break;
    }
        
    return cell;
}

const CGFloat OUIServerAccountSetupViewControllerHeaderHeight = 40;
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;
{
    if (section == ServerAccountAddressSection && _accountType.requiresServerURL) {
        UILabel *header = [self _sectionLabelWithFrame:CGRectMake(150, 0, tableView.bounds.size.width-150, OUIServerAccountSetupViewControllerHeaderHeight)];
        header.text = NSLocalizedStringFromTableInBundle(@"Enter the location of your WebDAV space.", @"OmniUIDocument", OMNI_BUNDLE, @"webdav help");
        return header;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == ServerAccountAddressSection && _accountType.requiresServerURL) {
        return OUIServerAccountSetupViewControllerHeaderHeight;
    }
    
    return tableView.sectionHeaderHeight;
}

static const CGFloat OUIOmniSyncServerSetupFooterHeight = 144;

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section;
{
    if (section == ServerAccountCredentialsSection && [_accountType.identifier isEqualToString:OFXOmniSyncServerAccountTypeIdentifier]) {
        UIView *footerView = [[UIView alloc] initWithFrame:(CGRect){
            .origin.x = 0,
            .origin.y = 0,
            .size.width = 0, // Width will automatically be same as the table view it's put into.
            .size.height = OUIOmniSyncServerSetupFooterHeight
        }];
        
        // Account Info Button
        _accountInfoButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        _accountInfoButton.frame = (CGRect){
            .origin.x = 30,
            .origin.y = OUIOmniSyncServerSetupFooterHeight - 44 /* my height */,
            .size.width = 480,
            .size.height = 44
        };
        _accountInfoButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        
        [_accountInfoButton addTarget:self action:@selector(accountInfoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_accountInfoButton setTitle:NSLocalizedStringFromTableInBundle(@"Sign Up For a New Account", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server sign up button title")
                           forState:UIControlStateNormal];
        [_accountInfoButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [footerView addSubview:_accountInfoButton];
        
        // Message Label
        UILabel *messageLabel = [self _sectionLabelWithFrame:(CGRect){
            .origin.x = 0,
            .origin.y = _accountInfoButton.frame.origin.y - 40 /* my height */ - 10.0 /* padding at the bottom */,
            .size.width = tableView.bounds.size.width,
            .size.height = 40
        }];
        
        messageLabel.text = NSLocalizedStringFromTableInBundle(@"Omni Sync Server is a free service for sharing data between Omni applications on your Mac and iOS devices.", @"OmniUIDocument", OMNI_BUNDLE, @"omni sync server setup help");
        [footerView addSubview:messageLabel];

        
        return footerView;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if (section == ServerAccountCredentialsSection && [_accountType.identifier isEqualToString:OFXOmniSyncServerAccountTypeIdentifier])
        return OUIOmniSyncServerSetupFooterHeight;
    
    return tableView.sectionFooterHeight;
}

#pragma mark -
#pragma mark OUIEditableLabeledValueCell

- (void)editableLabeledValueCellTextDidChange:(OUIEditableLabeledValueCell *)cell;
{
    [self _validateSignInButton];
}

- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldShouldReturn:(UITextField *)textField;
{
    UIBarButtonItem *signInButton = self.navigationItem.rightBarButtonItem;
    BOOL trySignIn = signInButton.enabled;
    if (trySignIn)
        [self saveSettingsAndSync:nil];
    
    return trySignIn;
}

#pragma mark - Private

- (void)_cancel:(id)sender;
{
    [self cancel];
}

- (NSURL *)_signinURLFromWebDAVString:(NSString *)webdavString;
{
    NSURL *url = [NSURL URLWithString:webdavString];

    if (url == nil)
        url = [NSURL URLWithString:[webdavString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

    OFCreateRegularExpression(reasonableHostnameRegularExpression, @"^[-_$A-Za-z0-9]+\\.[-_$A-Za-z0-9]+");

    if ([url scheme] == nil && ![NSString isEmptyString:webdavString] && [reasonableHostnameRegularExpression of_firstMatchInString:webdavString])
        url = [NSURL URLWithString:[@"http://" stringByAppendingString:webdavString]];

    NSString *scheme = [url scheme];
    if (OFNOTEQUAL(scheme, @"http") && OFNOTEQUAL(scheme, @"https"))
        return nil;

    if ([NSString isEmptyString:[url host]])
        return nil;

    return url;
}

- (void)_validateSignInButton;
{
    UIBarButtonItem *signInButton = self.navigationItem.rightBarButtonItem;

    BOOL requirementsMet = YES;
    
    if (_accountType.requiresServerURL)
        requirementsMet &= ([self _signinURLFromWebDAVString:TEXT_AT(ServerAccountAddressSection, 0)] != nil);
    
    BOOL hasUsername = ![NSString isEmptyString:TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow)];
    if (_accountType.requiresUsername)
        requirementsMet &= hasUsername;
    
    if (_accountType.requiresPassword)
        requirementsMet &= ![NSString isEmptyString:TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow)];

    signInButton.enabled = requirementsMet;

    if ([_accountType.identifier isEqualToString:OFXOmniSyncServerAccountTypeIdentifier]) {
        // Validate Account 'button'
        [_accountInfoButton setTitle:hasUsername ? NSLocalizedStringFromTableInBundle(@"Account Info", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server account info button title") : NSLocalizedStringFromTableInBundle(@"Sign Up For a New Account", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server sign up button title")
                            forState:UIControlStateNormal];
    }
}

- (UILabel *)_sectionLabelWithFrame:(CGRect)frame;
{
    OUIServerAccountSetupViewControllerSectionLabel *header = [[OUIServerAccountSetupViewControllerSectionLabel alloc] initWithFrame:frame];
    header.textAlignment = NSTextAlignmentLeft;
    header.font = [UIFont systemFontOfSize:14];
    header.backgroundColor = [UIColor clearColor];
    header.opaque = NO;
    header.textColor = [UIColor colorWithRed:0.196 green:0.224 blue:0.29 alpha:1];
    header.shadowColor = [UIColor colorWithWhite:1 alpha:.5];
    header.shadowOffset = CGSizeMake(0, 1);
    header.numberOfLines = 0 /* no limit */;
    
    return header;
}

- (void)accountInfoButtonTapped:(id)sender;
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://www.omnigroup.com/sync/"]];
}

@end

