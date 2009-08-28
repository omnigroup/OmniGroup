// Copyright 2003-2009 Omni Development, Inc.  All rights reserved.
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
    return [[[OASpringLoadHelper alloc] _initWithDelegate:aDelegate] autorelease];
}

- (void)dealloc;
{
    [self _stopSpringTimer];

    nonretainedDelegate = nil;

    [super dealloc];
}

#pragma mark API

- (void)beginSpringLoad;
{
    NSPoint startPoint = [NSEvent mouseLocation];

    slopRect = NSMakeRect(startPoint.x - 2.0, startPoint.y - 2.0, 4.0, 4.0);

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

    nonretainedDelegate = aDelegate;

    return self;
}

- (void)_startSpringTimer;
{
    if (springTimer != nil)
        [self _stopSpringTimer];

    NSTimeInterval springingDelaySeconds = 0.5; // The value for 'Medium' in Finder's preferences.

    // As of 10.5, Finder's spring-loaded folder preference is in the global domain under com.apple.springing.delay, as seconds.
    NSNumber *springLoadedFolderDelayNumber = [[NSUserDefaults standardUserDefaults] objectForKey:@"com.apple.springing.delay"];
    if (springLoadedFolderDelayNumber) {
        // Might be a different type than we expect; be careful.
        if ([springLoadedFolderDelayNumber respondsToSelector:@selector(doubleValue)])
            springingDelaySeconds = [springLoadedFolderDelayNumber doubleValue];
        else if ([springLoadedFolderDelayNumber respondsToSelector:@selector(floatValue)])
            springingDelaySeconds = [springLoadedFolderDelayNumber floatValue];
        else {
            OBASSERT_NOT_REACHED("Unable to interpret com.apple.springing.delay preference value");
        }
    }
    
#ifdef DEBUG_kc
    NSLog(@"-[%@ %s]: Springing delay set to %0.3f seconds (%@=%@)", OBShortObjectDescription(self), _cmd, springingDelaySeconds, NSStringFromClass([springLoadedFolderDelayNumber class]), springLoadedFolderDelayNumber);
#endif

    if ([self _shouldFlash]) {
        springTimer = [[NSTimer scheduledTimerWithTimeInterval:springingDelaySeconds target:self selector:@selector(_startFlashing) userInfo:nil repeats:NO] retain];
    } else {
        springTimer = [[NSTimer scheduledTimerWithTimeInterval:springingDelaySeconds target:self selector:@selector(_springLoad) userInfo:nil repeats:NO] retain];
    }
}

- (BOOL)_shouldFlash;
{
    return [nonretainedDelegate springLoadHelperShouldFlash:self];
}

- (void)_startFlashing;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    flashCount = 0;

    if (springTimer != nil)
        [self _stopSpringTimer];

    springTimer = [[NSTimer scheduledTimerWithTimeInterval:0.075 target:self selector:@selector(_flash) userInfo:nil repeats:YES] retain];
}

- (void)_flash;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    if (flashCount++ == 4) {
        // The spring load action invoked by -springLoadHelperWantsSpringLoad: may leave the target selected, but we don't necessarily want to leave the flash on since the delegate might not actually select the target on spring load (OmniOutliner might hoist or expand a row, for example).
        [nonretainedDelegate springLoadHelper:self wantsFlash:NO];
        [self _springLoad];
    } else {
        [nonretainedDelegate springLoadHelper:self wantsFlash:!(flashCount % 2 == 0)];
    }
}

- (void)_stopSpringTimer;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    [springTimer invalidate];
    [springTimer release];
    springTimer = nil;
}

- (void)_springLoad;
{
#ifdef DEBUG_SpringLoad
    NSLog(@"-[%@ %s]", OBShortObjectDescription(self), _cmd);
#endif

    if (springTimer != nil)
        [self _stopSpringTimer];

    [nonretainedDelegate springLoadHelperWantsSpringLoad:self];
}

@end
