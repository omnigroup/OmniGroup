// Copyright 2001-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUChecker.h>

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
#import <OmniFoundation/OmniFoundation-Swift.h> // for NSProcessInfo-OFExtensions
#import <OmniBase/OmniBase.h>

#import "OSUFeatures.h"

#if OSU_FULL
    #import <OmniSoftwareUpdate/OSUController.h>
    #import "OSUItem.h"
#elif (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)
    #import "OSUPrivacyAlertWindowController.h"
#endif
#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSURunTime.h>
#import <OmniSoftwareUpdate/OSUCheckOperation.h>
#import "OSUErrors.h"
#import "OSUAppcastSignature.h"
#import "InfoPlist.h"
#import <OmniSoftwareUpdate/OSUCheckerTarget.h>
#import "OSUSettings.h"
#import "OSURunOperation.h"
#import "OSUPartialItem.h"
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
#import <OmniUI/OUIAppController.h>
#endif

#if OSU_FULL
#import <OmniSoftwareUpdate/OSUReportKeys.h>
#elif defined(OMNI_BUILDING_FRAMEWORK_OR_BUNDLE)
#import <OmniSystemInfo/OSUReportKeys.h>
#else
#import "OSUReportKeys.h" // Non-framework import intentional. Building the OSUCheckService; hopefully avoids a dependency cycle in Xcode 10.
#endif


RCS_ID("$Id$");

static OFDeclareDebugLogLevel(OSUDebug);
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

#if 0 && (defined(DEBUG_correia) || defined(DEBUG_kilodelta))
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
    OSUPrivacyAlertWindowController *alert = [[OSUPrivacyAlertWindowController alloc] init];
    return [alert runHavingSeenPreviousVersion:hasSeenPreviousVersion];
}

@end
#endif

// Strings of interest
static NSString * const OSUDefaultCurrentVersionsURLString = @"https://update.omnigroup.com/appcast/";  // Must end in '/' for the path appending to not replace the last component

// Info.plist keys
static NSString * const OSUBundleCheckAtLaunchKey = @"OSUSoftwareUpdateAtLaunch";
static NSString * const OSUBundleCheckerClassKey = @"OSUCheckerClass";
static NSString * const OSUBundleTrackInfoKey = @"OSUSoftwareUpdateTrack";
static NSString * const OSUBundleLicenseTypeKey = @"OSUSoftwareUpdateLicenseType";

// Preferences keys
static NSString * const OSUCurrentVersionsURLKey = @"OSUCurrentVersionsURL";
static NSString * const OSUNewestVersionNumberLaunchedKey = @"OSUNewestVersionNumberLaunched";

NSString * const OSUNewsAnnouncementNotification = @"OSUNewsAnnouncement";
NSString * const OSUNewsAnnouncementHasBeenReadNotification = @"OSUNewsAnnouncementHasBeenRead";

// We used to have this be the bundle version, but when using a Copy Files build phase to install a framework into an app, codesign would get called with .../Versions/A instead of ..Versions/2009A (which was what we had FRAMEWORK_VERSION set to). Instead, just define this here and don't try to grab it out of the framework version (which isn't useful now anyway since we bundle frameworks inside the app).
#define OSU_VERSION_NUMBER 2009A

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

#if 0 && defined(DEBUG_bungi)
    #define PROBE_CHECK_INTERVAL (30.0)
#else
    #define PROBE_CHECK_INTERVAL (2 * 60.0 * 60.0) // How often to retry if there are network failures
#endif

@interface OSUChecker ()
@property(nonatomic,retain) id <OSUCheckerTarget> target;
@property(nonatomic,retain) NSDateFormatter *dateFormatter;
@property(nonatomic,weak) NSURLSessionTask *newsCacheTask;
@end

@implementation OSUChecker
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSTimer *_automaticUpdateTimer;
#else
    OFScheduledEvent *_automaticUpdateEvent;
#endif
    
    // Keep track of when we last actually started a check, so we can repeat at a shorter interval for things like network reachability issues.
    NSDate *_lastAttemptedCheckDate;
    
    id <OSUCheckerTarget> _checkTarget;
    
    NSString *_licenseType;
    
    struct {
        unsigned int shouldCheckAutomatically: 1;
        unsigned int initiateCheckOnLicenseTypeChange: 1;
        unsigned int scheduleNextCheckOnLicenseTypeChange: 1;
    } _flags;
    
    OFNetReachability *_netReachability;
    
    OSUCheckOperation *_currentCheckOperation;
    
    // Track info updates
    NSURLSessionDataTask *_refreshingTrackInfoTask;
}

static inline BOOL _hasScheduledCheck(OSUChecker *self)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return self->_automaticUpdateTimer != nil;
#else
    return self->_automaticUpdateEvent != nil;
#endif
}

#if IPAD_RETAIL_DEMO || MAC_APP_STORE_RETAIL_DEMO
// Retail demo builds should never check for updates or submit system information
#else
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
    self->_automaticUpdateEvent = [[OFScheduledEvent alloc] initWithInvocation:[[OFInvocation alloc] initForObject:self selector:@selector(_initiateCheck)] atDate:date];
    [[OFScheduler mainScheduler] scheduleEvent:self->_automaticUpdateEvent];
#endif
}
#endif

static inline void _cancelScheduledCheck(OSUChecker *self)
{
    if (!_hasScheduledCheck(self))
        return;
    
    OSU_DEBUG(1, @"Cancelling scheduled check");

    OBRetainAutorelease(self);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [self->_automaticUpdateTimer invalidate];
    self->_automaticUpdateTimer = nil;
#else
    [[OFScheduler mainScheduler] abortEvent:self->_automaticUpdateEvent];
    self->_automaticUpdateEvent = nil;
#endif
}

#ifdef OMNI_ASSERTIONS_ON
static void OSUAtExitHandler(void)
{
    @autoreleasepool {
        // All we do is check that there is no error in the termination handling logic.  It might not be safe to use NSUserDefaults/CFPreferences at this point and it isn't the end of the world if this doesn't record perfect stats.
        // Ignore if we are in a test environment
        if (![[NSProcessInfo processInfo] isRunningUnitTests]) {
            OBASSERT(OSURunTimeHasHandledApplicationTermination() == YES);
        }
    }
}
#endif

+ (void)initialize;
{
    OBINITIALIZE;
    
#ifdef OMNI_ASSERTIONS_ON
    atexit(OSUAtExitHandler);
#endif

#if 0 && defined(DEBUG)
    // Useful if you are checking various cases for timed checking
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate dateWithTimeIntervalSinceNow:-60] forKey:OSULastSuccessfulCheckDateKey];
#endif
}

// On the Mac, we'll automatically start when OFController gets running. On iOS we don't have OFController and apps must call +startWithTarget: and +shutdown
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
OBDidLoad(^{
    [[OFController sharedController] addStatusObserver:(id)[OSUChecker class]];
});
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
        NSString *urlString = [[[NSUserDefaults standardUserDefaults] stringForKey:OSUCurrentVersionsURLKey] copy];
        if ([NSString isEmptyString:urlString])
            urlString = OSUDefaultCurrentVersionsURLString;
        
        OSUCurrentVersionsURL = [NSURL URLWithString:urlString];
    }
    
    OSUChecker *checker = [self sharedUpdateChecker];
    [checker setTarget:target];
    
    // On iOS/MAS we currently ignore the results and don't care what track we are on. OSUItem isn't part of the OmniSystemInfo/OmniSoftwareUpdate-iOS subset (and would need work to avoid using NSXMLDocument on iOS).
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
    _checkTarget = nil;
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

- (BOOL)unreadNewsAvailable
{
    return [[OSUPreferences unreadNews] boolValue];
}

- (void)_cacheCurrentNews
{
    if (self.newsCacheTask) {
        return;
    }
    __weak OSUChecker *weakSelf = self;
    NSURLSessionTask *newsCacheTask = [[NSURLSession sharedSession] dataTaskWithURL:[self currentNewsURL] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        OSUChecker *strongSelf = weakSelf;
        if (!data || !strongSelf) {
            return;
        }
        [data writeToURL:[strongSelf cachedNewsURL] atomically:YES];

        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [[NSNotificationCenter defaultCenter] postNotificationName:OSUNewsAnnouncementNotification
                                                                object:strongSelf
                                                              userInfo:@{@"OSUNewsAnnouncementURL":[strongSelf cachedNewsURL]}];
        }];

        strongSelf.newsCacheTask = nil;
    }];
    self.newsCacheTask = newsCacheTask;
    [newsCacheTask resume];
}

- (void)setUnreadNewsAvailable:(BOOL)unreadNewsAvailable
{
    BOOL originalUnreadValue = self.unreadNewsAvailable;
    if (unreadNewsAvailable != originalUnreadValue) {
        [[OSUPreferences unreadNews] setBoolValue:unreadNewsAvailable];
        
        if (originalUnreadValue == YES) {
            // the news was read by the user, and is no longer considered unread.
            [[NSNotificationCenter defaultCenter] postNotificationName:OSUNewsAnnouncementHasBeenReadNotification object:nil];
        }
    }
}

- (BOOL)currentNewsIsCached
{
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:[self cachedNewsURL].path];
    if (!fileExists) {
        [self _cacheCurrentNews];
        return NO;
    }
    return YES;
}

- (NSURL *)cachedNewsURL
{
    NSURL *cacheURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    cacheURL = [cacheURL URLByAppendingPathComponent:@"GraffleNewsAnnouncement.html"];
    return cacheURL;
}

- (NSURL *)currentNewsURL
{
    NSString *urlString = [[OSUPreferences currentNewsURL] stringValue];
    if (urlString) {
        return [NSURL URLWithString:urlString];
    }
    return nil;
}

- (void)setCurrentNewsURL:(NSURL *)currentNewsURL
{
    if (currentNewsURL != self.currentNewsURL) {
        [[OSUPreferences currentNewsURL] setStringValue:[currentNewsURL absoluteString]];
        self.unreadNewsAvailable = YES;
        [self _cacheCurrentNews];
    }
}

- (void)handleNewsURL:(NSURL *)url withPublishDate:(NSDate *)publishDate
{
    OBPRECONDITION(publishDate);
    OBPRECONDITION(url);
    if (publishDate == nil || url == nil) {
        // if we didn't get a valid url or publish date, we need to bail and not try to show news.
        return;
    }
    
    NSDate *currentNewsDate = [[OSUPreferences newsPublishDate] objectValue];
    // only publish that we have a new news item, if the publishDate is later than the last news item publish date we received.
    if (currentNewsDate == nil || [currentNewsDate compare:publishDate] == NSOrderedAscending) {
#if defined(DEBUG_kilodelta)
        NSLog(@"news item with a date later than: %@ -- new date: %@", currentNewsDate, publishDate);
#endif
        [[OSUPreferences newsPublishDate] setObjectValue:publishDate];
        self.currentNewsURL = url;
    }
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
    OSUCheckOperation *check = [[OSUCheckOperation alloc] initForQuery:NO url:OSUCurrentVersionsURL licenseType:_licenseType];
    return [check runSynchronously];
}

#pragma mark -
#pragma mark NSObject (OFControllerStatusObserver)

// On the Mac, we'll automatically start when OFController gets running. On iOS we don't have OFController and apps must call +startWithTarget: and +shutdown
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
+ (void)controllerStartedRunning:(OFController *)controller;
{
#if OSU_FULL
    [self startWithTarget:[OSUController sharedController]];
#else
    [self startWithTarget:[[OSUSystemInfoController alloc] init]];
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
    
    // We'll get a spurious update of NO the first time OFNetReachability hears from the system. We want to provoke a check earlier if the host becomes reachable, but we'll still poll on a timer if it isn't, since reachabiliy can't tell for sure (it doesn't consider proxies, distant routers, remote DNS, or any number of other things).
    if (reachable) {
        OSU_DEBUG(1, @"Network configuration has changed to a reachable state");
        [self _initiateCheck];
    }
}

#pragma mark - Private

@synthesize target = _checkTarget;
- (void)setTarget:(id <OSUCheckerTarget>)target;
{
    OBPRECONDITION(!target || [target conformsToProtocol:@protocol(OSUCheckerTarget)]);
    
    _checkTarget = target;
    
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

- (NSDateFormatter *)dateFormatter
{
    if (_dateFormatter == nil) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        NSLocale *us = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        [formatter setLocale:us];
        // Formatter needs to follow RFC 822 for RSS version 2.0
        formatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
        _dateFormatter = formatter;
    }
    
    return _dateFormatter;
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

    OFVersionNumber *currentlyRunningVersionNumber = [[OFVersionNumber alloc] initWithVersionString:[self applicationEngineeringVersion]];
    if (currentlyRunningVersionNumber == nil) {
#ifdef DEBUG
        NSLog(@"Unable to compute version number of this app");
#endif
        return NO;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *newestVersionNumberLaunchedString = [defaults stringForKey:OSUNewestVersionNumberLaunchedKey];
    if (![NSString isEmptyString:newestVersionNumberLaunchedString]) {
        OFVersionNumber *newestVersionNumberLaunched = [[OFVersionNumber alloc] initWithVersionString:newestVersionNumberLaunchedString];

        if ([currentlyRunningVersionNumber compareToVersionNumber:newestVersionNumberLaunched] != NSOrderedDescending)
            return NO; // This version is the same or older than the version we ran at last launch
    }

    [defaults setObject:[currentlyRunningVersionNumber cleanVersionString] forKey:OSUNewestVersionNumberLaunchedKey];

    return YES;
}

- (BOOL)_shouldCheckAutomatically;
{
#if IPAD_RETAIL_DEMO || MAC_APP_STORE_RETAIL_DEMO
    // Retail demo builds should never check for updates or submit system information
    return NO;
#else
    // Disallow automatic checks if we are a debug build; attached to the debugger.
    // You can still trigger a manual check to debug Software Update, or turn this off if necessary.
    
#if 1 && defined(DEBUG)
    if (OBIsBeingDebugged() && (OSUDebug == 0))
        return NO;
#endif
    
    return _flags.shouldCheckAutomatically;
#endif
}

- (void)_scheduleNextCheck;
{
#if IPAD_RETAIL_DEMO || MAC_APP_STORE_RETAIL_DEMO
    // Retail demo builds should never check for updates or submit system information
#else
    // Make sure we haven't been disabled
    if (![[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue])
        _flags.shouldCheckAutomatically = 0;

    if (![self _shouldCheckAutomatically] || _currentCheckOperation) {
        _cancelScheduledCheck(self);
        return;
    }
    
    // Determine when we should make the next check.
    
    // The date at which we'd ideally try again if everything has been working smoothly.
    NSDate *nextCheckDate = nil;
    {
        NSTimeInterval minimumCheckTimeInterval = (OSUDebug > 0) ? 15.0 : MINIMUM_CHECK_INTERVAL; // While debugging, allow more frequent checks
        NSTimeInterval checkInterval = MAX([[OSUPreferences checkInterval] floatValue] * 60.0 * 60.0, minimumCheckTimeInterval);
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDate *now = [NSDate date];
        NSDate *lastCheckDate = [defaults objectForKey:OSULastSuccessfulCheckDateKey];
        if (![lastCheckDate isKindOfClass:[NSDate class]] || [lastCheckDate timeIntervalSinceNow] > 60.0) {
            // If we don't have a last check date, or it is some strange value, then write 'now' as the date and we'll wait a full check interval.
            lastCheckDate = now;
            [defaults setObject:lastCheckDate forKey:OSULastSuccessfulCheckDateKey];
        }
        
        // This might be in the past if we have been failing due to network connection issues.
        nextCheckDate = [lastCheckDate dateByAddingTimeInterval:checkInterval];
        OSU_DEBUG(1, "Next regular check date is %@", nextCheckDate);
    }
    
    // If there are network failures, we need to continue to probe (but hopefully the network reachability will kick in and prompt us earlier).
    if (_lastAttemptedCheckDate && [nextCheckDate timeIntervalSinceNow] < 0) {
        nextCheckDate = [_lastAttemptedCheckDate dateByAddingTimeInterval:PROBE_CHECK_INTERVAL];
        OSU_DEBUG(1, "  Next regular check has passed, retry at %@", nextCheckDate);
    }
    
    if (_hasScheduledCheck(self)) {
        if(fabs([_scheduledCheckFireDate(self) timeIntervalSinceDate:nextCheckDate]) < 1.0) {
            // We already have a scheduled check at the time we would be scheduling one, so we don't need to do anything.
            OSU_DEBUG(1, "  Effectively the same date -- skipping reregistering");
            return;
        } else {
            // We have a scheduled check at a different time. Cancel the existing event and add a new one.
            _cancelScheduledCheck(self);
        }
    }
    
    _scheduleCheckForDate(self, nextCheckDate);
#endif
}

- (void)_initiateCheck;
{
#if MAC_APP_STORE_RETAIL_DEMO
    // Retail demo builds should never check for updates or submit system information
#else
    if (_currentCheckOperation)
        return;
    
    // clear cached news url to avoid using stale data
    [[NSFileManager defaultManager] removeItemAtURL:[self cachedNewsURL] error:nil];
    
    [self _beginLoadingURLInitiatedByUser:NO];
#endif
}

- (void)_beginLoadingURLInitiatedByUser:(BOOL)initiatedByUser;
{
#if MAC_APP_STORE_RETAIL_DEMO
    // Retail demo builds should never check for updates or submit system information
#else
    if (![self _shouldLoadAfterWarningUserAboutNewVersion]) {
        // This is a hack to avoid a panel saying that there are no updates.  Instead, we should probably have an enum for the status
        return;
    }
    
    [self _clearCurrentCheckOperation];
    
    [self willChangeValueForKey:OSUCheckerCheckInProgressBinding];
    _currentCheckOperation = [[OSUCheckOperation alloc] initForQuery:YES url:OSUCurrentVersionsURL licenseType:_licenseType];
    _currentCheckOperation.initiatedByUser = initiatedByUser;
    [self didChangeValueForKey:OSUCheckerCheckInProgressBinding];
    
    _lastAttemptedCheckDate = [NSDate date];
    
    OSU_DEBUG(1, @"Starting check");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_checkOperationCompleted:) name:OSUCheckOperationCompletedNotification object:_currentCheckOperation];
    [_currentCheckOperation runAsynchronously];
#endif
}

- (void)_clearCurrentCheckOperation;
{
    if (_currentCheckOperation) {
        [self willChangeValueForKey:OSUCheckerCheckInProgressBinding];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:OSUCheckOperationCompletedNotification object:_currentCheckOperation];
        _currentCheckOperation = nil;
        [self didChangeValueForKey:OSUCheckerCheckInProgressBinding];
    }
}

- (void)_checkOperationCompleted:(NSNotification *)note;
{
    if ([note object] != _currentCheckOperation) {
        OBASSERT_NOT_REACHED("Ignoring result from some other check operation");
        return;
    }
    
    // The fetch subprocess has completed.
    NSDictionary *output = _currentCheckOperation.output;
#if defined(DEBUG)
    // This is helpful when you need to test the behavior when a software update check fails. (Specifically, this only mimics the kind of failure you get if the server can be reached but never actually responds.)
    if ((output != nil) && [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUTestCheckFailure"]) {
        NSLog(@"OSUTestCheckFailure: pretending that we got no check operation output");
        output = nil;
    }
#endif
    __autoreleasing NSError *error = nil;
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
        error = errorDict ? [[NSError alloc] initWithPropertyList:errorDict] : nil;
    }
    
    BOOL initiatedByUser = _currentCheckOperation.initiatedByUser;
    
    [self _clearCurrentCheckOperation]; // Done with _currentCheckOperation from this point forward
    
    if (!initiatedByUser) {
        BOOL isNetworkError = ([error causedByNetworkConnectionLost] || [error causedByUnreachableHost]);

        BOOL isXPCError = ([error hasUnderlyingErrorDomain:OSUErrorDomain code:OSUCheckServiceTimedOut] || [error hasUnderlyingErrorDomain:OSUErrorDomain code:OSUCheckServiceFailed]);
        if (isXPCError) {
            // NOTE: If we get reports of this log message from users, crashes in the XPC service are caught by the system and written to ~/Library/Logs/DiagnosticReports.
            [error log:@"Automatic software update check failed due to XPC service failure"];
        }
        
        if (isNetworkError || isXPCError) {
            // Try again later. We don't advance OSULastSuccessfulCheckDateKey preference here, so the time interval will be smaller.
            OSU_DEBUG(1, @"Check failed due to a hopefully transient error (network:%d, XPC:%d)", isNetworkError, isXPCError);
            [self _scheduleNextCheck];

            // But, if the network configuration changes, we'll want to try sooner.
            if (isNetworkError && !_netReachability) {
                [self _startWatchingNetworkReachability];
            }
            
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
        // Updating the last success date so that _scheduleNextCheck will schedule a check using our normal interval into the future
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:OSULastSuccessfulCheckDateKey];

#if OSU_FULL
        [self _interpretSoftwareUpdateData:data operation:operation error:&error];
#else
        [self _checkForMessageInSoftwareUpdateData:data];
#endif
    }
    
    if (error) {
        if ([_checkTarget respondsToSelector:@selector(checker:check:failedWithError:)])
            [_checkTarget checker:self check:operation failedWithError:error];
        else
            NSLog(@"Check operation %@ failed with error: %@", operation, [error toPropertyList]);
    } else {
        // Only schedule a check if there was no error.  Note that if the user manually performs a check after this has happened, the automatic checking should start up again.
        // Note, we *do* reschedule on network errors above that look transient. But, if there is some corruption of the software update plist, we don't want to be pestering the user about it.
        [self _scheduleNextCheck];
    }
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
        if (!data || !verifiedPortions || ![verifiedPortions count]) {
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
    
    NSXMLDocument *document =  data ? [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:outError] : nil;
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
    
    OFVersionNumber *currentVersion = [[OFVersionNumber alloc] initWithVersionString:[self applicationEngineeringVersion]];
    NSString *currentTrack = [self applicationTrack];

    BOOL showOlderVersions = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUIncludeVersionsOlderThanCurrentVersion"];
    
    NSError *firstError = nil;
    NSMutableArray *items = [NSMutableArray array];
    NSUInteger nodeIndex = [nodes count];
 
    while (nodeIndex--) {
        __autoreleasing NSError *itemError = nil;
        OSUItem *item = [[OSUItem alloc] initWithRSSElement:[nodes objectAtIndex:nodeIndex] error:&itemError];
        
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

    // from the feed items we have, check if we have a news item.
    OSUItem *newsItem = nil;
    for (OSUItem *item in items) {
        if (item.isNewsItem) {
            newsItem = item;
            break;
        }
    }
    
    if (newsItem != nil) {
        NSDate *publishDate = [self _convertRFC822DateString:newsItem.publishDateString];
        [self handleNewsURL:newsItem.releaseNotesURL withPublishDate:publishDate];
#if defined(DEBUG_kilodelta)
        NSLog(@"------- Got a new news item: %@ for date: %@", newsItem.releaseNotesURL, publishDate);
#endif
        // take this item out of the feed so we don't show it.
        [items removeObject:newsItem];
        
        //Note: What should happen if we have a news feed item and an update? Currently we badge the UI for news, but show the update panel.
    }
    
    // If it looks like we'll display anything, retrieve the track descriptions and up-to-date orderings
    if (items.count != 0 && _refreshingTrackInfoTask == nil) {
        NSArray *trackInfoAttributes = [document objectsForXQuery:[NSString stringWithFormat:@"declare namespace oac = \"%@\";\n /rss/channel/attribute::oac:trackinfo", OSUAppcastTrackInfoNamespace] error:NULL];
        if (trackInfoAttributes.count != 0) {
            NSURLComponents *trackInfoURLComponents = [[NSURLComponents alloc] initWithString:[[trackInfoAttributes objectAtIndex:0] stringValue]];
            if (trackInfoURLComponents != nil) {
                if (OFISEQUAL(trackInfoURLComponents.scheme, @"http") && [trackInfoURLComponents.host hasSuffix:@".omnigroup.com"]) {
                    trackInfoURLComponents.scheme = @"https";
                }
                NSURL *trackInfoURL = trackInfoURLComponents.URL;
                if (trackInfoURL != nil) {
                    NSMutableURLRequest *infoRequest = [NSMutableURLRequest requestWithURL:trackInfoURL];
                    [infoRequest setValue:[[operation url] absoluteString] forHTTPHeaderField:@"Referer" /* sic */];

                    _refreshingTrackInfoTask = [[NSURLSession sharedSession] dataTaskWithRequest:infoRequest completionHandler:^(NSData * _Nullable trackData, NSURLResponse * _Nullable response, NSError * _Nullable error){
                        [self _trackInfoDataTaskFinished: trackData];
                    }];
                    [_refreshingTrackInfoTask resume];
                }
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

- (void)_trackInfoDataTaskFinished:(NSData *)trackData;
{
    OBPRECONDITION(![NSThread isMainThread], "We are called on a NSURLSession worker queue.");

    NSError *error = _refreshingTrackInfoTask.error;
    if (error) {
        [error log:@"Couldn't fetch track info"];
        _refreshingTrackInfoTask = nil;
        return;
    }
    NSURLResponse *response = _refreshingTrackInfoTask.response;
    _refreshingTrackInfoTask = nil;

    if (![[response MIMEType] containsString:@"xml"]) {
        NSLog(@"Ignoring track data with unknown MIME type %@", [response MIMEType]);
        return;
    }

    if (!trackData) {
        OBASSERT(trackData);
        return;
    }

    __autoreleasing NSError *xmlError = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:trackData options:NSXMLNodeOptionsNone error:&xmlError];

    if (!document) {
        [xmlError log: @"Can't parse track info"];
    } else {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [OSUItem processTrackInformation:document];
        }];
    }
}

#else
- (void)_checkForMessageInSoftwareUpdateData:(NSData *)data NS_EXTENSION_UNAVAILABLE_IOS("");
{
    OSUPartialItem *oneItem = [[OSUPartialItem alloc] initWithXMLData:data];
    if (oneItem) {
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        if (oneItem.releaseNotesURLString.length > 0 && [[UIApplication sharedApplication].delegate isKindOfClass:[OUIAppController class]]) {
            OUIAppController.sharedController.newsURLStringToShowWhenReady = oneItem.releaseNotesURLString;
        }
#endif
        // MAS Build.
        NSURL *newsURL = [NSURL URLWithString:oneItem.releaseNotesURLString];
        NSDate *publishDate = [self _convertRFC822DateString:oneItem.publishDateString];
        [self handleNewsURL:newsURL withPublishDate:publishDate];
    }
}

#endif

- (BOOL)_shouldLoadAfterWarningUserAboutNewVersion;
{
    OBPRECONDITION(OSUVersionNumber);
    OBPRECONDITION(_checkTarget);
    
    // The first time OSU runs for this user, prompt them that we'll send some info to the network.  We check in 'com.omnigroup.OmniSoftwareUpdate' so that the user only gets this panel once for any OSU version rather than getting peppered with it.
    NSString *prefKey = @"OSUHighestRunVersion";

    NSString *str = (NSString *)OSUSettingGetValueForKey(prefKey);
    OFVersionNumber *highestRunVersion = str ? [[OFVersionNumber alloc] initWithVersionString:str] : nil;
    
    if (highestRunVersion && [highestRunVersion compareToVersionNumber:OSUVersionNumber] != NSOrderedAscending)
        return YES;

    // Unconditionally update preferences so that this panel doesn't come up again.
    OSUSettingSetValueForKey(prefKey, [OSUVersionNumber cleanVersionString]);

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
}
#endif

- (NSDate *)_convertRFC822DateString:(NSString *)dateString
{
    if ([NSString isEmptyString:dateString]) {
        return nil;
    }

    // Guard against some possible bad date formats in the OSU publish date string.
    
    if ([dateString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"-"]].location != NSNotFound) {
        // guard against a possibly poorly formated date string.
        dateString = [dateString stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    }
    
    if ([dateString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@","]].location == NSNotFound) {
        // use a format that doesn't include the day abrev.
        self.dateFormatter.dateFormat = @"dd MMM yyyy HH:mm:ss zzz";
    }
    
    NSDate *date = [self.dateFormatter dateFromString:dateString];
    if (date == nil) {
        OSU_DEBUG(1, @"failed to convert: %@ into a RFC822 date", dateString);
        OBASSERT_NOT_REACHED("failed to convert: %@ into a RFC822 date", dateString);
    }
    return date;
}
@end
