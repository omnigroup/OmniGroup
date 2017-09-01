// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspectorSliceView.h>

#import <OmniUI/OUIEmptyPaddingInspectorSlice.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorAppearance.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorSliceView.h>
#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniUI/OUIMinimalScrollNotifierImplementation.h>
#import <OmniUI/UIViewController-OUIExtensions.h>
#import <OmniUI/OUIAbstractTableViewInspectorSlice.h>

#import "OUIParameters.h"

#import "OUIInspectorBackgroundView.h"
#import "OUIInspectorSlice-Internal.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG_curt) && defined(DEBUG)
    #define DEBUG_ANIM(format, ...) NSLog(@"ANIM: " format, ## __VA_ARGS__)
#else
    #define DEBUG_ANIM(format, ...)
#endif

NSString *OUIStackedSlicesInspectorContentViewDidChangeFrameNotification = @"OUIStackedSlicesInspectorContentViewDidChangeFrame";

@interface OUIStackedSlicesInspectorPaneContentView : UIScrollView
@property (nonatomic, strong) OUIInspectorBackgroundView *backgroundView;
@end

@implementation OUIStackedSlicesInspectorPaneContentView

static id _commonInit(OUIStackedSlicesInspectorPaneContentView *self)
{
    self->_backgroundView = [[OUIInspectorBackgroundView alloc] initWithFrame:self.bounds];
    [self addSubview:self->_backgroundView];
    self.alwaysBounceVertical = YES;
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (UIColor *)inspectorBackgroundViewColor;
{
    return [_backgroundView inspectorBackgroundViewColor];
}

- (void)setInspectorBackgroundViewColor:(UIColor *)color;
{
    _backgroundView.backgroundColor = color;
}

- (void)layoutSubviews;
{
    [super layoutSubviews]; // Scroller

    // Have to do this after the previous adjustments or the background view can get stuck scrolled part way down when we become unscrollable.
    _backgroundView.frame = self.bounds;
}

@end

@interface OUIStackedSlicesInspectorPane ()

@property(nonatomic,copy) NSArray *slices;
@property(nonatomic, readonly) BOOL needsSliceLayout;
@property(nonatomic) BOOL maintainHeirarchyOnNextSliceLayout;
@property(nonatomic, strong) NSSet *oldSlicesForMaintainingHierarchy;
@property(nonatomic) UIStackView *sliceStackView;

@end

@implementation OUIStackedSlicesInspectorPane
{
    NSArray *_slices;
    id <OUIScrollNotifier> _scrollNotifier;
    BOOL _initialLayoutHasBeenDone;
}

+ (instancetype)stackedSlicesPaneWithAvailableSlices:(OUIInspectorSlice *)slice, ...;
{
    OBPRECONDITION(slice);
    
    NSMutableArray *slices = [[NSMutableArray alloc] initWithObjects:slice, nil];
    if (slice) {
        OUIInspectorSlice *nextSlice;
        
        va_list argList;
        va_start(argList, slice);
        while ((nextSlice = va_arg(argList, OUIInspectorSlice *)) != nil) {
            OBASSERT([nextSlice isKindOfClass:[OUIInspectorSlice class]]);
            [slices addObject:nextSlice];
        }
        va_end(argList);
    }

    OUIStackedSlicesInspectorPane *result = [[self alloc] init];
    
    NSArray *availableSlices = [slices copy];
    result.availableSlices = availableSlices;

    
    return result;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIColor *)inspectorBackgroundViewColor;
{
    return self.view.backgroundColor;
}

- (void)setInspectorBackgroundViewColor:(UIColor *)color;
{
    self.view.backgroundColor = color;
    [self.view setNeedsDisplay];
}

- (void)setSliceAlignmentInsets:(UIEdgeInsets)newValue;
{
    if (UIEdgeInsetsEqualToEdgeInsets(_sliceAlignmentInsets, newValue)) {
        return;
    }
    
    _sliceAlignmentInsets = newValue;
    
    for (OUIInspectorSlice *slice in self.slices) {
        slice.alignmentInsets = _sliceAlignmentInsets;
    }
}

- (void)setSliceSeparatorColor:(UIColor *)newValue;
{
    if (OFISEQUAL(_sliceSeparatorColor,newValue)) {
        return;
    }
    
    _sliceSeparatorColor = newValue;
    
    for (OUIInspectorSlice *slice in self.slices) {
        slice.separatorColor = _sliceSeparatorColor;
    }
}

- (NSArray *)makeAvailableSlices;
{
    return nil; // For subclasses
}

- (void)setAvailableSlices:(NSArray *)availableSlices;
{
    if (OFISEQUAL(_availableSlices, availableSlices))
        return;
    
    _availableSlices = [availableSlices copy];
    
    if (self.visibility != OUIViewControllerVisibilityHidden) {
        // If we are currently on screen, a subclass might be changing the available slices somehow (like the tabbed document contents inspector in OO/iPad).
        // This will both update the filtered slices and their interface for the current inspection set.
        [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
    }
}

- (NSArray *)appropriateSlices:(NSArray *)availableSlices forInspectedObjects:(NSArray *)inspectedObjects;
{
    NSMutableArray *appropriateSlices = [NSMutableArray array];
    OUIInspectorSlice *previousSlice = nil;
    for (OUIInspectorSlice *slice in _availableSlices) {
        // Don't put a spacer at the beginning, or two spacers back-to-back
        if ([slice isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]) {
            if (previousSlice.includesInspectorSliceGroupSpacerOnBottom) {
                continue;
            }
        }
        
        if (![slice isAppropriateForInspectorPane:self]) {
            continue;
        }
        
        // This is a hack to make sure the slice checks with THIS pane for its appropriateness. Please see commit message for more details.
        OUIStackedSlicesInspectorPane *oldContainingPane = slice.containingPane;
        slice.containingPane = self;
        if ([slice isAppropriateForInspectedObjects:inspectedObjects]) {
            // If this slice includes a top group spacer and the previous slice was a spacer, remove that previous slice as it's not needed
            if (slice.includesInspectorSliceGroupSpacerOnTop && (previousSlice != nil) && [previousSlice isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]) {
                OBASSERT([[appropriateSlices lastObject] isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]);
                [appropriateSlices removeLastObject];
            }
            
            [appropriateSlices addObject:slice];
            previousSlice = slice;
        }
        slice.containingPane = oldContainingPane;
    }
    // Don't have a spacer at the end, either
    if ([appropriateSlices.lastObject isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]) {
        [appropriateSlices removeLastObject];
    }
    
    return appropriateSlices;
}

- (NSArray *)appropriateSlicesForInspectedObjects;
{
    // Only fill the _availableSlices once. This allows the delegate/subclass to return an autoreleased array that isn't stored in a static (meaning that they can go away on a low memory warning). If we fill this multiple times, then we'll get confused and replace the slices constantly (since we do pointer equality in -setSlices:.
    if (!_availableSlices) {
        _availableSlices = [[self.inspector makeAvailableSlicesForStackedSlicesPane:self] copy];
    }
    
    // TODO: Add support for this style of use in the superclass? There already is in the delegate-based path.
    if (!_availableSlices) {
        _availableSlices = [[self makeAvailableSlices] copy];
        OBASSERT([_availableSlices count] > 0); // Didn't get slices from the delegate or a subclass!
    }
    
    // can be empty if the inspector is being closed
    NSArray *inspectedObjects = self.inspectedObjects;
    
    return [self appropriateSlices:_availableSlices forInspectedObjects:inspectedObjects];
}

static void _removeSlice(OUIStackedSlicesInspectorPane *self, OUIStackedSlicesInspectorPaneContentView *view, OUIInspectorSlice *slice)
{
    [slice willMoveToParentViewController:nil];
    if ([slice isViewLoaded] && slice.view.superview == view) {
        [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
    }
    [slice removeFromParentViewController];
}

+ (OUIInspectorSliceGroupPosition)_sliceGroupPositionForSlice:(OUIInspectorSlice *)slice precededBySlice:(OUIInspectorSlice *)precedingSlice followedBySlice:(OUIInspectorSlice *)followingSlice;
{
    BOOL isBeginningOfGroup = ((precedingSlice == nil) || precedingSlice.includesInspectorSliceGroupSpacerOnTop);
    BOOL isEndOfGroup = ((followingSlice == nil) || followingSlice.includesInspectorSliceGroupSpacerOnBottom);
    if (isBeginningOfGroup) {
        if (isEndOfGroup) {
            return OUIInspectorSliceGroupPositionAlone;
        } else {
            return OUIInspectorSliceGroupPositionFirst;
        }
    } else if (isEndOfGroup) {
        return OUIInspectorSliceGroupPositionLast;
    } else {
        return OUIInspectorSliceGroupPositionCenter;
    }
}

@synthesize slices = _slices;

- (void)setNeedsSliceLayout
{
    _needsSliceLayout = YES;
    if (_initialLayoutHasBeenDone) {
        [self.view setNeedsLayout];
        [self.contentView setNeedsLayout];
    }
}

- (void)setSlices:(NSArray *)slices maintainViewHierarchy:(BOOL)maintainHierarchy;
{
    if ([slices isEqualToArray:self.slices]) {
        return;  // otherwise, we get fooled into never adding the slices to the view
    }
    if (!self.oldSlicesForMaintainingHierarchy) {  // this will get cleared out when the change is actually commited to the view hierarchy.  if it hasn't been cleared yet, the current _slices aren't really our current slices so we don't want to remember them as our old slices.
        self.oldSlicesForMaintainingHierarchy = [NSSet setWithArray:self.slices];
    }
    for (OUIInspectorSlice *slice in self.slices) {
        [slice willMoveToParentViewController:nil];
        [self.sliceStackView removeArrangedSubview:slice.view];
        [slice.view removeFromSuperview];
        [slice removeFromParentViewController];
    }
    // view controllers need to be told they're being added & removed from each other.
    _slices = slices;
    
    self.maintainHeirarchyOnNextSliceLayout = maintainHierarchy;
    for (OUIInspectorSlice *slice in slices) {
        slice.containingPane = self;
        slice.view.backgroundColor = [slice sliceBackgroundColor];
        
        if ([OUIInspectorAppearance inspectorAppearanceEnabled])
            [slice notifyChildrenThatAppearanceDidChange:OUIInspectorAppearance.appearance];
        
        [self addChildViewController:slice];
        [self.sliceStackView addArrangedSubview:slice.view];
        
        if (![slice isKindOfClass:[OUIAbstractTableViewInspectorSlice class]]) {
            UIEdgeInsets sliceEdgeInsets = [OUIInspectorSlice sliceAlignmentInsets];
            slice.contentView.layoutMargins = sliceEdgeInsets;
        }
    }
    for (NSUInteger index = 0; index < slices.count; index++) {
        OUIInspectorSlice *previous = index > 0 ? slices[index-1] : nil;
        OUIInspectorSlice *next = index < (slices.count-1) ? slices[index+1] : nil;
        OUIInspectorSlice *current = slices[index];
        
        current.groupPosition = [OUIStackedSlicesInspectorPane _sliceGroupPositionForSlice:current precededBySlice:previous followedBySlice:next];
    }
    [self setNeedsSliceLayout];
}

- (void)setSlices:(NSArray *)slices;
{
    [self setSlices:slices maintainViewHierarchy:YES];
}

- (void)sliceSizeChanged:(OUIInspectorSlice *)slice;
{
    // TODO: It seems like we should be able to animate the resizing to avoid jumpy transitions.
    if (_initialLayoutHasBeenDone) {
        [self.contentView setNeedsLayout];
    }
}

- (void)updateSlices;
{
    self.slices = [self appropriateSlicesForInspectedObjects];
    
    OUIStackedSlicesInspectorPaneContentView *paneContentView = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
    if (self.slices.count == 0) {
        paneContentView.backgroundView.label.text = NSLocalizedStringFromTableInBundle(@"Nothing to Inspect", @"OmniUI", OMNI_BUNDLE, @"Text letting the user know why nothing is showing in the inspector");
        paneContentView.backgroundView.label.font = [paneContentView.backgroundView.label.font fontWithSize:InspectorFontSize];
    }
    else {
        paneContentView.backgroundView.label.text = nil;
    }
}

- (BOOL)inspectorPaneOfClassHasAlreadyBeenPresented:(Class)paneClass;
{
    OUIStackedSlicesInspectorPane *pane = self;
    while (pane != nil) {
        if ([pane class] == paneClass) {
            return YES;
        }
        if ([pane isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
            pane = pane.parentSlice.containingPane;
        }
    }
    
    return NO;
}

- (BOOL)inspectorSliceOfClassHasAlreadyBeenPresented:(Class)sliceClass;
{
    OUIStackedSlicesInspectorPane *earlierPane = self.parentSlice.containingPane;
    while (earlierPane != nil) {
        OBASSERT([earlierPane isKindOfClass:[OUIStackedSlicesInspectorPane class]]);
        NSArray *parentPaneSlices = earlierPane.slices;
        for (OUIInspectorSlice *iteratedSlice in parentPaneSlices) {
            if ([iteratedSlice class] == sliceClass) {
                return YES;
            }
        }
        
        earlierPane = earlierPane.parentSlice.containingPane;
    }
    return NO;
}

#pragma mark OUIInspectorPane subclass

- (void)inspectorWillShow:(OUIInspector *)inspector;
{
    [super inspectorWillShow:inspector];
    
    // This gets called earlier than -updateInterfaceFromInspectedObjects:. Might want to switch to just calling -updateInterfaceFromInspectedObjects: here instead of in -viewWillAppear:
    [self updateSlices];
    
    for (OUIInspectorSlice *slice in _slices) {
        @autoreleasepool {
            [slice inspectorWillShow:inspector];
        }
    }
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    [self updateSlices];
    
    for (OUIInspectorSlice *slice in _slices) {
        @autoreleasepool {
            [slice updateInterfaceFromInspectedObjects:reason];
        }
    }
}

#pragma mark -
#pragma mark UIViewController

- (void)didReceiveMemoryWarning;
{
    // Make sure to do this only when the whole inspector is hidden. We don't want to kill off a pane that pushed a detail pane.
    if (self.visibility == OUIViewControllerVisibilityHidden && self.inspector.viewController.visibility == OUIViewControllerVisibilityHidden) {
        // Remove our slices now to avoid getting assertion failures about their views not being subviews of ours when we remove them.
        
        // Ditch our current slices too. When we get reloaded, we'll rebuild and re add them.
        OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
        for (OUIInspectorSlice *slice in _slices)
            _removeSlice(self, view, slice);
        
        _slices = nil;

        // Tell all our available slices about this tradegy now that they aren't children view controllers.
        [_availableSlices makeObjectsPerformSelector:@selector(fakeDidReceiveMemoryWarning)];
        
        _scrollNotifier = nil;
        view.delegate = nil;
    }
    
    [super didReceiveMemoryWarning];
}

- (UIView *)contentView;
{
    return self.view;
}

- (void)loadView;
{
    OUIStackedSlicesInspectorPaneContentView *view = [[OUIStackedSlicesInspectorPaneContentView alloc] init];

    if (!_scrollNotifier)
        _scrollNotifier = [[OUIMinimalScrollNotifierImplementation alloc] init];
    view.delegate = _scrollNotifier;

    self.sliceStackView = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    self.sliceStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sliceStackView.alignment = UIStackViewAlignmentFill;
    self.sliceStackView.axis = UILayoutConstraintAxisVertical;
    self.sliceStackView.distribution = UIStackViewDistributionEqualSpacing;
    self.sliceStackView.spacing = 0;
    [view addSubview:self.sliceStackView];

    [NSLayoutConstraint activateConstraints:
     @[
       // set up constraints so that the stackView is as big as the scrollview.
       [self.sliceStackView.leftAnchor constraintEqualToAnchor:view.leftAnchor],
       [self.sliceStackView.rightAnchor constraintEqualToAnchor: view.rightAnchor],
       [self.sliceStackView.topAnchor constraintEqualToAnchor:view.topAnchor],
       [self.sliceStackView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
       [self.sliceStackView.widthAnchor constraintEqualToAnchor:view.widthAnchor], // this is required in addition to the left & right pins, because the stackSliceView doesn't have an intrinsic content size, so, like a scroll view, it needs 6 points of definition.
       ]];

    // If we are getting our view reloaded after a memory warning, we might already have slices. They should be mostly set up, but their superview needs fixing.
    for (OUIInspectorSlice *slice in _slices) {
        OBASSERT(slice.containingPane == self);
        OBASSERT([self isChildViewController:slice]);
        UIView *sliceView = slice.view;
        [self.sliceStackView addArrangedSubview:sliceView];
        [sliceView.widthAnchor constraintEqualToAnchor:self.sliceStackView.widthAnchor].active = YES;
        sliceView.backgroundColor = [slice sliceBackgroundColor];
    }

    self.view = view;
}

- (void)viewWillAppear:(BOOL)animated;
{
    // Sadly, UINavigationController calls -navigationController:willShowViewController:animated: (which we use to provoke -inspectorWillShow:) BEFORE -viewWillAppear: when pushing but AFTER when popping. So, we have to update our list of child view controllers here too to avoid assertions in our life cycle checking. We don't want to send slices -viewWillAppear: and then drop them w/o ever sending -viewDidAppear: and the will/did disappear.
    [self updateSlices];
    
    // The last time we were on screen, we may have been dismissed because the keyboard showed.  We would have gotten the message that the keyboard was showing, and changed our bottom content inset to deal with that, but not gotten the message that the keyboard dismissed and so not have reset our bottom inset to 0.
    UIScrollView *scrollview = (UIScrollView*)self.contentView;
    UIEdgeInsets defaultInsets = scrollview.contentInset;
    if (self.inspector.alwaysShowToolbar || ([self.toolbarItems count] > 0)) {
        defaultInsets.bottom = self.navigationController.toolbar.frame.size.height;
    } else {
        defaultInsets.bottom = 0;
    }
    scrollview.contentInset = defaultInsets;

    if ([OUIInspectorAppearance inspectorAppearanceEnabled])
        [self notifyChildrenThatAppearanceDidChange:OUIInspectorAppearance.appearance];
    
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
    [view flashScrollIndicators];
    
    UIEdgeInsets margins = UIEdgeInsetsMake(0.0, self.view.layoutMargins.left, 0.0, self.view.layoutMargins.right);
    for (OUIInspectorSlice *slice in _slices)
        slice.view.layoutMargins = margins;
}

#pragma mark -
#pragma mark Keyboard Interaction

- (void)updateContentInsetsForKeyboard
{
    if (!self.isViewLoaded || self.view.window == nil) {
        return;
    }
    
    // We want to add bottom content inset ONLY if we're not being presented as popover.
    UIPresentationController *inspectorPresentationController = self.navigationController.presentationController;
    UITraitCollection *presentingTraitCollection = inspectorPresentationController.presentingViewController.traitCollection;
    
    BOOL shouldTreatAsPopover = NO;
    
#if !defined(__IPHONE_8_3) || (__IPHONE_8_3 > __IPHONE_OS_VERSION_MAX_ALLOWED)
    // iOS 8.2 and before
    shouldTreatAsPopover = (presentingTraitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular);
#else
    // iOS 8.3 and after
    shouldTreatAsPopover = (presentingTraitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) && (presentingTraitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular);
#endif
    
    if (shouldTreatAsPopover) {
        return;
    }
    
    // Add content inset to bottom of scroll view.
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
    
    OUIKeyboardNotifier *notifier = [OUIKeyboardNotifier sharedNotifier];
    UIEdgeInsets insets = view.contentInset;
    insets.bottom = notifier.lastKnownKeyboardHeight;
    if (self.inspector.alwaysShowToolbar || ([self.toolbarItems count] > 0)) {
        insets.bottom += self.navigationController.toolbar.frame.size.height;
    }
    
    [UIView animateWithDuration:notifier.lastAnimationDuration animations:^{
        [UIView setAnimationCurve:notifier.lastAnimationCurve];
        view.contentInset = insets;
    }];
}

#pragma mark - OUIInspectorAppearance

- (NSArray <id<OUIThemedAppearanceClient>> *)themedAppearanceChildClients
{
    NSArray <id<OUIThemedAppearanceClient>> *clients = self.availableSlices;
    if ([self inInspector])
        clients = [clients arrayByAddingObject:self.view];
    
    return clients;
}

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
    view.inspectorBackgroundViewColor = appearance.InspectorBackgroundColor;
    self.navigationController.toolbar.barStyle = appearance.InspectorBarStyle;
    self.navigationController.toolbar.backgroundColor = appearance.InspectorBackgroundColor;
}

@end
