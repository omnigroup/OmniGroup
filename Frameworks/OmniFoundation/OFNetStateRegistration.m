// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFNetStateRegistration.h>

#import <OmniBase/NSError-OBUtilities.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <Foundation/Foundation.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#import <UIKit/UIDevice.h>
#import <sys/socket.h>
#import <netinet/in.h>
#else
#import <OmniFoundation/OFController.h>
#endif
#import <dns_sd.h>
#include <netdb.h>

#if !defined(OB_ARC) || !OB_ARC
#error This file requires ARC
#endif

NSInteger OFNetStateRegistrationDebug;

#define DEBUG_REGISTRATION(level, format, ...) do { \
    if (OFNetStateRegistrationDebug >= (level)) \
        NSLog(@"STATE REGISTRATION %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)


// <http://www.dns-sd.org/ServiceTypes.html> Short name of protocol, fourteen characters maximum, conforming to normal DNS host name rules: Only lower-case letters, digits, and hyphens; must begin and end with lower-case letter or digit.
NSString * const OFNetStateServiceType = @"_omnistate._tcp."; // OBFinishPorting register this
#ifdef USE_WIDE
NSString * const OFNetStateServiceDomain = @""; // can go across Back to my Mac
#else
NSString * const OFNetStateServiceDomain = @"local.";
#endif

RCS_ID("$Id$")

/*
 THREADING NOTES:
 
 Calls to this class can be made from any thread/queue, but the NSNetService should be used only on the main queue (since we have to schedule it in a runloop and we don't want to do so in a transient runloop for a worker thread/queue).
 We use the _service ivar on the calling thread, store it in a strong local and then invoke blocks on the main queue.
 The NSNetService is potentially initialized on a non-main queue, and depending on the vagaries of reference counting, it might be deallocated on a background queue. But, all the runloop registration/deregistration happens on the main queue.
 
 TODO:
 
 * Coalesce updates locally to avoid these messages:
 
 Nov 27 16:33:03 crispy.local mDNSResponder[36]: Excessive update rate for ePnc0zniQID\032OFXUnitTests\032container:package\032for\032A\.test6\.package._omnistate._tcp.local.; delaying announcement by 1 second

  This could be tricky if we want to ensure that the "last" update has a chance to be seen. If -invalidate is called while we have a pending update, it could get dropped. Maybe we don't care.
 
 */

@implementation OFNetStateRegistration
{
    int _socket;
    in_port_t _port;
    NSNetService *_service;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBInitializeDebugLogLevel(OFNetStateRegistrationDebug);
}

- initWithName:(NSString *)name groupIdentifier:(NSString *)groupIdentifier itemIdentifier:(NSString *)itemIdentifier memberIdentifier:(NSString *)memberIdentifier  state:(NSData *)state;
{
    OBPRECONDITION(![NSString isEmptyString:memberIdentifier]);
    OBPRECONDITION(![NSString isEmptyString:groupIdentifier]);
    OBPRECONDITION(OFNOTEQUAL(memberIdentifier, groupIdentifier));
    
    if (!(self = [super init]))
        return nil;
    
    _name = [name copy];
    _registrationIdentifier = OFXMLCreateID();
    _memberIdentifier = [memberIdentifier copy];
    _groupIdentifier = [groupIdentifier copy];
    _itemIdentifier = [itemIdentifier copy];
    _state = [state copy];
    
    NSError *error;
    _socket = [[self class] _createSocketBoundToLocalPort:&_port requestedPort:0 error:&error];
    if (_socket < 0) {
        // One possible failure is NSPOSIXErrorDomain+EPERM for sandboxed applications
        NSLog(@"Error creating socket for network state registration: %@", [error toPropertyList]);
    }
    
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
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [service stop];
        [service removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }];
    
    if (_socket > 0) {
        if (close(_socket) < 0)
            NSLog(@"%s: close -> %d, %s", __PRETTY_FUNCTION__, OMNI_ERRNO(), strerror(OMNI_ERRNO()));
    }
}

NSString * const OFNetStateRegistrationGroupIdentifierKey = @"g";
NSString * const OFNetStateRegistrationItemIdentifierKey = @"i";
NSString * const OFNetStateRegistrationMemberIdentifierKey = @"m";
NSString * const OFNetStateRegistrationStateKey = @"s";

- (void)setState:(NSData *)state;
{
    OBPRECONDITION(_service); // not invalidated
    
    if (OFISEQUAL(_state, state))
        return;
    
    DEBUG_REGISTRATION(1, @"Setting state to %@", state);

    _state = [state copy];
    [self _updateTXTRecord];
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@ %@>", NSStringFromClass([self class]), self, _name, _memberIdentifier];
}

#pragma mark - Private

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)_applicationDidEnterBackground:(NSNotification *)notification;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_service != nil);
    
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

- (void)_updateTXTRecord;
{
    NSMutableDictionary *txtRecord = [NSMutableDictionary new];
    
    txtRecord[OFNetStateRegistrationMemberIdentifierKey] = _memberIdentifier;
    
    if (_groupIdentifier) {
        txtRecord[OFNetStateRegistrationGroupIdentifierKey] = _groupIdentifier;
    }
    if (![NSString isEmptyString:_itemIdentifier])
        txtRecord[OFNetStateRegistrationItemIdentifierKey] = _itemIdentifier;
    
    if (_state) {
        DEBUG_REGISTRATION(1, @"_state %@", _state);
        NSData *state = _state;
        if ([state length] > 20) { // SHA-1 digest length
            state = [state sha1Signature];
            DEBUG_REGISTRATION(1, @"state, SHA1 %@", state);
        }
        NSString *stateString = [state ascii85String];
        DEBUG_REGISTRATION(1, @"state, ascii85 %@", stateString);

        txtRecord[OFNetStateRegistrationStateKey] = stateString; // We need short strings for Bonjour, so no hex
    }
    
    NSData *txtData = OFNetStateTXTRecordDataFromDictionary(txtRecord, YES);
    
    DEBUG_REGISTRATION(1, @"txtRecord now %@", txtRecord);

    NSNetService *service = _service;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (![service setTXTRecordData:txtData] && ![txtData isEqual:[service TXTRecordData]]) {
            NSLog(@"%@: unable to set TXT record of %@ to %@", self, service, _state);
            OBASSERT_NOT_REACHED("What happened that prevented setting the TXT record?");
        }
    }];
}

- (void)_publishService;
{
    OBPRECONDITION(!_service);
    
    // We need the name to be unique, at least within our app, if we want to publish multiple registrations. Without this, if an app publishes several services under different ports and the same name, only one service will appear in dns-sd.
    // If the name is too *long*, then nothing will be published (not even a truncated version).
    // So, we put our random unique part first and then the debugging bit aftr and possibly truncate it.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSBundle *controllingBundle = [NSBundle mainBundle];
#else
    NSBundle *controllingBundle = [OFController controllingBundle];
#endif
    NSString *serviceName = [NSString stringWithFormat:@"%@ %@", _registrationIdentifier, [[controllingBundle bundleIdentifier] pathExtension]];
    if (![NSString isEmptyString:_name])
        serviceName = [serviceName stringByAppendingFormat:@" %@", _name];

    /* Maximum length, in bytes, of a service name represented as a */
    /* literal C-String, including the terminating NULL at the end. */
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
    
    [self _updateTXTRecord]; // Update our TXT data; doing this before -publish fails.
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
                if (length < 2)
                    return [NSString stringWithFormat:@"TXT record entry for \"%@\" is too short.", key];
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
                        return [NSString stringWithFormat:@"Unable to handle TXT record entry with type '%c' for key \"%@\".", type, key];
                }
            } else {
                value = string;
            }
        }
        
        [validatedValues setObject:value forKey:key];
    }
    
    return validatedValues;
}
