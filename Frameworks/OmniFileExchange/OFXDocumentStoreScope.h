// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <OmniDocumentStore/ODSScope.h>

@class OFXAgent, OFXServerAccount;

@interface OFXDocumentStoreScope : ODSScope

- initWithSyncAgent:(OFXAgent *)syncAgent account:(OFXServerAccount *)account documentStore:(ODSStore *)documentStore;

@property(nonatomic,readonly) OFXAgent *syncAgent;
@property(nonatomic,readonly) OFXServerAccount *account;

@end

#endif
