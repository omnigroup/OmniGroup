// Copyright 2001-2008, 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUCheckOperation.h"

#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniBase/OmniBase.h>
#import <SystemConfiguration/SCDynamicStore.h>
#import <SystemConfiguration/SCNetwork.h>
#import <SystemConfiguration/SCNetworkReachability.h>

#import "OSUPreferences.h"
#import "OSUChecker.h"
#import "OSUOpenGLExtensions.h"
#import "OSUErrors.h"
#import "OSUHardwareInfo.h"

RCS_ID("$Id$");

@interface OSUCheckOperation (/*Private*/)

// We calculate these in the background, but dispatch back to the main thread to update them.
@property(nonatomic,readwrite,retain) NSDictionary *output;
@property(nonatomic,readwrite,retain) NSError *error;

@end

@implementation OSUCheckOperation
{
    BOOL _forQuery;
    NSString *_licenseType;
    NSURL *_url;
    NSDictionary *_output;
    NSError *_error;
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
    [_output release];
    [_error release];
    [_url release];
    [_licenseType release];
    
    [super dealloc];
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
    
    [NSThread detachNewThreadSelector:@selector(_run) toTarget:self withObject:nil];
}

- (NSDictionary *)runSynchronously;
{
    OBPRECONDITION(_runType == OSUCheckOperationHasNotRun);

    if (_runType != OSUCheckOperationHasNotRun)
        return nil;
    
    _runType = OSUCheckOperationRunSynchronously;

    [self _run];

    OBPOSTCONDITION(_output || _error);
    return _output;
}

@synthesize runType = _runType;
@synthesize initiatedByUser = _initiatedByUser;
@synthesize output = _output;
@synthesize error = _error;

NSString * const OSUCheckOperationCompletedNotification = @"OSUCheckOperationCompleted";

#pragma mark -
#pragma mark Private

- (void)_run;
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSString *host = [_url host];
    if ([NSString isEmptyString:host]) {
        // A file URL for testing?
        OBASSERT([_url isFileURL]);
        host = @"localhost"; // needed to not have an empty array below and for the checker to determine network availability.
    }
    
    OFVersionNumber *versionNumber = [OSUChecker OSUVersionNumber];
    if (!versionNumber)
        versionNumber = [[[OFVersionNumber alloc] initWithVersionString:@"1.0"] autorelease];
    
    OSUChecker *checker = [OSUChecker sharedUpdateChecker];

    // If we aren't actually submitting the query, this is probably due to the user popping up the sheet in the preferences to see what we *would* submit.
    BOOL includeHardwareDetails = !_forQuery || [[OSUPreferences includeHardwareDetails] boolValue];
    
    // Send the current track to the server so it can make decisions about what we'll see.
    NSArray *tracks = [OSUPreferences visibleTracks];
    NSString *track = (tracks && [tracks count])? [tracks objectAtIndex:0] : [checker applicationTrack];
    
    OSURunOperationParameters params = {
        .firstHopHost = host,
        .baseURLString = [_url absoluteString],
        .appIdentifier = [checker applicationIdentifier],
        .appVersionString = [checker applicationEngineeringVersion],
        .track = track,
        .includeHardwareInfo = includeHardwareDetails,
        .reportMode = !_forQuery,
        .licenseType = _licenseType,
        .osuVersionString = [versionNumber cleanVersionString]
    };
    
    NSError *error = nil;
    NSDictionary *dict = OSURunOperation(&params, &error);
 
    id object = dict ? (id)dict : (id)error;
    
    // waitUntilDone==YES means this will just call the method here if we are in the main thread, which we want for the benefit of -runSynchronously
    [self performSelectorOnMainThread:@selector(_runFinishedWithObject:) withObject:object waitUntilDone:YES modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];

    [pool release];
}

- (void)_runFinishedWithObject:(id)object;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if ([object isKindOfClass:[NSError class]]) {
        self.output = nil;
        self.error = object;
    } else {
        OBASSERT([object isKindOfClass:[NSDictionary class]]);
        self.output = object;
        self.error = nil;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OSUCheckOperationCompletedNotification object:self userInfo:nil];
}

@end

static BOOL OSUCheckReachability(NSString *hostname, NSError **outError)
{
    if ([NSString isEmptyString:hostname])
        return YES;
    
    const char *hostNameCString = [hostname UTF8String]; // Should it be ASCII by this point?
    
    SCNetworkReachabilityRef target = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, hostNameCString);
    SCNetworkReachabilityFlags flags = 0;
    Boolean canDetermineReachability = SCNetworkReachabilityGetFlags(target, &flags);
    CFRelease(target);
    
    NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Your Internet connection might not be active, or there might be a problem somewhere along the network.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error text generated when software update is unable to retrieve the list of current software versions");
    if (!canDetermineReachability) {
        // Unable to determine whether the host is reachable. Most likely problem is that we failed to look up the host name. Most likely reason for that is a network partition, or a multiple failure of name servers (because, of course, EVERYONE actually READS the dns specs and maintains at least two nameservers with decent geographical and topological separation, RIGHT?). Another possibility is that configd is screwed up somehow. At any rate, it's unlikely that we'd be able to retrieve the status info, so return an error.
        // TODO: Localize these.  We are running in a tool that doesn't have direct access to the .strings files, so we'll need to look them up out of our containing .framework's bundle.
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not contact %@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error text generated when software update is unable to retrieve the list of current software versions"), hostname];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, suggestion, NSLocalizedRecoverySuggestionErrorKey, nil];
        if (outError)
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSURemoteNetworkFailure userInfo:userInfo];
        return NO;
    }
    
    Boolean reachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    
    if (!reachable) {
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ is not reachable.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - the host from which we retrieve updates is unreachable"), hostname];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, suggestion, NSLocalizedRecoverySuggestionErrorKey, nil];
        if (outError)
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSULocalNetworkFailure userInfo:userInfo];
        return NO;
    }
    
    return YES;
}

static BOOL isGLExtensionsKey(CFStringRef keyString)
{
    if (CFStringHasPrefix(keyString, CFSTR("gl_extensions"))) {
        // Assume no more than 10 GL adapters for now... where's my CFRegExp?
        
        if (CFStringGetLength(keyString) == 14) {
            UniChar ch = CFStringGetCharacterAtIndex(keyString, 13);
            if (ch >= '0' && ch <= '9')
                return YES;
        }
    }
    
    return NO;
}

static void _queryStringApplier(const void *key, const void *value, void *context)
{
    CFStringRef keyString = (CFStringRef)key;
    CFStringRef valueString = (CFStringRef)value;
    CFMutableStringRef query = (CFMutableStringRef)context;
    
    CFStringRef escapedKey = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, keyString, NULL, NULL, kCFStringEncodingUTF8);
    CFStringRef escapedValue;
    
    if (isGLExtensionsKey(keyString)) {
        CFStringRef compactedValue = OSUCopyCompactedOpenGLExtensionsList(valueString);
        escapedValue = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, compactedValue, NULL, NULL, kCFStringEncodingUTF8);
        CFRelease(compactedValue);
    } else {
        escapedValue = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, valueString, NULL, NULL, kCFStringEncodingUTF8);
    }
    
    
    if (CFStringGetLength(query) > 1)
        CFStringAppend(query, CFSTR(";"));
    CFStringAppend(query, escapedKey);
    CFStringAppend(query, CFSTR("="));
    CFStringAppend(query, escapedValue);
    
    CFRelease(escapedKey);
    CFRelease(escapedValue);
}

static NSURL *OSUMakeCheckURL(NSString *baseURLString, NSString *appIdentifier, NSString *appVersionString, NSString *track, NSString *osuVersionString, CFDictionaryRef info)
{
    OBPRECONDITION(baseURLString);
    OBPRECONDITION(appIdentifier);
    OBPRECONDITION(appVersionString);
    OBPRECONDITION(track);
    OBPRECONDITION(osuVersionString);
    
    // Build a query string from all the key/value pairs in the info dictionary.
    CFMutableStringRef queryString = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, CFSTR("?"));
    CFStringAppendFormat(queryString, NULL, CFSTR("OSU=%@"), osuVersionString);
    if (info)
        CFDictionaryApplyFunction(info, _queryStringApplier, queryString);
    
    // Build up the URL based on the scope of the query.
    NSURL *rootURL = [NSURL URLWithString:baseURLString];
    OBASSERT([rootURL query] == nil);  // The input URL should _not_ have a query already (since +URLWithString:relativeToURL: will toss it if it does).
    
    // The root URL might be a file URL; if it is use the file raw w/o adding our extra scoping.
    NSURL *url;
    
    if ([rootURL isFileURL]) {
        url = rootURL;
    } else {
        NSString *scopePath = [appIdentifier stringByAppendingPathComponent:appVersionString];
        if (![NSString isEmptyString:track])
            scopePath = [scopePath stringByAppendingPathComponent:track];
        
        NSURL *scopeURL = [NSURL URLWithString:[[rootURL path] stringByAppendingPathComponent:scopePath] relativeToURL:rootURL];
        
        // Build a URL from what was given and the query string
        url = [[NSURL URLWithString:(NSString *)queryString relativeToURL:scopeURL] absoluteURL];
    }
    
    CFRelease(queryString);
    
    return url;
}

NSDictionary *OSUPerformCheck(NSURL *url)
{
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    
#ifdef DEBUG_bungi
    NSLog(@"OSU URL = %@", url);
#endif
    [resultDict setObject:[url absoluteString] forKey:OSUCheckResultsURLKey];
    
    NSError *error = nil;
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSURLResponse *response = nil;
    
    NSError *requestError = nil;
    NSData *resourceData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&requestError];
    if (!resourceData) {
        OBASSERT(requestError);
        error = requestError;
    }

    if ([response MIMEType])
        [resultDict setObject:[response MIMEType] forKey:OSUCheckResultsMIMETypeKey];
    if ([response textEncodingName])
        [resultDict setObject:[response textEncodingName] forKey:OSUCheckResultsTextEncodingNameKey];
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        NSInteger statusCode = [httpResponse statusCode];
        
        if ([httpResponse allHeaderFields])
            [resultDict setObject:[httpResponse allHeaderFields] forKey:OSUCheckResultsHeadersKey];
        
        [resultDict setObject:[NSNumber numberWithInteger:statusCode] forKey:OSUCheckResultsStatusCodeKey];
        
        if (statusCode >= 400) {
            // While we may have gotten back a result data, it is an error response.
            NSString *description = NSLocalizedStringFromTableInBundle(@"Error fetching software update information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
            NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please try again later or contact us to let us know this is broken.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason");
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, suggestion, NSLocalizedRecoverySuggestionErrorKey, url, NSURLErrorFailingURLErrorKey, nil];
            error = [NSError errorWithDomain:OSUErrorDomain code:OSUServerError userInfo:userInfo];
        }
    }
    
    // The check of 'error' here is intentional (as opposed to checking resultDict == nil) since they error might be formed from the response data (and indicate that there is no non-error response).
    if (error)
        [resultDict setObject:[error toPropertyList] forKey:OSUCheckResultsErrorKey];
    else if (resourceData)
        [resultDict setObject:resourceData forKey:OSUCheckResultsDataKey];
    
    return resultDict;
}

NSDictionary *OSURunOperation(const OSURunOperationParameters *params, NSError **outError)
{
    // Don't check for network availability if we are just going to report the system info
    if (!params->reportMode) {
        // Don't collect info if we are in non-report mode and we can't connect anyway.
        if (!OSUCheckReachability(params->firstHopHost, outError))
            return nil;
    }
    
    @try {
        CFDictionaryRef hardwareInfo = OSUCopyHardwareInfo(params->appIdentifier, params->includeHardwareInfo, params->licenseType, params->reportMode);
        
        NSURL *url = OSUMakeCheckURL(params->baseURLString, params->appIdentifier, params->appVersionString, params->track, params->osuVersionString, params->reportMode ? NULL : hardwareInfo);
        
        if (params->reportMode) {
            NSMutableDictionary *report = [NSMutableDictionary dictionary];
            if (hardwareInfo) {
                [report setObject:(id)hardwareInfo forKey:OSUReportResultsInfoKey];
                CFRelease(hardwareInfo);
            }
            
            NSString *urlString = [url absoluteString];
            if (urlString)
                [report setObject:urlString forKey:OSUReportResultsURLKey];
            return report;
        } else {
            CFRelease(hardwareInfo);
            return OSUPerformCheck(url);
        }
    } @catch (NSException *exc) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Error while checking for updated version.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Exception raised: %@", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error reason"), exc];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
        
        if (outError)
            *outError = [NSError errorWithDomain:OSUErrorDomain code:OSUExceptionRaised userInfo:userInfo];
        return nil;
    }
    
    OBASSERT_NOT_REACHED("silly compiler.");
    return nil;
}

