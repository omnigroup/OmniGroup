// Copyright 2007-2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSURunTime.h"

#import <Foundation/Foundation.h>
#import <OmniFoundation/OFNull.h> // For OFNOTEQUAL
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

static NSString * const OSULastRunStartIntervalKey = @"OSULastRunStartInterval";

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

static NSInteger OSURuntimeDebug = NSIntegerMax;
#define OSU_RUNTIME_DEBUG(level, format, ...) do { \
    if (OSURuntimeDebug >= (level)) \
        NSLog(@"OSU: " format, ## __VA_ARGS__); \
} while (0)

static void OSURuntimeDebugInitialize(void) __attribute__((constructor));
static void OSURuntimeDebugInitialize(void)
{
    OFInitializeDebugLogLevel(OSURuntimeDebug);
}

BOOL OSURunTimeHasHandledApplicationTermination(void)
{
    return (OSURunTimeHasRunningSession == NO);
}

void OSURunTimeApplicationActivated(NSString *appIdentifier, NSString *bundleVersion)
{
    // Record the time we started this run of the application.  Also, increment the number of runs.
    // If we crash, OCC will handle calculating how long we ran until we crashed.  If we quit normally, we will do it.
    // Thus, if we launch and a preference exists for the 'last start time', then there is a bug.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Can't really OBASSERT on this since it'll fire over and over when in the debugger. So, we just log and only when not building for DEBUG to avoid accumulating log spam.
#if !defined(DEBUG) || defined(DEBUG_kc)
    if ([defaults objectForKey:OSULastRunStartIntervalKey] != nil) {
        NSLog(@"%@ default is non-nil; unless you forcibly killed the app and restarted it it should be nil at launch time.", OSULastRunStartIntervalKey);
        
        // If we aren't in the debugger and we get activated when we don't expect to, then we signal this as a crash. On the Mac, OmniCrashCatcher will have called this on our app's behalf, but on iOS we do it ourselves.
        OSURunTimeApplicationDeactivated(appIdentifier, bundleVersion, YES/*crashed*/);
    }
#endif

    OBASSERT(OSURunTimeHasRunningSession == NO);
    OSURunTimeHasRunningSession = YES;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    [[NSProcessInfo processInfo] disableSuddenTermination];
#endif
    NSNumber *startIntervalNumber = @(now);
    [defaults setObject:startIntervalNumber forKey:OSULastRunStartIntervalKey];
    OSU_RUNTIME_DEBUG(1, @"Activating %@ at %@", appIdentifier, startIntervalNumber);
    
    [defaults synchronize]; // Make sure we save in case we crash before NSUserDefaults automatically synchronizes
}

static NSDictionary *_OSURunTimeUpdateStatisticsScope(NSDictionary *oldScope, NSString *version, NSNumber *startTimeNumber, NSTimeInterval now, BOOL crashed, BOOL newRun)
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
    if (startTimeNumber) {
        NSTimeInterval startTime = [startTimeNumber doubleValue];
        OBASSERT(startTime < now);
        if (startTime < now) {            
            NSNumber *totalRunTimeNumber = [oldScope objectForKey:OSUTotalRunTimeKey];

            if (totalRunTimeNumber && ![totalRunTimeNumber isKindOfClass:[NSNumber class]]) {
                OBASSERT([totalRunTimeNumber isKindOfClass:[NSNumber class]]);
                totalRunTimeNumber = nil;
            }

            NSTimeInterval totalRunTime = totalRunTimeNumber ? [totalRunTimeNumber doubleValue] : 0.0;
            
            totalRunTime += (now - startTime);
            
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
    
    OBPRECONDITION(crashed || OSURunTimeHasRunningSession);
    if (!crashed && !OSURunTimeHasRunningSession)
        return;
    OSURunTimeHasRunningSession = NO;

    NSNumber *startTimeNumber = [(NSNumber *)CFPreferencesCopyAppValue((CFStringRef)OSULastRunStartIntervalKey, (CFStringRef)appIdentifier) autorelease];
    OBASSERT(startTimeNumber == nil || [startTimeNumber isKindOfClass:[NSNumber class]]);
    if (![startTimeNumber isKindOfClass:[NSNumber class]])
        startTimeNumber = nil;

    NSDictionary *statisticsValue = [(NSDictionary *)CFPreferencesCopyAppValue((CFStringRef)OSURunTimeStatisticsKey, (CFStringRef)appIdentifier) autorelease];
    if (statisticsValue && ![statisticsValue isKindOfClass:[NSDictionary class]]) {
        OBASSERT([statisticsValue isKindOfClass:[NSDictionary class]]);
        statisticsValue = nil;
    }
    
    NSDictionary *statistics = statisticsValue ? [[statisticsValue copy] autorelease] : [NSDictionary dictionary];

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    static BOOL firstCallForThisRun = YES;
    
    NSDictionary *all = _OSURunTimeUpdateStatisticsScope([statistics objectForKey:OSURunTimeStatisticsAllVersionsScopeKey], nil/*version*/, startTimeNumber, now, crashed, firstCallForThisRun);
    NSDictionary *current = _OSURunTimeUpdateStatisticsScope([statistics objectForKey:OSURunTimeStatisticsCurrentVersionsScopeKey], bundleVersion, startTimeNumber, now, crashed, firstCallForThisRun);
    
    statistics = [[NSDictionary alloc] initWithObjectsAndKeys:all, OSURunTimeStatisticsAllVersionsScopeKey, current, OSURunTimeStatisticsCurrentVersionsScopeKey, nil];
    OSU_RUNTIME_DEBUG(1, @"Deactivating %@ with %@", appIdentifier, statistics);

    CFPreferencesSetAppValue((CFStringRef)OSURunTimeStatisticsKey, (CFDictionaryRef)statistics, (CFStringRef)appIdentifier);
    [statistics release];
    
    CFPreferencesSetAppValue((CFStringRef)OSULastRunStartIntervalKey, NULL, (CFStringRef)appIdentifier);

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
    NSDictionary *statistics = [(NSDictionary *)CFPreferencesCopyAppValue((CFStringRef)OSURunTimeStatisticsKey, (CFStringRef)appIdentifier) autorelease];
    if (!statistics || ![statistics isKindOfClass:[NSDictionary class]])
        statistics = nil;
    
    _OSURunTimeAddStatisticsToInfo(info, [statistics objectForKey:OSURunTimeStatisticsAllVersionsScopeKey], @"t");
    _OSURunTimeAddStatisticsToInfo(info, [statistics objectForKey:OSURunTimeStatisticsCurrentVersionsScopeKey], @"");
}
