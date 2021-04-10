// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXFeatures.h>

@interface OFXServerAccount ()

- _initWithUUID:(NSString *)uuid propertyList:(NSDictionary *)propertyList error:(NSError **)outError;

- (void)_storeCredential:(NSURLCredential *)credential forServiceIdentifier:(NSString *)serviceIdentifier;

- (void)_takeValuesFromPropertyList:(NSDictionary *)propertyList;

#if OMNI_BUILDING_FOR_IOS
// This is set to YES when an account was previously using the URL format plist, and has just migrated to the bookmark format plist.
@property(readonly,nonatomic) BOOL didMigrate;
#endif

@end

OB_HIDDEN extern NSString * const OFXAccountPropertListKey;
