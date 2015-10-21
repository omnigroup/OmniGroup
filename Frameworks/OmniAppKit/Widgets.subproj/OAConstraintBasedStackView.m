// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAConstraintBasedStackView.h"

RCS_ID("$Id$")

@interface OAConstraintBasedStackView ()
@property (nonatomic, copy) NSArray *stackConstraints;
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
            [self _addToOrderedSubviews:subview];
        }
    }
}

//
// NSView subclass
//

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
        @"priority" : @(250.0),
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

- (void)_addToOrderedSubviews:(NSView *)subview;
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
    [subview addObserver:self forKeyPath:CBSVHiddenSubviewProperty options:NSKeyValueObservingOptionNew context:&CBSVHiddenSubviewContext];
    [self _setNeedsReload];
}

- (void)didAddSubview:(NSView *)subview;
{
    [super didAddSubview:subview];
    [self _addToOrderedSubviews:subview];
}

- (void)willRemoveSubview:(NSView *)subview;
{
    [subview removeObserver:self forKeyPath:CBSVHiddenSubviewProperty context:&CBSVHiddenSubviewContext];
    [self.orderedSubviews removeObjectIdenticalTo:subview];
    [super willRemoveSubview:subview];
    [self _setNeedsReload];
}

#pragma mark - NSObject subclass

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &CBSVHiddenSubviewContext) {
        [self _setNeedsReload];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Properties

- (void)setStackConstraints:(NSArray *)stackConstraints;
{
    if (OFISEQUAL(_stackConstraints, stackConstraints))
        return;

    if (_stackConstraints != nil) {
        [NSLayoutConstraint deactivateConstraints:_stackConstraints];
    }
    _stackConstraints = [stackConstraints copy];
    if (stackConstraints != nil) {
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
