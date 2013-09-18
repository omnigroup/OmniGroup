// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIShieldView.h>

RCS_ID("$Id$");

@implementation OUIShieldView

+ (OUIShieldView *)shieldViewWithView:(UIView *)view;
{
    OUIShieldView *shieldView = [[OUIShieldView alloc] initWithFrame:view.bounds];
    shieldView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    OBASSERT(view.autoresizesSubviews);
    
    return shieldView;
}

#pragma mark - UIView subclass

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hitView = nil;
    
    // Check passthrough views.
    for (UIView *passthrough in self.passthroughViews) {
        hitView = [passthrough hitTest:[self convertPoint:point toView:passthrough] withEvent:event];
        if (hitView) {
            return hitView;
        }
    }
        
    // Check super.
    return [super hitTest:point withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    // We capture all touches sent to us, and if they complete successfully we inform the delegate so it can dismiss us.
    
    if (_delegate && [_delegate respondsToSelector:@selector(shieldViewWasTouched:)])
        [_delegate shieldViewWasTouched:self];
}

// Per the documentation, these implementations must exist. We want them anyway so we don't forward touch events up the responder chain.
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
}

@end
