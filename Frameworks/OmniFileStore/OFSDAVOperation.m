// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSDAVOperation.h"

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/Errors.h>

RCS_ID("$Id$");

@implementation OFSDAVOperation

- initWithFileManager:(OFSDAVFileManager *)fileManager request:(NSURLRequest *)request target:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;
{
    OBPRECONDITION([[[request URL] scheme] isEqualToString:@"http"] || [[[request URL] scheme] isEqualToString:@"https"]); // We want a NSHTTPURLResponse
    
    _nonretained_fileManager = fileManager;
    _request = [request copy];
    _target = [target retain];
    
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
    [super dealloc];
}

- (void)startOperation;
{
    OBPRECONDITION(_connection == nil);
    _connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self]; // this starts the operation
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
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Please make sure that the location set in your Sync preferences actually exists.", @"OmniFileStore", OMNI_BUNDLE, @"error reason");
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedRecoverySuggestionErrorKey, nil];
        [info setObject:davError forKey:NSUnderlyingErrorKey];
        
        return [NSError errorWithDomain:OFSDAVHTTPErrorDomain code:code userInfo:info];
    }
    
    return davError;
}

- (NSData *)run:(NSError **)outError;
{
    [self startOperation];
    while (!_finished && !_error) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        [pool release];
    }
    
    // Try to upgrade the response to an error if we didn't get an error in the actual attempt but rather received error content from the server.
    OBASSERT(_response || _error); // Only nil if we got back something other than an http response
    if (_response && !_error) {
        NSInteger code = [_response statusCode];
        OBASSERT(code < 300 || code > 399); // shouldn't have been left with a redirection.
        if (code >= 400) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to perform WebDAV operation.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The %@ server returned \"%@\" (%d) in response to a request to \"%@ %@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [[_request URL] host], [NSHTTPURLResponse localizedStringForStatusCode:code], code, [_request HTTPMethod], [[_request URL] path]];
            NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedRecoverySuggestionErrorKey, nil];
            
            // Add the error content.  Need to obey the charset specified in the Content-Type header.  And the content type.
            if (_resultData) {
                [info setObject:_resultData forKey:@"errorData"];
                
                NSString *contentType = [[_response allHeaderFields] objectForKey:@"Content-Type"];
                do {
                    if (![contentType isKindOfClass:[NSString class]]) {
                        NSLog(@"Error Content-Type not a string");
                        break;
                    }
                    
                    NSArray *components = [contentType componentsSeparatedByString:@";"];
                    if ([components count] != 2) {
                        NSLog(@"Error Content-Type doesn't have two components (mime-type; charset)");
                        break;
                    }
                    
                    // Record the Content-Type
                    [info setObject:contentType forKey:@"errorDataContentType"];
                    
                    components = [[components objectAtIndex:1] componentsSeparatedByString:@"="];
                    if ([components count] != 2) {
                        NSLog(@"Error Content-Type charset doesn't have two components (charset=iana-name)");
                        break;
                    }
                    
                    NSString *encodingName = [[components objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    
                    CFStringEncoding encoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)encodingName);
                    if (encoding == kCFStringEncodingInvalidId) {
                        NSLog(@"Error Content-Type charset encoding not recognized '%@'", encodingName);
                        break;
                    }
                    
                    CFStringRef str = CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)_resultData, encoding);
                    if (!str) {
                        NSLog(@"Error content cannot be turned into string using encoding '%@' (%ld)", encodingName, (long)encoding);
                        break;
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

- (void)runAsynchronously;
{
    // [[OFSDAVOperation backgroundRunLoop] performSelector:@selector(startOperation) target:self argument:nil order:0 modes:nil];
    [self startOperation];
}

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
    
    // Some WebDAV servers (the one builtin in Mac OS X Server, but not the one in .Mac) will redirect "/xyz" to "/xyz/" if we PROPFIND something that is a directory.  But, the re-sent request will be a GET instead of a PROPFIND.  This, in turn, will cause us to get back HTML instead of the expected XML.
    // Likewise, if we MOVE /a/ to /b/ we've seen directires to the non-slash version.  In particular, when using the LAN-local apache and picking local in the simulator on an incompatible database conflict.  When we try to put the new resource into place, it redirects.
    if (redirectResponse) {
        NSString *method = [_request HTTPMethod];
        if ([method isEqualToString:@"PROPFIND"] || [method isEqualToString:@"MOVE"]) {
            // Duplicat the original request, including any DAV headers and body content, but put in the redirected URL.
            NSMutableURLRequest *redirect = [[_request mutableCopy] autorelease];
            [redirect setURL:[request URL]];
            return redirect;
        } else
            OBASSERT_NOT_REACHED("Anything else get redirected that needs this treatment?");
    }
    
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did receive challenge %@", [self shortDescription], challenge);
    
    if (OFSFileManagerDebug > 2) {
        NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
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
        _resultData = [[NSMutableData alloc] init];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    OBPRECONDITION(_response);
    OBPRECONDITION([_response statusCode] != 204); // "No Content"
    
    if (OFSFileManagerDebug > 2)
        NSLog(@"%@: did receive data of length %ld", [self shortDescription], [data length]);
    
    if (_target)
        [_target fileManager:_nonretained_fileManager didReceiveData:data];
    else if (!_resultData)
        _resultData = [[NSMutableData alloc] initWithData:data];
    else
        [_resultData appendData:data];
    
    // Check that the server and we agree on the expected content length, if it was sent.  It might not have said a content length, in which case we'll just get as much content as we are given.
#ifdef OMNI_ASSERTIONS_ON
    long long expectedContentLength = [_response expectedContentLength];
#endif
    OBPOSTCONDITION(expectedContentLength >= 0 || expectedContentLength == NSURLResponseUnknownLength);
    OBPOSTCONDITION(expectedContentLength == NSURLResponseUnknownLength || [_resultData length] <= (unsigned long long)expectedContentLength);
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
        [_target fileManagerDidFinishLoading:_nonretained_fileManager];
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
        [_target fileManager:_nonretained_fileManager didFailWithError:error];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse;
{
    if (OFSFileManagerDebug > 1)
        NSLog(@"%@: will cache response %@", [self shortDescription], cachedResponse);
    return nil; // Don't cache DAV stuff if asked to.
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"%@ %@", [_request HTTPMethod], [[_request URL] absoluteString]];
}

@end

