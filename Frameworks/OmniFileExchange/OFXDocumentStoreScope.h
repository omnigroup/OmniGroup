// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentStoreScope.h>

@class OFXAgent, OFXServerAccount;

@interface OFXDocumentStoreScope : OFSDocumentStoreScope

- initWithSyncAgent:(OFXAgent *)syncAgent account:(OFXServerAccount *)account documentStore:(OFSDocumentStore *)documentStore;

@property(nonatomic,readonly) OFXAgent *syncAgent;
@property(nonatomic,readonly) OFXServerAccount *account;

@end
