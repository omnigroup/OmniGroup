// Copyright 2009-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQFlipSwapViewAnimation.h>

#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQHoleLayer.h>

RCS_ID("$Id$");

static NSString * const OQFlipSwapViewAnimationName = @"OQFlipSwapViewAnimation";

@implementation OQFlipSwapViewAnimation
{
    CALayer *_targetLayer;
    NSWindow *_window;
}

static NSImage *_imageForView(NSView *view)
{
    OBPRECONDITION(view.wantsLayer);
    OBPRECONDITION(view.layer);
    
    NSImage *image;
    NSRect bounds = view.bounds;
    CALayer *layer;
    if ((layer = view.layer))
        image = [layer imageForRect:bounds useAnimatedValues:YES];
    else {
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:bounds];
        OBASSERT(bitmap);
        image = [[[NSImage alloc] initWithSize:bounds.size] autorelease];
        [image addRepresentation:bitmap];
    }
        
    OBASSERT(image);
    return image;
}

static CGFloat _degToRad(CGFloat deg)
{
    return (CGFloat)(deg * (2.0 * M_PI / 360.0));
}

static void _addFlip(CALayer *parentLayer, NSRect layerViewRect, NSImage *image, CGFloat fromAngle, CGFloat toAngle, CGFloat aboutX)
{
    CATransform3D fromTransform = CATransform3DMakeRotation(_degToRad(fromAngle), aboutX, 0, 0);
    CATransform3D toTransform = CATransform3DMakeRotation(_degToRad(toAngle), aboutX, 0, 0);
    
    CALayer *flipLayer = [CALayer layer];
    flipLayer.anchorPoint = NSMakePoint(0.5f, 0.5f);
    flipLayer.frame = layerViewRect;
    flipLayer.contents = image;
    flipLayer.doubleSided = NO;
    flipLayer.transform = fromTransform;
    
    CABasicAnimation *flipAnimation = [CABasicAnimation animationWithKeyPath:@"transform"];
    flipAnimation.removedOnCompletion = NO;
    flipAnimation.fillMode = kCAFillModeBoth;
    flipAnimation.timingFunction = [CAMediaTimingFunction functionCompatibleWithDefault];
    flipAnimation.fromValue = [NSValue valueWithCATransform3D:fromTransform];
    flipAnimation.toValue = [NSValue valueWithCATransform3D:toTransform];
    flipAnimation.duration = [CATransaction animationDuration];
    
    [flipLayer addAnimation:flipAnimation forKey:@"flip"];
    [parentLayer addSublayer:flipLayer];
}

+ (void)replaceView:(NSView *)oldView withView:(NSView *)newView setFirstResponder:(NSResponder *)newFirstResponder;
{
    NSView *parentView = [oldView superview];
    if (!parentView) {
        OBASSERT_NOT_REACHED("No parent view");
        return;
    }
    
    // Change the size no matter whether we animate or not.
    NSRect viewFrame = oldView.frame;
    newView.frame = viewFrame;
    
    // No animation in in bundle of cases.
    NSWindow *parentWindow = [parentView window];
    CALayer *parentLayer = parentView.layer;
    if (!parentWindow || ![parentWindow isVisible] || !parentLayer || [CATransaction disableActions]) {
        [parentView replaceSubview:oldView with:newView];
        return;
    }
    
    NSRect viewScreenRect = [parentView convertRect:viewFrame toView:nil];
    viewScreenRect = [parentWindow convertRectToScreen:viewScreenRect];
    //NSLog(@"viewScreenRect = %@", NSStringFromRect(viewScreenRect));
    
    // TODO: Actual math re: perepective warp on near edge.
    NSRect windowRect = NSInsetRect(viewScreenRect, -16, -16);
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect styleMask:NSWindowStyleMaskBorderless backing:[parentWindow backingType] defer:NO];
    [window setReleasedWhenClosed:NO]; // The instance will own it.
    [window setLevel:[parentWindow level] + 1]; // This makes us not participate in spaces/expose and window order by default
    [window setIgnoresMouseEvents:YES];
    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor clearColor]];
    
    NSView *contentView = [window contentView];
    contentView.layer = [CALayer layer];
    contentView.wantsLayer = YES;
    //contentView.layer.backgroundColor = CGColorCreateGenericRGB(0.5, 0.5, 0.75, 0.5);

    // Compute the rect w/in our window that covers the view to be replaced
    NSRect layerViewRect = viewScreenRect;
    layerViewRect = [window convertRectFromScreen:layerViewRect];
    
    [CATransaction begin];
    
    if ([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSEventModifierFlagShift)
        [CATransaction setAnimationDuration:2.0];
    
    [CATransaction setDisableActions:YES];
    
    // Put an opaque hole layer w/in the window covering exactly the area we are replacing.
    {
        OQHoleLayer *hole = [OQHoleLayer layer];
        hole.frame = layerViewRect;
        [contentView.layer addSublayer:hole];
    }
    
    // Add a layer with a (hokey) perspective transform applied as the content view's sublayer transform.
    // Need this to keep the hole from flipping with us.
    CALayer *perspectiveLayer;
    {
        perspectiveLayer = [CALayer layer];
        perspectiveLayer.anchorPoint = CGPointMake(0.5f, 0.5f);
        perspectiveLayer.zPosition = 1; // Put it above the hole
        perspectiveLayer.frame = NSMakeRect(0, 0, layerViewRect.size.width, layerViewRect.size.height);
        
        CATransform3D P = CATransform3DIdentity;
        P.m34 = 1.0f/-200.f;
        perspectiveLayer.sublayerTransform = P;
        [contentView.layer addSublayer:perspectiveLayer];
    }
    
    // Add two layers that have snapshots of the old/new views and set up a flip on them.
    {
        NSImage *oldImage = _imageForView(oldView);

        // Do the replace and _then_ capture the image, else the view might not have a layer and might not draw right (or at all)
        [parentView replaceSubview:oldView with:newView];
        NSImage *newImage = _imageForView(newView);
        
        _addFlip(perspectiveLayer, layerViewRect, oldImage, 0.0f, -179.9f, 1.0f);
        _addFlip(perspectiveLayer, layerViewRect, newImage, 180.0f, 0.1f, 1.0f);
    }

    OQFlipSwapViewAnimation *animation = [[self alloc] init];
    animation->_window = window;
    animation->_targetLayer = [parentLayer retain];
    
    animation.fromValue = [NSNumber numberWithFloat:0.0f];
    animation.toValue = [NSNumber numberWithFloat:1.0f];
    animation.removedOnCompletion = NO;
    animation.fillMode = kCAFillModeForwards;
    animation.timingFunction = [CAMediaTimingFunction functionCompatibleWithDefault];
    animation.delegate = (id <CAAnimationDelegate>)self;
    animation.duration = [CATransaction animationDuration];
    
    OBASSERT(parentLayer);
    OBASSERT([parentLayer animationForKey:OQFlipSwapViewAnimationName] == nil);
    [parentLayer addAnimation:animation forKey:OQFlipSwapViewAnimationName];
    OBASSERT([parentLayer animationForKey:OQFlipSwapViewAnimationName] == animation);
    [animation release];

    [CATransaction commit];

    [window display]; // off screen
    [parentWindow addChildWindow:window ordered:NSWindowAbove];
}

- (void)dealloc;
{
    [_targetLayer release];
    [_window release];
    [super dealloc];
}

#pragma mark CALayer delegate

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;
{
    CGColorRef color = CGColorCreateGenericRGB(0.5f, 0.5f, 1.0f, 0.75f);
    CGContextSetFillColorWithColor(ctx, color);
    CFRelease(color);
    
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextFillRect(ctx, layer.bounds);
}

#pragma mark CAAnimation delegate

+ (void)animationDidStop:(CAAnimation *)_anim finished:(BOOL)flag;
{
    OBPRECONDITION([_anim isKindOfClass:self]);
    OQFlipSwapViewAnimation *anim = (OQFlipSwapViewAnimation *)_anim;
    
    //NSLog(@"stopped %@ finished: %d", [anim shortDescription], flag);
    
    // We set the animation to not be removed
    OBASSERT([anim->_targetLayer animationForKey:OQFlipSwapViewAnimationName] == anim);
    [anim->_targetLayer removeAnimationForKey:OQFlipSwapViewAnimationName];
    
    [[anim->_window parentWindow] removeChildWindow:anim->_window];
    [anim->_window orderOut:nil];
}

#pragma mark -
#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    // We consider ourselves immutable after being first set up.  Anyone else shouldn't muck with us either.
    // This is necessary since -addAnimation:forKey: copies the animation (or we could implement this method for real to deal with our ivars.
    return [self retain];
}

@end
