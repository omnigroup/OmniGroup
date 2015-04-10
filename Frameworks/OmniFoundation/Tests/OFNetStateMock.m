// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFNetStateMock.h"

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

#import <dns_sd.h>

RCS_ID("$Id$")

OB_REQUIRE_ARC

static NSInteger OFNetStateNotifierDebug;

#define DEBUG_NOTIFIER(level, format, ...) do { \
    if (OFNetStateNotifierDebug >= (level)) \
        NSLog(@"STATE NOTIFIER MOCK %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

static NSInteger OFNetStateRegistrationDebug;

#define DEBUG_REGISTRATION(level, format, ...) do { \
    if (OFNetStateRegistrationDebug >= (level)) \
        NSLog(@"STATE REGISTRATION MOCK %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

// NSNetServices will unique their names by some random rules and do identity based on address/port or some such. We'll use a random identifier.
static NSString * OFNetServiceEntryName = @"name";
static NSString * OFNetServiceEntryData = @"data";


@interface OFNetStateRegistrationMock : NSObject

+ (BOOL)netServiceName:(NSString *)serviceName matchesAnyGroup:(NSSet *)groupIdentifiers;

- initWithGroupIdentifier:(NSString *)groupIdentifier memberIdentifier:(NSString *)memberIdentifier name:(NSString *)name state:(NSData *)state;

- (void)invalidate;

@property(nonatomic,readonly) NSString *name; // Debugging; this will be included in the service name, but might be truncated
@property(nonatomic,readonly) NSString *registrationIdentifier; // Unique to this specific instance
@property(nonatomic,readonly) NSString *groupIdentifier;
@property(nonatomic,readonly) NSString *memberIdentifier;

// Some opaque data describing the current local state. If this is too long, its SHA-1 will be used instead.
@property(nonatomic,copy) NSData *localState;

@end

@interface OFNetStateNotifierMock ()

+ (void)_publishEntry:(NSDictionary *)entry forIdentifier:(NSString *)identifier;

@property(nonatomic,readonly) NSString *memberIdentifier;
@property(nonatomic,copy) NSSet *monitoredGroupIdentifiers;

@property(nonatomic,weak) id <OFNetStateNotifierDelegate> delegate;
@property(nonatomic,copy) NSString *name;

@end

@implementation OFNetStateNotifierMock
{
    NSTimer *_updateStateTimer;
    NSDictionary *_entryByIdentifier;
    NSMutableDictionary *_reportedVersionByIdentifier;
}

static NSOperationQueue *NetStateQueue = nil;
static NSMutableDictionary *NetStateEntryByIdentifier = nil;
static NSMutableArray *NetStateNotifiers = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    NetStateQueue = [[NSOperationQueue alloc] init];
    NetStateQueue.name = @"com.omnigroup.OmniFoundation.OFNetStateNotifierMock";
    NetStateQueue.maxConcurrentOperationCount = 1;
    
    NetStateEntryByIdentifier = [[NSMutableDictionary alloc] init];
    NetStateNotifiers = [[NSMutableArray alloc] init];
}

+ (void)install;
{
    Class OFNetStateNotifierClass = object_getClass([OFNetStateNotifier class]);
    OBASSERT(OFNetStateNotifierClass);
    
    Class OFNetStateRegistrationClass = object_getClass([OFNetStateRegistration class]);
    OBASSERT(OFNetStateRegistrationClass);
    
    OBReplaceMethodImplementation(OFNetStateNotifierClass, @selector(allocWithZone:), imp_implementationWithBlock(^(Class cls, NSZone *zone){
        // This method replacement confuses ARC, unsurprisingly.
        id result = [OFNetStateNotifierMock allocWithZone:zone];
        OBStrongRetain(result);
        return result;
    }));
    OBReplaceMethodImplementation(OFNetStateRegistrationClass, @selector(allocWithZone:), imp_implementationWithBlock(^(Class cls, NSZone *zone){
        // This method replacement confuses ARC, unsurprisingly.
        id result = [OFNetStateRegistrationMock allocWithZone:zone];
        OBStrongRetain(result);
        return result;
    }));
}

+ (void)_publishEntry:(NSDictionary *)entry forIdentifier:(NSString *)identifier;
{
    [NetStateQueue addOperationWithBlock:^{
        if (entry)
            NetStateEntryByIdentifier[identifier] = entry;
        else
            [NetStateEntryByIdentifier removeObjectForKey:identifier];
        
        NSDictionary *entries = [NetStateEntryByIdentifier copy];
        NSArray *notifiers = [NetStateNotifiers copy];
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            for (OFNetStateNotifierMock *mock in notifiers)
                [mock _processEntries:entries];
        }];
    }];
}

@synthesize delegate = _weak_delegate;

- initWithMemberIdentifier:(NSString *)memberIdentifier;
{
    if (!(self = [super init]))
        return nil;
    
    _memberIdentifier = [memberIdentifier copy];
    _reportedVersionByIdentifier = [[NSMutableDictionary alloc] init];
    
    [NetStateQueue addOperationWithBlock:^{
        [NetStateNotifiers addObject:self];
        
        // NSNetServiceBrowser would have eventually told us about the registered entries
        NSDictionary *entries = [NetStateEntryByIdentifier copy];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _processEntries:entries];
        }];
    }];
    
    return self;
}

- (void)invalidate;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_NOTIFIER(1, "Invalidating");
    
    _weak_delegate = nil;
    
    [_updateStateTimer invalidate];
    _updateStateTimer = nil;

    [NetStateQueue addOperationWithBlock:^{
        [NetStateNotifiers removeObject:self];
    }];
}

- (void)setMonitoredGroupIdentifiers:(NSSet *)monitoredGroupIdentifiers;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (OFISEQUAL(_monitoredGroupIdentifiers, monitoredGroupIdentifiers))
        return;
    
    _monitoredGroupIdentifiers = [monitoredGroupIdentifiers copy];
    
    [self _queueUpdateState];
}

#pragma mark - Private

- (void)_processEntries:(NSDictionary *)entryByIdentifier;
{
    _entryByIdentifier = [entryByIdentifier copy];
    [self _queueUpdateState];
}

static const NSTimeInterval kUpdateStateCoalesceInterval = 0.05;

- (void)_queueUpdateState;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Coalesce our work in notifying our delegate.
    if (_updateStateTimer)
        return;
    _updateStateTimer = [NSTimer scheduledTimerWithTimeInterval:kUpdateStateCoalesceInterval target:self selector:@selector(_updateStateTimerFired:) userInfo:nil repeats:NO];
}

- (void)_updateStateTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [_updateStateTimer invalidate];
    _updateStateTimer = nil;
    
    id <OFNetStateNotifierDelegate> delegate = _weak_delegate;
    
#if 0
    if (OFNetStateNotifierDebug >= 2) {
        // No good -allValues on NSMapTable (and -dictionaryRepresentation doesn't work since NSNetService doesn't conform to NSCopying
        NSMutableArray *entries = [NSMutableArray array];
        for (NSNetService *service in _serviceToEntry) {
            OFNetStateRegistrationEntry *entry = [_serviceToEntry objectForKey:service];
            [entries addObject:entry];
        }
        [entries sortUsingSelector:@selector(comparyByDiscoveryTimeInterval:)];
        
        DEBUG_NOTIFIER(0, @"Updating state based on monitored groups %@ and entries:\n%@", [[_monitoredGroupIdentifiers allObjects] sortedArrayUsingSelector:@selector(compare:)], [entries arrayByPerformingSelector:@selector(shortDescription)]);
    }
#endif
    
    /*
     
     UPDATE for note below: In the A->B->A case, the registration doesn't guarantee that other observers will ever see a TXT record for B (mDNS might collapse the two updates into nothing). So, each state update to a registration must produce a unique TXT record. So OFNetStateRegistration includes a version token. If this makes the TXT record too long, we might drop the state entirely and just report the version token (and update it when the state changes).
     
     -----
     
     We cannot remember a set of all previous states and ignore those in the future, at least not without cooperation from the registrations. Consider when a registration's state is based on a hash of its content, without any consideration for a timestamp. In this case if we have a registaration transition from state A, to B, and then back to A, we'd not inform our delegate about the transition back to state A. As a concrete example, a OmniFileExchange container may get a new file and then delete that file. We want to inform our delegate of the deletion.
     
     So, we remember the last seen state for each NSNetService. This could result in more notifications than we really want as a bunch of clients transition between states. We may coalesce notifications for a little bit, which would cut down on this some (can't completely eliminate it with this approach since one peer needs to post a state change to provoke the others to update and then *they* will all post their state changes). If this becomes a problem, we can maybe remember the history of states for each client and make better decisions about whether to notify based on that.
     */
    
    __block BOOL changed = NO;
    
    [_entryByIdentifier enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSDictionary *entry, BOOL *stop) {
        DEBUG_NOTIFIER(2, @"  looking for updates for entry %@", [entry shortDescription]);
        
        __autoreleasing NSString *errorString = nil;
        NSDictionary *txtRecord = OFNetStateTXTRecordDictionaryFromData(entry[OFNetServiceEntryData], YES, &errorString);
        if (!txtRecord) {
            // Failed to resolve or we aren't even interested in it.
            DEBUG_NOTIFIER(2, @"  no TXT record -- failed to resolve or we haven't asked it to: %@", errorString);
            return;
        }
        
        // Ignore registrations that are from the same member (possibly more than one in the same process, so this is not a host check).
        NSString *memberIdentifier = txtRecord[OFNetStateRegistrationMemberIdentifierKey];
        if ([NSString isEmptyString:memberIdentifier] || [_memberIdentifier isEqual:memberIdentifier]) {
            DEBUG_NOTIFIER(2, @"  no member identifier (or it is us)");
            return;
        }
        
        // Ignore invalid TXT records, or those from groups we don't care about.
        NSString *groupIdentifier = txtRecord[OFNetStateRegistrationGroupIdentifierKey];
        if ([NSString isEmptyString:groupIdentifier] || [_monitoredGroupIdentifiers member:groupIdentifier] == nil) {
            DEBUG_NOTIFIER(2, @"  no group identifier, or it is not a monitored group");
            return;
        }
        
        // Ignore registrations that haven't published a state yet. An empty string is considered a valid state, unlike the member/group strings (might be a list of document identifiers, so the empty string would be "no documents").
        NSString *state = txtRecord[OFNetStateRegistrationStateKey];
        if (!state) {
            DEBUG_NOTIFIER(2, @"  no state");
            return;
        }
        
        NSString *version = txtRecord[OFNetStateRegistrationVersionKey];
        if (!version) {
            OBASSERT_NOT_REACHED("Bad client? Should include a version if there is a state");
            DEBUG_NOTIFIER(2, @"  no version");
            return;
        }
        
        NSString *reportedVersion = _reportedVersionByIdentifier[identifier];
        if (OFNOTEQUAL(version, reportedVersion)) {
            DEBUG_NOTIFIER(1, @"State version of service %@ changed from %@ to %@", identifier, version, reportedVersion);
            _reportedVersionByIdentifier[identifier] = version;
            changed = YES;
        } else {
            DEBUG_NOTIFIER(2, @"  reported version hasn't changed");
        }
    }];
    
    if (changed) {
        DEBUG_NOTIFIER(1, @"Notifying delegate of change %@", [(id)delegate shortDescription]);
        [delegate netStateNotifierStateChanged:(OFNetStateNotifier *)self];
    }
}

@end

@interface OFNetServiceMock : NSObject
{
    NSString *_identifier;
    NSData *_txtRecord;
}

- initWithName:(NSString *)name;

@property(nonatomic,readonly) NSString *name;
- (BOOL)setTXTRecordData:(NSData *)data;

@end
@implementation OFNetServiceMock

- (id)initWithName:(NSString *)name;
{
    if (!(self = [super init]))
        return nil;
    
    _identifier = OFXMLCreateID();
    _name = [name copy];
    
    return self;
}

- (BOOL)setTXTRecordData:(NSData *)data;
{
    _txtRecord = [data copy];
    [self publish];
    
    return YES;
}
- (NSData *)TXTRecordData;
{
    return _txtRecord;
}

- (void)publish;
{
    OBASSERT(NetStateQueue);
    
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    if (_name)
        entry[OFNetServiceEntryName] = _name;
    if (_txtRecord)
        entry[OFNetServiceEntryData] = _txtRecord;
    [OFNetStateNotifierMock _publishEntry:entry forIdentifier:_identifier];
}

@end

@implementation OFNetStateRegistrationMock
{
    OFNetServiceMock *_service;
    NSString *_version;
}

static NSString * const OFNetStateRegistrationGroupTerminator = @" ";

- initWithGroupIdentifier:(NSString *)groupIdentifier memberIdentifier:(NSString *)memberIdentifier name:(NSString *)name state:(NSData *)state;
{
    if (!(self = [super init]))
        return nil;
    
    _groupIdentifier = [groupIdentifier copy];
    _memberIdentifier = [memberIdentifier copy];
    _name = [name copy];
    _localState = [state copy];
    _version = OFXMLCreateID();

    _registrationIdentifier = OFXMLCreateID();

    [self _publishService];

    return self;
}

- (void)dealloc;
{
    if (_service)
        [self invalidate];
}

- (void)invalidate;
{
#if 0
    OBPRECONDITION(_service);
    
    DEBUG_REGISTRATION(2, @"invalidating");
    
    _invalidated = YES;
    
    NSNetService *service = _service;
    _service = nil;
    NSTimer *timer = _delayedUpdateTimer;
    _delayedUpdateTimer = nil;
    
    // We could close() this here, but lets not do it until the NSNetService is stopped.
    int serviceSocket = _socket;
    _socket = -1;
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [timer invalidate];
        [service stop];
        [service removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        if (serviceSocket > 0) {
            if (close(serviceSocket) < 0)
                NSLog(@"%s: close -> %d, %s", __PRETTY_FUNCTION__, OMNI_ERRNO(), strerror(OMNI_ERRNO()));
        }
    }];
#endif
}

- (void)setLocalState:(NSData *)state;
{
    // Might get backgrounded and have some background task that finishes up. If we ever get foregrounded again, we'll remember the state to publish.
    //OBPRECONDITION(_service); // not invalidated
    
    if (OFISEQUAL(_localState, state))
        return;
    
    DEBUG_REGISTRATION(1, @"Setting state");
    DEBUG_REGISTRATION(2, @"   ... new value is %@", state);
    
    _localState = [state copy];
    _version = OFXMLCreateID();
    
    if (_localState && _service)
        [self _queueTXTRecordUpdate];
}

- (void)_queueTXTRecordUpdate;
{
    OBPRECONDITION(_service);
    
    NSMutableDictionary *txtRecord = [NSMutableDictionary new];
    
    txtRecord[OFNetStateRegistrationMemberIdentifierKey] = _memberIdentifier;
    
    if (_groupIdentifier)
        txtRecord[OFNetStateRegistrationGroupIdentifierKey] = _groupIdentifier;
    
    if (_localState) {
        DEBUG_REGISTRATION(2, @"_localState %@", _localState);
        NSData *state = _localState;
        if ([state length] > 20) { // SHA-1 digest length
            state = [state sha1Signature];
            DEBUG_REGISTRATION(1, @"state, SHA1 %@", state);
        }
        NSString *stateString = [state ascii85String];
        DEBUG_REGISTRATION(1, @"state, ascii85 %@", stateString);
        
        txtRecord[OFNetStateRegistrationStateKey] = stateString; // We need short strings for Bonjour, so no hex
        
        /*
         Say there are members A and B, both in state S1. If A goes to S2, B hears about this and quickly flaps from S1->S2->S1, then A may not see that B has changed state at all when it may need to. For example, if A creates a document and B deletes it (assuming the state is based on info about the document). A needs to be able to tell that B did this rather than thinking B didn't acknowledge the state.
         
         Right now we don't publish the actual state value to the delegate in OFNetStateNotifier, so it is almost not worth including the state itself in the TXT record. We could probably get away with just sending a version token.
         */
        OBASSERT(![NSString isEmptyString:_version]);
        txtRecord[OFNetStateRegistrationVersionKey] = _version;
    }
    
    NSData *txtData = OFNetStateTXTRecordDataFromDictionary(txtRecord, YES);
    
    DEBUG_REGISTRATION(1, @"txtRecord now %@", txtRecord);
    
    OFNetServiceMock *service = _service;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        _updateTXTRecord(self, service, txtData);
    }];
}

static void _updateTXTRecord(OFNetStateRegistrationMock *self, OFNetServiceMock *service, NSData *txtData)
{
    if (![service setTXTRecordData:txtData] && ![txtData isEqual:[service TXTRecordData]]) {
        NSLog(@"%@: unable to set TXT record of %@ to %@", self, service, [txtData unadornedLowercaseHexString]);
        OBASSERT_NOT_REACHED("What happened that prevented setting the TXT record?");
    }
}

+ (BOOL)netServiceName:(NSString *)serviceName matchesAnyGroup:(NSSet *)groupIdentifiers;
{
    return [groupIdentifiers any:^BOOL(NSString *groupIdentifier) {
        if (![serviceName hasPrefix:groupIdentifier])
            return NO;
        
        // Allow clients that don't append a registration identifier... bad form, but might as well.
        if ([serviceName rangeOfString:OFNetStateRegistrationGroupTerminator].location == [groupIdentifier length])
            return YES;
        
        return NO;
    }] != nil;
}

- (void)_publishService;
{
    OBPRECONDITION(!_service);
    
    // We need the name to be unique, at least within our app, if we want to publish multiple registrations. Without this, if an app publishes several services under different ports and the same name, only one service will appear in dns-sd.
    // If the name is too *long*, then nothing will be published (not even a truncated version).
    // We also encode the group name in our service name so that OFNetStateNotifier can avoid resolving TXT records for un-interesting registrations.
    // NOTE: we don't currently use this since OFNetStateNotifiers can change the groups the monitor, but maybe we should.
    NSString *serviceName = [NSString stringWithFormat:@"%@%@%@", _groupIdentifier, OFNetStateRegistrationGroupTerminator, _registrationIdentifier];
    
    // We need all of this to be present so that our name is unique
    OBASSERT([serviceName length] < kDNSServiceMaxServiceName);
    
    // Then add in as much debug info as we can.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSBundle *controllingBundle = [NSBundle mainBundle];
#else
    NSBundle *controllingBundle = [OFController controllingBundle];
#endif
    NSString *appName = [[controllingBundle infoDictionary] objectForKey:@"CFBundleDisplayName"];
    if (![NSString isEmptyString:appName])
        serviceName = [serviceName stringByAppendingFormat:@" %@", appName];
    if (![NSString isEmptyString:_name])
        serviceName = [serviceName stringByAppendingFormat:@" %@", _name];
    
    // Truncate the service name to make sure it gets registered instead of silently dropped on the floor(!)
    if ([serviceName length] >= kDNSServiceMaxServiceName)
        serviceName = [serviceName substringToIndex:kDNSServiceMaxServiceName-1];
    
    // *Hopefully* this is OK; we're creating the service on whatever thread the instance's owner uses, but not registering it here. This is needed since we want to serialize the 'has a service' checks on the calling thread.
    _service = [[OFNetServiceMock alloc] initWithName:serviceName];
    OBASSERT(_service);
    
    OFNetServiceMock *service = _service;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [service publish];
    }];
    
    [self _queueTXTRecordUpdate]; // Update our TXT data; doing this before -publish fails.
}

@end
