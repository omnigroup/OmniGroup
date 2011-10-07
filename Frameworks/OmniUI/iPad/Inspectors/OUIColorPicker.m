// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorPicker.h>

#import <OmniUI/OUIColorValue.h>

RCS_ID("$Id$");

@implementation OUIColorPicker

- (void)dealloc;
{
    [_selectionValue release];
    [super dealloc];
}

@synthesize target = _nonretained_target;
- (void)setTarget:(id)target;
{
    OBPRECONDITION(!target || [target respondsToSelector:@selector(changeColor:)]); // Later we could make the action configurable too...
    
    _nonretained_target = target;
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

#pragma mark -
#pragma mark OUIColorSwatchPicker target

- (void)changeColor:(id <OUIColorValue>)colorValue;
{
    if (![[UIApplication sharedApplication] sendAction:@selector(changeColor:) to:_nonretained_target from:colorValue forEvent:nil])
        NSLog(@"Unable to find target for -changeColor: on color picker.");
}

@end
