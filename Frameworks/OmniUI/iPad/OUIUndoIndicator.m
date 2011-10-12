// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoIndicator.h>

RCS_ID("$Id$");

@interface OUIUndoIndicatorView : UIView
- (void)bounce;
@end

@interface OUIUndoIndicator ()
- (void)_update;
@end

@implementation OUIUndoIndicator
{
@private
    UIView *_parentView;
    NSUInteger _groupingLevel;
    BOOL _hasUnsavedChanges;
}

- initWithParentView:(UIView *)parentView;
{
    OBPRECONDITION(parentView);
    
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    _parentView = [parentView retain];

    return self;
}

- (void)dealloc;
{
    [_parentView release];
    [super dealloc];
}

@synthesize groupingLevel = _groupingLevel;
- (void)setGroupingLevel:(NSUInteger)groupingLevel;
{
    if (_groupingLevel == groupingLevel)
        return;

    _groupingLevel = groupingLevel;
    [self _update];
}

@synthesize hasUnsavedChanges = _hasUnsavedChanges;
- (void)setHasUnsavedChanges:(BOOL)hasUnsavedChanges;
{
    if (_hasUnsavedChanges == hasUnsavedChanges)
        return;
    
    _hasUnsavedChanges = hasUnsavedChanges;
    [self _update];
}

- (void)_update;
{
    if (_groupingLevel > 0 || _hasUnsavedChanges) {
        OUIUndoIndicatorView *view = (OUIUndoIndicatorView *)self.view;
        if (view.superview != _parentView)
            [_parentView addSubview:view];
        
        if (_hasUnsavedChanges)
            view.backgroundColor = [UIColor redColor];
        else
            view.backgroundColor = [UIColor greenColor];
        
        CGFloat size = 20 + 10*_groupingLevel;
        view.frame = CGRectMake(0, 0, size, size);
    } else if ([self isViewLoaded]) {
        OUIUndoIndicatorView *view = (OUIUndoIndicatorView *)self.view;
        if (view.superview)
            [view removeFromSuperview];
    }
}

#pragma mark -
#pragma mark UIViewController

- (void)loadView;
{
    OUIUndoIndicatorView *view = [[OUIUndoIndicatorView alloc] init];
    view.layer.zPosition = CGFLOAT_MAX;
    self.view = view;
    [view release];
}

@end

@implementation OUIUndoIndicatorView

- (void)bounce;
{
    CGAffineTransform xform = CGAffineTransformIdentity;
    xform = CGAffineTransformScale(xform, 2, 2);
    
    CALayer *layer = self.layer;
    
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform"];
    anim.fromValue = [NSValue valueWithCATransform3D:layer.transform];
    anim.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(xform)];
    anim.removedOnCompletion = YES;
    anim.cumulative = YES;
    anim.autoreverses = YES;
    
    [layer addAnimation:anim forKey:[[NSDate date] description]]; // stack these up to allow them to assumulate
}

@end
