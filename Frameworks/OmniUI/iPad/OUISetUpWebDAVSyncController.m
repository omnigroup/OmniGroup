// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPreference.h>
#import "OUIEditableLabeledValueCell.h"
#import "OUISetUpWebDAVSyncController.h"

RCS_ID("$Id$");

enum {
    SYNC_HEADER_SECTION,
    SYNC_SERVER_ADDRESS_SECTION,
    NUM_SECTIONS
};

#define EDITABLE_LABEL_VALUE_CELL_TAG 5000

@interface OUISetUpWebDAVSyncController ()

@property (nonatomic, retain) UIView *syncSectionHeaderView;
@property (nonatomic, retain) UIView *syncSectionFooterView;

@end

@implementation OUISetUpWebDAVSyncController

- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)nibBundle;
{
    self = [super initWithNibName:nibName bundle:nibBundle];
    if (self == nil)
        return nil;
        
    _webDAVSyncURLPreference = [[OFPreference preferenceForKey:@"LastSyncWebDAVURL"] retain];
    
    return self;
}

- (void)dealloc;
{
    [_webDAVSyncURLPreference release];
    [_syncSectionHeaderView release];
    [_syncSectionFooterView release];

    [super dealloc];
}

@synthesize syncSectionHeaderView = _syncSectionHeaderView;
@synthesize syncSectionFooterView = _syncSectionFooterView;

- (void)viewDidLoad;
{
    [super viewDidLoad];

    NSString *text = nil;
    
    text = NSLocalizedStringFromTableInBundle(@"Enter the location of your WebDAV space.", @"OmniUI", OMNI_BUNDLE, @"WebDAV sync setup text"); 
    self.syncSectionHeaderView = [[self class] informativeViewWithText:text topMargin:16 bottomMargin:0];
    
    text = NSLocalizedStringFromTableInBundle(@"Be aware that hosting providers that don’t fully comply with the WebDAV standard may not work properly.", @"OmniUI", OMNI_BUNDLE, @"WebDAV sync setup text");
    self.syncSectionFooterView = [[self class] informativeViewWithText:text];
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    self.syncSectionHeaderView = nil;
    self.syncSectionFooterView = nil;
}

- (NSSet *)textFieldsAffectingSyncButtonEnabledState
{
    NSMutableSet *textFields = [NSMutableSet set];
    [textFields unionSet:[super textFieldsAffectingSyncButtonEnabledState]];

    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:SYNC_SERVER_ADDRESS_SECTION];
    UITextField *webDAVURLField = [self textFieldForEditableLabeledValueCellWithTag:EDITABLE_LABEL_VALUE_CELL_TAG inRowAtIndexPath:indexPath];
    if (webDAVURLField)
        [textFields addObject:webDAVURLField];
    
    return textFields;
}

#pragma mark -
#pragma mark Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return NUM_SECTIONS;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section;
{
    if (section == SYNC_SERVER_ADDRESS_SECTION)
        return self.syncSectionHeaderView.frame.size.height;

    return 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;
{
    if (section == SYNC_SERVER_ADDRESS_SECTION)
        return self.syncSectionHeaderView;
        
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
{
    if (section == SYNC_SERVER_ADDRESS_SECTION)
        return self.syncSectionFooterView.frame.size.height;

    return 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section;
{
    if (section == SYNC_SERVER_ADDRESS_SECTION)
        return self.syncSectionFooterView;

    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == SYNC_SERVER_ADDRESS_SECTION) {
        OBASSERT(indexPath.row == 0);

        UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        OUIEditableLabeledValueCell *contents = [[OUIEditableLabeledValueCell alloc] initWithFrame:cell.contentView.bounds];
        
        contents.delegate = self;
        contents.tag = EDITABLE_LABEL_VALUE_CELL_TAG;
        contents.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        contents.valueField.autocorrectionType = UITextAutocorrectionTypeNo;
        contents.valueField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        
        contents.label = NSLocalizedStringFromTableInBundle(@"address", @"OmniUI", OMNI_BUNDLE, @"for WebDAV address edit field");
        contents.value = [_webDAVSyncURLPreference stringValue];
        contents.valueField.placeholder = @"https://www.example.com/webdav";
        contents.valueField.returnKeyType = UIReturnKeyGo;
        contents.valueField.enablesReturnKeyAutomatically = YES;
        contents.valueField.keyboardType = UIKeyboardTypeURL;
	
        [cell.contentView addSubview:contents];
        [contents release];

        return cell;
    }

    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

#pragma mark -
#pragma mark IBActions

- (IBAction)saveSettingsAndSync;
{
    /*
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:SYNC_SERVER_ADDRESS_SECTION]];
    OUIEditableLabeledValueCell *contents = (id)[cell viewWithTag:EDITABLE_LABEL_VALUE_CELL_TAG];
    OBASSERT(contents != nil);

    NSString *urlString = contents.value;

    NSError *error = nil;
    if (![XMLSyncManager setSyncURIDisplayString:urlString error:&error]) {
        [AppController presentError:error];
        return;
    }

    if (![[AppController appController] syncSetupCompleted:&error]) {
        [AppController presentError:error];
        return;
    }

    [_webDAVSyncURLPreference setStringValue:[XMLSyncManager syncURIDisplayString]];

    UIViewController *modalParent = self.modalParentViewController;
    [modalParent dismissModalViewControllerAnimated:NO];
     */
}

#pragma mark -
#pragma mark EditableLabeledValueCellDelegate

- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldShouldReturn:(UITextField *)textField;
{
    if (![self canSaveSettingsAndSync])
        return NO;

    [self saveSettingsAndSync];
    return YES;
}

@end
