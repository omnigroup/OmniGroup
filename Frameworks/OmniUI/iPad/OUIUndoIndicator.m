// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoIndicator.h>

RCS_ID("$Id$");

static OUIUndoIndicator *_sharedIndicator;

@interface OUIUndoIndicatorView : UIView
- (void)bounce;
@end

@implementation OUIUndoIndicator
{
    CALayer *_indicatorDot;
    CALayer *_accumulatingDot;
}

+ (OUIUndoIndicator *)sharedIndicator {
    if (!_sharedIndicator) {
        _sharedIndicator = [[OUIUndoIndicator alloc] init];
    }
    return _sharedIndicator;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    return self;
}

- (void)setGroupingLevel:(NSUInteger)groupingLevel;
{
    if (_groupingLevel == groupingLevel)
        return;

    _groupingLevel = groupingLevel;
    [self _update];
}

- (void)setHasUnsavedChanges:(BOOL)hasUnsavedChanges;
{
    if (_hasUnsavedChanges == hasUnsavedChanges)
        return;
    
    _hasUnsavedChanges = hasUnsavedChanges;
    [self _update];
}

- (void)setUndoIsEnabled:(BOOL)undoIsEnabled
{
    if (_undoIsEnabled == undoIsEnabled) {
        return;
    }
    
    _undoIsEnabled = undoIsEnabled;
    [self _update];
}

- (void)setAccumulatingGraphicsChanges:(BOOL)isAccumulating {
    if (_accumulatingGraphicsChanges == isAccumulating) {
        return;
    }
    
    _accumulatingGraphicsChanges = isAccumulating;
    [self _update];
}

- (void)_update;
{
    OUIUndoIndicatorView *view = (OUIUndoIndicatorView *)self.view;
    UIView *parentView = _parentView;
    if (view.superview != parentView){
        [parentView addSubview:view];
        view.frame = CGRectMake(0, self.frameYOffset, 50, 50);
    }
    
    // grouping level controls size and color of the indicator dot
    if (_groupingLevel > 0){
        CGFloat size = 20 + 10*_groupingLevel;
        _indicatorDot.frame = CGRectMake((view.frame.size.width - size)/2, (view.frame.size.height - size)/2, size, size);
        _indicatorDot.cornerRadius = size/2;
        _indicatorDot.backgroundColor = [UIColor redColor].CGColor;
    } else {
        _indicatorDot.backgroundColor = [UIColor greenColor].CGColor;
    }
    
    // _hasUnsavedChanges puts a red border around the whole view
    view.layer.borderWidth = 2;
    if (_hasUnsavedChanges)
        view.layer.borderColor = [UIColor redColor].CGColor;
    else
        view.layer.borderColor = [UIColor darkGrayColor].CGColor;
    
    // if the undo manager is disabled, the background of the view should be grey
    if (_undoIsEnabled) {
        view.backgroundColor = [UIColor clearColor];
    } else {
        view.backgroundColor = [UIColor darkGrayColor];
    }
    
    if (_accumulatingGraphicsChanges) {
        _accumulatingDot.backgroundColor = [UIColor redColor].CGColor;
    } else {
        _accumulatingDot.backgroundColor = [UIColor greenColor].CGColor;
    }
}

#pragma mark - UIViewController

- (void)loadView;
{
    OUIUndoIndicatorView *view = [[OUIUndoIndicatorView alloc] init];
    view.userInteractionEnabled = NO; // Allow clicking through it.
    view.layer.zPosition = FLT_MAX;
    self.view = view;
    _indicatorDot = [CALayer layer];
    _accumulatingDot = [CALayer layer];
    _accumulatingDot.frame = CGRectMake(0, 0, 15, 15);
    _accumulatingDot.cornerRadius = 15.0/2.0;
    [self.view.layer addSublayer:_indicatorDot];
    [self.view.layer addSublayer:_accumulatingDot];
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
