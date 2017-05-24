// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAbstractColorInspectorSlice.h>

#import <OmniAppKit/OAColor.h>
#import <OmniUI/OUIColorInspectorPane.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSelectionValue.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>

RCS_ID("$Id$");

@implementation OUIAbstractColorInspectorSlice

- (OAColor *)colorForObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (void)setColor:(OAColor *)color forObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (IBAction)showDetails:(id)sender;
{    
    if (!self.detailPane) {
        OUIColorInspectorPane *pane = [[OUIColorInspectorPane alloc] init];
        if (self.title) {
            pane.title = self.title;
        }
        self.detailPane = pane;
    }
    
    [super showDetails:sender];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    NSMutableArray *colors = [NSMutableArray array];
    
    // Find a single color, obeying color spaces, that all the objects have.
    [self eachAppropriateObjectForInspection:^(id object){
        OAColor *objectColor = [self colorForObject:object];
        if (objectColor)
            [colors addObject:objectColor];
    }];
    
    OUIInspectorSelectionValue *selectionValue = [[OUIInspectorSelectionValue alloc] initWithValues:colors];
    
    // Compare the two colors in RGBA space, but keep the old single color's color space. This allow us to map to RGBA for text (where we store the RGBA in a CGColorRef for CoreText's benefit) but not lose the color space in our color picking UI, mapping all HSV colors with S or V of zero to black or white (and losing the H component).  See <bug://bugs/59912> (Hue slider jumps around)
    if (OFNOTEQUAL([selectionValue.firstValue colorUsingColorSpace:OAColorSpaceRGB], [_selectionValue.firstValue colorUsingColorSpace:OAColorSpaceRGB]))
        _selectionValue = selectionValue; // take reference from above
    
    // Don't check off swatches as selected unless there is only one color selected. Otherwise, we could have the main swatch list have one checkmark when there is really another selected color that just isn't in the list being shown.
    
    [super updateInterfaceFromInspectedObjects:reason];
}

#pragma mark -
#pragma mark OUIColorInspectorPaneParentSlice

@synthesize allowsNone = _allowsNone;
@synthesize defaultColor = _defaultColor;

@synthesize selectionValue = _selectionValue;

- (void)handleColorChange:(OAColor *)color;
{
    NSArray *appropriateObjects = self.appropriateObjectsForInspection;
    [self.inspector beginChangeGroup];
    {
        for (id object in appropriateObjects)
            [self setColor:color forObject:object];
    }
    [self.inspector endChangeGroup];
}

- (void)beginChangingColor
{
    [self.inspector willBeginChangingInspectedObjects];
}

- (void)changeColor:(id)sender;
{
    OBPRECONDITION([sender conformsToProtocol:@protocol(OUIColorValue)]);
    id <OUIColorValue> colorValue = sender;
    
    OAColor *color = colorValue.color;
        
    [self handleColorChange:color];
    
    // Pre-populate our selected color before querying back from the objects. This will allow us to keep the original colorspace if the colors are equivalent enough.
    // Do this before calling -updateInterfaceFromInspectedObjects: or -didEndChangingInspectedObjects (which will also update the interface) since that'll read the current selectionValue.
    _selectionValue = [[OUIInspectorSelectionValue alloc] initWithValue:color];
    
    if (self.inspector.topVisiblePane == self.containingPane) {
        // -didEndChangingInspectedObjects will update the interface for us
        // Only need to update if we are the visible inspector (not our detail). Otherwise we'll update when the detail closes.
        [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonObjectsEdited];
    }
}

- (void)endChangingColor
{
    [self.inspector didEndChangingInspectedObjects];
}

@end

