// Copyright 2010-2013 The Omni Group. All rights reserved.
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

#pragma mark -
#pragma mark UIViewController

- (void)viewWillAppear:(BOOL)animated;
{
    OBPRECONDITION(_weak_inspector); // should have been set by now
    
    [super viewWillAppear:animated];
    
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

@end
