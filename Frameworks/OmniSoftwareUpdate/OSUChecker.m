// Copyright 2001-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUChecker.h"

#import <OmniAppKit/OAPreferenceController.h>
#import <OmniAppKit/OAController.h>
#import <OmniFoundation/OFScheduler.h>
#import <OmniFoundation/OFScheduledEvent.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSUserDefaults-OFExtensions.h>
#import <OmniFoundation/OFMultipleOptionErrorRecovery.h>
#import <OmniFoundation/OFCancelErrorRecovery.h>

#import <SystemConfiguration/SystemConfiguration.h>

#import "OSUCheckTool.h"
#import "OSUController.h"
#import "OSUDownloadController.h"
#import "OSUPreferences.h"
#import "OSURunTime.h"
#import "OSUCheckOperation.h"
#import "OSUErrors.h"
#import "OSUItem.h"
#import "OSUSendFeedbackErrorRecovery.h"
#import "OSUAppcastSignature.h"

RCS_ID("$Id$");

#if defined(DEBUG_bungi) || defined(DEBUG_wiml)
#define OSU_DEBUG
#endif

// Strings of interest
static NSString *OSUDefaultCurrentVersionsURLString = @"http://update.omnigroup.com/appcast/";  // Must end in '/' for the path appending to not replace the last component

// Info.plist keys
static NSString *OSUBundleCheckAtLaunchKey = @"OSUSoftwareUpdateAtLaunch";
static NSString *OSUBundleCheckerClassKey = @"OSUCheckerClass";
static NSString *OSUBundleTrackInfoKey = @"OSUSoftwareUpdateTrack";

// Preferences keys
static NSString *OSUNextCheckKey = @"OSUNextScheduledCheck";
static NSString *OSUCurrentVersionsURLKey = @"OSUCurrentVersionsURL";
static NSString *OSUNewestVersionNumberLaunchedKey = @"OSUNewestVersionNumberLaunched";
// static NSString *OSUVisibleTracksKey = @"OSUVisibleTracks";

static OFVersionNumber *OSUVersionNumber = nil;
static NSURL    *OSUCurrentVersionsURL = nil;

// 
NSString * const OSULicenseTypeUnset = @"unset";
NSString * const OSULicenseTypeNone = @"none";
NSString * const OSULicenseTypeRegistered = @"registered";
NSString * const OSULicenseTypeRetail = @"retail";
NSString * const OSULicenseTypeBundle = @"bundle";
NSString * const OSULicenseTypeTrial = @"trial";
NSString * const OSULicenseTypeExpiring = @"expiring";

#define MINIMUM_CHECK_INTERVAL (60.0 * 15.0) // Cannot automatically check more frequently than every fifteen minutes

#define SCKey_GlobalIPv4State CFSTR("State:/Network/Global/IPv4")
#define SCKey_GlobalIPv4State_hasUsefulRoute CFSTR("Router")

NSString *OSUSoftwareUpdateExceptionName = @"OSUSoftwareUpdateException";

@interface OSUChecker (Private)

- (BOOL)_shouldCheckAtLaunch;
- (void)_scheduleNextCheck;
- (void)_initiateCheck;
- (void)_beginLoadingURLInitiatedByUser:(BOOL)initiatedByUser;
- (void)_clearCurrentCheckOperation;
- (void)_checkOperationCompleted:(NSNotification *)note;
- (BOOL)_interpretSoftwareUpdateData:(NSData *)data operation:(OSUCheckOperation *)operation error:(NSError **)outError;
- (BOOL)_shouldLoadAfterWarningUserAboutNewVersion;
- (BOOL)_postponeCheckForURL;

- (void)_scDynamicStoreDisconnect;
- (BOOL)_scDynamicStoreConnect;

static void networkInterfaceWatcherCallback(SCDynamicStoreRef store, CFArrayRef keys, void *info);

// This is kept separate from our ivars so that people who use this class don't need to pull in all the SystemConfiguration framework headers.
struct _OSUSoftwareUpdatePostponementState {
    SCDynamicStoreRef store; // our connection to the system configuration daemon
    CFRunLoopSourceRef loopSource; // our run loop's reference to 'store'

    SCDynamicStoreContext callbackContext;
};

static NSString *OSUBundleVersionForBundle(NSBundle *bundle);

@end

@implementation OSUChecker

static inline void cancelScheduledEvent(OSUChecker *self)
{
    if (self->_automaticUpdateEvent != nil) {
        [[self retain] autorelease];
        [[OFScheduler mainScheduler] abortEvent:self->_automaticUpdateEvent];
    	[self->_automaticUpdateEvent release];
        self->_automaticUpdateEvent = nil;
    }
}

+ (void)didLoad;
{
    [[OFController sharedController] addObserver:self];
}

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

- (OFVersionNumber *)applicationMarketingVersion
{
    static OFVersionNumber *version = nil;
    if (!version) {
        NSDictionary *myInfo = [[NSBundle mainBundle] infoDictionary];
        version = [[OFVersionNumber alloc] initWithVersionString:[myInfo objectForKey:@"CFBundleShortVersionString"]];
    }
    return version;
}

// Try to give developers some warning if they have a bogus track selected.
+ (NSArray *)supportedTracksByPermissiveness;
{
    // These are listed in order of permissiveness for the benefit of +mostPermissiveTrackSeen.  Do not reorder.
    static NSArray *supportedTracks = nil;
    if (!supportedTracks)
        supportedTracks = [[NSArray alloc] initWithObjects:@"", @"rc", @"beta", @"sneakypeek", nil];
    return supportedTracks;
}

- (NSString *)applicationIdentifier;
{
    return [[NSBundle mainBundle] bundleIdentifier];
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
}

- (void)setTarget:(id)anObject;
{
    SEL actionSelector = @selector(newVersionsAvailable:fromCheck:);
    if (anObject != nil && ![anObject respondsToSelector:actionSelector]) {
        OBRejectInvalidCall(self, _cmd, @"Target must respond to %@", NSStringFromSelector(actionSelector));
    }
    
    OBPRECONDITION(_checkTarget == nil);
    _checkTarget = [anObject retain];

    _flags.shouldCheckAutomatically = [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue];
    _currentCheckOperation = nil;
    _automaticUpdateEvent = nil;

    if ([self _shouldCheckAtLaunch]) {
	// Do a check immediately, unless our license type isn't set; licensing system is still processing stuff in this case.
	if (_licenseType)
	    [self _initiateCheck];
	else
            _flags.initiateCheckOnLicenseTypeChange = YES;
    } else {
	// As above, only schedule if we have our license type set already.
	if (_licenseType)
	    [self _scheduleNextCheck];
	else
            _flags.scheduleNextCheckOnLicenseTypeChange = YES;
    }
    [OFPreference addObserver:self selector:@selector(softwareUpdatePreferencesChanged:) forPreference:[OSUPreferences automaticSoftwareUpdateCheckEnabled]];
    [OFPreference addObserver:self selector:@selector(softwareUpdatePreferencesChanged:) forPreference:[OSUPreferences checkInterval]];
}

- (BOOL)checkInProgress
{
    return (_currentCheckOperation != nil)? YES : NO; 
}

- (void)dealloc;
{
    OBASSERT(_automaticUpdateEvent == nil);  // if it were non-nil, it would be retaining us and we wouldn't be being deallocated
    [self _scDynamicStoreDisconnect]; 
    [_checkTarget release];
    _checkTarget = nil;
    [_licenseType release];
    [super dealloc];
}


// API

- (void)checkSynchronously;
{
    if (_checkTarget == nil)
        return;

    OSUDownloadController *currentDownload = [OSUDownloadController currentDownloadController];
    if (currentDownload) {
        [currentDownload showWindow:nil];
        NSBeep();
        return;
    }
    
    @try {
        cancelScheduledEvent(self);

        // Do this via the task so that hardware collection occurs.
        [self _beginLoadingURLInitiatedByUser:YES];

        [OSUController startingCheckForUpdates];

    } @catch (NSException *exc) {
        [self _clearCurrentCheckOperation];
#ifdef DEBUG
        NSLog(@"Exception raised in %s: %@", __PRETTY_FUNCTION__, exc);
#endif	
        [exc raise];
    } @finally {
        [self _scheduleNextCheck];
    }
}

static inline NSDictionary *dataToPlist(NSData *input)
{
    CFStringRef errorString = NULL;
    
    // Contrary to the name, this call handles the text-style plist as well.
    CFPropertyListRef output = CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)input, kCFPropertyListImmutable, &errorString);
    
    [(id)output autorelease];
    if (errorString) {
#ifdef DEBUG    
        NSLog(@"Error creating property list: %@", errorString); // TODO: Return an NSError from this function
#endif	
        CFRelease(errorString);
    }
    
    return (NSDictionary *)output;
}

- (NSDictionary *)generateReport;
{
    OSUCheckOperation *check = [[[OSUCheckOperation alloc] initForQuery:NO url:OSUCurrentVersionsURL licenseType:_licenseType] autorelease];
    return dataToPlist([check runSynchronously]);
}

//
// NSObject(OFControllerObserver)
//

static NSString *OSUBundleVersionForBundle(NSBundle *bundle)
{
    NSString *version = [[bundle infoDictionary] objectForKey:@"CFBundleVersion"];
    
    OBPOSTCONDITION(version);
    OBPOSTCONDITION([version isKindOfClass:[NSString class]]);
    
    return version;
}

static void OSUAtExitHandler(void)
{
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    // All we do is check that there is no error in the termination handling logic.  It might not be safe to use NSUserDefaults/CFPreferences at this point and it isn't the end of the world if this doesn't record perfect stats.
    OBASSERT(OSURunTimeHasHandledApplicationTermination() == YES);
    [p release];
}

+ (void)controllerStartedRunning:(OFController *)controller;
{
    // Must do this here instead of in +initialize since defaults from the app plist might not be registered yet (preventing site licensees from changing their app bundle to provide a local OSU plist).
    NSString *urlString = [[[[NSUserDefaults standardUserDefaults] stringForKey:OSUCurrentVersionsURLKey] copy] autorelease];
    if ([NSString isEmptyString:urlString])
        urlString = OSUDefaultCurrentVersionsURLString;

    NSString *versionString = OSUBundleVersionForBundle(OMNI_BUNDLE);
    OSUVersionNumber = [[OFVersionNumber alloc] initWithVersionString:versionString];

    OSUCurrentVersionsURL = [[NSURL URLWithString:urlString] retain];

    [[self sharedUpdateChecker] setTarget:[OSUController class]];
    
    OSURunTimeApplicationStarted();
    atexit(OSUAtExitHandler);
    
    {
        NSString *packageURLString = [[NSUserDefaults standardUserDefaults] stringForKey:@"OSUDownloadAndInstallFromURL"];
        if (![NSString isEmptyString:packageURLString]) {
            NSURL *packageURL = [NSURL URLWithString:packageURLString];
            NSError *error = nil;
            if (![[OSUController sharedController] beginDownloadAndInstallFromPackageAtURL:packageURL item:nil error:&error])
                [NSApp presentError:error];
        }
    }
    
    // Warn developers if they are on a funky track ('sneakpeek' and 'sneakypeak' being the most common typos).
#ifdef DEBUG
    NSString *runningTrack = [[self sharedUpdateChecker] applicationTrack];
    if (![[self supportedTracksByPermissiveness] containsObject:runningTrack])
        NSRunAlertPanel(@"Unknown software update track", @"Specified the track '%@' but only know about '%@'.  Typo?", @"OK", nil, nil, runningTrack, [self supportedTracksByPermissiveness]);
#endif
}

+ (void)controllerWillTerminate:(OFController *)controller;
{
    NSBundle *bundle = [NSBundle mainBundle];
    OSURunTimeApplicationTerminated([bundle bundleIdentifier], OSUBundleVersionForBundle(bundle), NO/*crashed*/);
}

@end

@implementation OSUChecker (NotificationsDelegatesDatasources)

- (void)softwareUpdatePreferencesChanged:(NSNotification *)aNotification;
{
    _flags.shouldCheckAutomatically = [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue];
    [self _scheduleNextCheck];
}

@end

@implementation OSUChecker (Private)

- (BOOL)_shouldCheckAtLaunch;
{
#if 0 && defined(DEBUG_bungi) // or anyone else debugging OSU code
    return YES;
#endif

    if (!_flags.shouldCheckAutomatically)
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
    [defaults autoSynchronize];

    return YES;
}

- (void)_scheduleNextCheck;
{
    // Make sure we haven't been disabled
    if (![[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue])
        _flags.shouldCheckAutomatically = 0;

    if (!_flags.shouldCheckAutomatically || _currentCheckOperation) {
        cancelScheduledEvent(self);
        return;
    }
    
    // Determine when we should make the next check
    NSTimeInterval checkInterval = MAX([[OSUPreferences checkInterval] floatValue] * 60.0 * 60.0, MINIMUM_CHECK_INTERVAL);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDate *now = [NSDate date];
    NSDate *nextCheckDate = [defaults objectForKey:OSUNextCheckKey];
    if (nextCheckDate == nil || ![nextCheckDate isKindOfClass:[NSDate class]] ||
        ([nextCheckDate timeIntervalSinceDate:now] > checkInterval)) {
        nextCheckDate = [[NSDate alloc] initWithTimeInterval:checkInterval sinceDate:now];
        [nextCheckDate autorelease];
        [defaults setObject:nextCheckDate forKey:OSUNextCheckKey];
        [defaults autoSynchronize];
    }
    
    if (_automaticUpdateEvent) {
        if(fabs([[_automaticUpdateEvent date] timeIntervalSinceDate:nextCheckDate]) < 1.0) {
            // We already have a scheduled check at the time we would be scheduling one, so we don't need to do anything.
            return;
        } else {
            // We have a scheduled check at a different time. Cancel the existing event and add a new one.
            cancelScheduledEvent(self);
        }
    }
    OBASSERT(_automaticUpdateEvent == nil);
    _automaticUpdateEvent = [[OFScheduledEvent alloc] initWithInvocation:[[[OFInvocation alloc] initForObject:self selector:@selector(_initiateCheck)] autorelease] atDate:nextCheckDate];
    [[OFScheduler mainScheduler] scheduleEvent:_automaticUpdateEvent];
#ifdef OSU_DEBUG
    NSLog(@"OSU: Scheduled update for %f seconds in the future", [nextCheckDate timeIntervalSinceNow]);
#endif
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
    NSError *error = nil;
    int terminationStatus = [_currentCheckOperation terminationStatus];
    if (terminationStatus != OSUTool_Success) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fetch software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - will be followed by more detailed error reason");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Tool exited with %d", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - tried to run a helper tool to fetch software update information, but it exited with an error code"), terminationStatus];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
        error = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToFetchSoftwareUpdateInformation userInfo:userInfo];
    }
    
    NSDictionary *results = nil;
    if (!error) {
        results = dataToPlist([_currentCheckOperation output]);
        NSDictionary *errorDict = [results objectForKey:OSUTool_ResultsErrorKey];
        error = errorDict ? [[[NSError alloc] initWithPropertyList:errorDict] autorelease] : nil;
    }
    
    [self _clearCurrentCheckOperation]; // Done with _currentCheckOperation from this point forward
    
    if (error && [error code] == OSUToolLocalNetworkFailure) {
        if (!_postpone) {
            [self _scDynamicStoreConnect];
            return;
        }
    }
    
    NSData *data = [results objectForKey:OSUTool_ResultsDataKey];
    if (!error && !data) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fetch software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - will be followed by more detailed error reason");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Tool returned no data", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason - we ran a helper tool to fetch software update information, but it didn't return any information");
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
        error = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToFetchSoftwareUpdateInformation userInfo:userInfo];
    }
    
    
    OSUCheckOperation *operation = [note object];
    if (!error)
        [self _interpretSoftwareUpdateData:data operation:operation error:&error];

    if (error) {
        // If we get an error that is due to a server-side misconfiguration, go ahead and report it so that we'll know to fix it and users won't get stranded.  But if we simply can't connect to the server, it's presumably a transient error and shouldn't be reported unless the user is specifically checking for updates.
#if 0
        BOOL isNetworkError = NO;
        if ([[error domain] isEqualToString:OSUToolErrorDomain]) {
            int code = [error code];
            if (code == OSUToolRemoteNetworkFailure && code == OSUToolLocalNetworkFailure)
                isNetworkError = YES;
        }
#endif
        
        // Disabling the errors from the asynchronous check until the UI is improved.  <bug://bugs/40635> (Warn users if they haven't successfully connected to software update in N days)
        BOOL shouldReport = operation.initiatedByUser /*|| !isNetworkError*/;
        
        if (shouldReport) {
            error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:nil options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
            [NSApp presentError:error];
        } else {
#ifdef DEBUG	
            NSLog(@"Error interpreting response from software update server: %@", error);
#endif	    
	}
    } else
        // Only schedule a check if there was no error.  Note that if the user manually performs a check after this has happened, the automatic checking should start up again.
        [self _scheduleNextCheck];
}

- (BOOL)_interpretSoftwareUpdateData:(NSData *)data operation:(OSUCheckOperation *)operation error:(NSError **)outError;
{
    OBPRECONDITION(data);

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:OSUNextCheckKey];
    // Removing the nextCheckKey will cause _scheduleNextCheck to schedule a check in the future
    
    if (outError)
        *outError = nil;
    
    NSString *trust = [OMNI_BUNDLE pathForResource:@"AppcastTrustRoot" ofType:@"pem"];
    if (trust) {
#ifdef DEBUG
        NSLog(@"OSU: Using %@", trust);
#endif
        NSArray *verifiedPortions = OSUGetSignedPortionsOfAppcast(data, trust, outError);
        if (!verifiedPortions || ![verifiedPortions count]) {
            if (outError) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to authenticate the response from the software update server.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - we have some update information but it doesn't look authentic");
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
                
                if (!verifiedPortions) {
                    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"There was a problem checking the signature.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - the checksum or signature didn't match - more info in underlying error")];
                    [userInfo setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
                    [userInfo setObject:*outError forKey:NSUnderlyingErrorKey];
                } else {
                    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The update information is not signed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - the update information wasn't signed at all, but we require it to be signed")];
                    [userInfo setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
                }
                
                NSURL *serverURL = [operation url];
                if (serverURL)
                    [userInfo setObject:[serverURL absoluteString] forKey:NSErrorFailingURLStringKey];
                
                *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToParseSoftwareUpdateData userInfo:userInfo];
            }
            
            return NO;
        }
        
        if ([verifiedPortions count] != 1) {
            NSLog(@"Warning: Update contained %u reference nodes; only using the first.", [verifiedPortions count]);
        }
        
        data = [verifiedPortions objectAtIndex:0];
    }
    
    NSXMLDocument *document = [[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:outError] autorelease];
    if (!document) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to parse response from the software update server.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The data returned from <%@> was not a valid XML document.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description"), [[operation url] absoluteString]];
            
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
            if (outError && *outError)
                [userInfo setObject:*outError forKey:NSUnderlyingErrorKey];
        
            *outError = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUUnableToParseSoftwareUpdateData userInfo:userInfo];
        }
        return NO;
    }
    
    NSArray *nodes = [document nodesForXPath:@"/rss/channel/item" error:outError];
    if (!nodes)
        return NO;
    
    //NSLog(@"nodes = %@", nodes);
    
    NSString *appVersionString = OSUBundleVersionForBundle([NSBundle mainBundle]);
    OFVersionNumber *currentVersion = [[[OFVersionNumber alloc] initWithVersionString:appVersionString] autorelease];

    BOOL showOlderVersions = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUIncludeVersionsOlderThanCurrentVersion"];
    
    NSError *firstError = nil;
    NSMutableArray *items = [NSMutableArray array];
    unsigned int nodeIndex = [nodes count];
    while (nodeIndex--) {
        NSError *itemError = nil;
        OSUItem *item = [[[OSUItem alloc] initWithRSSElement:[nodes objectAtIndex:nodeIndex] error:&itemError] autorelease];
        if (!item) {
#ifdef DEBUG	
            NSLog(@"Unable to interpret node %@ as a software update: %@", [nodes objectAtIndex:nodeIndex], itemError);
#endif	    
            if (!firstError)
                firstError = itemError;
        } else if (showOlderVersions || [currentVersion compareToVersionNumber:[item buildVersion]] == NSOrderedAscending)
            // Include the item if it is newer than us; the RSS feed might not be filtering this on our behalf.
            [items addObject:item];
    }
    
    // If we had some matching nodes, but none were usable, return the error for the first
    if ([nodes count] > 0 && [items count] == 0 && firstError) {
        if (outError)
            *outError = firstError;
        return NO;
    }

    [OSUItem setSupersededFlagForItems:items];
    [items makeObjectsPerformSelector:@selector(setAvailablityBasedOnSystemVersion:) withObject:[OFVersionNumber userVisibleOperatingSystemVersionNumber]];
    
    // Note that we go ahead and pass ignored items to the check target; it will handle the ignored flag
    [_checkTarget newVersionsAvailable:[items filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededPredicate]] fromCheck:operation];
    
    return YES;
}

// This is split out so that it can be overridden by more sophisticated subclasses/categories.
- (BOOL)hostAppearsToBeReachable:(NSString *)hostname;
{
    if ([hostname isEqualToString:@"localhost"])
        return YES;  // ummm, I guess so

    // Can't represent the hostname as an ASCII C string --- it's probably bogus. (Might fail when/if unicode DNS ever happens, but we'd need to fix this code to handle that, and it won't affect us unless Omni gets a new domain anyway...
    if (![hostname canBeConvertedToEncoding:NSASCIIStringEncoding]) {
        OBASSERT_NOT_REACHED("Non-ASCII host name");
        return NO;
    }

    // Okay, talk to configd and see if this machine has any network interfaces at all.
    if (_postpone == NULL && ![self _scDynamicStoreConnect]) {
        // Um, something is wrong --- we can't talk to configd! Bail out.
        return NO;
    }

    if (_postpone == NULL || _postpone->store == NULL) {
        OBASSERT_NOT_REACHED("-_scDynamicStoreConnect should have returned NO in this case"); // clang
        return NO;
    }
    
    // TODO: This will fail if the machine has non-IPv4 routes to the outside world. Right now that's not a problem, but if Apple starts supporting IPv6 or whatever in a useful way, we should look at this code again.
    
    CFDictionaryRef ipv4state = SCDynamicStoreCopyValue(_postpone->store, SCKey_GlobalIPv4State);
    if (!ipv4state) {
        // Dude, we don't have any knowledge of IPv4 at all!
        // (This normally indicates a machine with no network interfaces, eg. a laptop, or a desktop machine that is not plugged in / dialed up / talking to an AirtPort / whatever)
        return NO;
    } else {
        BOOL reachable;
        // TODO: Check whether ipv4state is, in fact, a CFDictionary?
        if (!CFDictionaryContainsKey(ipv4state, SCKey_GlobalIPv4State_hasUsefulRoute))
            reachable = NO;  // We have some ipv4 state, but it doesn't look useful
        else
            reachable = YES;  // Might as well give it a try.
        
        // TODO: Should we furthermore try to call SCNetworkCheckReachabilityByName() if we have a router? (Probably not: even if everything is working, it might take a while for that call to return, and we don't want to hang the app for the duration. The fetcher tool can call that.)
        
        CFRelease(ipv4state);
        return reachable;
    }
    
    // NOTREACHED
}

- (BOOL)_shouldLoadAfterWarningUserAboutNewVersion;
{
    OBPRECONDITION(OSUVersionNumber);

    // The first time OSU runs for this user, prompt them that we'll send some info to the network.  We check in 'com.omnigroup.OmniSoftwareUpdate' so that the user only gets this panel once for any OSU version rather than getting peppered with it.
    CFStringRef prefKey = CFSTR("OSUHighestRunVersion");
    CFStringRef prefDomain = CFSTR("com.omnigroup.OmniSoftwareUpdate");

    NSString *str = (NSString *)CFPreferencesCopyAppValue(prefKey, prefDomain);
    OFVersionNumber *highestRunVersion = str ? [[[OFVersionNumber alloc] initWithVersionString:str] autorelease] : nil;
    [str release];
    
    if (highestRunVersion && [highestRunVersion compareToVersionNumber:OSUVersionNumber] != NSOrderedAscending)
        return YES;

    // Unconditionally update preferences so that this panel doesn't come up again.
    CFPreferencesSetAppValue(prefKey, [OSUVersionNumber cleanVersionString], prefDomain);
    CFPreferencesAppSynchronize(prefDomain);

    // Version 2009 actually sends the same info as version 2004, but does so in a different format. No need to re-ask the user about details of transfer encoding.
    if (highestRunVersion != nil && OSUVersionNumber != nil &&
        [highestRunVersion componentCount] == 1 && [highestRunVersion componentAtIndex:0] == 2004 &&
        [OSUVersionNumber componentCount] == 1 && [OSUVersionNumber componentAtIndex:0] == 2009) {
        // Manufacture some consent.
        return YES;
    }
    
    BOOL hasSeenPreviousVersion = (highestRunVersion != nil);
    
    OSUPrivacyNoticeResult rc = [[OSUController sharedController] runPrivacyNoticePanelHavingSeenPreviousVersion:hasSeenPreviousVersion];
    if (rc == OSUPrivacyNoticeResultOK)
        return [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue];

    OAPreferenceController *prefsController = [OAPreferenceController sharedPreferenceController];
    [prefsController showPreferencesPanel:nil];
    [prefsController setCurrentClientByClassName:NSStringFromClass([OSUPreferences class])];
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
            canCheckImmediately = [self hostAppearsToBeReachable:urlHost];
        }
    }

    if (canCheckImmediately && (_postpone != NULL)) {
        // Tear down the network-watching stuff.
#ifdef DEBUG
        NSLog(@"%@: no longer watching for network changes", NSStringFromClass(self->isa));
#endif
        [self _scDynamicStoreDisconnect];
    }

    // Set up the network-watching stuff if necessary.
    if (!canCheckImmediately) {
        BOOL connected;
        
        if (_postpone == nil)
            connected = [self _scDynamicStoreConnect];
        else
            connected = YES;

        if (connected) {
#ifdef DEBUG
            NSLog(@"%@: no network. will watch for changes.", NSStringFromClass(self->isa));
#endif
        } else {
#ifdef DEBUG
            NSLog(@"Cannot connect to configd. Will not automatically perform software update.");
#endif	    
        }
    }

    return (!canCheckImmediately);
}

static void networkInterfaceWatcherCallback(SCDynamicStoreRef store, CFArrayRef keys, void *info)
{
    OSUChecker *self = info;
#ifdef DEBUG
    NSLog(@"%@: Network configuration has changed", NSStringFromClass(self->isa));
#endif
    [self _initiateCheck];
}

- (void)_scDynamicStoreDisconnect;
{
    if (_postpone == NULL)
        return;

    if (_postpone->loopSource) {
        CFRunLoopSourceInvalidate(_postpone->loopSource);
        CFRelease(_postpone->loopSource);
        _postpone->loopSource = NULL;
    }
    
    CFRelease(_postpone->store);
    _postpone->store = NULL;
    
    free(_postpone);
    _postpone = NULL;
}

- (BOOL)_scDynamicStoreConnect;
{
    // SystemConfig keys to watch. These keys reflect the highest layer of the network stack, after link activity is detected, DHCP or whatever has completed, etc.
    NSArray *watchedRegexps = [NSArray arrayWithObject:@"State:/Network/Global/.*"];

    _postpone = calloc(1, sizeof(*_postpone));
    if (!_postpone)
        goto error0;

    _postpone->loopSource = NULL;

    // We don't do any retain/release stuff here since we will always deallocate the dynamic store connection before we deallocate ourselves.
    _postpone->callbackContext.version = 0;
    _postpone->callbackContext.info = self;
    _postpone->callbackContext.retain = NULL;
    _postpone->callbackContext.release = NULL;
    _postpone->callbackContext.copyDescription = NULL;

    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("OSUChecker"), networkInterfaceWatcherCallback, &(_postpone->callbackContext));
    if (!store)
        goto error1;

    if (!SCDynamicStoreSetNotificationKeys(store, NULL, (CFArrayRef)watchedRegexps))
        goto error2;
    
    if(!(_postpone->loopSource = SCDynamicStoreCreateRunLoopSource(NULL, store, 0)))
        goto error2;

    _postpone->store = store;

    CFRunLoopAddSource(CFRunLoopGetCurrent(), _postpone->loopSource, kCFRunLoopCommonModes);

    return YES;

error2:
    CFRelease(store);
    
error1:
    {
        free(_postpone);
#ifdef DEBUG
        int sysconfigError = SCError();
        NSLog(@"%@: SystemConfiguration error: %s (%d)", NSStringFromClass(self->isa), SCErrorString(sysconfigError), sysconfigError);
#endif	
    }
error0:
        return NO;
}

@end
