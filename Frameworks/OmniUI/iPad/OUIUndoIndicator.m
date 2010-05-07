// Copyright 2010 The Omni Group.  All rights reserved.
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

@implementation OUIUndoIndicator

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

- (void)show;
{
    OBPRECONDITION([_parentView window]);
    
    OUIUndoIndicatorView *view = (OUIUndoIndicatorView *)self.view;
    if (view.superview != _parentView)
        [_parentView addSubview:view];
    [view bounce];
}

- (void)hide;
{
    if ([self isViewLoaded])
        [self.view removeFromSuperview];
}

#pragma mark -
#pragma mark UIViewController

- (void)loadView;
{
    OUIUndoIndicatorView *view = [[OUIUndoIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
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

- (void)drawRect:(CGRect)r;
{
    [[UIColor greenColor] set];
    UIRectFill(self.bounds);
}

@end
