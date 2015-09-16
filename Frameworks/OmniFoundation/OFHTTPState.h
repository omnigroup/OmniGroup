// Copyright 2012-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFHTTPStateMachine, OFHTTPState;
@class NSMutableURLRequest;

typedef OFHTTPState *(^OFHTTPStateTransitionBlock)();
typedef BOOL (^OPHTTPSetupRequestBlock)(NSMutableURLRequest *request);

#define OFHTTPStateDone ((OFHTTPState *)nil)
extern OFHTTPState *OFHTTPStatePause; // Return this to signal to the state machine that you aren't done running, but that some other external asynchronous operation is happening. Call -start again to restart the machine (it will remain in the previous state, or you can set its currentState property before restarting).

@interface OFHTTPState : NSObject
{
@private
    NSString *name;
    
    NSString *httpMethod;
    NSString *relativePath;
    OPHTTPSetupRequestBlock setupRequest;
    OFHTTPStateTransitionBlock success, redirect, failure;
    NSMutableDictionary *transitions;
}

- initWithName:(NSString *)aName;

@property (readonly, nonatomic) NSString *name;

@property (retain, nonatomic) NSString *httpMethod;
@property (retain, nonatomic) NSString *relativePath;
@property (copy, nonatomic) OPHTTPSetupRequestBlock setupRequest;

@property (copy, nonatomic) OFHTTPStateTransitionBlock success;
@property (copy, nonatomic) OFHTTPStateTransitionBlock redirect;
@property (copy, nonatomic) OFHTTPStateTransitionBlock failure;

- (void)onStatus:(NSInteger)code transition:(OFHTTPStateTransitionBlock)transition;

@property (readonly, nonatomic) NSDictionary *transitions;

- (void)invalidate;

@end
