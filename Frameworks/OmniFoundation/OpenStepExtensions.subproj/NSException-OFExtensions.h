// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSException.h>
#import <OmniBase/NSException-OBExtensions.h>
#import <OmniFoundation/OFBundleRegistryTarget.h>

@interface NSException (OFExtensions) <OFBundleRegistryTarget>
- (NSString *)displayName;
@end
