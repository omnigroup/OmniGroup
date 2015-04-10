// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorInspectorPane.h>

#import <OmniUI/OUIColorInspectorPaneParentSlice.h>
#import <OmniUI/OUIColorPicker.h>
#import <OmniUI/OUIColorValue.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUINavigationController.h>
#import <OmniUI/OUISegmentedControl.h>
#import <OmniUI/OUISegmentedControlButton.h>
#import <OmniUI/UIViewController-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIColorInspectorPane

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) == nil) {
        return nil;
    }
    
    self.automaticallyAdjustsScrollViewInsets = NO;
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(self.parentViewController == nil);

    [_colorTypeSegmentedControl removeFromSuperview];
    [_colorTypeSegmentedControl removeAllSegments];
}

@synthesize colorTypeSegmentedControl = _colorTypeSegmentedControl;
@synthesize shadowDivider = _shadowDivider;

@synthesize noneColorPicker = _noneColorPicker;
@synthesize paletteColorPicker = _paletteColorPicker;
@synthesize hsvColorPicker = _hsvColorPicker;
@synthesize rgbColorPicker = _rgbColorPicker;
@synthesize grayColorPicker = _grayColorPicker;

@synthesize disableAutoPickingPanes;

- (void)_setSelectedColorTypeIndex:(NSInteger)colorTypeIndex;
{
    if (colorTypeIndex != (NSInteger)_colorTypeIndex) {
        _colorTypeIndex = colorTypeIndex;
        
        if (self.visibility == OUIViewControllerVisibilityVisible)
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIColorTypeChangeNotification object:self];
    }
    
    [_colorTypeSegmentedControl setSelectedSegmentIndex:_colorTypeIndex];
    
    OUISegmentedControlButton *segment = [_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex];
    OUIColorPicker *colorPicker = segment.representedObject;
    if (colorPicker == _currentColorPicker)
        return;
    
    OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
    
    OUIColorPicker *previousColorPicker = _currentColorPicker;
    _currentColorPicker = colorPicker;
    if (previousColorPicker)
        [previousColorPicker willMoveToParentViewController:nil];
    
    // Set up the new view
    UIView *pickerView = nil;
    if (_currentColorPicker) {
        [self addChildViewController:_currentColorPicker];
        _currentColorPicker.selectionValue = slice.selectionValue;
                        
        // Keep only the height of the picker's view
        pickerView = _currentColorPicker.view;
        pickerView.frame = self.view.bounds;
        pickerView.alpha = 0.0;
        [self.view addSubview:pickerView];
    }

    void (^viewChangeAnimation)(void) = ^{
        if (previousColorPicker)
            previousColorPicker.view.alpha = 0.0;
        if (_currentColorPicker)
            pickerView.alpha = 1.0;
        [_shadowDivider setHidden:(_currentColorPicker != _paletteColorPicker)];
    };

    void (^viewChangeCompletionHandler)(BOOL) = ^(BOOL didComplete){
        previousColorPicker.selectionValue = nil; // Don't retain objects that we really aren't inspecting.
        if (previousColorPicker)
            [previousColorPicker.view removeFromSuperview];
        [previousColorPicker removeFromParentViewController];
        [_currentColorPicker didMoveToParentViewController:self];
    };

    UIViewAnimationOptions animationOptions = UIViewAnimationOptionLayoutSubviews | UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent;
    [UIView animateWithDuration:OUICrossFadeDuration delay:0 options:animationOptions animations:viewChangeAnimation completion:viewChangeCompletionHandler];
}

- (NSString *)selectedColorPickerIdentifier;
{
    if (_colorTypeIndex == NSNotFound)
        return nil;
    return [[[_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex] representedObject] identifier];
}

- (void)setSelectedColorPickerIdentifier:(NSString *)identifier;
{
    NSUInteger pickerIndex = NSNotFound;
    NSUInteger segmentIndex = [_colorTypeSegmentedControl segmentCount];
    while (segmentIndex--) {
        if (OFISEQUAL(identifier, [[[_colorTypeSegmentedControl segmentAtIndex:segmentIndex] representedObject] identifier])) {
            pickerIndex = segmentIndex;
            break;
        }
    }
    
    if (pickerIndex != NSNotFound) {
        _colorTypeIndex = pickerIndex;
        if ([self isViewLoaded]) {
            [self _setSelectedColorTypeIndex:_colorTypeIndex];
        }
    }
}

- (IBAction)colorTypeSegmentedControlSelectionChanged:(id)sender;
{
    OUIColorPicker *oldPicker = _currentColorPicker;
    
    [self _setSelectedColorTypeIndex:[_colorTypeSegmentedControl selectedSegmentIndex]];
    
    if (oldPicker != _currentColorPicker) {
        [oldPicker wasDeselectedInColorInspectorPane:self];
        [_currentColorPicker wasSelectedInColorInspectorPane:self];
    }
}

#pragma mark -
#pragma mark OUIInspectorPane subclass

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
    
    _currentColorPicker.selectionValue = slice.selectionValue;
}

#pragma mark -
#pragma mark UIViewController subclass

- (UIView *)navigationBarAccessoryView;
{
    (void)[self view]; // load view if we haven't yet
    return _colorTypeSegmentedControl;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    // Let callers assign their own title
    if ([NSString isEmptyString:self.title])
        self.title = NSLocalizedStringFromTableInBundle(@"Color", @"OUIInspectors", OMNI_BUNDLE, @"color inspector title");
    
    OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
    OBASSERT(slice);
    if (slice.allowsNone)
        [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorNoneSegment.png" representedObject:_noneColorPicker];

    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorPaletteSegment.png" representedObject:_paletteColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorHSVSegment.png" representedObject:_hsvColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorRGBSegment.png" representedObject:_rgbColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorGraySegment.png" representedObject:_grayColorPicker];
    
    _colorTypeSegmentedControl.selectedSegment = [_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex];
    [self _setSelectedColorTypeIndex:_colorTypeIndex];
    
    // Needed to chain -changeColor: up to us from the color pickers.
    NSUInteger segmentIndex = [_colorTypeSegmentedControl segmentCount];
    while (segmentIndex--) {
        OUIColorPicker *picker = [_colorTypeSegmentedControl segmentAtIndex:segmentIndex].representedObject;
        picker.target = self;
    }
}

#define BOTTOM_SPACING_BELOW_ACCESSORY 7.0

- (void)viewDidLayoutSubviews;
{
    UIView *pickerView = _currentColorPicker.view;
    if ([pickerView isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollview = OB_CHECKED_CAST(UIScrollView, pickerView);
        CGFloat topOffset = self.topLayoutGuide.length + CGRectGetHeight(_colorTypeSegmentedControl.frame) + BOTTOM_SPACING_BELOW_ACCESSORY + 8.0f;
        scrollview.contentInset = UIEdgeInsetsMake(topOffset, 0.0f, 0.0f, 0.0f);
        scrollview.contentOffset = (CGPoint){0.0f, -topOffset};

        // After updating our inset, we want to give our picker the opportunity to scroll back to its selected value
        [_currentColorPicker scrollToSelectionValueAnimated:NO];
    }
}

- (void)viewWillAppear:(BOOL)animated;
{
    if (!disableAutoPickingPanes) {
        // Default to the higest fidelity color picker, prefering earlier pickers. So, if the palette picker has an exact match, it will get used.
        OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
        OUIInspectorSelectionValue *selectionValue = slice.selectionValue;
        
        OUIColorPickerFidelity bestFidelity = OUIColorPickerFidelityZero;
        NSUInteger bestPickerIndex = NSNotFound;
        NSUInteger pickerCount = [_colorTypeSegmentedControl segmentCount];
        for (NSUInteger pickerIndex = 0; pickerIndex < pickerCount; pickerIndex++) {
            OUIColorPicker *picker = [[_colorTypeSegmentedControl segmentAtIndex:pickerIndex] representedObject];
            OUIColorPickerFidelity fidelity = [picker fidelityForSelectionValue:selectionValue];
            
            if (bestPickerIndex == NSNotFound || fidelity > bestFidelity) {
                bestPickerIndex = pickerIndex;
                bestFidelity = fidelity;
            }
        }
        
        [self _setSelectedColorTypeIndex:bestPickerIndex];
    }

    // Do this after possibly swapping child view controllers. This allows us to remove the old before it gets send -viewWillAppear:, which would hit an assertion (rightly).
    [super viewWillAppear:animated];
}

#pragma mark -
#pragma mark NSObject (OUIColorSwatch)

- (void)changeColor:(id <OUIColorValue>)colorValue;
{
    // The responder chain doesn't leap back up the nav controller stack.
    [self.parentSlice changeColor:colorValue];
}

@end
