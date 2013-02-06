// Copyright 2012-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSURL, NSURLConnection, NSMutableSet, NSMutableData, NSURLRequest, NSURLResponse, NSURLAuthenticationChallenge;
@class OFHTTPState;

@interface OFHTTPStateMachine : NSObject
{
@private
    NSURL *rootURL;
    NSString *username, *password;
    
    id delegate;
    
    NSURLConnection *activeConnection;
    OFHTTPState *currentState;
    NSMutableSet *states;

    NSInteger statusCode;
    NSString *responseETag;
    NSMutableData *responseData;
    BOOL redirectHandling;
    BOOL initialRequest;
}

- initWithRootURL:(NSURL *)aURL delegate:(id)aDelegate;
- (OFHTTPState *)addStateWithName:(NSString *)aName;

- (void)start;
- (void)cancel;
- (void)invalidate;

@property (retain, nonatomic) NSURL *rootURL;

@property (retain, nonatomic) NSString *username;
@property (retain, nonatomic) NSString *password;

@property (retain, nonatomic) OFHTTPState *currentState;
@property (assign, nonatomic) NSInteger statusCode;
@property (retain, nonatomic) NSString *responseETag;
@property (readonly, nonatomic) NSMutableData *responseData;

@end

@interface NSObject (OFHTTPStateMachineDelegate)

- (void)httpStateMachineCompleted:(OFHTTPStateMachine *)machine;
- (NSURLRequest *)httpStateMachine:(OFHTTPStateMachine *)machine shouldSendRequest:(NSURLRequest *)request forRedirect:(NSURLResponse *)redirectResponse;
- (void)httpStateMachine:(OFHTTPStateMachine *)machine failedWithError:(NSError *)error;
- (void)httpStateMachine:(OFHTTPStateMachine *)machine validateRecoverableTrustChallenge:(NSURLAuthenticationChallenge *)challenge;

@end
