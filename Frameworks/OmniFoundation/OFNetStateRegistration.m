// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFNetStateRegistration.h>

#import <OmniBase/NSError-OBUtilities.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <Foundation/Foundation.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#import <UIKit/UIDevice.h>
#import <sys/socket.h>
#import <netinet/in.h>
#else
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#import <OmniFoundation/OFController.h>
#endif
#import <dns_sd.h>
#include <netdb.h>

OB_REQUIRE_ARC

static OFDeclareDebugLogLevel(OFNetStateRegistrationDebug);
#define DEBUG_REGISTRATION(level, format, ...) do { \
    if (OFNetStateRegistrationDebug >= (level)) \
        NSLog(@"STATE REGISTRATION %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)


// <http://www.dns-sd.org/ServiceTypes.html> Short name of protocol, fourteen characters maximum, conforming to normal DNS host name rules: Only lower-case letters, digits, and hyphens; must begin and end with lower-case letter or digit.

#if 0 && defined(DEBUG)
NSString * const OFNetStateServiceType = @"_omnidebug._tcp."; // Different service type to make it easier to work on local builds w/o seeing chatter from a zillion other devices on the network.
#else
NSString * const OFNetStateServiceType = @"_omnistate._tcp."; // OBFinishPorting <bug:///147854> (Frameworks-iOS Engineering: Register _omnistate._tcp.)
#endif

#ifdef USE_WIDE
NSString * const OFNetStateServiceDomain = @""; // can go across Back to my Mac
#else
NSString * const OFNetStateServiceDomain = @"local.";
#endif

RCS_ID("$Id$")

/*
 THREADING NOTES:
 
 Calls to this class can be made from any thread/queue (just one calling thread/serial queue, not multiple), but the NSNetService should be used only on the main queue (since we have to schedule it in a runloop and we don't want to do so in a transient runloop for a worker thread/queue).
 We use the _service ivar on the calling thread, store it in a strong local and then invoke blocks on the main queue.
 The NSNetService is potentially initialized on a non-main queue, and depending on the vagaries of reference counting, it might be deallocated on a background queue. But, all the runloop registration/deregistration happens on the main queue.
 
 Update coalescing:
 
 If you update your TXT record too quickly, mDNSResponder will bleat wildly to the console log:

   3/21/13 3:01:38.738 PM mDNSResponder[36]: Excessive update rate for jWOlAmmA4a1\032fyHotaIF7vq._omnistate._tcp.local.; delaying announcement by 2 seconds

 So, we should coalesce updates ourselves. This could be tricky if we want to ensure that the "last" update has a chance to be seen. If -invalidate is called while we have a pending update, it could get dropped. Maybe we don't care.
 
 */

// When mDNSResponder starts complaining, it starts by delaying our announcement by one second. But, if we keep up a constant stream of updates, it will still complain at longer and longer coalescing intervals. Experimentally, we can do three second updates for a sustainted period and not get mDNSResponder complaints (obviously this could change in the future).
static const NSTimeInterval kCoalesceTimeInterval = 3;

@implementation OFNetStateRegistration
{
    int _socket;
    in_port_t _port;
    
    NSNetService *_service;
    NSString *_version;
    
    // Main thread state for coalescing updates
    NSTimeInterval _lastUpdateTimeInterval;
    NSTimer *_delayedUpdateTimer;
    NSData *_delayedUpdateTXTData;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
#ifdef OMNI_ASSERTIONS_ON
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // No NSProcessInfo or readable entitlements on iOS, of course...
#else
    if ([[NSProcessInfo processInfo] isSandboxed]) {
        NSDictionary *entitlements = [[NSProcessInfo processInfo] effectiveCodeSigningEntitlements:NULL];
        
        // Assert that we have network server entitlement, or this ain't gonna work
        OBASSERT([[entitlements objectForKey:@"com.apple.security.network.server"] boolValue]);
    }
#endif
#endif
}

static NSString * const OFNetStateRegistrationGroupTerminator = @" ";

- initWithGroupIdentifier:(NSString *)groupIdentifier memberIdentifier:(NSString *)memberIdentifier name:(NSString *)name state:(NSData *)state;
{
    OBPRECONDITION(![NSString isEmptyString:groupIdentifier]);
    OBPRECONDITION([groupIdentifier rangeOfString:OFNetStateRegistrationGroupTerminator].location == NSNotFound);
    OBPRECONDITION([groupIdentifier length] < kDNSServiceMaxServiceName); // We put this in the NSNetService name to avoid resolving TXT records on things we don't care about.
    
    OBPRECONDITION(![NSString isEmptyString:memberIdentifier]);
    OBPRECONDITION(OFNOTEQUAL(memberIdentifier, groupIdentifier));

    if (!(self = [super init]))
        return nil;
    
    _groupIdentifier = [groupIdentifier copy];
    _memberIdentifier = [memberIdentifier copy];
    _name = [name copy];
    _localState = [state copy];
    _version = OFXMLCreateID();
    
    _registrationIdentifier = OFXMLCreateID();
    _socket = -1;
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    BOOL inForeground = ([OFSharedApplication() applicationState] != UIApplicationStateBackground);
#else
    BOOL inForeground = YES;
#endif
    if (inForeground)
        [self _publishService];
    
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
    if (_service)
        [self invalidate];
}

- (void)invalidate;
{
    OBPRECONDITION(_service);
    
    DEBUG_REGISTRATION(2, @"invalidating");
    
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
}

NSString * const OFNetStateRegistrationGroupIdentifierKey = @"g";
NSString * const OFNetStateRegistrationMemberIdentifierKey = @"m";
NSString * const OFNetStateRegistrationStateKey = @"s";
NSString * const OFNetStateRegistrationVersionKey = @"v";

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

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@ %@ %@>", NSStringFromClass([self class]), self, _name, _memberIdentifier, _registrationIdentifier];
}

#pragma mark - Private

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)_applicationDidEnterBackground:(NSNotification *)notification;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard
    if (_service)
        [self invalidate];
}

- (void)_applicationWillEnterForeground:(NSNotification *)notification;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_service == nil);
    
    if (!_service)
        [self _publishService];
}
#endif

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

    NSNetService *service = _service;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        NSTimeInterval nextAllowedUpdateInterval = _lastUpdateTimeInterval + kCoalesceTimeInterval;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval delayInterval = (nextAllowedUpdateInterval - now);
        if (delayInterval > 0) {
            _delayedUpdateTXTData = [txtData copy];
            if (!_delayedUpdateTimer) {
                // Pass the NSNetService we had at the time along rather than reading _service again when this fires.
                DEBUG_REGISTRATION(1, @"Delaying TXT record update for %g seconds", delayInterval);
                _delayedUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:delayInterval target:self selector:@selector(_performDelayedTXTDataUpdate:) userInfo:service repeats:NO];
            }
        } else
            _updateTXTRecord(self, service, txtData);
    }];
}

- (void)_performDelayedTXTDataUpdate:(NSTimer *)timer;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_REGISTRATION(1, @"Performing delayed TXT record update");

    if (_delayedUpdateTimer == nil) {
        // We don't cancel the timer immediately in -invalidate since we have to dispatch to the main queue. This might give it time to fire.
        OBASSERT(_service == nil);
        return;
    }
    
    NSNetService *service = timer.userInfo;
    
    NSData *txtData = _delayedUpdateTXTData;
    _delayedUpdateTXTData = nil;
    
    [_delayedUpdateTimer invalidate];
    _delayedUpdateTimer = nil;
    
    _updateTXTRecord(self, service, txtData);
}

static void _updateTXTRecord(OFNetStateRegistration *self, NSNetService *service, NSData *txtData)
{
    if (![service setTXTRecordData:txtData] && ![txtData isEqual:[service TXTRecordData]]) {
        NSLog(@"%@: unable to set TXT record of %@ to %@", self, service, [txtData unadornedLowercaseHexString]);
        OBASSERT_NOT_REACHED("What happened that prevented setting the TXT record?");
    } else {
        DEBUG_REGISTRATION(2, "Set TXT data on service %@ to %@", service, txtData);
    }
    self->_lastUpdateTimeInterval = [NSDate timeIntervalSinceReferenceDate];
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
    OBPRECONDITION(_socket < 0);
    
    __autoreleasing NSError *error;
    _socket = [[self class] _createSocketBoundToLocalPort:&_port requestedPort:0 error:&error];
    if (_socket < 0) {
        // One possible failure is NSPOSIXErrorDomain+EPERM for sandboxed applications
        NSLog(@"Error creating socket for network state registration: %@", [error toPropertyList]);
    }
    
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
    _service = [[NSNetService alloc] initWithDomain:OFNetStateServiceDomain type:OFNetStateServiceType name:serviceName port:_port];
    OBASSERT(_service);
    
    NSNetService *service = _service;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [service scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [service publish];
    }];
    
    [self _queueTXTRecordUpdate]; // Update our TXT data; doing this before -publish fails.
}

+ (int)_createSocketBoundToLocalPort:(in_port_t *)outPort requestedPort:(in_port_t)requestedPort error:(NSError **)outError;
{    
    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) {
        OBErrorWithErrno(outError, OMNI_ERRNO(), "socket", @"", @"Unable to create socket descriptor");
        OFError(outError, OFNetStateRegistrationCannotCreateSocket, NSLocalizedStringFromTableInBundle(@"Cannot create socket.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), @"Unable to create socket descriptor.");
        return -1;
    }
    
    struct sockaddr_in ipv4;
    bzero(&ipv4, sizeof(ipv4));
    socklen_t socketAddressLength = sizeof(ipv4);
    ipv4.sin_len = sizeof(ipv4);
    ipv4.sin_family = AF_INET;
    ipv4.sin_addr.s_addr = htonl(INADDR_ANY);
    ipv4.sin_port = htons(requestedPort); // 0 means for the system to pick an available port
    
    if (bind(fd, (struct sockaddr *)&ipv4, socketAddressLength) < 0) {
        close(fd);
        OBErrorWithErrno(outError, OMNI_ERRNO(), "bind", @"", @"Unable to bind socket.");
        OFError(outError, OFNetStateRegistrationCannotCreateSocket, NSLocalizedStringFromTableInBundle(@"Cannot create socket.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), @"Unable to bind socket.");
        return -1;
    }
    
    int shouldReuse = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &shouldReuse, sizeof(shouldReuse)) < 0) {
        close(fd);
        OBErrorWithErrno(outError, OMNI_ERRNO(), "setsockopt", @"SO_REUSEADDR", @"Unable to set socket option.");
        OFError(outError, OFNetStateRegistrationCannotCreateSocket, NSLocalizedStringFromTableInBundle(@"Cannot create socket.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), @"Unable to set socket option.");
        return NO;
    }
    
    shouldReuse = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &shouldReuse, sizeof(shouldReuse)) < 0) {
        close(fd);
        OBErrorWithErrno(outError, OMNI_ERRNO(), "setsockopt", @"SO_REUSEPORT", @"Unable to set socket option.");
        OFError(outError, OFNetStateRegistrationCannotCreateSocket, NSLocalizedStringFromTableInBundle(@"Cannot create socket.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), @"Unable to set socket option.");
        return NO;
    }
    
    memset(&ipv4, 0, sizeof(ipv4));
    if (getsockname(fd, (struct sockaddr *)&ipv4, &socketAddressLength) < 0) {
        close(fd);
        OBErrorWithErrno(outError, OMNI_ERRNO(), "getsockname", @"", @"Unable to get socket address.");
        OFError(outError, OFNetStateRegistrationCannotCreateSocket, NSLocalizedStringFromTableInBundle(@"Cannot create socket.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), @"Unable to get socket address.");
        return NO;
    }
    
    *outPort = ntohs(ipv4.sin_port);
    return fd;
}

@end

NSData *OFNetStateTXTRecordDataFromDictionary(NSDictionary *dictionary, BOOL addTypePrefixes)
{
    // The TXT records have some undocumented restrictions and some issues that are only documented at the CF level.
    // The total length of the UTF-8 representation for each key and its data must be < 255.
    // The values can be datas or strings, but if strings, they'll be flattened to data and when unarchiving from the TXT data, the resulting dictionary will have datas for values, no matter the input type.
    // So, we need to record each pref on its own and not record anything of excessive length.
    
    NSMutableDictionary *valueByKey = [NSMutableDictionary dictionary];
    NSArray *keys = [dictionary allKeys];
    NSUInteger keyIndex = [keys count];
    while (keyIndex--) {
        NSString *key = [keys objectAtIndex:keyIndex];
        id value = [dictionary objectForKey:key];
        
        NSString *string;
        
        if ([value isKindOfClass:[NSString class]]) {
            if (addTypePrefixes)
                string = [NSString stringWithFormat:@"s:%@", value];
            else
                string = value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            CFNumberType type = CFNumberGetType((CFNumberRef)value);
            switch (type) {
                case kCFNumberSInt32Type:
                    if (addTypePrefixes)
                        string = [NSString stringWithFormat:@"i:%d", [value intValue]];
                    else
                        string = [NSString stringWithFormat:@"%d", [value intValue]];
                    break;
                case kCFNumberCharType:
                    if (addTypePrefixes)
                        string = [NSString stringWithFormat:@"c:%d", [value intValue]];
                    else
                        string = [NSString stringWithFormat:@"%d", [value intValue]];
                    break;
                default:
                    NSLog(@"Unable to archive key '%@' in TXT record with number of type %ld", key, type);
                    OBASSERT_NOT_REACHED("Add archiving for this type");
                    continue;
            }
        } else {
            NSLog(@"Unable to archive key '%@' in TXT record with value of class %@", key, [value class]);
            OBASSERT_NOT_REACHED("Add archiving for this type");
            continue;
        }
        
        // We could check the key+string length vs 255 and drop individual settings if they would break the whole batch.  But it seems like that might be confusing.  Better to have the client complain that it couldn't get the settings.
        [valueByKey setObject:string forKey:key];
    }
    
    return [NSNetService dataFromTXTRecordDictionary:valueByKey];
}

NSDictionary *OFNetStateTXTRecordDictionaryFromData(NSData *txtRecord, BOOL expectTypePrefixes, __autoreleasing NSString **outErrorString)
{
    OBPRECONDITION(outErrorString != NULL);
    
    if ([txtRecord length] == 0) {
        *outErrorString = @"No TXT record data returned.";
        return nil;
    }
    
    NSDictionary *dict = [NSNetService dictionaryFromTXTRecordData:txtRecord];
    if (!dict) {
        *outErrorString = @"Unable to interpret TXT record data.";
        return nil;
    }
    
    NSMutableDictionary *validatedValues = [NSMutableDictionary dictionary];
    
    NSArray *keys = [dict allKeys];
    NSUInteger keyIndex = [keys count];
    while (keyIndex--) {
        NSString *key = [keys objectAtIndex:keyIndex];
        id value = [dict objectForKey:key];
        
        // If the TXT record is just "foozle", it will be mapped to "foozle"=<null/>
        if (OFNOTNULL(value)) {
            NSString *string;
            if ([value isKindOfClass:[NSString class]])
                string = value;
            else if ([value isKindOfClass:[NSData class]])
                string = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
            
            //NSLog(@"%@: %@", key, string);
            if (!string) {
                *outErrorString = [NSString stringWithFormat: @"Unable to interpret data for TXT record entry \"%@\".", key];
                return nil;
            }
            
            if (expectTypePrefixes) {
                NSUInteger length = [string length];
                if (length < 2) {
                    *outErrorString = [NSString stringWithFormat:@"TXT record entry for \"%@\" is too short.", key];
                    return nil;
                }
                NSString *payload = [string substringFromIndex:2];
                
                unichar type = [string characterAtIndex:0];
                switch (type) {
                    case 's': {
                        value = payload;
                        break;
                    }
                    case 'i': {
                        value = [NSNumber numberWithInt:[payload intValue]];
                        break;
                    }
                    case 'c': {
                        // Probably a bool...
                        value = [NSNumber numberWithChar:(char)[payload intValue]];
                        break;
                    }
                    default:
                        OBASSERT_NOT_REACHED("Implement this type");
                        *outErrorString = [NSString stringWithFormat:@"Unable to handle TXT record entry with type '%c' for key \"%@\".", type, key];
                        return nil;
                }
            } else {
                value = string;
            }
        }
        
        if (value)
            [validatedValues setObject:value forKey:key];
    }
    
    return validatedValues;
}
