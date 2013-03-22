// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMenuController.h>

#import <OmniUI/OUIAppController.h>
//#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/UITableView-OUIExtensions.h>

#import <UIKit/UIPopoverController.h>
#import <UIKit/UITableView.h>

RCS_ID("$Id$");

#define kOUIMenuControllerTableWidth (320)

@interface OUIMenuController (/*Private*/) <UIPopoverControllerDelegate, UITableViewDelegate, UITableViewDataSource>
- (void)_discardMenu;
@end

@implementation OUIMenuController
{
    __weak id <OUIMenuControllerDelegate> _nonretained_delegate;
    
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
    
    NSArray *_options;
}

+ (OUIMenuOption *)menuOptionWithFirstResponderSelector:(SEL)selector title:(NSString *)title image:(UIImage *)image;
{
    void (^action)(void) = ^{
        // Try the first responder and then the app delegate.
        UIApplication *app = [UIApplication sharedApplication];
        if ([app sendAction:selector to:nil from:self forEvent:nil])
            return;
        if ([app sendAction:selector to:app.delegate from:self forEvent:nil])
            return;
        
        NSLog(@"No target found for menu action %@", NSStringFromSelector(selector));
    };
    
    return [[[OUIMenuOption alloc] initWithTitle:title image:image action:action] autorelease];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    OBRejectUnusedImplementation(self, _cmd); // Use -initWithDelegate:
}

- initWithDelegate:(id <OUIMenuControllerDelegate>)delegate;
{
    OBPRECONDITION(delegate);
    
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;

    _nonretained_delegate = delegate;
    
    return self;
}

- initWithOptions:(NSArray *)options;
{
    OBPRECONDITION([options count] > 0);
    
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    _options = [options copy];
    
    return self;
}

- (void)dealloc;
{
    [_menuNavigationController release];
    [_menuPopoverController release];
    [_options release];
    [super dealloc];
}

- (void)showMenuFromBarItem:(UIBarButtonItem *)barItem;
{
    if ([_menuPopoverController isPopoverVisible]) {
        [_menuPopoverController dismissPopoverAnimated:YES];
        return;
    }
    
    // Options chould change each time we are presented.
    if (_nonretained_delegate) {
        [_options release];
        _options = [[_nonretained_delegate menuControllerOptions:self] copy];
    } else {
        // The options should be set in this case and we should keep using the static list.
    }
    
    UITableView *tableView = (UITableView *)self.view;
    [tableView reloadData];
    OUITableViewAdjustHeightToFitContents(tableView); // -sizeToFit doesn't work after # options changes, sadly
    tableView.scrollEnabled = NO;
    
    self.contentSizeForViewInPopover = self.view.frame.size; // Make sure we set this before creating our popover

    if (!_menuNavigationController) {
        _menuNavigationController = [[UINavigationController alloc] initWithRootViewController:self];
        _menuNavigationController.navigationBarHidden = [NSString isEmptyString:self.title];
    }
    if (!_menuPopoverController) {
        _menuPopoverController = [[UIPopoverController alloc] initWithContentViewController:_menuNavigationController];
        _menuPopoverController.delegate = self;
    }
    
    [[OUIAppController controller] presentPopover:_menuPopoverController fromBarButtonItem:barItem permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, kOUIMenuControllerTableWidth, 0) style:UITableViewStylePlain];
    tableView.delegate = self;
    tableView.dataSource = self;
    
    self.view = tableView;
    [tableView release];
}

#pragma mark -
#pragma mark UITableView dataSource

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    if (section == 0) {
        OBASSERT(_options);
        return [_options count];
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // Returning a nil cell will cause UITableView to throw an exception
    if (indexPath.section != 0)
        return [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];

    if (indexPath.row >= (NSInteger)[_options count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested");
        return [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
    }
    OUIMenuOption *option = [_options objectAtIndex:indexPath.row];
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:option.title];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:option.title] autorelease];
        cell.backgroundColor = [UIColor whiteColor];
        cell.opaque = YES;
        UILabel *label = cell.textLabel;
        label.text = option.title;

        cell.imageView.image = option.image;

        [cell sizeToFit];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{    
    // Returning a nil cell will cause UITableView to throw an exception
    if (indexPath.section != 0)
        return;

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= (NSInteger)[_options count]) {
        OBASSERT_NOT_REACHED("Unknown menu item selected");
        return;
    }
    OUIMenuOption *option = [[[_options objectAtIndex:indexPath.row] retain] autorelease];

    [_menuPopoverController dismissPopoverAnimated:YES];
    [self _discardMenu]; // -popoverControllerDidDismissPopover: is only called when user action causes the popover to auto-dismiss 
    
    OUIMenuOptionAction action = option.action;
    if (action)
        action();
}

#pragma mark -
#pragma mark UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    [self _discardMenu];

    // Don't keep the popover controller alive needlessly.
    [[OUIAppController controller] forgetPossiblyVisiblePopoverIfAlreadyHidden];
}

#pragma mark -
#pragma mark Private

- (void)_discardMenu;
{
    _menuPopoverController.delegate = nil;
    [_menuPopoverController release];
    _menuPopoverController = nil;
    
    [_menuNavigationController release];
    _menuNavigationController = nil;

    [_options release];
    _options = nil;
}

@end
