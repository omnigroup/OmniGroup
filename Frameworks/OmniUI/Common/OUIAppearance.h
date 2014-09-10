// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <UIKit/UIColor.h>
#import <UIKit/UIGeometry.h>

#define OUI_SYSTEM_COLOR_CLASS UIColor
#define OUI_SYSTEM_EDGE_INSETS_STRUCT UIEdgeInsets

#else

#import <AppKit/NSColor.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSLayoutConstraint.h>

#define OUI_SYSTEM_COLOR_CLASS NSColor
#define OUI_SYSTEM_EDGE_INSETS_STRUCT NSEdgeInsets

void OUIAppearanceSetUserOverrideFolder(NSString *userOverrideFolder);

#endif

/// Subclasses can post this notification (with self as the object) when something happens that is about to cause the appearance instances values to change.
extern NSString *const OUIAppearanceValuesWillChangeNotification;

// Subclasses can post this notification (with self as the object) when something happens that causes its values to change.
// N.B., on the Mac, listen to this rather than NSSystemColorsDidChangeNotification so that OUIAppearance can be sure to update its cached gradients and colors first.
extern NSString *const OUIAppearanceValuesDidChangeNotification;

// We expect that NSGeometry types and CGGeometry types are the same (so that we can use, for example, CGSize everywhere instead of a hypothetical OUI_SYSTEM_SIZE_STRUCT). There are no NSGeometry types on iOS, so only check on the Mac.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #if !defined(NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES) || !NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
        #error NSGeometry and CGGeometry types must be identical!
    #endif
#endif

/// Key for the aliases section within an OUIAppearance plist. Has value @"OUIAppearanceAliases".
extern NSString * const OUIAppearanceAliasesKey;

/*! Reads values from a plist in a bundle and converts those values into usable constants for implementing user interfaces. +appearance searches in the bundle of the receiver for a plist with a name derived from that of the receiver. (See +appearance for details.)
 *
 * Subclasses can inherit and override appearance attributes from their superclass. If an appearance object is asked for a value that is not in its plist, it will consult its superclass. Thus, it is recommended that each application or framework create a subclass of OUIAppearance and use it consitently.
 *
 * OUIAppearance will dynamically generate accessors for any declared properties. To use this feature, declare a _readonly_ property of the appropriate type in a category on your OUIAppearance subclass. (Declaring the property in a category helps avoid accidental automatic property synthesis.)
 *
 * Then, provide a `dynamic` declaration in your category implementation. At runtime, OUIAppearance will use the property's name (which may differ from the property's getter name) as a key path to the appropriate primitive accessor (such as -colorForKeyPath:).
 */
@interface OUIAppearance : NSObject

/*! Returns an instance of the receiver whose values come from a plist in the receiver's bundle. This method first looks for a plist named "<ClassName>Appearance.plist", followed by "<ClassName>.plist".
 */
+ (instancetype)appearance;

- (NSString *)stringForKeyPath:(NSString * )keyPath;
- (NSDictionary *)dictionaryForKeyPath:(NSString *)keyPath;

- (OUI_SYSTEM_COLOR_CLASS *)colorForKeyPath:(NSString *)keyPath;
    // value must be a dictionary suitable for +[NSColor(OAExtensions colorFromPropertyListRepresentation:]

- (CGFloat)CGFloatForKeyPath:(NSString *)keyPath;
- (NSInteger)integerForKeyPath:(NSString *)keyPath;

- (BOOL)boolForKeyPath:(NSString *)keyPath;

- (OUI_SYSTEM_EDGE_INSETS_STRUCT)edgeInsetsForKeyPath:(NSString *)keyPath;
    // value must be a dictionary of the form {left: <number>, right: <number>, top: <number>, bottom: <number>} (missing keys are assumed to be 0)

- (CGSize)sizeForKeyPath:(NSString *)keyPath;
    // value must be a dictionary of the form {width: <number>, height: <number>} (missing keys are assumed to be 0)

/// Cause this appearance instance to invalidate all its internal caching and reread values from the on-disk plist definitions.
- (void)invalidateCachedValues;
/// Incremented each time the cache is invalidated, whether externally or because of a dynamic plist change.
@property (nonatomic, readonly) NSUInteger cacheInvalidationCount;

@end

/// API for use by subclasses
@interface OUIAppearance (Subclasses)
/// Returns the singleton instance of the given appearance subclass.
+ (OUIAppearance *)appearanceForClass:(Class)cls;
@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

@interface NSColor (OUIAppearance)

+ (NSColor *)OUISidebarBackgroundColor;
+ (NSColor *)OUISidebarFontColor;

+ (NSColor *)OUISelectionBorderColor;
+ (NSColor *)OUIInactiveSelectionBorderColor;

@end

#else

@interface OUIAppearance (OmniUIAppearance)
@property (readonly) CGFloat emptyOverlayViewLabelMaxWidthRatio;
@end

@interface UIColor (OUIAppearance)

+ (UIColor *)omniRedColor;
+ (UIColor *)omniOrangeColor;
+ (UIColor *)omniYellowColor;
+ (UIColor *)omniGreenColor;
+ (UIColor *)omniTealColor;
+ (UIColor *)omniBlueColor;
+ (UIColor *)omniPurpleColor;
+ (UIColor *)omniGraphiteColor;
+ (UIColor *)omniCremaColor;

+ (UIColor *)omniAlternateRedColor;
+ (UIColor *)omniAlternateYellowColor;

+ (UIColor *)omniNeutralDeemphasizedColor;
+ (UIColor *)omniNeutralPlaceholderColor;
+ (UIColor *)omniNeutralLightweightColor;

+ (UIColor *)omniDeleteColor;

- (BOOL)isLightColor;

@end

#endif

// Lifted up here so that OUIDocumentPreview and OUIAppearance (OmniUIInternal) can use it.
typedef NS_ENUM(NSUInteger, OUIDocumentPreviewArea) {
    OUIDocumentPreviewAreaLarge, // Fill item, when in a scope
    OUIDocumentPreviewAreaMedium, // Full item, when at the home screen
    OUIDocumentPreviewAreaSmall, // Inner folder item, when in a scope
    OUIDocumentPreviewAreaTiny, // Inner folder item, when at the home screen.
};
