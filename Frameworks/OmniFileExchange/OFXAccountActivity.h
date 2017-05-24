// Copyright 2012-2014,2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFXAgent, OFXFileMetadata, OFXRegistrationTable<ValueType>, OFXServerAccount;
 
@interface OFXAccountActivity : NSObject

// Should only be called by OFXAgentActivity ideally
- initWithRunningAccount:(OFXServerAccount *)account agent:(OFXAgent *)agent;
- initWithAccount:(OFXServerAccount *)account agent:(OFXAgent *)agent; // for accounts that failed to start

@property(nonatomic,readonly) OFXServerAccount *account;
@property(nonatomic,readonly) OFXRegistrationTable <OFXFileMetadata *> *registrationTable;

@property(nonatomic,readonly) NSUInteger downloadingFileCount;
@property(nonatomic,readonly) unsigned long long downloadingSize;

@property(nonatomic,readonly) NSUInteger uploadingFileCount;
@property(nonatomic,readonly) unsigned long long uploadingSize;

@property(nonatomic,readonly) BOOL isActive;
@property(nonatomic,readonly) NSError *lastError; // This is for the whole account

@property(nonatomic,readonly) NSDate *lastSyncDate;

@end
