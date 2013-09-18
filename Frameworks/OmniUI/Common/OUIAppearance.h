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

#else

#import <AppKit/NSColor.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSLayoutConstraint.h>

#define OUI_SYSTEM_COLOR_CLASS NSColor
#define OUI_SYSTEM_EDGE_INSETS_STRUCT NSEdgeInsets

extern NSString *const OUIAppearanceColorsDidChangeNotification; // listen to this rather than NSSystemColorsDidChangeNotification so that OUIAppearance can be sure to update its cached gradients and colors first

#endif

// OUIAppearance reads values from a plist in a bundle and converts those values into usable constants for implementing user interfaces.
// On the Mac, each NSBundle instance has one instance of OUIAppearance.plist in its Resources directory; the only way to get an instance of OUIAppearance is to ask a bundle (probably OMNI_BUNDLE).
// On iOS, there is only one bundle, so OUIAppearance instances are created with a specific plist name instead of a bundle. The initializer will take an appearance name "Foo" and search for "FooAppearance.plist" and "Foo.plist" in that order.
@interface OUIAppearance : NSObject

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (instancetype)appearance;
    // determines intended name from called class; subclass OUIAppearance to get app-specific behavior
+ (instancetype)appearanceWithName:(NSString *)appearanceName;
- (id)initWithName:(NSString *)appearanceName;
#endif

- (OUI_SYSTEM_COLOR_CLASS *)colorForKey:(NSString *)key; // value must be a dictionary suitable for +[NSColor(OAExtensions colorFromPropertyListRepresentation:]
- (CGFloat)CGFloatForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (OUI_SYSTEM_EDGE_INSETS_STRUCT)edgeInsetsForKey:(NSString *)key; // value must be a dictionary of the form {left: <number>, right: <number>, top: <number>, bottom: <number>} (missing keys are assumed to be 0)

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

@interface NSBundle (OUIAppearance)
- (OUIAppearance *)appearance;
@end

@interface NSColor (OUIAppearance)

+ (NSColor *)OUISidebarBackgroundColor;
+ (NSColor *)OUISidebarFontColor;

+ (NSColor *)OUISelectionBorderColor;
+ (NSColor *)OUIInactiveSelectionBorderColor;

@end

@interface NSGradient (OUIAppearance)

+ (NSGradient *)OUISelectionGradient;
+ (NSGradient *)OUIInactiveSelectionGradient;

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
