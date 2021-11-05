// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>

#import <OmniUI/OUICustomSubclass.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorPane.h>
#import <OmniUI/OUIEmptyPaddingInspectorSlice.h>
#import <OmniUI/OUIInspectorSliceView.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIInspectorSlice-Internal.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

// OUIInspectorSlice
OBDEPRECATED_METHOD(-updateInterfaceFromInspectedObjects); // -> -updateInterfaceFromInspectedObjects:

// these should all be done via constraints now
OBDEPRECATED_METHOD(-paddingToInspectorTop);
OBDEPRECATED_METHOD(-paddingToInspectorBottom);
OBDEPRECATED_METHOD(-paddingToInspectorLeft);
OBDEPRECATED_METHOD(-paddingToInspectorRight);
OBDEPRECATED_METHOD(-paddingToPreviousSlice:remainingHeight:);
OBDEPRECATED_METHOD(-topInsetFromSliceBackgroundView);
OBDEPRECATED_METHOD(-bottomInsetFromSliceBackgroundView);
OBDEPRECATED_METHOD(-minimumHeightForWidth:);

@implementation OUIInspectorSlice
{
    OUIInspectorPane *_detailPane;
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
    static UIEdgeInsets alignmentInsets = (UIEdgeInsets) { .left = 16, .right = 16, .top = 0.0f, .bottom = 0.0f };
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

+ (NSDirectionalEdgeInsets)sliceDirectionalLayoutMargins;
{
    // Try to match the default UITableView insets for our default insets.
    static dispatch_once_t predicate;
    static NSDirectionalEdgeInsets directionalEdgeInsets = (NSDirectionalEdgeInsets){0,0,0,0};
    dispatch_once(&predicate, ^{
        UIEdgeInsets sliceAlignmentInsets = [self sliceAlignmentInsets];
        directionalEdgeInsets = NSDirectionalEdgeInsetsMake(sliceAlignmentInsets.top, sliceAlignmentInsets.left, sliceAlignmentInsets.bottom, sliceAlignmentInsets.right);
    });
    return directionalEdgeInsets;
}

- (UIColor *)sliceBackgroundColor;
{
    return [[self class] sliceBackgroundColor];
}

+ (UIColor *)sliceBackgroundColor;
{
    return [UIColor colorNamed:@"inspectorSliceBackgroundColor" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

+ (UIColor *)sliceSeparatorColor;
{
    // Use UITableView's default separator color as our default separator color.
    static dispatch_once_t predicate;
    static UIColor *separatorColor = nil;
    dispatch_once(&predicate, ^{
        UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        separatorColor = tableView.separatorColor;
    });
    return separatorColor;
}

+ (CGFloat)paddingBetweenSliceGroups;
{
    return 35.0f; // Tries to match the space in between UITableView sections.
}

+ (NSString *)nibName;
{
    // OUIAllocateViewController means we might get 'MyCustomFooInspectorSlice' for 'OUIFooInspectorSlice'. View controller's should be created so often that this would be too slow. One question is whether UINib is uniqued, though, since otherwise we perform extra I/O.
    // Swift classes prepend their module name to the value returned from NSStringFromClass(), which is in turn passed back from OUICustomClassOriginalClassName(). The compiled nib is extremely unlikely to have a module-scoped filename. Strip the leading module and dot before handing back the nib name.
    NSString *className = OUICustomClassOriginalClassName(self);
    NSRange dotRange  = [className rangeOfString:@"."];
    if (dotRange.location != NSNotFound)
        className = [className substringFromIndex:(dotRange.location + dotRange.length)];
    return className;
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
    self.suppressesTrailingImplicitSeparator = NO;
    
    return self;
}

- (OUIInspector *)inspector;
{
    OUIInspector *inspector = self.containingPane.inspector;
    OBASSERT(inspector);
    return inspector;
}

- (UIView *)contentView {
    if (_contentView == nil) {
        _contentView = [[UIView alloc] init];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_contentView];
        
        // These constraints were created but never activated. Many inspector slices (if not all) are adding their parts to self.view instead of self.contentView, and they wind up occluded by contentView and unable to receive touches. Let's see if we can get by without this view, but we may need to do some cleanup later (remove this view, or fix all the slices to use it properly).
//        NSArray *constraints = @[
//             [_contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
//             [_contentView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor],
//             [_contentView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
//             [_contentView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor]];
//        [NSLayoutConstraint activateConstraints:constraints];
    }
    
    return _contentView;
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
    if (!self.isViewLoaded) {
        return NO;
    }
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
    if (!self.isViewLoaded) {
        return NO;
    }
    UIView *contentView = self.view;
    if ([contentView isKindOfClass:[UITableView class]]) {
        UITableView *tableView = (UITableView *)contentView;
        if (tableView.style == UITableViewStyleGrouped) {
            return YES;
        }
    }
    return NO;
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

// If we have a background view, we want to use it instead of the content view when calculating vertical spacing.
- (UIView *)_viewForVerticalPaddingCalculations;
{
    return self.view;
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
    OUIStackedSlicesInspectorPane *containingPane = self.containingPane;
    OBPRECONDITION(containingPane, "<bug:///150992> (iOS-OmniPlan Unassigned: OPBaselinesInspectorSlice looks for appropriateObjectsForInspection too early and fails assertion)");
    
    NSMutableArray *objects = nil;
    
    for (id object in containingPane.inspectedObjects) {
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
    OUIStackedSlicesInspectorPane *containingPane = self.containingPane;
    OBPRECONDITION(containingPane);
        
    for (id object in containingPane.inspectedObjects) {
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
