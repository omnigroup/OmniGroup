// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODAVOperation-Internal.h"

#import <OmniDAV/ODAVErrors.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <Security/SecTrust.h>

RCS_ID("$Id$");

NSString * const ODAVContentTypeHeader = @"Content-Type";

@implementation ODAVOperation
{
    void (^_start)(void);
    void (^_cancel)(void);
    
    // For PUT operations
    long long _bodyBytesSent;
    long long _expectedBytesToWrite;
    
    // Mostly for GET operations, though _response gets used at the end of a PUT or during an auth challenge.
    NSHTTPURLResponse *_response;
    NSMutableData *_resultData;
    NSUInteger _bytesReceived;
    
    BOOL _finished;
    BOOL _shouldCollectDetailsForError;
    BOOL _authChallengeCancelled;
    NSMutableData *_errorData;
    NSError *_error;
    NSMutableArray <ODAVRedirect *> *_redirects;
}

static BOOL _isRead(ODAVOperation *self)
{
    NSString *method = [self->_request HTTPMethod];
    
    // We assert it is uppercase in the initializer.
    if ([method isEqualToString:@"GET"] || [method isEqualToString:@"PROPFIND"] || [method isEqualToString:@"LOCK"])
        return YES;
    
    OBASSERT([method isEqualToString:@"PUT"] ||
             [method isEqualToString:@"POST"] ||
             [method isEqualToString:@"MKCOL"] ||
             [method isEqualToString:@"DELETE"] ||
             [method isEqualToString:@"MOVE"] ||
             [method isEqualToString:@"COPY"] ||
             [method isEqualToString:@"UNLOCK"]); // The delegate doesn't need to read any data from these operations
    
    return NO;
}

static OFCharacterSet *QuotedStringDelimiterSet = nil;
static OFCharacterSet *TokenDelimiterSet = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    QuotedStringDelimiterSet = [[OFCharacterSet alloc] initWithString:@"\"\\"];

    // This definition of a Content-Type header token's delimiters is from the MIME standard, RFC 1521: http://www.oac.uci.edu/indiv/ehood/MIME/1521/04_Content-Type.html
    OFCharacterSet *newSet = [[OFCharacterSet alloc] initWithString:@"()<>@,;:\\\"/[]?="];
    [newSet addCharacter:' '];
    [newSet addCharactersFromCharacterSet:[NSCharacterSet controlCharacterSet]];
    
    // This is not part of the MIME standard, but we don't really need to treat "/" in any special way for this implementation
    [newSet removeCharacter:'/'];
    
    TokenDelimiterSet = newSet;
}

- initWithRequest:(NSURLRequest *)request
            start:(void (^)(void))start
           cancel:(void (^)(void))cancel;
{
    OBPRECONDITION([[[request URL] scheme] isEqualToString:@"http"] || [[[request URL] scheme] isEqualToString:@"https"]); // We want a NSHTTPURLResponse
    OBPRECONDITION([[request HTTPMethod] isEqualToString:[[request HTTPMethod] uppercaseString]]);
    OBPRECONDITION(start);
    OBPRECONDITION(cancel);
    
    if (!(self = [super init]))
        return nil;

    _request = [request copy];
    _redirects = [[NSMutableArray alloc] init];
        
    // For write operations, we have to record the expected length here AND in the NSURLConnection callback. The issue is that for https PUT operations, we can get an authorization challenge after we've uploaded the entire body, at which point we'll have to start all over. NSURLConnection keeps the # bytes increasing and doubles the expected bytes to write at this point (which is more accurate than going back to zero bytes, by some measure).
    if (!_isRead(self)) {
        NSData *body = [request HTTPBody];
        // OBASSERT(body); // We don't support streams, but we might be performing an operation which doesn't involve data (e.g. removing a file)
        
        _expectedBytesToWrite = [body length];
    }

    _start = [start copy];
    _cancel = [cancel copy];

    return self;
}

- (void)dealloc;
{
    if (!_finished) {
        if (_cancel)
            _cancel();
    }
}

- (NSError *)prettyErrorForDAVError:(NSError *)davError;
{
    // Pretty up some errors, wrapping them in another DAV error rather than making our own.  Just put prettier strings on them.
    NSInteger code = [davError code];
    
    // me.com returns 402 Payment Required if you mistype your user name.  402 is currently reserved and Apple shouldn't be using it at all; Radar 6253979
    // 409 Conflict -- we can get this if the user mistypes the directory or forgets to create it.  There might be other cases, but this is by far the most likely.
    if (code == ODAV_HTTP_UNAUTHORIZED || code == ODAV_HTTP_PAYMENT_REQUIRED || code == ODAV_HTTP_CONFLICT) {
        NSString *location = [[_request URL] absoluteString];
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not access the WebDAV location <%@>.", @"OmniDAV", OMNI_BUNDLE, @"error description"),
                                 location];
        NSString *reason;
        switch (code) {
            case 401:
                reason = NSLocalizedStringFromTableInBundle(@"Please check that the user name and password you provided are correct.", @"OmniDAV", OMNI_BUNDLE, @"error suggestion");
                break;
            case 402:
                reason = NSLocalizedStringFromTableInBundle(@"Please make sure that the account information is correct.", @"OmniDAV", OMNI_BUNDLE, @"error reason");
                break;
            default:
            case 409:
                reason = NSLocalizedStringFromTableInBundle(@"Please make sure that the destination folder exists.", @"OmniDAV", OMNI_BUNDLE, @"error reason");
                break;
        }

        NSDictionary *info = @{
                 NSLocalizedDescriptionKey: description,
                 NSLocalizedRecoverySuggestionErrorKey: reason,
                 NSUnderlyingErrorKey: davError
        };
        return [NSError errorWithDomain:ODAVHTTPErrorDomain code:code userInfo:info];
    }
    
    return davError;
}

+ (NSString *)_parseContentTypeHeaderValue:(NSString *)aString intoDictionary:(OFMultiValueDictionary *)parameters valueChars:(NSCharacterSet *)validValues;
{
    __block NSString *bareHeader = nil;
    @autoreleasepool {
        OFCharacterSet *whitespaceSet = [OFCharacterSet whitespaceOFCharacterSet];
        
        OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:aString];
        scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
        
        bareHeader = [scanner readFullTokenWithDelimiterOFCharacterSet:TokenDelimiterSet forceLowercase:YES]; // Base mime types are case-insensitive
        
        scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
        while (scannerPeekCharacter(scanner) == ';') {
            scannerSkipPeekedCharacter(scanner); // Skip ';'
            scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
            NSString *attribute = [scanner readFullTokenWithDelimiterOFCharacterSet:TokenDelimiterSet forceLowercase:YES]; // Attribute names are case-insensitive
            if ([NSString isEmptyString:attribute])
                break; // Missing parameter name
            scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
            if (scannerPeekCharacter(scanner) != '=')
                break; // Missing '='
            scannerSkipPeekedCharacter(scanner); // Skip '='
            scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
            if (scannerPeekCharacter(scanner) == '"') { // Value is a quoted-string
                scannerSkipPeekedCharacter(scanner); // Skip '"'
                NSMutableString *value = [NSMutableString string];
                while (scannerHasData(scanner)) {
                    NSString *partialValue = [scanner readFullTokenWithDelimiterOFCharacterSet:QuotedStringDelimiterSet forceLowercase:NO];
                    [value appendString:partialValue];
                    unichar delimiterCharacter = scannerPeekCharacter(scanner);
                    if (delimiterCharacter == '\\') {
                        scannerSkipPeekedCharacter(scanner); // Skip '\'
                        unichar quotedCharacter = scannerPeekCharacter(scanner);
                        if (quotedCharacter != OFCharacterScannerEndOfDataCharacter) {
                            // There isn't a particularly efficient way to do this using the ObjC interface, so...
                            CFStringAppendCharacters((CFMutableStringRef)value, &quotedCharacter, 1);
                        }
                    } else if (delimiterCharacter == '"') {
                        scannerSkipPeekedCharacter(scanner); // Skip final '"'
                        break; // We're done scanning this quoted-string value
                    } else {
                        OBASSERT(delimiterCharacter == OFCharacterScannerEndOfDataCharacter); // We only have two characters in our delimiter set, and we've already tested for both above
                        break; // Malformed input (we never saw our final quote), but we can go ahead and use what we've got so far
                    }
                }
                [parameters addObject:value forKey:attribute];
            } else {
                // Value is a simple token, not a quoted-string
                NSString *value = [scanner readFullTokenWithDelimiterOFCharacterSet:TokenDelimiterSet forceLowercase:NO];
                [parameters addObject:value forKey:attribute];
            }
            scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
        }
    }
    return bareHeader;
}

- (NSInteger)statusCode;
{
    if (!_response)
        OBRejectInvalidCall(self, _cmd, @"No response");
    return [_response statusCode];
}

- (NSString *)valueForResponseHeader:(NSString *)header;
{
    OBPRECONDITION(_response);
    return [_response allHeaderFields][header];
}

- (BOOL)retryable;
{
    return _isRead(self);
}

#pragma mark - ODAVAsynchronousOperation

// These callbacks should all be called with this macro
#define PERFORM_CALLBACK(callback, ...) do { \
    typeof(callback) _cb = (callback); \
    if (_cb) { \
        [_callbackQueue addOperationWithBlock:^{ \
            _cb(__VA_ARGS__); \
        }]; \
    } \
} while(0)

@synthesize didFinish = _didFinish;
@synthesize didReceiveData = _didReceiveData;
@synthesize didReceiveBytes = _didReceiveBytes;
@synthesize didSendBytes = _didSendBytes;

@synthesize resultData = _resultData;

- (NSURL *)url;
{
    return [_request URL];
}

- (long long)processedLength;
{
    // TODO: In general, we could have a POST that sends body data AND returns content. We don't for DAV support right now, but lets assert this is true.
    OBPRECONDITION([_resultData length] == 0 || _bodyBytesSent == 0);
    
    if (_isRead(self)) {
        // If we have a didReceiveData block, we don't buffer up the data, but we do keep a count.
        if (_didReceiveData)
            return _bytesReceived;
        else
            return [_resultData length];
    } else {
        return _bodyBytesSent;
    }
}

- (long long)expectedLength;
{
    // TODO: In general, we could have a POST that sends body data AND returns content. We don't for DAV support right now, but lets assert this is true.
    OBPRECONDITION([_resultData length] == 0 || _bodyBytesSent == 0);

    if (_isRead(self)) {
        return _response ? [_response expectedContentLength] : NSURLResponseUnknownLength;
    } else {
        // See our initializer for details on this ivar's purpose.
        return _expectedBytesToWrite;
    }
}

- (void)startWithCallbackQueue:(NSOperationQueue *)queue;
{
    OBPRECONDITION(_start);
    OBPRECONDITION(_didFinish); // What is the purpose of an async operation that we don't track the end of?
    OBPRECONDITION(_response == nil);
    
    /*
     Operations get called by their owning session on its queue, but invoke their callbacks on a potentially different queue.
     */
    
    if (queue)
        _callbackQueue = queue;
    else
        _callbackQueue = [NSOperationQueue currentQueue];
    
    _start();
}

- (void)cancel;
{
    if (_cancel) {
        _cancel();
        _cancel = nil;
    }
    _start = nil;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark - Internal

- (void)_credentialsNotFoundForChallenge:(NSURLAuthenticationChallenge *)challenge disposition:(NSURLSessionAuthChallengeDisposition)disposition;
{
    // Keep around the response that says something about the failure, and set the flag indicating we want details recorded for this error
    OBASSERT(_response == nil);
    _response = [[challenge failureResponse] copy];
    _shouldCollectDetailsForError = YES;
    _authChallengeCancelled = (disposition == NSURLSessionAuthChallengeCancelAuthenticationChallenge);
}

- (void)_didCompleteWithError:(NSError *)error;
{
    OBASSERT(!_finished);
    OBASSERT(_error == nil);

    if (error) {
        [self _logError:error];
        
        _error = [error copy];
    } else {
#ifdef OMNI_ASSERTIONS_ON
        long long expectedContentLength = [_response expectedContentLength];
#endif
        OBASSERT(expectedContentLength >= 0 || expectedContentLength == NSURLResponseUnknownLength);
#ifdef OMNI_ASSERTIONS_ON
        if (_didReceiveData == nil)
            OBPRECONDITION(_bytesReceived == [_resultData length]); // We don't buffer the data if we are passing it out to a block.
        OBASSERT(expectedContentLength == NSURLResponseUnknownLength || _bytesReceived <= (unsigned long long)expectedContentLength); // should have gotten all the content if we are to be considered successfully finised
#endif
    }
    [self _finish];
}

- (void)_didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    OBPRECONDITION(_response == nil);
    OBPRECONDITION(bytesSent >= 0);
    
    DEBUG_DAV(3, @"%@: did send data of length %qd (total %qd, expected %qd)", [self shortDescription], bytesSent, totalBytesSent, totalBytesExpectedToSend);
    
    _bodyBytesSent = totalBytesSent;
    _expectedBytesToWrite = totalBytesExpectedToSend; // See our initializer for details on this ivar's purpose.
    
    OBASSERT(bytesSent <= totalBytesSent);
    OBASSERT(totalBytesSent <= totalBytesExpectedToSend);
    
    PERFORM_CALLBACK(_didSendBytes, self, bytesSent);
}

- (void)_didReceiveResponse:(NSURLResponse *)response;
{
    // We'll already have a _response set for credential errors, via -_credentialsNotFoundForChallenge:.
    if (_response) {
        // The NSURL machinery handles redirects without even showing them to us; the only expected situation for us to get multiple responses is during authentication requests.
        // If this assertion fails it's probably fine to extend it with additional status codes.
        OBASSERT([_response statusCode] == ODAV_HTTP_UNAUTHORIZED);
    }
    
    // Discard information we may have collected from a previous response.
    _response = nil;
    _resultData = nil;
    _bytesReceived = 0;
    _shouldCollectDetailsForError = NO;
    _errorData = nil;
    
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        // This will mean we treat it as success in that we'll try to decode the response data.
        NSLog(@"%@: Unexpected response: %@", [self shortDescription], response);
        NSLog(@"  URL: %@", [response URL]);
        NSLog(@"  MIMEType: %@", [response MIMEType]);
        NSLog(@"  expectedContentLength: %qd", [response expectedContentLength]);
        NSLog(@"  textEncodingName: %@", [response textEncodingName]);
        NSLog(@"  suggestedFilename: %@", [response suggestedFilename]);
        return;
    }
    
    _response = [response copy];
    
    if (ODAVConnectionDebug > 2) {
        NSLog(@"%@: did receive response %@", [self shortDescription], _response);
        NSLog(@"  URL: %@", [_response URL]);
        NSLog(@"  MIMEType: %@", [_response MIMEType]);
        NSLog(@"  expectedContentLength: %qd", [_response expectedContentLength]);
        NSLog(@"  textEncodingName: %@", [_response textEncodingName]);
        NSLog(@"  suggestedFilename: %@", [_response suggestedFilename]);
        NSLog(@"  statusCode: %ld", [_response statusCode]);
        NSLog(@"  allHeaderFields: %@", [_response allHeaderFields]);
    }
    
    NSInteger statusCode = [_response statusCode];
    if (statusCode >= 200 && statusCode < 300) {
        // If we got a successful response, we want to pre-populate our result data with empty data rather than ever returning nil
        OBASSERT(_resultData == nil);
        _resultData = [[NSMutableData alloc] init];
        _bytesReceived = 0;
        
        NSDictionary *responseHeaders = [(NSHTTPURLResponse *)response allHeaderFields];
        NSString *location = [responseHeaders objectForKey:@"Content-Location"];
        if (location) {
            ODAVAddRedirectEntry(_redirects, kODAVRedirectContentLocation, [_response URL], [NSURL URLWithString:location relativeToURL:[_response URL]], responseHeaders);
        }
    }
    
    OBASSERT(statusCode > 199);   // NSURLConnection should handle 100-Continue.
    if (statusCode >= 300) {
        // When the source is a redirecting URL, we'll have gone through the normal redirection path. But when the Destination header points at something that needs redirection, we don't.
        // Apache does *not* do the MOVE in this case, and does not return a Location header (possibly since there is nothing at that location).
        // NSURLConnection presumably notices there is no Location header in the 301/302 response and doesn't do its redirection path.
        // We can't recover from this easily here, so it is an error.
        if (statusCode < 400) {
#ifdef DEBUG_bungi
            OBASSERT(NO, "This is likely a bug in the calling code");
#endif
            OBASSERT([[_request HTTPMethod] isEqual:@"COPY"] || [[_request HTTPMethod] isEqual:@"MOVE"]);
#ifdef OMNI_ASSERTIONS_ON
            NSDictionary *responseHeaders = [(NSHTTPURLResponse *)response allHeaderFields];
            OBASSERT(responseHeaders[@"Location"] == nil);
            NSLog(@"%@: Incorrect MOVE/COPY with Destination needing redirect %@", [self shortDescription], [_request valueForHTTPHeaderField:@"Destination"]);
#endif
        }
        
        /* We treat 3xx codes as errors here (in addition to the 4xx and 5xx codes) because any redirection should have been handled at a lower level, by NSURLConnection. If we do end up with a 3xx response, we can't treat it as a success anyway, because the response body of a 3xx is not the entity we requested --- it's usually a little server-generated HTML snippet saying "click here if the redirect didn't work". */
        _shouldCollectDetailsForError = YES;
        return;
    }
    
    if (statusCode == ODAV_HTTP_MULTI_STATUS && ![[_request HTTPMethod] isEqual:@"PROPFIND"]) {
        // PROPFIND is supposed to return ODAV_HTTP_MULTI_STATUS, but if we get it for COPY/DELETE/MOVE, then it is an error
        // The response will be a DAV multistatus that we will turn into an error.
        _shouldCollectDetailsForError = YES;
        return;
    }
    
    OBASSERT(_isRead(self) || statusCode == ODAV_HTTP_CREATED || statusCode == ODAV_HTTP_NO_CONTENT);
}

- (void)_didReceiveData:(NSData *)data;
{
    OBPRECONDITION(_response);
    OBPRECONDITION([_response statusCode] != ODAV_HTTP_NO_CONTENT);
    
    DEBUG_DAV(3, @"%@: did receive data of length %ld", [self shortDescription], [data length]);
    
    if (_shouldCollectDetailsForError) {
        // We're collecting details about an HTTP error
        if (!_errorData)
            _errorData = [[NSMutableData alloc] initWithData:data];
        else
            [_errorData appendData:data];
        return; // We don't want to send uninterpreted error content to our target
    }
    
    long long processedBytes = [data length];
    OBASSERT(processedBytes >= 0);
    
    _bytesReceived += processedBytes;
    
    if (_didReceiveData)
        // We don't accumulate data in this case (but do want to report the total bytes received).
        PERFORM_CALLBACK(_didReceiveData, self, data);
    else {
        PERFORM_CALLBACK(_didReceiveBytes, self, [data length]);
        
        // We are supposed to collect the data
        if (!_resultData)
            _resultData = [[NSMutableData alloc] initWithData:data];
        else
            [_resultData appendData:data];
        OBASSERT(_bytesReceived > 0);
        OBASSERT(_bytesReceived == [_resultData length]);
    }
    
    // Check that the server and we agree on the expected content length, if it was sent.  It might not have said a content length, in which case we'll just get as much content as we are given.
#ifdef OMNI_ASSERTIONS_ON
    long long expectedContentLength = [_response expectedContentLength];
#endif
    OBPOSTCONDITION(expectedContentLength >= 0 || expectedContentLength == NSURLResponseUnknownLength);
    OBPOSTCONDITION(expectedContentLength == NSURLResponseUnknownLength || _bytesReceived <= (NSUInteger)expectedContentLength);
}

- (NSURLRequest *)_willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse;
{
    if (ODAVConnectionDebug > 2) {
        NSLog(@"%@: will send request %@, redirect response %@", [self shortDescription], request, redirectResponse);
        NSLog(@"request URL: %@", [request URL]);
        NSLog(@"request headers: %@", [request allHTTPHeaderFields]);
        NSLog(@"redirect URL: %@", [redirectResponse URL]);
        NSLog(@"redirect headers: %@", [(id)redirectResponse allHeaderFields]);
    }
    
    NSURLRequest *continuation = nil;
    
    // Some WebDAV servers (the one builtin in Mac OS X Server, but not the one in .Mac) will redirect "/xyz" to "/xyz/" if we PROPFIND something that is a directory.  But, the re-sent request will be a GET instead of a PROPFIND.  This, in turn, will cause us to get back HTML instead of the expected XML.
    // (This is what HTTP specifies as correct behavior for everything except GET and HEAD, mostly for security reasons: see RFC2616 section 10.3.)
    // Likewise, if we MOVE /a/ to /b/ we've seen redirects to the non-slash version.  In particular, when using the LAN-local apache and picking local in the simulator on an incompatible database conflict.  When we try to put the new resource into place, it redirects.
    // The above is arguably a bug in Apache.
    /*
     RFC4918 section [5.2], "Collection Resources", says in part:
     There is a standing convention that when a collection is referred to by its name without a trailing slash, the server may handle the request as if the trailing slash were present. In this case, it should return a Content-Location header in the response, pointing to the URL ending with the "/". For example, if a client invokes a method on http://example.com/blah (no trailing slash), the server may respond as if the operation were invoked on http://example.com/blah/ (trailing slash), and should return a Content-Location header with the value http://example.com/blah/. Wherever a server produces a URL referring to a collection, the server should include the trailing slash. In general, clients should use the trailing slash form of collection names. If clients do not use the trailing slash form the client needs to be prepared to see a redirect response. Clients will find the DAV:resourcetype property more reliable than the URL to find out if a resource is a collection.
     */
    if (redirectResponse) {
        NSString *method = [_request HTTPMethod];
        if ([method isEqualToString:@"PROPFIND"] || [method isEqualToString:@"MKCOL"] || [method isEqualToString:@"DELETE"]) {
            // PROPFIND is a GET-like request, so when we redirect, keep the method.
            // Duplicate the original request, including any DAV headers and body content, but put in the redirected URL.
            // MKCOL is not a 'safe' method, but for our purposes it can be considered redirectable.
            OBPRECONDITION([_request valueForHTTPHeaderField:@"If"] == nil); // TODO: May need to rewrite the URL here too.
            NSMutableURLRequest *redirect = [_request mutableCopy];
            [redirect setURL:[request URL]];
            continuation = redirect;
        } else if ([method isEqualToString:@"GET"]) {
            // The NSURLConnection machinery handles GETs the way we want already.
            continuation = request;
        } else if ([method isEqualToString:@"MOVE"] || [method isEqualToString:@"COPY"]) {
            // MOVE/COPY is a bit dubious. If the source URL gets rewritten by the server, do we know that the destination URL we're sending is still what it should be?
            // In theory we wouldn't get this, as long as we paid attention to the response to the PUT/MKCOL/PROPFIND request used to create/find the resource we're operating on.
            // Exception: When replacing a remote database with the local version, if the user-entered URL incurs a redirect (e.g. http->https), we will still get a redirect on MOVE when moving the old database aside before replacing it with the new one.  TODO: Figure out how to avoid this.
            // OBASSERT_NOT_REACHED("In theory, we shouldn't get redirected on MOVE?");
            
            // Try to rewrite the destination URL analogously to the source URL.
            NSString *rewrote = OFURLAnalogousRewrite([_request URL], [_request valueForHTTPHeaderField:@"Destination"], [request URL]);
            if (rewrote) {
#ifdef OMNI_ASSERTIONS_ON
                NSLog(@"%@: Suboptimal redirect %@ -> %@ (destination %@ -> %@)", [self shortDescription], [redirectResponse URL], [request URL], [_request valueForHTTPHeaderField:@"Destination"], rewrote);
#endif
                NSMutableURLRequest *redirect = [_request mutableCopy];
                [redirect setURL:[request URL]];
                [redirect setValue:rewrote forHTTPHeaderField:@"Destination"];
                continuation = redirect;
            } else {
                // We don't have enough information to figure out what the redirected request should be.
                continuation = nil;
            }
        } else if ([method isEqualToString:@"PUT"]) {
            // We really should never get a redirect on PUT anymore when working on our remote databases: we always use an up-to-date base URL derived from an earlier PROPFIND on our .ofocus collection.
            // The one exception is when uploading an .ics file, which goes directly into the directory specified by the user and therefore might hit an initial redirect, esp. for the http->https redirect case.
            // OBASSERT_NOT_REACHED("In theory, we shouldn't get redirected on PUT?");
            
#ifdef OMNI_ASSERTIONS_ON
            NSLog(@"%@: Suboptimal redirect %@ -> %@", [self shortDescription], [redirectResponse URL], [request URL]);
#endif
            
            NSMutableURLRequest *redirect = [_request mutableCopy];
            [redirect setURL:[request URL]];
            continuation = redirect;
        } else {
            OBASSERT_NOT_REACHED("Anything else get redirected that needs this treatment?");
            continuation = request;
        }
        
        if (continuation && redirectResponse) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)redirectResponse;
            ODAVAddRedirectEntry(_redirects,
                                 [NSString stringWithFormat:@"%u", (unsigned)[httpResponse statusCode]],
                                 [redirectResponse URL], [continuation URL], [httpResponse allHeaderFields]);
        }
        
    } else {
        // We're probably sending the initial request, here.
        // (Note that 10.4 doesn't seem to call us for the initial request; 10.6 does. Not sure when this changed.)
        continuation = request;
    }
    
    return continuation;
}

#pragma mark - Private

- (NSError *)_generateErrorFromMultiStatus;
{
    // The error data we've collected should be a DAV multistatus describing why the operation didn't happen.
    __autoreleasing NSError *error;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithData:_errorData whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] error:&error];
    if (!doc)
        return nil; // -_generateErrorForResponse will just report a generic error with the original error data unparsed.
    
    OFXMLCursor *cursor = [doc cursor];
    if (![[cursor name] isEqualToString:@"multistatus"])
        return nil;
    
    // There will be multiple <response> elements, but we'll just take the first. The last may actually be better since Apache reports parent directories first.
    if (![cursor openNextChildElementNamed:@"response"])
        return nil;
    

    OFXMLElement *child;
    
    NSString *encodedPath;
    if ((child = [[cursor currentElement] firstChildNamed:@"href"]))
        encodedPath = OFCharacterDataFromElement(child);
    
    NSString *statusLine;
    if ((child = [[cursor currentElement] firstChildNamed:@"status"]))
        statusLine = OFCharacterDataFromElement(child);
    
    if (!encodedPath || !statusLine)
        return nil;
    
    // I don't see any obvious CF/NS function to parse a HTTP status line...
    NSUInteger statusCode;
    {
        NSArray *components = [statusLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([components count] != 3)
            return nil;
        
        NSString *statusCodeString = components[1];
        if ([statusCodeString rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].length > 0)
            return nil;
        statusCode = [statusCodeString unsignedLongValue];
    }

    return [NSError errorWithDomain:ODAVHTTPErrorDomain code:statusCode userInfo:nil];
}

- (NSString *)_localizedStringForStatusCode:(NSInteger)statusCode;
{
    switch (statusCode) {
        case ODAV_HTTP_INSUFFICIENT_STORAGE:
            return NSLocalizedStringFromTableInBundle(@"insufficient storage", @"OmniDAV", OMNI_BUNDLE, @"Text for HTTP error code 507 (insufficient storage)"); // We can do better than "server error", which is what +[NSHTTPURLResponse localizedStringForStatusCode:] returns
        default:
            return [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
    }
}

- (NSError *)_generateErrorForResponse;
{
    NSInteger statusCode = [_response statusCode];
    
    NSMutableDictionary *info = [NSMutableDictionary new];

    if (statusCode == ODAV_HTTP_MULTI_STATUS && _errorData) {
        // Nil if we can't parse out a status code from the multistatus response. We'll still have a wrapping ODAV_HTTP_MULTI_STATUS error.
        NSError *underlyingError = [self _generateErrorFromMultiStatus];
        if (underlyingError)
            info[NSUnderlyingErrorKey] = underlyingError;
    }
    
    info[NSLocalizedDescriptionKey] = NSLocalizedStringFromTableInBundle(@"Unable to perform WebDAV operation.", @"OmniDAV", OMNI_BUNDLE, @"error description");
    info[NSLocalizedRecoverySuggestionErrorKey] = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The %@ server returned \"%@\" (%ld) in response to a request to \"%@ %@\".", @"OmniDAV", OMNI_BUNDLE, @"error reason"), [[_request URL] host], [self _localizedStringForStatusCode:statusCode], statusCode, [_request HTTPMethod], [[_request URL] path]];
    
    // We should always have a response and request when generating the error.
    // There is at least one case in the field where this is not true, and we are aborting due to an unhandled exception trying to stuff nil into the error dictionary. (See <bug:///84169> (Crash (unhandled exception) writing ICS file to sync server))
    // Assert that we have a response and request, but handle that error condition gracefully.
    
    OBASSERT(_response != nil);
    if (_response != nil) {
        [info setObject:[_response URL] forKey:NSURLErrorFailingURLErrorKey];
    } else {
        NSLog(@"_response is nil in %s", __func__);
    }
    
    OBASSERT(_request != nil);
    if (_request != nil) {
        [info setObject:[_request allHTTPHeaderFields] forKey:@"headers"];
        [info setObject:[_request HTTPMethod] forKey:@"method"];
    } else {
        NSLog(@"_request is nil in %s", __func__);
    }

    // We don't make use of this yet (and may not ever), but it is handy for debugging
    NSString *locationHeader = [[_response allHeaderFields] objectForKey:@"Location"];
    if (locationHeader) {
        [info setObject:locationHeader forKey:ODAVResponseLocationErrorKey];
    }
    NSArray <ODAVRedirect *> *preFailureRedirects = self.redirects;
    if (preFailureRedirects && preFailureRedirects.count)
        [info setObject:preFailureRedirects forKey:ODAVPreviousRedirectsErrorKey];
    
    // Add the error content.  Need to obey the charset specified in the Content-Type header.  And the content type.
    if (_errorData != nil) {
        [info setObject:_errorData forKey:@"errorData"];
        
        NSString *contentType = [[_response allHeaderFields] objectForKey:ODAVContentTypeHeader];
        do {
            if (![contentType isKindOfClass:[NSString class]]) {
                NSLog(@"Error %@ not a string", ODAVContentTypeHeader);
                break;
            }
            
            // Record the Content-Type
            [info setObject:contentType forKey:ODAVHTTPErrorDataContentTypeKey];
            OFMultiValueDictionary *parameters = [[OFMultiValueDictionary alloc] init];
            [[self class] _parseContentTypeHeaderValue:contentType intoDictionary:parameters valueChars:nil];
            NSString *encodingName = [parameters firstObjectForKey:@"charset"];
            CFStringEncoding encoding = kCFStringEncodingInvalidId;
            if (encodingName != nil)
                encoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)encodingName);
            if (encoding == kCFStringEncodingInvalidId)
                encoding = kCFStringEncodingWindowsLatin1; // Better a mangled error than no error at all!
            
            CFStringRef str = CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)_errorData, encoding);
            if (!str) {
                // The specified encoding didn't work, let's try Windows Latin 1
                str = CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)_errorData, kCFStringEncodingWindowsLatin1);
                if (!str) {
                    NSLog(@"Error content cannot be turned into string using encoding '%@' (%ld)", encodingName, (long)encoding);
                    [info setObject:_errorData forKey:ODAVHTTPErrorDataKey];
                    break;
                }
            }
            
            [info setObject:(__bridge id)str forKey:ODAVHTTPErrorStringKey];
            CFRelease(str);
        } while (0);
    }
    
    NSError *davError = [NSError errorWithDomain:ODAVHTTPErrorDomain code:statusCode userInfo:info];
    return [self prettyErrorForDAVError:davError];
}

- (void)_logError:(NSError *)error;
{
    if (ODAVConnectionDebug > 0) {
        if (ODAVConnectionDebug > 1)
            // full details
            NSLog(@"%@: did fail with error: %@", [self shortDescription], [error toPropertyList]);
        else
            // brief note
            NSLog(@"%@: did fail with error: %ld %@", [self shortDescription], error.code, [error localizedDescription]);
    }
}

- (void)_finish;
{
    OBPRECONDITION(!_finished);
    
    if (_shouldCollectDetailsForError) {
        // If we've already recorded a cancellation error in _error, don't overwrite that. In that case, include the detailed error response as the underlying error.
        if (_error != nil && ([_error hasUnderlyingErrorDomain:NSURLErrorDomain code:NSURLErrorUserCancelledAuthentication] || ([_error hasUnderlyingErrorDomain:NSURLErrorDomain code:NSURLErrorCancelled] && _authChallengeCancelled))) {
            NSDictionary *userInfo = @{NSUnderlyingErrorKey: [self _generateErrorForResponse]};
            _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:userInfo];
        } else {
            _error = [self _generateErrorForResponse];
        }
    }
    
    if (_error != nil) {
        [self _logError:_error];
    } else {
        DEBUG_DAV(3, @"%@: did finish", [self shortDescription]);
    }
    
    // Do this before calling the 'did finish' hook so that we are marked as finished when the target (possibly) calls our -resultData.
    _finished = YES;
    
    // Clear all our block pointers to help avoid retain cycles, now that we are done and need to go away.
    typeof(_didFinish) didFinish = _didFinish;
    _didFinish = nil;
    _didReceiveBytes = nil;
    _didReceiveData = nil;
    _didSendBytes = nil;
        
    PERFORM_CALLBACK(didFinish, self, _error);
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"%@ %@", [_request HTTPMethod], [[_request URL] absoluteString]];
}

@end

@interface ODAVRedirect ()
@property(nonatomic,copy) NSURL *from;
@property(nonatomic,copy) NSURL *to;
@property(nonatomic,copy) NSString *type;

@property(nonatomic,copy) NSString *cacheControl;
@property(nonatomic,copy) NSString *expires;
@end

@implementation ODAVRedirect

static NSURL *_tryRedirect(Class self, NSString *urlString, NSURL *from, NSURL *to)
{
    NSString *fromString = [from absoluteString];
    
    if ([fromString hasSuffix:@"/"] == NO)
        return nil; // Not doing redirects on files themselves, but the container. Don't want to assume that if "/a/b" got redirected to "/c/b" that everything in "/a" is redirected to "/c".
    
    if (![urlString hasPrefix:fromString])
        return nil;
    
    NSString *redirectedURLString = [[to absoluteString] stringByAppendingString:[urlString substringFromIndex:[fromString length]]];
    DEBUG_DAV(2, @"using it yields %@", redirectedURLString);
    
    NSURL *redirectedURL = [NSURL URLWithString:redirectedURLString];
    if (!redirectedURL) {
        NSLog(@"Attempting to redirect from %@ with redirect %@ -> %@ produced invalid URL string %@", urlString, from, to, redirectedURLString);
        return nil;
    }
    
    return redirectedURL;
}

static BOOL _emptyPath(NSURL *url)
{
    NSString *path = [url path];
    
    return [path isEqual:@"/"] || [NSString isEmptyString:path];
}

+ (NSURL *)suggestAlternateURLForURL:(NSURL *)url withRedirects:(NSArray *)redirects;
{
    NSString *urlString = [url absoluteString];
    DEBUG_DAV(1, @"checking for redirects that apply to %@", urlString);
    
    for (ODAVRedirect *redirect in redirects) {
        DEBUG_DAV(2, @"checking %@", redirect);
        
        NSURL *from = redirect.from;
        NSURL *to = redirect.to;
        
        // If we have a/b and there is a redirect from a/b/c to a/d/c, infer the redirect was really from a/b to a/d
        do {
            if (_emptyPath(from) || _emptyPath(to))
                break;
            
            NSString *fromPathComponent = [from lastPathComponent];
            NSString *toPathComponent = [to lastPathComponent];
            DEBUG_DAV(2, @"from lastPathComponent %@", fromPathComponent);
            DEBUG_DAV(2, @"to lastPathComponent %@", toPathComponent);
            if ([toPathComponent isEqual:fromPathComponent] == NO)
                break;
            from = [from URLByDeletingLastPathComponent];
            to = [to URLByDeletingLastPathComponent];
        } while (YES);
        
        // If we have a/b/c and there is a redirect from a/b to a/d, this should give us a/d/c
        NSURL *redirectedURL = _tryRedirect(self, urlString, from, to);
        if (redirectedURL)
            return redirectedURL;
    }
    
    return nil;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    dict[@"from"] = _from;
    dict[@"to"] = _to;
    dict[@"type"] = _type;
    
    if (_cacheControl)
        dict[@"cacheControl"] = _cacheControl;
    if (_expires)
        dict[@"expires"] = _expires;
    
    return dict;
}

- (NSString *)description;
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@:%p %@ -> %@", NSStringFromClass([self class]), self, _from, _to];
    if (_cacheControl)
        [description appendFormat:@" cacheControl:%@", _cacheControl];
    if (_expires)
        [description appendFormat:@" expires:%@", _expires];
    [description appendString:@">"];
    return description;
}

@end

void ODAVAddRedirectEntry(NSMutableArray <ODAVRedirect *> *entries, NSString *type, NSURL *from, NSURL *to, NSDictionary *responseHeaders)
{
    OBPRECONDITION(entries != nil);
    OBPRECONDITION(type != nil);
    OBPRECONDITION(from != nil);
    OBPRECONDITION(to != nil);
    
    ODAVRedirect *redirect = [ODAVRedirect new];
    redirect.from = from;
    redirect.to = to;
    redirect.type = type;
    
#ifdef OMNI_ASSERTIONS_ON
    if ([entries count]) {
        // Our redirect chain should be continuous --- actually we'll cope fine if it isn't, but if there's some situation where it isn't, I'd like to know about it in case we rely on it in the future.
        ODAVRedirect *previousRedirect = [entries lastObject];
        OBASSERT([from isEqual:previousRedirect.to]);
    }
#endif
    
    if (responseHeaders) {
        __block BOOL haveCacheControl = NO;
        __block BOOL haveExpires = NO;
        
        /* For HTTP redirects, it can be useful to know whether the server expects us to cache the redirect; see RFC2616 [10.3.3] and [10.3.8]. We don't make direct use of this info but the application might. */
        [responseHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *header, NSString *value, BOOL *stop) {
            if (!haveCacheControl && [header caseInsensitiveCompare:@"Cache-Control"] == NSOrderedSame) {
                haveCacheControl = YES;
                redirect.cacheControl = value;
            } else if (!haveExpires && [header caseInsensitiveCompare:@"Expires"] == NSOrderedSame) {
                haveExpires = YES;
                redirect.expires = value;
            }
        }];
    }
    
    [entries addObject:redirect];
}

/*
 Handles the Content-Range header in the specific case that it is a byte-content-range:
 
 Content-Range = byte-content-range / other-content-range
 
 byte-content-range = "bytes" SP ( byte-range-resp / unsatisfied-range )

 byte-range-resp = first-byte-pos "-" last-byte-pos "/" ( complete-length / "*" )
 unsatisfied-range = "*" "/" complete-length

 first-byte-pos, last-byte-pos, complete-length = 1*DIGIT
*/
BOOL ODAVParseContentRangeBytes(NSString *contentRange, unsigned long long *outFirstByte, unsigned long long *outLastByte, unsigned long long *outTotalLength)
{
    if (!contentRange)
        return NO;
    
    NSScanner *scan = [NSScanner scannerWithString:contentRange];
    scan.charactersToBeSkipped = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    
    if (![scan scanString:@"bytes" intoString:NULL])
        return NO;
    
    if ([scan scanString:@"*" intoString:NULL]) {
        // unsatisfied-range
    } else {
        if (![scan scanUnsignedLongLong:outFirstByte] ||
            ![scan scanString:@"-" intoString:NULL] ||
            ![scan scanUnsignedLongLong:outLastByte])
            return NO;
    }
    
    if (![scan scanString:@"/" intoString:NULL])
        return NO;
    
    if ([scan scanString:@"*" intoString:NULL]) {
        // unspecified complete-length
    } else if ([scan scanUnsignedLongLong:outTotalLength]) {
        // specified complete-length
    } else {
        return NO;
    }

    return YES;
}
