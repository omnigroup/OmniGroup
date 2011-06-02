// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSDAVOperation.h"

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/Errors.h>
#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFPreference.h>
#import <Security/SecTrust.h>

RCS_ID("$Id$");

@implementation OFSDAVOperation

static BOOL _isRead(OFSDAVOperation *self)
{
    NSString *method = [self->_request HTTPMethod];
    
    // We assert it is uppercase in the initializer.
    if ([method isEqualToString:@"GET"] || [method isEqualToString:@"PROPFIND"])
        return YES;
    
    OBASSERT([method isEqualToString:@"PUT"] || [method isEqualToString:@"MKCOL"] || [method isEqualToString:@"DELETE"] || [method isEqualToString:@"MOVE"]); // The delegate doesn't need to read any data from these operations
    
    return NO;
}

- initWithFileManager:(OFSDAVFileManager *)fileManager request:(NSURLRequest *)request target:(id <OFSFileManagerAsynchronousOperationTarget>)target;
{
    OBPRECONDITION([[[request URL] scheme] isEqualToString:@"http"] || [[[request URL] scheme] isEqualToString:@"https"]); // We want a NSHTTPURLResponse
    OBPRECONDITION([[request HTTPMethod] isEqualToString:[[request HTTPMethod] uppercaseString]]);
    
    if (!(self = [super init]))
        return nil;

    _nonretained_fileManager = fileManager;
    _request = [request copy];
    _target = [target retain];
    _redirections = [[NSMutableArray alloc] init];
    
    // For write operations, we have to record the expected length here AND in the NSURLConnection callback. The issue is that for https PUT operations, we can get an authorization challenge after we've uploaded the entire body, at which point we'll have to start all over. NSURLConnection keeps the # bytes increasing and doubles the expected bytes to write at this point (which is more accurate than going back to zero bytes, by some measure).
    if (!_isRead(self)) {
        NSData *body = [request HTTPBody];
        // OBASSERT(body); // We don't support streams, but we might be performing an operation which doesn't involve data (e.g. removing a file)
        
        _expectedBytesToWrite = [body length];
        
        // Must implement the byte-based option
        OBASSERT(_target == nil || [_target respondsToSelector:@selector(fileManager:operation:didProcessBytes:)]);
            
    } else {
        // Must implement one of the reading options
        if ([_target respondsToSelector:@selector(fileManager:operation:didReceiveData:)])
            _targetWantsData = YES;
        else {
            OBASSERT(_target == nil || [_target respondsToSelector:@selector(fileManager:operation:didReceiveData:)] || [_target respondsToSelector:@selector(fileManager:operation:didProcessBytes:)]);
        }
    }
    
    return self;
}

- (void)dealloc;
{
    _nonretained_fileManager = nil;
    if (!_finished)
        [_connection cancel];
    [_connection release];
    [_request release];
    [_response release];
    [_resultData release];
    [_error release];
    [_target release];
    [_redirections release];
    [super dealloc];
}

- (NSError *)prettyErrorForDAVError:(NSError *)davError;
{
    // Pretty up some errors, wrapping them in another DAV error rather than making our own.  Just put prettier strings on them.
    NSInteger code = [davError code];
    
    // me.com returns 402 Payment Required if you mistype your user name.  402 is currently reserved and Apple shouldn't be using it at all; Radar 6253979
    // 409 Conflict -- we can get this if the user mistypes the directory or forgets to create it.  There might be other cases, but this is by far the most likely.
    if (code == 402 || code == 409) {
        NSString *location = [[_request URL] absoluteString];
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not access the WebDAV location <%@>.", @"OmniFileStore", OMNI_BUNDLE, @"error description"),
                                 location];
        NSString *reason;
        switch (code) {
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
    [scanner release];
    return bareHeader;
}

- (NSData *)run:(NSError **)outError;
{
    // Start the NSURLConnection and then wait for it to finish.
    [self startOperation];
    
    while (!_finished && !_error) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        [pool release];
    }
    
    if (OFSFileManagerDebug > 1) {
        NSLog(@"%@: redirections = %@", [self shortDescription], [_redirections description]);
    }
    
    // Try to upgrade the response to an error if we didn't get an error in the actual attempt but rather received error content from the server.
    OBASSERT(_response || _error); // Only nil if we got back something other than an http response
    if (_response && !_error) {
        NSInteger code = [_response statusCode];
        OBASSERT(code < 300 || code > 399); // shouldn't have been left with a redirection.
        OBASSERT(code > 199);   // NSURLConnection should handle 100-Continue.
        if (code >= 300) {
            /* We treat 3xx codes as errors here (in addition to the 4xx and 5xx codes) because any redirection should have been handled at a lower level, by NSURLConnection. If we do end up with a 3xx response, we can't treat it as a success anyway, because the response body of a 3xx is not the entity we requested --- it's usually a little server-generated HTML snippet saying "click here if the redirect didn't work". */
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to perform WebDAV operation.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The %@ server returned \"%@\" (%d) in response to a request to \"%@ %@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [[_request URL] host], [NSHTTPURLResponse localizedStringForStatusCode:code], code, [_request HTTPMethod], [[_request URL] path]];
            NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedRecoverySuggestionErrorKey, nil];
            
            [info setObject:[_response URL] forKey:OFSURLErrorFailingURLErrorKey];
            
            /* We don't make use of this yet (and may not ever), but it is handy for debugging */ 
            NSString *locationHeader = [[_response allHeaderFields] objectForKey:@"Location"];
            if (locationHeader) {
                [info setObject:locationHeader forKey:OFSResponseLocationErrorKey];
            }
            
#ifdef DEBUG_wiml
            NSLog(@"%@ - err = %@", [self shortDescription], [info description]);
#endif            
            // Add the error content.  Need to obey the charset specified in the Content-Type header.  And the content type.
            if (_resultData) {
                [info setObject:_resultData forKey:@"errorData"];
                
                NSString *contentType = [[_response allHeaderFields] objectForKey:@"Content-Type"];
                do {
                    if (![contentType isKindOfClass:[NSString class]]) {
                        NSLog(@"Error Content-Type not a string");
                        break;
                    }
                    
                    // Record the Content-Type
                    [info setObject:contentType forKey:@"errorDataContentType"];
                    OFMultiValueDictionary *parameters = [[[OFMultiValueDictionary alloc] init] autorelease];
                    [[self class] _parseContentTypeHeaderValue:contentType intoDictionary:parameters valueChars:nil];
                    NSString *encodingName = [parameters firstObjectForKey:@"charset"];
                    CFStringEncoding encoding = kCFStringEncodingInvalidId;
                    if (encodingName != nil)
                        encoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)encodingName);
                    if (encoding == kCFStringEncodingInvalidId)
                        encoding = kCFStringEncodingWindowsLatin1; // Better a mangled error than no error at all!
                    
                    CFStringRef str = CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)_resultData, encoding);
                    if (!str) {
                        // The specified encoding didn't work, let's try Windows Latin 1
                        str = CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)_resultData, kCFStringEncodingWindowsLatin1);
                        if (!str) {
                            NSLog(@"Error content cannot be turned into string using encoding '%@' (%ld)", encodingName, (long)encoding);
                            [info setObject:_resultData forKey:@"errorData"];
                            break;
                        }
                    }
                    
                    [info setObject:(id)str forKey:@"errorString"];
                    CFRelease(str);
                } while (0);
            }
            
            NSError *davError = [NSError errorWithDomain:OFSDAVHTTPErrorDomain code:code userInfo:info];            
            _error = [[self prettyErrorForDAVError:davError] retain];
        }
    }
    
    if (_error) {
        if (outError)
            *outError = _error;
        return nil;
    }
    
    return _resultData;
}

- (NSArray *)redirects
{
    return _redirections;
}

#pragma mark -
#pragma mark OFSAsynchronousOperation

- (NSURL *)url;
{
    return [_request URL];
}

- (long long)processedLength;
{
    // TODO: In general, we could have a POST that sends body data AND returns content. We don't for DAV support right now, but lets assert this is true.
    OBPRECONDITION([_resultData length] == 0 || _bodyBytesSent == 0);
    
    if (_isRead(self)) {
        if (_target)
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

- (void)startOperation;
{
    OBPRECONDITION(_connection == nil);
    OBPRECONDITION(_response == nil);
    _connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self]; // this starts the operation
}

- (void)stopOperation;
{
    [_connection cancel];
    [_connection release];
    _connection = nil;
}

#pragma mark -
#pragma mark NSURLConnection delegate

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
            NSMutableURLRequest *redirect = [[_request mutableCopy] autorelease];
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
                NSMutableURLRequest *redirect = [[_request mutableCopy] autorelease];
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
            
            NSMutableURLRequest *redirect = [[_request mutableCopy] autorelease];
            [redirect setURL:[request URL]];
            continuation = redirect;
        } else {
            OBASSERT_NOT_REACHED("Anything else get redirected that needs this treatment?");
            continuation = request;
        }
        
        if (continuation && redirectResponse) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)redirectResponse;
            OFSAddRedirectEntry(_redirections,
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

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace;
{
    // The purpose of this method, as far as I can tell, is simply to tell NSURLConnection whether our -connection:didReceiveAuthenticationChallenge: will totally choke and die on a given authentication method. We still have the ability to reject the challenge later.
    // If we return NO, the NSURLConnection will still try its usual fallbacks, like the keychain.
    
    BOOL result;
    
    NSString *authenticationMethod = [protectionSpace authenticationMethod];
    if ([authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate])
        result = NO;
    else if ([authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if (NSFoundationVersionNumber >= OFFoundationVersionNumber10_5)
            result = YES;
        else
            result = NO; // Shouldn't be reached, but who knows.
    } else {
        result = YES;
    }
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: canAuthenticateAgainstProtectionSpace %@  ->  %@", [self shortDescription], protectionSpace, result?@"YES":@"NO");

    return result;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did receive challenge %@", [self shortDescription], challenge);
    
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
        
        BOOL shouldAskDelegate = NO;
        
        SecTrustRef trustRef;
        if ((trustRef = [protectionSpace serverTrust]) != NULL) {
            
            // The SecTrust API exists on 10.4, just not the screwy "server trust" protection space.
            // On 10.4, we will instead get a call to the private method +[NSURLRequest setAllowsAnyHTTPSCertificate:forHost:], which OFSDAVFileManager provides an override for.
            OSStatus oserr;
            SecTrustResultType evaluationResult;
            
            evaluationResult = kSecTrustResultOtherError;
            oserr = SecTrustEvaluate(trustRef, &evaluationResult); // NB: May block for long periods (eg OCSP verification, etc)
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
                (void)shouldAskDelegate;
                
                // The situation we're interested in is "recoverable failure": this indicates that the evaluation failed, but might succeed if we prod it a little.
                // shouldAskDelegate = YES;
                // For now, we're just replicating the behavior of the old WebKit API: if a hostname is in OFSDAVFileManager's whitelist, we disable all certificate checks.

                NSString *trustedHost = [[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:OFSTrustedSyncHostPreference];
                if ([OFSDAVFileManager isTrustedHost:[protectionSpace host]] || [trustedHost isEqualToString:[protectionSpace host]]) {
                    credential = [[NSURLCredential class] performSelector:@selector(credentialForTrust:) withObject:(id)trustRef];
                    if (OFSFileManagerDebug > 2)
                        NSLog(@"credential = %@", credential);
                    [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                    return;
                } else {
                    id <OFSDAVFileManagerAuthenticationDelegate> delegate = [OFSDAVFileManager authenticationDelegate];
                    [delegate DAVFileManager:_nonretained_fileManager validateCertificateForChallenge:challenge];
                    [[challenge sender] cancelAuthenticationChallenge:challenge];   // delegate will decide whether to restart the operation
                    return;
                }
            }
        }
        
        // If we "continue without credential", NSURLConnection will consult certificate trust roots and per-cert trust overrides in the normal way. If we cancel the "challenge", NSURLConnection will drop the connection, even if it would have succeeded without our meddling (that is, we can force failure as well as forcing success).

        if (!shouldAskDelegate) {
            [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
            return;
        }
    }

    id <OFSDAVFileManagerAuthenticationDelegate> delegate = [OFSDAVFileManager authenticationDelegate];
    if (delegate)
        credential = [delegate DAVFileManager:_nonretained_fileManager findCredentialsForChallenge:challenge];
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"credential = %@", credential);
    
    if (credential)
        [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
    else {
        _response = [[challenge failureResponse] copy]; // Keep around the response that says something about the failure
        [[challenge sender] cancelAuthenticationChallenge:challenge];
    }
}

- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did cancel challenge %@", [self shortDescription], challenge);
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    OBPRECONDITION(_response == nil);
    
    [_response release];
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
            OFSAddRedirectEntry(_redirections, kOFSRedirectContentLocation, [_response URL], [NSURL URLWithString:location relativeToURL:[_response URL]], responseHeaders);
        }
    }
    
    OBASSERT(_isRead(self) || statusCode == 201 /* Accepted */ || statusCode == 204 /* No Content */ || statusCode >= 400 /* Some sort of error (e.g. missing file or permission denied) */);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    OBPRECONDITION(_response);
    OBPRECONDITION([_response statusCode] != 204); // "No Content"
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did receive data of length %ld", [self shortDescription], [data length]);
    
#ifdef OMNI_ASSERTIONS_ON
    long long bytesReportedSoFar;
#endif
    if (_target) {
        long long processedBytes = [data length];
        OBASSERT(processedBytes >= 0);
        
        _bytesReceived += processedBytes;
        
        if (_targetWantsData)
            [_target fileManager:_nonretained_fileManager operation:self didReceiveData:data];
        else
            [_target fileManager:_nonretained_fileManager operation:self didProcessBytes:[data length]];
            
#ifdef OMNI_ASSERTIONS_ON
        bytesReportedSoFar = _bytesReceived;
#endif
    } else {
        // We are supposed to collect the data (for example, OFSDAVFileManager -_rawDataByRunningRequest:operation:error:).
        if (!_resultData)
            _resultData = [[NSMutableData alloc] initWithData:data];
        else
            [_resultData appendData:data];
        
#ifdef OMNI_ASSERTIONS_ON
        bytesReportedSoFar = [_resultData length];
#endif
    }

    
    // Check that the server and we agree on the expected content length, if it was sent.  It might not have said a content length, in which case we'll just get as much content as we are given.
#ifdef OMNI_ASSERTIONS_ON
    long long expectedContentLength = [_response expectedContentLength];
#endif
    OBPOSTCONDITION(expectedContentLength >= 0 || expectedContentLength == NSURLResponseUnknownLength);
    OBPOSTCONDITION(expectedContentLength == NSURLResponseUnknownLength || bytesReportedSoFar <= expectedContentLength);
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;
{
    OBPRECONDITION(_response == nil);
    OBPRECONDITION(bytesWritten >= 0);
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did send data of length %ld (total %ld, expected %ld)", [self shortDescription], bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    
    _bodyBytesSent += bytesWritten;
    _expectedBytesToWrite = totalBytesExpectedToWrite; // See our initializer for details on this ivar's purpose.

    if (_target) {
        OBASSERT(bytesWritten <= totalBytesWritten);
        OBASSERT(totalBytesWritten <= totalBytesExpectedToWrite);
        [_target fileManager:_nonretained_fileManager operation:self didProcessBytes:bytesWritten];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
#ifdef OMNI_ASSERTIONS_ON
    long long expectedContentLength = [_response expectedContentLength];
#endif
    OBPRECONDITION(expectedContentLength >= 0 || expectedContentLength == NSURLResponseUnknownLength);
    OBPRECONDITION(_target != nil || expectedContentLength == NSURLResponseUnknownLength || [_resultData length] <= (unsigned long long)expectedContentLength); // should have gotten all the content if we are to be considered successfully finised
    OBPRECONDITION(!_finished);
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did finish loading", self);
    _finished = YES;
    
    if (_target)
        [_target fileManager:_nonretained_fileManager operationDidFinish:self withError:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
{
    OBPRECONDITION(!_finished);
    OBPRECONDITION(!_error);
    
    if (OFSFileManagerDebug > 0)
        NSLog(@"%@: did fail with error: %@", [self shortDescription], [error toPropertyList]);
    
    if ([[error domain] isEqualToString:NSURLErrorDomain] && [error code] == NSURLErrorUserCancelledAuthentication) {
        // If we run out of credentials to try, we cancel.  Layer a more useful error on this one.
        NSString *desc = NSLocalizedStringFromTableInBundle(@"Unable to authenticate with WebDAV server.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Please check that the user name and password you provided are correct.", @"OmniFileStore", OMNI_BUNDLE, @"error suggestion");
        OFSError(&error, OFSDAVFileManagerCannotAuthenticate, desc, reason);
    }
    
    [_error release];
    _error = [error copy];
    
    if (_target)
        [_target fileManager:_nonretained_fileManager operationDidFinish:self withError:error];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse;
{
    if (OFSFileManagerDebug > 1)
        NSLog(@"%@: will cache response %@", [self shortDescription], cachedResponse);
    return nil; // Don't cache DAV stuff if asked to.
}

#pragma mark -
#pragma mark Debugging

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
        OBASSERT([from isEqual:[[entries lastObject] objectForKey:kOFSRedirectedTo]]);
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

