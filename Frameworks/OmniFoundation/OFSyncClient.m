// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSyncClient.h>

#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniBase/macros.h>

#import <Foundation/NSUUID.h> // 10.8 only
#import <sys/sysctl.h>
#import <mach-o/arch.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIDevice.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#endif

OB_REQUIRE_ARC

RCS_ID("$Id$")

static NSString * const OFSyncClientHostIdentifierKey = @"hostID";
static NSString * const OFSyncClientIdentifierKey = @"clientIdentifier";
static NSString * const OFSyncClientRegistrationDateKey = @"registrationDate";

static NSString * const OFSyncClientLastSyncDateKey = @"lastSyncDate";
static NSString * const OFSyncClientNameKey = @"name";
static NSString * const OFSyncClientDescriptionKey = @"description";
static NSString * const OFSyncClientApplicationIdentifierKey = @"bundleIdentifier";
static NSString * const OFSyncClientVersionKey = @"bundleVersion";
static NSString * const OFSyncClientOSVersionNumberKey = @"OSVersionNumber";
static NSString * const OFSyncClientOSVersionKey = @"OSVersion";
static NSString * const OFSyncClientHardwareModelKey = @"HardwareModel";
static NSString * const OFSyncClientHardwareCPUCountKey = @"HardwareCPUCount";
static NSString * const OFSyncClientHardwareCPUTypeKey = @"HardwareCPUType";
static NSString * const OFSyncClientHardwareCPUTypeNameKey = @"HardwareCPUTypeName";
static NSString * const OFSyncClientHardwareCPUTypeDescriptionKey = @"HardwareCPUTypeDescription";
static NSString * const OFSyncClientCurrentFrameworkVersion = @"CurrentFrameworkVersion";
static NSString * const OFSyncClientApplicationMarketingVersion = @"ApplicationMarketingVersion";

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

static NSString *OFSyncClientHostIdentifier(NSString *domain)
{
    OBPRECONDITION(![NSString isEmptyString:domain]);
    OBPRECONDITION([NSUUID class], @"Requires 10.8");
    
    /* OmniFocus 1.x used the machine identifier (the hardware address of en0) as the sync client identifier.
     Starting with OmniFocus 2, we'd like separate instances (defined as OmniFocus 2 vs 1, or Debug vs. Release) to be able to sync independently with the same sync server account.
     
     Since separate instances will have their own sandbox container, we'll store a generated sync client in the user defaults.
     To make sure that we don't re-use this generated identifier on another machine in the case that the user copies the entire sandbox container, or preferences, to a new machine, we'll key the storage by this machine's hardware identifier.
     
     This implementation relies on the fact that we'll have separate bundle identifiers and/or sandbox containers for instances of OmniFocus which we want to act independently from the sync client identifier perspective.
     */
    
    static NSString *syncClientHostID = nil;
    static dispatch_once_t once = 0;
    
    dispatch_once(&once, ^{
        NSString *preferenceKey = [NSString stringWithFormat:@"%@:%@", domain, OFUniqueMachineIdentifier()];
        
        syncClientHostID = [[[NSUserDefaults standardUserDefaults] stringForKey:preferenceKey] copy];
        if (syncClientHostID == nil) {
            syncClientHostID = [[[NSUUID UUID] UUIDString] copy];
            [[NSUserDefaults standardUserDefaults] setObject:syncClientHostID forKey:preferenceKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    });
    
    OBPOSTCONDITION(syncClientHostID != nil);
    return syncClientHostID;
}

#else

static NSString * _Nonnull OFSyncClientHostIdentifier(NSString * _Nonnull domain)
{
    OBPRECONDITION(![NSString isEmptyString:domain]);
    
    /* iOS devices have a unique ID, but [[UIDevice currentDevice] uniqueIdentifier] is deprecated.
     We'd like a unique ID that is persistent, but most importantly, is not restored onto another device in the case that you backup on device and setup a new device from that backup.
     Losing the unique ID isn't too terrible (since we auto expire stale sync clients), so we'll persist a UUID to Caches, and use that as the sync client identifier ID.
     
     Update: On iOS 5, when the device runs low on space, it may purge the stuff in caches. It seems crazy that it would purge our tiny file, but if it does, we'll re-generate one. Despite having said about that losing the client ID isn't too terrible, losing it frequently because you run at the edge of the storage limits of your device is pretty terrible because you'll keep getting new sync client IDs, and if you get the more frequenly than our expiry interval, we'll never be able to compact your database and sync times will get progressively slower.
     
     Strategy:
     - First look for an existing sync client ID in the legacy location - Caches
     - If we don't find one there, generate one there if running on iOS 4, or in Private Documents on iOS5 and set the do not backup attribute
     */
    
    static NSString *syncClientHostID = nil;
    static dispatch_once_t once = 0;
    
    dispatch_once(&once, ^{
        __autoreleasing NSError *error = nil;
        NSArray *libraryDirectoryPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask,YES);
        OBASSERT([libraryDirectoryPaths count] > 0);
        
        // See Technical Q&A QA1699 suggests "Private Documents" - http://developer.apple.com/library/ios/#qa/qa1699/_index.html
        NSString *privateDocumentsPath = [[libraryDirectoryPaths objectAtIndex:0] stringByAppendingPathComponent:@"Private Documents"];
        NSString *syncClientIdentifierFilePath = [privateDocumentsPath stringByAppendingPathComponent:domain];
        
        syncClientHostID = [[NSString alloc] initWithContentsOfFile:syncClientIdentifierFilePath usedEncoding:NULL error:&error];

        // Create the SyncClientIdentifier file if necessary
        if (!syncClientHostID) {
            if (!([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code] == NSFileReadNoSuchFileError))
                NSLog(@"Error reading UUID file: %@", error);

            OBASSERT([NSUUID UUID] != Nil, "Requires OS X 10.8 or iOS 6.0 or later");
            syncClientHostID = [[[NSUUID UUID] UUIDString] copy];
            
            BOOL success = NO;
            NSString *parentDirectory = [syncClientIdentifierFilePath stringByDeletingLastPathComponent];
            if ([[NSFileManager defaultManager] createDirectoryAtPath:parentDirectory withIntermediateDirectories:YES attributes:nil error:&error])
                success = [syncClientHostID writeToFile:syncClientIdentifierFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
            
            if (success) {
                BOOL skipBackupAttributeSuccess = [[NSFileManager defaultManager] addExcludedFromBackupAttributeToItemAtPath:syncClientIdentifierFilePath error:NULL];
#ifdef OMNI_ASSERTIONS_ON
                OBPOSTCONDITION(skipBackupAttributeSuccess);
#else
                (void)skipBackupAttributeSuccess;
#endif
            }
            
            if (!success)
                NSLog(@"Error persisting UUID :%@", error);
        }
    });
    
    OBPOSTCONDITION(syncClientHostID != nil);
    return syncClientHostID;
}

#endif // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

static BOOL setSysctlStringKeyByName(NSMutableDictionary *dict, NSString *key, const char *name)
{
    size_t bufSize = 0;
    
    // Passing a null pointer just says we want to get the size out
    if (sysctlbyname(name, NULL, &bufSize, NULL, 0) < 0) {
#ifdef DEBUG
	perror("sysctl");
#endif
	return NO;
    }
    
    char *value = calloc(1, bufSize + 1);
    
    if (sysctlbyname(name, value, &bufSize, NULL, 0) < 0) {
	// Not expecting any errors now!
	free(value);
#ifdef DEBUG
	perror("sysctl");
#endif
	return NO;
    }
    
    NSString *str = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
    [dict setObject:str forKey:key];
    
    free(value);
    return YES;
}

static void setUInt32Key(NSMutableDictionary *dict, NSString *key, uint32_t value)
{
    NSString *valueString = CFBridgingRelease(CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIu32), value));
    [dict setObject:valueString forKey:key];
}

static void setUInt64Key(NSMutableDictionary *dict, NSString *key, uint64_t value)
{
    NSString *valueString = CFBridgingRelease(CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIu64), value));
    [dict setObject:valueString forKey:key];
}

static void setSysctlIntKeyByName(NSMutableDictionary *dict, NSString *key, const char *name)
{
    union {
        uint32_t ui32;
        uint64_t ui64;
    } value;
    value.ui64 = (uint64_t)-1;
    
    size_t valueSize = sizeof(value);
    if (sysctlbyname(name, &value, &valueSize, NULL, 0) < 0) {
        perror("sysctl");
        value.ui32 = (uint32_t)-1;
        valueSize  = sizeof(value.ui32);
    }
    
    // Might get back a 64-bit value for size/cycle values
    if (valueSize == sizeof(value.ui32))
        setUInt32Key(dict, key, value.ui32);
    else if (valueSize == sizeof(value.ui64))
        setUInt64Key(dict, key, value.ui64);
}


NSMutableDictionary *OFSyncBaseClientState(NSString *domain, NSString *clientIdentifier, NSDate *registrationDate)
{
    OBPRECONDITION(![NSString isEmptyString:clientIdentifier]);
    OBPRECONDITION(registrationDate);
    
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            clientIdentifier, OFSyncClientIdentifierKey,
            OFSyncClientHostIdentifier(domain), OFSyncClientHostIdentifierKey,
            registrationDate, OFSyncClientRegistrationDateKey,
            nil];
}

NSString *OFSyncClientIdentifier(NSDictionary *clientState)
{
    NSString *identifier = [clientState objectForKey:OFSyncClientIdentifierKey];
    OBASSERT(![NSString isEmptyString:identifier]);
    return identifier;
}

NSDate *OFSyncClientLastSyncDate(NSDictionary *clientState)
{
    // Gets added by OFSyncClientState(), so all the plists should have it on the server.
    NSDate *date = [clientState objectForKey:OFSyncClientLastSyncDateKey];
    OBASSERT(date);
    return date;
}

NSString *OFSyncClientApplicationIdentifier(NSDictionary *clientState)
{
    NSString *bundleID = [clientState objectForKey:OFSyncClientApplicationIdentifierKey];
    return bundleID;
}

OFVersionNumber *OFSyncClientVersion(NSDictionary *clientState)
{
    NSString *versionString = [clientState objectForKey:OFSyncClientVersionKey];
    OBASSERT(![NSString isEmptyString:versionString]);
    OFVersionNumber *versionNumber = [[OFVersionNumber alloc] initWithVersionString:versionString];
    OBASSERT(versionNumber != nil);
    return versionNumber;
}

NSString *OFSyncClientHardwareModel(NSDictionary *clientState)
{
    NSString *hardwareModel = [clientState objectForKey:OFSyncClientHardwareModelKey];
    OBASSERT(![NSString isEmptyString:hardwareModel]);
    return hardwareModel;
}

// Testing support.
NSDate *OFSyncClientDateWithTimeIntervalSinceNow(NSTimeInterval sinceNow)
{
    NSString *syncDateString = [[NSUserDefaults standardUserDefaults] stringForKey:@"OFSyncClientReferenceDate"];
    if (![NSString isEmptyString:syncDateString]) {
        NSDate *referenceDate = [[NSDate alloc] initWithXMLString:syncDateString];
        OBASSERT(referenceDate);
        
        // The clock is stopped in this case, so we can't really do multiple sync operations (but we want predictable outputs, so that's expected).  We could add the ability to set the reference date later if we need.
        return [referenceDate dateByAddingTimeInterval:sinceNow];
    }
    
    return [NSDate dateWithTimeIntervalSinceNow:sinceNow];
}

NSDictionary *OFSyncClientRequiredState(OFSyncClientParameters *parameters, NSString *clientIdentifier, NSDate *registrationDate)
{
    OBPRECONDITION(![NSString isEmptyString:clientIdentifier]);
    OBPRECONDITION(registrationDate);
    
    NSString *hostID = OFSyncClientHostIdentifier(parameters.hostIdentifierDomain);    
    return [NSDictionary dictionaryWithObjectsAndKeys:
            clientIdentifier, OFSyncClientIdentifierKey,
            hostID, OFSyncClientHostIdentifierKey,
            registrationDate, OFSyncClientRegistrationDateKey,
            nil];
}

@implementation OFSyncClientParameters

- (id)initWithDefaultClientIdentifierPreferenceKey:(NSString *)defaultClientIdentifierPreferenceKey hostIdentifierDomain:(NSString *)hostIdentifierDomain currentFrameworkVersion:(OFVersionNumber *)currentFrameworkVersion;
{
    OBPRECONDITION(![NSString isEmptyString:defaultClientIdentifierPreferenceKey]);
    OBPRECONDITION(![NSString isEmptyString:hostIdentifierDomain]);
    OBPRECONDITION(OFNOTEQUAL(defaultClientIdentifierPreferenceKey, hostIdentifierDomain));
    OBPRECONDITION(currentFrameworkVersion);
    
    if (!(self = [super init]))
        return nil;
    
    _defaultClientIdentifierPreferenceKey = [defaultClientIdentifierPreferenceKey copy];
    _defaultClientIdentifierPreference = [OFPreference preferenceForKey:_defaultClientIdentifierPreferenceKey];
    _hostIdentifierDomain = [hostIdentifierDomain copy];
    _currentFrameworkVersion = [currentFrameworkVersion copy];
    
    // Make sure this gets cached. Access has to be on the main queue if we're initializing (say when first syncing with an existing database) or we try to set an OFPreference on a background queue, assert, and trap.
    if ([NSThread isMainThread]) {
        [self defaultClientIdentifier];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self defaultClientIdentifier];
        });
    }
    
    return self;
}

- (NSString *)defaultClientIdentifier;
{    
    NSString *clientIdentifier = [_defaultClientIdentifierPreference stringValue];
    if ([NSString isEmptyString:clientIdentifier]) {
        clientIdentifier = OFXMLCreateID();
        [_defaultClientIdentifierPreference setStringValue:clientIdentifier];
    }
    
    return clientIdentifier;
}

- (BOOL)isClientStateFromCurrentHost:(NSDictionary *)clientState;
{
    NSString *hostID = [clientState objectForKey:OFSyncClientHostIdentifierKey];
    
    // DO NOT return YES for old client states with a nil host.  We want a reset on upgrade.  Otherwise, if you had two clients syncing preferences and each independently updated their client state with their host, we'd still not reset _unless_ we fetched the client files from the server earlier in sync to check that we were valid.  This is extra work for now, so we'll just invalidate all old sync clients.
    
    NSString *domain = self.hostIdentifierDomain;
    return [hostID isEqual:OFSyncClientHostIdentifier(domain)];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *d = [super debugDictionary];
    
    [d setObject:[_defaultClientIdentifierPreference shortDescription] forKey:@"defaultClientIdentifierPreference"];
    [d setObject:_hostIdentifierDomain forKey:@"hostIdentifierDomain"];
    [d setObject:[_currentFrameworkVersion originalVersionString] forKey:@"currentFrameworkVersion"];
    
    return d;
}

@end

@implementation OFSyncClient

+ (NSMutableDictionary *)makeClientStateWithPreviousState:(nullable NSDictionary *)oldClientState parameters:(OFSyncClientParameters *)parameters onlyIncludeRequiredKeys:(BOOL)onlyRequiredKeys;
{
    OBPRECONDITION(parameters);
    OBPRECONDITION(!oldClientState || [oldClientState objectForKey:OFSyncClientHostIdentifierKey]);
    OBPRECONDITION(!oldClientState || [oldClientState objectForKey:OFSyncClientIdentifierKey]);
    OBPRECONDITION(!oldClientState || [oldClientState objectForKey:OFSyncClientRegistrationDateKey]);
    
    NSMutableDictionary *client = [NSMutableDictionary dictionary];
    
    NSString *clientIdentifier = [oldClientState objectForKey:OFSyncClientIdentifierKey];
    if (!clientIdentifier) {
        if (oldClientState) {
            NSLog(@"Non-nil client has nil identifier: %@", oldClientState);
            OBASSERT_NOT_REACHED("Make sure that we don't lose client identifiers");
            clientIdentifier = OFXMLCreateID(); // If this happens, generate a random identifier
        } else {
            clientIdentifier = parameters.defaultClientIdentifier;
        }
    }
    client[OFSyncClientIdentifierKey] = clientIdentifier;
    
    NSString *domain = parameters.hostIdentifierDomain;
    
    client[OFSyncClientHostIdentifierKey] = OFSyncClientHostIdentifier(domain);
    
    NSDate *syncDate = OFSyncClientDateWithTimeIntervalSinceNow(0.0);
    NSDate *registrationDate = [oldClientState objectForKey:OFSyncClientRegistrationDateKey];
    if (!registrationDate)
        registrationDate = syncDate;  // Need to populate this the first time and then store it
    client[OFSyncClientRegistrationDateKey] = registrationDate;
    client[OFSyncClientLastSyncDateKey] = syncDate;
    
    client[OFSyncClientCurrentFrameworkVersion] = [parameters.currentFrameworkVersion cleanVersionString];
    client[OFSyncClientApplicationMarketingVersion] = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
    
    if (onlyRequiredKeys)
        return client;
    
    NSString *name = [self computerName];
    if (!name)
        name = @"Unknown";
    [client setObject:name forKey:OFSyncClientNameKey];
    
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleIdentifier = [bundle bundleIdentifier];
    if ([NSString isEmptyString:bundleIdentifier])
        bundleIdentifier = [bundle bundlePath]; // Command line unit test tool
    [client setObject:bundleIdentifier forKey:OFSyncClientApplicationIdentifierKey];
    
    NSString *bundleVersion = [[bundle infoDictionary] objectForKey:(id)kCFBundleVersionKey];
    if (![NSString isEmptyString:bundleVersion])
        [client setObject:bundleVersion forKey:OFSyncClientVersionKey];
    
    [client setObject:[[OFVersionNumber userVisibleOperatingSystemVersionNumber] cleanVersionString] forKey:OFSyncClientOSVersionNumberKey];
    
    // Version number (this has the release string, like 9D34 for 10.5.3).  Might be interesting, in case they are running a old beta and should update.
    if (!setSysctlStringKeyByName(client, OFSyncClientOSVersionKey, "kern.osversion")) {
        // 10.4 doesn't have kern.osversion
        NSString *version = [[OFVersionNumber userVisibleOperatingSystemVersionNumber] cleanVersionString];
        if (version)
            [client setObject:version forKey:OFSyncClientOSVersionKey];
    }
    
    // Computer model
    setSysctlStringKeyByName(client, OFSyncClientHardwareModelKey, "hw.model");
    
    // Number of processors
    setSysctlIntKeyByName(client, OFSyncClientHardwareCPUCountKey, "hw.ncpu");
    
    // Type/Subtype of processors
    {
        // sysctl -a reports 'hw.cputype'/'hw.cpusubtype', but there are no defines for the names.
        const NXArchInfo *archInfo = NXGetLocalArchInfo();
        if (archInfo) {
            {
                NSString *value = [[NSString alloc] initWithFormat:@"%d,%d", archInfo->cputype, archInfo->cpusubtype];
                [client setObject:value forKey:OFSyncClientHardwareCPUTypeKey];
            }
            
            if (archInfo->name) {
                NSString *value = [[NSString alloc] initWithCString:archInfo->name encoding:NSUTF8StringEncoding];
                [client setObject:value forKey:OFSyncClientHardwareCPUTypeNameKey];
            }
            
            if (archInfo->description) {
                NSString *value = [[NSString alloc] initWithCString:archInfo->description encoding:NSUTF8StringEncoding];
                [client setObject:value forKey:OFSyncClientHardwareCPUTypeDescriptionKey];
            }
        }
    }
    
    return client;
}

+ (NSString *)computerName;
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    return OFHostName();
#else
    return [[UIDevice currentDevice] name];
#endif
}

- (id)initWithURL:(NSURL *)clientURL previousClient:(nullable OFSyncClient *)previousClient parameters:(OFSyncClientParameters *)parameters error:(NSError **)outError;
{
    NSDictionary *propertyList = [[self class] makeClientStateWithPreviousState:previousClient.propertyList parameters:parameters onlyIncludeRequiredKeys:NO];
    return [self initWithURL:clientURL propertyList:propertyList error:outError];
}

- (id)initWithURL:(NSURL *)clientURL propertyList:(NSDictionary *)propertyList error:(NSError **)outError;
{
    OBPRECONDITION(clientURL);
    OBPRECONDITION(propertyList);
    
    if (!(self = [super init]))
        return nil;
    
    _clientURL = clientURL;
    _propertyList = [propertyList copy];
    
    _identifier = [OFSyncClientIdentifier(_propertyList) copy];
    if (!_identifier) {
        NSString *reason = [NSString stringWithFormat:@"No client identifier in %@", clientURL];
        OFError(outError, OFSyncClientStateInvalidPropertyList, @"Invalid client state.", reason);
        return nil;
    }
    
    return self;
}

- (NSDate *)registrationDate;
{
    // Gets added by OFSyncClientState(), so all the plists should have it on the server.
    NSDate *date = [_propertyList objectForKey:OFSyncClientRegistrationDateKey];
    OBASSERT(date);
    return date;
}

- (NSDate *)lastSyncDate;
{
    return OFSyncClientLastSyncDate(_propertyList);
}

- (NSString *)name;
{
    NSString *name = [_propertyList objectForKey:OFSyncClientNameKey];
    if ([NSString isEmptyString:name]) {
        OBASSERT_NOT_REACHED("Unnamed sync client");
        name = @"Unnamed";
    }
    return name;
}

- (NSString *)hardwareModel;
{
    return OFSyncClientHardwareModel(_propertyList);
}

- (BOOL)lastSyncDatePastLimitDate:(NSDate *)limitDate;
{
    NSDate *lastSyncDate = [self lastSyncDate];
    return lastSyncDate && [limitDate compare:lastSyncDate] != NSOrderedAscending;
}

- (NSComparisonResult)compareByLastSyncDate:(OFSyncClient *)otherClient;
{
    NSDate *date = self.lastSyncDate;
    NSDate *otherDate = otherClient.lastSyncDate;
    
    if (date == otherDate)
        return NSOrderedSame; // Might both be nil in error...
    
    // consider nil as older than non-nil
    if (!date)
        return NSOrderedAscending;
    if (!otherDate)
        return NSOrderedDescending;
    
    return [date compare:otherDate];
}

- (OFVersionNumber *)currentFrameworkVersion;
{
    NSString *versionString = _propertyList[OFSyncClientCurrentFrameworkVersion];
    if ([NSString isEmptyString:versionString]) {
        // Older clients might not have written a version. Make them act like version zero.
        versionString = @"0";
    }
    OFVersionNumber *versionNumber = [[OFVersionNumber alloc] initWithVersionString:versionString];
    if (!versionNumber) {
        OBASSERT_NOT_REACHED("Bad version written to property list");
        versionNumber = [[OFVersionNumber alloc] initWithVersionString:@"0"];
    }
    
    return versionNumber;
}

- (nullable OFVersionNumber *)applicationMarketingVersion;
{
    NSString *versionString = _propertyList[OFSyncClientApplicationMarketingVersion];
    if ([NSString isEmptyString:versionString]) {
        return nil;
    }
    
    OFVersionNumber *versionNumber = [[OFVersionNumber alloc] initWithVersionString:versionString];
    return versionNumber;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, _clientURL];
}

@end
