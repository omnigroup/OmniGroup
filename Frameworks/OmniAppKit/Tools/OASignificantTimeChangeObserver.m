// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASignificantTimeChangeObserver.h>
#import <OmniBase/OmniBase.h>

#if OMNI_BUILDING_FOR_IOS
#import <UIKit/UIApplication.h> // for UIApplicationSignificantTimeChangeNotification
#elif OMNI_BUILDING_FOR_MAC
#import <AppKit/AppKit.h> // for NSWorkspace and notifications
#else
@import Foundation;
#endif

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const OASignificantTimeChangeNotification = @"OASignificantTimeChangeNotification";

#pragma mark -

@interface OASignificantTimeChangeObserver : NSObject {
  @private
    BOOL _hasRegisteredWithNotificationCenter;
    NSTimer *_timer;
}

@end

#pragma mark -

@implementation OASignificantTimeChangeObserver

// This object, and the entire implementation, is an implementation detail of OASignificantTimeChangeNotification.
// Make sure the shared instance is created at startup.
static void EnsureDateChangeObservers(void) __attribute__((constructor));
static void EnsureDateChangeObservers(void) {
    [OASignificantTimeChangeObserver sharedDateChangeTracker];
}

+ (OASignificantTimeChangeObserver *)sharedDateChangeTracker;
{
    static OASignificantTimeChangeObserver *sharedDateChangeTracker = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        sharedDateChangeTracker = [[self alloc] init];
    });

    return sharedDateChangeTracker;
}

- (id)init;
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    [self _addSignificantTimeChangeObservers];
    [self _setUpTimer];
    
    return self;
}

- (void)dealloc;
{
    [self _removeSignificantTimeChangeObservers];
}

#pragma mark - Notification handlers

- (void)handleSignificantTimeChangeTimerDidFire:(NSTimer *)timer;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OASignificantTimeChangeNotification object:nil];
    
    [self _invalidate];
    [self _setUpTimer];
}

- (void)handleSignificantTimeChangeNotification:(NSNotification *)notification;
{
    [self handleSignificantTimeChangeTimerDidFire:_timer];
}

- (void)handleTimeZoneDidChangeNotification:(NSNotification *)notification;
{
    [self handleSignificantTimeChangeTimerDidFire:_timer];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

- (void)handleSystemSignificantTimeChangeNotification:(NSNotification *)notification;
{
    [self handleSignificantTimeChangeTimerDidFire:_timer];
}

#else

- (void)handleWorkspaceDidWakeNotification:(NSNotification *)notification;
{
    [self handleSignificantTimeChangeTimerDidFire:_timer];
}

#endif

#pragma mark - Private

- (void)_invalidate;
{
    if ([_timer isValid]) {
        [_timer invalidate];
    }
    
    _timer = nil;
}

- (NSDate *)_beginningOfNextDay
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.hour = 0;
    components.minute = 0;
    components.second = 0;
    
    NSDate *beginningOfTomorrow = [[NSCalendar currentCalendar] nextDateAfterDate:[NSDate date] matchingComponents:components options:NSCalendarMatchNextTime];
    return beginningOfTomorrow;
}

- (void)_setUpTimer;
{
    //OBPRECONDITION(_timer == nil);
    if (_timer != nil) {
        return;
    }
    
    // Schedule this timer for just after midnight, so that hopefully
    // - we fire the timer after system services that we rely on have handled the midnight switchover
    // - we aren't subject to drift that causes us to fire just before midnight
    
    const NSTimeInterval DAY_ROLLOVER_PADDING = 1.0;
    NSDate *beginningOfTomorrow = [[self _beginningOfNextDay] dateByAddingTimeInterval:DAY_ROLLOVER_PADDING];

    _timer = [[NSTimer alloc] initWithFireDate:beginningOfTomorrow interval:0 target:self selector:@selector(handleSignificantTimeChangeTimerDidFire:) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
}

- (void)_addSignificantTimeChangeObservers;
{
    if (_hasRegisteredWithNotificationCenter)
        return;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSignificantTimeChangeNotification:) name:NSSystemClockDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTimeZoneDidChangeNotification:) name:NSSystemTimeZoneDidChangeNotification object:nil];

#if OMNI_BUILDING_FOR_IOS
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSystemSignificantTimeChangeNotification:) name:UIApplicationSignificantTimeChangeNotification object:nil];
#elif OMNI_BUILDING_FOR_MAC
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(handleWorkspaceDidWakeNotification:) name:NSWorkspaceDidWakeNotification object:nil];
#elif OMNI_BUILDING_FOR_SERVER
    // NSWorkspaceDidWakeNotification is sent when the machine wakes from sleep, which the servers should never do.
#else
    OBFinishPortingLater("Significant time change notification?");
#endif
    
    _hasRegisteredWithNotificationCenter = YES;
}

- (void)_removeSignificantTimeChangeObservers;
{
    if (!_hasRegisteredWithNotificationCenter)
        return;
    
    NSNotificationCenter *notificationCenter = nil;
    
    notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:NSSystemClockDidChangeNotification object:nil];

#if OMNI_BUILDING_FOR_IOS
    [notificationCenter removeObserver:self name:UIApplicationSignificantTimeChangeNotification object:nil];
#elif OMNI_BUILDING_FOR_MAC
    notificationCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [notificationCenter removeObserver:self name:NSWorkspaceDidWakeNotification object:nil];
#else
    OBFinishPortingLater("Significant time change notification?");
#endif

    _hasRegisteredWithNotificationCenter = NO;
}

@end

NS_ASSUME_NONNULL_END
