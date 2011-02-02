// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorPicker.h>

RCS_ID("$Id$");

@implementation OUIColorPicker

- (void)dealloc;
{
    [_selectionValue release];
    [super dealloc];
}

- (CGFloat)height;
{
    [self view]; // set in -viewDidLoad
    return _originalHeight;
}

@synthesize selectionValue = _selectionValue;

- (OUIColorPickerFidelity)fidelityForSelectionValue:(OUIInspectorSelectionValue *)selectionValue;
{
    return OUIColorPickerFidelityZero;
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    _originalHeight = CGRectGetHeight(self.view.frame);
}

@end
