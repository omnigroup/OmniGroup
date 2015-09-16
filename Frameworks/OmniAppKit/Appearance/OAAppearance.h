// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

// Explicitly grab the TargetConditionals header so that when building iOS extensions, we can get the right value for TARGET_OS_IPHONE
#import <TargetConditionals.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <UIKit/UIColor.h>
#import <UIKit/UIGeometry.h>

#define OA_SYSTEM_COLOR_CLASS UIColor
#define OA_SYSTEM_EDGE_INSETS_STRUCT UIEdgeInsets

#else

#import <AppKit/NSColor.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSLayoutConstraint.h>

#define OA_SYSTEM_COLOR_CLASS NSColor
#define OA_SYSTEM_EDGE_INSETS_STRUCT NSEdgeInsets

void OAAppearanceSetUserOverrideFolder(NSString *userOverrideFolder);

#endif

/// Subclasses can post this notification (with self as the object) when something happens that is about to cause the appearance instances values to change.
extern NSString *const OAAppearanceValuesWillChangeNotification;

// Subclasses can post this notification (with self as the object) when something happens that causes its values to change.
// N.B., on the Mac, listen to this rather than NSSystemColorsDidChangeNotification so that OAAppearance can be sure to update its cached gradients and colors first.
extern NSString *const OAAppearanceValuesDidChangeNotification;

// We expect that NSGeometry types and CGGeometry types are the same (so that we can use, for example, CGSize everywhere instead of a hypothetical OA_SYSTEM_SIZE_STRUCT). There are no NSGeometry types on iOS, so only check on the Mac.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #if !defined(NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES) || !NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
        #error NSGeometry and CGGeometry types must be identical!
    #endif
#endif

/// Key for the aliases section within an OAAppearance plist. Has value @"OAAppearanceAliases".
extern NSString * const OAAppearanceAliasesKey;

/*! Reads values from a plist in a bundle and converts those values into usable constants for implementing user interfaces. +appearance searches in the bundle of the receiver for a plist with a name derived from that of the receiver. (See +appearance for details.)
 *
 * Subclasses can inherit and override appearance attributes from their superclass. If an appearance object is asked for a value that is not in its plist, it will consult its superclass. Thus, it is recommended that each application or framework create a subclass of OAAppearance and use it consitently.
 *
 * OAAppearance will dynamically generate accessors for any declared properties. To use this feature, declare a _readonly_ property of the appropriate type in a category on your OAAppearance subclass. (Declaring the property in a category helps avoid accidental automatic property synthesis.)
 *
 * Then, provide a `dynamic` declaration in your category implementation. At runtime, OAAppearance will use the property's name (which may differ from the property's getter name) as a key path to the appropriate primitive accessor (such as -colorForKeyPath:).
 */
@interface OAAppearance : NSObject

/*! Returns an instance of the receiver whose values come from a plist in the receiver's bundle. This method first looks for a plist named "<ClassName>Appearance.plist", followed by "<ClassName>.plist".
 */
+ (instancetype)appearance;

- (NSString *)stringForKeyPath:(NSString * )keyPath;
- (NSDictionary *)dictionaryForKeyPath:(NSString *)keyPath;

- (OA_SYSTEM_COLOR_CLASS *)colorForKeyPath:(NSString *)keyPath;
    // value must be a dictionary suitable for +[NSColor(OAExtensions colorFromPropertyListRepresentation:]

- (float)floatForKeyPath:(NSString *)keyPath;
- (double)doubleForKeyPath:(NSString *)keyPath;
- (CGFloat)CGFloatForKeyPath:(NSString *)keyPath;
- (NSInteger)integerForKeyPath:(NSString *)keyPath;

- (BOOL)boolForKeyPath:(NSString *)keyPath;

- (OA_SYSTEM_EDGE_INSETS_STRUCT)edgeInsetsForKeyPath:(NSString *)keyPath;
    // value must be a dictionary of the form {left: <number>, right: <number>, top: <number>, bottom: <number>} (missing keys are assumed to be 0)

- (CGSize)sizeForKeyPath:(NSString *)keyPath;
    // value must be a dictionary of the form {width: <number>, height: <number>} (missing keys are assumed to be 0)

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
/*!
 If the value of the key path is a string, the main bundle will be searched for an image with that name.
 Otherwise, the value at the key path can be a dictionary with the following entries:
 
 name: the name to use, required
 bundle: optional, one of...
 "self" -- the bundle defining the OAAppearance subclass
 "main" -- the main bundle
 other -- a bundle identifier
 */
- (UIImage *)imageForKeyPath:(NSString *)keyPath;
#else // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
/*!
 If the value of the key path is a string, the main bundle will be searched for an image with that name.
 Otherwise, the value at the key path can be a dictionary with the following entries:
 
 name: the name to use, required
 bundle: optional, one of...
    "self" -- the bundle defining the OAAppearance subclass
    "main" -- the main bundle
    other -- a bundle identifier
 color: optional, one of...
    string -- the name of another key path to use for the tint color, via -colorForKeyPath:.
    dictionary -- a specific color to use, via +[NSColor(OAExtensions colorFromPropertyListRepresentation:]
 */
- (NSImage *)imageForKeyPath:(NSString *)keyPath;
#endif

/// Cause this appearance instance to invalidate all its internal caching and reread values from the on-disk plist definitions. N.B., because of the inheritance mechanism whereby subclasses can get their values from the on-disk plist definitions of superclasses, invalidating a superclass singleton's cache invalidates the cache of all subclass singletons. Thus `[[OAAppearance appearance] invalidateCachedValues]` causes the cache of all appearance instances to be invalidated.
- (void)invalidateCachedValues;
/// Incremented each time the cache is invalidated, whether externally or because of a dynamic plist change.
@property (nonatomic, readonly) NSUInteger cacheInvalidationCount;

@end

/// API for use by subclasses
@interface OAAppearance (Subclasses)
/// Returns the singleton instance of the given appearance subclass. Any overrides must call super and should vend the returned result. The default implementation dynamically creates classes that are necessary for correct subclassing behavior of dynamic accessors.
+ (OAAppearance *)appearanceForClass:(Class)cls NS_REQUIRES_SUPER;
@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

@interface NSColor (OAAppearance)

+ (NSColor *)OASidebarBackgroundColor;
+ (NSColor *)OASidebarFontColor;

+ (NSColor *)OASelectionBorderColor;
+ (NSColor *)OAInactiveSelectionBorderColor;

@end

#else

@interface OAAppearance (OAAppearance)
@property (readonly) CGFloat emptyOverlayViewLabelMaxWidthRatio;
@property (readonly) CGFloat overlayInspectorWindowHeightFraction;
@property (readonly) CGFloat overlayInspectorWindowMaxHeight;
@property (readonly) UIColor *overlayInspectorTopSeparatorColor;
@property (readonly) UIEdgeInsets navigationBarTextFieldBackgroundImageInsets;
@property (readonly) CGFloat navigationBarTextFieldLineHeightMultiplier;
@end

@interface UIColor (OAAppearance)
- (BOOL)isLightColor;
@end

#endif
