// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIServerAccountSetupViewController.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFileStore/Errors.h> // For OFSShouldOfferToReportError()
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIEditableLabeledTableViewCell.h>
#import <OmniUI/OUIEditableLabeledValueCell.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

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
    ServerAccountAddressSection,
    ServerAccountCredentialsSection,
    ServerAccountDescriptionSection,
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

@interface OUIServerAccountSetupViewController () <OUIEditableLabeledValueCellDelegate, UITableViewDataSource, UITableViewDelegate, MFMailComposeViewControllerDelegate>
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

    self.location = [_account.remoteBaseURL absoluteString];
    self.accountName = _account.credential.user;
    self.password = _account.credential.password;
    self.nickname = _account.nickname;

    return self;
}


#pragma mark - Actions

- (void)saveSettingsAndSync:(id)sender;
{
    NSString *nickname = TEXT_AT(ServerAccountDescriptionSection, 0);
    
    NSURL *serverURL = nil;
    if (_accountType.requiresServerURL)
        serverURL = [OFXServerAccount signinURLFromWebDAVString:TEXT_AT(ServerAccountAddressSection, 0)];
                     
    NSString *username = nil;
    if (_accountType.requiresUsername)
        username = TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow);
    
    NSString *password = nil;
    if (_accountType.requiresPassword)
        password = TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow);
    
    BOOL isCloudSyncEnabled = ((UISwitch *)(CELL_AT(ServerAccountCloudSyncEnabledSection, 0).accessoryView)).on;

    if (_account != nil) {
        // Some combinations of options require a new account
        BOOL needNewAccount = isCloudSyncEnabled != _account.isCloudSyncEnabled;

        NSURL *newRemoteBaseURL = OFURLWithTrailingSlash([_accountType baseURLForServerURL:serverURL username:username]);
        if (OFNOTEQUAL(newRemoteBaseURL, _account.remoteBaseURL))
            needNewAccount = YES;

        if (needNewAccount) {
            // We need to create a new account to enable cloud sync
            OFXServerAccount *oldAccount = _account;
            _account = nil;
            void (^oldFinished)(id viewController, NSError *errorOrNil) = self.finished;
            self.finished = ^(id viewController, NSError *errorOrNil) {
                if (errorOrNil != nil) {
                    // Pass along the error to our finished call
                    oldFinished(viewController, errorOrNil);
                } else {
                    // Success! Remove the old account.
                    [[OUIDocumentAppController controller] warnAboutDiscardingUnsyncedEditsInAccount:oldAccount withCancelAction:^{
                        oldFinished(viewController, nil);
                    } discardAction:^{
                        [oldAccount prepareForRemoval];
                        oldFinished(viewController, nil); // Go ahead and discard unsynced edits
                    }];
                }
            };
        }
    }

    // Remember if this is a new account or if we are changing the configuration on an existing one.
    BOOL needValidation;
    if (_account == nil) {
        NSURL *remoteBaseURL = OFURLWithTrailingSlash([_accountType baseURLForServerURL:serverURL username:username]);
        
        __autoreleasing NSError *error = nil;
        NSURL *documentsURL = [OFXServerAccount generateLocalDocumentsURLForNewAccount:&error];
        if (documentsURL == nil) {
            [self finishWithError:error];
            OUI_PRESENT_ALERT(error);
            return;
        }
        
        _account = [[OFXServerAccount alloc] initWithType:_accountType remoteBaseURL:remoteBaseURL localDocumentsURL:documentsURL error:&error]; // New account instead of editing one.
        if (!_account) {
            [self finishWithError:error];
            OUI_PRESENT_ALERT(error);
            return;
        }
        
        _account.isCloudSyncEnabled = isCloudSyncEnabled;
        needValidation = YES;
    } else {
        if (_accountType.requiresServerURL && OFNOTEQUAL(serverURL, _account.remoteBaseURL)) {
            needValidation = YES;
        } else if (_accountType.requiresUsername && OFNOTEQUAL(username, _account.credential.user)) {
            needValidation = YES;
        } else if (_accountType.requiresPassword && OFNOTEQUAL(password, _account.credential.password)) {
            needValidation = YES;
        } else {
            // isCloudSyncEnabled required a whole new account, so we don't need to test it
            needValidation = NO;
        }
    }

    // Let us rename existing accounts even if their credentials aren't currently valid
    _account.nickname = nickname;
    if (!needValidation) {
        [self finishWithError:nil];
        return;
    }

    // Validate the new account settings
    OBASSERT(_account.isCloudSyncEnabled == isCloudSyncEnabled); // If this changed, we created a new _account with it set properly

    OUIServerAccountValidationViewController *validationViewController = [[OUIServerAccountValidationViewController alloc] initWithAccount:_account username:username password:password];

    validationViewController.finished = ^(OUIServerAccountValidationViewController *vc, NSError *errorOrNil){
        if (errorOrNil != nil) {
            _account = nil; // Make a new instance if this one failed and wasn't added to the registry
            [self.navigationController popToViewController:self animated:YES];
            
            if (![errorOrNil causedByUserCancelling]) {
                [[OUIDocumentAppController controller] presentSyncError:errorOrNil inNavigationController:self.navigationController retryBlock:NULL];
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
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.backgroundView = nil;

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
    
    if (_accountType.requiresServerURL && [NSString isEmptyString:self.location])
        [CELL_AT(ServerAccountAddressSection, 0).editableValueCell.valueField becomeFirstResponder];
    else if (_accountType.requiresUsername && [NSString isEmptyString:self.accountName])
        [CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow).editableValueCell.valueField becomeFirstResponder];
    else if (_accountType.requiresPassword && [NSString isEmptyString:self.password])
        [CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow).editableValueCell.valueField becomeFirstResponder];

#ifdef DEBUG_bungi
    // Speedy account creation
    if (_account == nil) {
        CELL_AT(ServerAccountAddressSection, 0).editableValueCell.valueField.text = @"https://crispy.local:8001/test";
        CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow).editableValueCell.valueField.text = @"test";
        CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow).editableValueCell.valueField.text = @"password";
    }
#endif

    [self _validateSignInButton];
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

- (NSString *)_suggestedNickname;
{
    NSURL *url = [OFXServerAccount signinURLFromWebDAVString:TEXT_AT(ServerAccountAddressSection, 0)];
    NSString *username = TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow);
    return [OFXServerAccount suggestedDisplayNameForAccountType:_accountType url:url username:username excludingAccount:_account];

#if 0
    if (_accountType.requiresServerURL) {
        NSURL *locationURL = [OFXServerAccount signinURLFromWebDAVString:TEXT_AT(ServerAccountAddressSection, 0)];
        if (locationURL != nil)
            return [locationURL host];
    }

    return _accountType.displayName;
#endif
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
        cell.textLabel.font = [OUIEditableLabeledValueCell labelFontForStyle:OUILabeledValueCellStyleDefault];

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
    NSString *localizedLocationLabelString = NSLocalizedStringFromTableInBundle(@"Location", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: location");
    NSString *localizedNicknameLabelString = NSLocalizedStringFromTableInBundle(@"Nickname", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: nickname");
    NSString *localizedUsernameLabelString = NSLocalizedStringFromTableInBundle(@"Account Name", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: account name");
    NSString *localizedPasswordLabelString = NSLocalizedStringFromTableInBundle(@"Password", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: password");
    UIFont *font = [OUIEditableLabeledValueCell labelFontForStyle:contents.style];

    static CGFloat minWidth = 0.0f;

    if (minWidth == 0.0f) {
        CGSize locationLabelSize = [localizedLocationLabelString sizeWithFont:font];
        CGSize usernameLabelSize = [localizedUsernameLabelString sizeWithFont:font];
        CGSize passwordLabelSize = [localizedPasswordLabelString sizeWithFont:font];
        CGSize nicknameLabelSize = [localizedNicknameLabelString sizeWithFont:font];
        minWidth = MAX(locationLabelSize.width, MAX(usernameLabelSize.width, MAX(passwordLabelSize.width, nicknameLabelSize.width)));
    }

    switch (section) {
        case ServerAccountDescriptionSection:
            contents.label = localizedNicknameLabelString;
            contents.value = self.nickname;
            contents.valueField.placeholder = [self _suggestedNickname];
            contents.valueField.keyboardType = UIKeyboardTypeDefault;
            contents.valueField.secureTextEntry = NO;
            contents.minimumLabelWidth = minWidth;
            contents.labelAlignment = NSTextAlignmentRight;
            break;

        case ServerAccountAddressSection:
            contents.label = localizedLocationLabelString;
            contents.value = self.location;
            contents.valueField.placeholder = @"https://example.com/account/";
            contents.valueField.keyboardType = UIKeyboardTypeURL;
            contents.valueField.secureTextEntry = NO;
            contents.minimumLabelWidth = minWidth;
            contents.labelAlignment = NSTextAlignmentRight;
            break;

        case ServerAccountCredentialsSection: {
            
            switch (indexPath.row) {
                case ServerAccountCredentialsUsernameRow:
                    contents.label = localizedUsernameLabelString;
                    contents.value = self.accountName;
                    contents.valueField.placeholder = nil;
                    contents.valueField.keyboardType = UIKeyboardTypeDefault;
                    contents.valueField.secureTextEntry = NO;
                    contents.minimumLabelWidth = minWidth;
                    contents.labelAlignment = NSTextAlignmentRight;
                    break;
                    
                case ServerAccountCredentialsPasswordRow:
                    contents.label = localizedPasswordLabelString;
                    contents.value = self.password;
                    contents.valueField.placeholder = nil;
                    contents.valueField.secureTextEntry = YES;
                    contents.valueField.keyboardType = UIKeyboardTypeDefault;
                    contents.minimumLabelWidth = minWidth;
                    contents.labelAlignment = NSTextAlignmentRight;
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

static const CGFloat OUIOmniSyncServerSetupHeaderHeight = 44;
static const CGFloat OUIServerAccountSetupViewControllerHeaderHeight = 40;
static const CGFloat OUIServerAccountSeendSettingsFooterHeight = 140;

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;
{
    if (section == ServerAccountCredentialsSection && [_accountType.identifier isEqualToString:OFXOmniSyncServerAccountTypeIdentifier]) {
        UIView *headerView = [[UIView alloc] initWithFrame:(CGRect){
            .origin.x = 0,
            .origin.y = 0,
            .size.width = 0, // Width will automatically be same as the table view it's put into.
            .size.height = OUIOmniSyncServerSetupHeaderHeight
        }];
        
        // Account Info Button
        _accountInfoButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        _accountInfoButton.frame = (CGRect){
            .origin.x = 30,
            .origin.y = OUIOmniSyncServerSetupHeaderHeight - 44 /* my height */,
            .size.width = 480,
            .size.height = 44
        };
        _accountInfoButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        
        [_accountInfoButton addTarget:self action:@selector(accountInfoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_accountInfoButton setTitle:NSLocalizedStringFromTableInBundle(@"Sign Up", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server sign up button title")
                            forState:UIControlStateNormal];
        [_accountInfoButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [headerView addSubview:_accountInfoButton];

#if 0
        // Message Label
        UILabel *messageLabel = [self _sectionLabelWithFrame:(CGRect){
            .origin.x = 0,
            .origin.y = _accountInfoButton.frame.origin.y - 40 /* my height */ - 10.0 /* padding at the bottom */,
            .size.width = tableView.bounds.size.width,
            .size.height = 40
        }];
        
        messageLabel.text = NSLocalizedStringFromTableInBundle(@"Easily sync Omni documents between devices. Signup is free!", @"OmniUIDocument", OMNI_BUNDLE, @"omni sync server setup help");
        [headerView addSubview:messageLabel];
#endif
        return headerView;
    }

    if (section == ServerAccountAddressSection && _accountType.requiresServerURL) {
        UILabel *header = [self _sectionLabelWithFrame:CGRectMake(150, 0, tableView.bounds.size.width-150, OUIServerAccountSetupViewControllerHeaderHeight)];
        header.text = NSLocalizedStringFromTableInBundle(@"Enter the location of your WebDAV space.", @"OmniUIDocument", OMNI_BUNDLE, @"webdav help");
        return header;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == ServerAccountCredentialsSection && [_accountType.identifier isEqualToString:OFXOmniSyncServerAccountTypeIdentifier])
        return OUIOmniSyncServerSetupHeaderHeight + tableView.sectionHeaderHeight;

    if (section == ServerAccountAddressSection && _accountType.requiresServerURL) 
        return OUIServerAccountSetupViewControllerHeaderHeight;
    
    return tableView.sectionHeaderHeight;
}


- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section;
{
    if (section == ServerAccountCloudSyncEnabledSection) {
        UIView *footerView = [[UIView alloc] initWithFrame:(CGRect){
            .origin.x = 0,
            .origin.y = 0,
            .size.width = 0, // Width will automatically be same as the table view it's put into.
            .size.height = OUIServerAccountSeendSettingsFooterHeight
        }];
        
        UILabel *messageLabel = [self _sectionLabelWithFrame:(CGRect){
            .origin.x = 0,
            .origin.y = 10,
            .size.width = 480,
            .size.height = 40
        }];
        
        messageLabel.text = NSLocalizedStringFromTableInBundle(@"OmniPresence automatically keeps your documents up to date on all of your iPads and Macs.", @"OmniUIDocument", OMNI_BUNDLE, @"omni sync server nickname help");
        
        [footerView addSubview:messageLabel];
        
        // Send Settings Button
        if ([MFMailComposeViewController canSendMail]) {
            OFXServerAccountRegistry *serverAccountRegistry = [OFXServerAccountRegistry defaultAccountRegistry];
            BOOL shouldEnableSettingsButton = [serverAccountRegistry.validCloudSyncAccounts containsObject:self.account] || [serverAccountRegistry.validImportExportAccounts containsObject:self.account];
            
            UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
            settingsButton.frame = (CGRect){
                .origin.x = 30,
                .origin.y = OUIServerAccountSeendSettingsFooterHeight - 44 /* my height */,
                .size.width = 480,
                .size.height = 44
            };
            settingsButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
            settingsButton.enabled = shouldEnableSettingsButton;
            
            [settingsButton addTarget:self action:@selector(sendSettingsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [settingsButton setTitle:NSLocalizedStringFromTableInBundle(@"Send Settings via Email", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server send settings button title")
                                forState:UIControlStateNormal];
            [settingsButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            [footerView addSubview:settingsButton];
        }
        
        
        return footerView;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if (section == ServerAccountCloudSyncEnabledSection)
        return OUIServerAccountSeendSettingsFooterHeight;
    
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

- (void)_validateSignInButton;
{
    UIBarButtonItem *signInButton = self.navigationItem.rightBarButtonItem;

    BOOL requirementsMet = YES;
    
    if (_accountType.requiresServerURL)
        requirementsMet &= ([OFXServerAccount signinURLFromWebDAVString:TEXT_AT(ServerAccountAddressSection, 0)] != nil);
    
    BOOL hasUsername = ![NSString isEmptyString:TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow)];
    if (_accountType.requiresUsername)
        requirementsMet &= hasUsername;
    
    if (_accountType.requiresPassword)
        requirementsMet &= ![NSString isEmptyString:TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow)];

    signInButton.enabled = requirementsMet;
    CELL_AT(ServerAccountDescriptionSection, 0).editableValueCell.valueField.placeholder = [self _suggestedNickname];

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

- (NSString *)_accountName;
{
    NSString *currentNickname = TEXT_AT(ServerAccountDescriptionSection, 0);
    if (currentNickname != nil)
        return currentNickname;
    else
        return [self _suggestedNickname];
}

- (void)sendSettingsButtonTapped:(id)sender;
{
    NSMutableDictionary *contents = [NSMutableDictionary dictionary];
    [contents setObject:_accountType.identifier forKey:@"accountType" defaultObject:nil];
    [contents setObject:TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow) forKey:@"accountName" defaultObject:nil];
    // [contents setObject:TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow) forKey:@"password" defaultObject:nil];
    if (_accountType.requiresServerURL)
        [contents setObject:TEXT_AT(ServerAccountAddressSection, 0) forKey:@"location" defaultObject:nil];
    [contents setObject:TEXT_AT(ServerAccountDescriptionSection, 0) forKey:@"nickname" defaultObject:nil];

    NSString *error;
    NSData *configData = [NSPropertyListSerialization dataFromPropertyList:contents format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
    
    MFMailComposeViewController *composer = [[MFMailComposeViewController alloc] init];
    composer.mailComposeDelegate = self;
    [composer setSubject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"OmniPresence Configuration: %@", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Presence config email subject format"), [self _accountName]]];
    [composer setMessageBody:NSLocalizedStringFromTableInBundle(@"Open this file on another device to configure OmniPresence there.", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Presence config email body") isHTML:NO];
    [composer addAttachmentData:configData mimeType:@"application/vnd.omnigroup.omnipresence.config" fileName:[[self _accountName] stringByAppendingPathExtension:@"omnipresence-config"]];
    [self presentViewController:composer animated:YES completion:nil];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


@end

