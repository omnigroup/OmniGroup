// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIAppMenuController.h"

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDocumentPicker.h>

RCS_ID("$Id$");

enum {
#ifdef SEPARATE_SAMPLE_DOCUMENTS
    ToggleSampleDocuments,
#endif
    OnlineHelp,
    SendFeedback,
    ReleaseNotes,
    NormalMenuItemCount,
    
    //
    RunTests = NormalMenuItemCount
} MenuItem;

static NSUInteger MenuItemCount = NormalMenuItemCount;

@interface OUIAppMenuController (/*Private*/)
- (void)_toggleSampleDocuments:(id)sender;
- (void)_discardMenu;
@end

@implementation OUIAppMenuController

+ (void)initialize;
{
    OBINITIALIZE;
    
    BOOL includedTestsMenu;
    
#if defined(DEBUG)
    includedTestsMenu = YES;
#else
    includedTestsMenu = [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIIncludeTestsMenu"];
#endif

    if (includedTestsMenu && NSClassFromString(@"SenTestSuite"))
        MenuItemCount++;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIAppMenu" bundle:OMNI_BUNDLE];
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
        
    self.contentSizeForViewInPopover = self.view.frame.size; // Make sure we set this before creating our popover

    if (!_menuNavigationController) {
        _menuNavigationController = [[UINavigationController alloc] initWithRootViewController:self];
        _menuNavigationController.navigationBarHidden = YES;
    }
    if (!_menuPopoverController) {
        _menuPopoverController = [[UIPopoverController alloc] initWithContentViewController:_menuNavigationController];
        _menuPopoverController.delegate = self;
    }
    
#ifdef SEPARATE_SAMPLE_DOCUMENTS
    if (_needsReloadOfDocumentsItem) {
        _needsReloadOfDocumentsItem = NO;

        UITableView *tableView = (UITableView *)self.view;
        [tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:ToggleSampleDocuments inSection:0]]
                         withRowAnimation:UITableViewRowAnimationNone];
    }
#endif

    [_menuPopoverController presentPopoverFromBarButtonItem:barItem permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

- (void)dismiss;
{
    [_menuPopoverController dismissPopoverAnimated:NO];
    [self _discardMenu]; // -popoverControllerDidDismissPopover: is only called when user action causes the popover to auto-dismiss 
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    UIView *view = self.view;
    [view sizeToFit];
}

- (void)viewDidUnload;
{
    [_menuNavigationController release];
    _menuNavigationController = nil;
    
    [_menuPopoverController release];
    _menuPopoverController = nil;
    
    [super viewDidUnload];
}

#pragma mark -
#pragma mark UITableView dataSource

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    if (section == 0)
        return MenuItemCount;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // Returning a nil cell will cause UITableView to throw an exception
    if (indexPath.section != 0)
        return [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:nil] autorelease];

    NSString *title;
    UIImage *image = nil;
    
    switch (indexPath.row) {
#ifdef SEPARATE_SAMPLE_DOCUMENTS
        case ToggleSampleDocuments: {
            OUIAppController *controller = [OUIAppController controller];
            if (OFISEQUAL(controller.documentPicker.directory, [OUIDocumentPicker userDocumentsDirectory]))
                title = NSLocalizedStringFromTableInBundle(@"Tutorial and Samples", @"OmniUI", OMNI_BUNDLE, @"App menu item title");
            else
                title = NSLocalizedStringFromTableInBundle(@"My Documents", @"OmniUI", OMNI_BUNDLE, @"App menu item title");
            break;
        }
#endif
        case OnlineHelp:
            title = [[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"] table:@"InfoPlist"];
            image = [UIImage imageNamed:@"OUIMenuItemHelp.png"];
            OBASSERT(title != nil);
            break;
        case SendFeedback:
            title = [[OUIAppController controller] feedbackMenuTitle];
            image = [UIImage imageNamed:@"OUIMenuItemSendFeedback.png"];
            break;
        case ReleaseNotes:
            title = NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"App menu item title");
            image = [UIImage imageNamed:@"OUIMenuItemReleaseNotes.png"];
            break;
        case RunTests:
            title = NSLocalizedStringFromTableInBundle(@"Run Tests", @"OmniUI", OMNI_BUNDLE, @"App menu item title");
            image = [UIImage imageNamed:@"OUIMenuItemRunTests.png"];
            break;
            
        default:
            OBASSERT_NOT_REACHED("Unknown menu item row requested");
            return [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:nil] autorelease];
    }

    OBASSERT(image);
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:title];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:title] autorelease];
        cell.backgroundColor = [UIColor whiteColor];
        cell.opaque = YES;
        UILabel *label = cell.textLabel;
        label.text = title;

        cell.imageView.image = image;

        [cell sizeToFit];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    SEL action = NULL;
    
    // Returning a nil cell will cause UITableView to throw an exception
    if (indexPath.section != 0)
        return;

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.row) {
#ifdef SEPARATE_SAMPLE_DOCUMENTS
        case ToggleSampleDocuments:
            action = @selector(_toggleSampleDocuments:);
            break;
#endif
        case OnlineHelp:
            action = @selector(showOnlineHelp:);
            break;
        case SendFeedback:
            action = @selector(sendFeedback:);
            break;
        case ReleaseNotes:
            action = @selector(showReleaseNotes:);
            break;
        case RunTests:
            action = @selector(runTests:);
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown menu item selected");
            break;
    }
    
    [_menuPopoverController dismissPopoverAnimated:YES];
    [self _discardMenu]; // -popoverControllerDidDismissPopover: is only called when user action causes the popover to auto-dismiss 
    
    if (!action)
        return;
    
    // Try the first responder and then the app delegate.
    UIApplication *app = [UIApplication sharedApplication];
    if ([app sendAction:action to:nil from:self forEvent:nil])
        return;
    if ([app sendAction:action to:app.delegate from:self forEvent:nil])
        return;

    NSLog(@"No target found for menu action %@", NSStringFromSelector(action));
}

#pragma mark -
#pragma mark UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    [self _discardMenu];
}

#pragma mark -
#pragma mark Private

- (void)_toggleSampleDocuments:(id)sender;
{
    OUIAppController *controller = [OUIAppController controller];
    OUIDocumentPicker *picker = controller.documentPicker;
    
    if (OFISEQUAL(picker.directory, [OUIDocumentPicker userDocumentsDirectory]))
        picker.directory = [OUIDocumentPicker sampleDocumentsDirectory];
    else
        picker.directory = [OUIDocumentPicker userDocumentsDirectory];
    [picker scrollToProxy:[picker.previewScrollView firstProxy] animated:NO];

    // We can't do this reload here since it would be visible while the popover is animating away
    _needsReloadOfDocumentsItem = YES;
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
