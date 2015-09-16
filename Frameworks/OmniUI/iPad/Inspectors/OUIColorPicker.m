// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorPicker.h>

#import <OmniUI/OUIColorValue.h>
#import <OmniUI/OUIInspectorSelectionValue.h>

RCS_ID("$Id$");

@implementation OUIColorPicker
{
    OUIInspectorSelectionValue *_selectionValue;
}

@synthesize target = _weak_target;
- (void)setTarget:(id)target;
{
    OBPRECONDITION(!target || [target respondsToSelector:@selector(changeColor:)]); // Later we could make the action configurable too...
    
    _weak_target = target;
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

- (void)scrollToSelectionValueAnimated:(BOOL)animated;
{
    // for subclasses
}

#pragma mark -
#pragma mark OUIColorSwatchPicker target

- (void)changeColor:(id <OUIColorValue>)colorValue NS_EXTENSION_UNAVAILABLE_IOS("");
{
    id target = _weak_target;
    
    if (![[UIApplication sharedApplication] sendAction:@selector(changeColor:) to:target from:colorValue forEvent:nil])
        NSLog(@"Unable to find target for -changeColor: on color picker.");
}

@end
