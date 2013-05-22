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

@end

NSString * const OFXAccountPropertListKey OB_HIDDEN;
