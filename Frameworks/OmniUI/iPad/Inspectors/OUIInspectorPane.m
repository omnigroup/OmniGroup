// Copyright 2010 The Omni Group.  All rights reserved.
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

@implementation OUIInspectorPane

- (void)dealloc;
{
    [_inspectedObjects release];
    [super dealloc];
}

@synthesize inspector = _nonretained_inspector;
- (OUIInspector *)inspector;
{
    OBPRECONDITION(_nonretained_inspector);
    return _nonretained_inspector;
}

@synthesize parentSlice = _nonretained_parentSlice;

@synthesize inspectedObjects = _inspectedObjects;

- (void)updateInterfaceFromInspectedObjects;
{
    // For subclasses
}

#pragma mark -
#pragma mark UIViewController

- (void)viewWillAppear:(BOOL)animated;
{
    OBPRECONDITION(_nonretained_inspector); // should have been set by now
    
    [super viewWillAppear:animated];
    
    [self updateInterfaceFromInspectedObjects];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

@end
