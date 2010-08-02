// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "LayerShadowPathDemo.h"

#import <QuartzCore/QuartzCore.h>

RCS_ID("$Id$")

@implementation LayerShadowPathDemo

- (NSString *)name;
{
    return @"CALayer, shadow path";
}

// Preserve the same path for the sliding case.
static CGPathRef _createPathForRect(LayerShadowPathDemo *self, CGRect rect)
{
    if (!self->_path || !CGRectEqualToRect(self->_pathRect, rect)) {
        if (self->_path)
            CFRelease(self->_path);
        self->_pathRect = rect;
        
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL/*transform*/, rect);
        self->_path = CGPathCreateCopy(path);
        CFRelease(path);
    }
    
    return CFRetain(self->_path);
}

- (void)setFrame:(CGRect)frame;
{
    CGRect oldBounds = self.bounds;
    
    [super setFrame:frame];
    
    // Don't needlessly animate, but do make sure shadowPath gets set so we don't animate using the non-path renderer
    if (CGRectEqualToRect(oldBounds, self.bounds)) {
        CGPathRef path = _createPathForRect(self, self.bounds);
        
        self.layer.shadowPath = path;
        
        CFRelease(path);
        return;
    }
    
    CGMutablePathRef newShadowPath = CGPathCreateMutable();
    CGPathAddRect(newShadowPath, NULL/*transform*/, self.bounds);

    if (_usingTimer) {
        // Since we are supposedly user-event driven, we'd want to disable the implicit animation here. But, UIView already disables it, which is the point of the 'else'!
        self.layer.shadowPath = newShadowPath;
    } else {
        // If we just set the shadowPath, UIView's -actionForLayer:forKey: returns an NSNull, disabling the animation.
        CABasicAnimation *shadowAnimation = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
        
        CGMutablePathRef oldShadowPath = CGPathCreateMutable();
        CGPathAddRect(oldShadowPath, NULL/*transform*/, oldBounds);
        shadowAnimation.fromValue = (id)oldShadowPath;
        CFRelease(oldShadowPath);
        
        shadowAnimation.toValue = (id)newShadowPath;
        
        shadowAnimation.duration = 1;
        shadowAnimation.autoreverses = YES;
        shadowAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        
        [self.layer addAnimation:shadowAnimation forKey:@"shadowPath"];
    }

    CFRelease(newShadowPath);
}

@end
