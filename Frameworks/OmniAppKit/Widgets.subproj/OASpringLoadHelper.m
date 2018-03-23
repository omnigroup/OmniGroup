// Copyright 2003-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASpringLoadHelper.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OASpringLoadHelper (/*Private*/)
@property (nonatomic, weak) id <OASpringLoadHelper> delegate;
- (id)_initWithDelegate:(id <OASpringLoadHelper>)aDelegate;
- (void)_startSpringTimer;
- (BOOL)_shouldFlash;
- (void)_startFlashing;
- (void)_flash;
- (void)_stopSpringTimer;
- (void)_springLoad;
@end

@implementation OASpringLoadHelper

+ (OASpringLoadHelper *)springLoadHelperWithDelegate:(id <OASpringLoadHelper>)aDelegate;
{
    return [[OASpringLoadHelper alloc] _initWithDelegate:aDelegate];
}

- (void)dealloc;
{
    [self _stopSpringTimer];

    _delegate = nil;
}

#pragma mark API

- (void)beginSpringLoad;
{
    NSPoint startPoint = [NSEvent mouseLocation];

    slopRect = NSMakeRect(startPoint.x - 2.0f, startPoint.y - 2.0f, 4.0f, 4.0f);

    [self _startSpringTimer];
}

- (void)updateSpringLoad;
{
    // Make sure that the spring load only fires if the user holds the mouse relatively still
    if (!NSPointInRect([NSEvent mouseLocation], slopRect)) {
        [self cancelSpringLoad];
        [self beginSpringLoad];
    }
}

- (void)cancelSpringLoad;
{
    [self _stopSpringTimer];
}

#pragma mark Private

- (id)_initWithDelegate:(id <OASpringLoadHelper>)aDelegate;
{
    if (!(self = [super init]))
        return nil;

    _delegate = aDelegate;

    return self;
}

- (void)_startSpringTimer;
{
    if (springTimer != nil)
        [self _stopSpringTimer];

    NSTimeInterval springingDelaySeconds = 0.5; // The value for 'Medium' in Finder's preferences.

    // As of 10.5, Finder's spring-loaded folder preference is in the global domain under com.apple.springing.delay, as seconds.
    NSNumber *springLoadedFolderDelayNumber = [[NSUserDefaults standardUserDefaults] objectForKey:@"com.apple.springing.delay"];
    if (springLoadedFolderDelayNumber != nil) {
        // Might be a different type than we expect; be careful.
        if ([springLoadedFolderDelayNumber respondsToSelector:@selector(doubleValue)])
            springingDelaySeconds = [springLoadedFolderDelayNumber doubleValue];
        else if ([springLoadedFolderDelayNumber respondsToSelector:@selector(floatValue)])
            springingDelaySeconds = [springLoadedFolderDelayNumber floatValue];
        else {
            OBASSERT_NOT_REACHED("Unable to interpret com.apple.springing.delay preference value");
        }
    }
    
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %@]: Springing delay set to %0.3f seconds (%@=%@)", OBShortObjectDescription(self), NSStringFromSelector(_cmd), springingDelaySeconds, NSStringFromClass([springLoadedFolderDelayNumber class]), springLoadedFolderDelayNumber);
#endif

    if ([self _shouldFlash]) {
        springTimer = [NSTimer scheduledTimerWithTimeInterval:springingDelaySeconds target:self selector:@selector(_startFlashing) userInfo:nil repeats:NO];
    } else {
        springTimer = [NSTimer scheduledTimerWithTimeInterval:springingDelaySeconds target:self selector:@selector(_springLoad) userInfo:nil repeats:NO];
    }
}

- (BOOL)_shouldFlash;
{
    return [self.delegate springLoadHelperShouldFlash:self];
}

- (void)_startFlashing;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
#endif

    flashCount = 0;

    if (springTimer != nil)
        [self _stopSpringTimer];

    springTimer = [NSTimer scheduledTimerWithTimeInterval:0.075 target:self selector:@selector(_flash) userInfo:nil repeats:YES];
}

- (void)_flash;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
#endif

    id<OASpringLoadHelper> delegate = self.delegate;
    if (flashCount++ == 4) {
        // The spring load action invoked by -springLoadHelperWantsSpringLoad: may leave the target selected, but we don't necessarily want to leave the flash on since the delegate might not actually select the target on spring load (OmniOutliner might focus or expand a row, for example).
        [delegate springLoadHelper:self wantsFlash:NO];
        [self _springLoad];
    } else {
        [delegate springLoadHelper:self wantsFlash:!(flashCount % 2 == 0)];
    }
}

- (void)_stopSpringTimer;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
#endif

    [springTimer invalidate];
    springTimer = nil;
}

- (void)_springLoad;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
#endif

    if (springTimer != nil)
        [self _stopSpringTimer];

    [self.delegate springLoadHelperWantsSpringLoad:self];
}

@end
