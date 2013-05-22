// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIHoldOnesHorsesIndicator.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define DEBUG_HORSE(format, ...) NSLog(@"HORSE: " format, ## __VA_ARGS__)
#else
#define DEBUG_HORSE(format, ...)
#endif

static const NSTimeInterval kDelayBeforeShowingSpinner = 0.5f;
static const NSTimeInterval kFadeInterval = 0.25f;
static const NSTimeInterval kMinimumSpinnerDisplayTime = 1.0f; // used to ensure that spinner appears for a minimum amount of time, if at all

static UIColor *BackgroundWashColor;

@interface OUIHoldOnesHorsesIndicator ()
{
    BOOL _okToDeactivate;
}
@property (nonatomic, assign) BOOL shouldDisableAllInteraction;
@property (nonatomic, strong) UIView *parentView;
@property (nonatomic, strong) UIView *indicatorView;
@property (nonatomic, strong) UIActivityIndicatorView *spinnerView;
@property (nonatomic, strong) NSTimer *stateChangeTimer;
@property (nonatomic, copy) void (^delayedDeactivationHandler)(void);

- (void)_startDelayUntilInitialSpinner;
- (void)_startMinimumSpinnerDisplayTimer;
- (void)_startDelayUntilDeactivate;

@end

@implementation OUIHoldOnesHorsesIndicator

+ (void)initialize;
{
    OBINITIALIZE;
    
    BackgroundWashColor = [[UIColor colorWithWhite:0.0f alpha:0.5f] retain];
}

+ (OUIHoldOnesHorsesIndicator *)holdOnesHorsesIndicatorForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable;
{
    OUIHoldOnesHorsesIndicator *result = [[[OUIHoldOnesHorsesIndicator alloc] initForView:view shouldDisableAllInteraction:disable] autorelease];
    [result activate];
    return result;
}

- (id)initForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable;
{
    self = [super init];
    if (self) {
        _shouldDisableAllInteraction = disable;
        _parentView = [view retain];
    }
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(self.indicatorView == nil);
    OBPRECONDITION(self.spinnerView == nil);
    
    [_parentView release];
    [_indicatorView release];
    [_spinnerView release];
    [_stateChangeTimer invalidate];
    [_stateChangeTimer release];
    [_delayedDeactivationHandler release];
    
    [super dealloc];
}

- (void)_startSpinner:(NSTimer *)timer;
{
    DEBUG_HORSE(@"In %@", NSStringFromSelector(_cmd));
    _okToDeactivate = NO;
    self.stateChangeTimer = nil;
    [UIView animateWithDuration:kFadeInterval animations:^{
        self.indicatorView.backgroundColor = BackgroundWashColor;
    } completion:^(BOOL finished) {
        [self.spinnerView startAnimating];
        [self _startMinimumSpinnerDisplayTimer];
    }];
}

- (void)_minimumDisplayTimeReached:(NSTimer *)timer;
{
    DEBUG_HORSE(@"In %@", NSStringFromSelector(_cmd));
    _okToDeactivate = YES;
}

- (void)activate;
{
    DEBUG_HORSE(@"In %@", NSStringFromSelector(_cmd));
    OBPRECONDITION(self.indicatorView == nil);

    CGRect indicatorFrame;
    indicatorFrame.size = self.parentView.frame.size;
    indicatorFrame.origin = CGPointZero;
    self.indicatorView = [[[UIView alloc] initWithFrame:indicatorFrame] autorelease];
    // TODO: We may want to expose style and color as properties, defaulting to small and white. For now let's just not worry about it.
    self.spinnerView = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite] autorelease];
    [self.indicatorView addSubview:self.spinnerView];
    self.spinnerView.center = self.indicatorView.center;
    [self.parentView addSubview:self.indicatorView];
    
    if (self.shouldDisableAllInteraction)
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    _okToDeactivate = YES;
    [self _startDelayUntilInitialSpinner];
}

- (void)_deactivateNow;
{
    DEBUG_HORSE(@"In %@", NSStringFromSelector(_cmd));
    self.stateChangeTimer = nil;
    
    if (self.shouldDisableAllInteraction)
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    
    [self.indicatorView removeFromSuperview];
    self.indicatorView = nil;
    self.spinnerView = nil;
    
    if (self.delayedDeactivationHandler != NULL)
        self.delayedDeactivationHandler();
}

- (void)deactivateImmediately:(BOOL)immediately withCompletionHandler:(void(^)())handler; // removes the waiting indicator and resumes user interaction, then calls the completion handler. If immediately == NO, then ensures that spinner has been displayed for some minimum time before clearing it.
{
    DEBUG_HORSE(@"In %@", NSStringFromSelector(_cmd));
    OBPRECONDITION(self.indicatorView != nil);
    OBPRECONDITION(self.delayedDeactivationHandler == NULL); // may not be necessary, but we haven't thought through what happens with two deactivate calls in a row

    self.delayedDeactivationHandler = handler;
    
    if (_okToDeactivate || immediately)
        [self _deactivateNow];
    else
        [self _startDelayUntilDeactivate];
}

#pragma mark Private API

- (void)setStateChangeTimer:(NSTimer *)stateChangeTimer;
{
    if (_stateChangeTimer == stateChangeTimer)
        return;
    
    [_stateChangeTimer invalidate];
    [_stateChangeTimer release];
    
    _stateChangeTimer = [stateChangeTimer retain];
}

- (void)_startDelayUntilInitialSpinner;
{
    self.stateChangeTimer = [NSTimer scheduledTimerWithTimeInterval:kDelayBeforeShowingSpinner target:self selector:@selector(_startSpinner:) userInfo:nil repeats:NO];
}

- (void)_startMinimumSpinnerDisplayTimer;
{
    self.stateChangeTimer = [NSTimer scheduledTimerWithTimeInterval:kMinimumSpinnerDisplayTime target:self selector:@selector(_minimumDisplayTimeReached:) userInfo:nil repeats:NO];
}

- (void)_startDelayUntilDeactivate;
{
    OBASSERT(self.stateChangeTimer != nil);
    NSDate *okToDeactivateTime = self.stateChangeTimer.fireDate;
    OBASSERT([self.stateChangeTimer.fireDate compare:[NSDate date]] == NSOrderedDescending); // deactivate time should be in the future or we wouldn't have reached here

    NSTimer *deactivateTimer = [[[NSTimer alloc] initWithFireDate:okToDeactivateTime interval:0.0f target:self selector:@selector(_deactivateNow) userInfo:nil repeats:NO] autorelease];
    [[NSRunLoop mainRunLoop] addTimer:deactivateTimer forMode:NSRunLoopCommonModes];
    self.stateChangeTimer = deactivateTimer;
}

@end
