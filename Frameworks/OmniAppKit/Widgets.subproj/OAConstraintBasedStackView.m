// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAConstraintBasedStackView.h>

RCS_ID("$Id$")


NS_ASSUME_NONNULL_BEGIN

@interface OAConstraintBasedStackView ()
@property (nullable, nonatomic, copy) NSArray *stackConstraints;
@property (nonatomic, retain) NSMutableArray *orderedSubviews;
@end


static void *CBSVHiddenSubviewContext;
static NSString * const CBSVHiddenSubviewProperty = @"hidden";


@implementation OAConstraintBasedStackView

static void _commonInit(OAConstraintBasedStackView *self)
{
    self.orderedSubviews = [[NSMutableArray alloc] init];
    self.translatesAutoresizingMaskIntoConstraints = NO;
}

- (instancetype)initWithFrame:(NSRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    _commonInit(self);

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    _commonInit(self);
    
    return self;
}

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    // If we were initialized with initWithCoder: we won't yet have built our list of orderedSubviews and will need to do so now. (Yes, it's possible that we simply don't have any subviews, but that's unlikely, and if it's true this is inexpensive anyway.)
    if (self.orderedSubviews.count == 0) {
        for (NSView *subview in self.subviews) {
            [self _addToOrderedSubviewsAtAppropriateIndex:subview];
        }
    }
}

#pragma mark -- OAAnimatedSubviewHiding

- (void)setSubview:(NSView *)subview isHidden:(BOOL)shouldBeHidden animated:(BOOL)animated;
{
    [self setSubviews:[NSArray arrayWithObject:subview] areHidden:shouldBeHidden animated:animated];
}

- (void)setSubviews:(NSArray <NSView *> *)subviews areHidden:(BOOL)shouldBeHidden animated:(BOOL)animated;
{
    if (self.hidden) {
        animated = NO;
    }
    [NSStackView setViews:subviews areHidden:shouldBeHidden animated:animated byCollapsingOrientation:NSUserInterfaceLayoutOrientationVertical completionBlock:NULL];
}

- (void)setHiddenSubviews:(NSArray <NSView *> *)hiddenSubviews animated:(BOOL)animated;
{
    if (self.hidden) {
        animated = NO;
    }
    [NSStackView setHiddenSubviews:hiddenSubviews ofView:self animated:animated byCollapsingOrientation:NSUserInterfaceLayoutOrientationVertical completionBlock:NULL];
}

- (void)setUnhiddenSubviews:(NSArray <NSView *> *)unhiddenSubviews animated:(BOOL)animated;
{
    if (self.hidden) {
        animated = NO;
    }
    [NSStackView setUnhiddenSubviews:unhiddenSubviews ofView:self animated:animated byCollapsingOrientation:NSUserInterfaceLayoutOrientationVertical completionBlock:NULL];
}

#pragma mark -- Crossfading

- (void)crossfadeToViews:(NSArray <NSView *> *)views completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;
{
    [self crossfadeAfterPerformingLayout:^{
        self.arrangedSubviews = views;
    } completionBlock:completionBlock];
}

- (void)crossfadeAfterPerformingLayout:(OACrossfadeLayoutBlock)layoutBlock completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;
{
    [NSView crossfadeView:self afterPerformingLayout:layoutBlock preAnimationBlock:nil completionBlock:completionBlock];
}

#pragma mark -- NSView subclass

- (BOOL)isFlipped;
{
    return YES;
}

- (void)updateConstraints;
{
    OBPRECONDITION(!self.translatesAutoresizingMaskIntoConstraints);

    NSMutableArray *stackConstraints = [NSMutableArray array];
    NSView *lastView = nil;
    NSDictionary *metrics = @{
        @"left" : @(0.0),
        @"right" : @(0.0),
        @"vspace" : @(0.0),
        @"priority" : @(750.0),
    };
    for (NSView *subview in self.orderedSubviews) {
        OBASSERT(subview.superview == self);
        if (subview.isHidden)
            continue; // Skip hidden views

        [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-left-[subview]-right-|" options:0 metrics:metrics views:NSDictionaryOfVariableBindings(subview)]];

        if (lastView == nil)
            [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-vspace@priority-[subview]" options:0 metrics:metrics views:NSDictionaryOfVariableBindings(subview)]];
        else
            [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[lastView]-vspace@priority-[subview]" options:0 metrics:metrics views:NSDictionaryOfVariableBindings(lastView, subview)]];
        lastView = subview;
    }
    if (lastView != nil)
        [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[lastView]-vspace@priority-|" options:0 metrics:metrics views:NSDictionaryOfVariableBindings(lastView)]];

    self.stackConstraints = stackConstraints;

    [super updateConstraints];
}

- (void)_updateFramesOfOrderedSubviews;
{
    OBASSERT([self isFlipped]);
    CGFloat yOffset = 0.0;
    for (NSView *view in self.orderedSubviews) {
        NSRect frame = view.frame;
        frame.origin.y = yOffset;
        view.frame = frame;
        yOffset = NSMaxY(frame);
    }
}

- (void)_didAddToOrderedSubviews:(NSView *)subview;
{
    [subview addObserver:self forKeyPath:CBSVHiddenSubviewProperty options:NSKeyValueObservingOptionNew context:&CBSVHiddenSubviewContext];
    [self _setNeedsReload];
}

- (void)_didRemoveFromOrderedSubviews:(NSView *)subview;
{
    [subview removeObserver:self forKeyPath:CBSVHiddenSubviewProperty context:&CBSVHiddenSubviewContext];
    [self _setNeedsReload];
}

- (void)_addToOrderedSubviewsAtAppropriateIndex:(NSView *)subview;
{
    NSMutableArray *orderedSubviews = self.orderedSubviews;
    [orderedSubviews insertObject:subview inArraySortedUsingComparator:^NSComparisonResult(NSView *view1, NSView *view2) {
        CGFloat y1 = view1.frame.origin.y;
        CGFloat y2 = view2.frame.origin.y;
        if (y1 > y2)
            return NSOrderedAscending;
        else if (y1 < y2)
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    }];
    [self _didAddToOrderedSubviews:subview];
}

- (void)didAddSubview:(NSView *)subview;
{
    [super didAddSubview:subview];
    if ([self.orderedSubviews indexOfObjectIdenticalTo:subview] == NSNotFound) {
        [self _addToOrderedSubviewsAtAppropriateIndex:subview];
    }
}

- (void)willRemoveSubview:(NSView *)subview;
{
    [self.orderedSubviews removeObjectIdenticalTo:subview];
    [self _didRemoveFromOrderedSubviews:subview];
    [super willRemoveSubview:subview];
}

#pragma mark - NSObject subclass

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSString*, id> *)change context:(nullable void *)context;
{
    if (context == &CBSVHiddenSubviewContext) {
        [self _setNeedsReload];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Properties

- (void)setStackConstraints:(nullable NSArray <NSLayoutConstraint *> *)stackConstraints;
{
    if (OFISEQUAL(_stackConstraints, stackConstraints))
        return;

    if (_stackConstraints != nil) {
        [NSLayoutConstraint deactivateConstraints:_stackConstraints];
    }
    _stackConstraints = [stackConstraints copy];
    if (stackConstraints != nil) {
        [self _updateFramesOfOrderedSubviews];
        [NSLayoutConstraint activateConstraints:stackConstraints];
    }
}


#pragma mark - Private

- (void)_setNeedsReload;
{
    self.stackConstraints = nil;
    [self setNeedsUpdateConstraints:YES];
}

@end


@implementation OAConstraintBasedStackView (OAConstraintBasedStackViewArrangedSubviews)

- (void)setArrangedSubviews:(NSArray<__kindof NSView *> *)newValue;
{
    NSArray *subviews = [self.subviews copy];
    for (NSView *subview in subviews) {
        [self removeArrangedSubview:subview];
    }
    for (NSView *subview in newValue) {
        subview.translatesAutoresizingMaskIntoConstraints = NO;
        [self addArrangedSubview:subview];
    }
}

- (NSArray<__kindof NSView *> *)arrangedSubviews;
{
    return [NSArray arrayWithArray:self.orderedSubviews];
}

- (void)addArrangedSubview:(NSView *)view;
{
    OBPRECONDITION([self.orderedSubviews indexOfObjectIdenticalTo:view] == NSNotFound);
    OBPRECONDITION(view.superview != self);
    [self.orderedSubviews addObject:view]; // Append to orderedSubviews so it will end up on the bottom
    [self _didAddToOrderedSubviews:view];
    [self addSubview:view];
}

// This API is copied from NSStackView API - dunno why they used NSInteger instead of NSUInteger for the insertion index
- (void)insertArrangedSubview:(NSView *)view atIndex:(NSInteger)insertionIndex;
{
    NSUInteger oldIndex = [self.orderedSubviews indexOfObjectIdenticalTo:view];
    if (oldIndex != (NSUInteger)insertionIndex) { // Optimization: && (oldIndex != (NSUInteger)(insertionIndex + 1))
        [self.orderedSubviews insertObject:view atIndex:(NSUInteger)insertionIndex];
        if (oldIndex == NSNotFound) {
            OBPRECONDITION(view.superview != self);
            [self _didAddToOrderedSubviews:view];
            [self addSubview:view];
        } else {
            OBPRECONDITION(view.superview == self);
            [self.orderedSubviews removeObjectAtIndex:oldIndex];
            [self _setNeedsReload];
        }
    }
}

- (void)removeArrangedSubview:(NSView *)view;
{
    OBASSERT(view.superview == self);
    [view removeFromSuperview]; // The view will be removed from orderedSubviews in -willRemoveSubview
}

@end

NS_ASSUME_NONNULL_END
