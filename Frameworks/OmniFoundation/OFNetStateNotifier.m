// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFNetStateNotifier.h>

#import <Foundation/Foundation.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFNetStateRegistration.h>
#import <OmniFoundation/OFPreference.h>
#import <Foundation/NSNetServices.h>
#import <Foundation/NSMapTable.h>

#if !OF_ENABLE_NET_STATE
#error Should not be in the target
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif

OB_REQUIRE_ARC

RCS_ID("$Id$")

@interface OFNetStateRegistrationEntry : NSObject
@property(nonatomic,readonly) NSTimeInterval discoveryTimeInterval;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,assign) BOOL resolveStarted; // At least on 10.9b5, we can get multiple calls to -netServiceDidResolveAddress:.
@property(nonatomic,assign) BOOL resolveReceived;
@property(nonatomic,assign) BOOL resolveStopped;
@property(nonatomic,assign) BOOL monitoring;
@property(nonatomic,copy) NSDictionary *txtRecord;
@property(nonatomic,copy) NSString *reportedVersion;
@end
@implementation OFNetStateRegistrationEntry

- init;
{
    if (!(self = [super init]))
        return nil;
    
    _discoveryTimeInterval = [NSDate timeIntervalSinceReferenceDate];
    
    return self;
}

- (NSComparisonResult)comparyByDiscoveryTimeInterval:(OFNetStateRegistrationEntry *)otherEntry;
{
    if (_discoveryTimeInterval < otherEntry->_discoveryTimeInterval)
        return NSOrderedAscending;
    if (_discoveryTimeInterval > otherEntry->_discoveryTimeInterval)
        return NSOrderedDescending;
    
    OBASSERT_NOT_REACHED("Really discovered two instances this close in time?");
    return NSOrderedSame;
}

- (NSString *)shortDescription;
{
    NSString *resolve;
    if (_resolveStopped)
        resolve = @"done";
    else if (_resolveStarted)
        resolve = @"started";
    else
        resolve = @"none";
    
    return [NSString stringWithFormat:@"<%@:%p \"%@\" resolve:%@ monitor:%@", NSStringFromClass([self class]), self, _name, resolve, _monitoring ? @"on" : @"off"];
}

@end


static OFDeclareDebugLogLevel(OFNetStateNotifierDebug);
#define DEBUG_NOTIFIER(level, format, ...) do { \
    if (OFNetStateNotifierDebug >= (level)) \
        NSLog(@"STATE NOTIFIER %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)


#define RESOLVE_TIMEOUT (5.0)

@interface OFNetStateNotifier () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@end

@implementation OFNetStateNotifier
{
    NSNetServiceBrowser *_browser;
    NSMapTable *_serviceToEntry;
    NSTimer *_updateStateTimer;
}

@synthesize delegate = _weak_delegate;

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithMemberIdentifier:(NSString *)memberIdentifier;
{
    OBPRECONDITION(![NSString isEmptyString:memberIdentifier]);
    
    if (!(self = [super init]))
        return nil;
    
    _memberIdentifier = [memberIdentifier copy];
    
    // NSNetService instances you get back from various callbacks will not necessarily be pointer-equal! In particular, -netServiceBrowser:didRemoveService:moreComing: will get passed an instance that is not pointer equal to the previously passed service. NSNetService implements -isEqual: to do name comparison, so we just need to avoid NSMapTableObjectPointerPersonality for our NSNetService keys.
    _serviceToEntry = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory
                                                valueOptions:NSMapTableStrongMemory|NSMapTableObjectPointerPersonality
                                                    capacity:0];

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    BOOL inForeground = ([OFSharedApplication() applicationState] != UIApplicationStateBackground);
#else
    BOOL inForeground = YES;
#endif
    if (inForeground)
        [self _startBrowser];
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
#endif
    
    return self;
}

- (void)dealloc;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
    [self invalidate];
}

- (void)invalidate;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_NOTIFIER(1, "Invalidating");
    
    [_updateStateTimer invalidate];
    _updateStateTimer = nil;
    
    [_browser stop];
    [_browser removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [_browser setDelegate:nil];
    _browser = nil;

    // Since we forget our services and stop our browser, the last reported state for each service will be pointer-equal if we get started up again. Maybe we could switch to registration->state, but with multiple network interfaces, we could have a single registration reporting multiple states temporarily (or permanently when mDNS lets entries get stuck, as it does frequently).
    
    for (NSNetService *service in _serviceToEntry) {
        OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
        
        // Clear the delegate first; otherwise -netServiceDidStop: will be called if it is still resolving, but we won't have a record of it any more.
        service.delegate = nil;
        if (entry.resolveStarted && !entry.resolveStopped)
            [service stop];
        else if (entry.monitoring) {
            OBASSERT(entry.resolveStarted);
            OBASSERT(entry.resolveStopped);
            [service stopMonitoring]; // Only resolved services have had TXT monitoring started
        }
    }
    [_serviceToEntry removeAllObjects];
}

- (void)setMonitoredGroupIdentifiers:(NSSet *)monitoredGroupIdentifiers;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([monitoredGroupIdentifiers any:^BOOL(id object){ return [object isKindOfClass:[NSString class]] == NO; }] == nil, "all objects in the set should be NSString instances");
    OBPRECONDITION([monitoredGroupIdentifiers member:_memberIdentifier] == nil); // Individuals aren't groups
    
    DEBUG_NOTIFIER(1, @"setting monitoring groups to %@", monitoredGroupIdentifiers);
    _monitoredGroupIdentifiers = [monitoredGroupIdentifiers copy];

    for (NSNetService *service in _serviceToEntry) {
        OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
    
        BOOL shouldMonitor = [OFNetStateRegistration netServiceName:entry.name matchesAnyGroup:_monitoredGroupIdentifiers];
        
        DEBUG_NOTIFIER(2, @"  reconsidering entry %@, should monitor %d", [entry shortDescription], shouldMonitor);

        if (shouldMonitor) {
            service.delegate = self;
            if (!entry.resolveStarted) {
                entry.resolveStarted = YES;
                [service resolveWithTimeout:RESOLVE_TIMEOUT];
            } else if (entry.resolveReceived && !entry.monitoring) {
                entry.monitoring = YES;
                [service startMonitoring];
            }
        } else {
            service.delegate = nil;
            if (entry.monitoring) {
                entry.monitoring = NO;
                [service stopMonitoring];
            }
        }
    }
    
    [self _queueUpdateState];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_NOTIFIER(2, @"found service %@, more coming %d", service, moreComing);
    
    if ([_serviceToEntry objectForKey:service])
        return; // This service is already resolving
    
    OFNetStateRegistrationEntry *entry = [OFNetStateRegistrationEntry new];
    entry.name = service.name;
    [_serviceToEntry setObject:entry forKey:service];

    // Only resolve (and then monitor) the services that are interesting to us. This is better for the network and should help reduce the impact of <bug:///92583> (Crash in Bonjour/mDNS/NSNetService)
    if ([OFNetStateRegistration netServiceName:service.name matchesAnyGroup:_monitoredGroupIdentifiers]) {
        entry.resolveStarted = YES;
        service.delegate = self;
        [service resolveWithTimeout:RESOLVE_TIMEOUT];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // This can happen if we are quickly invalidating an old OFNetStateNotifier/OFNetStateRegistration setup and making a new one. NSNetServiceBrowser doesn't keep track of whether it has sent us particular NSNetService instances and will happily send us notifications for services that are disappearing.
    if ([_serviceToEntry objectForKey:service] == nil) {
        OBASSERT(service.delegate == nil);
        return;
    }
    
    DEBUG_NOTIFIER(1, @"removed service %@, more coming %d", service, moreComing);
    
    service.delegate = nil;
    OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
    
    // We used to hold onto the last state of the service in case it came back online -- we aren't any more which means we we could signal a change when a peer comes back online with the same state we'd seen from it before.
    if (entry.resolveStarted && !entry.resolveStopped)
        [service stop];
    if (entry.monitoring)
        [service stopMonitoring];
    [_serviceToEntry removeObjectForKey:service];

    if (!moreComing) {
        DEBUG_NOTIFIER(3, @"_serviceToEntry = %@", _serviceToEntry);
    }
    
    // Observers don't care if old states go offline, only if new ones appear. If this service comes back online, we might treat it as new (we used to store old states -- might need to re-add that).
    //[self _queueUpdateState];
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)service;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_NOTIFIER(2, @"resolved service %@: hostname=%@, TXT=%@", service, [service hostName], [service TXTRecordData]);
    DEBUG_NOTIFIER(3, @"addresses=%@", [[service addresses] description]);
    
    OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
    OBASSERT(entry);
    OBASSERT(entry.resolveStarted);

    // In iOS 8 b5 and 10.10 b5, we often receive spurious <00> TXT updates (which get interpreted as zero entry dictionaries). We'll ignore these (we often get good updates and bad ones, sometimes just bad ones until we try to re-resolve).
    NSData *txtData = [service TXTRecordData];
    if ([txtData length] <= 1) {
        DEBUG_NOTIFIER(1, @"  ... bad TXT record; ignoring");
        return;
    }
    
    // We assume that NSNetServices participating in this protocol will never change their peer group (the service should go away and a different one should come back).
    __autoreleasing NSString *errorString;
    NSDictionary *txtRecord = OFNetStateTXTRecordDictionaryFromData(txtData, YES, &errorString);
    if (!txtRecord) {
        NSLog(@"Unable to unarchive TXT record: %@", errorString);
        service.delegate = nil;
        [_serviceToEntry removeObjectForKey:service]; // Avoid assertions about !resolving and !txtRecord
        return;
    }
    
    // We may not like it, but record the TXT record we got.
    entry.txtRecord = txtRecord;
    entry.resolveReceived = YES;
    
    NSString *groupIdentifier = txtRecord[OFNetStateRegistrationGroupIdentifierKey];
    if ([NSString isEmptyString:groupIdentifier]) {
        DEBUG_NOTIFIER(1, @"service has no peer group %@", service);
        DEBUG_NOTIFIER(2, @"   ... in TXT %@", [service TXTRecordData]);
        DEBUG_NOTIFIER(2, @"   ... in TXT %@", txtRecord);
        return;
    }
    
    // Going to keep it; listen for TXT changes for the tails on the other side
    if (!entry.monitoring && [OFNetStateRegistration netServiceName:entry.name matchesAnyGroup:_monitoredGroupIdentifiers]) {
        entry.monitoring = YES;
        [service startMonitoring];
    }
    
    DEBUG_NOTIFIER(1, @"service TXT %@ %@ (TXT %@)", entry, entry.name, txtRecord);
    [self _queueUpdateState];
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errorDict;
{
    OBPRECONDITION([NSThread isMainThread]);

    OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
    OBASSERT(entry);
    OBASSERT(entry.resolveStarted);
    
    DEBUG_NOTIFIER(1, @"service did not resolve %@", entry);

#ifdef DEBUG
    NSLog(@"%@: Error resolving service %@: %@", [self shortDescription], service, errorDict);
#endif
}

- (void)netServiceDidStop:(NSNetService *)service;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
    OBASSERT(entry);
    OBASSERT(entry.resolveStarted == YES);
    OBASSERT(entry.resolveStopped == NO);

    entry.resolveStopped = YES;
    
    // Called when our -resolveWithTimeout: call finishes. We shuld have received -netServiceDidResolveAddress: or -netService:didNotResolve: already
    DEBUG_NOTIFIER(2, @"service did stop %@, entry %@", service, entry);
    
    // In iOS 8 b5 and 10.10b5, we often get spurious TXT data updates of <00>. We ignore these and try re-resolving.
    if (entry.txtRecord == nil) {
        entry.resolveStopped = NO;
        entry.resolveReceived = NO;
        
        DEBUG_NOTIFIER(1, @"  ... no good TXT records received -- retrying resolve");
        [service resolveWithTimeout:RESOLVE_TIMEOUT];
        return;
    }
    
    // We ignore entries that are still resolving, so we need to update again now that this one has finished.
    [self _queueUpdateState];
}

- (void)netService:(NSNetService *)service didUpdateTXTRecordData:(NSData *)data;
{
    OBPRECONDITION([NSThread isMainThread]);

    /*
     NOTE: The NSNetService -TXTRecordData does NOT update, so we must use the passed in data. Crazy.
     */
    
    OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
    OBASSERT(entry); // ... should have resolved first.
    if (!entry)
        return;
    
    OBASSERT(entry.resolveStarted);
    // OBASSERT(entry.resolveStopped); We get the first TXT record update from our resolve before -netServiceDidStop:.

    DEBUG_NOTIFIER(1, @"service did update TXT record %@ to %@", service, data);
    
    // In iOS 8 b5 and 10.10 b5, we often receive spurious <00> TXT updates (which get interpreted as zero entry dictionaries). We'll ignore these (we often get good updates and bad ones, sometimes just bad ones until we try to re-resolve).
    NSData *txtData = [service TXTRecordData];
    if ([txtData length] <= 1) {
        DEBUG_NOTIFIER(1, @"  ... bad TXT record; ignoring");
        return;
    }

    __autoreleasing NSString *errorString;
    NSDictionary *txtRecord = OFNetStateTXTRecordDictionaryFromData(data, YES, &errorString);
    if (!txtRecord) {
        NSLog(@"Unable to unarchive TXT record: %@", errorString);
        return;
    }
    
    if ([entry.txtRecord isEqual:txtRecord]) {
        DEBUG_NOTIFIER(1, @" ... TXT the same, bailing: %@", txtRecord);
        return;
    }
    
    entry.txtRecord = txtRecord;
    DEBUG_NOTIFIER(1, @" ... TXT now %@", txtRecord);

    [self _queueUpdateState];
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@ %@>", NSStringFromClass([self class]), self, _name, _memberIdentifier];
}

#pragma mark - Private

- (void)_startBrowser;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(!_browser);
    
    OBASSERT(_serviceToEntry);
    
    DEBUG_NOTIFIER(2, @"starting search");
    _browser = [[NSNetServiceBrowser alloc] init];
    [_browser setDelegate:self];
    [_browser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [_browser searchForServicesOfType:OFNetStateServiceType inDomain:OFNetStateServiceDomain];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)_applicationDidEnterBackground:(NSNotification *)notification;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard
    if (_browser)
        [self invalidate];
}

- (void)_applicationWillEnterForeground:(NSNotification *)notification;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_browser == nil);
    
    if (!_browser)
        [self _startBrowser];
}
#endif

static const NSTimeInterval kUpdateStateCoalesceInterval = 0.25;

- (void)_queueUpdateState;
{
    OBPRECONDITION([NSThread isMainThread]);

    // Coalesce our work in notifying our delegate.
    if (_updateStateTimer)
        return;
    _updateStateTimer = [NSTimer scheduledTimerWithTimeInterval:kUpdateStateCoalesceInterval target:self selector:@selector(_updateStateTimerFired:) userInfo:nil repeats:NO];
    [_updateStateTimer setTolerance:kUpdateStateCoalesceInterval];
}

- (void)_updateStateTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION([NSThread isMainThread]);

    [_updateStateTimer invalidate];
    _updateStateTimer = nil;
    
    id <OFNetStateNotifierDelegate> delegate = _weak_delegate;
    
    if (OFNetStateNotifierDebug >= 2) {
        // No good -allValues on NSMapTable (and -dictionaryRepresentation doesn't work since NSNetService doesn't conform to NSCopying
        NSMutableArray *entries = [NSMutableArray array];
        for (NSNetService *service in _serviceToEntry) {
            OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
            if (entry.monitoring == NO && OFNetStateNotifierDebug < 3)
                continue; // Don't spew log information for everything in the world unless the debug level is really elevated
            [entries addObject:entry];
        }
        [entries sortUsingSelector:@selector(comparyByDiscoveryTimeInterval:)];
        
        DEBUG_NOTIFIER(2, @"Updating state based on monitored groups %@ and entries:\n%@", [[[_monitoredGroupIdentifiers allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "], [entries arrayByPerformingSelector:@selector(shortDescription)]);
    }
    
    /*
     
     UPDATE for note below: In the A->B->A case, the registration doesn't guarantee that other observers will ever see a TXT record for B (mDNS might collapse the two updates into nothing). So, each state update to a registration must produce a unique TXT record. So OFNetStateRegistration includes a version token. If this makes the TXT record too long, we might drop the state entirely and just report the version token (and update it when the state changes).
     
     -----
     
     We cannot remember a set of all previous states and ignore those in the future, at least not without cooperation from the registrations. Consider when a registration's state is based on a hash of its content, without any consideration for a timestamp. In this case if we have a registaration transition from state A, to B, and then back to A, we'd not inform our delegate about the transition back to state A. As a concrete example, a OmniFileExchange container may get a new file and then delete that file. We want to inform our delegate of the deletion.
     
     So, we remember the last seen state for each NSNetService. This could result in more notifications than we really want as a bunch of clients transition between states. We may coalesce notifications for a little bit, which would cut down on this some (can't completely eliminate it with this approach since one peer needs to post a state change to provoke the others to update and then *they* will all post their state changes). If this becomes a problem, we can maybe remember the history of states for each client and make better decisions about whether to notify based on that.
     */
    
    BOOL changed = NO;
    
    for (NSNetService *service in _serviceToEntry) {
        OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
        
        NSInteger debugLevel = entry.monitoring ? 2 : 3;

        DEBUG_NOTIFIER(debugLevel, @"  looking for updates for entry %@", [entry shortDescription]);

        if (!entry.resolveStopped) {
            DEBUG_NOTIFIER(debugLevel, @"  still resolving");
            continue;
        }
        
        NSDictionary *txtRecord = entry.txtRecord;
        if (!txtRecord) {
            // Failed to resolve or we aren't even interested in it.
            DEBUG_NOTIFIER(debugLevel, @"  no TXT record -- failed to resolve or we haven't asked it to");
            continue;
        }
        
        // Ignore registrations that are from the same member (possibly more than one in the same process, so this is not a host check).
        NSString *memberIdentifier = txtRecord[OFNetStateRegistrationMemberIdentifierKey];
        if ([NSString isEmptyString:memberIdentifier] || [_memberIdentifier isEqual:memberIdentifier]) {
            DEBUG_NOTIFIER(debugLevel, @"  no member identifier (or it is us)");
            continue;
        }
        
        // Ignore invalid TXT records, or those from groups we don't care about.
        NSString *groupIdentifier = txtRecord[OFNetStateRegistrationGroupIdentifierKey];
        if ([NSString isEmptyString:groupIdentifier] || [_monitoredGroupIdentifiers member:groupIdentifier] == nil) {
            DEBUG_NOTIFIER(debugLevel, @"  no group identifier, or it is not a monitored group");
            continue;
        }
        
        // Ignore registrations that haven't published a state yet. An empty string is considered a valid state, unlike the member/group strings (might be a list of document identifiers, so the empty string would be "no documents").
        NSString *state = txtRecord[OFNetStateRegistrationStateKey];
        if (!state) {
            DEBUG_NOTIFIER(debugLevel, @"  no state");
            continue;
        }
        
        NSString *version = txtRecord[OFNetStateRegistrationVersionKey];
        if (!version) {
            OBASSERT_NOT_REACHED("Bad client? Should include a version if there is a state");
            DEBUG_NOTIFIER(debugLevel, @"  no version");
            continue;
        }
        
        NSString *reportedVersion = entry.reportedVersion;
        if (OFNOTEQUAL(version, reportedVersion)) {
            DEBUG_NOTIFIER(1, @"State version of service %@ changed from %@ to %@", service, version, reportedVersion);
            entry.reportedVersion = version;
            changed = YES;
        } else {
            DEBUG_NOTIFIER(debugLevel, @"  reported version hasn't changed");
        }
    }
    
    if (changed) {
        DEBUG_NOTIFIER(1, @"Notifying delegate of change %@", [(id)delegate shortDescription]);
        [delegate netStateNotifierStateChanged:self];
    }
}

@end
