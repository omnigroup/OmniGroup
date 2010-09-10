// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIUndoButtonController.h"

//#import <OmniUI/OUIAppController.h>
#import "OUIUndoButton.h"

RCS_ID("$Id$");

@interface OUIUndoButtonController (/*private */)
- (void)_updateButtonStates;
@end
 

@implementation OUIUndoButtonController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIUndoMenu" bundle:OMNI_BUNDLE];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
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
    UIImage *layoutBackgroundImage = [UIImage imageNamed:@"OUIStandardPopoverButton.png"];
    layoutBackgroundImage = [layoutBackgroundImage stretchableImageWithLeftCapWidth:6 topCapHeight:0];
    
    [_undoButton setBackgroundImage:layoutBackgroundImage forState:UIControlStateNormal];
    [_redoButton setBackgroundImage:layoutBackgroundImage forState:UIControlStateNormal];
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
    
    [_menuPopoverController presentPopoverFromBarButtonItem:item permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

- (BOOL)dismissUndoMenu;
{
    if (![_menuPopoverController isPopoverVisible])
        return NO;
    
    [_menuPopoverController dismissPopoverAnimated:YES];
    return YES;
}

#pragma mark -
#pragma mark Actions

- (IBAction)undoButtonAction:(id)sender;
{
    if (undoBarButtonItemTarget)
        [undoBarButtonItemTarget undo:_undoButton];
    
    [self _updateButtonStates];
}

- (IBAction)redoButtonAction:(id)sender;
{
    if (undoBarButtonItemTarget)
        [undoBarButtonItemTarget redo:_redoButton];
    
    [self _updateButtonStates];
}

@synthesize undoButton = _undoButton;
@synthesize redoButton = _redoButton;
@synthesize undoBarButtonItemTarget;

#pragma mark -
#pragma mark Private

- (void)_updateButtonStates;
{
    if (undoBarButtonItemTarget) {
        [_undoButton setEnabled:[undoBarButtonItemTarget canPerformAction:@selector(undo:) withSender:_undoButton]];
        [_redoButton setEnabled:[undoBarButtonItemTarget canPerformAction:@selector(redo:) withSender:_redoButton]];
    }
}

@end
