// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColor.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef OA_PLATFORM_COLOR_CLASS

NS_SWIFT_NAME(ColorCatalog)
@interface OAColorCatalog : NSObject

/// Subclasses can profive a prefix here such that:
///
///    @property (class, nonatomic, readonly) UIColor *fooColor;
///
/// will be looked up as "PREFIX_fooColor" in the asset catalog.
@property (class, nullable, readonly) NSString *colorNamePrefix;

/// This is a convenience method forcalling +colorNamed:bundle: with a nil bundle,which will lookup the color in the default bundle for this class's asset catalog.
+ (nullable OA_PLATFORM_COLOR_CLASS *)colorNamed:(NSString *)name;

/// This is the primitive method which should be overriden by subclasses as needed.
+ (nullable OA_PLATFORM_COLOR_CLASS *)colorNamed:(NSString *)name bundle:(nullable NSBundle *)bundle;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@interface OAColorCatalog (LegacyDarkSupport)

+ (NSString *)legacyDarkColorNameForColorName:(NSString *)colorName;

@end

#endif

NS_ASSUME_NONNULL_END
