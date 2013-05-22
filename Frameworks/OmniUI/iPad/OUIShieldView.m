// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIShieldView.h>

RCS_ID("$Id$");

@implementation OUIShieldView

@synthesize passthroughViews = _passthroughViews;

#pragma mark -
#pragma mark Class Methods
+ (OUIShieldView *)shieldViewWithView:(UIView *)view;
{
    OUIShieldView *shieldView = [[[OUIShieldView alloc] initWithFrame:view.bounds] autorelease];
    shieldView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    OBASSERT(view.autoresizesSubviews);
    
    return shieldView;
}

#pragma mark -
#pragma mark Public

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

#pragma mark -
#pragma mark NSObject
- (void)dealloc;
{
    [_passthroughViews release];
    
    [super dealloc];
}
@end
