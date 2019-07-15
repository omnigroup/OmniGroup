// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// OFBundleRegistry searches for loadable bundles, then processes the OFRegistrations for all software components (i.e. frameworks, the application, and any loadable bundles).

#import <OmniFoundation/OFObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray, NSBundle;

// The iPhone can't dynamically load code (or even link frameworks), so a lot of this class does nothing on that platform.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #define OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
#endif

#ifdef OF_BUNDLE_REGISTRY_DYNAMIC_BUNDLE_LOADING
extern NSString * const OFBundleRegistryDisabledBundlesDefaultsKey;
#endif

@interface OFBundleRegistry : OFObject

+ (void)registerKnownBundles;
    // Called automatically via OBInvokeRegisteredLoadActions()

@property (nonatomic, class, readonly) NSDictionary <NSString *, NSString *> *softwareVersionDictionary;
    // Returns a dictionary of the registered software versions
@property (nonatomic, class, readonly) NSArray <NSMutableDictionary <NSString *, id> *> *knownBundles;
    // Returns the known bundle descriptions (see comments in the implementation for details)
@property (nonatomic, class, readonly) NSArray <NSBundle *> *knownNSBundles;
    // Returns the known bundle descriptions (see comments in the implementation for details)

+ (void)noteAdditionalBundles:(nullable NSArray *)additionalBundles owner:(id)bundleOwner;
    // Objects that maintain bundles or plugins that are not known to OFBundleRegistry can note their descriptions here and they will be included in +knownBundles

@end

NS_ASSUME_NONNULL_END

