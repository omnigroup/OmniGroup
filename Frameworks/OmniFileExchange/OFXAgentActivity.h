// Copyright 2012-2013 The Omni Group. All rights reserved.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFXAgent, OFXServerAccount, OFXAccountActivity;

@interface OFXAgentActivity : NSObject

- initWithAgent:(OFXAgent *)agent;

@property(nonatomic,readonly) OFXAgent *agent;

- (OFXAccountActivity *)activityForAccount:(OFXServerAccount *)account;

@property(nonatomic,readonly) BOOL isActive; // YES if any account is syncing
@property(nonatomic,readonly,copy) NSSet *accountUUIDsWithErrors;

- (void)eachAccountActivityWithError:(void (^)(OFXAccountActivity *accountActivity))applier;

@end
