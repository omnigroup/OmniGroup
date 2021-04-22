// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSStackView-OAExtensions.h>

#import <Cocoa/Cocoa.h>

RCS_ID("$Id$")


NS_ASSUME_NONNULL_BEGIN

static CGFloat _viewSizeForOrientation(NSView *view, NSUserInterfaceLayoutOrientation orientation)
{
    return (orientation == NSUserInterfaceLayoutOrientationVertical) ? view.fittingSize.height : view.fittingSize.width;
}

// This static string is used for debugging help, and also to provide the associated object key for the subviews' temporary layout constraint
static NSString *const OAAnimatedHidingSupportConstraintIdentifier = @"Temporary OAAnimatedHidingSupport constraint";

typedef enum {
    OAAnimatedHiddenStateHidden,
    OAAnimatedHiddenStateUnhidden
} OAAnimatedHiddenState;


@interface NSView (OAAnimatedHidingSupport)
@property (nullable, nonatomic, retain) NSLayoutConstraint *constraintForOAAnimatedHidingSupport;
- (nullable NSLayoutConstraint *)prepareToOAAnimateToState:(OAAnimatedHiddenState)targetState orientation:(NSUserInterfaceLayoutOrientation)orientation;
- (void)cleanupAfterOOAnimatingWithConstraint:(NSLayoutConstraint *)constraint;
@end


@interface NSStackView (OAAnimatedViewHidingSupportPrivate)
// Seems like exposing this outside of OAAnimatedViewHidingSupport is noise / exposing an implementation detail that is unnecessary since nothing other than NSStackView(OAAnimatedSubviewHiding) needs it. OAConstraintBasedStackView doesn't need it and I don't really expect any other clients of OAAnimatedViewHidingSupport to materialize (indeed, eventually I would expect OAConstraintBasedStackView to disappear and OAAnimatedViewHidingSupport with it as it gets collapsed into OAAnimatedSubviewHiding), but if any do materialize and they need this, we can expose it at that time.
+ (NSLayoutConstraint *)_collapseConstraintForView:(NSView *)view orientation:(NSUserInterfaceLayoutOrientation)orientation constant:(CGFloat)constant;
@end


@implementation NSStackView (OAExtensions)

- (void)removeAllArrangedSubviews;
{
    NSArray *arrangedSubviews = [NSArray arrayWithArray:self.arrangedSubviews];
    for (NSView *view in arrangedSubviews) {
        [self removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

@end


@implementation NSStackView (OAAnimatedSubviewHiding)

- (void)setSubview:(NSView *)subview isHidden:(BOOL)shouldBeHidden animated:(BOOL)animated;
{
    [self setSubviews:[NSArray arrayWithObject:subview] areHidden:shouldBeHidden animated:animated];
}

- (void)setSubviews:(NSArray <NSView *> *)subviews areHidden:(BOOL)shouldBeHidden animated:(BOOL)animated;
{
    [NSStackView setViews:subviews areHidden:shouldBeHidden animated:animated byCollapsingOrientation:self.orientation completionBlock:^void (void) {
        [self _collapseCompletelyIfAllSubviewsAreHidden];
    }];
}

- (void)setHiddenSubviews:(NSArray <NSView *> *)hiddenSubviews animated:(BOOL)animated;
{
    [NSStackView setHiddenSubviews:hiddenSubviews ofView:self animated:animated byCollapsingOrientation:self.orientation completionBlock:^void (void) {
        [self _collapseCompletelyIfAllSubviewsAreHidden];
    }];
}

- (void)setUnhiddenSubviews:(NSArray <NSView *> *)unhiddenSubviews animated:(BOOL)animated;
{
    [NSStackView setUnhiddenSubviews:unhiddenSubviews ofView:self animated:animated byCollapsingOrientation:self.orientation completionBlock:^void (void) {
        [self _collapseCompletelyIfAllSubviewsAreHidden];
    }];
}

- (void)_collapseCompletelyIfAllSubviewsAreHidden;
{
    // If *all* subviews are hidden, the stack view is left without any internal force causing it to shrink, so it continues to take up whatever space it previously was occupying unless some external constraint forces it to collapse. If the subviews are hidden by animating them collapsed, then the stack view animates collapsed as well, though it doesn't make it all the way to zero for some reason. So when animating we want to ensure it's collapsed completely, and when not animating we want the same for parity. Note that if a client directly hides all the subviews, this behavior won't kick in.
    BOOL allSubviewsAreHidden = YES;
    for (NSView *subview in self.subviews) {
        if (!subview.hidden) {
            allSubviewsAreHidden = NO;
            break;
        }
    }
    if (allSubviewsAreHidden) {
        NSLayoutConstraint *constraint = [NSStackView _collapseConstraintForView:self orientation:self.orientation constant:0.0];
        if (constraint != nil) {
            [self.window layoutIfNeeded];
            constraint.active = NO;
        }
    }
}

@end


@implementation NSStackView (OAAnimatedViewHidingSupport)

#pragma mark -- OAAnimatedHidingSupport

+ (void)setViews:(nullable NSArray <NSView *> *)views areHidden:(BOOL)shouldBeHidden animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;
{
    NSArray *viewsToHide = (shouldBeHidden ? views : nil);
    NSArray *viewsToUnhide = (shouldBeHidden ? nil : views);
    [self hideViews:viewsToHide andUnhideViews:viewsToUnhide animated:animated byCollapsingOrientation:orientation completionBlock:completionBlock];
}

+ (void)setHiddenSubviews:(nullable NSArray <NSView *> *)hiddenSubviews ofView:(NSView *)parentView animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;
{
    NSMutableArray *subviewsToHide = [NSMutableArray array];
    NSMutableArray *subviewsToUnhide = [NSMutableArray array];
    
    if ([hiddenSubviews count] == 0) {
        [subviewsToUnhide addObjectsFromArray:parentView.subviews];
    } else {
        for (NSView *subview in parentView.subviews) {
            BOOL shouldBeHidden = ([hiddenSubviews indexOfObjectIdenticalTo:subview] != NSNotFound);
            if (shouldBeHidden) {
                [subviewsToHide addObject:subview];
            } else {
                [subviewsToUnhide addObject:subview];
            }
        }
    }
    
    [self hideViews:subviewsToHide andUnhideViews:subviewsToUnhide animated:animated byCollapsingOrientation:orientation completionBlock:completionBlock];
}

+ (void)setUnhiddenSubviews:(nullable NSArray <NSView *> *)unhiddenSubviews ofView:(NSView *)parentView animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;
{
    NSMutableArray *subviewsToHide = [NSMutableArray array];
    NSMutableArray *subviewsToUnhide = [NSMutableArray array];
    
    if ([unhiddenSubviews count] == 0) {
        [subviewsToHide addObjectsFromArray:parentView.subviews];
    } else {
        for (NSView *subview in parentView.subviews) {
            BOOL shouldBeUnhidden = ([unhiddenSubviews indexOfObjectIdenticalTo:subview] != NSNotFound);
            if (shouldBeUnhidden) {
                [subviewsToUnhide addObject:subview];
            } else {
                [subviewsToHide addObject:subview];
            }
        }
    }
    
    [self hideViews:subviewsToHide andUnhideViews:subviewsToUnhide animated:animated byCollapsingOrientation:orientation completionBlock:completionBlock];
}

+ (void)hideViews:(nullable NSArray <NSView *> *)viewsToHide andUnhideViews:(nullable NSArray <NSView *> *)viewsToUnhide animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;
{
    NSWindow *window = [[viewsToHide lastObject] window];
    if (window == nil) {
        window = [[viewsToUnhide lastObject] window];
    }
    
    if (animated) {
        if ((window == nil) || !window.visible) {
            animated = NO;
        }
    }
    
    if (!animated) {
        for (NSView *view in viewsToHide) {
            view.hidden = YES;
        }
        for (NSView *view in viewsToUnhide) {
            view.hidden = NO;
        }
        if (completionBlock != NULL) {
            completionBlock();
        }
        return;
    }
    
    NSMapTable *viewToTargetSizeMapTable = [NSMapTable weakToStrongObjectsMapTable];
    NSMutableArray *constraints = [NSMutableArray array];
    
    // We need to lock from before the constraints are setup to after they begin animating because that setup involves looking at any existing constraints to see if they should be left alone, revised, or discarded.
    NSLock *lock = [[NSLock alloc] init];
    [lock lock];
    
    @try {
        for (NSView *view in viewsToHide) {
            NSLayoutConstraint *constraint = [view prepareToOAAnimateToState:OAAnimatedHiddenStateHidden orientation:orientation];
            if (constraint != nil) {
                [constraints addObject:constraint];
            }
        }
        
        for (NSView *view in viewsToUnhide) {
            NSLayoutConstraint *constraint = [view prepareToOAAnimateToState:OAAnimatedHiddenStateUnhidden orientation:orientation];
            if (constraint != nil) {
                [constraints addObject:constraint];
                constraint.active = NO; // Temporarily disable the constraint so that looking up the view size get's its "natural" size
                CGFloat targetConstant = _viewSizeForOrientation(view, orientation);
                constraint.active = YES;
                [viewToTargetSizeMapTable setObject:[NSNumber numberWithDouble:targetConstant] forKey:view];
            }
        }
        
        if (constraints.count == 0) {
            return;
        }
        
        [window layoutIfNeeded];
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * context) {
            context.allowsImplicitAnimation = YES; // So the window frame change will animate
            context.duration = 0.15; // Per Bill, we want a slightly-faster-than-default animation (0.15)
            
            for (NSLayoutConstraint *constraint in constraints) {
                NSView *view = constraint.firstItem;
                NSNumber *targetSizeNumber = [viewToTargetSizeMapTable objectForKey:view];
                constraint.animator.constant = targetSizeNumber.doubleValue;
            }
            
        } completionHandler:^{
            for (NSLayoutConstraint *constraint in constraints) {
                NSView *view = constraint.firstItem;
                [view cleanupAfterOOAnimatingWithConstraint:constraint];
            }
            
            if (completionBlock != NULL) {
                completionBlock();
            }
        }];
    }
    @finally {
        [lock unlock];
    }
}

+ (NSLayoutConstraint *)_collapseConstraintForView:(NSView *)view orientation:(NSUserInterfaceLayoutOrientation)orientation constant:(CGFloat)constant;
{
    NSLayoutAttribute attribute = (orientation == NSUserInterfaceLayoutOrientationVertical) ? NSLayoutAttributeHeight : NSLayoutAttributeWidth;
    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:view attribute:attribute relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:0.0 constant:constant];
    constraint.active = YES;
    constraint.identifier = OAAnimatedHidingSupportConstraintIdentifier;
    
    return constraint;
}

@end


@implementation NSView (OAAnimatedHidingSupport)

- (nullable NSLayoutConstraint *)constraintForOAAnimatedHidingSupport;
{
    return objc_getAssociatedObject(self, &OAAnimatedHidingSupportConstraintIdentifier);
}

- (void)setConstraintForOAAnimatedHidingSupport:(nullable NSLayoutConstraint *)constraint;
{
    objc_setAssociatedObject(self, &OAAnimatedHidingSupportConstraintIdentifier, constraint, OBJC_ASSOCIATION_RETAIN);
}

- (OAAnimatedHiddenState)_currentActualOrInProgressOAAnimatedState;
{
    // Because of the race conditions noted below, you probably want to lock from before preparing for an animation to after actually initiating that animation.
    
    // Race condition: another thread may already have created a constraint but not yet assigned it
    NSLayoutConstraint *existingConstraint = self.constraintForOAAnimatedHidingSupport;
    if ((existingConstraint == nil) || !existingConstraint.active) {
        return (self.hidden ? OAAnimatedHiddenStateHidden : OAAnimatedHiddenStateUnhidden);
    }
    
    // Race condition: another animation/thread may have set up for an animation but not yet begun animating
    return (existingConstraint.animator.constant == 0.0 ? OAAnimatedHiddenStateHidden : OAAnimatedHiddenStateUnhidden);
}

- (nullable NSLayoutConstraint *)prepareToOAAnimateToState:(OAAnimatedHiddenState)targetState orientation:(NSUserInterfaceLayoutOrientation)orientation;
{
    if (targetState == self._currentActualOrInProgressOAAnimatedState) {
        return nil;
    }
    
    CGFloat startingConstant = 0.0;
    
    NSLayoutConstraint *existingConstraint = self.constraintForOAAnimatedHidingSupport;
    if (existingConstraint != nil) {
        OBASSERT(existingConstraint.active);
        startingConstant = existingConstraint.constant;
        existingConstraint.active = NO;
        self.constraintForOAAnimatedHidingSupport = nil;
        
    } else {
        startingConstant = (targetState == OAAnimatedHiddenStateHidden ? _viewSizeForOrientation(self, orientation) : 0.0);
    }
    
    NSLayoutConstraint *constraint = [NSStackView _collapseConstraintForView:self orientation:orientation constant:startingConstant];
    constraint.active = YES;
    
    self.constraintForOAAnimatedHidingSupport = constraint;
    self.hidden = NO;
    
    return constraint;
}

- (void)cleanupAfterOOAnimatingWithConstraint:(NSLayoutConstraint *)constraint;
{
    if (self.constraintForOAAnimatedHidingSupport == constraint) {
        self.constraintForOAAnimatedHidingSupport = nil;
        if (constraint.constant == constraint.animator.constant) { // Make sure we are no longer animating (it's possible a separate animation was started, reusing the same constraint)
            if (constraint.active && (constraint.constant == 0.0)) {
                self.hidden = YES;
            }
            constraint.active = NO;
        }
    }
}

@end


@implementation NSStackView (OACrossfadeSupport)

- (void)crossfadeAfterPerformingLayout:(OACrossfadeLayoutBlock)layoutBlock completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;
{
    /*
     If the new layout results in a change in size, the size change is animated by using temporary size constraints which can conflict with our internal constraints. To handle this possibility, before the animation we temporarily change our visibility priorities to allow the internal views to be dropped if necessary, then after the animation is complete we restore the original visibility priorities.
     */
    NSMapTable *visibilityPrioritiesByView = [NSMapTable weakToStrongObjectsMapTable];
    void (^preAnimationBlock)(void) = ^{
        for (NSView *view in self.views) {
            [visibilityPrioritiesByView setObject:[NSNumber numberWithFloat:[self visibilityPriorityForView:view]] forKey:view];
            [self setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible forView:view];
        }
    };
    void (^extendedCompletionBlock)(void) = ^{
        for (NSView *view in self.views) {
            NSNumber *visibilityPriority = [visibilityPrioritiesByView objectForKey:view];
            if (visibilityPriority != nil) {
                [self setVisibilityPriority:[visibilityPriority floatValue] forView:view];
            }
        }
        
        if (completionBlock != nil) {
            completionBlock();
        }
    };
    
    [NSView crossfadeView:self afterPerformingLayout:layoutBlock preAnimationBlock:preAnimationBlock completionBlock:extendedCompletionBlock];
}

@end

NS_ASSUME_NONNULL_END
