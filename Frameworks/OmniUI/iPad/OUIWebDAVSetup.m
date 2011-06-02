// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVSetup.h"

#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFRegularExpression.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>

#import <MobileCoreServices/MobileCoreServices.h>

#import "OUICredentials.h"
#import "OUIEditableLabeledValueCell.h"
#import "OUIExportOptionsController.h"
#import "OUIExportOptionsView.h"
#import "OUIWebDAVConnection.h"
#import "OUIWebDAVController.h"

RCS_ID("$Id$")

@interface OUIWebDAVSetupSectionLabel : UILabel
@end

@implementation OUIWebDAVSetupSectionLabel
const CGFloat OUIWebDAVSetupSectionLabelIndent = 32;    // default grouped, table row indent
// it would be more convenient to use -textRectForBounds:limitedToNumberOfLines: but that is not getting called
- (void)drawTextInRect:(CGRect)rect;
{
    rect.origin.x += 2*OUIWebDAVSetupSectionLabelIndent;
    rect.size.width -= 3*OUIWebDAVSetupSectionLabelIndent;
    
    [super drawTextInRect:rect];
}

@end

enum {
    WedDAVAddress,
    WebDAVUsername,
    WebDAVPassword,
    NumberWebDavSetupSections
} WebDAVSetupSections;

NSString * const OUIWebDAVLocation = @"OUIWebDAVLocation";
NSString * const OUIWebDAVUsername = @"OUIWebDAVUsername";
NSString * const OUIMobileMeUsername = @"OUIMobileMeUsername";
NSString * const OUIOmniSyncUsername = @"OUIOmniSyncUsername";

@interface OUIWebDAVSetup (/* private */)
- (NSURL *)_signinURLFromWebDAVString:(NSString *)webdavString;
- (void)_validateSignInButton:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
- (UILabel *)_sectionLabelWithFrame:(CGRect)frame;
@end


@implementation OUIWebDAVSetup

#pragma mark -
#pragma mark Initialization

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIWebDAVSetup" bundle:OMNI_BUNDLE];
}


#pragma mark -
#pragma mark View lifecycle

- (void)viewDidLoad;
{
    [super viewDidLoad];

    NSString *syncButtonTitle = NSLocalizedStringFromTableInBundle(@"Sign In", @"OmniUI", OMNI_BUNDLE, @"sign in button title");
    UIBarButtonItem *syncBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleDone target:self action:@selector(saveSettingsAndSync:)];
    self.navigationItem.rightBarButtonItem = syncBarButtonItem;
    [syncBarButtonItem release];

    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;
    [cancel release];
    
    switch (_syncType) {
        case OUIiTunesSync:
            self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"iTunes", @"OmniUI", OMNI_BUNDLE, @"iTunes");
            break;
        case OUIMobileMeSync:
            self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"MobileMe", @"OmniUI", OMNI_BUNDLE, @"MobileMe");
            break;
        case OUIOmniSync:
            self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Omni Sync", @"OmniUI", OMNI_BUNDLE, @"Omni Sync");
            break;
        case OUIWebDAVSync:
            self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"WebDAV", @"OmniUI", OMNI_BUNDLE, @"WebDAV");
            break;
        default:
            break;
    }
    
    [self _validateSignInButton:nil shouldChangeCharactersInRange:(NSRange){0,0} replacementString:nil];
}

- (void)viewWillAppear:(BOOL)animated;
{
    switch (_syncType) {
        case OUIWebDAVSync:
            [_nonretainedAddressField becomeFirstResponder];
            break;
        case OUIMobileMeSync:
        case OUIOmniSync:
            [_nonretainedUsernameField becomeFirstResponder];
            break;
        default:
            break;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveSettingsAndSync:) name:OUICertificateTrustUpdated object:nil];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUICertificateTrustUpdated object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    // Override to allow orientations other than the default portrait orientation.
    return YES;
}

#pragma mark Actions
- (IBAction)cancel:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
    [[OUIWebDAVConnection sharedConnection] close];
}

- (void)saveSettingsAndSync:(id)sender;
{
    NSURL *url = nil;
    switch (_syncType) {
        case OUIWebDAVSync:
        {
            url = [self _signinURLFromWebDAVString:_nonretainedAddressField.text];
            break;
        }
            
        case OUIMobileMeSync:
        {
            NSURL *mobileMe = [NSURL URLWithString:@"https://idisk.me.com/"];
            NSRange range = [_nonretainedUsernameField.text rangeOfString:@"@"];
            if (range.length != 0)
                _nonretainedUsernameField.text = [_nonretainedUsernameField.text substringToIndex:range.location];
            url = OFSURLRelativeToDirectoryURL(mobileMe, [_nonretainedUsernameField.text stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
            break;
        }
            
        case OUIOmniSync:
        {
            NSURL *omniSync = [NSURL URLWithString:@"https://sync.omnigroup.com/"];
            url = OFSURLRelativeToDirectoryURL(omniSync, [_nonretainedUsernameField.text stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
            break;
        }
            
        default:
            break;
    }
    
    OUIWebDAVConnection *sharedConnection = [OUIWebDAVConnection sharedConnection];
    sharedConnection.address = OFSURLWithTrailingSlash(url);
    sharedConnection.username = _nonretainedUsernameField.text;
    sharedConnection.newKeychainPassword = _nonretainedPasswordField.text;
    
    if ([sharedConnection validConnection]) {
        UIViewController *viewController = nil;
        if (_isExporting) {
            viewController = [[OUIExportOptionsController alloc] initWithExportType:OUIExportOptionsExport];
            [(OUIExportOptionsController *)viewController setSyncType:_syncType];
        } else {
            viewController = [[OUIWebDAVController alloc] initWithNibName:nil bundle:nil];
            [(OUIWebDAVController *)viewController setSyncType:_syncType];
            [(OUIWebDAVController *)viewController setIsExporting:_isExporting];
        }
        
        switch (_syncType) {
            case OUIWebDAVSync:
                [[OFPreference preferenceForKey:OUIWebDAVLocation] setStringValue:[sharedConnection.address absoluteString]];
                [[OFPreference preferenceForKey:OUIWebDAVUsername] setStringValue:sharedConnection.username];
                break;
            case OUIMobileMeSync:
            {
                [[OFPreference preferenceForKey:OUIMobileMeUsername] setStringValue:sharedConnection.username];
                break;
            }
                
            case OUIOmniSync:
            {
                [[OFPreference preferenceForKey:OUIOmniSyncUsername] setStringValue:sharedConnection.username];
                break;
            }
                
            default:
                break;
        }
        
        [self.navigationController dismissModalViewControllerAnimated:YES];
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        OUIAppController *appController = [OUIAppController controller];
        [appController.topViewController presentModalViewController:navigationController animated:YES];
        
        [navigationController release];
        [viewController release];
    }
}

#pragma mark -
#pragma mark Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return (_syncType == OUIWebDAVSync) ? 2 : 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    NSUInteger numberRows = 0;

    switch (_syncType) {
        case OUIWebDAVSync:
            if (section == 0)
                numberRows = 1;
            else
                numberRows = 2;
            break;
        case OUIMobileMeSync:
        case OUIOmniSync:
        default:
            numberRows = 2;   // no server address section for mobile me or omni sync
    }
    
    return numberRows;   
}


// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        OUIEditableLabeledValueCell *contents = [[OUIEditableLabeledValueCell alloc] initWithFrame:cell.contentView.bounds];
        contents.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        contents.valueField.autocorrectionType = UITextAutocorrectionTypeNo;
        contents.valueField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        contents.delegate = self;
        
        NSString *savedAddress = nil;
        NSString *savedUsername = nil;
        switch (_syncType) {
            case OUIMobileMeSync:
                savedUsername = [[OFPreference preferenceForKey:OUIMobileMeUsername] stringValue];
                break;
            case OUIOmniSync:
                savedUsername = [[OFPreference preferenceForKey:OUIOmniSyncUsername] stringValue];
                break;
            case OUIWebDAVSync:
                savedAddress = [[OFPreference preferenceForKey:OUIWebDAVLocation] stringValue];
                savedUsername = [[OFPreference preferenceForKey:OUIWebDAVUsername] stringValue];
                break;
            default:
                break;
            
        }
        
        NSUInteger fieldIndex = indexPath.row;
        if (_syncType == OUIWebDAVSync)
            fieldIndex += indexPath.section;
        else
            fieldIndex++;   // address field is hidden for mobile me and omni sync
            
        switch (fieldIndex) {
            case WedDAVAddress:
                contents.label = NSLocalizedStringFromTableInBundle(@"Address", @"OmniUI", OMNI_BUNDLE, @"for WebDAV address edit field");
                contents.value = savedAddress;
                contents.valueField.placeholder = @"https://example.com/user/";
                _nonretainedAddressField = contents.valueField;
                contents.valueField.keyboardType = UIKeyboardTypeURL;

                break;
            case WebDAVUsername:
                contents.label = NSLocalizedStringFromTableInBundle(@"User Name", @"OmniUI", OMNI_BUNDLE, @"for WebDAV username edit field");
                contents.value = savedUsername;
                contents.valueField.placeholder = NSLocalizedStringFromTableInBundle(@"username", @"OmniUI", OMNI_BUNDLE, @"default for WebDAV username edit field");
                _nonretainedUsernameField = contents.valueField;
                contents.valueField.keyboardType = UIKeyboardTypeDefault;

                break;
            case WebDAVPassword:
                contents.label = NSLocalizedStringFromTableInBundle(@"Password", @"OmniUI", OMNI_BUNDLE, @"for WebDAV password edit field");
                contents.valueField.placeholder = NSLocalizedStringFromTableInBundle(@"p@ssword", @"OmniUI", OMNI_BUNDLE, @"default for WebDAV password edit field");
                contents.valueField.secureTextEntry = YES;
                _nonretainedPasswordField = contents.valueField;
                contents.valueField.keyboardType = UIKeyboardTypeDefault;

                break;
            default:
                break;
        }
        
        contents.valueField.returnKeyType = UIReturnKeyGo;
        contents.valueField.enablesReturnKeyAutomatically = YES;
	
        [cell.contentView addSubview:contents];
        [contents release];
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section;
{
    if (section == 0 && _syncType == OUIWebDAVSync) {
        return NSLocalizedStringFromTableInBundle(@"Be aware that hosting providers that don't fully comply with the WebDAV standard may not work properly.", @"OmniUI", OMNI_BUNDLE, @"webdav help");
    }
    
    return nil;
}

const CGFloat OUIWebDAVSetupHeaderHeight = 40;
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;
{
    if (section == 0 && _syncType == OUIWebDAVSync) {
        UILabel *header = [self _sectionLabelWithFrame:CGRectMake(150, 0, tableView.bounds.size.width-150, OUIWebDAVSetupHeaderHeight)];
        header.text = NSLocalizedStringFromTableInBundle(@"Enter the location of your WebDAV space.", @"OmniUI", OMNI_BUNDLE, @"webdav help");
        return header;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 0 && _syncType == OUIWebDAVSync)
        return OUIWebDAVSetupHeaderHeight;
    
    return tableView.sectionHeaderHeight;
}

const CGFloat OUIWebDAVSetupFooterHeight = 50;
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section;
{
    if (section == 0 && _syncType == OUIWebDAVSync) {
        UILabel *header = [self _sectionLabelWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, OUIWebDAVSetupFooterHeight)];
        header.text = NSLocalizedStringFromTableInBundle(@"Be aware that hosting providers that don't fully comply with the WebDAV standard may not work properly.", @"OmniUI", OMNI_BUNDLE, @"webdav help");
        return header;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if (section == 0 && _syncType == OUIWebDAVSync)
        return OUIWebDAVSetupFooterHeight;
    
    return tableView.sectionFooterHeight;
}

#pragma mark -
#pragma mark Memory management

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Relinquish ownership any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUICertificateTrustUpdated object:nil];
}


- (void)dealloc {
    [super dealloc];
}

@synthesize syncType = _syncType;

#pragma mark -
#pragma mark OUIEditableLabeledValueCell
- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    [self _validateSignInButton:textField shouldChangeCharactersInRange:range replacementString:string];
    return YES;
}

- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldShouldReturn:(UITextField *)textField;
{
    UIBarButtonItem *signInButton = self.navigationItem.rightBarButtonItem;
    BOOL trySignIn = signInButton.enabled;
    if (trySignIn)
        [self saveSettingsAndSync:nil];
    
    return trySignIn;
}

#pragma mark -
#pragma mark private

- (NSURL *)_signinURLFromWebDAVString:(NSString *)webdavString;
{
    NSURL *url = [NSURL URLWithString:webdavString];

    if (url == nil)
        url = [NSURL URLWithString:[webdavString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

    static OFRegularExpression *reasonableHostnameRegularExpression = nil;
    if (reasonableHostnameRegularExpression == nil)
        reasonableHostnameRegularExpression = [[OFRegularExpression alloc] initWithString:@"^[-_$A-Za-z0-9]+\\.[-_$A-Za-z0-9]+"];

    if ([url scheme] == nil && ![NSString isEmptyString:webdavString] && [reasonableHostnameRegularExpression hasMatchInString:webdavString])
        url = [NSURL URLWithString:[@"http://" stringByAppendingString:webdavString]];

    NSString *scheme = [url scheme];
    if (OFNOTEQUAL(scheme, @"http") && OFNOTEQUAL(scheme, @"https"))
        return nil;

    if ([NSString isEmptyString:[url host]])
        return nil;

    return url;
}

- (void)_validateSignInButton:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    UIBarButtonItem *signInButton = self.navigationItem.rightBarButtonItem;
    switch (_syncType) {
        case OUIWebDAVSync:
        {
            NSString *webdavString = _nonretainedAddressField.text;
            if (textField == _nonretainedAddressField)
                webdavString = [webdavString stringByReplacingCharactersInRange:range withString:string];
            signInButton.enabled = [self _signinURLFromWebDAVString:webdavString] != nil;
            break;
        }
        case OUIMobileMeSync:
        case OUIOmniSync:
        {
            NSString *username = _nonretainedUsernameField.text;
            NSString *password = _nonretainedPasswordField.text;
            if (textField == _nonretainedUsernameField)
                username = [username stringByReplacingCharactersInRange:range withString:string];
            else if (textField == _nonretainedPasswordField)
                password = [password stringByReplacingCharactersInRange:range withString:string];
            signInButton.enabled = (![NSString isEmptyString:password] && ![NSString isEmptyString:username]);
            break;
        }
        default:
            break;
    }
}

- (UILabel *)_sectionLabelWithFrame:(CGRect)frame;
{
    OUIWebDAVSetupSectionLabel *header = [[OUIWebDAVSetupSectionLabel alloc] initWithFrame:frame];
    header.textAlignment = UITextAlignmentLeft;
    header.font = [UIFont systemFontOfSize:14];
    header.backgroundColor = [UIColor clearColor];
    header.opaque = NO;
    header.textColor = [UIColor colorWithRed:0.196 green:0.224 blue:0.29 alpha:1];
    header.shadowColor = [UIColor colorWithWhite:1 alpha:.5];
    header.shadowOffset = CGSizeMake(0, 1);
    header.numberOfLines = 0 /* no limit */;
    
    return [header autorelease];
}

@synthesize isExporting = _isExporting;
@end

