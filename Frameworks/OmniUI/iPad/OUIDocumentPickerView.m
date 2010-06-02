// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPickerView.h>

#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIDocumentProxyView.h>
#import <OmniUI/OUIToolbarViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import "OUIDocumentProxy-Internal.h"
#import "OUIDocumentPreview.h"

RCS_ID("$Id$");

NSString * const OUIDocumentPickerViewProxiesBinding = @"proxies";

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_SCROLL(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_SCROLL(format, ...)
#endif

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_LAYOUT(format, ...) NSLog(@"DOC LAYOUT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_LAYOUT(format, ...)
#endif

#define USE_CUSTOM_SCROLLING 1

@interface OUIDocumentPickerView (/*Private*/)
@end

@implementation OUIDocumentPickerView

static id _commonInit(OUIDocumentPickerView *self)
{
//    self.pagingEnabled = YES; // stop on multiples of view bounds
        
#if USE_CUSTOM_SCROLLING
    self.scrollEnabled = NO; // This sets enabled=NO on the built-in recognizers, but doesn't remove them.
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePickerPanGesture:)];
    [self addGestureRecognizer:pan];
    [pan release];
#endif
    
    self.showsVerticalScrollIndicator = NO;
    self.showsHorizontalScrollIndicator = YES;
    
    // Create six proxy views. One for the center, two for the nearest neighbors (on screen), two for speculatively loaded views past those neighbors and one for a potential duplicate being animated in.
    NSMutableArray *proxyViews = [NSMutableArray array];
    NSUInteger viewCount = 6;
    while (viewCount--) {
        OUIDocumentProxyView *view = [[OUIDocumentProxyView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        view.hidden = YES;
        [self addSubview:view];
        [proxyViews addObject:view];
        [view release];
    }
    self->_proxyViews = [[NSArray alloc] initWithArray:proxyViews];
    
    return self;
}

static const CGFloat kMinimumVelocityToStartDeceleration = 15;

static CGPoint _contentOffsetForCenteringProxy(OUIDocumentPickerView *self, OUIDocumentProxy *proxy)
{
    OBPRECONDITION(proxy);
    
    CGRect proxyFrame = proxy.frame;
    return CGPointMake(floor(CGRectGetMidX(proxyFrame) - self.bounds.size.width / 2), 0);
}

static void _cancelSmoothScroll(OUIDocumentPickerViewSmoothScroll *ss)
{
    [ss->timer invalidate];
    [ss->timer release];    
    memset(ss, 0, sizeof(*ss));
}

// The built-in scrolling support doesn't clamp.  Instead, as you pull further past the end, you get less and less return for your effort. Eventually you hit the edge of the screen and the snapback starts.

// TODO: Show scrollers while panning

static CGPoint _handleOverpull(OUIDocumentPickerView *self, CGPoint desiredOffset)
{
    if ([self->_sortedProxies count] == 0)
        return CGPointZero;
    
    const CGFloat kOverpullDampenPower = 0.8;

    CGFloat leftLimit = _contentOffsetForCenteringProxy(self, self.firstProxy).x;
    if (desiredOffset.x < leftLimit) {
        CGFloat overpull = leftLimit - desiredOffset.x;
        CGFloat dampened = pow(overpull, kOverpullDampenPower);
        
        return CGPointMake(floor(desiredOffset.x + dampened), desiredOffset.y);
    }

    CGFloat rightLimit = _contentOffsetForCenteringProxy(self, self.lastProxy).x;
    if (desiredOffset.x > rightLimit) {
        CGFloat overpull = desiredOffset.x - rightLimit;
        CGFloat dampened = pow(overpull, kOverpullDampenPower);
        
        return CGPointMake(floor(desiredOffset.x - dampened), desiredOffset.y);
    }

    return desiredOffset;
}

static BOOL _shouldConstrainOffsetToScrollLimits(OUIDocumentPickerView *self, CGFloat xOffset, CGPoint *outLimitPoint)
{    
    CGPoint leftOffset = _contentOffsetForCenteringProxy(self, self.firstProxy);
    if (xOffset < leftOffset.x) {
        if (outLimitPoint)
            *outLimitPoint = leftOffset;
        return YES; // bounced!
    }
    
    CGPoint rightOffset = _contentOffsetForCenteringProxy(self, self.lastProxy);
    if (xOffset > rightOffset.x) {
        if (outLimitPoint)
            *outLimitPoint = rightOffset;
        return YES; // bounced!
    }
    
    return NO;
}

static BOOL _shouldConstrainToScrollLimits(OUIDocumentPickerView *self, CGPoint *outLimitPoint)
{
    CGPoint offset = self.contentOffset;
    return _shouldConstrainOffsetToScrollLimits(self, offset.x, outLimitPoint);
}

static OUIDocumentProxy *_proxyWithCenterClosestToContentOffsetX(OUIDocumentPickerView *self, CGFloat xTarget)
{
    OUIDocumentProxy *closestProxy = nil;
    CGFloat closestDistance = CGFLOAT_MAX;
    
    for (OUIDocumentProxy *proxy in self->_proxies) {
        CGFloat proxyXCenter = _contentOffsetForCenteringProxy(self, proxy).x;
        CGFloat distance = fabs(proxyXCenter - xTarget);
        if (closestDistance > distance) {
            closestDistance = distance;
            closestProxy = proxy;
        }
    }
    
    return closestProxy;
}

static void _bounceBackIfNecessary(OUIDocumentPickerView *self)
{
    CGPoint limitOffset;
    if (_shouldConstrainToScrollLimits(self, &limitOffset)) {
        [self setContentOffset:limitOffset animated:YES];
        return;
    }
    
    OUIDocumentProxy *proxy = self.proxyClosestToCenter;
    if (proxy)
        [self snapToProxy:proxy animated:YES];
}


/*
 Slow the scroll down as if with a constant friction force.  Friction is a constant force in the opposite direction of velocity and is related to the normal force and the friction constant.  We'll just assume the normal force is 1 and make the friction force be a constant (opposite the direction of velocity).
 
 Then, F=ma, if we assume our scroll view has mass 1, we just have a = F.
 
 Relating position to time with a constant acceleration, we have the standard
 
 x(t) = x(0) + v(0)*t + 1/2 a*t^2
 
 */

// Physics tuning knobs.
static const CGFloat kSmoothScrollFriction = 4000; // Higher is more sticky
static const CGFloat kBounceFrictionFactor = 50; // A scale factor to the friction force above to slow down faster when in the bounce zone
static const CGFloat kVelocityScale = 0.5; // Scaling factor from the event's delta to the initial velocity in view space -- so, this controls the mapping between the touch velocity and the initial speed


static BOOL _oppositeSigns(CGFloat a, CGFloat b)
{
    return (a * b) < 0;
}

static NSTimeInterval _smoothScrollDuration(OUIDocumentPickerViewSmoothScroll ss)
{
    // v = v0 + a*t.  Looking for v=0
    
    return -ss.v0 / ss.a;
}

static CGFloat _smoothScrollXOffsetAfterDuration(OUIDocumentPickerViewSmoothScroll ss, NSTimeInterval t)
{
    return ss.x0 + ss.v0*t + 0.5 * ss.a * t*t;
}

static CGFloat _smoothScrollStartingVelocityToHitOffsetAfterDuration(OUIDocumentPickerViewSmoothScroll ss, CGFloat targetX)
{
    /*
     Compute a starting velocity that will hit the given target position exactly when v reaches zero, given the constant acceleration due to the friction force opposite the initial velocity direction. The time this takes will be unknown -- the original scroll duration has nothing to do with it (changing the initial velocity changes the amount of time it takes to decelerate).
     
     Take the two equations of motion:
     
     v = v0 + a*t
     x = x0 + v0*t + 1/2 * a * t^2
     
     Using the firist, with v = 0:
     
     t = -v0/a
     
     Set d = x - x0 and substitute into the 2nd and simplify:
     
     v0 = sqrt(2*d*a)
     
     Add a fabs to make sure we don't take the sqrt of a negative number and then restore the correct sign to the velocity (opposite the acceleration) and we are good!
     
     */
        
    CGFloat d = targetX - ss.x0;
    
    CGFloat v0 = sqrt(fabs(2 * d * ss.a));
    
    if (!_oppositeSigns(v0, ss.a))
        v0 = -v0;
    
    return v0;
}

static void _startSmoothScroll(OUIDocumentPickerView *self, CGFloat xVelocity)
{
    OUIDocumentPickerViewSmoothScroll *ss = &self->_smoothScroll;
    _cancelSmoothScroll(ss);

    ss->x0 = self.contentOffset.x;
    ss->t0 = [NSDate timeIntervalSinceReferenceDate];
    ss->v0 = xVelocity;
    ss->a = (ss->v0 < 0) ? kSmoothScrollFriction : -kSmoothScrollFriction; // friction force is in the opposite direction as velocity
    
    // Compute an acceleration that will hit the given proxy.
    NSTimeInterval scrollDuration = _smoothScrollDuration(*ss);
    CGFloat normalEndX = _smoothScrollXOffsetAfterDuration(*ss, scrollDuration);
    
    OUIDocumentProxy *proxy = _proxyWithCenterClosestToContentOffsetX(self, normalEndX);

    DEBUG_SCROLL(@"on proxy %d", [self->_sortedProxies indexOfObjectIdenticalTo:self.proxyClosestToCenter]);
    DEBUG_SCROLL(@"to proxy %d", [self->_sortedProxies indexOfObjectIdenticalTo:proxy]);
    
    DEBUG_SCROLL(@"start scroll:");
    DEBUG_SCROLL(@"  x0: %f", ss->x0);
    DEBUG_SCROLL(@"  v0: %f", ss->v0);
    DEBUG_SCROLL(@"   a: %f", ss->a);
    DEBUG_SCROLL(@"   t: %f", _smoothScrollDuration(*ss));
    DEBUG_SCROLL(@"   x: %f", _smoothScrollXOffsetAfterDuration(*ss, _smoothScrollDuration(*ss)));
    
    if (proxy == self.proxyClosestToCenter) {
        // If our scroll won't even get us out of the current proxy, make it more sticky instead of slowly accelerating up to the very edge and then backing up to the center.
        ss->a *= kBounceFrictionFactor;
        DEBUG_SCROLL(@"not adjusting (same proxy, normalEndX %f)", normalEndX);
    } else if (_shouldConstrainOffsetToScrollLimits(self, normalEndX, NULL)) {
        // If our normal starting animation curve would take us past the ends just run into the edge and bounce back instead of going artificially slow.
        DEBUG_SCROLL(@"not adjusting (off the edge, normalEndX %f)", normalEndX);
    } else {
        CGFloat targetX = _contentOffsetForCenteringProxy(self, proxy).x;
        
        ss->v0 = _smoothScrollStartingVelocityToHitOffsetAfterDuration(*ss, targetX);
        
        DEBUG_SCROLL(@"adjusted for targetX:%f", targetX);
        DEBUG_SCROLL(@"  x0: %f", ss->x0);
        DEBUG_SCROLL(@"  v0: %f", ss->v0);
        DEBUG_SCROLL(@"   a: %f", ss->a);
        DEBUG_SCROLL(@"   t: %f", _smoothScrollDuration(*ss));
        DEBUG_SCROLL(@"   x: %f", _smoothScrollXOffsetAfterDuration(*ss, _smoothScrollDuration(*ss)));
    }

    OBASSERT(_oppositeSigns(ss->v0, ss->a));
    
    // TODO: Use a CFTimerRef?
    ss->timer = [[NSTimer scheduledTimerWithTimeInterval:1/60.0 target:self selector:@selector(_smoothScrollTimerFired:) userInfo:nil repeats:YES] retain];
}

- (void)_smoothScrollTimerFired:(NSTimer *)timer;
{
    CFTimeInterval t = [NSDate timeIntervalSinceReferenceDate] - _smoothScroll.t0;
    
    // Stop when the friction force has overcome the original velocity, or at least nearly so.
    CGFloat currentVelocity = _smoothScroll.v0 + _smoothScroll.a*t;
    if (fabs(currentVelocity) < 1 || _oppositeSigns(currentVelocity, _smoothScroll.v0)) {
        _cancelSmoothScroll(&_smoothScroll);
        _bounceBackIfNecessary(self);
        return;
    }
    
    
    CGFloat x = _smoothScrollXOffsetAfterDuration(_smoothScroll, t);
    
    DEBUG_SCROLL(@"t:%f / %f x:%f v0:%f vt:%f (b:%d)", t, _smoothScrollDuration(_smoothScroll), x, _smoothScroll.v0, currentVelocity, _smoothScroll.bouncing);
    self.contentOffset = CGPointMake(x, 0);

    // If this position puts us off the edge of the scrollable area, then we need to start to bounce back. First we need to slow down faster so we don't overshoot so much.
    OUIDocumentPickerViewSmoothScroll *ss = &self->_smoothScroll;
    if (!ss->bouncing && _shouldConstrainToScrollLimits(self, NULL)) {        
        // Restart the smooth scroll from our current position/velocity, but with a higher acceleration so that we slow down faster.
        ss->bouncing = YES;
        
        ss->x0 = self.contentOffset.x;
        ss->t0 = [NSDate timeIntervalSinceReferenceDate];
        ss->v0 = currentVelocity;
        ss->a *= kBounceFrictionFactor;

        if (!_oppositeSigns(ss->v0, ss->a))
            ss->a = -ss->a;
        
        DEBUG_SCROLL(@"BOUNCE:");
        DEBUG_SCROLL(@"  x0: %f", ss->x0);
        DEBUG_SCROLL(@"  v0: %f", ss->v0);
        DEBUG_SCROLL(@"   a: %f", ss->a);
        DEBUG_SCROLL(@"   t: %f", _smoothScrollDuration(*ss));
        DEBUG_SCROLL(@"   x: %f", _smoothScrollXOffsetAfterDuration(*ss, _smoothScrollDuration(*ss)));
    }
}

- (void)_handlePickerPanGesture:(UIPanGestureRecognizer *)gestureRecognizer;
{
    OBPRECONDITION(_smoothScroll.timer == nil);
    _cancelSmoothScroll(&_smoothScroll); // just in case...
    
    /*
     
     Smooth scrolling normally happens via:
     #1  0x004788fc in -[UIScrollView(Static) _smoothScroll:] ()
     #2  0x004722ea in ScrollerHeartbeatCallback ()
     #3  0x03209d92 in HeartbeatTimerCallback ()
     
     The reported velocity is the delta between the last two moves, or maybe a few more.  It doesn't matter how long ago those moves were! In a normal scroll setup, if you tap, swipe really quick and stop and hold (so your last delta is huge) and then stop touching the screen, the velocity will start a scroll.
     
     */
    
    if (_disableScroll)
        return;

    UIGestureRecognizerState state = gestureRecognizer.state;
    
    if (state == UIGestureRecognizerStateBegan)
        _contentOffsetOnPanStart = self.contentOffset;
    if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged) {
        CGPoint scrolledOffset = _contentOffsetOnPanStart;
        
        scrolledOffset.x -= [gestureRecognizer translationInView:self].x;
        self.contentOffset = _handleOverpull(self, scrolledOffset);
        DEBUG_SCROLL(@"drag %@", NSStringFromPoint(self.contentOffset));
    }
    if (state == UIGestureRecognizerStateEnded) {
        CGFloat xVelocity = -kVelocityScale * [gestureRecognizer velocityInView:self].x;
        if (fabs(xVelocity) > kMinimumVelocityToStartDeceleration) {
            _startSmoothScroll(self, xVelocity);
        } else {
            // Make sure that if we finish touching while we are pulled past our limit that we rebound.
            _bounceBackIfNecessary(self);
        }
    }
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{    
    _cancelSmoothScroll(&_smoothScroll);
    [_sortedProxies release];
    [_proxies release];
    [_proxyViews release];
    [super dealloc];
}

- (id <OUIDocumentPickerViewDelegate>)delegate;
{
    return (id <OUIDocumentPickerViewDelegate>)[super delegate];
}

- (void)setDelegate:(id <OUIDocumentPickerViewDelegate>)delegate;
{
    OBPRECONDITION(!delegate || [delegate conformsToProtocol:@protocol(OUIDocumentPickerViewDelegate)]);
    [super setDelegate:delegate];
}

@synthesize disableLayout = _disableLayout;

@synthesize bottomGap = _bottomGap;
- (void)setBottomGap:(CGFloat)bottomGap;
{
    _bottomGap = bottomGap;
    [self setNeedsLayout];
}

@synthesize proxies = _proxies;
- (void)setProxies:(NSSet *)proxies;
{
    [_proxies release];
    _proxies = [[NSMutableSet alloc] initWithSet:proxies];
    
    [_sortedProxies release];
    _sortedProxies = [[[_proxies allObjects] sortedArrayUsingSelector:@selector(compare:)] copy];

    [self setNeedsLayout];
}

@synthesize sortedProxies = _sortedProxies;

- (OUIDocumentProxy *)firstProxy;
{
    if ([_sortedProxies count] > 0)
        return [_sortedProxies objectAtIndex:0];
    return nil;
}

- (OUIDocumentProxy *)lastProxy;
{
    return [_sortedProxies lastObject];
}

- (OUIDocumentProxy *)proxyClosestToCenter;
{
    return _proxyWithCenterClosestToContentOffsetX(self, self.contentOffset.x);
}

- (OUIDocumentProxy *)proxyToLeftOfProxy:(OUIDocumentProxy *)proxy;
{
    NSUInteger proxyIndex = [_sortedProxies indexOfObjectIdenticalTo:proxy];
    OBASSERT(proxyIndex != NSNotFound);
    return (proxyIndex == 0 || proxyIndex == NSNotFound) ? nil : [_sortedProxies objectAtIndex:proxyIndex - 1];
}

- (OUIDocumentProxy *)proxyToRightOfProxy:(OUIDocumentProxy *)proxy;
{
    NSUInteger proxyIndex = [_sortedProxies indexOfObjectIdenticalTo:proxy];
    OBASSERT(proxyIndex != NSNotFound);
    return (proxyIndex == [_sortedProxies count] - 1 || proxyIndex == NSNotFound) ? nil : [_sortedProxies objectAtIndex:proxyIndex + 1];
}

- (void)snapToProxy:(OUIDocumentProxy *)proxy animated:(BOOL)animated;
{
    if (!proxy)
        return;
    
    [self layoutIfNeeded];
    [self setContentOffset:_contentOffsetForCenteringProxy(self, proxy) animated:animated];
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

// The selected flag is set by layout based on our scroll position. There should be exactly one selected proxy unless we are empty.
- (OUIDocumentProxy *)selectedProxy;
{
    OUIDocumentProxy *selectedProxy = nil;

    for (OUIDocumentProxy *proxy in _proxies) {
        if (proxy.selected) {
            OBASSERT(!selectedProxy);
            selectedProxy = proxy;
        }
    }
    
    OBASSERT(selectedProxy != nil || [_proxies count] == 0);
    return selectedProxy;
}

// Called by OUIDocumentPicker when the interface orientation changes.
@synthesize disableRotationDisplay = _disableRotationDisplay;
- (void)willRotate;
{
    OBPRECONDITION(_flags.isRotating == NO);

    // This will cause us to discard speculatively loaded previews (and not rebuild them).
    _flags.isRotating = YES;
    [self layoutSubviews];
    if (_disableRotationDisplay)
        return;
    
    // Fade the previews out; make *all* our views go to zero alpha so that that is where they are for the -didRotate call (in case a different set of views is visible when fading in).
    [UIView beginAnimations:@"fade out proxies before rotation" context:NULL];
    {
        for (OUIDocumentProxyView *view in _proxyViews)
            view.alpha = 0;
    }
    [UIView commitAnimations];
}

- (void)didRotate;
{
    OBPRECONDITION(_flags.isRotating == YES);

    // Allow speculative preview loading.  Don't care if we lay out immediately.
    _flags.isRotating = NO;
    [self setNeedsLayout];
    if (_disableRotationDisplay)
        return;
    
    // We assume the caller has done a non-animating layout and scroll snap for the new orientation. Fade stuff back in.
    [UIView beginAnimations:@"fade in proxies after rotation" context:NULL];
    {
        for (OUIDocumentProxyView *view in _proxyViews)
            view.alpha = 1;
    }
    [UIView commitAnimations];
}

#pragma mark -
#pragma mark UIView

// UIScrollView would presumably use -touchesShouldBegin:withEvent:inContentView: for this, but with our having turned off its gesture recognizers, it doesn't.  So, if we have an smooth scroll going, we'll pretend the content views are invisible to taps.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hit = [super hitTest:point withEvent:event];
    
    if (_smoothScroll.timer && [hit isDescendantOfView:self])
        return self;
    return hit;
}

// We do our own pagination. UIScrollView's pagination is in even bounds sized blocks. This means that if we put on preview on each page, you can only see a single preview at a time.  We want to at least be able to see the edges of the neighboring previews and also don't want to have to pan across all the empty space.
- (void)layoutSubviews;
{
    if (_disableLayout)
        return;
    
    [super layoutSubviews];
    
    const CGRect bounds = self.bounds;

    const CGFloat kProxySpacing = 32;
    const CGFloat kNeighborWidthVisible = 120;
    const CGFloat kTopGap = 40;
    
    const CGFloat maximumHeight = CGRectGetHeight(bounds) - (_bottomGap + kTopGap);
    const CGFloat maximumWidth = CGRectGetWidth(bounds) - 2*kProxySpacing - kNeighborWidthVisible;

    DEBUG_LAYOUT(@"Laying out proxies in %@ with maximum size %@", [self shortDescription], NSStringFromCGSize(CGSizeMake(maximumWidth, maximumHeight)));
    
    if (maximumHeight <= 0 || maximumWidth <= 0) {
        // We aren't sized right yet
        _flags.needsRecentering = YES;
        return;
    }

    CGRect contentRect;
    contentRect.origin = self.contentOffset;
    contentRect.size = bounds.size;
    
    // Keep track of which proxy views are in use by visible proxies.
    NSMutableArray *unusedProxyViews = [[NSMutableArray alloc] initWithArray:_proxyViews];
    
    // Keep track of proxies that don't have views that need them.
    NSMutableArray *visibleProxiesWithoutView = nil;
    NSMutableArray *nearlyVisibleProxiesWithoutView = nil;
    
    CGFloat firstProxyWidth = 0, lastProxyWidth = 0;
    CGFloat xOffset = 0;
    for (OUIDocumentProxy *proxy in _sortedProxies) {
        //id <OUIDocumentPreview> preview = proxy.currentPreview;
        DEBUG_LAYOUT(@"proxy %@, preview = %@", proxy.name, [(id)preview shortDescription]);

        CGSize previewSize = [proxy previewSizeForTargetSize:CGSizeMake(maximumWidth, maximumHeight)];
        
        DEBUG_LAYOUT(@"  previewSize %@", NSStringFromCGSize(previewSize));

        if (firstProxyWidth == 0)
            firstProxyWidth = previewSize.width;
        else
            xOffset += kProxySpacing;
        
        lastProxyWidth = previewSize.width;
        
        // Store the frame on the proxy view controller itself. It will propagate to its view when loaded. This lets us do geometry queries on proxies that don't have their view loaded or scrolled into view.
        CGRect frame = CGRectMake(xOffset, kTopGap + (maximumHeight - previewSize.height) / 2,
                                  previewSize.width, previewSize.height);
        
        // CGRectIntegral can make the rect bigger when the size is integral but the position is fractional. We want the size to remain the same.
        CGRect integralFrame;
        integralFrame.origin.x = floor(frame.origin.x);
        integralFrame.origin.y = floor(frame.origin.y);
        integralFrame.size = frame.size;
        frame = CGRectIntegral(integralFrame);
        
        // If this proxy just has a placeholder, shrink the rect to fit the preview image. This lets us take up the same space (we advance based on 'frame'), but also lets us position the shadows and selection gray view in the preview correctly.
        if (![proxy hasPDFPreview]) {
            UIImage *image = [OUIDocumentProxyView placeholderPreviewImage];
            CGSize imageSize = image.size;
            CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
            CGRect imageRect = CGRectMake(floor(center.x - imageSize.width/2),
                                          floor(center.y - imageSize.height / 2),
                                          imageSize.width, imageSize.height);
            proxy.frame = imageRect;
            DEBUG_LAYOUT(@"  assigned image frame %@ based on %@", NSStringFromCGRect(imageRect), NSStringFromCGRect(frame));
        } else {
            proxy.frame = frame;
            DEBUG_LAYOUT(@"  assigned frame %@", NSStringFromCGRect(frame));
        }
        
        BOOL proxyVisible = CGRectIntersectsRect(frame, contentRect);
        OUIDocumentProxyView *proxyView = proxy.view;
        
        if (!proxyVisible) {
            CGFloat centerDistance = fabs(CGRectGetMidX(contentRect) - CGRectGetMidX(frame));
            BOOL nearlyVisible = (centerDistance / CGRectGetWidth(contentRect) < 1.5); // half the current screen (center to edge) and then one more screen over.
            
            if (nearlyVisible && !_flags.isRotating) {
                if (proxyView) {
                    // keep the view for now...
                    OBASSERT([unusedProxyViews containsObjectIdenticalTo:proxyView]);
                    [unusedProxyViews removeObjectIdenticalTo:proxyView];
                    DEBUG_LAYOUT(@"  kept nearly visible view");
                } else {
                    // try to give this a view if we can so it can preload its preview
                    if (!nearlyVisibleProxiesWithoutView)
                        nearlyVisibleProxiesWithoutView = [NSMutableArray array];
                    [nearlyVisibleProxiesWithoutView addObject:proxy];
                }
            } else {
                // If we aren't close to being visible and yet have a view, give it up.
                if (proxyView) {
                    proxy.view = nil;
                    DEBUG_LAYOUT(@"Removed view from proxy %@", proxy.name);
                }
            }
        } else {
            // If it is visible and already has a view, let it keep the one it has.
            if (proxyView) {
                OBASSERT([unusedProxyViews containsObjectIdenticalTo:proxyView]);
                [unusedProxyViews removeObjectIdenticalTo:proxyView];
                DEBUG_LAYOUT(@"  kept view");
            } else {
                // This proxy needs a view!
                if (!visibleProxiesWithoutView)
                    visibleProxiesWithoutView = [NSMutableArray array];
                [visibleProxiesWithoutView addObject:proxy];
            }
        }
        
        if (proxy.layoutShouldAdvance) {
            CGFloat nextXOffset = CGRectGetMaxX(frame);
            DEBUG_LAYOUT(@"  stepping %f", nextXOffset - xOffset);
            xOffset = nextXOffset;
        }
    }
    
    // Now, assign views to visibile or nearly visible proxies that don't have them. First, union the two lists.
    if (visibleProxiesWithoutView || nearlyVisibleProxiesWithoutView) {
        NSMutableArray *proxiesNeedingView = [NSMutableArray array];
        if (visibleProxiesWithoutView)
            [proxiesNeedingView addObjectsFromArray:visibleProxiesWithoutView];
        if (nearlyVisibleProxiesWithoutView)
            [proxiesNeedingView addObjectsFromArray:nearlyVisibleProxiesWithoutView];
        
        for (OUIDocumentProxy *proxy in proxiesNeedingView) {            
            OBASSERT(proxy.view == nil);
            
            OUIDocumentProxyView *view = [unusedProxyViews lastObject];
            OBASSERT(view); // we should never run out given that our layout only shows 3 at a time.
            if (view) {
                OBASSERT(view.superview == self); // we keep these views as subviews, just hide them.
                
                // Make the view start out at the "original" position instead of flying from where ever it was last left.
                OUIBeginWithoutAnimating
                {
                    view.hidden = NO;
                    view.frame = proxy.previousFrame;
                }
                OUIEndWithoutAnimating;
                
                proxy.view = view;
                [unusedProxyViews removeLastObject];
                DEBUG_LAYOUT(@"Assigned view %@ to proxy %@", [proxy.view shortDescription], proxy.name);
            }
        }
    }
    
    // Any remaining unused proxy views should be hidden.
    for (OUIDocumentProxyView *view in unusedProxyViews) {
        DEBUG_LAYOUT(@"Hiding unused view %@", [view shortDescription]);
        view.hidden = YES;
        view.preview = nil;
    }
    [unusedProxyViews release];
    
    self.contentSize = CGSizeMake(xOffset, maximumHeight);
    self.contentInset = UIEdgeInsetsMake(0,
                                         ceil(bounds.size.width - firstProxyWidth) / 2,
                                         0,
                                         ceil(bounds.size.width - lastProxyWidth) / 2);
    

    OUIDocumentProxy *centerProxy = [self proxyClosestToCenter];
    if (_flags.needsRecentering && centerProxy != nil) {
        [self setContentOffset:_contentOffsetForCenteringProxy(self, centerProxy) animated:NO];
        _flags.needsRecentering = NO;
    }

    BOOL changedSelection = NO;
    for (OUIDocumentProxy *proxy in _sortedProxies) {
        BOOL isSelected = (proxy == centerProxy);
        changedSelection |= (proxy.selected ^ isSelected);
        proxy.selected = isSelected;
    }
    
    if (changedSelection || !centerProxy) {
        [self.delegate documentPickerView:self didSelectProxy:centerProxy];
    }
}

#pragma mark -
#pragma mark UIResponder

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    _cancelSmoothScroll(&_smoothScroll);
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    // If all the touches have ended, and there is no autoscroll, then the user possibly just grabbed the view while it was autoscrolling to stop it.
    if ([[event touchesForView:self] isSubsetOfSet:touches])
        [self snapToProxy:self.proxyClosestToCenter animated:YES];
    [super touchesEnded:touches withEvent:event];
}

@synthesize disableScroll = _disableScroll;
@end
