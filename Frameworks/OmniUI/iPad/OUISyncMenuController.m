// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISyncMenuController.h"

#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>

#import <MobileCoreServices/MobileCoreServices.h>

#import "OUIExportOptionsController.h"
#import "OUIExportOptionsView.h"
#import "OUIWebDAVConnection.h"
#import "OUIWebDAVController.h"
#import "OUIWebDAVSetup.h"

RCS_ID("$Id$")

@interface OUISyncMenuController (/*Private*/)
+ (NSURL *)_urlFromPreference:(OFPreference *)preference;
- (void)_discardMenu;
@end

@implementation OUISyncMenuController

+ (void)displayInSheet;
{
    OUISyncMenuController *controller = [[OUISyncMenuController alloc] init];
    controller.isExporting = YES;
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    [controller release];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    OUIAppController *appController = [OUIAppController controller];
    [appController.topViewController presentModalViewController:navigationController animated:YES];
    
    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:controller action:@selector(cancel:)];
    controller.navigationItem.leftBarButtonItem = cancel;
    [cancel release];
    
    controller.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUI", OMNI_BUNDLE, @"export options title");
    
    [navigationController release];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUISyncMenu" bundle:OMNI_BUNDLE];
}

- (void)dealloc;
{
    [_menuNavigationController release];
    [_menuPopoverController release];
    
    [super dealloc];
}

- (void)showMenuFromBarItem:(UIBarButtonItem *)barItem;
{
    if ([_menuPopoverController isPopoverVisible]) {
        [_menuPopoverController dismissPopoverAnimated:YES];
        return;
    }
    
    self.contentSizeForViewInPopover = CGSizeMake(320, 108); // Make sure we set this before creating our popover
    
    if (!_menuNavigationController) {
        _menuNavigationController = [[UINavigationController alloc] initWithRootViewController:self];
        _menuNavigationController.navigationBarHidden = NO;
        _menuNavigationController.topViewController.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Import Document\u2026", @"OmniUI", OMNI_BUNDLE, @"Import document title"); 
    }
    if (!_menuPopoverController) {
        _menuPopoverController = [[UIPopoverController alloc] initWithContentViewController:_menuNavigationController];
        _menuPopoverController.delegate = self;
    }
    
    [[OUIAppController controller] presentPopover:_menuPopoverController fromBarButtonItem:barItem permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
    [(UITableView *)self.view reloadData];
}

#pragma mark -
#pragma mark Sheet specific stuff
- (void)cancel:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
    [[OUIWebDAVConnection sharedConnection] close];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    [self.view sizeToFit];
}

- (void)viewDidUnload;
{
    [_menuNavigationController release];
    _menuNavigationController = nil;
    
    [_menuPopoverController release];
    _menuPopoverController = nil;
    
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    // Override to allow orientations other than the default portrait orientation.
    return YES;
}

#pragma mark -
#pragma mark UITableView dataSource

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    return _isExporting ? OUINumberSyncChoices : (OUINumberSyncChoices-1 /* no importing from iTunes */);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // Returning a nil cell will cause UITableView to throw an exception
    if (indexPath.section != 0)
        return [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
    
    NSString *title = nil;
    NSString *description = nil;
    switch (indexPath.row) {
        case OUIiTunesSync:
            title = _isExporting ? NSLocalizedStringFromTableInBundle(@"Export to iTunes", @"OmniUI", OMNI_BUNDLE, @"Export document title") : NSLocalizedStringFromTableInBundle(@"Copy from iTunes", @"OmniUI", OMNI_BUNDLE, @"Import document title");
            description = NSLocalizedStringFromTableInBundle(@"Documents", @"OmniUI", OMNI_BUNDLE, @"Export document desciption");
            break;
        case OUIMobileMeSync:
            title = _isExporting ? NSLocalizedStringFromTableInBundle(@"Export to iDisk", @"OmniUI", OMNI_BUNDLE, @"Export document title") : NSLocalizedStringFromTableInBundle(@"Copy from iDisk", @"OmniUI", OMNI_BUNDLE, @"Import document title");
            description = [[OFPreference preferenceForKey:OUIMobileMeUsername] stringValue];
            break;
        case OUIOmniSync:
            title = _isExporting ? NSLocalizedStringFromTableInBundle(@"Export to Omni Sync", @"OmniUI", OMNI_BUNDLE, @"Export document title") : NSLocalizedStringFromTableInBundle(@"Copy from Omni Sync", @"OmniUI", OMNI_BUNDLE, @"Import document title");
            description = [[OFPreference preferenceForKey:OUIOmniSyncUsername] stringValue];
            break;
        case OUIWebDAVSync:
            title = _isExporting ? NSLocalizedStringFromTableInBundle(@"Export to WebDAV", @"OmniUI", OMNI_BUNDLE, @"Export document title") : NSLocalizedStringFromTableInBundle(@"Copy from WebDAV", @"OmniUI", OMNI_BUNDLE, @"Import document title");
            description = [[[self class] _urlFromPreference:[OFPreference preferenceForKey:OUIWebDAVLocation]] absoluteString];
            break;
        default:
            break;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:title];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:title] autorelease];
        cell.backgroundColor = [UIColor whiteColor];
        cell.opaque = YES;
        
        [cell sizeToFit];
    }
    
    UILabel *label = cell.textLabel;
    label.text = title;
    UILabel *note = cell.detailTextLabel;
    if (![NSString isEmptyString:description])
        note.text = description;
    else
        note.text = NSLocalizedStringFromTableInBundle(@"Not logged in", @"OmniUI", OMNI_BUNDLE, @"Import description");
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    [_menuPopoverController dismissPopoverAnimated:YES];
    [self _discardMenu]; // -popoverControllerDidDismissPopover: is only called when user action causes the popover to auto-dismiss 
    
    // looking for a previous connection
    NSURL *previousConnectionLocation = nil;
    NSString *previousConnectionUsername = nil;
    switch (indexPath.row) {
        case OUIMobileMeSync:
            previousConnectionUsername = [[OFPreference preferenceForKey:OUIMobileMeUsername] stringValue];
            NSURL *mobileMe = [NSURL URLWithString:@"https://idisk.me.com/"];
            previousConnectionLocation = OFSURLRelativeToDirectoryURL(mobileMe, [previousConnectionUsername stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
            break;
        case OUIOmniSync:
            previousConnectionUsername = [[OFPreference preferenceForKey:OUIOmniSyncUsername] stringValue];
            previousConnectionLocation = [NSURL URLWithString:[@"https://sync.omnigroup.com/" stringByAppendingPathComponent:previousConnectionUsername]];
            break;
        case OUIWebDAVSync:
            previousConnectionLocation = [[self class] _urlFromPreference:[OFPreference preferenceForKey:OUIWebDAVLocation]];
            previousConnectionUsername = [[OFPreference preferenceForKey:OUIWebDAVUsername] stringValue];
            break;
        case OUIiTunesSync:
        {
            // iTunes only allows interaction with the top Documents directory 
            NSString *inboxPath = [[OUIDocumentPicker userDocumentsDirectory] stringByExpandingTildeInPath];
            previousConnectionLocation = [NSURL fileURLWithPath:inboxPath];
            previousConnectionUsername = @"local";   // OUIWebDAVConnection likes having a username so that it knows that it is setup correctly
            break;
        }
            
        default:
            break;
    }
    
    UIViewController *viewController = nil;
    
    OUIWebDAVConnection *connection = [OUIWebDAVConnection sharedConnection];
    connection.address = OFSURLWithTrailingSlash(previousConnectionLocation);
    connection.username = previousConnectionUsername;
    
    if ((previousConnectionLocation && ![NSString isEmptyString:previousConnectionUsername]) || (indexPath.row == OUIiTunesSync)) {
        if (_isExporting) {
            viewController = [[OUIExportOptionsController alloc] initWithExportType:OUIExportOptionsExport];
            [(OUIExportOptionsController *)viewController setSyncType:indexPath.row];
            [self.navigationController pushViewController:viewController animated:YES];
            [viewController release];
            return;
        } else {
            viewController = [[OUIWebDAVController alloc] init];
            [(OUIWebDAVController *)viewController setSyncType:indexPath.row];
            [(OUIWebDAVController *)viewController setIsExporting:_isExporting];
        }
    } else {
        viewController = [[OUIWebDAVSetup alloc] init];
        [(OUIWebDAVSetup *)viewController setSyncType:indexPath.row];
        [(OUIWebDAVSetup *)viewController setIsExporting:_isExporting];
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

#pragma mark -
#pragma mark UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    [self _discardMenu];
}

@synthesize isExporting = _isExporting;

#pragma mark -
#pragma mark Private

+ (NSURL *)_urlFromPreference:(OFPreference *)preference;
{
    NSString *locationString = [preference stringValue];
    if ([NSString isEmptyString:locationString])
        return nil;

    NSURL *url = [NSURL URLWithString:locationString];
    if (url != nil)
        return url;

    return [NSURL URLWithString:[locationString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}

- (void)_discardMenu;
{
    _menuPopoverController.delegate = nil;
    [_menuPopoverController release];
    _menuPopoverController = nil;
    
    [_menuNavigationController release];
    _menuNavigationController = nil;
}

@end
