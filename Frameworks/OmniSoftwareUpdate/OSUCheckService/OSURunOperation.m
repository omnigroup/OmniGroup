// Copyright 2001-2008, 2010-2011, 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSURunOperation.h"

#import "OSURunOperationParameters.h"
#import "OSUOpenGLExtensions.h"
#import "OSUHardwareInfo.h"
#import "OSUCheckServiceProtocol.h"
#import "OSULookupCredentialProtocol.h"

#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

static OFDeclareDebugLogLevel(OSUDebugQuery);
#define OSU_DEBUG_QUERY(level, format, ...) do { \
    if (OSUDebugQuery >= (level)) \
        NSLog(@"OSU QUERY: " format, ## __VA_ARGS__); \
} while (0)


static BOOL isGLExtensionsKey(NSString *keyString)
{
    if ([keyString hasPrefix:@"gl_extensions"]) {
        // Assume no more than 10 GL adapters for now... where's my CFRegExp?
        
        if ([keyString length] == 14) {
            unichar ch = [keyString characterAtIndex:13];
            if (ch >= '0' && ch <= '9')
                return YES;
        }
    }
    
    // We handle OpenCL the same way now too. These are of the form clN_ext
    if ([keyString length] == 7 && [keyString hasPrefix:@"cl"] && [keyString hasSuffix:@"_ext"]) {
        // Assume no more than 10 GL adapters for now... where's my CFRegExp?
        
        unichar ch = [keyString characterAtIndex:2];
        if (ch >= '0' && ch <= '9')
            return YES;
    }
    
    return NO;
}

static NSURL *OSUMakeCheckURL(NSString *baseURLString, NSString *appIdentifier, NSString *appVersionString, NSString *track, NSString *osuVersionString, NSDictionary *info)
{
    OBPRECONDITION(baseURLString);
    OBPRECONDITION(appIdentifier);
    OBPRECONDITION(appVersionString);
    OBPRECONDITION(track);
    OBPRECONDITION(osuVersionString);
    
    // Build a query string from all the key/value pairs in the info dictionary.
    NSMutableString *queryString = [NSMutableString stringWithString:@"?"];
    
    [queryString appendFormat:@"OSU=%@", osuVersionString]; // Adding this first means we don't need to check before adding a ';' between key/value pairs below.
    
    // An encoding/bug-fix version. The "OSU" key above encodes a version that we use to decide whether to re-ask the user whether we are permitted to send info, while this version number specifies how we gathered the information and lets the interpreters of the logs better understand how to reason about the reports. Our OpenGL extension keys have embedded encoding versions already (which is fine -- we might pick multiple alternate encodings for them to get the smallest one for any particular system's report). This can serve as an overall encoding version.
    
    // v=1; Fixed run time calculations to not use NSDate. Added this encoding and the 'end' marker to detect truncated reports
    [queryString appendString:@";v=1"];
    
    [info enumerateKeysAndObjectsUsingBlock:^(NSString *keyString, NSString *valueString, BOOL *stop) {
        OBASSERT([keyString isEqualToString:@"v"] == NO, "We use this as our encoding version above");
        OBASSERT([keyString isEqualToString:@"end"] == NO, "We use this as a terminator below");
        
        NSString *escapedKey = CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)keyString, NULL, NULL, kCFStringEncodingUTF8));
        NSString *escapedValue;
        
        if (isGLExtensionsKey(keyString)) {
            NSString *compactedValue = OSUCopyCompactedOpenGLExtensionsList(valueString);
            escapedValue = CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)compactedValue, NULL, NULL, kCFStringEncodingUTF8));
        } else {
            escapedValue = CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)valueString, NULL, NULL, kCFStringEncodingUTF8));
        }
        
        
        [queryString appendString:@";"];
        [queryString appendString:escapedKey];
        [queryString appendString:@"="];
        [queryString appendString:escapedValue];
    }];
    
    // Add a terminating marker so we can detect when reports have been truncated (possibly by a proxy)
    [queryString appendString:@";end="];
    
    
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
        url = [[NSURL URLWithString:queryString relativeToURL:scopeURL] absoluteURL];
    }
    
    return url;
}

@interface OSUFetchOperation : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>

- initWithURL:(NSURL *)requestURL lookupCredential:(id <OSULookupCredential>)lookupCredential completionHandler:(OSURunOperationCompletionHandler)completionHandler;

@property(nonatomic,readonly) id <OSULookupCredential> lookupCredential;
@property(nonatomic,readonly) NSData *resourceData;
@property(nonatomic,readonly) NSError *error;
@property(nonatomic,readonly) NSURLResponse *response;
@end

// When running in the XPC service, we can't read the calling app's keychain (yay!). So, it needs to pass down the credential to use. Right now we have very minimal support for password-protected feeds -- you need to have visited the feed in Safari to get a password prompt, and then the calling app can see that and pass it down.
// Further, if we are running in the XCP service, we are currently on its queue, and if we block, we don't be able to process inbound replies to our lookupCredential usage. So, we perform our lookup work on yet another queue (which isn't needed in non-XPC version on iOS, but presumably someday we'll get XPC there...).
@implementation OSUFetchOperation
{
    NSURLRequest *_request;
    NSOperationQueue *_delegateQueue;
    NSURLConnection *_connection;
    NSMutableData *_resourceData;
    OSURunOperationCompletionHandler _completionHandler;
    NSURLCredential *_credential;
    BOOL _alreadyOfferedCredential;
}

- initWithURL:(NSURL *)requestURL lookupCredential:(id <OSULookupCredential>)lookupCredential completionHandler:(OSURunOperationCompletionHandler)completionHandler;
{
    if (!(self = [super init]))
        return nil;
    

    // The intention is that check operations should be far enough apart in time that the cached data wouldn't be used anyway. Caching clutters up the filesystem and makes debugger a bit harder (when it unexpectedly caches due to the shorter time window).
    _request = [NSURLRequest requestWithURL:requestURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    _lookupCredential = lookupCredential;
    _completionHandler = [completionHandler copy];

    _resourceData = [[NSMutableData alloc] init];
    
    return self;
}

- (void)start;
{
    OBPRECONDITION(_connection == nil);
    
    _delegateQueue = [[NSOperationQueue alloc] init];
    _delegateQueue.maxConcurrentOperationCount = 1;
    _delegateQueue.name = @"com.omnigroup.OmniSoftwareUpdate.CheckService.FetchOperation";
    
    OSU_DEBUG_QUERY(1, "Performing check with URL %@", _request.URL);

    _connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self startImmediately:NO];
    [_connection setDelegateQueue:_delegateQueue];
    
    [_connection start];
}

- (void)_finished;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _delegateQueue);
    OBPRECONDITION(_connection, "Shouldn't be finished yet");
    OBPRECONDITION(_completionHandler, "Shouldn't be finished yet");
    
    NSURL *url = _request.URL;
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    
    
    [resultDict setObject:[url absoluteString] forKey:OSUCheckResultsURLKey];
    
    OBASSERT_IF(_resourceData == nil, _error);
    
    if ([_response MIMEType])
        [resultDict setObject:[_response MIMEType] forKey:OSUCheckResultsMIMETypeKey];
    if ([_response textEncodingName])
        [resultDict setObject:[_response textEncodingName] forKey:OSUCheckResultsTextEncodingNameKey];
    
    NSError *error = _error;
    if ([_response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)_response;
        
        NSInteger statusCode = [httpResponse statusCode];
        
        if ([httpResponse allHeaderFields])
            [resultDict setObject:[httpResponse allHeaderFields] forKey:OSUCheckResultsHeadersKey];
        
        [resultDict setObject:[NSNumber numberWithInteger:statusCode] forKey:OSUCheckResultsStatusCodeKey];
        
        if (statusCode >= 400) {
            // While we may have gotten back a result data, it is an error response.
            // Calling code in OSUCheckOperation will add localized description/suggestion, but we add the code/url here.
            NSString *reason = [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:reason, NSLocalizedFailureReasonErrorKey, url, NSURLErrorFailingURLErrorKey, nil];
            error = [NSError errorWithDomain:OSUCheckServiceErrorDomain code:OSUCheckServiceServerError userInfo:userInfo];
        }
    }
    
    // The check of 'error' here is intentional (as opposed to checking resultDict == nil) since they error might be formed from the response data (and indicate that there is no non-error response).
    if (error)
        [resultDict setObject:[error toPropertyList] forKey:OSUCheckResultsErrorKey];
    else if (_resourceData) {
#if 0 && defined(DEBUG)
        // Intentionally corrupt the result data to check that the signature checking works. Just appending a space won't hurt since the signature is validated against the normalized XML.
        NSLog(@"*** Intentionally corrupting result data to test signature checking ***");
        NSString *string = [[NSString alloc] initWithData:_resourceData encoding:NSUTF8StringEncoding];
        NSRange priceRange = [string rangeOfString:@"<omniappcast:price>0</omniappcast:price>"];
        if (priceRange.location == NSNotFound) {
            NSLog(@"*** Cannot find range to edit ***");
        } else {
            NSMutableString *mutated = [string mutableCopy];
            [mutated replaceCharactersInRange:priceRange withString:@"<omniappcast:price>999</omniappcast:price>"];
            _resourceData = [[mutated dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        }
#endif
        [resultDict setObject:_resourceData forKey:OSUCheckResultsDataKey];
    }
    
    OSU_DEBUG_QUERY(2, "Query resulted in dictionary %@", resultDict);
    
    OSURunOperationCompletionHandler handler = _completionHandler;

    // Clean up possible retain cycles
    _completionHandler = nil;
    _delegateQueue = nil;
    _connection = nil;
    
    handler(resultDict, nil);
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
{
    OBPRECONDITION(connection == _connection);
    OBPRECONDITION([NSOperationQueue currentQueue] == _delegateQueue);
    OBPRECONDITION(_error == nil);
    OBPRECONDITION(error);
    
    _error = error;
    [self _finished];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
    OBPRECONDITION(connection == _connection);
    OBPRECONDITION([NSOperationQueue currentQueue] == _delegateQueue);
    OBPRECONDITION(_error == nil);

    [self _finished];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    OBPRECONDITION(connection == _connection);
    OBPRECONDITION([NSOperationQueue currentQueue] == _delegateQueue);
    OBPRECONDITION(_error == nil);
    OBPRECONDITION(response);
    
    _response = response;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    OBPRECONDITION(connection == _connection);
    OBPRECONDITION([NSOperationQueue currentQueue] == _delegateQueue);
    OBPRECONDITION(data);
    
    [_resourceData appendData:data];
}


- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBPRECONDITION(connection == _connection);
    OBPRECONDITION([NSOperationQueue currentQueue] == _delegateQueue);
    
    OBASSERT([challenge sender], "NSURLConnection-based challenged need the old 'sender' calls.");
    
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    NSString *challengeMethod = [protectionSpace authenticationMethod];
    
    if ([challengeMethod isEqual:NSURLAuthenticationMethodServerTrust]) {
#if 0 && defined(DEBUG_bungi)
        // This is only for testing authenticated feeds, since the local test server has a self-signed certificate.
        SecTrustRef trustRef;
        if ((trustRef = [protectionSpace serverTrust]) != NULL) {
            SecTrustResultType evaluationResult = kSecTrustResultOtherError;
            OSStatus oserr = SecTrustEvaluate(trustRef, &evaluationResult); // NB: May block for long periods (eg OCSP verification, etc)

            if (oserr == noErr && evaluationResult == kSecTrustResultRecoverableTrustFailure) {
                NSLog(@"*** Adding trust for certificate ***");
                
                NSURLCredential *credential = [NSURLCredential credentialForTrust:trustRef];
                [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                return;
            }
        }
#endif

        // If we "continue without credential", NSURLConnection will consult certificate trust roots and per-cert trust overrides in the normal way. If we cancel the "challenge", NSURLConnection will drop the connection, even if it would have succeeded without our meddling (that is, we can force failure as well as forcing success).
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
        return;
    }
    
    if (!_credential && _lookupCredential) {
        __block BOOL done = NO;
        
        // Since we are not on the XPC queue here, we can send a XPC message back to the app and block (this is the whole reason we use a separate queue for the NSURL operation).
        [_lookupCredential lookupCredentialForProtectionSpace:protectionSpace withReply:^(NSURLCredential *foundCredential){
            _credential = foundCredential;
            done = YES;
        }];

        // We expect this to be very quick, but let's time out eventually. Maybe the user's keychain will need to be unlocked, but we don't want to wait for them to type in a  username or password. The app on the other end may decide to put up a password sheet, store the credential, and re-run the update check, though.
        BOOL finished = OFRunLoopRunUntil(60, OFRunLoopRunTypePolling, ^BOOL{
            return done;
        });
        if (!finished) {
            NSLog(@"Timed out waiting for credential lookup from the main app.");
        }
    }
    
    if (_credential && _alreadyOfferedCredential == NO) {
        _alreadyOfferedCredential = YES;
        [[challenge sender] useCredential:_credential forAuthenticationChallenge:challenge];
    } else {
        if (_alreadyOfferedCredential) {
            NSLog(@"Offered credentials didn't work, continuing without credentials.");
            if (_credential.password == nil)
                NSLog(@"  Unsurprising, since the password is nil"); // Happens during development *sometimes*
        } else
            NSLog(@"No credentials specified by calling application, but got a challenge: %@", challenge);
        
        // We'd prefer to cancel here, but if we do, we might deadlock (based on experience with queue-based scheduling in OmniDAV).
        //[[challenge sender] cancelAuthenticationChallenge:challenge];
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

@end


static void OSUPerformCheck(NSURL *url, id <OSULookupCredential> lookupCredential, OSURunOperationCompletionHandler completionHandler)
{
    OBPRECONDITION(completionHandler);
    
    OSUFetchOperation *op = [[OSUFetchOperation alloc] initWithURL:url lookupCredential:lookupCredential completionHandler:completionHandler];
    [op start];
}

void OSURunOperation(OSURunOperationParameters *params, NSDictionary *runtimeStatsAndProbes, id <OSULookupCredential> lookupCredential, OSURunOperationCompletionHandler completionHandler)
{
    @try {
        NSMutableDictionary *hardwareInfo = CFBridgingRelease(OSUCopyHardwareInfo(params.appIdentifier, params.uuidString, runtimeStatsAndProbes, params.includeHardwareInfo, params.licenseType, params.reportMode));
        
        NSURL *url = OSUMakeCheckURL(params.baseURLString, params.appIdentifier, params.appVersionString, params.track, params.osuVersionString, params.reportMode ? NULL : hardwareInfo);
        
        if (params.reportMode) {
            NSMutableDictionary *report = [NSMutableDictionary dictionary];
            if (hardwareInfo) {
                [report setObject:(id)hardwareInfo forKey:OSUReportResultsInfoKey];
            }
            
            NSString *urlString = [url absoluteString];
            if (urlString)
                [report setObject:urlString forKey:OSUReportResultsURLKey];
            
            if (completionHandler)
                completionHandler(report, nil);
        } else {
            OSUPerformCheck(url, lookupCredential, completionHandler);
        }
    } @catch (NSException *exc) {
        if (completionHandler) {
            NSString *reason = [exc description];
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:reason, NSLocalizedFailureReasonErrorKey, nil];
        
            NSError *error = [NSError errorWithDomain:OSUCheckServiceErrorDomain code:OSUCheckServiceExceptionRaisedError userInfo:userInfo];
            completionHandler(nil, error);
        }
    }
}

