// Copyright 2010-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorPane.h>

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspector.h>
#import <OmniBase/OmniBase.h>

#import <UIKit/UIPopoverController.h>

RCS_ID("$Id$");

// OUIInspectorPane
OBDEPRECATED_METHOD(-updateInterfaceFromInspectedObjects); // -> -updateInterfaceFromInspectedObjects:

@implementation OUIInspectorPane
{
    __weak OUIInspector *_weak_inspector; // the main inspector
    __weak OUIInspectorSlice *_weak_parentSlice; // our parent slice if any
    NSArray *_inspectedObjects;
}

- (BOOL)inInspector;
{
    return _weak_inspector != nil;
}

@synthesize inspector = _weak_inspector;
- (OUIInspector *)inspector;
{
    OBPRECONDITION(_weak_inspector);
    return _weak_inspector;
}

@synthesize parentSlice = _weak_parentSlice;

@synthesize inspectedObjects = _inspectedObjects;

- (void)inspectorWillShow:(OUIInspector *)inspector;
{
    // For subclasses
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    // For subclasses
}

- (void)doneButton:(id)sender;
{
    [self.inspector dismiss];
}

- (void)_updateForContainment;
{
    if (self.inspector.mainPane == self) {
        // For the mainPane, when modal show a done button, when in a popover show nothing
        if ([self.inspector isVisible]) {
            
            // If we just now were modal and we transitioned to a popover (i.e. 6+ portrait->landscape), the popover is going to be positioned and sized terribly. Better to dismiss it.
            if (self.navigationItem.leftBarButtonItem.action == @selector(doneButton:)) {
                [self.inspector dismissAnimated:NO];
                self.navigationItem.leftBarButtonItem = nil;
            }
        } else if (!self.navigationItem.leftBarButtonItem) {
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButton:)];
        }
    }
}

#pragma mark -
#pragma mark UIViewController

- (void)viewWillAppear:(BOOL)animated;
{
    OBPRECONDITION(_weak_inspector); // should have been set by now
    
    [super viewWillAppear:animated];
    [self _updateForContainment];
    [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[self view] endEditing:YES];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator NS_AVAILABLE_IOS(8_0);
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:NULL completion:^(id <UIViewControllerTransitionCoordinator> coordinator) {
        [self _updateForContainment];
    }];
}

@end
