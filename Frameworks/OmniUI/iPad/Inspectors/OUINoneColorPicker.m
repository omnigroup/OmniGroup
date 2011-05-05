// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUINoneColorPicker.h"

#import <OmniUI/OUIInspectorSelectionValue.h>
#import <OmniUI/OUIInspectorLabel.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIColorInspectorPane.h>
#import <OmniUI/OUIColorInspectorPaneParentSlice.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation OUINoneColorPicker

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    OUIInspectorLabel *label = [[OUIInspectorLabel alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 5)];
    label.text = NSLocalizedStringFromTableInBundle(@"No color selected", @"OUIInspectors", OMNI_BUNDLE, @"Descriptive text on the no color pane of the color picker");
    
    label.textAlignment = UITextAlignmentCenter;
    label.backgroundColor = nil;
    label.opaque = NO;
    label.numberOfLines = 0;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    [label sizeToFit];
    
    self.view = label;
    [label release];
}

#pragma mark -
#pragma mark OUIComponentColorPicker subclass

- (NSString *)identifier;
{
    return @"none";
}

- (OUIColorPickerFidelity)fidelityForSelectionValue:(OUIInspectorSelectionValue *)selectionValue;
{
    if (selectionValue.firstValue == nil)
        return OUIColorPickerFidelityExact;
    return OUIColorPickerFidelityZero;
}

static void _sendColor(OUINoneColorPicker *self, OQColor *color, OUIColorInspectorPane *pane)
{
    [self->_selectedColor release];
    self->_selectedColor = [color copy];

    if (![[UIApplication sharedApplication] sendAction:@selector(changeColor:) to:pane from:self forEvent:nil])
        OBASSERT_NOT_REACHED("Showing a color picker, but not interested in the result?");
}

- (void)wasDeselectedInColorInspectorPane:(OUIColorInspectorPane *)pane;
{
    OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)pane.parentSlice;

    OQColor *color = slice.defaultColor;
    if (!color) {
        OBASSERT_NOT_REACHED("Should have returned a default color");
        color = [OQColor whiteColor];
    }
    
    _sendColor(self, color, pane);
}

- (void)wasSelectedInColorInspectorPane:(OUIColorInspectorPane *)pane;
{
    _sendColor(self, nil, pane);
}

#pragma mark -
#pragma mark OUIColorValue

- (OQColor *)color;
{
    return _selectedColor;
}

- (BOOL)isContinuousColorChange;
{
    return NO;
}

@end
