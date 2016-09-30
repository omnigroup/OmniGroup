// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUCheckOperation.h>

#import <OmniSoftwareUpdate/OSUProbe.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniBase/OmniBase.h>

#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#import "OSUErrors.h"
#import "OSURunOperationParameters.h"
#import "OSURunOperation.h"
#import "OSURuntime.h"
#import <OmniSoftwareUpdate/OSUHardwareInfo.h>
#import "OSUSettings.h"

RCS_ID("$Id$");

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define OSU_CHECK_WITH_XPC 0
#else
#define OSU_CHECK_WITH_XPC 1
#import "OSUCheckServiceProtocol.h"
#import "OSULookupCredentialProtocol.h"
#import <OmniFoundation/NSObject-OFExtensions.h> // OFRunLoopRunUntil
#endif

@interface OSUCheckOperation (/*Private*/)

// We calculate these in the background, but dispatch back to the main thread to update them.
@property(nonatomic,readwrite,strong) NSDictionary *output;
@property(nonatomic,readwrite,strong) NSError *error;

#if OSU_CHECK_WITH_XPC
@property (nonatomic, readonly) NSXPCConnection *connection;
#endif

@end

#if OSU_CHECK_WITH_XPC
@interface OSUCheckOperation () <OSULookupCredential>
@end
#endif

@implementation OSUCheckOperation
{
    BOOL _forQuery;
    NSString *_licenseType;
    NSURL *_url;
    NSDictionary *_output;
    NSError *_error;
    
#if OSU_CHECK_WITH_XPC
    NSXPCConnection *_connection;
    struct {
        NSUInteger invalid:1;
        NSUInteger interrupted:1;
    } _connectionFlags;
#endif
}

- initForQuery:(BOOL)doQuery url:(NSURL *)url licenseType:(NSString *)licenseType;
{
    OBPRECONDITION(url);
    OBPRECONDITION(licenseType); // App might not have set it yet; this is considered an error, but we should send *something*
    
    if (!(self = [super init]))
        return nil;

    _forQuery = doQuery;
    _url = [url copy];

    if (!licenseType)
        licenseType = OSULicenseTypeUnset;
    _licenseType = [licenseType copy];
    
    return self;
}

- (void)dealloc;
{
#if OSU_CHECK_WITH_XPC
    [_connection invalidate];
#endif
}

- (NSURL *)url;
{
    return _url;
}

- (void)runAsynchronously;
{
    OBPRECONDITION(_runType == OSUCheckOperationHasNotRun);
    
    if (_runType != OSUCheckOperationHasNotRun)
        return;
    
    _runType = OSUCheckOperationRunAsynchronously;
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.name = @"com.omnigroup.OmniSoftwareUpdate.CheckOperation";
    [queue addOperationWithBlock:^{
        @autoreleasepool {
            [self _run];
        }
        [queue self]; // Paranoia for when we convert to ARC...
    }];
}

- (NSDictionary *)runSynchronously;
{
    OBPRECONDITION(_runType == OSUCheckOperationHasNotRun);

    if (_runType != OSUCheckOperationHasNotRun)
        return nil;
    
    _runType = OSUCheckOperationRunSynchronously;

    @autoreleasepool {
        [self _run];
    }

    OBPOSTCONDITION(_output || _error);
    return _output;
}

@synthesize runType = _runType;
@synthesize initiatedByUser = _initiatedByUser;
@synthesize output = _output;
@synthesize error = _error;

NSString * const OSUCheckOperationCompletedNotification = @"OSUCheckOperationCompleted";

#if OSU_CHECK_WITH_XPC

#pragma mark - OSULookupCredential

// Callback for the XPC service to ask us for credentials on a protected feed.
- (void)lookupCredentialForProtectionSpace:(NSURLProtectionSpace *)protectionSpace withReply:(void (^)(NSURLCredential *))reply;
{
    NSURLCredential *credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:protectionSpace];
    
    if ([NSString isEmptyString:credential.password]) {
        // This can happen when the Keychain entry, sandbox, and app signature has gotten off kilter somehow so that we are refused access to the keychain w/o a prompt for whether to allow access. Adding a log message here in case we need to search back for support...
        NSLog(@"Keychain item has no password, ignoring.");
        credential = nil;
    }
    
    reply(credential);
}

#endif

#pragma mark - Private

static NSError *OSUTransformCheckServiceError(NSError *error, NSString *hostname)
{
    __autoreleasing NSError *result = error;

    NSError *serviceError = [result underlyingErrorWithDomain:OSUCheckServiceErrorDomain];
    if (serviceError == nil)
        return result;
    
    NSInteger code = [serviceError code];
    if (code == OSUCheckServiceServerError) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Error fetching software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = [error localizedFailureReason]; // Should be set from +[NSHTTPURLResponse localizedStringForStatusCode:]
        NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please try again later or contact us to let us know this is broken.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, suggestion, NSLocalizedRecoverySuggestionErrorKey, error, NSUnderlyingErrorKey, nil];
        if (reason)
            userInfo[NSLocalizedFailureReasonErrorKey] = reason;
        
        return [NSError errorWithDomain:OSUErrorDomain code:OSUServerError userInfo:userInfo];
    }
    
    if (code == OSUCheckServiceExceptionRaisedError) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        userInfo[NSUnderlyingErrorKey] = error;
        userInfo[NSLocalizedDescriptionKey] = NSLocalizedStringFromTableInBundle(@"Error while checking for updated version.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        
        NSString *reason = [error localizedFailureReason];
        if (reason)
            userInfo[NSLocalizedFailureReasonErrorKey] = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Exception raised: %@", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), reason];
        
        return [NSError errorWithDomain:OSUErrorDomain code:OSUExceptionRaised userInfo:userInfo];
    }
    
    OBASSERT_NOT_REACHED("Untranslated error from service: %@", serviceError);
    
    return result;
}

- (void)_run;
{
#if defined(DEBUG)
    unsigned int delay = (unsigned int)[[NSUserDefaults standardUserDefaults] integerForKey:@"OSUCheckDelay"];
    // This is helpful when you need some time to examine/test the software update panel in its initial state before it gets a response from the software update server.
    if (delay > 0) {
        NSLog(@"OSUCheckDelay: delaying the check for %u seconds", delay);
        sleep(delay);
    }
#endif

    NSString *host = [_url host];
    if ([NSString isEmptyString:host]) {
        // A file URL for testing?
        OBASSERT([_url isFileURL]);
        host = @"localhost"; // needed to not have an empty array below and for the checker to determine network availability.
    }
    
    OFVersionNumber *versionNumber = [OSUChecker OSUVersionNumber];
    if (!versionNumber)
        versionNumber = [[OFVersionNumber alloc] initWithVersionString:@"1.0"];
    
    OSUChecker *checker = [OSUChecker sharedUpdateChecker];

    // If we aren't actually submitting the query, this is probably due to the user popping up the sheet in the preferences to see what we *would* submit.
    BOOL includeHardwareDetails = !_forQuery || [[OSUPreferences includeHardwareDetails] boolValue];
    
    // Send the current track to the server so it can make decisions about what we'll see.
    NSArray *tracks = [OSUPreferences visibleTracks];
    NSString *track = (tracks && [tracks count])? [tracks objectAtIndex:0] : [checker applicationTrack];
    
    OSURunOperationParameters *params = [[OSURunOperationParameters alloc] init];
    params.firstHopHost = host;
    params.baseURLString = [_url absoluteString];
    params.appIdentifier = [checker applicationIdentifier];
    params.appVersionString = [checker applicationEngineeringVersion];
    params.track = track;
    params.includeHardwareInfo = includeHardwareDetails;
    params.reportMode = !_forQuery;
    params.licenseType = _licenseType;
    params.osuVersionString = [versionNumber cleanVersionString];
    
    
    NSString *uuidString = OSUSettingGetValueForKey(OSUReportInfoUUIDKey);
    if (!uuidString) {
        CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
        if (uuid) {
            uuidString = CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, uuid));
            CFRelease(uuid);
            OSUSettingSetValueForKey(OSUReportInfoUUIDKey, uuidString);
        }
    }
    params.uuidString = uuidString;

    // See OSUCheckService's main() for why this is split out.
    NSMutableDictionary *runtimeStats = [NSMutableDictionary dictionary];
    OSURunTimeAddStatisticsToInfo([checker applicationIdentifier], runtimeStats);
    
    // Embed our custom probes too (also in our preferences domain).
    [[NSNotificationCenter defaultCenter] postNotificationName:OSUProbeFinalizeForQueryNotification object:self];
    NSMutableDictionary *probes = [NSMutableDictionary dictionary];
    for (OSUProbe *probe in [OSUProbe allProbes]) {
        NSString *key = probe.key;
        NSString *value = [probe.value description]; // All the values in the info dictionary must be strings
        if (value)
            probes[key] = value;
    }

    __autoreleasing NSError *error = nil;
    
#if OSU_CHECK_WITH_XPC
    // The XPC service won't be able to look up credentials from this app, so pass them down if we have them. This is not great since we don't have the protection space that would be in the challenge so we find the credential that matches the host...
    id <OSULookupCredential> lookupCredential = self;
    
    NSXPCConnection *connection = self.connection;
    __block NSError *strongError = nil;
    id <OSUCheckService> remoteObjectProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
        strongError = proxyError;
    }];
    
    __block NSDictionary *dict = nil;
    if (strongError == nil) {
        if (remoteObjectProxy) {
            // We really want this to be synchronous (we are already on a background queue).
            __block BOOL hasReceivedResponseOrError = NO;
            [remoteObjectProxy performCheck:params runtimeStats:runtimeStats probes:probes lookupCredential:lookupCredential withReply:^(NSDictionary *results, NSError *checkError){
                dict = [results copy];
                if (!dict)
                    strongError = checkError;
                hasReceivedResponseOrError = YES;
            }];
            
            BOOL done = OFRunLoopRunUntil(60.0/*timeout*/, OFRunLoopRunTypePolling, ^BOOL{
                return hasReceivedResponseOrError || _connectionFlags.interrupted || _connectionFlags.invalid;
            });
            if (done == NO) {
                OBASSERT_NULL(dict);
                NSString *description = NSLocalizedStringFromTableInBundle(@"Error fetching software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
                NSString *reason = NSLocalizedStringFromTableInBundle(@"Timed out waiting for the software update service.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
                NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please try again later or contact us to let us know this is broken.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
                strongError = [NSError errorWithDomain:OSUErrorDomain code:OSUCheckServiceTimedOut userInfo:@{NSLocalizedDescriptionKey:description, NSLocalizedFailureReasonErrorKey:reason, NSLocalizedRecoverySuggestionErrorKey:suggestion}];
            } else if (_connectionFlags.interrupted || _connectionFlags.invalid) {
                OBASSERT_NULL(dict);
                NSString *description = NSLocalizedStringFromTableInBundle(@"Error fetching software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
                NSString *reason = NSLocalizedStringFromTableInBundle(@"The background software update service failed.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
                NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please try again later or contact us to let us know this is broken.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
                strongError = [NSError errorWithDomain:OSUErrorDomain code:OSUCheckServiceFailed userInfo:@{NSLocalizedDescriptionKey:description, NSLocalizedFailureReasonErrorKey:reason, NSLocalizedRecoverySuggestionErrorKey:suggestion}];
            }
        } else {
            OBASSERT(strongError);
        }
    }
    
    [connection invalidate]; // Our invalidation handler should get called and _connection cleared.
    
    if (!dict)
        error = strongError;
    
#else
    // No XPC here, so we don't need to call back to the main app to lookup credentials.
    id <OSULookupCredential> lookupCredential = nil;
    __block NSDictionary *dict = nil;
    __block NSError *strongError = nil;
    __block BOOL hasReceivedResponseOrError = NO;

    OSURunOperation(params, runtimeStats, probes, lookupCredential, ^(NSDictionary *runResult, NSError *runError){
        if (runResult)
            dict = runResult;
        else
            strongError = runError;
        hasReceivedResponseOrError = YES;
    });
    
    BOOL done = OFRunLoopRunUntil(60.0/*timeout*/, OFRunLoopRunTypePolling, ^BOOL{
        return hasReceivedResponseOrError;
    });
    if (done == NO) {
        OBASSERT_NULL(dict);
        NSString *description = NSLocalizedStringFromTableInBundle(@"Error fetching software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Timed out waiting for the software update service.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please try again later or contact us to let us know this is broken.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
        strongError = [NSError errorWithDomain:OSUErrorDomain code:OSUCheckServiceTimedOut userInfo:@{NSLocalizedDescriptionKey:description, NSLocalizedFailureReasonErrorKey:reason, NSLocalizedRecoverySuggestionErrorKey:suggestion}];
    }

    if (strongError)
        error = strongError;
#endif
    
    // Transform errors from the background service (even it is compiled in)
    if (!dict)
        error = OSUTransformCheckServiceError(error, host);
    
    id object = dict ? (id)dict : (id)error;
    
    // waitUntilDone==YES means this will just call the method here if we are in the main thread, which we want for the benefit of -runSynchronously
    [self performSelectorOnMainThread:@selector(_runFinishedWithObject:) withObject:object waitUntilDone:YES modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
}

- (void)_runFinishedWithObject:(id)object;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if ([object isKindOfClass:[NSError class]]) {
        self.output = nil;
        self.error = object;
    } else {
        OBASSERT([object isKindOfClass:[NSDictionary class]], @"Got object of class %@", [object class]);
        self.output = object;
        self.error = nil;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OSUCheckOperationCompletedNotification object:self userInfo:nil];
}

#pragma mark -
#pragma mark XPC

#if OSU_CHECK_WITH_XPC
- (NSXPCConnection *)connection;
{
    if (_connection == nil) {

        // As of around 09/19/2016, the XPC service needs a bundle identifier registered with the MacAppStore.
#if MAC_APP_STORE
        static NSString * const ServiceName = @"com.omnigroup.OmniSoftwareUpdate.OSUCheckService.MacAppStore";
#else
        static NSString * const ServiceName = @"com.omnigroup.OmniSoftwareUpdate.OSUCheckService";
#endif

        _connectionFlags.invalid = NO;
        _connectionFlags.interrupted = NO;
        _connection = [[NSXPCConnection alloc] initWithServiceName:ServiceName];
        
        NSXPCInterface *remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUCheckService)];
        
        [remoteObjectInterface setInterface:[NSXPCInterface interfaceWithProtocol:@protocol(OSULookupCredential)] forSelector:@selector(performCheck:runtimeStats:probes:lookupCredential:withReply:) argumentIndex:3 ofReply:NO];

        _connection.remoteObjectInterface = remoteObjectInterface;

        __weak typeof(self) weakSelf = self;
        _connection.interruptionHandler = ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_connectionFlags.interrupted = YES;
                [strongSelf->_connection invalidate];
                strongSelf->_connection = nil;
            }
        };
        
        _connection.invalidationHandler = ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_connectionFlags.invalid = YES;
                strongSelf->_connection = nil;
            }
        };
        
        [_connection resume];
    }
    
    return _connection;
}
#endif

@end

