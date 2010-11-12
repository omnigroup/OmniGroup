// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVSetup.h"
#import "OUIEditableLabeledValueCell.h"
#import <OmniFileStore/OFSFileManager.h>
#import "OUICredentials.h"
#import "OUIWebDAVController.h"
#import <OmniFoundation/OFPreference.h>
#import "OUIWebDAVConnection.h"
#import "OUIExportOptionsController.h"
#import "OUIExportOptionsView.h"
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIAppController.h>
#import <OmniFileStore/OFSFileInfo.h>

#import <MobileCoreServices/MobileCoreServices.h>

RCS_ID("$Id$")

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
- (void)_validateSignInButton;
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
    UIBarButtonItem *syncBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleDone target:self action:@selector(saveSettingsAndSync:)];
    self.navigationItem.rightBarButtonItem = syncBarButtonItem;
    [syncBarButtonItem release];

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
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
    
    [self _validateSignInButton];
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
            url = [NSURL URLWithString:[_nonretainedAddressField.text stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
            break;
        case OUIMobileMeSync:
        {
            NSURL *mobileMe = [NSURL URLWithString:@"https://idisk.me.com/"];
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
    sharedConnection.address = url;
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
                [[OFPreference preferenceForKey:OUIWebDAVLocation] setStringValue:_nonretainedAddressField.text];
                [[OFPreference preferenceForKey:OUIWebDAVUsername] setStringValue:_nonretainedUsernameField.text];
                break;
            case OUIMobileMeSync:
            {
                [[OFPreference preferenceForKey:OUIMobileMeUsername] setStringValue:_nonretainedUsernameField.text];
                break;
            }
                
            case OUIOmniSync:
            {
                [[OFPreference preferenceForKey:OUIOmniSyncUsername] setStringValue:_nonretainedUsernameField.text];
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
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    NSUInteger numberSections = NumberWebDavSetupSections;
    if (_syncType == OUIMobileMeSync || _syncType == OUIOmniSync)
        numberSections--;   // no server address section for mobile me or omni sync
        
    return numberSections;   
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
        if (_syncType == OUIMobileMeSync || _syncType == OUIOmniSync)
            fieldIndex++;   // address field is hidden for mobile me and omni sync
            
        switch (fieldIndex) {
            case WedDAVAddress:
                contents.label = NSLocalizedStringFromTableInBundle(@"Server Address", @"OmniUI", OMNI_BUNDLE, @"for WebDAV address edit field");
                contents.value = savedAddress;
                contents.valueField.placeholder = @"https://example.com/user";
                _nonretainedAddressField = contents.valueField;
                contents.valueField.keyboardType = UIKeyboardTypeURL;

                break;
            case WebDAVUsername:
                contents.label = NSLocalizedStringFromTableInBundle(@"User Name", @"OmniUI", OMNI_BUNDLE, @"for WebDAV username edit field");
                contents.value = savedUsername;
                contents.valueField.placeholder = @"username";
                _nonretainedUsernameField = contents.valueField;
                contents.valueField.keyboardType = UIKeyboardTypeDefault;

                break;
            case WebDAVPassword:
                contents.label = NSLocalizedStringFromTableInBundle(@"Password", @"OmniUI", OMNI_BUNDLE, @"for WebDAV password edit field");
                contents.valueField.placeholder = @"p@ssword";
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

#pragma mark -
#pragma mark Memory management

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Relinquish ownership any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload {
    // Relinquish ownership of anything that can be recreated in viewDidLoad or on demand.
    // For example: self.myOutlet = nil;
}


- (void)dealloc {
    [super dealloc];
}

@synthesize syncType = _syncType;

#pragma mark -
#pragma mark OUIEditableLabeledValueCell
- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    [self _validateSignInButton];
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
- (void)_validateSignInButton;
{
    UIBarButtonItem *signInButton = self.navigationItem.rightBarButtonItem;
    switch (_syncType) {
        case OUIWebDAVSync:
            signInButton.enabled = (![NSString isEmptyString:_nonretainedPasswordField.text] && ![NSString isEmptyString:_nonretainedAddressField.text] && ![NSString isEmptyString:_nonretainedUsernameField.text]);
            break;
        case OUIMobileMeSync:
        case OUIOmniSync:
            signInButton.enabled = (![NSString isEmptyString:_nonretainedPasswordField.text] && ![NSString isEmptyString:_nonretainedUsernameField.text]);
            break;
        default:
            break;
    }
    
}

@synthesize isExporting = _isExporting;
@end

