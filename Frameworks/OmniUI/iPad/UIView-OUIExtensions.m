// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIDrawing.h>
#import <UIKit/UIView.h>

NSString * const OUIHuggingConstraintIdentifierLeading = @"com.omnigroup.framework.OmniUI.leading";
NSString * const OUIHuggingConstraintIdentifierTrailing = @"com.omnigroup.framework.OmniUI.trailing";
NSString * const OUIHuggingConstraintIdentifierTop = @"com.omnigroup.framework.OmniUI.top";
NSString * const OUIHuggingConstraintIdentifierBottom = @"com.omnigroup.framework.OmniUI.bottom";

@implementation UIView (OUIExtensions)

#if defined(OMNI_ASSERTIONS_ON)
    #define OUI_VIEW_CHECK_COORDINATES 0 // Too many false positives to have this on all the time
    #define OUI_VIEW_CHECK_THREADING 1
#else
    #define OUI_VIEW_CHECK_COORDINATES 0
    #define OUI_VIEW_CHECK_THREADING 0
#endif

#if OUI_VIEW_CHECK_COORDINATES
static CGRect (*_original_convertRectFromView)(UIView *self, SEL _cmd, CGRect rect, UIView *view) = NULL;
static CGRect (*_original_convertRectToView)(UIView *self, SEL _cmd, CGRect rect, UIView *view) = NULL;
static CGPoint (*_original_convertPointFromView)(UIView *self, SEL _cmd, CGPoint point, UIView *view) = NULL;
static CGPoint (*_original_convertPointToView)(UIView *self, SEL _cmd, CGPoint point, UIView *view) = NULL;
#endif

#if OUI_VIEW_CHECK_THREADING
static void (*_original_setNeedsLayout)(UIView *self, SEL _cmd) = NULL;
static void (*_original_setNeedsDisplay)(UIView *self, SEL _cmd) = NULL;
static void (*_original_setNeedsDisplayInRect)(UIView *self, SEL _cmd, CGRect) = NULL;
static void (*_original_setNeedsUpdateConstraints)(UIView *self, SEL _cmd) = NULL;
static void (*_original_invalidateIntrinsicContentSize)(UIView *self, SEL _cmd) = NULL;
#endif

#if OUI_VIEW_CHECK_COORDINATES
// -window on UIWindow returns nil instead of self. Also, though the documentation doesn't allow it, we currently want to allow the case that two views just have a common ancestor and aren't in a window at all (yet).
static UIView *_rootView(UIView *view)
{
    while (YES) {
        UIView *container = view.superview;
        if (!container)
            return view;
        view = container;
    }
}

static UIWindow *_window(UIView *view)
{
    // -window on UIWindow returns nil instead of self.
    if ([view isKindOfClass:[UIWindow class]])
        return (UIWindow *)view;
    return view.window;
}

static BOOL _viewsCompatible(UIView *self, UIView *otherView)
{
    // The documentation for this method is much more restrictive about this than what seems to actually happen.
    // UIKit will attempt to convert points between different UIWindows in context menus, so we'll allow that here.

    
    if (!otherView) {
        // "If aView is nil, this method instead converts to/from window base coordinates"
        
        // Not sure what to do other than whitelist UISearchResultsTableView which has a nil root view when an instance of UISearchDisplayController is present, but not in the view hierarchy. See <bug:///81503> (Failed assertion switching between calendars and search in Forecast view).
        if ([self isKindOfClass:NSClassFromString(@"UISearchResultsTableView")])
            return YES;
        
        // Not sure what UIKit does in this case. It might just not do any transform, but until we need it we'll stick to requiring a window.
//      UIView *root = _rootView(self);
//      OBASSERT([root isKindOfClass:[UIWindow class]]);
        return YES;
    }
    
    // Bail on the text selection loupe for standard UIKit controls. Not our problem.
    if ([self isKindOfClass:NSClassFromString(@"UITextRangeView")] ||
        [otherView isKindOfClass:NSClassFromString(@"UITextRangeView")])
        return YES;

    // Bail on the UIPeripheralHostView. Not our problem.
    if ([self isKindOfClass:NSClassFromString(@"UIPeripheralHostView")] ||
        [otherView isKindOfClass:NSClassFromString(@"UIPeripheralHostView")])
        return YES;

    // Bail on the UICalloutBar. Not our problem.
    if ([self isKindOfClass:NSClassFromString(@"UICalloutBar")] ||
        [otherView isKindOfClass:NSClassFromString(@"UICalloutBar")])
        return YES;
    
    // Bail on the UIKBBackdropView. Not our problem.
    if ([self isKindOfClass:NSClassFromString(@"UIKBBackdropView")] ||
        [otherView isKindOfClass:NSClassFromString(@"UIKBBackdropView")])
        return YES;

    // Bail on the snapshot view. There is some internal UIKit magic going on that takes advantage of whatever the default behavior of the transform is when they aren't in the same window.
    if ([self isKindOfClass:NSClassFromString(@"UISnapshotView")] ||
        [otherView isKindOfClass:NSClassFromString(@"UISnapshotView")])
        return YES;
    
    // If an <MKAnnotation> canShowCallout, selecting that annotation generates a convertPoint:toView: where the UICalloutView is not yet associated with a window. Bail in that case.
    // There are, however, cases where UICalloutView would correctly pass our assertions (e.g. tapping an accessory view button in the callout), but these framework behaviours are not our concern in these validations.
    if ([self isKindOfClass:NSClassFromString(@"UICalloutView")] ||
        [otherView isKindOfClass:NSClassFromString(@"UICalloutView")])
        return YES;
    
    // Bail on the PLTileContainerView. Not our problem.
    if ([self isKindOfClass:NSClassFromString(@"PLTileContainerView")] ||
        [otherView isKindOfClass:NSClassFromString(@"PLTileContainerView")])
        return YES;

    // Bail on the assertion when UIKit is removing the tint view from the current window because it does this bogus conversion.
    // Hopefully silencing this false positive doesn't also silence other warnings we do care about.
    // This quiets the assertion in OmniFocus for iPad when showing the sidebar "popover".
    if ([self isKindOfClass:[UIWindow class]] &&
        [otherView isKindOfClass:[UINavigationBar class]] &&
        otherView.window == nil)
        return YES;
    
    // Bail on the assertion when we're pushing or popping a navigation item on a navigation bar and that item isn't in a window yet
    if ([self isKindOfClass:NSClassFromString(@"UINavigationItemView")] &&
        [otherView isKindOfClass:[UINavigationBar class]] &&
        [self window] == nil)
        return YES;
    
    // Without this pool, the OO/iPad zombies with these assertions on due to an over-autorelease when exiting a field editor. Guessing there is an ARC bug of some sort, but it isn't clear...
    @autoreleasepool {
        // "Otherwise, both view and the receiver must belong to the same UIWindow object."
        // We just require that they have a common ancestor view, though.
        UIView *root1 = _rootView(self);
        UIView *root2 = _rootView(otherView);
        
        if (root1 == root2)
            return YES;
        
        // Bail on UITextEffectsWindow. Not our problem.
        if ([root1 isKindOfClass:NSClassFromString(@"UITextEffectsWindow")] ||
            [root2 isKindOfClass:NSClassFromString(@"UITextEffectsWindow")])
            return YES;
        
        UIWindow *window1 = _window(self);
        UIWindow *window2 = _window(otherView);
        
        // Might actually be allowed if they are on any screen, but it isn't clear how UIKit would treat those transforms since there is no screen arrangement UI (presumably left-to-right with the top-edge aligned, but who knows).
        OBASSERT(window1.screen == window2.screen);
        
        return YES;
    }
}

static CGRect _replacement_convertRectFromView(UIView *self, SEL _cmd, CGRect rect, UIView *view)
{
    OBPRECONDITION(_viewsCompatible(self, view));
    return _original_convertRectFromView(self, _cmd, rect, view);
}

static CGRect _replacement_convertRectToView(UIView *self, SEL _cmd, CGRect rect, UIView *view)
{
    OBPRECONDITION(_viewsCompatible(self, view));
    return _original_convertRectToView(self, _cmd, rect, view);
}

static CGPoint _replacement_convertPointFromView(UIView *self, SEL _cmd, CGPoint point, UIView *view)
{
    OBPRECONDITION(_viewsCompatible(self, view));
    return _original_convertPointFromView(self, _cmd, point, view);
}

static CGPoint _replacement_convertPointToView(UIView *self, SEL _cmd, CGPoint point, UIView *view)
{
    OBPRECONDITION(_viewsCompatible(self, view));
    return _original_convertPointToView(self, _cmd, point, view);
}

static void (*_original_setFrame)(UIView *self, SEL _cmd, CGRect rect) = NULL;
static void (*_original_setBounds)(UIView *self, SEL _cmd, CGRect rect) = NULL;
static void (*_original_setCenter)(UIView *self, SEL _cmd, CGPoint point) = NULL;

#endif // OUI_VIEW_CHECK_COORDINATES

#ifdef OMNI_ASSERTIONS_ON
static BOOL checkValue(CGFloat v)
{
    OBASSERT(!isnan(v));
    OBASSERT(!isinf(v));
    return YES;
}

BOOL OUICheckValidFrame(CGRect rect)
{
    OBASSERT(checkValue(rect.origin.x));
    OBASSERT(checkValue(rect.origin.y));
    OBASSERT(checkValue(rect.size.width));
    OBASSERT(checkValue(rect.size.height));
    return YES;
}
#endif

#if OUI_VIEW_CHECK_COORDINATES
static BOOL OUIShouldIgnoreProblemsInView(UIView *self)
{
    // Popping up a UIMenuController temporarily makes x=+Inf frames
    if ([self containingViewMatching:^(UIView *view){
        return [NSStringFromClass([view class]) isEqual:@"UICalloutBar"];
    }])
        return YES;
    
    return NO;
}

static void _replacement_setFrame(UIView *self, SEL _cmd, CGRect rect)
{
    if (OUIShouldIgnoreProblemsInView(self) == NO) {
        OBASSERT(OUICheckValidFrame(rect));
    }
    _original_setFrame(self, _cmd, rect);
}
static void _replacement_setBounds(UIView *self, SEL _cmd, CGRect rect)
{
    if (OUIShouldIgnoreProblemsInView(self) == NO) {
        OBASSERT(OUICheckValidFrame(rect));
    }
    _original_setBounds(self, _cmd, rect);
}
static void _replacement_setCenter(UIView *self, SEL _cmd, CGPoint point)
{
    if (OUIShouldIgnoreProblemsInView(self) == NO) {
        OBASSERT(checkValue(point.x));
        OBASSERT(checkValue(point.y));
    }
    _original_setCenter(self, _cmd, point);
}
#endif


#if OUI_VIEW_CHECK_THREADING
static void _replacement_setNeedsLayout(UIView *self, SEL _cmd)
{
    OBPRECONDITION([NSThread isMainThread]);
    _original_setNeedsLayout(self, _cmd);
}

static void _replacement_setNeedsDisplay(UIView *self, SEL _cmd)
{
    OBPRECONDITION([NSThread isMainThread]);
    _original_setNeedsDisplay(self, _cmd);
}

static void _replacement_setNeedsDisplayInRect(UIView *self, SEL _cmd, CGRect rect)
{
    OBPRECONDITION([NSThread isMainThread]);
    _original_setNeedsDisplayInRect(self, _cmd, rect);
}

static void _replacement_setNeedsUpdateConstraints(UIView *self, SEL _cmd)
{
    OBPRECONDITION([NSThread isMainThread]);
    _original_setNeedsUpdateConstraints(self, _cmd);
}

static void _replacement_invalidateIntrinsicContentSize(UIView *self, SEL _cmd)
{
    OBPRECONDITION([NSThread isMainThread]);
    _original_invalidateIntrinsicContentSize(self, _cmd);
}
#endif

#if OUI_VIEW_CHECK_COORDINATES
static void OUIViewPerformPosingForCoordinates(void) __attribute__((constructor));
static void OUIViewPerformPosingForCoordinates(void)
{
    Class viewClass = NSClassFromString(@"UIView");
    _original_convertRectFromView = (typeof(_original_convertRectFromView))OBReplaceMethodImplementation(viewClass, @selector(convertRect:fromView:), (IMP)_replacement_convertRectFromView);
    _original_convertRectToView = (typeof(_original_convertRectToView))OBReplaceMethodImplementation(viewClass, @selector(convertRect:toView:), (IMP)_replacement_convertRectToView);
    _original_convertPointFromView = (typeof(_original_convertPointFromView))OBReplaceMethodImplementation(viewClass, @selector(convertPoint:fromView:), (IMP)_replacement_convertPointFromView);
    _original_convertPointToView = (typeof(_original_convertPointToView))OBReplaceMethodImplementation(viewClass, @selector(convertPoint:toView:), (IMP)_replacement_convertPointToView);

    _original_setFrame = (typeof(_original_setFrame))OBReplaceMethodImplementation(viewClass, @selector(setFrame:), (IMP)_replacement_setFrame);
    _original_setBounds = (typeof(_original_setBounds))OBReplaceMethodImplementation(viewClass, @selector(setBounds:), (IMP)_replacement_setBounds);
    _original_setCenter = (typeof(_original_setCenter))OBReplaceMethodImplementation(viewClass, @selector(setCenter:), (IMP)_replacement_setCenter);
}
#endif

#if OUI_VIEW_CHECK_THREADING
static void OUIViewPerformPosingForThreading(void) __attribute__((constructor));
static void OUIViewPerformPosingForThreading(void)
{
    Class viewClass = NSClassFromString(@"UIView");
    
    _original_setNeedsLayout = (typeof(_original_setNeedsLayout))OBReplaceMethodImplementation(viewClass, @selector(setNeedsLayout), (IMP)_replacement_setNeedsLayout);
    _original_setNeedsDisplay = (typeof(_original_setNeedsDisplay))OBReplaceMethodImplementation(viewClass, @selector(setNeedsDisplay), (IMP)_replacement_setNeedsDisplay);
    _original_setNeedsDisplayInRect = (typeof(_original_setNeedsDisplayInRect))OBReplaceMethodImplementation(viewClass, @selector(setNeedsDisplayInRect:), (IMP)_replacement_setNeedsDisplayInRect);
    _original_setNeedsUpdateConstraints = (typeof(_original_setNeedsUpdateConstraints))OBReplaceMethodImplementation(viewClass, @selector(setNeedsUpdateConstraints), (IMP)_replacement_setNeedsUpdateConstraints);
    _original_invalidateIntrinsicContentSize = (typeof(_original_invalidateIntrinsicContentSize))OBReplaceMethodImplementation(viewClass, @selector(invalidateIntrinsicContentSize), (IMP)_replacement_invalidateIntrinsicContentSize);
}
#endif

+ (UIView *)topLevelViewFromNibNamed:(NSString *)nibName;
{
    UINib *nib = [UINib nibWithNibName:nibName bundle:nil];
    NSArray *topLevelObjects = [nib instantiateWithOwner:nil options:nil];
    OBASSERT([topLevelObjects count] == 1);
    
    UIView *topLevelView = (UIView *)[topLevelObjects firstObject];
    OBASSERT([topLevelView isKindOfClass:[UIView class]]);
    
    return topLevelView;
}

- (UIImage *)snapshotImageWithRect:(CGRect)rect;
{
    OBPRECONDITION(rect.size.width >= 1);
    OBPRECONDITION(rect.size.height >= 1);
    OBPRECONDITION(CGRectContainsRect(self.bounds, rect)); // Don't want to have to fill/clear uncovered areas in the image, but we could if a caller needs it.

    [self layoutIfNeeded];
    
    UIImage *image;
    
    // CGRect bounds = self.bounds;
    // OBASSERT(bounds.size.width >= 1);
    // OBASSERT(bounds.size.height >= 1);
    
    OUIGraphicsBeginImageContext(rect.size);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextTranslateCTM(ctx, -rect.origin.x, -rect.origin.y);
        
        // Switching back to render in context because -drawViewHierarchyInRect: puts the view onscreen or something and causes flicker to ongoing animation <bug:///92160> 
        //if (![self drawViewHierarchyInRect:bounds afterScreenUpdates:YES]) {
        //    OBASSERT_NOT_REACHED("Some bitmap contents missing");
        //}
        [[self layer] renderInContext:ctx];
        
        image = UIGraphicsGetImageFromCurrentImageContext();
    }
    OUIGraphicsEndImageContext();
    
    return image;
}

- (UIImage *)snapshotImageWithSize:(CGSize)imageSize;
{
    OBPRECONDITION(imageSize.width >= 1);
    OBPRECONDITION(imageSize.height >= 1);
    
    [self layoutIfNeeded];
    
    UIImage *image;
    
    CGRect bounds = self.bounds;
    OBASSERT(bounds.size.width >= 1);
    OBASSERT(bounds.size.height >= 1);
    
    OUIGraphicsBeginImageContext(imageSize);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextTranslateCTM(ctx, -bounds.origin.x, -bounds.origin.y);
        CGContextScaleCTM(ctx, imageSize.width / bounds.size.width, imageSize.height / bounds.size.height);
        
        [[self layer] renderInContext:ctx];
        
        image = UIGraphicsGetImageFromCurrentImageContext();
    }
    OUIGraphicsEndImageContext();
    
    return image;
}

- (UIImage *)snapshotImageWithScale:(CGFloat)scale;
{
    CGRect bounds = self.bounds;
    CGSize imageSize = CGSizeMake(ceil(bounds.size.width * scale),
                                  ceil(bounds.size.height * scale));
    
    return [self snapshotImageWithSize:imageSize];
}

- (UIImage *)snapshotImage;
{
    return [self snapshotImageWithScale:1.0];
}

- (UIMotionEffect *)tiltMotionEffectWithMaxTilt:(CGFloat)maxTilt;
{
    UIInterpolatingMotionEffect *xAxis = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    xAxis.minimumRelativeValue = [NSNumber numberWithFloat:-maxTilt];
    xAxis.maximumRelativeValue = [NSNumber numberWithFloat:maxTilt];
    
    UIInterpolatingMotionEffect *yAxis = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    yAxis.minimumRelativeValue = [NSNumber numberWithFloat:-maxTilt];
    yAxis.maximumRelativeValue = [NSNumber numberWithFloat:maxTilt];
    
    UIMotionEffectGroup *group = [[UIMotionEffectGroup alloc] init];
    group.motionEffects = @[xAxis, yAxis];
    return group;
}

- (void)addMotionMaxTilt:(CGFloat)maxTilt;
{
    [self addMotionEffect:[self tiltMotionEffectWithMaxTilt:maxTilt]];
}

- (id)containingViewOfClass:(Class)cls;
{
    return [self enclosingViewOfClass:cls];
}

- (id)enclosingViewOfClass:(Class)cls; // can return self
{
    return [self enclosingViewMatching:^(id view){
        return [view isKindOfClass:cls];
    }];
}

- (id)containingViewMatching:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    return [self enclosingViewMatching:predicate];
}

- (id)enclosingViewMatching:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    if (!predicate) {
        OBASSERT_NOT_REACHED("Treating nil predicate as true... probably not that useful");
        return self;
    }
    
    UIView *view = self;
    while (view) {
        if (predicate(view))
            return view;
        view = view.superview;
    }
    return nil;
}

- (OUIViewVisitorResult)applyToViewTree:(OUIViewVisitorBlock)block;
{
    if (block == NULL)
        return OUIViewVisitorResultStop;

    switch (block(self)) {
        case OUIViewVisitorResultStop:
            return OUIViewVisitorResultStop;
            
        case OUIViewVisitorResultSkipSubviews:
            return OUIViewVisitorResultContinue;
            
        case OUIViewVisitorResultContinue:
            for (UIView *view in self.subviews) {
                if ([view applyToViewTree:block] == OUIViewVisitorResultStop)
                    return OUIViewVisitorResultStop;
            }
            return OUIViewVisitorResultContinue;

        default:
            OBASSERT_NOT_REACHED("unhandled case");
            return OUIViewVisitorResultStop;
    }
}

const CGFloat StandardSpacingMetric = -10000.0f;
const CGFloat LayoutMarginMetric = -20000.0f;

+ (CGFloat)standardSpacingMetric;
{
    return StandardSpacingMetric;
}

+ (CGFloat)layoutMarginMetric;
{
    return LayoutMarginMetric;
}

+ (UIEdgeInsets)standardSpacingEdgeInsets;
{
    return UIEdgeInsetsMake(StandardSpacingMetric, StandardSpacingMetric, StandardSpacingMetric, StandardSpacingMetric);
}

+ (UIEdgeInsets)layoutMarginEdgeInsets;
{
    return UIEdgeInsetsMake(LayoutMarginMetric, LayoutMarginMetric, LayoutMarginMetric, LayoutMarginMetric);
}

- (NSArray<NSLayoutConstraint *> *)constraintsToHugSubview:(UIView *)subview horizontalLayoutMargin:(CGFloat)horizontalLayoutMargin verticalLayoutMargin:(CGFloat)verticalLayoutMargin;
{
    UIEdgeInsets insets = UIEdgeInsetsMake(verticalLayoutMargin, horizontalLayoutMargin, verticalLayoutMargin, horizontalLayoutMargin);
    return [self constraintsToHugSubview:subview insets:insets];
}

- (NSArray<NSLayoutConstraint *> *)constraintsToHugSubview:(UIView *)subview insets:(UIEdgeInsets)insets;
{
    OBPRECONDITION(subview.superview == self);
    subview.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *leadingConstraint = nil;
    NSLayoutConstraint *trailingConstraint = nil;
    NSLayoutConstraint *topConstraint = nil;
    NSLayoutConstraint *bottomConstraint = nil;

    if (insets.left == StandardSpacingMetric) {
        leadingConstraint = [subview.leadingAnchor constraintEqualToSystemSpacingAfterAnchor:self.leadingAnchor multiplier:1.0];
    } else if (insets.left == LayoutMarginMetric) {
        leadingConstraint = [subview.leadingAnchor constraintEqualToSystemSpacingAfterAnchor:self.layoutMarginsGuide.leadingAnchor multiplier:1.0];
    } else {
        leadingConstraint = [subview.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:insets.left];
    }

    if (insets.right == StandardSpacingMetric) {
        trailingConstraint = [self.trailingAnchor constraintEqualToSystemSpacingAfterAnchor:subview.trailingAnchor multiplier:1.0];
    } else if (insets.right == LayoutMarginMetric) {
        trailingConstraint = [self.layoutMarginsGuide.trailingAnchor constraintEqualToSystemSpacingAfterAnchor:subview.trailingAnchor multiplier:1.0];
    } else {
        trailingConstraint = [self.trailingAnchor constraintEqualToAnchor:subview.trailingAnchor constant:insets.right];
    }

    if (insets.top == StandardSpacingMetric) {
        topConstraint = [subview.topAnchor constraintEqualToSystemSpacingBelowAnchor:self.topAnchor multiplier:1.0];
    } else if (insets.top == LayoutMarginMetric) {
        topConstraint = [subview.topAnchor constraintEqualToSystemSpacingBelowAnchor:self.layoutMarginsGuide.topAnchor multiplier:1.0];
    } else {
        topConstraint = [subview.topAnchor constraintEqualToAnchor:self.topAnchor constant:insets.top];
    }

    if (insets.bottom == StandardSpacingMetric) {
        bottomConstraint = [self.bottomAnchor constraintEqualToSystemSpacingBelowAnchor:subview.bottomAnchor multiplier:1.0];
    } else if (insets.bottom == LayoutMarginMetric) {
        bottomConstraint = [subview.bottomAnchor constraintEqualToSystemSpacingBelowAnchor:self.layoutMarginsGuide.bottomAnchor multiplier:1.0];
    } else {
        bottomConstraint = [self.bottomAnchor constraintEqualToAnchor:subview.bottomAnchor constant:insets.bottom];
    }
    
    leadingConstraint.identifier = OUIHuggingConstraintIdentifierLeading;
    trailingConstraint.identifier = OUIHuggingConstraintIdentifierTrailing;
    topConstraint.identifier = OUIHuggingConstraintIdentifierTop;
    bottomConstraint.identifier = OUIHuggingConstraintIdentifierBottom;
    
    return @[
        leadingConstraint,
        trailingConstraint,
        topConstraint,
        bottomConstraint,
    ];
}

- (NSArray<NSLayoutConstraint *> *)constraintsToHugSubview:(UIView *)subview preferHorizontalLayoutMargin:(BOOL)preferHorizontalLayoutMargin preferVerticalLayoutMargin:(BOOL)preferVerticalLayoutMargin;
{
    return [self constraintsToHugSubview:subview horizontalLayoutMargin:preferHorizontalLayoutMargin ? LayoutMarginMetric : 0.0f verticalLayoutMargin:preferVerticalLayoutMargin ? LayoutMarginMetric : 0.0f];
}

- (void)addConstraintsToHugSubview:(UIView *)subview preferHorizontalLayoutMargin:(BOOL)preferHorizontalLayoutMargin preferVerticalLayoutMargin:(BOOL)preferVerticalLayoutMargin;
{
    NSArray *constraints = [self constraintsToHugSubview:subview preferHorizontalLayoutMargin:preferHorizontalLayoutMargin preferVerticalLayoutMargin:preferVerticalLayoutMargin];
    [NSLayoutConstraint activateConstraints:constraints];
}

- (NSArray<NSLayoutConstraint *> *)standardSpacingConstraintsForSubview:(UIView *)subview;
{
    return [self constraintsToHugSubview:subview preferHorizontalLayoutMargin:YES preferVerticalLayoutMargin:YES];
}

- (void)addStandardSpacingConstraintsForSubview:(UIView *)subview;
{
    [self addConstraintsToHugSubview:subview preferHorizontalLayoutMargin:YES preferVerticalLayoutMargin:YES];
}

- (NSArray<NSLayoutConstraint *> *)huggingConstraintsForSubview:(UIView *)subview;
{
    return [self constraintsToHugSubview:subview preferHorizontalLayoutMargin:NO preferVerticalLayoutMargin:NO];
}

- (void)addHuggingConstraintsForSubview:(UIView *)subview;
{
    [self addConstraintsToHugSubview:subview preferHorizontalLayoutMargin:NO preferVerticalLayoutMargin:NO];
}


// Subclass to return YES if this view has no border or doesn't want to be in your border finding nonsense.
- (BOOL)skipWhenComputingBorderEdgeInsets;
{
    return self.hidden || self.alpha == 0;
}

// Subclass to return YES for background-y type views that are just for grouping/positioning. Often this will just be a UIView so this shouldn't be needed.
- (BOOL)recurseWhenComputingBorderEdgeInsets;
{
    return [self class] == [UIView class];
}

- (UIEdgeInsets)borderEdgeInsets;
{
    // Shouldn't have called this, then.
    OBPRECONDITION(self.skipWhenComputingBorderEdgeInsets == NO);

    CGRect unionBorderRect = CGRectNull;
    
    if ([self class] != [UIView class]) {
        // We are either a concrete view of some sort that should define our border insets directly (even if we have implementation defined subviews like UIButton does), or we are a background/placement view of some sort that should define -ignoreWhenComputingBorderEdgeInsets to return YES. Default to using the entire frame for the concrete view case (not recursing and looking at the implementation detail views).
        if (!self.recurseWhenComputingBorderEdgeInsets)
            return UIEdgeInsetsZero;
    }
    
    // Default to looking through our subviews, finding their effective border rects and unioning that.
    for (UIView *subview in self.subviews) {
        if (subview.skipWhenComputingBorderEdgeInsets)
            continue;
        
        UIEdgeInsets subviewInsets = subview.borderEdgeInsets;
        
        CGRect borderRect = [self convertRect:UIEdgeInsetsInsetRect(subview.bounds, subviewInsets) fromView:subview];
        if (CGRectEqualToRect(unionBorderRect, CGRectNull))
            unionBorderRect = borderRect;
        else
            unionBorderRect = CGRectUnion(unionBorderRect, borderRect);
    }

    // If no subviews have a border, this this is most likely a leaf view that wants default behavior of having its border go to the edge.
    if (CGRectEqualToRect(unionBorderRect, CGRectNull)) {
        // We also could someday support nested container UIViews that happen to currently have all their subviews hidden and so shouldn't count.
        // But having leaf "concrete" vews return OUINoBorderEdgeInsets here by default means that they will get cut off by default when grouped in a parent UIView.
        OBASSERT([self class] != [UIView class]);
        OBASSERT([[self subviews] count] == 0);
        
        return UIEdgeInsetsZero;
    }
    
    // Now, calculate the effective inset from our bounds
    CGRect bounds = self.bounds;
    return (UIEdgeInsets){
        .top = CGRectGetMinY(unionBorderRect) - CGRectGetMinY(bounds),
        .left = CGRectGetMinX(unionBorderRect) - CGRectGetMinX(bounds),
        .right = CGRectGetMaxX(bounds) - CGRectGetMaxX(unionBorderRect),
        .bottom = CGRectGetMaxY(bounds) - CGRectGetMaxY(unionBorderRect),
    };
}

- (void)expectDeallocationOfViewTreeSoon;
{
    if (OBExpectedDeallocationsIsEnabled()) {
        [self applyToViewTree:^(UIView *treeView) {
            OBExpectDeallocationWithPossibleFailureReason(treeView, ^NSString *(UIView *remainingView){
                if (remainingView.superview)
                    return @"still has superview";
                return nil;
            });
            return OUIViewVisitorResultContinue;
        }];
    }
}

// Terrible. There doesn't seem to be a proper way to set the field editor's text color, or access the field editor
- (void)recursivelySetUITextFieldColor:(UIColor *)color;
{
    for (UIView *subview in self.subviews) {
        [subview recursivelySetUITextFieldColor:color];
    }
}

- (UIScene *)containingScene
{
    return self.window.windowScene;
}

@end

@implementation UITextField (RecursivelySetUITextFieldColor)

- (void)recursivelySetUITextFieldColor:(UIColor *)color;
{
    self.textColor = color;
}

@end

#ifdef DEBUG // Uses private API
UIResponder *OUIWindowFindFirstResponder(UIWindow *window)
{
    return [window valueForKey:@"firstResponder"];
}

static void _OUIAppendViewTreeDescription(NSMutableString *str, UIView *view, NSUInteger indent)
{
    for (NSUInteger i = 0; i < indent; i++)
        [str appendString:@"  "];
    [str appendString:[view shortDescription]];
    
    for (UIView *subview in view.subviews)
        _OUIAppendViewTreeDescription(str, subview, indent + 1);
}

void OUILogViewTree(UIView *root)
{
    NSMutableString *str = [NSMutableString string];
    _OUIAppendViewTreeDescription(str, root, 0);
    
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    fwrite([data bytes], 1, [data length], stderr);
    fputc('\n', stderr);
}

#endif

UIViewAnimationOptions OUIAnimationOptionFromCurve(UIViewAnimationCurve curve) {
    // UIViewAnimationOptions shifts the UIViewAnimationCurve up 16 bits.
    // This approach handles non-public animation curves we need to follow as well (for example, when the keyboard is being displayed)
    return curve << 16;
}

// Allows the caller to conditionally leave animations as they were or disable them. Won't ever force animations on.
void OUIWithAnimationsDisabled(BOOL disabled, void (NS_NOESCAPE ^actions)(void))
{
    if (disabled)
        OUIWithoutAnimating(actions);
    else
        actions();
}

void OUIWithoutAnimating(void (NS_NOESCAPE ^actions)(void))
{
    BOOL wasAnimating = [UIView areAnimationsEnabled];
    @try {
        if (wasAnimating)
            [UIView setAnimationsEnabled:NO];
        actions();
    } @finally {
        OBASSERT(![UIView areAnimationsEnabled]); // Make sure something hasn't turned it on again, like -[UIToolbar setItem:] (Radar 8496247)
        if (wasAnimating)
            [UIView setAnimationsEnabled:YES];
    }
}

void OUIWithoutLayersAnimating(void (NS_NOESCAPE ^actions)(void))
{
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    actions();
    [CATransaction commit];
}

void OUIWithLayerAnimationsDisabled(BOOL disabled, void (NS_NOESCAPE ^actions)(void))
{
    if (disabled)
        OUIWithoutLayersAnimating(actions);
    else
        actions();
}

void OUIWithAppropriateLayerAnimations(void (NS_NOESCAPE ^actions)(void))
{
    BOOL shouldAnimate = [UIView areAnimationsEnabled];
    OUIWithLayerAnimationsDisabled(shouldAnimate == NO, actions);
}

// A (hopefully) rarely needed hack, given a name here to make it a bit more clear what is happening.
void OUIDisplayNeededViews(void)
{
    // The view/layer rendering trigger is registered as run loop observer on the main thread. Poke it.
    OBPRECONDITION([NSThread isMainThread]);
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
}
