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

@synthesize selectionValue = _selectionValue;

- (NSString *)identifier;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (OUIColorPickerFidelity)fidelityForSelectionValue:(OUIInspectorSelectionValue *)selectionValue;
{
    return OUIColorPickerFidelityZero;
}

- (void)wasDeselectedInColorInspectorPane:(OUIColorInspectorPane *)pane;
{
    // for subclasses
}

- (void)wasSelectedInColorInspectorPane:(OUIColorInspectorPane *)pane;
{
    // for subclasses
}

@end
