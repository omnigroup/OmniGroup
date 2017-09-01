// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIServerAccountSetupViewController.h>
#import <OmniUIDocument/OUIServerAccountSetupViewController-Subclass.h>

#import <OmniDAV/ODAVErrors.h> // For OFSShouldOfferToReportError()
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIEditableLabeledTableViewCell.h>
#import <OmniUI/OUIEditableLabeledValueCell.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniAppKit/OAAppearance.h>
#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniAppKit/OAAppearanceColors.h>
#import <OmniUI/OUICustomSubclass.h>

#import "OUIServerAccountValidationViewController.h"

RCS_ID("$Id$")

static const CGFloat TableViewIndent = 15;

@interface OUIServerAccountSetupViewControllerSectionLabel : UILabel
@end

@implementation OUIServerAccountSetupViewControllerSectionLabel
- (void)drawTextInRect:(CGRect)rect;
{
    // Would be less lame to make containing UIView with a label inset from the edges so that UITableView could set the frame of our view as it wishes w/o this hack.
    rect.origin.x += TableViewIndent;
    rect.size.width -= TableViewIndent;
    
    [super drawTextInRect:rect];
}

@end


#define CELL_AT(section,row) ((OUIEditableLabeledTableViewCell *)[_tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]])
#define TEXT_AT(section,row) [self textAtSection:section andRow:row]

@interface OUIServerAccountSetupViewController () <OUIEditableLabeledValueCellDelegate, UITableViewDataSource, UITableViewDelegate, MFMailComposeViewControllerDelegate>
@end


@implementation OUIServerAccountSetupViewController
{
    UIButton *_accountInfoButton;
    NSMutableDictionary *_cachedTextValues;
    OFXServerAccountUsageMode _usageModeToCreate;
    BOOL _showDeletionSection;
}

+ (id)allocWithZone:(NSZone *)zone;
{
    OUIAllocateCustomClass;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

static void _commonInit(OUIServerAccountSetupViewController *self)
{
    self->_cachedTextValues = [[NSMutableDictionary alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardHeightWillChange:) name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
}

- (id)initForCreatingAccountOfType:(OFXServerAccountType *)accountType withUsageMode:(OFXServerAccountUsageMode)usageModeToCreate;
{
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    _commonInit(self);
    
    _accountType = accountType;
    _usageModeToCreate = usageModeToCreate;
    _showDeletionSection = NO;
    
    return self;
}

- (id)initWithAccount:(OFXServerAccount *)account
{
    OBPRECONDITION(account);

    if (!(self = [self initWithNibName:nil bundle:nil]))
        return nil;
    
    _commonInit(self);
    
    _account = account;
    _accountType = account.type;
    _usageModeToCreate = account.usageMode; // in case we need to destroy and recreate the account due to any edits
    _showDeletionSection = YES;
    
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(_account.credentialServiceIdentifier, NULL);

    self.location = [_account.remoteBaseURL absoluteString];
    self.accountName = credential.user;
    self.password = credential.password;
    self.nickname = _account.nickname;

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
}

- (NSString *)textAtSection:(NSUInteger)section andRow:(NSUInteger)row;
{
    NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
    return [_cachedTextValues objectForKey:path];
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

    if (_account != nil) {
        // Some combinations of options require a new account
        NSURL *newRemoteBaseURL = OFURLWithTrailingSlash([_accountType baseURLForServerURL:serverURL username:username]);
        if (OFNOTEQUAL(newRemoteBaseURL, _account.remoteBaseURL)) {
            // We need to create a new account to enable cloud sync
            OFXServerAccount *oldAccount = _account;
            _account = nil;
            void (^oldFinished)(id viewController, NSError *errorOrNil) = self.finished;
            self.finished = ^(id viewController, NSError *errorOrNil) {
                if (errorOrNil != nil) {
                    // Pass along the error to our finished call
                    if (oldFinished)
                        oldFinished(viewController, errorOrNil);
                } else {
                    // Success! Remove the old account.
                    [[OUIDocumentAppController controller] warnAboutDiscardingUnsyncedEditsInAccount:oldAccount withCancelAction:^{
                        if (oldFinished)
                            oldFinished(viewController, nil);
                    } discardAction:^{
                        [oldAccount prepareForRemoval];
                        if (oldFinished)
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
            OUI_PRESENT_ALERT_FROM(error, self);
            return;
        }
        
        _account = [[OFXServerAccount alloc] initWithType:_accountType usageMode:_usageModeToCreate remoteBaseURL:remoteBaseURL localDocumentsURL:documentsURL error:&error]; // New account instead of editing one.
        if (!_account) {
            [self finishWithError:error];
            OUI_PRESENT_ALERT_FROM(error, self);
            return;
        }
        
        needValidation = YES;
    } else {
        NSURLCredential *credential = nil;
        if (_account.credentialServiceIdentifier)
            credential = OFReadCredentialsForServiceIdentifier(_account.credentialServiceIdentifier, NULL);
        
        if (_accountType.requiresServerURL && OFNOTEQUAL(serverURL, _account.remoteBaseURL)) {
            needValidation = YES;
        } else if (_accountType.requiresUsername && OFNOTEQUAL(username, credential.user)) {
            needValidation = YES;
        } else if (_accountType.requiresPassword && OFNOTEQUAL(password, credential.password)) {
            needValidation = YES;
        } else {
            // isCloudSyncEnabled required a whole new account, so we don't need to test it
            needValidation = NO;
        }
    }
    
    // Let us rename existing accounts even if their credentials aren't currently valid
    _account.nickname = nickname;
    if (!needValidation) {
        [self _validateSignInButton];
        return;
    }

    // Validate the new account settings

    OUIServerAccountValidationViewController *validationViewController = [[OUIServerAccountValidationViewController alloc] initWithAccount:_account username:username password:password];

    validationViewController.finished = ^(OUIServerAccountValidationViewController *vc, NSError *errorOrNil){
        if (errorOrNil != nil) {
            _account = nil; // Make a new instance if this one failed and wasn't added to the registry
            [self.navigationController popToViewController:self animated:YES];
            
            if (![errorOrNil causedByUserCancelling]) {
                // Passing a nil account so that this doesn't present an option to edit an account ... since we are already doing that.
                [[OUIDocumentAppController controller] presentSyncError:errorOrNil forAccount:nil inViewController:self.navigationController retryBlock:NULL];
            }
        } else {
            [self finishWithError:errorOrNil];
            [self.navigationController popToRootViewControllerAnimated:YES];
        }
    };
    [self.navigationController pushViewController:validationViewController animated:YES];
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    
    _tableView.scrollEnabled = YES;
    _tableView.alwaysBounceVertical = NO;

    self.view = _tableView;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [_tableView reloadData];
    
    if (self.navigationController.viewControllers[0] == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancel:)];
    }
    
    NSString *syncButtonTitle = NSLocalizedStringFromTableInBundle(@"Save", @"OmniUIDocument", OMNI_BUNDLE, @"Account setup toolbar button title to save account settings");
    UIBarButtonItem *syncBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleDone target:self action:@selector(saveSettingsAndSync:)];
    self.navigationItem.rightBarButtonItem = syncBarButtonItem;
    
    self.navigationItem.title = _accountType.setUpAccountTitle;
    
    [self _validateSignInButton];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    OBFinishPortingLater("<bug:///147833> (iOS-OmniOutliner Bug: OUIServerAccountSetupViewController.m:281 - This isn't reliable -- it works in the WebDAV case, but not OSS, for whatever reason (likely because our UITableView isn't in the window yet)");
    [_tableView layoutIfNeeded];
    
#if 0 && defined(DEBUG_bungi)
    // Speedy account creation
    if (_account == nil) {
        CELL_AT(ServerAccountAddressSection, 0).editableValueCell.valueField.text = @"https://crispix.local:8001/test";
        CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow).editableValueCell.valueField.text = @"test";
        CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow).editableValueCell.valueField.text = @"password";
    }
#endif

    [self _validateSignInButton];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    if (_accountType.requiresServerURL && [NSString isEmptyString:self.location])
        [CELL_AT(ServerAccountAddressSection, 0).editableValueCell.valueField becomeFirstResponder];
    else if (_accountType.requiresUsername && [NSString isEmptyString:self.accountName])
        [CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow).editableValueCell.valueField becomeFirstResponder];
    else if (_accountType.requiresPassword && [NSString isEmptyString:self.password])
        [CELL_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow).editableValueCell.valueField becomeFirstResponder];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    if (_showDeletionSection)
        return ServerAccountSectionCount;
    else
        return ServerAccountSectionCount - 1;
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
        case ServerAccountDeletionSection:
            OBASSERT(_showDeletionSection);
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
    
    if (indexPath.section == ServerAccountDeletionSection) {
        OBASSERT(_showDeletionSection);
        return [self deletionCellForTableView:tableView];
    }
    
    OUIEditableLabeledTableViewCell *cell;
    if (indexPath.section == ServerAccountCredentialsSection && indexPath.row == ServerAccountCredentialsPasswordRow) {
        cell = [self valueCellOfType:OUIValueCellTypePassword forTableView:tableView];
    }
    else {
        cell = [self valueCellOfType:OUIValueCellTypePlaintext forTableView:tableView];
    }
    
    OUIEditableLabeledValueCell *contents = cell.editableValueCell;

    NSInteger section = indexPath.section;
    NSString *localizedLocationLabelString = NSLocalizedStringFromTableInBundle(@"Location", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: location");
    NSString *localizedNicknameLabelString = NSLocalizedStringFromTableInBundle(@"Nickname", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: nickname");
    NSString *localizedUsernameLabelString = NSLocalizedStringFromTableInBundle(@"Account Name", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: account name");
    NSString *localizedPasswordLabelString = NSLocalizedStringFromTableInBundle(@"Password", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup label: password");
    
    NSDictionary *attributes = @{NSFontAttributeName: [OUIEditableLabeledValueCell labelFont]};

    static CGFloat minWidth = 0.0f;

    if (minWidth == 0.0f) {
        // Lame... should really use the UITextField's width, not NSStringDrawing
        CGSize locationLabelSize = [localizedLocationLabelString sizeWithAttributes:attributes];
        CGSize usernameLabelSize = [localizedUsernameLabelString sizeWithAttributes:attributes];
        CGSize passwordLabelSize = [localizedPasswordLabelString sizeWithAttributes:attributes];
        CGSize nicknameLabelSize = [localizedNicknameLabelString sizeWithAttributes:attributes];
        minWidth = ceil(4 + MAX(locationLabelSize.width, MAX(usernameLabelSize.width, MAX(passwordLabelSize.width, nicknameLabelSize.width))));
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
            contents.valueField.placeholder = OBUnlocalized(@"https://example.com/account/");
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
    
    NSString *_cachedValue = [_cachedTextValues objectForKey:indexPath];
    if (_cachedValue)
        contents.value = _cachedValue;
    else if (contents.value)
        [_cachedTextValues setObject:contents.value forKey:indexPath];
    else
        [_cachedTextValues removeObjectForKey:indexPath];
    return cell;
}

// NB: For now this is private. If we ever make it public for customizing in subclasses or such, we should consider integrating it into valueCellOfType:forTableView: below.
- (nonnull UITableViewCell *)deletionCellForTableView:(UITableView *)tableView
{
    static NSString *const DeletionCellIdentifier = @"DeletionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DeletionCellIdentifier];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:DeletionCellIdentifier];
    cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Delete Account", @"OmniUIDocument", OMNI_BUNDLE, @"Server Account Setup button label");
    cell.textLabel.textColor = [OAAppearanceDefaultColors appearance].omniDeleteColor;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    return cell;
    
}

// By default, we'll ignore the type parameter and make the same kind of cell for passwords and plain text.
// Subclasses may choose to do things differently.
- (nonnull OUIEditableLabeledTableViewCell *)valueCellOfType:(OUIValueCellType)type forTableView:(UITableView *)tableView;
{
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
    return cell;
}



static const CGFloat OUIOmniSyncServerSetupHeaderHeight = 44;
static const CGFloat OUIServerAccountSetupViewControllerHeaderHeight = 40;
static const CGFloat OUIServerAccountSendSettingsFooterHeight = 120;

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
        _accountInfoButton = [UIButton buttonWithType:UIButtonTypeSystem];

        _accountInfoButton.titleLabel.font = [UIFont systemFontOfSize:17];
        [_accountInfoButton addTarget:self action:@selector(accountInfoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_accountInfoButton setTitle:NSLocalizedStringFromTableInBundle(@"Sign Up For a New Account", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server sign up button title")
                            forState:UIControlStateNormal];
        [_accountInfoButton sizeToFit];
        
        CGRect frame = _accountInfoButton.frame;
        frame.origin.x = TableViewIndent;
        frame.origin.y = OUIOmniSyncServerSetupHeaderHeight - 44;
        _accountInfoButton.frame = frame;
        
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
        UILabel *header = [self _sectionLabelWithFrame:CGRectMake(TableViewIndent, 0, tableView.bounds.size.width - TableViewIndent, OUIServerAccountSetupViewControllerHeaderHeight)];
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
    if (section == ServerAccountSectionCount - 1) {
        
        if (!_account || _account.usageMode != OFXServerAccountUsageModeCloudSync)
            return nil;
        
        CGFloat height = OUIServerAccountSendSettingsFooterHeight;
        
        OBFinishPortingLater("<bug:///105469> (Unassigned: Make Cloud Setup accommodate the keyboard correctly [adaptability])");
        if (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone) { // add space to scroll up with keyboard showing
            height += 220;
        }
        
        UIView *footerView = [[UIView alloc] initWithFrame:(CGRect){
            .origin.x = 0,
            .origin.y = 0,
            .size.width = 0, // Width will automatically be same as the table view it's put into.
            .size.height = height
        }];
        
        
        // Send Settings Button
        if ([MFMailComposeViewController canSendMail]) {
            OFXServerAccountRegistry *serverAccountRegistry = [OFXServerAccountRegistry defaultAccountRegistry];
            BOOL shouldEnableSettingsButton = [serverAccountRegistry.validCloudSyncAccounts containsObject:self.account] || [serverAccountRegistry.validImportExportAccounts containsObject:self.account];
            
            UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
            settingsButton.titleLabel.font = [UIFont systemFontOfSize:17];
            settingsButton.enabled = shouldEnableSettingsButton;
            
            [settingsButton addTarget:self action:@selector(sendSettingsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [settingsButton setTitle:NSLocalizedStringFromTableInBundle(@"Send Settings via Email", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server send settings button title")
                                forState:UIControlStateNormal];
            [settingsButton sizeToFit];
            
            CGRect frame = settingsButton.frame;
            frame.origin.x = TableViewIndent;
            frame.origin.y = OUIServerAccountSendSettingsFooterHeight - 44;
            settingsButton.frame = frame;
            
            [footerView addSubview:settingsButton];
        }
        
        
        return footerView;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if (section == ServerAccountSectionCount - 1) {
        if (!_account || _account.usageMode != OFXServerAccountUsageModeCloudSync)
            return 0;
        
        OBFinishPortingLater("<bug:///105469> (Unassigned: Make Cloud Setup accommodate the keyboard correctly [adaptability])");
        if (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone) // add space to scroll up with keyboard showing
            return OUIServerAccountSendSettingsFooterHeight + 220;
        return OUIServerAccountSendSettingsFooterHeight;
    }
    return tableView.sectionFooterHeight;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return indexPath.section == ServerAccountDeletionSection;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(indexPath.section == ServerAccountDeletionSection);
    OBPRECONDITION(indexPath.row == 0);
    
    UIAlertController *deleteConfirmation = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *deleteTitle = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Delete \"%@\"", @"OmniUIDocument", OMNI_BUNDLE, @"Server account setup confirmation action label format"), [self _accountName]];
    [deleteConfirmation addAction:[UIAlertAction actionWithTitle:deleteTitle style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [[OUIDocumentAppController controller] warnAboutDiscardingUnsyncedEditsInAccount:_account withCancelAction:NULL discardAction:^{
            [_account prepareForRemoval];
            if (self.finished)
                self.finished(self, nil);
            [self.navigationController popViewControllerAnimated:YES];
        }];
    }]];
    
    [deleteConfirmation addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"Server account setup confirmation cancellation label") style:UIAlertActionStyleCancel handler:^(UIAlertAction *unused){
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }]];
    
    UIPopoverPresentationController *presentationController = deleteConfirmation.popoverPresentationController;
    presentationController.sourceView = _tableView;
    presentationController.sourceRect = [_tableView rectForRowAtIndexPath:indexPath];
    presentationController.permittedArrowDirections = UIPopoverArrowDirectionUp|UIPopoverArrowDirectionDown;
    
    [self presentViewController:deleteConfirmation animated:YES completion:nil];
}

#pragma mark -
#pragma mark OUIEditableLabeledValueCell

- (void)editableLabeledValueCellTextDidChange:(OUIEditableLabeledValueCell *)cell;
{
    UITableViewCell *tableCell = [cell containingTableViewCell];
    NSIndexPath *indexPath = [_tableView indexPathForCell:tableCell];
    if (cell.value)
        [_cachedTextValues setObject:cell.value forKey:indexPath];
    else
        [_cachedTextValues removeObjectForKey:indexPath];
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

    NSString *accountName = TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsUsernameRow);
    BOOL hasUsername = ![NSString isEmptyString:accountName];
    if (_accountType.requiresUsername)
        requirementsMet &= hasUsername;

    BOOL locationsEqual = YES;
    if (_accountType.requiresServerURL) {
        NSURL *location = [OFXServerAccount signinURLFromWebDAVString:TEXT_AT(ServerAccountAddressSection, 0)];
        NSURL *baseURL = OFURLWithTrailingSlash([_accountType baseURLForServerURL:location username:accountName]);
        locationsEqual = [[baseURL absoluteString] isEqualToString:self.location];
        requirementsMet &= (location != nil);
    }

    NSString *password = TEXT_AT(ServerAccountCredentialsSection, ServerAccountCredentialsPasswordRow);
    if (_accountType.requiresPassword) {
        requirementsMet &= ![NSString isEmptyString:password];
    }

    NSString *nickname = TEXT_AT(ServerAccountDescriptionSection, 0);
    if (requirementsMet && [accountName isEqualToString:self.accountName] && [password isEqualToString:self.password] && locationsEqual && [nickname isEqualToString:_account.nickname]) {
            requirementsMet = NO;
    }

    signInButton.enabled = requirementsMet;
    CELL_AT(ServerAccountDescriptionSection, 0).editableValueCell.valueField.placeholder = [self _suggestedNickname];

    if ([_accountType.identifier isEqualToString:OFXOmniSyncServerAccountTypeIdentifier]) {
        // Validate Account 'button'
        [_accountInfoButton setTitle:hasUsername ? NSLocalizedStringFromTableInBundle(@"Account Info", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server account info button title") : NSLocalizedStringFromTableInBundle(@"Sign Up For a New Account", @"OmniUIDocument", OMNI_BUNDLE, @"Omni Sync Server sign up button title")
                            forState:UIControlStateNormal];
        [_accountInfoButton sizeToFit];
    }
}

- (UILabel *)_sectionLabelWithFrame:(CGRect)frame;
{
    OUIServerAccountSetupViewControllerSectionLabel *header = [[OUIServerAccountSetupViewControllerSectionLabel alloc] initWithFrame:frame];
    header.textAlignment = NSTextAlignmentLeft;
    header.font = [UIFont systemFontOfSize:14];
    header.backgroundColor = [UIColor clearColor];
    header.opaque = NO;
    header.textColor = [OAAppearanceDefaultColors appearance].omniNeutralDeemphasizedColor;
    header.numberOfLines = 0 /* no limit */;
    
    return header;
}

- (void)accountInfoButtonTapped:(id)sender;
{
    NSDictionary *emptyOptions = [NSDictionary dictionary];
    NSURL *syncSignupURL = [NSURL URLWithString:@"http://www.omnigroup.com/sync/"];
    [[UIApplication sharedApplication] openURL:syncSignupURL options:emptyOptions completionHandler:nil];
}

- (NSString *)_accountName;
{
    NSString *currentNickname = TEXT_AT(ServerAccountDescriptionSection, 0);
    if (![NSString isEmptyString:currentNickname])
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

    __autoreleasing NSError *error;
    NSData *configData = [NSPropertyListSerialization dataWithPropertyList:contents format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!configData) {
        OUI_PRESENT_ALERT_FROM(error, self);
        return;
    }
    
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

- (void)_keyboardHeightWillChange:(NSNotification *)keyboardNotification;
{
    OUIKeyboardNotifier *notifier = [OUIKeyboardNotifier sharedNotifier];
    UIEdgeInsets insets = _tableView.contentInset;
    insets.bottom = notifier.lastKnownKeyboardHeight;
    
    [UIView animateWithDuration:notifier.lastAnimationDuration delay:0 options:0 animations:^{
        [UIView setAnimationCurve:notifier.lastAnimationCurve];
        
        _tableView.contentInset = insets;
    } completion:nil];
}

@end

