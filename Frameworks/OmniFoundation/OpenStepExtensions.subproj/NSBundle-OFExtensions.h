// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSBundle.h>

#import <OmniBase/assertions.h>
#import <OmniFoundation/NSString-OFExtensions.h>

#import <OmniBase/OBUtilities.h> // OMNI_BUNDLE has moved to OmniBase.

@interface NSBundle (OFExtensions)

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
/// Various pieces of information extraced from the code signature for this bundle.
/// See Security/SecCode.h for the dictionary keys.
- (NSDictionary *)codeSigningInfoDictionary:(NSError **)error;
#endif

/// The code signing entitlements for this process. On iOS, these can only be extracted from the embedded provisioning profile, if one exists.
- (NSDictionary *)codeSigningEntitlements:(NSError **)error;

@end

/// If we are running a bundled app, this will return the main bundle.  Otherwise, if we are running unit tests, this will return the unit test bundle.
extern NSBundle * OFControllingBundle(void);
