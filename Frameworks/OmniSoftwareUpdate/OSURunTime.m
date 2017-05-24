// Copyright 2007-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSURunTime.h>

#import <Foundation/Foundation.h>
#import <OmniFoundation/OFNull.h> // For OFNOTEQUAL
#import <OmniFoundation/OFPreference.h>
#include <mach/clock.h>
#include <mach/mach.h>

OB_REQUIRE_ARC

RCS_ID("$Id$");

// This is measured in wall-clock seconds since the last boot and does not increment while the machine is asleep. Importantly, we don't use NSDate here since the user's clock could be temporarily wrong when we launch.
static NSString * const OSULastRunStartClockTimeKey = @"OSULastRunStartClockTime";

static NSString * const OSURunTimeStatisticsKey = @"OSURunTimeStatistics";

// scopes
static NSString * const OSURunTimeStatisticsAllVersionsScopeKey = @"total";
static NSString * const OSURunTimeStatisticsCurrentVersionsScopeKey = @"current";

// Subkeys in each of the scope dictionaries.
static NSString * const OSUNumberOfRunsKey = @"runCount";
static NSString * const OSUNumberOfCrashesKey = @"crashCount";
static NSString * const OSUTotalRunTimeKey = @"runTime";
static NSString * const OSUVersionKey = @"version";

static BOOL OSURunTimeHasRunningSession = NO;

static OFDeclareDebugLogLevel(OSURuntimeDebug);
#define OSU_RUNTIME_DEBUG(level, format, ...) do { \
    if (OSURuntimeDebug >= (level)) \
        NSLog(@"OSU: " format, ## __VA_ARGS__); \
} while (0)

NSString * const OSULastSuccessfulCheckDateKey = @"OSULastSuccessfulCheckDate";

BOOL OSURunTimeHasHandledApplicationTermination(void)
{
    return (OSURunTimeHasRunningSession == NO);
}

static unsigned OSUGetCurrentClockTime(void)
{
    static clock_serv_t cclock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &cclock);
    });
    
    mach_timespec_t mts;
    clock_get_time(cclock, &mts);
    return mts.tv_sec; // We don't care about the nanoseconds...
}

void OSURunTimeApplicationActivated(NSString *appIdentifier, NSString *bundleVersion)
{
    // Record the time we started this run of the application.  Also, increment the number of runs.
    // If we crash, OCC will handle calculating how long we ran until we crashed.  If we quit normally, we will do it.
    // Thus, if we launch and a preference exists for the 'last start time', then there is a bug.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Can't really OBASSERT on this since it'll fire over and over when in the debugger. So, we just log and only when not building for DEBUG to avoid accumulating log spam.
#if !defined(DEBUG) || defined(DEBUG_kc) || defined(DEBUG_bungi)
    if ([defaults objectForKey:OSULastRunStartClockTimeKey] != nil) {
        NSLog(@"%@ default is non-nil; unless you forcibly killed the app and restarted it it should be nil at launch time.", OSULastRunStartClockTimeKey);
        
        // If we aren't in the debugger and we get activated when we don't expect to, then we signal this as a crash. On the Mac, OmniCrashCatcher will have called this on our app's behalf, but on iOS we do it ourselves.
        OSURunTimeApplicationDeactivated(appIdentifier, bundleVersion, YES/*crashed*/);
    }
#endif

    OBASSERT(OSURunTimeHasRunningSession == NO);
    OSURunTimeHasRunningSession = YES;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    [[NSProcessInfo processInfo] disableSuddenTermination];
#endif
    NSNumber *startClockTimeNumber = @(OSUGetCurrentClockTime());
    [defaults setObject:startClockTimeNumber forKey:OSULastRunStartClockTimeKey];
    OSU_RUNTIME_DEBUG(1, @"Activating %@ at system clock time %@", appIdentifier, startClockTimeNumber);
    
    [defaults synchronize]; // Make sure we save in case we crash before NSUserDefaults automatically synchronizes
}

static NSDictionary *_OSURunTimeUpdateStatisticsScope(NSDictionary *oldScope, NSString *version, NSNumber *startClockTimeNumber, unsigned currentClockTime, BOOL crashed, BOOL newRun)
{
    if (oldScope && ![oldScope isKindOfClass:[NSDictionary class]]) {
        OBASSERT([oldScope isKindOfClass:[NSDictionary class]]);
        oldScope = nil;
    }
    
    // Validate the version.
    NSString *oldVersion = [oldScope objectForKey:OSUVersionKey];
    if (OFNOTEQUAL(version, oldVersion))
        oldScope = nil;
    
    NSMutableDictionary *newScope = [NSMutableDictionary dictionary];
    
    if (version)
        [newScope setObject:version forKey:OSUVersionKey];
    
    // Run time
    if (startClockTimeNumber) {
        unsigned startClockTime = [startClockTimeNumber doubleValue];

        // The clock can go "backwards" if the machine is restarted between runs of the app (possibly if the last run crashed) since OSUGetCurrentClockTime() returns the system clock.
        // OBASSERT(startClockTime <= currentClockTime);

        if (startClockTime < currentClockTime) {
            NSNumber *totalRunTimeNumber = [oldScope objectForKey:OSUTotalRunTimeKey];

            if (totalRunTimeNumber && ![totalRunTimeNumber isKindOfClass:[NSNumber class]]) {
                OBASSERT([totalRunTimeNumber isKindOfClass:[NSNumber class]]);
                totalRunTimeNumber = nil;
            }

            NSTimeInterval totalRunTime = totalRunTimeNumber ? [totalRunTimeNumber doubleValue] : 0.0;
            
            totalRunTime += (currentClockTime - startClockTime);
            
            [newScope setObject:[NSNumber numberWithDouble:totalRunTime] forKey:OSUTotalRunTimeKey];
        }
    }

    // Run count
    {
        NSNumber *runCountNumber = [oldScope objectForKey:OSUNumberOfRunsKey];
        if (runCountNumber && ![runCountNumber isKindOfClass:[NSNumber class]]) {
            OBASSERT([runCountNumber isKindOfClass:[NSNumber class]]);
            runCountNumber = nil;
        }
        unsigned int runCount = [runCountNumber unsignedIntValue];
        
        if (newRun) 
            runCount += 1;
        [newScope setObject:[NSNumber numberWithUnsignedInt:runCount] forKey:OSUNumberOfRunsKey];
    }
    
    // Crash count
    {
        NSNumber *crashCountNumber = [oldScope objectForKey:OSUNumberOfCrashesKey];
        if (crashCountNumber && ![crashCountNumber isKindOfClass:[NSNumber class]]) {
            OBASSERT([crashCountNumber isKindOfClass:[NSNumber class]]);
            crashCountNumber = nil;
        }
        
        unsigned int crashCount = [crashCountNumber unsignedIntValue];
        
        if (crashed)
            crashCount++;
        
        [newScope setObject:[NSNumber numberWithUnsignedInt:crashCount] forKey:OSUNumberOfCrashesKey];
    }
    
    return newScope;
}

// This takes a bundle identifier so that the OmniCrashCatcher app can invoke this for us when we crash.
// Add (now - start) to our total run duration and remove the defaults for the start time.
void OSURunTimeApplicationDeactivated(NSString *appIdentifier, NSString *bundleVersion, BOOL crashed)
{
    OBPRECONDITION(appIdentifier);
    OBPRECONDITION(bundleVersion);
    
    OSU_RUNTIME_DEBUG(1, @"Deactivating %@%@", appIdentifier, crashed ? @" for crash" : @" normally");

    if (!crashed && !OSURunTimeHasRunningSession) {
        OSU_RUNTIME_DEBUG(1, @"   ... no deactivation needed");
        return;
    }
    
    OSURunTimeHasRunningSession = NO;

    NSNumber *startClockTimeNumber = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)OSULastRunStartClockTimeKey, (CFStringRef)appIdentifier));
    OBASSERT(startClockTimeNumber == nil || [startClockTimeNumber isKindOfClass:[NSNumber class]]);
    if (![startClockTimeNumber isKindOfClass:[NSNumber class]])
        startClockTimeNumber = nil;

    NSDictionary *statisticsValue = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)OSURunTimeStatisticsKey, (CFStringRef)appIdentifier));
    if (statisticsValue && ![statisticsValue isKindOfClass:[NSDictionary class]]) {
        OBASSERT([statisticsValue isKindOfClass:[NSDictionary class]]);
        statisticsValue = nil;
    }
    
    NSDictionary *statistics = statisticsValue ? [statisticsValue copy] : [NSDictionary dictionary];

    unsigned currentClockTime = OSUGetCurrentClockTime();
    static BOOL firstCallForThisRun = YES;
    
    NSDictionary *all = _OSURunTimeUpdateStatisticsScope([statistics objectForKey:OSURunTimeStatisticsAllVersionsScopeKey], nil/*version*/, startClockTimeNumber, currentClockTime, crashed, firstCallForThisRun);
    NSDictionary *current = _OSURunTimeUpdateStatisticsScope([statistics objectForKey:OSURunTimeStatisticsCurrentVersionsScopeKey], bundleVersion, startClockTimeNumber, currentClockTime, crashed, firstCallForThisRun);
    
    statistics = [[NSDictionary alloc] initWithObjectsAndKeys:all, OSURunTimeStatisticsAllVersionsScopeKey, current, OSURunTimeStatisticsCurrentVersionsScopeKey, nil];
    OSU_RUNTIME_DEBUG(1, @"   ... setting statistics to %@", statistics);

    CFPreferencesSetAppValue((CFStringRef)OSURunTimeStatisticsKey, (CFDictionaryRef)statistics, (CFStringRef)appIdentifier);
    
    CFPreferencesSetAppValue((CFStringRef)OSULastRunStartClockTimeKey, NULL, (CFStringRef)appIdentifier);

    if (crashed) {
        // This might be a known crash. Signal that the next time the app runs, it should do a software update check by setting the last successful check date to the distant past (where nil may mean that we've never tried and should wait for the full check interval before doing another).
        NSDate *lastCheckDate = [NSDate distantPast];
        CFPreferencesSetAppValue((CFStringRef)OSULastSuccessfulCheckDateKey, (__bridge CFPropertyListRef)(lastCheckDate), (CFStringRef)appIdentifier);
        OSU_RUNTIME_DEBUG(1, @"   ... setting last software update check to %@", lastCheckDate);
    }
    
    CFPreferencesAppSynchronize((CFStringRef)appIdentifier);
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    [[NSProcessInfo processInfo] enableSuddenTermination];
#endif
    
    // On iOS, let the crash cleanup go through w/o flagging this
    if (!crashed)
        firstCallForThisRun = NO;
}

// This gets called from within a short-lived tool.  We'll feel free to leak.
static void _OSURunTimeAddStatisticsToInfo(NSMutableDictionary *info, NSDictionary *scope, NSString *prefix)
{
    [info setObject:[NSString stringWithFormat:@"%u", [[scope objectForKey:OSUNumberOfRunsKey] unsignedIntValue]] forKey:[NSString stringWithFormat:@"%@nrun", prefix]];
    [info setObject:[NSString stringWithFormat:@"%u", [[scope objectForKey:OSUNumberOfCrashesKey] unsignedIntValue]] forKey:[NSString stringWithFormat:@"%@ndie", prefix]];
    
    // We'll report integral minutes instead of seconds.  We can go more than 8000 years with this w/o overflowing 32 bits.
    NSNumber *runTimeNumber = [scope objectForKey:OSUTotalRunTimeKey];
    NSTimeInterval runTime = runTimeNumber ? [runTimeNumber doubleValue] : 0.0;
    
    unsigned long runMinutes = (unsigned long)floor(runTime / 60.0);
    [info setObject:[NSString stringWithFormat:@"%lu", runMinutes] forKey:[NSString stringWithFormat:@"%@runmin", prefix]];
}

void OSURunTimeAddStatisticsToInfo(NSString *appIdentifier, NSMutableDictionary *info)
{
    NSDictionary *statistics = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)OSURunTimeStatisticsKey, (CFStringRef)appIdentifier));
    if (!statistics || ![statistics isKindOfClass:[NSDictionary class]])
        statistics = nil;
    
    _OSURunTimeAddStatisticsToInfo(info, [statistics objectForKey:OSURunTimeStatisticsAllVersionsScopeKey], @"t");
    _OSURunTimeAddStatisticsToInfo(info, [statistics objectForKey:OSURunTimeStatisticsCurrentVersionsScopeKey], @"");
}
