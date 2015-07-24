// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorPane.h>
#import <OmniUI/OUIEmptyPaddingInspectorSlice.h>
#import <OmniUI/OUIInspectorSliceView.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUICustomSubclass.h"
#import "OUIInspectorSlice-Internal.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

// OUIInspectorSlice
OBDEPRECATED_METHOD(-updateInterfaceFromInspectedObjects); // -> -updateInterfaceFromInspectedObjects:


@interface OUIInspectorSlice ()
@property(nonatomic,retain) UIView *sliceBackgroundView;
@property (readwrite, weak, nonatomic) OUIStackedSlicesInspectorPane *lastValidContainingPane;
@end


@implementation OUIInspectorSlice
{
    OUIInspectorPane *_detailPane;
    UIView *_sliceBackgroundView;
}

+ (void)initialize;
{
    [super initialize]; // Note: Not using OBINITIALIZE because we want to execute the following code for every subclass
    
    // We add -init below for caller's convenience, but subclasses should not subclass that; they should subclass the designated initializer.
    OBASSERT(OBClassImplementingMethod(self, @selector(init)) == [OUIInspectorSlice class]);
}

+ (instancetype)slice;
{
    return [[self alloc] init];
}

+ (UIEdgeInsets)sliceAlignmentInsets;
{
    // Try to match the default UITableView insets for our default insets.
    static dispatch_once_t predicate;
    static UIEdgeInsets alignmentInsets = (UIEdgeInsets) { .left = 15.0f, .right = 15.0f, .top = 0.0f, .bottom = 0.0f };
    dispatch_once(&predicate, ^{
        UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        UIEdgeInsets separatorInsets = tableView.separatorInset;
        if (separatorInsets.left != 0.0f) {
            alignmentInsets.left = separatorInsets.left;
        }
        if (separatorInsets.right != 0.0f) {
            alignmentInsets.right = separatorInsets.right;
        }
    });
    return alignmentInsets;
}

+ (UIColor *)sliceBackgroundColor;
{
    return [UIColor whiteColor];
}

+ (UIColor *)sliceSeparatorColor;
{
#if 1
    // iOS 7 GM bug: Table views in popovers draw their separators in very light gray the second time the popover is displayed. This is to match what they end up drawing on subsequent displays, so at least we'll be consistent.
    // RADAR 14969546 : <bug:///94533> (UITableViews in popovers lose their separator color after they are first presented)
    return [UIColor colorWithWhite:0.9f alpha:1.0f];
#else
    // Use UITableView's default separator color as our default separator color.
    static dispatch_once_t predicate;
    static UIColor *separatorColor = nil;
    dispatch_once(&predicate, ^{
        UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        separatorColor = tableView.separatorColor;
    });
    return separatorColor;
#endif
}

+ (CGFloat)paddingBetweenSliceGroups;
{
    return 35.0f; // Tries to match the space in between UITableView sections.
}

+ (NSString *)nibName;
{
    // OUIAllocateViewController means we might get 'MyCustomFooInspectorSlice' for 'OUIFooInspectorSlice'. View controller's should be created so often that this would be too slow. One question is whether UINib is uniqued, though, since otherwise we perform extra I/O.
    return OUICustomClassOriginalClassName(self);
}

+ (NSBundle *)nibBundle;
{
    // OUIAllocateViewController means we might get 'MyCustomFooInspectorSlice' for 'OUIFooInspectorSlice'. View controller's should be created so often that this would be too slow. One question is whether UINib is uniqued, though, since otherwise we perform extra I/O.
    Class cls = NSClassFromString(OUICustomClassOriginalClassName(self));
    assert(cls);
    return [NSBundle bundleForClass:cls];
}

+ (id)allocWithZone:(NSZone *)zone;
{
    OUIAllocateCustomClass;
}

- init;
{
    return [self initWithNibName:[[self class] nibName] bundle:[[self class] nibBundle]];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    OBASSERT_NOT_IMPLEMENTED(self, getColorsFromObject:); // -> colorForObject:
    
    self.alignmentInsets = [[self class] sliceAlignmentInsets];
    self.groupPosition = OUIInspectorSliceGroupPositionAlone;
    self.separatorColor = [OUIInspectorSlice sliceSeparatorColor];
    
    return self;
}

- (void)dealloc;
{
    // Attempting to fix ARC weak reference cleanup crasher in <bug:///93163> (Crash after setting font color on Level 1 style)
    _detailPane.parentSlice = nil;
}

- (OUIStackedSlicesInspectorPane *)containingPane;
{
    if (self.parentViewController) {
        OBASSERT([self.parentViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]);
        self.lastValidContainingPane = (OUIStackedSlicesInspectorPane *)self.parentViewController;
    }
    return self.lastValidContainingPane;
}

- (OUIInspector *)inspector;
{
    OUIInspector *inspector = self.containingPane.inspector;
    OBASSERT(inspector);
    return inspector;
}

- (void)setAlignmentInsets:(UIEdgeInsets)newValue;
{
    if (UIEdgeInsetsEqualToEdgeInsets(_alignmentInsets, newValue)) {
        return;
    }
    
    _alignmentInsets = newValue;
    
    if (self.isViewLoaded) {
        UIView *view = self.view;
        if ([view respondsToSelector:@selector(setInspectorSliceAlignmentInsets:)]) {
            [(id)view setInspectorSliceAlignmentInsets:_alignmentInsets];
        }
    }
}

- (void)setGroupPosition:(OUIInspectorSliceGroupPosition)newValue;
{
    if (_groupPosition == newValue) {
        return;
    }
    
    _groupPosition = newValue;
    
    if (self.isViewLoaded) {
        UIView *view = self.view;
        if ([view respondsToSelector:@selector(setInspectorSliceGroupPosition:)]) {
            [(id)view setInspectorSliceGroupPosition:_groupPosition];
        }
    }
}

- (void)_pushSeparatorColor;
{
    if (self.isViewLoaded) {
        UIView *view = self.view;
        if ([view respondsToSelector:@selector(setInspectorSliceSeparatorColor:)]) {
            [(id)view setInspectorSliceSeparatorColor:_separatorColor];
        }
        if ([view isKindOfClass:[UITableView class]]) {
            [(UITableView *)view setSeparatorColor:_separatorColor];
        }
        
        view = self.sliceBackgroundView;
        if ([view respondsToSelector:@selector(setInspectorSliceSeparatorColor:)]) {
            [(id)view setInspectorSliceSeparatorColor:_separatorColor];
        }
        if ([view isKindOfClass:[UITableView class]]) {
            [(UITableView *)view setSeparatorColor:_separatorColor];
        }
    }
}

- (void)setSeparatorColor:(UIColor *)newValue;
{
    if (OFISEQUAL(_separatorColor,newValue)) {
        return;
    }
    
    _separatorColor = newValue;
    
    [self _pushSeparatorColor];
}

- (BOOL)includesInspectorSliceGroupSpacerOnTop;
{
    UIView *contentView = self.view;
    if ([contentView isKindOfClass:[UITableView class]]) {
        UITableView *tableView = (UITableView *)contentView;
        if (tableView.style == UITableViewStyleGrouped) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)includesInspectorSliceGroupSpacerOnBottom;
{
    UIView *contentView = self.view;
    if ([contentView isKindOfClass:[UITableView class]]) {
        UITableView *tableView = (UITableView *)contentView;
        if (tableView.style == UITableViewStyleGrouped) {
            return YES;
        }
    }
    return NO;
}

- (UIView *)sliceBackgroundView;
{
    if (!self.isViewLoaded) {
        (void)[self view]; // The background view normally gets loaded when the content view does, so if that's not loaded yet, do so now.
    }
    OBASSERT(_sliceBackgroundView != self.view);
    return _sliceBackgroundView;
}

- (UIView *)makeSliceBackgroundView;
{
    // If we're already providing group spacers on top and bottom, we won't need a slice background
    if (self.includesInspectorSliceGroupSpacerOnTop && self.includesInspectorSliceGroupSpacerOnBottom) {
        return nil;
    }
    
    OUIInspectorSliceView *view = [[OUIInspectorSliceView alloc] init];
#if DEBUG_OUIINSPECTORSLICEVIEW
    view.debugIdentifier = NSStringFromClass([self class]);
#endif // DEBUG_OUIINSPECTORSLICEVIEW
    return view;
}

+ (void)configureTableViewBackground:(UITableView *)tableView;
{
    // Assume that this table view is going to become part of our slice and that it should get the background from the stack.
    tableView.backgroundView = nil;
}

- (void)configureTableViewBackground:(UITableView *)tableView;
{
    [[self class] configureTableViewBackground:tableView];
}

// Uses -[UIView(OUIExtensions) borderEdgeInsets] to find out what adjustment to make to the nominal spacing to make things *look* like they are spaced that way.
static CGFloat _borderOffsetFromEdge(UIView *view, CGRectEdge fromEdge)
{
    UIEdgeInsets insets = view.borderEdgeInsets;
    
    switch (fromEdge) {
        case CGRectMinXEdge:
            return insets.left;
        case CGRectMinYEdge:
            return insets.top;
        case CGRectMaxXEdge:
            return insets.right;
        case CGRectMaxYEdge:
            return insets.bottom;
        default:
            OBASSERT_NOT_REACHED("Bad edge enum");
            return 0;
    }
}

// If we have a background view, we want to use it instead of the content view when calculating vertical spacing.
- (UIView *)_viewForVerticalPaddingCalculations;
{
    UIView *backgroundView = self.sliceBackgroundView;
    OBASSERT_IF(backgroundView != nil, self.view != nil);
    return (backgroundView != nil) ? backgroundView : self.view;
}

- (CGFloat)paddingToInspectorTop;
{
    CGFloat padding = 0.0f;
    if (!self.includesInspectorSliceGroupSpacerOnTop) {
        padding += [[self class] paddingBetweenSliceGroups];
    }
    padding -= _borderOffsetFromEdge(self._viewForVerticalPaddingCalculations, CGRectMinYEdge);
    return padding;
}

- (CGFloat)paddingToInspectorBottom;
{
    CGFloat padding = 30 - _borderOffsetFromEdge(self._viewForVerticalPaddingCalculations, CGRectMaxYEdge);
    if (self.includesInspectorSliceGroupSpacerOnBottom) {
        padding -= [[self class] paddingBetweenSliceGroups];
    }
    return padding;
}

- (CGFloat)paddingToPreviousSlice:(OUIInspectorSlice *)previousSlice remainingHeight:(CGFloat)remainingHeight;
{
    OBPRECONDITION(previousSlice);
    
    // If we're in the middle / at the end of a group, we don't want any padding between us and the previous slice.
    OUIInspectorSliceGroupPosition groupPosition = self.groupPosition;
    if ((groupPosition == OUIInspectorSliceGroupPositionCenter) || (groupPosition == OUIInspectorSliceGroupPositionLast)) {
        return _borderOffsetFromEdge(self._viewForVerticalPaddingCalculations, CGRectMinYEdge);
    }
    
    // Padding slices and background slice views are assumed to have no padding, and we assume we don't want any default padding between them and their bordering slices.
    if (previousSlice.includesInspectorSliceGroupSpacerOnBottom || (previousSlice.sliceBackgroundView != nil)) {
        return _borderOffsetFromEdge(self._viewForVerticalPaddingCalculations, CGRectMinYEdge);
    }
    if (self.includesInspectorSliceGroupSpacerOnTop || (self.sliceBackgroundView != nil)) {
        return _borderOffsetFromEdge(previousSlice._viewForVerticalPaddingCalculations, CGRectMaxYEdge);
    }
    
    // Otherwise, we assume 14 points between slices, and adjust as appropriate based on the border offsets for the slices to get the right visual spacing.
    CGFloat result = 14 - _borderOffsetFromEdge(self.view, CGRectMinYEdge) - _borderOffsetFromEdge(previousSlice.view, CGRectMaxYEdge);
    
    OBASSERT(result >= -14.0); // if the combined border of the views is too large, we can end up overlapping content and causing badness
    return result;    
}

- (CGFloat)paddingToInspectorLeft;
{
    // The goal is to match the inset of grouped table view cells (for cases where we have controls next to one), though individual inspectors may need to adjust this.
    return self.alignmentInsets.left - _borderOffsetFromEdge(self.view, CGRectMinXEdge);
}

- (CGFloat)paddingToInspectorRight;
{
    // The goal is to match the inset of grouped table view cells (for cases where we have controls next to one), though individual inspectors may need to adjust this.
    return self.alignmentInsets.right - _borderOffsetFromEdge(self.view, CGRectMaxXEdge);
}

- (CGFloat)topInsetFromSliceBackgroundView;
{
    return (_sliceBackgroundView != nil) ? _sliceBackgroundView.inspectorSliceTopBorderHeight : 0.0f;
}

- (CGFloat)bottomInsetFromSliceBackgroundView;
{
    return (_sliceBackgroundView != nil) ? _sliceBackgroundView.inspectorSliceBottomBorderHeight : 0.0f;
}

// Called on both height-resizable and non-resizable slices. Subclasses must implement this to be height sizeable. The default implementation is to just return the current view height (assuming a fixed height view). For backwards compatibility, if the view *is* height sizeable, we use kOUIInspectorWellHeight.
- (CGFloat)minimumHeightForWidth:(CGFloat)width;
{
    // Shouldn't be called unless we have a height sizeable view.
    OBPRECONDITION([self isViewLoaded]);
    
    if (self.view.autoresizingMask & UIViewAutoresizingFlexibleHeight)
        return kOUIInspectorWellHeight;
    return CGRectGetHeight(self.view.bounds);
}

- (void)sizeChanged;
{
    [self.containingPane sliceSizeChanged:self];
}

@synthesize detailPane = _detailPane;
- (void)setDetailPane:(OUIInspectorPane *)detailPane;
{
    // Just expect this to get called when loading xib. If we want to swap out details, we'll need to only do it when the detail isn't on screen.
    OBPRECONDITION(!_detailPane);
    
    _detailPane = detailPane;
    
    // propagate the inspector if we already got it set.
    _detailPane.parentSlice = self;
}

- (IBAction)showDetails:(id)sender;
{
    OBPRECONDITION(_detailPane);
    if (!_detailPane)
        return;
    
    [self.inspector pushPane:_detailPane];
}

- (BOOL)isAppropriateForInspectorPane:(OUIStackedSlicesInspectorPane *)containingPane;
{
    return YES;
}

- (BOOL)isAppropriateForInspectedObjects:(NSArray *)objects;
{
    for (id object in objects)
        if ([self isAppropriateForInspectedObject:object])
            return YES;
    return NO;
}

- (NSArray *)appropriateObjectsForInspection;
{
    OBPRECONDITION(self.containingPane);
    
    NSMutableArray *objects = nil;
    
    for (id object in self.containingPane.inspectedObjects) {
        if ([self isAppropriateForInspectedObject:object]) {
            if (!objects)
                objects = [NSMutableArray array];
            [objects addObject:object];
        }
    }
    
    return objects;
}

#ifdef NS_BLOCKS_AVAILABLE
- (void)eachAppropriateObjectForInspection:(void (^)(id obj))action;
{
    OBPRECONDITION(self.containingPane);
        
    for (id object in self.containingPane.inspectedObjects) {
        if ([self isAppropriateForInspectedObject:object])
            action(object);
    }
}
#endif

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    // For subclasses
}

- (void)inspectorWillShow:(OUIInspector *)inspector;
{
    // For subclasses
}

- (void)containingPaneDidLayout;
{
    // For subclasses. ([TAB] I believe diverse bad things may happen if you use this to provoke any layout changes, ranging from incorrect borderEdgeInsets to infinite layout recursion. Maybe.)
}

- (NSNumber *)singleSelectedValueForCGFloatSelector:(SEL)sel;
{
    CGFloat value = 0;
    BOOL hasValue = NO;
    
    for (id object in self.appropriateObjectsForInspection) {
        CGFloat (*getter)(id obj, SEL _cmd) = (typeof(getter))[object methodForSelector:sel];
        OBASSERT(getter);
        if (!getter)
            continue;
        
        CGFloat objectValue = getter(object, sel);
        if (!hasValue) {
            value = objectValue;
            hasValue = YES;
        } else if (value != objectValue)
            return nil;
    }
    
    if (hasValue)
        return [NSNumber numberWithFloat:value];
    return nil;
}

- (NSNumber *)singleSelectedValueForIntegerSelector:(SEL)sel;
{
    NSInteger value = 0;
    BOOL hasValue = NO;
    
    for (id object in self.appropriateObjectsForInspection) {
        NSInteger (*getter)(id obj, SEL _cmd) = (typeof(getter))[object methodForSelector:sel];
        OBASSERT(getter);
        if (!getter)
            continue;
        
        NSInteger objectValue = getter(object, sel);
        if (!hasValue) {
            value = objectValue;
            hasValue = YES;
        } else if (value != objectValue)
            return nil;
    }
    
    if (hasValue)
        return [NSNumber numberWithInteger:value];
    return nil;
}

- (NSValue *)singleSelectedValueForCGPointSelector:(SEL)sel;
{
    CGPoint value = CGPointZero;
    BOOL hasValue = NO;
    
    for (id object in self.appropriateObjectsForInspection) {
        CGPoint (*getter)(id obj, SEL _cmd) = (typeof(getter))[object methodForSelector:sel];
        OBASSERT(getter);
        if (!getter)
            continue;
        
        CGPoint objectValue = getter(object, sel);
        if (!hasValue) {
            value = objectValue;
            hasValue = YES;
        } else if (!CGPointEqualToPoint(value, objectValue))
            return nil;
    }
    
    if (hasValue)
        return [NSValue valueWithCGPoint:value];
    return nil;
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)setView:(UIView *)newValue;
{
    [super setView:newValue];
    
    UIView *view = self.view;
    if (view == nil) {
        self.sliceBackgroundView = nil;
    } else if (_sliceBackgroundView == nil) {
        self.sliceBackgroundView = [self makeSliceBackgroundView];
    }
    
    if ([view respondsToSelector:@selector(setInspectorSliceAlignmentInsets:)]) {
        [(id)view setInspectorSliceAlignmentInsets:_alignmentInsets];
    }
    if ([view respondsToSelector:@selector(setInspectorSliceGroupPosition:)]) {
        [(id)view setInspectorSliceGroupPosition:self.groupPosition];
    }
    [self _pushSeparatorColor];
}

- (void)fakeDidReceiveMemoryWarning;
{
    // Hack entry point for our containing OUIStackedSlicesInspectorPane.
    [super didReceiveMemoryWarning];
}

- (void)didReceiveMemoryWarning;
{
    [super didReceiveMemoryWarning];
    
    // We do nothing here. We let our stacked slices inspector handle it so it can perform an orderly teardown.
    if (self.containingPane)
        return;
    [self fakeDidReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated;
{
    OBPRECONDITION(self.containingPane != nil);
    [super viewWillAppear:animated];
}

- (void)willMoveToParentViewController:(UIViewController *)parent;
{
    OBPRECONDITION(parent == nil || [parent isKindOfClass:[OUIStackedSlicesInspectorPane class]]);
    [super willMoveToParentViewController:parent];
}

- (void)didMoveToParentViewController:(UIViewController *)parent;
{
    OBPRECONDITION(parent == nil || [parent isKindOfClass:[OUIStackedSlicesInspectorPane class]]);
    [super didMoveToParentViewController:parent];
}

@end
