// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXFeatures.h>

@interface OFXServerAccount ()

- _initWithUUID:(NSString *)uuid propertyList:(NSDictionary *)propertyList error:(NSError **)outError;

- (void)_storeCredential:(NSURLCredential *)credential forServiceIdentifier:(NSString *)serviceIdentifier;

- (void)_takeValuesFromPropertyList:(NSDictionary *)propertyList;

#if OFX_USE_SECURITY_SCOPED_BOOKMARKS
// Returns nil if the localDocumentsURL is not yet security scoped (we are a new account).
@property(nonatomic,readonly) NSURL *localDocumentsBookmarkURL;
#endif

@end

NSString * const OFXAccountPropertListKey OB_HIDDEN;
