    //
//  OUIUndoButtonController.m
//  OmniGraffle-iPad
//
//  Created by Ryan Patrick on 5/24/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import "OUIUndoButtonController.h"
#import "OUIAppController.h"

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
    [super dealloc];
}

- (void)viewDidLoad;
{
    UIImage *layoutBackgroundImage = [UIImage imageNamed:@"OUIStandardPopoverButton.png"];
    layoutBackgroundImage = [layoutBackgroundImage stretchableImageWithLeftCapWidth:6 topCapHeight:0];
    
    [undoButton setBackgroundImage:layoutBackgroundImage forState:UIControlStateNormal];
    [redoButton setBackgroundImage:layoutBackgroundImage forState:UIControlStateNormal];
}

- (void)showUndoMenu:(id)sender;
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
    
    [_menuPopoverController presentPopoverFromRect:[sender frame] inView:[sender superview] permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

#pragma mark -
#pragma mark Actions
- (void)_sendAction:(SEL)action;
{
    // Try the first responder and then the app delegate.
    UIApplication *app = [UIApplication sharedApplication];
    if ([app sendAction:action to:nil from:self forEvent:nil])
        return;
    if ([app sendAction:action to:app.delegate from:self forEvent:nil])
        return;
    
    NSLog(@"No target found for menu action %@", NSStringFromSelector(action));
}

- (IBAction)undoButton:(id)sender;
{
    SEL action = @selector(undoButtonAction:);
    [self _sendAction:action];
    [self _updateButtonStates];
}

- (IBAction)redoButton:(id)sender;
{
    SEL action = @selector(redoButtonAction:);
    [self _sendAction:action];
    [self _updateButtonStates];

}

#pragma mark -
#pragma mark Private
- (void)_updateButtonStates;
{
    OUIAppController *controller = [OUIAppController controller];
    [undoButton setEnabled:[controller canUndo]];
    [redoButton setEnabled:[controller canRedo]];
}
@end
