// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoButtonController.h>

#import <OmniUI/OUIUndoButton.h>
#import <OmniUI/OUIUndoButtonPopoverHelper.h>

RCS_ID("$Id$");

@implementation OUIUndoButtonController
{
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIUndoMenu" bundle:OMNI_BUNDLE];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)didReceiveMemoryWarning;
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    if (_menuPopoverController) {
        [_menuPopoverController dismissPopoverAnimated:NO];
        
        [_menuPopoverController release];
        [_menuNavigationController release];
        
        _menuPopoverController = nil;
        _menuNavigationController = nil;
    }
}

- (void)dealloc;
{
    [_menuNavigationController release];
    [_menuPopoverController release];
    [_undoButton release];
    [_redoButton release];
    [super dealloc];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    UIImage *layoutBackgroundImage = [UIImage imageNamed:@"OUIStandardPopoverButton.png"];
    layoutBackgroundImage = [layoutBackgroundImage stretchableImageWithLeftCapWidth:6 topCapHeight:0];
    
    [_undoButton setBackgroundImage:layoutBackgroundImage forState:UIControlStateNormal];
    [_redoButton setBackgroundImage:layoutBackgroundImage forState:UIControlStateNormal];
    
    [_undoButton setTitle:NSLocalizedStringFromTableInBundle(@"Undo", @"OmniUI", OMNI_BUNDLE, @"Undo button title") forState:UIControlStateNormal];
    [_redoButton setTitle:NSLocalizedStringFromTableInBundle(@"Redo", @"OmniUI", OMNI_BUNDLE, @"Redo button title") forState:UIControlStateNormal];
}

- (void)showUndoMenuFromItem:(OUIUndoBarButtonItem *)item;
{
    if ([_menuPopoverController isPopoverVisible])
        return;
    
    self.contentSizeForViewInPopover = self.view.frame.size; // Make sure we set this before creating our popover
    
    if (!_menuNavigationController) {
        _menuNavigationController = [[UINavigationController alloc] initWithRootViewController:self];
        _menuNavigationController.navigationBarHidden = YES;
    }
    if (!_menuPopoverController) {
        _menuPopoverController = [[UIPopoverController alloc] initWithContentViewController:_menuNavigationController];
        _menuPopoverController.delegate = self;
    }
    
    [self _updateButtonStates];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoPopoverWillShowNotification object:self];

    [[OUIUndoButtonPopoverHelper sharedPopoverHelper] presentPopover:_menuPopoverController fromBarButtonItem:item permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

- (BOOL)dismissUndoMenu;
{
    if (![_menuPopoverController isPopoverVisible])
        return NO;
    
    [_menuPopoverController dismissPopoverAnimated:YES];
    return YES;
}

- (BOOL)isMenuVisible;
{
    if (_menuPopoverController && [_menuPopoverController isPopoverVisible])
        return YES;
    return NO;
}

#pragma mark - Actions

- (void)doesNotRecognizeSelector:(SEL)aSelector;
{
    NSLog(@"%@", NSStringFromSelector(aSelector));
    [super doesNotRecognizeSelector:aSelector];
}

- (IBAction)undoButtonAction:(id)sender;
{
    if (_undoBarButtonItemTarget)
        [_undoBarButtonItemTarget undo:_undoButton];
    
    [self _updateButtonStates];
}

- (IBAction)redoButtonAction:(id)sender;
{
    if (_undoBarButtonItemTarget)
        [_undoBarButtonItemTarget redo:_redoButton];
    
    [self _updateButtonStates];
}

#pragma mark - Private

- (void)_updateButtonStates;
{
    if (_undoBarButtonItemTarget) {
        [_undoButton setEnabled:[_undoBarButtonItemTarget canPerformAction:@selector(undo:) withSender:_undoButton]];
        [_redoButton setEnabled:[_undoBarButtonItemTarget canPerformAction:@selector(redo:) withSender:_redoButton]];
    }
}

@end
