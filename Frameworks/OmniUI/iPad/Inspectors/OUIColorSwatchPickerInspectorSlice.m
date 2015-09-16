// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorSwatchPickerInspectorSlice.h>

#import <OmniUI/OUIColorSwatchPicker.h>
#import <OmniUI/OUIInspectorSelectionValue.h>
#import <OmniUI/OUIInspector.h>

RCS_ID("$Id$");

@implementation OUIColorSwatchPickerInspectorSlice
{
    BOOL _hasAddedColorSinceShowingDetail;
    OUIColorSwatchPicker *_swatchPicker;
}

- (OUIColorSwatchPicker *)swatchPicker;
{
    OBPRECONDITION(_swatchPicker); // Call -view first. Could do that here, but then we'd could the view if this was called when closing/unloading the view.
    return _swatchPicker;
}

- (void)loadColorSwatchesForObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark OUIColorInspectorPaneParentSlice subclass

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (IBAction)showDetails:(id)sender;
{
    _hasAddedColorSinceShowingDetail = NO;
    [super showDetails:sender];
}

- (void)changeColor:(id)sender;
{
    OBPRECONDITION([sender conformsToProtocol:@protocol(OUIColorValue)]);
    id <OUIColorValue> colorValue = sender;
    
    OAColor *color = colorValue.color;
    
    [super changeColor:sender];
    
    // Don't add more than one swatch to our top swatch list per journey into the detail pane.
    // In particular, if you scrub through the HSV sliders, we don't want to blow away all our colors.
    if (!_swatchPicker.hasSelectedSwatch) {
        [_swatchPicker addColor:color replacingRecentlyAdded:_hasAddedColorSinceShowingDetail];
        _hasAddedColorSinceShowingDetail = YES;
    }
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    NSArray *appropriateObjects = self.appropriateObjectsForInspection;
    
    // Get the appropriate color swatch
    [self loadColorSwatchesForObject:[appropriateObjects anyObject]];
    
    // Subclass is assumed to have updated the selection value before calling us.
    [_swatchPicker setSwatchSelectionColor:self.selectionValue.firstValue];
    
    [super updateInterfaceFromInspectedObjects:reason];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    const CGFloat kWidth = 200; // will be resized anyway; just something to use as a starting point for the other views
    const CGFloat kLabelToSwatchPadding = 8;
    
    CGFloat yOffset = 0;
    
    CGRect viewFrame = CGRectMake(0, 0, kWidth, 10);
    UIView *view = [[UIView alloc] initWithFrame:viewFrame];
    view.autoresizesSubviews = YES;
    
    // If a title is set on the view controller before the view is loaded, add a UILabel.
    // Not sure if it is worth allowing this to be set after the view is loaded.
    NSString *title = self.title;
    if (![NSString isEmptyString:title]) {
        CGRect labelFrame = CGRectMake(0, yOffset, kWidth, 10);
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
        
        yOffset = CGRectGetMaxY(labelFrame) + kLabelToSwatchPadding;
    }
    
    OBASSERT(_swatchPicker == nil);
    _swatchPicker = [[OUIColorSwatchPicker alloc] initWithFrame:CGRectMake(0, yOffset, kWidth, 0)];
    _swatchPicker.target = self;
    [_swatchPicker sizeHeightToFit];
    _swatchPicker.wraps = NO;
    _swatchPicker.showsNavigationSwatch = YES;
    _swatchPicker.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    
    [view addSubview:_swatchPicker];
    
    yOffset = CGRectGetMaxY(_swatchPicker.frame);
    viewFrame.size.height = yOffset;
    view.frame = viewFrame;
    
    self.view = view;
}

@end

