// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIColorSwatchPicker.h>
#import <OmniUI/OUIColorValue.h>
#import <OmniUI/OUIInspectorSelectionValue.h>
#import <OmniUI/OUIColorInspectorPane.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation OUIAbstractColorInspectorSlice

+ (NSString *)nibName;
{
    // Default to using the concrete xib for all subclasses instead of using our current class name.
    return @"OUIColorInspectorSlice";
}

- (void)dealloc;
{
    [_swatchPicker release];
    [_selectionValue release];
    [super dealloc];
}

@synthesize swatchPicker = _swatchPicker;
- (OUIColorSwatchPicker *)swatchPicker;
{
    OBPRECONDITION(_swatchPicker); // Call -view first. Could do that here, but then we'd could the view if this was called when closing/unloading the view.
    return _swatchPicker;
}

@synthesize selectionValue = _selectionValue;

- (NSSet *)getColorsFromObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (void)setColor:(OQColor *)color forObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)loadColorSwatchesForObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (IBAction)showDetails:(id)sender;
{
    _hasAddedColorSinceShowingDetail = NO;
    [super showDetails:sender];
}

- (void)updateInterfaceFromInspectedObjects;
{
    NSMutableArray *colors = [NSMutableArray array];
    NSSet *appropriateObjects = self.appropriateObjectsForInspection;
    
    // Get the appropriate color swatch
    [self loadColorSwatchesForObject:[appropriateObjects anyObject]];

    // Find a single color, obeying color spaces, that all the objects have.
    for (id object in appropriateObjects) {
        NSSet *objectColors = [self getColorsFromObject:object];
        if (objectColors)
            [colors addObjectsFromArray:[objectColors allObjects]];
    }

    OUIInspectorSelectionValue *selectionValue = [[OUIInspectorSelectionValue alloc] initWithValues:colors];

    // Compare the two colors in RGBA space, but keep the old single color's color space. This allow us to map to RGBA for text (where we store the RGBA in a CGColorRef for CoreText's benefit) but not lose the color space in our color picking UI, mapping all HSV colors with S or V of zero to black or white (and losing the H component).  See <bug://bugs/59912> (Hue slider jumps around)
    if (OFNOTEQUAL([selectionValue.dominantValue colorUsingColorSpace:OQColorSpaceRGB], [_selectionValue.uniqueValue colorUsingColorSpace:OQColorSpaceRGB])) {
        [_selectionValue release];
        _selectionValue = [selectionValue retain];
    } else
        [selectionValue release];

    // Don't check off swatches as selected unless there is only one color selected. Otherwise, we could have the main swatch list have one checkmark when there is really another selected color that just isn't in the list being shown.
    
    [_swatchPicker setSwatchSelectionColor:_selectionValue.uniqueValue];

    [super updateInterfaceFromInspectedObjects];
}

#pragma mark -
#pragma mark NSViewController

- (void)loadView;
{
    const CGFloat kWidth = 200; // will be resized anyway; just something to use as a starting point for the other views
    const CGFloat kEdgeInset = 9;
    const CGFloat kLabelToSwatchPadding = 8;
    const CGFloat kSwatchPickerBottomPadding = 9;
    
    CGFloat yOffset = 0;

    CGRect viewFrame = CGRectMake(0, 0, kWidth, 10);
    UIView *view = [[UIView alloc] initWithFrame:viewFrame];
    view.autoresizesSubviews = YES;
    
    // If a title is set on the view controller before the view is loaded, add a UILabel.
    // Not sure if it is worth allowing this to be set after the view is loaded.
    NSString *title = self.title;
    if (![NSString isEmptyString:title]) {
        CGRect labelFrame = CGRectMake(kEdgeInset, yOffset, kWidth - 2*kEdgeInset, 10);
        UILabel *label = [[UILabel alloc] initWithFrame:labelFrame];
        label.text = title;
        label.font = [OUIInspector labelFont];
        label.textColor = [OUIInspector labelTextColor];
        label.opaque = NO;
        label.backgroundColor = nil;
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
        
        [label sizeToFit]; // size the height
        labelFrame.size.height = label.frame.size.height;
        label.frame = labelFrame;
        
        [view addSubview:label];
        [label release];
        
        yOffset = CGRectGetMaxY(labelFrame) + kLabelToSwatchPadding;
    }
    
    OBASSERT(_swatchPicker == nil);
    _swatchPicker = [[OUIColorSwatchPicker alloc] initWithFrame:CGRectMake(kEdgeInset, yOffset, kWidth - 2*kEdgeInset, 0)];
    [_swatchPicker sizeHeightToFit];
    _swatchPicker.wraps = NO;
    _swatchPicker.showsNavigationSwatch = YES;
    _swatchPicker.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    
    [view addSubview:_swatchPicker];
    
    yOffset = CGRectGetMaxY(_swatchPicker.frame) + kSwatchPickerBottomPadding;
    viewFrame.size.height = yOffset;
    view.frame = viewFrame;
    
    self.view = view;
    [view release];
    
    if (!self.detailPane) {
        OUIColorInspectorPane *pane = [[OUIColorInspectorPane alloc] init];
        pane.title = self.title;
        self.detailPane = pane;
        [pane release];
    }
}

- (void)viewDidUnload;
{
    [_swatchPicker release];
    _swatchPicker = nil;
    [super viewDidUnload];
}

#pragma mark -
#pragma mark NSObject (OUIColorSwatch)

- (void)changeColor:(id)sender;
{
    OBPRECONDITION([sender conformsToProtocol:@protocol(OUIColorValue)]);
    id <OUIColorValue> colorValue = sender;
    
    OQColor *color = colorValue.color;
    
    //NSLog(@"setting color %@, continuous %d", [colorValue.color shortDescription], colorValue.isContinuousColorChange);
    
    BOOL isContinuousChange = colorValue.isContinuousColorChange;
    
    OUIInspector *inspector = self.inspector;
    NSSet *appropriateObjects = self.appropriateObjectsForInspection;
    
    if (isContinuousChange && !_inContinuousChange) {
        //NSLog(@"will begin");
        _inContinuousChange = YES;
        [inspector willBeginChangingInspectedObjects];
    }
    
    [inspector beginChangeGroup];
    {
        for (id object in appropriateObjects)
            [self setColor:color forObject:object];
    }
    [inspector endChangeGroup];
    
    if (!isContinuousChange) {
        //NSLog(@"will end");
        _inContinuousChange = NO;
        [inspector didEndChangingInspectedObjects];
    }
    
    // Pre-populate our selected color before querying back from the objects. This will allow us to keep the original colorspace if the colors are equivalent enough.
    [_selectionValue release];
    _selectionValue = [[OUIInspectorSelectionValue alloc] initWithValue:color];
    
    // Only need to update if we are the visible inspector (not our detail). Otherwise we'll update when the detail closes.
    if (inspector.topVisiblePane == self.containingPane)
        [self updateInterfaceFromInspectedObjects];

    // Don't add more than one swatch to our top swatch list per journey into the detail pane.
    // In particular, if you scrub through the HSV sliders, we don't want to blow away all our colors.
    if (!_swatchPicker.hasSelectedSwatch) {
        [_swatchPicker addColor:color replacingRecentlyAdded:_hasAddedColorSinceShowingDetail];
        _hasAddedColorSinceShowingDetail = YES;
    }
}

@end

@implementation OUIColorInspectorSlice

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIColorInspection)];
}

- (NSSet *)getColorsFromObject:(id)object;
{
    return [(id <OUIColorInspection>)object colorsForInspectorSlice:self];
}

- (void)setColor:(OQColor *)color forObject:(id)object;
{
    [(id <OUIColorInspection>)object setColor:color fromInspectorSlice:self];
}

- (void)loadColorSwatchesForObject:(id)object;
{
    if (!object)
        return;
    
    NSString *preferenceKey = [(id <OUIColorInspection>)object preferenceKeyForInspectorSlice:self];
    self.swatchPicker.palettePreferenceKey = preferenceKey;
}

@end

