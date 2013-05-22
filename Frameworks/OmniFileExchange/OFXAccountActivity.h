// Copyright 2012-2013 The Omni Group. All rights reserved.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFXAgent, OFXRegistrationTable, OFXServerAccount;
 
@interface OFXAccountActivity : NSObject

// Should only be called by OFXAgentActivity ideally
- initWithRunningAccount:(OFXServerAccount *)account agent:(OFXAgent *)agent;

@property(nonatomic,readonly) OFXServerAccount *account;
@property(nonatomic,readonly) OFXRegistrationTable *registrationTable;

@property(nonatomic,readonly) NSUInteger downloadingFileCount;
@property(nonatomic,readonly) unsigned long long downloadingSize;

@property(nonatomic,readonly) NSUInteger uploadingFileCount;
@property(nonatomic,readonly) unsigned long long uploadingSize;

@property(nonatomic,readonly) BOOL isActive;
@property(nonatomic,readonly) NSError *lastError;

@property(nonatomic,readonly) NSDate *lastSyncDate;

@end
