// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
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

- (void)setUseBlur:(BOOL)useBlur
{
    if (useBlur != _useBlur) {
        if (useBlur) {
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
            blurView.frame = self.bounds;
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self addSubview:blurView];
            OBASSERT(self.autoresizesSubviews);
        }
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    if (self.shouldForwardAllEvents) {
        if ([super hitTest:point withEvent:event]) {
            // Someplace inside of me did get hit. Let the delegate know, but return nil;
            id<OUIShieldViewDelegate> delegate = _delegate;
            if (delegate && [delegate respondsToSelector:@selector(shieldViewWasTouched:)]) {
                [delegate shieldViewWasTouched:self];
            }
        }
        
        // If we're forwarding all events, we don't care about the passthrough views below. Just return nil and let the event be forwarded.
        return nil;
    }
    else {
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
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    // We capture all touches sent to us, and if they complete successfully we inform the delegate so it can dismiss us.
    id<OUIShieldViewDelegate> delegate = _delegate;
    if (delegate && [delegate respondsToSelector:@selector(shieldViewWasTouched:)])
        [delegate shieldViewWasTouched:self];
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
