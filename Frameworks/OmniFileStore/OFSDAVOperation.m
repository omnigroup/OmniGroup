// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDAVOperation.h>

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLString.h>
#import <Security/SecTrust.h>

RCS_ID("$Id$");

// Methods from the removed protocol OFSFileManagerAsynchronousOperationTarget.
OBDEPRECATED_METHOD(-fileManager:operationDidFinish:withError:);
OBDEPRECATED_METHOD(-fileManager:operation:didReceiveData:);
OBDEPRECATED_METHOD(-fileManager:operation:didReceiveBytes:);
OBDEPRECATED_METHOD(-fileManager:operation:didSendBytes:);
OBDEPRECATED_METHOD(-fileManager:operation:didProcessBytes:);

@implementation OFSDAVOperation
{
    NSURLRequest *_request;
    NSURLConnection *_connection;
    
    // For PUT operations
    long long _bodyBytesSent;
    long long _expectedBytesToWrite;
    
    // Mostly for GET operations, though _response gets used at the end of a PUT or during an auth challenge.
    NSHTTPURLResponse *_response;
    NSMutableData *_resultData;
    NSUInteger _bytesReceived;
    
    BOOL _finished;
    BOOL _shouldCollectDetailsForError;
    NSMutableData *_errorData;
    NSError *_error;
    NSMutableArray *_redirects;
}

static BOOL _isRead(OFSDAVOperation *self)
{
    NSString *method = [self->_request HTTPMethod];
    
    // We assert it is uppercase in the initializer.
    if ([method isEqualToString:@"GET"] || [method isEqualToString:@"PROPFIND"] || [method isEqualToString:@"LOCK"])
        return YES;
    
    OBASSERT([method isEqualToString:@"PUT"] ||
             [method isEqualToString:@"MKCOL"] ||
             [method isEqualToString:@"DELETE"] ||
             [method isEqualToString:@"MOVE"] ||
             [method isEqualToString:@"COPY"] ||
             [method isEqualToString:@"UNLOCK"]); // The delegate doesn't need to read any data from these operations
    
    return NO;
}

- initWithRequest:(NSURLRequest *)request;
{
    OBPRECONDITION([[[request URL] scheme] isEqualToString:@"http"] || [[[request URL] scheme] isEqualToString:@"https"]); // We want a NSHTTPURLResponse
    OBPRECONDITION([[request HTTPMethod] isEqualToString:[[request HTTPMethod] uppercaseString]]);
    
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
    
    return self;
}

- (void)dealloc;
{
    if (!_finished) {
        if (OFSFileManagerDebug > 3)
            NSLog(@"%@: cancelling request in -dealloc", OBShortObjectDescription(self));
        [_connection cancel];
    }
}

- (NSError *)prettyErrorForDAVError:(NSError *)davError;
{
    // Pretty up some errors, wrapping them in another DAV error rather than making our own.  Just put prettier strings on them.
    NSInteger code = [davError code];
    
    // me.com returns 402 Payment Required if you mistype your user name.  402 is currently reserved and Apple shouldn't be using it at all; Radar 6253979
    // 409 Conflict -- we can get this if the user mistypes the directory or forgets to create it.  There might be other cases, but this is by far the most likely.
    if (code == OFS_HTTP_UNAUTHORIZED || code == OFS_HTTP_PAYMENT_REQUIRED || code == OFS_HTTP_CONFLICT) {
        NSString *location = [[_request URL] absoluteString];
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not access the WebDAV location <%@>.", @"OmniFileStore", OMNI_BUNDLE, @"error description"),
                                 location];
        NSString *reason;
        switch (code) {
            case 401:
                reason = NSLocalizedStringFromTableInBundle(@"Please check that the user name and password you provided are correct.", @"OmniFileStore", OMNI_BUNDLE, @"error suggestion");
                break;
            case 402:
                reason = NSLocalizedStringFromTableInBundle(@"Please make sure that the account information is correct.", @"OmniFileStore", OMNI_BUNDLE, @"error reason");
                break;
            default:
            case 409:
                reason = NSLocalizedStringFromTableInBundle(@"Please make sure that the destination folder exists.", @"OmniFileStore", OMNI_BUNDLE, @"error reason");
                break;
        }
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedRecoverySuggestionErrorKey, nil];
        [info setObject:davError forKey:NSUnderlyingErrorKey];
        
        return [NSError errorWithDomain:OFSDAVHTTPErrorDomain code:code userInfo:info];
    }
    
    return davError;
}

static OFCharacterSet *_tokenDelimiterOFCharacterSet(void)
{
    static OFCharacterSet *TokenDelimiterSet = nil;
    if (TokenDelimiterSet == nil) {
        // This definition of a Content-Type header token's delimiters is from the MIME standard, RFC 1521: http://www.oac.uci.edu/indiv/ehood/MIME/1521/04_Content-Type.html
        OFCharacterSet *newSet = [[OFCharacterSet alloc] initWithString:@"()<>@,;:\\\"/[]?="]; 
        [newSet addCharacter:' '];
        [newSet addCharactersFromCharacterSet:[NSCharacterSet controlCharacterSet]];

        // This is not part of the MIME standard, but we don't really need to treat "/" in any special way for this implementation
        [newSet removeCharacter:'/'];

        TokenDelimiterSet = newSet;
    }
    OBPOSTCONDITION(TokenDelimiterSet != nil);
    return TokenDelimiterSet;
}

static OFCharacterSet *_quotedStringDelimiterOFCharacterSet(void)
{
    static OFCharacterSet *QuotedStringDelimiterSet = nil;
    if (QuotedStringDelimiterSet == nil)
        QuotedStringDelimiterSet = [[OFCharacterSet alloc] initWithString:@"\"\\"];
    OBPOSTCONDITION(QuotedStringDelimiterSet != nil);
    return QuotedStringDelimiterSet;
}

+ (NSString *)_parseContentTypeHeaderValue:(NSString *)aString intoDictionary:(OFMultiValueDictionary *)parameters valueChars:(NSCharacterSet *)validValues;
{
    OFCharacterSet *whitespaceSet = [OFCharacterSet whitespaceOFCharacterSet];
    OFCharacterSet *tokenDelimiterSet = _tokenDelimiterOFCharacterSet();
    OFCharacterSet *quotedStringDelimiterSet = _quotedStringDelimiterOFCharacterSet();

    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:aString];
    scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
    NSString *bareHeader = [scanner readFullTokenWithDelimiterOFCharacterSet:tokenDelimiterSet forceLowercase:YES]; // Base mime types are case-insensitive
    scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
    while (scannerPeekCharacter(scanner) == ';') {
        scannerSkipPeekedCharacter(scanner); // Skip ';'
        scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
        NSString *attribute = [scanner readFullTokenWithDelimiterOFCharacterSet:tokenDelimiterSet forceLowercase:YES]; // Attribute names are case-insensitive
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
                NSString *partialValue = [scanner readFullTokenWithDelimiterOFCharacterSet:quotedStringDelimiterSet forceLowercase:NO];
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
            NSString *value = [scanner readFullTokenWithDelimiterOFCharacterSet:tokenDelimiterSet forceLowercase:NO];
            [parameters addObject:value forKey:attribute];
        }
        scannerScanUpToCharacterNotInOFCharacterSet(scanner, whitespaceSet); // Ignore whitespace
    }
    return bareHeader;
}

- (NSString *)valueForResponseHeader:(NSString *)header;
{
    OBPRECONDITION(_response);
    return [_response allHeaderFields][header];
}

#pragma mark - OFSAsynchronousOperation

@synthesize didFinish = _didFinish;
@synthesize didReceiveData = _didReceiveData;
@synthesize didReceiveBytes = _didReceiveBytes;
@synthesize didSendBytes = _didSendBytes;

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

- (void)startOperationOnQueue:(NSOperationQueue *)queue;
{
    OBPRECONDITION(_didFinish); // What is the purpose of an async operation that we don't track the end of?
    OBPRECONDITION(_connection == nil);
    OBPRECONDITION(_response == nil);
    OBPRECONDITION(_findCredentialsForChallenge);
    
    // We cannot use the newer NSOperationQueue based API here in all cases. In particular, if we are invoked on a background operation queue with a maximum concurrent operation count of one, then when -run: is called, it will block and will prevent dispatched delegate methods from firing (and will thus self-deadlock). We instead use the NSRunLoop API, which is OK since we always call -startOperation and -run:  on the same thread (so the current run loop can't be recycled when an operation queue worker thread dies and discard the schedling of our connection).

    // In the async version of the OFSFileManager API, the caller might be on a background queue serviced by a temporary thread. In this case, if the caller doesn't either specify a queue or run the runloop (preventing the calling thread from exiting) then the calling thread might exit and the delegate callbacks will silently not be called.
    if (queue) {
        if (OFSFileManagerDebug > 3)
            NSLog(@"%@: starting connection (on queue %@)", [self shortDescription], queue);
        _connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self startImmediately:NO];
        [_connection setDelegateQueue:queue];
        [_connection start];
    } else {
        if (OFSFileManagerDebug > 3)
            NSLog(@"%@: starting connection (on current runloop)", [self shortDescription]);
        _connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self startImmediately:YES];
    }
}

- (void)stopOperation;
{
    if (OFSFileManagerDebug > 3)
        NSLog(@"%@: cancelling request", [self shortDescription]);
    [_connection cancel];
    _connection = nil;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
{
    OBPRECONDITION(!_finished);
    OBPRECONDITION(_error == nil);
    
    [self _logError:error];
    
    _error = [error copy];
    
    [self _finish];
}

#if 0 // As far as I can tell, this never gets called (maybe since we implement -connection:willSendRequestForAuthenticationChallenge:.
- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection;
{
    OFSFileManager *fileManager = _weak_fileManager;
    OBASSERT(fileManager, "File manager deallocated before operations finished");
    
    id <OFSFileManagerDelegate> delegate = fileManager.delegate;
    if ([delegate respondsToSelector:@selector(fileManagerShouldUseCredentialStorage:)])
        return [delegate fileManagerShouldUseCredentialStorage:fileManager];
    else
        return YES;
}
#endif

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: will send request for authentication challenge %@", [self shortDescription], challenge);
    
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    NSString *challengeMethod = [protectionSpace authenticationMethod];
    if (OFSFileManagerDebug > 2) {
        NSLog(@"protection space %@ realm:%@ secure:%d proxy:%d host:%@ port:%ld proxyType:%@ protocol:%@ method:%@",
              protectionSpace,
              [protectionSpace realm],
              [protectionSpace receivesCredentialSecurely],
              [protectionSpace isProxy],
              [protectionSpace host],
              [protectionSpace port],
              [protectionSpace proxyType],
              [protectionSpace protocol],
              [protectionSpace authenticationMethod]);
        
        NSLog(@"proposed credential %@", [challenge proposedCredential]);
        NSLog(@"previous failure count %ld", [challenge previousFailureCount]);
        NSLog(@"failure response %@", [challenge failureResponse]);
        NSLog(@"error %@", [[challenge error] toPropertyList]);
    }
    
    // The +[NSURLCredentialStorage sharedCredentialStorage] doesn't have the .Mac password it in, sadly.
    //    NSURLCredentialStorage *storage = [NSURLCredentialStorage sharedCredentialStorage];
    //    NSLog(@"all credentials = %@", [storage allCredentials]);
    
    NSURLCredential *credential = nil;
    
    if ([challengeMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {        
        SecTrustRef trustRef;
        if ((trustRef = [protectionSpace serverTrust]) != NULL) {
            SecTrustResultType evaluationResult = kSecTrustResultOtherError;
            OSStatus oserr = SecTrustEvaluate(trustRef, &evaluationResult); // NB: May block for long periods (eg OCSP verification, etc)
            if (OFSFileManagerDebug > 2) {
                NSString *result; // TODO: Use OFSummarizeTrustResult() instead.
                if (oserr != noErr) {
                    result = [NSString stringWithFormat:@"error %ld", (long)oserr];
                } else {
                    result = [NSString stringWithFormat:@"condition %d", (int)evaluationResult];
                }
                NSLog(@"%@: SecTrustEvaluate returns %@", [self shortDescription], result);
            }
            if (oserr == noErr && evaluationResult == kSecTrustResultRecoverableTrustFailure) {
                // The situation we're interested in is "recoverable failure": this indicates that the evaluation failed, but might succeed if we prod it a little.
                BOOL hasTrust = OFHasTrustForChallenge(challenge);
                if (!hasTrust) {
                    // Our caller may choose to pop up UI or it might choose to immediately mark the certificate as trusted.
                    if (_validateCertificateForChallenge)
                        _validateCertificateForChallenge(self, challenge);
                    hasTrust = OFHasTrustForChallenge(challenge);
                }

                if (hasTrust) {
                    credential = [NSURLCredential credentialForTrust:trustRef];
                    if (OFSFileManagerDebug > 2)
                        NSLog(@"credential = %@", credential);
                    [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                    return;
                } else {
                    // The delegate didn't opt to immediately mark the certificate trusted. It is presumably giving up or prompting the user and will retry the operation later.
                    // We'd prefer to cancel here, but if we do, we deadlock (in the NSOperationQueue-based scheduling).
                    //[[challenge sender] cancelAuthenticationChallenge:challenge];
                    [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
                    return;
                }
            }
        }
        
        // If we "continue without credential", NSURLConnection will consult certificate trust roots and per-cert trust overrides in the normal way. If we cancel the "challenge", NSURLConnection will drop the connection, even if it would have succeeded without our meddling (that is, we can force failure as well as forcing success).
        
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
        return;
    }

    if (_findCredentialsForChallenge)
        credential = _findCredentialsForChallenge(self, challenge);
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"credential = %@", credential);
    
    if (credential) {
        [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
    } else {
        // Keep around the response that says something about the failure, and set the flag indicating we want details recorded for this error
        OBASSERT(_response == nil);
        _response = [[challenge failureResponse] copy];
        _shouldCollectDetailsForError = YES;
        
        // We'd prefer to cancel here, but if we do, we deadlock (in the NSOperationQueue-based scheduling).
        //[[challenge sender] cancelAuthenticationChallenge:challenge];
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

#pragma mark - NSURLConnectionDataDelegate

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse;
{
    if (OFSFileManagerDebug > 2) {
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
        } else if ([method isEqualToString:@"MOVE"]) {
            // MOVE is a bit dubious. If the source URL gets rewritten by the server, do we know that the destination URL we're sending is still what it should be?
            // In theory, since we just use MOVE to implement atomic writes, we shouldn't get redirects on MOVE, as long as we paid attention to the response to the PUT or MKCOL request used to create the resource we're MOVEing.
            // Exception: When replacing a remote database with the local version, if the user-entered URL incurs a redirect (e.g. http->https), we will still get a redirect on MOVE when moving the old database aside before replacing it with the new one.  TODO: Figure out how to avoid this.
            // OBASSERT_NOT_REACHED("In theory, we shouldn't get redirected on MOVE?");

            // Try to rewrite the destination URL analogously to the source URL.
            NSString *rewrote = OFSURLAnalogousRewrite([_request URL], [_request valueForHTTPHeaderField:@"Destination"], [request URL]);
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
            OFSAddRedirectEntry(_redirects,
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

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    OBPRECONDITION(_response == nil);
    
    _response = nil;
    
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
    
    if (OFSFileManagerDebug > 2) {
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
            OFSAddRedirectEntry(_redirects, kOFSRedirectContentLocation, [_response URL], [NSURL URLWithString:location relativeToURL:[_response URL]], responseHeaders);
        }
    }

    OBASSERT(statusCode < 300 || statusCode > 399); // shouldn't have been left with a redirection.
    OBASSERT(statusCode > 199);   // NSURLConnection should handle 100-Continue.
    if (statusCode >= 300) {
        /* We treat 3xx codes as errors here (in addition to the 4xx and 5xx codes) because any redirection should have been handled at a lower level, by NSURLConnection. If we do end up with a 3xx response, we can't treat it as a success anyway, because the response body of a 3xx is not the entity we requested --- it's usually a little server-generated HTML snippet saying "click here if the redirect didn't work". */
        _shouldCollectDetailsForError = YES;
    }
    if (statusCode == OFS_HTTP_MULTI_STATUS && ![[_request HTTPMethod] isEqual:@"PROPFIND"]) {
        // PROPFIND is supposed to return OFS_HTTP_MULTI_STATUS, but if we get it for COPY/DELETE/MOVE, then it is an error
        // The response will be a DAV multistatus that we will turn into an error.
        _shouldCollectDetailsForError = YES;
    } else {
        OBASSERT(_isRead(self) ||
                 statusCode == OFS_HTTP_CREATED ||
                 statusCode == OFS_HTTP_NO_CONTENT ||
                 statusCode >= 400 /* Some sort of error (e.g. missing file or permission denied) */);
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    OBPRECONDITION(_response);
    OBPRECONDITION([_response statusCode] != OFS_HTTP_NO_CONTENT);
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did receive data of length %ld", [self shortDescription], [data length]);
    
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
        _didReceiveData(self, data);
    else {
        if (_didReceiveBytes)
            _didReceiveBytes(self, [data length]);
        
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

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;
{
    OBPRECONDITION(_response == nil);
    OBPRECONDITION(bytesWritten >= 0);
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did send data of length %ld (total %ld, expected %ld)", [self shortDescription], bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    
    _bodyBytesSent += bytesWritten;
    _expectedBytesToWrite = totalBytesExpectedToWrite; // See our initializer for details on this ivar's purpose.

    OBASSERT(bytesWritten <= totalBytesWritten);
    OBASSERT(totalBytesWritten <= totalBytesExpectedToWrite);

    if (_didSendBytes)
        _didSendBytes(self, bytesWritten);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
#ifdef OMNI_ASSERTIONS_ON
    long long expectedContentLength = [_response expectedContentLength];
#endif
    OBPRECONDITION(expectedContentLength >= 0 || expectedContentLength == NSURLResponseUnknownLength);
#ifdef OMNI_ASSERTIONS_ON
    if (_didReceiveData == nil)
        OBPRECONDITION(_bytesReceived == [_resultData length]); // We don't buffer the data if we are passing it out to a block.
    OBPRECONDITION(expectedContentLength == NSURLResponseUnknownLength || _bytesReceived <= (unsigned long long)expectedContentLength); // should have gotten all the content if we are to be considered successfully finised

#endif
    [self _finish];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse;
{
    if (OFSFileManagerDebug > 1)
        NSLog(@"%@: will cache response %@", [self shortDescription], cachedResponse);
    return nil; // Don't cache DAV stuff if asked to.
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
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

    return [NSError errorWithDomain:OFSDAVHTTPErrorDomain code:statusCode userInfo:nil];
}

- (NSString *)_localizedStringForStatusCode:(NSInteger)statusCode;
{
    switch (statusCode) {
        case OFS_HTTP_INSUFFICIENT_STORAGE:
            return NSLocalizedStringFromTableInBundle(@"insufficient storage", @"OmniFileStore", OMNI_BUNDLE, @"Text for HTTP error code 507 (insufficient storage)"); // We can do better than "server error", which is what +[NSHTTPURLResponse localizedStringForStatusCode:] returns
        default:
            return [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
    }
}

- (NSError *)_generateErrorForResponse;
{
    NSInteger statusCode = [_response statusCode];
    
    NSMutableDictionary *info = [NSMutableDictionary new];

    if (statusCode == OFS_HTTP_MULTI_STATUS && _errorData) {
        // Nil if we can't parse out a status code from the multistatus response. We'll still have a wrapping OFS_HTTP_MULTI_STATUS error.
        NSError *underlyingError = [self _generateErrorFromMultiStatus];
        if (underlyingError)
            info[NSUnderlyingErrorKey] = underlyingError;
    }
    
    info[NSLocalizedDescriptionKey] = NSLocalizedStringFromTableInBundle(@"Unable to perform WebDAV operation.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
    info[NSLocalizedRecoverySuggestionErrorKey] = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The %@ server returned \"%@\" (%d) in response to a request to \"%@ %@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [[_request URL] host], [self _localizedStringForStatusCode:statusCode], statusCode, [_request HTTPMethod], [[_request URL] path]];
    
    // We should always have a response and request when generating the error.
    // There is at least one case in the field where this is not true, and we are aborting due to an unhandled exception trying to stuff nil into the error dictionary. (See <bug:///84169> (Crash (unhandled exception) writing ICS file to sync server))
    // Assert that we have a response and request, but handle that error condition gracefully.
    
    OBASSERT(_response != nil);
    if (_response != nil) {
        [info setObject:[_response URL] forKey:OFSURLErrorFailingURLErrorKey];
    } else {
        NSLog(@"_response is nil in %s", __func__);
    }
    
    OBASSERT(_request != nil);
    if (_request != nil) {
        [info setObject:[_request allHTTPHeaderFields] forKey:@"headers"];
    } else {
        NSLog(@"_request is nil in %s", __func__);
    }

    // We don't make use of this yet (and may not ever), but it is handy for debugging
    NSString *locationHeader = [[_response allHeaderFields] objectForKey:@"Location"];
    if (locationHeader) {
        [info setObject:locationHeader forKey:OFSResponseLocationErrorKey];
    }
    
    // Add the error content.  Need to obey the charset specified in the Content-Type header.  And the content type.
    if (_errorData != nil) {
        [info setObject:_errorData forKey:@"errorData"];
        
        NSString *contentType = [[_response allHeaderFields] objectForKey:@"Content-Type"];
        do {
            if (![contentType isKindOfClass:[NSString class]]) {
                NSLog(@"Error Content-Type not a string");
                break;
            }
            
            // Record the Content-Type
            [info setObject:contentType forKey:OFSDAVHTTPErrorDataContentTypeKey];
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
                    [info setObject:_errorData forKey:OFSDAVHTTPErrorDataKey];
                    break;
                }
            }
            
            [info setObject:(__bridge id)str forKey:OFSDAVHTTPErrorStringKey];
            CFRelease(str);
        } while (0);
    }
    
    NSError *davError = [NSError errorWithDomain:OFSDAVHTTPErrorDomain code:statusCode userInfo:info];
    return [self prettyErrorForDAVError:davError];
}

- (void)_logError:(NSError *)error;
{
    if (OFSFileManagerDebug > 0) {
        if (OFSFileManagerDebug > 1)
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
        _error = [self _generateErrorForResponse];
    }
    
    if (_error != nil) {
        [self _logError:_error];
    } else {
        if (OFSFileManagerDebug > 2)
            NSLog(@"%@: did finish", [self shortDescription]);
    }
    
    // Do this before calling the 'did finish' hook so that we are marked as finished when the target (possibly) calls our -resultData.
    _finished = YES;
    
    // Clear all our block pointers to help avoid retain cycles, now that we are done and need to go away.
    typeof(_didFinish) didFinish = _didFinish;
    _validateCertificateForChallenge = nil;
    _findCredentialsForChallenge = nil;
    _didFinish = nil;
    _didReceiveBytes = nil;
    _didReceiveData = nil;
    _didSendBytes = nil;
    
    if (didFinish)
        didFinish(self, _error);
}


#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"%@ %@", [_request HTTPMethod], [[_request URL] absoluteString]];
}

@end

void OFSAddRedirectEntry(NSMutableArray *entries, NSString *type, NSURL *from, NSURL *to, NSDictionary *responseHeaders)
{
    NSString *keys[5];
    id values[5];
    int keyCount;
    
    OBPRECONDITION(from != nil);
    OBPRECONDITION(to != nil);
    OBPRECONDITION(entries != nil);
    
    keys[0] = kOFSRedirectionType;
    values[0] = type;
    keys[1] = kOFSRedirectedTo;
    values[1] = to;
    keys[2] = kOFSRedirectedFrom;
    values[2] = from;
    keyCount = 3;
    
    if ([entries count]) {
        // Our redirect chain should be continuous --- actually we'll cope fine if it isn't, but if there's some situation where it isn't, I'd like to know about it in case we rely on it in the future.
        OBASSERT([from isEqual:[(NSDictionary *)[entries lastObject] objectForKey:kOFSRedirectedTo]]);
    }
    
    if (responseHeaders) {
        BOOL haveCacheControl = NO;
        BOOL haveExpires = NO;
        
        /* For HTTP redirects, it can be useful to know whether the server expects us to cache the redirect; see RFC2616 [10.3.3] and [10.3.8]. We don't make direct use of this info but the application might. */
        OFForEachObject([responseHeaders keyEnumerator], NSString *, header) {
            if (!haveCacheControl && [header caseInsensitiveCompare:@"Cache-Control"] == NSOrderedSame) {
                haveCacheControl = YES;
                keys[keyCount] = @"Cache-Control";
                values[keyCount] = [responseHeaders objectForKey:header];
                keyCount ++;
            } else if (!haveExpires && [header caseInsensitiveCompare:@"Expires"] == NSOrderedSame) {
                haveExpires = YES;
                keys[keyCount] = @"Expires";
                values[keyCount] = [responseHeaders objectForKey:header];
                keyCount ++;
            }
        }
    }
    
    [entries addObject:[NSDictionary dictionaryWithObjects:values forKeys:keys count:keyCount]];
}

