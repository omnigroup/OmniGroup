// Copyright 2010-2013 The Omni Group. All rights reserved.
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
#define OUI_SYSTEM_SIZE_STRUCT CGSize

#else

#import <AppKit/NSColor.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSLayoutConstraint.h>

#define OUI_SYSTEM_COLOR_CLASS NSColor
#define OUI_SYSTEM_EDGE_INSETS_STRUCT NSEdgeInsets
#define OUI_SYSTEM_SIZE_STRUCT NSSize

extern NSString *const OUIAppearanceColorsDidChangeNotification; // listen to this rather than NSSystemColorsDidChangeNotification so that OUIAppearance can be sure to update its cached gradients and colors first

#endif

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

- (NSDictionary *)dictionaryForKeyPath:(NSString *)keyPath;

- (OUI_SYSTEM_COLOR_CLASS *)colorForKeyPath:(NSString *)keyPath;
    // value must be a dictionary suitable for +[NSColor(OAExtensions colorFromPropertyListRepresentation:]

- (CGFloat)CGFloatForKeyPath:(NSString *)keyPath;

- (BOOL)boolForKeyPath:(NSString *)keyPath;

- (OUI_SYSTEM_EDGE_INSETS_STRUCT)edgeInsetsForKeyPath:(NSString *)keyPath;
    // value must be a dictionary of the form {left: <number>, right: <number>, top: <number>, bottom: <number>} (missing keys are assumed to be 0)

- (OUI_SYSTEM_SIZE_STRUCT)sizeForKeyPath:(NSString *)keyPath;
    // value must be a dictionary of the form {width: <number>, height: <number>} (missing keys are assumed to be 0)

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

@interface NSColor (OUIAppearance)

+ (NSColor *)OUISidebarBackgroundColor;
+ (NSColor *)OUISidebarFontColor;

+ (NSColor *)OUISelectionBorderColor;
+ (NSColor *)OUIInactiveSelectionBorderColor;

@end

#else

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
