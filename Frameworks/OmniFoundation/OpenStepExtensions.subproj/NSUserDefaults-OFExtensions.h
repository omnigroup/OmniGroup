// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// Don't try to read defaults in OBDidLoad actions, they might not be registered yet. Register for OFControllerDidInitNotification, then read defaults when that's posted.

#import <Foundation/NSUserDefaults.h>
#import <OmniFoundation/OFBundleRegistryTarget.h>
#import <OmniFoundation/OFBundleMigrationTarget.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (OFExtensions) <OFBundleRegistryTarget, OFBundleMigrationTarget>
@end

OB_HIDDEN extern NSString * const OFUserDefaultsRegistrationItemName; // Needed by OFBundleRegistry

NS_ASSUME_NONNULL_END
