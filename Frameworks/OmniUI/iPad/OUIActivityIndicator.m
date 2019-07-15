// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIActivityIndicator.h>

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIActivityIndicator
{
    UIView *_view;
    UIColor *_color;
    UIView *_backgroundView;
    
    UIActivityIndicatorView *_activityIndicator;
    NSUInteger _showCount;
}

static CFMutableDictionaryRef ViewToActivityIndicator = NULL;

+ (void)initialize;
{
    OBINITIALIZE;
    
    ViewToActivityIndicator = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);
}

- initWithView:(UIView *)view color:(UIColor *)color bezelColor:(UIColor *)bezelColor;
{
    OBPRECONDITION(view);
    OBPRECONDITION(view.window); // should already be on screen

    if (!(self = [super init]))
        return nil;
    
    _view = view;
    _color = [color copy];
    _backgroundView = [[UIView alloc] init];
    _backgroundView.backgroundColor = bezelColor;
    
    return self;
}

- (void)dealloc;
{
    if (_activityIndicator) {
        OBASSERT_NOT_REACHED("-hide should really have been called the right number of times");
        [self _remove];
    }
}

- (void)_add;
{
    OBPRECONDITION(_activityIndicator == nil);
    OBPRECONDITION(CFDictionaryGetValue(ViewToActivityIndicator, (__bridge CFTypeRef)_view) == nil);

    CFDictionaryAddValue(ViewToActivityIndicator, (__bridge CFTypeRef)_view, (__bridge const void *)(self));

    __block CGFloat maxAlpha;
    __block UIView *viewToFade = nil;
    
    [UIView performWithoutAnimation:^{
        _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        _activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
        
        if (_color)
            _activityIndicator.color = _color;
        
        _activityIndicator.layer.zPosition = 2;
        [_activityIndicator startAnimating];
        
        _backgroundView.frame = CGRectMake(0, 0, _activityIndicator.bounds.size.width + 40.0, _activityIndicator.bounds.size.height + 40.0);
        _backgroundView.layer.cornerRadius = 12.0;
        
        [_backgroundView addSubview:_activityIndicator];
        
        _activityIndicator.center = _backgroundView.center;
        
        [_view.superview addSubview:_backgroundView];
        _backgroundView.center = _view.center;
        
        
        BOOL shouldDrawBezel = (_backgroundView.backgroundColor != nil);
        if (shouldDrawBezel) {
            // When we fade the backgroundView in for the animation, we want to respect the alpha of the color that was passed in. Try to grab it here. If this fails for some reason, just default to full opacity.
            if (![_backgroundView.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&maxAlpha]) {
                maxAlpha = 1;
            }
            
            viewToFade = _backgroundView;
            _activityIndicator.alpha = 1;
            
        }
        else {
            maxAlpha = 1;
            viewToFade = _activityIndicator;
            _backgroundView.alpha = 1;
        }
        viewToFade.alpha = 0;
    }];
    
    // Just fade this in
    [UIView animateWithDuration:0.3 animations:^{
        viewToFade.alpha = maxAlpha;
    }];
}

- (void)_remove;
{
    OBPRECONDITION(_activityIndicator);
    OBPRECONDITION((__bridge OUIActivityIndicator *)CFDictionaryGetValue(ViewToActivityIndicator, (__bridge CFTypeRef)_view) == self);
    
    CFDictionaryRemoveValue(ViewToActivityIndicator, (__bridge CFTypeRef)_view);
    
    [_activityIndicator stopAnimating];
    
    [_backgroundView removeFromSuperview];
    _backgroundView = nil;
    _activityIndicator = nil;
}

- (void)_show;
{
    if (_showCount == 0)
        [self _add];
    _showCount++;
}

- (void)hide;
{
    if (_showCount == 0) {
        OBASSERT_NOT_REACHED("Called -hide too many times");
        return;
    }
    
    _showCount--;
    
    if (_showCount == 0)
        [self _remove];
}

+ (OUIActivityIndicator *)showActivityIndicatorInView:(UIView *)view;
{
    return [self showActivityIndicatorInView:view withColor:[UIColor whiteColor]];
}

+ (OUIActivityIndicator *)showActivityIndicatorInView:(UIView *)view withColor:(UIColor *)color;
{
    return [self showActivityIndicatorInView:view withColor:color bezelColor:nil];
}

+ (OUIActivityIndicator *)showActivityIndicatorInView:(UIView *)view withColor:(UIColor *)color bezelColor:(UIColor *)bezelColor {
    if (!view.window) {
        return nil;
    }
    OUIActivityIndicator *indicator = (__bridge OUIActivityIndicator *)CFDictionaryGetValue(ViewToActivityIndicator, (__bridge CFTypeRef)view);
    if (!indicator)
        indicator = [[OUIActivityIndicator alloc] initWithView:view color:color bezelColor:bezelColor];
    
    [indicator _show];
    
    return indicator;
}

@end
