// Copyright 2001-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUChecker.h"

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/OFController.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFScheduledEvent.h>
#import <OmniFoundation/OFScheduler.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#endif

#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSUserDefaults-OFExtensions.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniBase/OmniBase.h>

#import "OSUFeatures.h"

#if OSU_FULL
    #import "OSUController.h"
    #import "OSUItem.h"
#elif (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)
    #import "OSUPrivacyAlertWindowController.h"
#endif
#import "OSUPreferences.h"
#import "OSURunTime.h"
#import "OSUCheckOperation.h"
#import "OSUErrors.h"
#import "OSUAppcastSignature.h"
#import "InfoPlist.h"
#import "OSUCheckerTarget.h"

RCS_ID("$Id$");

static NSInteger OSUDebug = NSIntegerMax;
#define OSU_DEBUG(level, format, ...) do { \
    if (OSUDebug >= (level)) \
        NSLog(@"OSU: " format, ## __VA_ARGS__); \
} while (0)

#ifdef DEBUG
#define ITEM_DEBUG(...) do{ if(OSUItemDebug) NSLog(__VA_ARGS__); }while(0)
#else
#define ITEM_DEBUG(...) do{  }while(0)
#endif

#define VERIFY_APPCAST 1

#if 0 && defined(DEBUG_correia)
    #undef VERIFY_APPCAST
    #define VERIFY_APPCAST 0
#endif

#if (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE) && !OSU_FULL
// Need a stub target for checks
@interface OSUSystemInfoController : NSObject <OSUCheckerTarget>
@end
@implementation OSUSystemInfoController

- (OSUPrivacyNoticeResult)checker:(OSUChecker *)checker runPrivacyNoticePanelHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;
{
    OSUPrivacyAlertWindowController *alert = [[[OSUPrivacyAlertWindowController alloc] init] autorelease];
    return [alert runHavingSeenPreviousVersion:hasSeenPreviousVersion];
}

@end
#endif

// Strings of interest
static NSString * const OSUDefaultCurrentVersionsURLString = @"http://update.omnigroup.com/appcast/";  // Must end in '/' for the path appending to not replace the last component

// Info.plist keys
static NSString * const OSUBundleCheckAtLaunchKey = @"OSUSoftwareUpdateAtLaunch";
static NSString * const OSUBundleCheckerClassKey = @"OSUCheckerClass";
static NSString * const OSUBundleTrackInfoKey = @"OSUSoftwareUpdateTrack";
static NSString * const OSUBundleLicenseTypeKey = @"OSUSoftwareUpdateLicenseType";

// Preferences keys
static NSString * const OSUCurrentVersionsURLKey = @"OSUCurrentVersionsURL";
static NSString * const OSUNewestVersionNumberLaunchedKey = @"OSUNewestVersionNumberLaunched";

#define _OSUVersionNumberString(v) NSSTRINGIFY(v)
#define OSUVersionNumberString _OSUVersionNumberString(OSU_VERSION_NUMBER)

static OFVersionNumber *OSUVersionNumber = nil;
static NSURL *OSUCurrentVersionsURL = nil;

// 
NSString * const OSULicenseTypeUnset = @"unset";
NSString * const OSULicenseTypeNone = @"none";
NSString * const OSULicenseTypeRegistered = @"registered";
NSString * const OSULicenseTypeRetail = @"retail";
NSString * const OSULicenseTypeBundle = @"bundle";
NSString * const OSULicenseTypeTrial = @"trial";
NSString * const OSULicenseTypeExpiring = @"expiring";
NSString * const OSULicenseTypeAppStore = @"appstore";

#define MINIMUM_CHECK_INTERVAL (60.0 * 15.0) // Cannot automatically check more frequently than every fifteen minutes

@interface OSUChecker ()
@property(nonatomic,retain) id <OSUCheckerTarget> target;
@end

@implementation OSUChecker

static inline BOOL _hasScheduledCheck(OSUChecker *self)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return self->_automaticUpdateTimer != nil;
#else
    return self->_automaticUpdateEvent != nil;
#endif
}

static inline NSDate *_scheduledCheckFireDate(OSUChecker *self)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return [self->_automaticUpdateTimer fireDate];
#else
    return [self->_automaticUpdateEvent date];
#endif
}

static inline void _scheduleCheckForDate(OSUChecker *self, NSDate *date)
{
    OBASSERT(!_hasScheduledCheck(self));
    
    OSU_DEBUG(1, @"Scheduling check for %@ (%f seconds from now)", date, [date timeIntervalSinceNow]);
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    self->_automaticUpdateTimer = [[NSTimer alloc] initWithFireDate:date interval:0 target:self selector:@selector(_initiateCheck) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:self->_automaticUpdateTimer forMode:NSRunLoopCommonModes];
#else
    self->_automaticUpdateEvent = [[OFScheduledEvent alloc] initWithInvocation:[[[OFInvocation alloc] initForObject:self selector:@selector(_initiateCheck)] autorelease] atDate:date];
    [[OFScheduler mainScheduler] scheduleEvent:self->_automaticUpdateEvent];
#endif
}

static inline void _cancelScheduledCheck(OSUChecker *self)
{
    if (!_hasScheduledCheck(self))
        return;
    
    OSU_DEBUG(1, @"Cancelling scheduled check");

    OBRetainAutorelease(self);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [self->_automaticUpdateTimer invalidate];
    [self->_automaticUpdateTimer release];
    self->_automaticUpdateTimer = nil;
#else
    [[OFScheduler mainScheduler] abortEvent:self->_automaticUpdateEvent];
    [self->_automaticUpdateEvent release];
    self->_automaticUpdateEvent = nil;
#endif
}

#ifdef OMNI_ASSERTIONS_ON
static void OSUAtExitHandler(void)
{
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    // All we do is check that there is no error in the termination handling logic.  It might not be safe to use NSUserDefaults/CFPreferences at this point and it isn't the end of the world if this doesn't record perfect stats.
    OBASSERT(OSURunTimeHasHandledApplicationTermination() == YES);
    [p release];
}
#endif

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFInitializeDebugLogLevel(OSUDebug);
    
#ifdef OMNI_ASSERTIONS_ON
    atexit(OSUAtExitHandler);
#endif

#if 0 && defined(DEBUG)
    // Useful if you are checking various cases for timed checking
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate dateWithTimeIntervalSinceNow:60] forKey:OSUNextCheckKey];
#endif
}

// On the Mac, we'll automatically start when OFController gets running. On iOS we don't have OBPostLoader or OFController and apps must call +startWithTarget: and +shutdown
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
+ (void)didLoad;
{
    [[OFController sharedController] addObserver:(id)self];
}
#endif

static OSUChecker *sharedChecker = nil;

+ (OSUChecker *)sharedUpdateChecker;
{
    if (sharedChecker == nil) {
        Class checkerClass = nil;
        NSString *className = [[[NSBundle mainBundle] infoDictionary] objectForKey:OSUBundleCheckerClassKey];
        if (![NSString isEmptyString:className]) {
            checkerClass = NSClassFromString(className);
            OBASSERT(checkerClass != nil);
        }
        if (checkerClass == nil)
            checkerClass = self;
        
        sharedChecker = [[checkerClass alloc] init];
    }
    return sharedChecker;
}

+ (OFVersionNumber *)OSUVersionNumber;
{
    OBPRECONDITION(OSUVersionNumber);
    return OSUVersionNumber;
}

static BOOL OSUCheckerRunning = NO;

static NSString *OSUBundleVersionForBundle(NSBundle *bundle)
{
    NSString *version = [[bundle infoDictionary] objectForKey:@"CFBundleVersion"];
    
    OBPOSTCONDITION(version);
    OBPOSTCONDITION([version isKindOfClass:[NSString class]]);
    
    return version;
}

#pragma mark -
#pragma mark Activation / Deactivation

// On iOS, lifecycle notifications are managed externally, currently via OSUController.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
+ (void)applicationDidBecomeActive:(NSNotification *)notification;
{
    if (OSURunTimeHasHandledApplicationTermination()) {
        NSBundle *bundle = [NSBundle mainBundle];
        OSURunTimeApplicationActivated([bundle bundleIdentifier], OSUBundleVersionForBundle(bundle));
    }
}

+ (void)applicationDidResignActive:(NSNotification *)notification;
{
    NSBundle *bundle = [NSBundle mainBundle];
    OSURunTimeApplicationDeactivated([bundle bundleIdentifier], OSUBundleVersionForBundle(bundle), NO/*crashed*/);
}
#endif

#pragma mark -
#pragma mark Start / Terminate

+ (void)startWithTarget:(id <OSUCheckerTarget>)target;
{
    OSU_DEBUG(1, @"Starting with target %@", [(id)target shortDescription]);
    
    OBPRECONDITION(OSUCheckerRunning == NO);
    
    OSUCheckerRunning = YES;
    
    // Looking up defaults values here instead of in +initialize since entries from the app plist might not be registered yet (preventing site licensees from changing their app bundle to provide a local OSU plist).

    // We cannot use OSUBundleVersionForBundle(OMNI_BUNDLE) here, at least for iOS. In that case there is only one bundle and we don't have an Info.plist for OmniSoftwareUpdate.framework at all.
    if (!OSUVersionNumber) {
        NSString *versionString = OSUVersionNumberString;
        OSUVersionNumber = [[OFVersionNumber alloc] initWithVersionString:versionString];
        OBASSERT(OSUVersionNumber);
    }
    
    if (!OSUCurrentVersionsURL) {
        NSString *urlString = [[[[NSUserDefaults standardUserDefaults] stringForKey:OSUCurrentVersionsURLKey] copy] autorelease];
        if ([NSString isEmptyString:urlString])
            urlString = OSUDefaultCurrentVersionsURLString;
        
        OSUCurrentVersionsURL = [[NSURL URLWithString:urlString] retain];
    }
    
    OSUChecker *checker = [self sharedUpdateChecker];
    [checker setTarget:target];
    
    // On iOS/MAS we currently ignore the results and don't care what track we are on. OSUItem isn't part of the OmniSystemInfo/OmniSoftwareUpdateTouch subset (and would need work to avoid using NSXMLDocument on iOS).
#if OSU_FULL
    {
        /* Add our release track to the list of release tracks the user might be interested in seeing (unless it's already there, which is the common case of course) */
        NSString *runningTrack = [checker applicationTrack];
        NSArray *stickyTracks = [OSUPreferences visibleTracks];
        
        if (![NSString isEmptyString:runningTrack]) {
            if (!stickyTracks || ![stickyTracks containsObject:runningTrack]) {
                NSMutableArray *concat = [NSMutableArray array];
                [concat addObject:runningTrack];
                if (stickyTracks)
                    [concat addObjectsFromArray:stickyTracks];
                [OSUPreferences setVisibleTracks:[OSUItem dominantTracks:concat]];
            }
        }
    }
#endif
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:checker selector:@selector(_significantTimeChangeNotification:) name:UIApplicationSignificantTimeChangeNotification object:nil];
#endif
    
    NSBundle *bundle = [NSBundle mainBundle];
    OSURunTimeApplicationActivated([bundle bundleIdentifier], OSUBundleVersionForBundle(bundle));
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // The iPad version of OSUController handles telling us about application lifecycle changes
#else
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidResignActive:) name:NSApplicationDidResignActiveNotification object:nil];
#endif
    
    if ([target respondsToSelector:@selector(checkerDidStart:)])
        [target checkerDidStart:checker];
}

+ (void)shutdown;
{
    OSU_DEBUG(1, @"Shutting down");
    
    OBPRECONDITION(OSUCheckerRunning == YES);
    
    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard
    if (OSUCheckerRunning == NO)
        return;
    
    OSUCheckerRunning = NO;
    
    OSUChecker *checker = [self sharedUpdateChecker];
    [checker setTarget:nil];
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:checker name:UIApplicationSignificantTimeChangeNotification object:nil];
#endif
    
    NSBundle *bundle = [NSBundle mainBundle];
    OSURunTimeApplicationDeactivated([bundle bundleIdentifier], OSUBundleVersionForBundle(bundle), NO/*crashed*/);
}

- (id)init;
{
    self = [super init];
    if (self == nil)
        return nil;

    _licenseType = [[[NSBundle mainBundle] infoDictionary] objectForKey:OSUBundleLicenseTypeKey defaultObject:OSULicenseTypeNone];

    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(!_hasScheduledCheck(self)); // Otherwise, it would be retaining us and we wouldn't be being deallocated
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // This shouldn't ever be needed, as the notification is only observed for the shared checker, and is removed on shutdown, but just in case.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationSignificantTimeChangeNotification object:nil];
#endif
    [self _stopWatchingNetworkReachability];
    [_checkTarget release];
    _checkTarget = nil;
    [_licenseType release];
    [super dealloc];
}

- (OFVersionNumber *)applicationMarketingVersion
{
    static OFVersionNumber *version = nil;
    if (!version) {
        NSDictionary *myInfo = [[NSBundle mainBundle] infoDictionary];
        version = [[OFVersionNumber alloc] initWithVersionString:[myInfo objectForKey:@"CFBundleShortVersionString"]];
    }
    return version;
}

- (NSString *)applicationIdentifier;
{
    NSString *applicationIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    
#ifdef DEBUG
    NSString *debugSuffix = @".debug";
    if ([[applicationIdentifier lowercaseString] hasSuffix:debugSuffix]) {
        NSUInteger index = [applicationIdentifier length] - [debugSuffix length];
        applicationIdentifier = [applicationIdentifier substringToIndex:index];
    }
#endif
    
    return applicationIdentifier;
}

- (NSString *)applicationEngineeringVersion;
{
    return OSUBundleVersionForBundle([NSBundle mainBundle]);
}

- (NSString *)applicationTrack;
{
    NSString *track = [[[NSBundle mainBundle] infoDictionary] objectForKey:OSUBundleTrackInfoKey];
    
    // This should be present, with at least the empty string
    OBASSERT(track);
    
    return track;
}

- (BOOL)applicationOnReleaseTrack;
{
    NSString *track = [self applicationTrack];
    return [NSString isEmptyString:track] || [track isEqualToString:@"release"];
}

- (NSString *)licenseType;
{
    return _licenseType;
}

- (void)setLicenseType:(NSString *)licenseType;
{
    [self willChangeValueForKey:OSUCheckerLicenseTypeBinding];
    
    [_licenseType autorelease];
    _licenseType = [licenseType copy];
    
    // Either neither of these should be set or just one of them
    OBASSERT(!_flags.initiateCheckOnLicenseTypeChange || !_flags.scheduleNextCheckOnLicenseTypeChange);
    
    // If we wanted to do a check at startup, we might have delayed it if the licensing system wasn't done figuring stuff out yet.
    if (_flags.initiateCheckOnLicenseTypeChange) {
        _flags.initiateCheckOnLicenseTypeChange = NO;
        [self _initiateCheck];
    }

    // If we wanted to schedule a check, do that
    if (_flags.scheduleNextCheckOnLicenseTypeChange) {
        _flags.scheduleNextCheckOnLicenseTypeChange = NO;
        [self _scheduleNextCheck];
    }

    [self didChangeValueForKey:OSUCheckerLicenseTypeBinding];
}

- (BOOL)checkInProgress
{
    return (_currentCheckOperation != nil)? YES : NO; 
}

// API

- (BOOL)checkSynchronously;
{
    assert(_checkTarget != nil); // +startWithTarget: needs to be called before we start checking

    if ([_checkTarget respondsToSelector:@selector(checkerShouldStartCheck:)] && ![_checkTarget checkerShouldStartCheck:self])
        return NO; // Denied.
    
    @try {
        _cancelScheduledCheck(self);

        // Do this via the task so that hardware collection occurs.
        [self _beginLoadingURLInitiatedByUser:YES];

        if ([_checkTarget respondsToSelector:@selector(checker:didStartCheck:)])
            [_checkTarget checker:self didStartCheck:_currentCheckOperation];

    } @catch (NSException *exc) {
        [self _clearCurrentCheckOperation];
#ifdef DEBUG
        NSLog(@"Exception raised in %s: %@", __PRETTY_FUNCTION__, exc);
#endif	
        [exc raise];
    } @finally {
        [self _scheduleNextCheck];
    }
    
    return YES;
}

- (NSDictionary *)generateReport;
{
    OSUCheckOperation *check = [[[OSUCheckOperation alloc] initForQuery:NO url:OSUCurrentVersionsURL licenseType:_licenseType] autorelease];
    return [check runSynchronously];
}

#pragma mark -
#pragma mark NSObject (OFControllerObserver)

// On the Mac, we'll automatically start when OFController gets running. On iOS we don't have OBPostLoader or OFController and apps must call +startWithTarget: and +shutdown
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
+ (void)controllerStartedRunning:(OFController *)controller;
{
#if OSU_FULL
    [self startWithTarget:[OSUController sharedController]];
#else
    [self startWithTarget:[[[OSUSystemInfoController alloc] init] autorelease]];
#endif
}

+ (void)controllerWillTerminate:(OFController *)controller;
{
    [self shutdown];
}

#endif

#pragma mark -
#pragma mark OFNetReachabilityDelegate

- (void)reachabilityDidUpdate:(OFNetReachability *)reachability reachable:(BOOL)reachable usingCell:(BOOL)usingCell;
{
    OBPRECONDITION(reachability == _netReachability);
    
    OSU_DEBUG(1, @"Network configuration has changed");

    [self _initiateCheck];
}

#pragma mark - NSURLConnection delegates

// On iOS/MAS we don't download track information from the update feed since we ignore the result items anyway.
#if OSU_FULL

/* Zero or more connection:didReceiveResponse: messages will be sent to the delegate before receiving a connection:didReceiveData: message. */
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if (connection == _refreshingTrackInfo) {
        BOOL satisfactory;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            satisfactory = ( [(NSHTTPURLResponse *)response statusCode] <= 399 ) &&
            ( [[response MIMEType] containsString:@"xml"] ) ;
        } else {
            // No way to distinguish successful from unsuccessful responses for non-HTTP protocols? Presumably we'll just get -didFailWithError: for other protocols.
            satisfactory = YES;
        }
        
        [_refreshingTrackData release];
        _refreshingTrackData = nil;
        if (satisfactory)
            _refreshingTrackData = [[NSMutableData alloc] init];
    }
}

/* Zero or more connection:didReceiveData: messages will be sent */
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    /* It's a pity that Apple has no easy to use push- or stream- parser interface */
    if (connection == _refreshingTrackInfo && nil != _refreshingTrackData)
        [_refreshingTrackData appendData:data];
}

/* Unless a NSURLConnection receives a cancel message, the delegate will receive one and only one of connectionDidFinishLoading:, or connection:didFailWithError: message, but never both. */

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if (connection == _refreshingTrackInfo) {
        [_refreshingTrackInfo autorelease];
        _refreshingTrackInfo = nil;
        [_refreshingTrackData release];
        _refreshingTrackData = nil;
        
        NSLog(@"Couldn't fetch track text: %@", [error description]);
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (connection == _refreshingTrackInfo) {
        [_refreshingTrackInfo autorelease];
        _refreshingTrackInfo = nil;
        
        NSError *xmlError = nil;
        NSXMLDocument *document = [[[NSXMLDocument alloc] initWithData:_refreshingTrackData options:NSXMLNodeOptionsNone error:&xmlError] autorelease];
        [_refreshingTrackData release];
        _refreshingTrackData = nil;
        
        if (!document) {
            NSLog(@"Can't parse track text: %@", [xmlError description]);
        } else {
            [OSUItem processTrackInformation:document];
        }
    }
}

#endif

#pragma mark -
#pragma mark Private

@synthesize target = _checkTarget;
- (void)setTarget:(id <OSUCheckerTarget>)target;
{
    OBPRECONDITION(!target || [target conformsToProtocol:@protocol(OSUCheckerTarget)]);
    
    [_checkTarget release];
    _checkTarget = [target retain];
    
    _flags.shouldCheckAutomatically = [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue];
    _currentCheckOperation = nil;
    _cancelScheduledCheck(self);
    
    if (_checkTarget) {
        if ([self _shouldCheckAtLaunch]) {
            // Do a check immediately, unless our license type isn't set; licensing system is still processing stuff in this case.
            if (OFNOTEQUAL(_licenseType, OSULicenseTypeUnset))
                [self _initiateCheck];
            else
                _flags.initiateCheckOnLicenseTypeChange = YES;
        } else {
            // As above, only schedule if we have our license type set already.
            if (OFNOTEQUAL(_licenseType, OSULicenseTypeUnset))
                [self _scheduleNextCheck];
            else
                _flags.scheduleNextCheckOnLicenseTypeChange = YES;
        }
    
        [OFPreference addObserver:self selector:@selector(_softwareUpdatePreferencesChanged:) forPreference:[OSUPreferences automaticSoftwareUpdateCheckEnabled]];
        [OFPreference addObserver:self selector:@selector(_softwareUpdatePreferencesChanged:) forPreference:[OSUPreferences checkInterval]];
    } else {
        [OFPreference removeObserver:self forPreference:[OSUPreferences automaticSoftwareUpdateCheckEnabled]];
        [OFPreference removeObserver:self forPreference:[OSUPreferences checkInterval]];
    }
}

- (BOOL)_shouldCheckAtLaunch;
{
#if 0 && defined(DEBUG)
    return YES;
#endif

    if (![self _shouldCheckAutomatically])
        return NO;

    NSDictionary *myInfo = [[NSBundle mainBundle] infoDictionary];
    id checkAtLaunch = [myInfo objectForKey:OSUBundleCheckAtLaunchKey];
    if (checkAtLaunch == nil || ![checkAtLaunch boolValue])
        return NO;

    OFVersionNumber *currentlyRunningVersionNumber = [[[OFVersionNumber alloc] initWithVersionString:[self applicationEngineeringVersion]] autorelease];
    if (currentlyRunningVersionNumber == nil) {
#ifdef DEBUG
        NSLog(@"Unable to compute version number of this app");
#endif
        return NO;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *newestVersionNumberLaunchedString = [defaults stringForKey:OSUNewestVersionNumberLaunchedKey];
    if (![NSString isEmptyString:newestVersionNumberLaunchedString]) {
        OFVersionNumber *newestVersionNumberLaunched = [[[OFVersionNumber alloc] initWithVersionString:newestVersionNumberLaunchedString] autorelease];

        if ([currentlyRunningVersionNumber compareToVersionNumber:newestVersionNumberLaunched] != NSOrderedDescending)
            return NO; // This version is the same or older than the version we ran at last launch
    }

    [defaults setObject:[currentlyRunningVersionNumber cleanVersionString] forKey:OSUNewestVersionNumberLaunchedKey];

    return YES;
}

- (BOOL)_shouldCheckAutomatically;
{
    // Disallow automatic checks if we are a debug build; attached to the debugger.
    // You can still trigger a manual check to debug Software Update, or turn this off if necessary.
    
#ifdef DEBUG
    if (OBIsBeingDebugged())
        return NO;
#endif
    
    return _flags.shouldCheckAutomatically;
}

- (void)_scheduleNextCheck;
{
    // Make sure we haven't been disabled
    if (![[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue])
        _flags.shouldCheckAutomatically = 0;

    if (![self _shouldCheckAutomatically] || _currentCheckOperation) {
        _cancelScheduledCheck(self);
        return;
    }
    
    // Determine when we should make the next check
#if 0 && defined(DEBUG)
    NSTimeInterval checkInterval = 60;
#else
    NSTimeInterval checkInterval = MAX([[OSUPreferences checkInterval] floatValue] * 60.0 * 60.0, MINIMUM_CHECK_INTERVAL);
#endif
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDate *now = [NSDate date];
    NSDate *nextCheckDate = [defaults objectForKey:OSUNextCheckKey];
    if (nextCheckDate == nil || ![nextCheckDate isKindOfClass:[NSDate class]] ||
        ([nextCheckDate timeIntervalSinceDate:now] > checkInterval)) {
        nextCheckDate = [[NSDate alloc] initWithTimeInterval:checkInterval sinceDate:now];
        [nextCheckDate autorelease];
        [defaults setObject:nextCheckDate forKey:OSUNextCheckKey];
    }
    
    if (_hasScheduledCheck(self)) {
        if(fabs([_scheduledCheckFireDate(self) timeIntervalSinceDate:nextCheckDate]) < 1.0) {
            // We already have a scheduled check at the time we would be scheduling one, so we don't need to do anything.
            return;
        } else {
            // We have a scheduled check at a different time. Cancel the existing event and add a new one.
            _cancelScheduledCheck(self);
        }
    }
    
    _scheduleCheckForDate(self, nextCheckDate);
}

- (void)_initiateCheck;
{    
    if (_currentCheckOperation)
        return;
    
    if ([self _postponeCheckForURL])
        return; // um, never mind.

    [self _beginLoadingURLInitiatedByUser:NO];
}

- (void)_beginLoadingURLInitiatedByUser:(BOOL)initiatedByUser;
{
    if (![self _shouldLoadAfterWarningUserAboutNewVersion]) {
        // This is a hack to avoid a panel saying that there are no updates.  Instead, we should probably have an enum for the status
        return;
    }
    
    [self _clearCurrentCheckOperation];
    
    [self willChangeValueForKey:OSUCheckerCheckInProgressBinding];
    _currentCheckOperation = [[OSUCheckOperation alloc] initForQuery:YES url:OSUCurrentVersionsURL licenseType:_licenseType];
    _currentCheckOperation.initiatedByUser = initiatedByUser;
    [self didChangeValueForKey:OSUCheckerCheckInProgressBinding];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_checkOperationCompleted:) name:OSUCheckOperationCompletedNotification object:_currentCheckOperation];
    [_currentCheckOperation runAsynchronously];
}

- (void)_clearCurrentCheckOperation;
{
    if (_currentCheckOperation) {
        [self willChangeValueForKey:OSUCheckerCheckInProgressBinding];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:OSUCheckOperationCompletedNotification object:_currentCheckOperation];
        [_currentCheckOperation release];
        _currentCheckOperation = nil;
        [self didChangeValueForKey:OSUCheckerCheckInProgressBinding];
    }
}

- (void)_checkOperationCompleted:(NSNotification *)note;
{
    if ([note object] != _currentCheckOperation) {
        OBASSERT([note object] == _currentCheckOperation);
        return;
    }
    
    // The fetch subprocess has completed.
    NSDictionary *output = _currentCheckOperation.output;
    NSError *error = nil;
    if (!output) {
        error = _currentCheckOperation.error;
        OBASSERT(error);
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fetch software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - will be followed by more detailed error reason");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Check operation failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - tried to run a check operation to fetch software update information, but it exited with an error code");
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, error, NSUnderlyingErrorKey, nil];
        error = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToFetchSoftwareUpdateInformation userInfo:userInfo];
    }
    
    NSDictionary *results = nil;
    if (!error) {
        results = output;
        NSDictionary *errorDict = [results objectForKey:OSUCheckResultsErrorKey];
        error = errorDict ? [[[NSError alloc] initWithPropertyList:errorDict] autorelease] : nil;
    }
    
    [self _clearCurrentCheckOperation]; // Done with _currentCheckOperation from this point forward
    
    if ([error hasUnderlyingErrorDomain:OSUErrorDomain code:OSULocalNetworkFailure]) {
        if (!_netReachability) {
            [self _startWatchingNetworkReachability];
            return;
        }
    }
    
    NSData *data = [results objectForKey:OSUCheckResultsDataKey];
    if (!error && !data) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fetch software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - will be followed by more detailed error reason");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Tool returned no data", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - we ran a helper tool to fetch software update information, but it didn't return any information");
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
        error = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToFetchSoftwareUpdateInformation userInfo:userInfo];
    }
    
    
    OSUCheckOperation *operation = [note object];
    if (!error) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:OSUNextCheckKey];
        // Removing the nextCheckKey will cause _scheduleNextCheck to schedule a check in the future

#if OSU_FULL
        [self _interpretSoftwareUpdateData:data operation:operation error:&error];
#endif
    }
    
    if (error) {
        if ([_checkTarget respondsToSelector:@selector(checker:check:failedWithError:)])
            [_checkTarget checker:self check:operation failedWithError:error];
        else
            NSLog(@"Check operation %@ failed with error: %@", operation, [error toPropertyList]);
    } else
        // Only schedule a check if there was no error.  Note that if the user manually performs a check after this has happened, the automatic checking should start up again.
        [self _scheduleNextCheck];
}

// On iOS/MAS we ignore the results of the feed since this would require much more porting and is of limited utility anyway. We could eventually do this and be able to tell the user about updates, but they'd have to go to the App Store app to install them anyway.
#if OSU_FULL
- (BOOL)_interpretSoftwareUpdateData:(NSData *)data operation:(OSUCheckOperation *)operation error:(NSError **)outError;
{
    OBPRECONDITION(data);
    
    if (outError)
        *outError = nil;
    
#ifndef VERIFY_APPCAST
#error "Expected VERIFY_APPCAST to be defined (and very likely have a value of 1)"
#endif

#if VERIFY_APPCAST
    NSString *trust = [OMNI_BUNDLE pathForResource:@"AppcastTrustRoot" ofType:@"pem"];
    if (trust) {
        OSU_DEBUG(1, @"Using %@", trust);

        NSArray *verifiedPortions = OSUGetSignedPortionsOfAppcast(data, trust, outError);
        if (!verifiedPortions || ![verifiedPortions count]) {
            if (outError) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to authenticate the response from the software update server.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - we have some update information but it doesn't look authentic");
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
                
                if (!verifiedPortions) {
                    NSString *reason = NSLocalizedStringFromTableInBundle(@"There was a problem checking the signature.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - the checksum or signature didn't match - more info in underlying error");
                    [userInfo setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
                    [userInfo setObject:*outError forKey:NSUnderlyingErrorKey];
                } else {
                    NSString *reason = NSLocalizedStringFromTableInBundle(@"The update information is not signed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - the update information wasn't signed at all, but we require it to be signed");
                    [userInfo setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
                }
                
                NSURL *serverURL = [operation url];
                if (serverURL)
                    [userInfo setObject:[serverURL absoluteString] forKey:NSURLErrorFailingURLStringErrorKey];
                
                *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToParseSoftwareUpdateData userInfo:userInfo];
            }
            
            return NO;
        }
        
        if ([verifiedPortions count] != 1) {
            NSLog(@"Warning: Update contained %lu reference nodes; only using the first.", [verifiedPortions count]);
        }
        
        data = [verifiedPortions objectAtIndex:0];
    } else {
        NSLog(@"OSU: Verification has been disabled. Unauthentic updates may be accepted.");
    }
#else
    NSLog(@"OSU: Verification has been disabled in this configuration. Unauthentic updates may be accepted.");
#endif
    
    NSXMLDocument *document = [[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:outError] autorelease];
    if (!document) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to parse response from the software update server.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The data returned from <%@> was not a valid XML document.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description"), [[operation url] absoluteString]];
            
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
            if (outError && *outError)
                [userInfo setObject:*outError forKey:NSUnderlyingErrorKey];
        
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToParseSoftwareUpdateData userInfo:userInfo];
        }
        return NO;
    }
    
    NSArray *nodes = [document nodesForXPath:@"/rss/channel/item" error:outError];
    if (!nodes)
        return NO;
    
    OFVersionNumber *currentVersion = [[[OFVersionNumber alloc] initWithVersionString:[self applicationEngineeringVersion]] autorelease];
    NSString *currentTrack = [self applicationTrack];

    BOOL showOlderVersions = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUIncludeVersionsOlderThanCurrentVersion"];
    
    NSError *firstError = nil;
    NSMutableArray *items = [NSMutableArray array];
    NSUInteger nodeIndex = [nodes count];
    while (nodeIndex--) {
        NSError *itemError = nil;
        OSUItem *item = [[[OSUItem alloc] initWithRSSElement:[nodes objectAtIndex:nodeIndex] error:&itemError] autorelease];
        if (!item) {
            ITEM_DEBUG(@"Unable to interpret node %@ as a software update: %@", [nodes objectAtIndex:nodeIndex], itemError);
            if (!firstError)
                firstError = itemError;
        } else if ([currentVersion compareToVersionNumber:[item buildVersion]] == NSOrderedAscending) {
            // Include the item if it is newer than us; the RSS feed does not filter this on our behalf.
            [items addObject:item];
            ITEM_DEBUG(@"Using %@: version %@ > app %@", [item shortDescription], [[item buildVersion] cleanVersionString], [currentVersion cleanVersionString]);
        } else {
            item.isOldStable = YES;
            if (showOlderVersions) {
                // Including everything the feed sent us, even if it's older than us.
                [items addObject:item];
                ITEM_DEBUG(@"Using %@: showing old versions by preference", [item shortDescription]);
            } else {
                // Include an older release only if it's more stable: this allows someone to go back to a beta or full release version if they tried out the sneakypeek, for example.
                enum OSUTrackComparison cmp = [OSUItem compareTrack:[item track] toTrack:currentTrack];
                BOOL useIt = ( cmp == OSUTrackMoreStable );
                if (useIt)
                    [items addObject:item];
                ITEM_DEBUG(@"%@ %@: older, and item track %@ vs app track %@ = %d",
                           ( useIt ? @"Using" : @"Skipping" ),
                           [item shortDescription], [item track], currentTrack, cmp);
            }
        }
    }
    
    // If we had some matching nodes, but none were usable, return the error for the first
    if ([nodes count] > 0 && [items count] == 0 && firstError) {
        if (outError)
            *outError = firstError;
        return NO;
    }

    // If it looks like we'll display anything, retrieve the track descriptions and up-to-date orderings
    if ([items count] > 0 && !_refreshingTrackInfo) {
        NSArray *trackInfoAttributes = [document objectsForXQuery:[NSString stringWithFormat:@"declare namespace oac = \"%@\";\n /rss/channel/attribute::oac:trackinfo", OSUAppcastTrackInfoNamespace] error:NULL];
        if ([trackInfoAttributes count]) {
            NSURL *trackInfoURL = [NSURL URLWithString:[[trackInfoAttributes objectAtIndex:0] stringValue]];
            if (trackInfoURL) {
                NSMutableURLRequest *infoRequest = [NSMutableURLRequest requestWithURL:trackInfoURL];
                [infoRequest setValue:[[operation url] absoluteString] forHTTPHeaderField:@"Referer" /* sic */];
                _refreshingTrackInfo = [[NSURLConnection alloc] initWithRequest:infoRequest delegate:self];
                OBASSERT(_refreshingTrackData == nil); 
            }
        }
    }
    
    [items makeObjectsPerformSelector:@selector(setAvailablityBasedOnSystemVersion:) withObject:[OFVersionNumber userVisibleOperatingSystemVersionNumber]];
    [OSUItem setSupersededFlagForItems:items];
    
    if ([_checkTarget respondsToSelector:@selector(checker:newVersionsAvailable:fromCheck:)])
        // Note that we go ahead and pass ignored items to the check target; it will handle the ignored flag
        [_checkTarget checker:self newVersionsAvailable:[items filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededPredicate]] fromCheck:operation];
    
    return YES;
}
#endif

- (BOOL)_hostAppearsToBeReachable;
{
    OBPRECONDITION(OSUCurrentVersionsURL);
    OBPRECONDITION([OSUCurrentVersionsURL isFileURL] == NO);
    
    NSString *hostname = [OSUCurrentVersionsURL host];
    
    if ([hostname isEqualToString:@"localhost"])
        return YES;  // ummm, I guess so
    
    // Can't represent the hostname as an ASCII C string --- it's probably bogus. (Might fail when/if unicode DNS ever happens, but we'd need to fix this code to handle that, and it won't affect us unless Omni gets a new domain anyway...
    if (![hostname canBeConvertedToEncoding:NSASCIIStringEncoding]) {
        OBASSERT_NOT_REACHED("Non-ASCII host name");
        return NO;
    }
    
    // Try to start watching network reachability for our URL.
    if (_netReachability == nil && ![self _startWatchingNetworkReachability]) {
        // Failed to set up the network reachability query. Bail.
        return NO;
    }
    
    if (_netReachability == nil) {
        OBASSERT_NOT_REACHED("-_startWatchingNetworkReachability should have returned NO in this case"); // clang
        return NO;
    }
    
    // May still be NO if the query takes a while to resolve, but then we expect the delegate hook to be pinged.
    BOOL reachable = _netReachability.reachable;
    OSU_DEBUG(1, @"Returning reachable = %d", reachable);
    
    return reachable;
}

- (BOOL)_shouldLoadAfterWarningUserAboutNewVersion;
{
    OBPRECONDITION(OSUVersionNumber);
    OBPRECONDITION(_checkTarget);
    
    // The first time OSU runs for this user, prompt them that we'll send some info to the network.  We check in 'com.omnigroup.OmniSoftwareUpdate' so that the user only gets this panel once for any OSU version rather than getting peppered with it.
    CFStringRef prefKey = CFSTR("OSUHighestRunVersion");
    CFStringRef prefDomain = OSUSharedPreferencesDomain;

    NSString *str = (NSString *)CFPreferencesCopyAppValue(prefKey, prefDomain);
    OFVersionNumber *highestRunVersion = str ? [[[OFVersionNumber alloc] initWithVersionString:str] autorelease] : nil;
    [str release];
    
    if (highestRunVersion && [highestRunVersion compareToVersionNumber:OSUVersionNumber] != NSOrderedAscending)
        return YES;

    // Unconditionally update preferences so that this panel doesn't come up again.
    CFPreferencesSetAppValue(prefKey, [OSUVersionNumber cleanVersionString], prefDomain);
    CFPreferencesAppSynchronize(prefDomain);

    // Version 2009 actually sends the same info as all versions since 2004, but does so in a different format. No need to re-ask the user about details of transfer encoding.
    if (highestRunVersion != nil && OSUVersionNumber != nil &&
        [highestRunVersion componentCount] >= 1 && [highestRunVersion componentAtIndex:0] >= 2004 && [highestRunVersion componentAtIndex:0] <= 2009 &&
        [OSUVersionNumber componentCount] >= 1 && [OSUVersionNumber componentAtIndex:0] <= 2009) {
        // Manufacture some consent.
        return YES;
    }
    
    BOOL hasSeenPreviousVersion = (highestRunVersion != nil);
    
    OSUPrivacyNoticeResult rc = [_checkTarget checker:self runPrivacyNoticePanelHavingSeenPreviousVersion:hasSeenPreviousVersion];
    if (rc == OSUPrivacyNoticeResultOK)
        return [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue];

    [self _scheduleNextCheck]; // If the user doesn't change their prefs, we'll check sometime in the future automatically.
    return NO;
}

// Returns YES if we should postpone checking because our check URL requires network access but the system isn't connected to the network. This routine is also responsible for setting up or tearing down the connection to the system config daemon which we use to initiate a check when the machine reconnects to the net.
- (BOOL)_postponeCheckForURL;
{
    OBPRECONDITION(OSUCurrentVersionsURL);
    
    BOOL canCheckImmediately;

    NSString *urlScheme = [OSUCurrentVersionsURL scheme];
    if ([urlScheme isEqual:@"file"]) {
        canCheckImmediately = YES;  // filesystem is always available. we hope.
    } else {
        NSString *urlHost = [OSUCurrentVersionsURL host];

        if (urlHost == nil) {   // not sure what's up, but might as well give it a try
            canCheckImmediately = YES;
        } else {
            canCheckImmediately = [self _hostAppearsToBeReachable];
        }
    }

    if (canCheckImmediately && (_netReachability != nil)) {
        // Tear down the network-watching stuff.
        [self _stopWatchingNetworkReachability];
    }

    // Set up the network-watching stuff if necessary.
    if (!canCheckImmediately) {
        BOOL connected;
        
        if (_netReachability == nil)
            connected = [self _startWatchingNetworkReachability];
        else
            connected = YES;

        if (connected) {
            OSU_DEBUG(1, @"Cannot reach host, but will watch for changes.");
        } else {
            OSU_DEBUG(1, @"Cannot connect to configd. Will not automatically perform software update.");
        }
    }

    return (!canCheckImmediately);
}

- (void)_softwareUpdatePreferencesChanged:(NSNotification *)aNotification;
{
    _flags.shouldCheckAutomatically = [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue];
    [self _scheduleNextCheck];
}

- (BOOL)_startWatchingNetworkReachability;
{
    OBPRECONDITION(_netReachability == nil);
    OBPRECONDITION(OSUCurrentVersionsURL);

    NSString *hostname = [OSUCurrentVersionsURL host];
    OBASSERT(![NSString isEmptyString:hostname]);
    
    _netReachability = [[OFNetReachability alloc] initWithHostName:hostname];
    _netReachability.delegate = self;
    
    OSU_DEBUG(1, @"Started network reachability check for %@ -> %@", hostname, _netReachability);
    
    return _netReachability != nil;
}

- (void)_stopWatchingNetworkReachability;
{
    if (_netReachability) {
        OSU_DEBUG(1, @"Stopping network reachability check %@", _netReachability);
    }

    _netReachability.delegate = nil;
    [_netReachability release];
    _netReachability = nil;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)_significantTimeChangeNotification:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread]); // Make sure the timer goes into the right runloop always!
    
    if (!_hasScheduledCheck(self))
        return; // Don't care.
    
    NSDate *date = [_scheduledCheckFireDate(self) copy];
    _cancelScheduledCheck(self);
    _scheduleCheckForDate(self, date);
    [date release];
}
#endif

@end
