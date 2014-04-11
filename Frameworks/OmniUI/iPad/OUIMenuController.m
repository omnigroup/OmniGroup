// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMenuController.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIMenuOption.h>

#import <UIKit/UIPopoverController.h>

#import "OUIMenuOptionsController.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

@interface OUIMenuController (/*Private*/) <UINavigationControllerDelegate, UIPopoverControllerDelegate>
@end

@implementation OUIMenuController
{
    __weak id <OUIMenuControllerDelegate> _nonretained_delegate;
    
    id _retainCycleWhileShown;
    
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
    
    NSArray *_topOptions;
    CGSize _topMenuPreferredContentSize;
}

+ (void)showPromptFromSender:(id)sender title:(NSString *)title destructive:(BOOL)destructive action:(OUIMenuOptionAction)action;
{
    // 14797381: UIActivityIndicator has incorrect padding at the bottom
    OUIMenuOption *option = [[OUIMenuOption alloc] initWithTitle:title image:nil options:nil destructive:YES action:action];
    
    OUIMenuController *menu = [[OUIMenuController alloc] initWithOptions:@[option]];
    menu.sizesToOptionWidth = YES;
    menu.textAlignment = NSTextAlignmentCenter;
    [menu showMenuFromSender:sender];
}

+ (void)showPromptFromSender:(id)sender title:(NSString *)title tintColor:(UIColor *)tintColor action:(OUIMenuOptionAction)action;
{
    // 14797381: UIActivityIndicator has incorrect padding at the bottom
    OUIMenuOption *option = [[OUIMenuOption alloc] initWithTitle:title image:nil action:action];
    
    OUIMenuController *menu = [[OUIMenuController alloc] initWithOptions:@[option]];
    menu.sizesToOptionWidth = YES;
    menu.textAlignment = NSTextAlignmentCenter;
    menu.tintColor = tintColor;
    [menu showMenuFromSender:sender];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    OBRejectUnusedImplementation(self, _cmd); // Use -initWithDelegate:
}

- initWithDelegate:(id <OUIMenuControllerDelegate>)delegate;
{
    OBPRECONDITION(delegate);
    
    if (!(self = [super init]))
        return nil;

    _showsDividersBetweenOptions = YES;
    _nonretained_delegate = delegate;
    
    return self;
}

- initWithOptions:(NSArray *)options;
{
    OBPRECONDITION([options count] > 0);
    
    if (!(self = [super init]))
        return nil;
    
    _showsDividersBetweenOptions = YES;
    _topOptions = [options copy];
    
    return self;
}

- (void)dealloc;
{
    _menuPopoverController.delegate = nil;
    _menuNavigationController.delegate = nil;
}

- (void)setTintColor:(UIColor *)tintColor;
{
    if (OFISEQUAL(_tintColor, tintColor))
        return;
    
    _tintColor = tintColor;
}

- (OUIMenuOptionsController *)_makeTopMenu;
{
    // Options chould change each time we are presented.
    if (_nonretained_delegate) {
        _topOptions = [[_nonretained_delegate menuControllerOptions:self] copy];
    } else {
        // The options should be set in this case and we should keep using the static list.
    }
    
    OUIMenuOptionsController *topMenu = [[OUIMenuOptionsController alloc] initWithController:self options:_topOptions];
    topMenu.tintColor = _tintColor;
    topMenu.sizesToOptionWidth = _sizesToOptionWidth;
    topMenu.textAlignment = _textAlignment;
    topMenu.showsDividersBetweenOptions = _showsDividersBetweenOptions;
    topMenu.padTopAndBottom = _padTopAndBottom;
    topMenu.title = _title;
    
    [topMenu view]; // So we can ask it its preferred content size
    _topMenuPreferredContentSize = topMenu.preferredContentSize;
    
    return topMenu;
}

- (void)showMenuFromSender:(id)sender;
{
    OBPRECONDITION([sender isKindOfClass:[UIBarButtonItem class]] || [sender isKindOfClass:[UIView class]]);
    
    // Keep ourselves alive while the popover is on screen (so that delegate calls work).
    _retainCycleWhileShown = self;
    
    if (!_menuNavigationController) {
        OUIMenuOptionsController *topMenu = [self _makeTopMenu];
        
        _menuNavigationController = [[UINavigationController alloc] initWithRootViewController:topMenu];
        _menuNavigationController.delegate = self;
        _menuNavigationController.preferredContentSize = _topMenuPreferredContentSize;
        _menuNavigationController.view.tintColor = _tintColor; // Needed for back buttons, if nothing else.
        _menuNavigationController.navigationBarHidden = [NSString isEmptyString:_title];
    }
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        OBFinishPorting;
        // The following code is bing disabled. We are removing calls to -[OUIAppController topViewController]. In a ViewController Containment world, topViewController could be ambiguous. We need to find a better way to handle this.
#if 0
        _menuNavigationController.navigationBarHidden = NO;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelButton:)];
        [[[OUIAppController controller] topViewController] presentViewController:_menuNavigationController animated:YES completion:NULL];
#endif
    } else {
        if (!_menuPopoverController) {
            _menuPopoverController = [[UIPopoverController alloc] initWithContentViewController:_menuNavigationController];
            _menuPopoverController.delegate = self;
            _menuPopoverController.backgroundColor = [UIColor colorWithWhite:1.0f alpha:kOUIMenuControllerBackgroundOpacity];
        }
        
        // Popover animations between different sizes are ... not good. This assumes the top level menu is a decent size, and just makes the child menu scrollable if needed.
        _menuPopoverController.popoverContentSize = _menuNavigationController.preferredContentSize;

        if ([sender isKindOfClass:[UIView class]]) {
            [[OUIAppController controller] presentPopover:_menuPopoverController fromRect:[sender frame] inView:[sender superview] permittedArrowDirections:(UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown) animated:NO];
        } else {
            OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]);
            [[OUIAppController controller] presentPopover:_menuPopoverController fromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionUp animated:NO];
        }
    }
}

- (void)dismissMenuAnimated:(BOOL)animated;
{
    [_menuPopoverController dismissPopoverAnimated:animated];
}

- (BOOL)visible;
{
    return _menuPopoverController.isPopoverVisible;
}

// Called by OUIMenuOptionsController
- (void)didInvokeOption:(OUIMenuOption *)option;
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        OBFinishPorting; // We need to release ourselves on this path and clear up the menu (the iPad path makes sure the delegate method is called)
        [_menuNavigationController dismissViewControllerAnimated:YES completion:NULL];
    } else {
        if (_optionInvocationAction == OUIMenuControllerOptionInvocationActionDismiss) {
            [[OUIAppController controller] dismissPopover:_menuPopoverController animated:YES];
        } else if (_optionInvocationAction == OUIMenuControllerOptionInvocationActionReload) {
            if (_nonretained_delegate) {
                OUIMenuOptionsController *topMenu = [self _makeTopMenu];
                [_menuNavigationController setViewControllers:@[topMenu] animated:NO];
            }
        }
    }
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    // UIPopoverController will grow the popover if a pushed view controller is taller, but that animates poorly too. So, keep it the same height as the top menu always.
//    viewController.preferredContentSize = _topMenuPreferredContentSize;
    
    BOOL hideBar;
    if (viewController == navigationController.topViewController) {
        hideBar = [NSString isEmptyString:_title];
    } else {
        OBASSERT_NOT_REACHED("This method isn't being called on push right now... iOS bug -- we're doing it in the pushing code instead?");
        hideBar = NO; // back button
    }
    navigationController.navigationBarHidden = hideBar;
}

#pragma mark - UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    [self _discardMenu];

    // Don't keep the popover controller alive needlessly.
    [[OUIAppController controller] forgetPossiblyVisiblePopoverIfAlreadyHidden];
    
    [self _didFinish];
}

- (void)cancelButton:(id)sender;
{
    [_menuNavigationController dismissViewControllerAnimated:YES completion:^{
        [self _discardMenu];
        [self _didFinish];
    }];
}

#pragma mark - Private

- (void)_discardMenu;
{
    _menuPopoverController.delegate = nil;
    _menuPopoverController = nil;
    _menuNavigationController = nil;
    _topOptions = nil;
}

- (void)_didFinish;
{
    if (_didFinish) {
        typeof(_didFinish) didFinish = _didFinish;
        _didFinish = nil;
        didFinish();
    }
    
    // Matching the setup in -showMenuFromSender:
    OBRetainAutorelease(self);
    _retainCycleWhileShown = nil;
}

@end
