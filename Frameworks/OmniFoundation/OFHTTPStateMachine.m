// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFHTTPStateMachine.h>

#import <Foundation/Foundation.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFHTTPState.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

@implementation OFHTTPStateMachine

@synthesize rootURL, username, password, currentState, statusCode, responseETag, responseData;

static OFPreference *OFHTTPStateMachineLogLevelPreference;

static NSString * const HTTPErrorDomain = @"org.w3.http";

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFHTTPStateMachineLogLevelPreference = [[OFPreference preferenceForKey:@"OFHTTPStateMachineLogLevel"] retain];
}

#define STATE_LOG(level, format, ...) do { \
    if ([OFHTTPStateMachineLogLevelPreference intValue] >= level) \
        NSLog(@"HTTP: " format, ## __VA_ARGS__); \
} while(0)

- initWithRootURL:(NSURL *)aURL delegate:(id)aDelegate;
{
    if (!(self = [super init]))
        return nil;
    
    rootURL = [aURL retain];
    states = [[NSMutableSet alloc] init];
    delegate = aDelegate;
    responseData = [[NSMutableData alloc] init];
    initialRequest = YES;
    return self;
}

- (void)dealloc;
{
    [states release];
    [rootURL release];
    [responseData release];
    [responseETag release];
    
    [super dealloc];
}

- (OFHTTPState *)addStateWithName:(NSString *)aName;
{
    OFHTTPState *result = [[OFHTTPState alloc] initWithName:aName];
    [states addObject:result];
    [result release];
    return result;
}

- (void)start;
{
    OBPRECONDITION(activeConnection == nil);
    
    NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
    if (currentState.relativePath)
        [request setURL:[NSURL URLWithString:currentState.relativePath relativeToURL:rootURL]];
    else
        [request setURL:rootURL];
    if (currentState.httpMethod)
        [request setHTTPMethod:currentState.httpMethod];
    
    if (currentState.setupRequest && !currentState.setupRequest(request)) {
        [delegate httpStateMachineCompleted:self];
        return;
    }
    [responseData setLength:0];
    self.responseETag = nil;
    redirectHandling = NO;
    
    STATE_LOG(1, @"sending request for state=%@", currentState.name);

    // -setDelegateQueue: was broken on older OS versions according to our testing, but we require 10.7 and iOS 6 now, where it does work. See <http://ddeville.me/2011/12/broken-NSURLConnection-on-ios/>
    activeConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [activeConnection setDelegateQueue:[NSOperationQueue currentQueue]];
    [activeConnection start];
}

- (void)cancel;
{
    redirectHandling = YES;
    [activeConnection cancel];
    [activeConnection release];
    activeConnection = nil;
    [delegate httpStateMachineCompleted:self];
}

- (void)invalidate;
{
    OBPRECONDITION(activeConnection == nil);
    [states makeObjectsPerformSelector:@selector(invalidate)];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
{
    if (response) {
        if (currentState.redirect) {
            request = nil;
        } else {
            request = [delegate httpStateMachine:self shouldSendRequest:request forRedirect:response];
        }
    }
    redirectHandling = (request == nil);
    return request;
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
        if ([delegate respondsToSelector:@selector(httpStateMachine:validateRecoverableTrustChallenge:)])
            result = YES;
        else
            result = NO; // Shouldn't be reached, but who knows.
    } else {
        result = YES;
    }
    
    return result;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    NSString *challengeMethod = [protectionSpace authenticationMethod];

    STATE_LOG(1, @"challenge=%@ realm=%@ method=%@", [protectionSpace host], [protectionSpace realm], [protectionSpace authenticationMethod]);

    // Have a theory that we're getting the same challenge when the responses go (1)unauthorized,(2)redirect,(3)unauthorized, but can't repro. Trying the "> 1" to test and added more logging
    if ([challenge previousFailureCount] > 1) {
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    } else if ([challengeMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        SecTrustRef trustRef = [protectionSpace serverTrust];
        if (trustRef != NULL) {
            SecTrustResultType evaluationResult = kSecTrustResultOtherError;
            OSStatus oserr = SecTrustEvaluate(trustRef, &evaluationResult); // NB: May block for long periods (eg OCSP verification, etc)
            if (oserr == noErr && evaluationResult == kSecTrustResultRecoverableTrustFailure) {
                // The situation we're interested in is "recoverable failure": this indicates that the evaluation failed, but might succeed if we prod it a little.
                if ([delegate respondsToSelector:@selector(httpStateMachine:validateRecoverableTrustChallenge:)])
                    [delegate httpStateMachine:self validateRecoverableTrustChallenge:challenge];
                else 
                    [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
            } else {
                [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
            }
        }
    } else {
        NSURLCredential *credential = [NSURLCredential credentialWithUser:username password:password persistence:NSURLCredentialPersistenceForSession];
        [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
    }
}

- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
}

- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection;
{
    return !initialRequest;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    if (redirectHandling)
        return;
    
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    statusCode = [http statusCode];
    if (statusCode >= 200 && statusCode < 300) {
        self.responseETag = [[http allHeaderFields] objectForKey:@"Etag"];
    }
    STATE_LOG(1, @"state=%@ response: %ld %@", currentState.name, (long)statusCode, [NSHTTPURLResponse localizedStringForStatusCode:[http statusCode]]);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    [responseData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
    NSError *error = nil;
    OFHTTPState *newState = nil;
    
    [activeConnection release];
    activeConnection = nil;
    initialRequest = NO;
    
    NSNumber *statusCodeNumber = [NSNumber numberWithInteger:statusCode];
    if (statusCode == 409) // 'conflict' is kind of a weird code, we always want to treat this as the same as 404 not found, since some servers return a 409 when we expect 404, and we never actually expect 409
        statusCodeNumber = [NSNumber numberWithInteger:404];
    OFHTTPStateTransitionBlock customBlock = [currentState.transitions objectForKey:statusCodeNumber];
    
    if (redirectHandling) {
        newState = currentState.redirect();
    } else if (customBlock) {
        newState = customBlock();
    } else if (statusCode >= 200 && statusCode < 300) {
        if (currentState.success)
            newState = currentState.success();
    } else if (currentState.failure) {
        newState = currentState.failure();
    } else {
        error = [NSError errorWithDomain:HTTPErrorDomain code:statusCode userInfo:[NSDictionary dictionaryWithObject:[NSHTTPURLResponse localizedStringForStatusCode:statusCode] forKey:NSLocalizedDescriptionKey]];
    }
    
    if (newState) {
        if (newState != OFHTTPStatePause) {
            self.currentState = newState;
            [self start];
        }
    } else if (error) {
        [delegate httpStateMachine:self failedWithError:error];
    } else {
        [delegate httpStateMachineCompleted:self];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
{
    [activeConnection release];
    activeConnection = nil;
    
    [delegate httpStateMachine:self failedWithError:error];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse;
{
    return nil;
}


@end
