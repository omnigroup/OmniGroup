// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFNetStateNotifier.h>

#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFNetStateRegistration.h>
#import <Foundation/NSNetServices.h>
#import <Foundation/NSMapTable.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif

OB_REQUIRE_ARC

RCS_ID("$Id$")

@interface OFNetStateRegistrationEntry : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSDictionary *txtRecord;
@end
@implementation OFNetStateRegistrationEntry
@end


NSInteger OFNetStateNotifierDebug;

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
    NSMutableArray *_resolvingServices;
    NSMapTable *_serviceToEntry;
    NSMapTable *_serviceToReportedVersion;
}

+ (void)initialize;
{
    OBINITIALIZE;
    OBInitializeDebugLogLevel(OFNetStateNotifierDebug);
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
    _resolvingServices = [NSMutableArray new];
    
    // NSNetService instances you get back from various callbacks will not necessarily be pointer-equal! In particular, -netServiceBrowser:didRemoveService:moreComing: will get passed an instance that is not pointer equal to the previously passed service. NSNetService implements -isEqual: to do name comparison, so we just need to avoid NSMapTableObjectPointerPersonality for our NSNetService keys.
    _serviceToEntry = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory
                                                valueOptions:NSMapTableStrongMemory|NSMapTableObjectPointerPersonality
                                                    capacity:0];
    _serviceToReportedVersion = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory
                                                          valueOptions:NSMapTableStrongMemory|NSMapTableObjectPointerPersonality
                                                              capacity:0];
    
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
    
    [_browser stop];
    [_browser removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [_browser setDelegate:nil];
    _browser = nil;

    for (NSNetService *service in _resolvingServices) {
        // Clear the delegate first; otherwise -netServiceDidStop: will be called, where we assert the instance isn't in _resolvingServices.
        [service setDelegate:nil]; // though we'd expect to not get it after this, <bug://bugs/49568> (Bonjour server crashed with lots of machines syncing to it) argues differently
        [service stop]; // -resolveWithTimeout: is still running
    }
    [_resolvingServices removeAllObjects];
    
    for (NSNetService *service in _serviceToEntry) {
        [service stopMonitoring]; // Only resolved services have had TXT monitoring started, so those in _resolvingServices haven't
        [service setDelegate:nil];
    }
    [_serviceToEntry removeAllObjects];
    
    // Since we forget our services and stop our browser, the last reported state for each service will be pointer-equal if we get started up again. Maybe we could switch to registration->state, but with multiple network interfaces, we could have a single registration reporting multiple states temporarily (or permanently when mDNS lets entries get stuck, as it does frequently).
    [_serviceToReportedVersion removeAllObjects];
}

- (void)setMonitoredGroupIdentifiers:(NSSet *)monitoredGroupIdentifiers;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([monitoredGroupIdentifiers any:^BOOL(id object){ return [object isKindOfClass:[NSString class]] == NO; }] == nil, "all objects in the set should be NSString instances");
    OBPRECONDITION([monitoredGroupIdentifiers member:_memberIdentifier] == nil); // Individuals aren't groups
    
    DEBUG_NOTIFIER(1, @"monitoring groups %@", monitoredGroupIdentifiers);

    _monitoredGroupIdentifiers = [monitoredGroupIdentifiers copy];
    [self _updateState];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_NOTIFIER(2, @"found service %@, more coming %d", aNetService, moreComing);
    
    if ([_resolvingServices containsObject:aNetService])
        return; // This service is already resolving
    
    [_resolvingServices addObject:aNetService];
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:RESOLVE_TIMEOUT];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_NOTIFIER(1, @"removed service %@, more coming %d", aNetService, moreComing);
    
    [aNetService setDelegate:nil];
    
    if ([_resolvingServices containsObject:aNetService]) {
        [_resolvingServices removeObject:aNetService];
        [aNetService stop]; // If we were still resolving
        OBASSERT([_serviceToEntry objectForKey:aNetService] == nil);
    } else {
        OBASSERT([_serviceToEntry objectForKey:aNetService] != nil);
        [_serviceToEntry removeObjectForKey:aNetService];
        [_serviceToReportedVersion removeObjectForKey:aNetService];
    }

    if (!moreComing) {
        DEBUG_NOTIFIER(2, @"_resolvingServices = %@", _resolvingServices);
        DEBUG_NOTIFIER(2, @"_serviceToEntry = %@", _serviceToEntry);
        DEBUG_NOTIFIER(2, @"_serviceToReportedVersion = %@", _serviceToReportedVersion);
    }
    
    // We don't really need to do this since we'll hold onto its previous states anyway (in case it comes back online).
    //[self _updateState];
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_NOTIFIER(2, @"resolved service %@: hostname=%@", sender, [sender hostName]);
    DEBUG_NOTIFIER(3, @"addresses=%@", [[sender addresses] description]);
    
    [_resolvingServices removeObject:sender];
    
    // And unless we decide to add it to our entries, we don't want it calling us anymore
    [sender setDelegate:nil];
    
    // We assume that NSNetServices participating in this protocol will never change their peer group (the sender should go away and a different one should come back).
    __autoreleasing NSString *errorString;
    NSDictionary *txtRecord = OFNetStateTXTRecordDictionaryFromData([sender TXTRecordData], YES, &errorString);
    if (!txtRecord) {
        NSLog(@"Unable to unarchive TXT record: %@", errorString);
        return;
    }
    
    NSString *groupIdentifier = txtRecord[OFNetStateRegistrationGroupIdentifierKey];
    if ([NSString isEmptyString:groupIdentifier]) {
        DEBUG_NOTIFIER(1, @"service has no peer group %@", sender);
        return;
    }
    
    OFNetStateRegistrationEntry *entry = [OFNetStateRegistrationEntry new];
    entry.name = sender.name;
    entry.txtRecord = txtRecord;

    // Going to keep it; listen for TXT changes for the tails on the other side
    [sender setDelegate:self];
    [sender startMonitoring];
    
    DEBUG_NOTIFIER(1, @"adding entry %@ %@ (TXT %@)", entry, entry.name, txtRecord);
    [_serviceToEntry setObject:entry forKey:sender];
    
    [self _updateState];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([_resolvingServices indexOfObject:sender] != NSNotFound);

#ifdef DEBUG
    NSLog(@"%@: Error resolving service %@: %@", [self shortDescription], sender, errorDict);
#endif
    
    [_resolvingServices removeObject:sender];
}

- (void)netServiceDidStop:(NSNetService *)sender;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([_resolvingServices indexOfObject:sender] == NSNotFound);
    
    // Called when our -resolveWithTimeout: call finishes
    DEBUG_NOTIFIER(2, @"service did stop %@", sender);
}

- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data;
{
    OBPRECONDITION([NSThread isMainThread]);

    /*
     NOTE: The NSNetService -TXTRecordData does NOT update, so we must use the passed in data. Crazy.
     */
    
    OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:sender];
    OBASSERT(entry); // ... should have resolved first.
    if (!entry)
        return;
    
    DEBUG_NOTIFIER(1, @"service did update TXT record %@", sender);
    
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

    [self _updateState];
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
    OBASSERT(_resolvingServices);
    
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
    OBPRECONDITION(_browser != nil);
    
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

- (void)_updateState;
{
    OBPRECONDITION([NSThread isMainThread]);

    id <OFNetStateNotifierDelegate> delegate = _weak_delegate;
    
    /*
     
     UPDATE for note below: In the A->B->A case, the registration doesn't guarantee that other observers will ever see a TXT record for B (mDNS might collapse the two updates into nothing). So, each state update to a registration must produce a unique TXT record. So OFNetStateRegistration includes a version token. If this makes the TXT record too long, we might drop the state entirely and just report the version token (and update it when the state changes).
     
     -----
     
     We cannot remember a set of all previous states and ignore those in the future, at least not without cooperation from the registrations. Consider when a registration's state is based on a hash of its content, without any consideration for a timestamp. In this case if we have a registaration transition from state A, to B, and then back to A, we'd not inform our delegate about the transition back to state A. As a concrete example, a OmniFileExchange container may get a new file and then delete that file. We want to inform our delegate of the deletion.
     
     So, we remember the last seen state for each NSNetService. This could result in more notifications than we really want as a bunch of clients transition between states. We may coalesce notifications for a little bit, which would cut down on this some (can't completely eliminate it with this approach since one peer needs to post a state change to provoke the others to update and then *they* will all post their state changes). If this becomes a problem, we can maybe remember the history of states for each client and make better decisions about whether to notify based on that.
     */
    
    BOOL changed = NO;
    
    for (NSNetService *service in _serviceToEntry) {
        OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
        NSDictionary *txtRecord = entry.txtRecord;

        // Ignore registrations that are from the same member (possibly more than one in the same process, so this is not a host check).
        NSString *memberIdentifier = txtRecord[OFNetStateRegistrationMemberIdentifierKey];
        if ([NSString isEmptyString:memberIdentifier] || [_memberIdentifier isEqual:memberIdentifier])
            continue;
        
        // Ignore invalid TXT records, or those from groups we don't care about.
        NSString *groupIdentifier = txtRecord[OFNetStateRegistrationGroupIdentifierKey];
        if ([NSString isEmptyString:groupIdentifier] || [_monitoredGroupIdentifiers member:groupIdentifier] == nil)
            continue;
        
        // Ignore registrations that haven't published a state yet. An empty string is considered a valid state, unlike the member/group strings (might be a list of document identifiers, so the empty string would be "no documents").
        NSString *state = txtRecord[OFNetStateRegistrationStateKey];
        if (!state)
            continue;
        
        NSString *version = txtRecord[OFNetStateRegistrationVersionKey];
        if (!version) {
            OBASSERT_NOT_REACHED("Bad client? Should include a version if there is a state");
            continue;
        }
        
        NSString *reportedVersion = [_serviceToReportedVersion objectForKey:service];
        if (OFNOTEQUAL(version, reportedVersion)) {
            DEBUG_NOTIFIER(1, @"State version of service %@ changed from %@ to %@", service, version, reportedVersion);
            [_serviceToReportedVersion setObject:version forKey:service];
            changed = YES;
        }
    }
    
    if (changed) {
        DEBUG_NOTIFIER(1, @"Notifying delegate of change %@", [(id)delegate shortDescription]);
        [delegate netStateNotifierStateChanged:self];
    }
}

@end
