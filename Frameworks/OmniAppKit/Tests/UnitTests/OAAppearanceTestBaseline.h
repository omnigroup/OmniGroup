// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAppearance.h>
#import <OmniAppKit/OAAppearancePropertyListCoder.h>

// Constant strings that we use in the baseline .plist. All values are non-zero floats unless otherwise specified.
extern NSString * const OAAppearanceTestBaselineTopLevelLeafKey;
extern NSString * const OAAppearanceTestBaselineTopLevelContainerKey;
extern NSString * const OAAppearanceTestBaselineNestedLeafKey;

extern NSString * const OAAppearanceTestBaselineLeafAliasKey;
extern NSString * const OAAppearanceTestBaselineContainerAliasKey;

extern NSString * const OAAppearanceTestBaselineColorKey; // color object instead of a float
extern NSString * const OAAppearanceTestBaselineEdgeInsetKey; // edge inset struct instead of a float

// Trivial subclass for tests
@interface OAAppearanceTestBaseline : OAAppearance <OAAppearancePropertyListCodeable>

@property (readonly) CGFloat TopLevelFloat;
@property (readonly) NSColor *Color;
@property (readonly) NSEdgeInsets EdgeInsets;

/// Only accessible on subclass instances
@property (readonly) CGFloat SubclassFloat;

/// Should only be used in overriding test case. Order of access matters because appearnace instances are singletons.
@property (readonly) CGFloat OverriddenFloat;

@end

// Sub-subclasses for tests
@interface OAAppearanceTestSubclass1 : OAAppearanceTestBaseline
@end

@interface OAAppearanceTestSubclass2 : OAAppearanceTestBaseline
@property (readonly) NSString *SpecialLeafyString;
@end

@interface OAAppearanceTestInvalidPlist : OAAppearanceTestBaseline
@end

/// Test class covering all property encodings
@interface OAAppearanceTestEncodingCoverage: OAAppearance <OAAppearancePropertyListCodeable>
@property (readonly) NSString *string;
@property (readonly) CGFloat cgFloat;
@property (readonly) float float_;
@property (readonly) double double_;
@property (readonly) NSInteger integer;
@property (readonly) BOOL bool_;
@property (readonly) CGSize size;
@property (readonly) OA_SYSTEM_EDGE_INSETS_STRUCT insets;
@property (readonly) OA_SYSTEM_COLOR_CLASS *colorWithWhite;
@property (readonly) OA_SYSTEM_COLOR_CLASS *colorWithRGB;
@property (readonly) OA_SYSTEM_COLOR_CLASS *colorWithHSB;

// TODO: Generalize for iOS. This test current only runs on Mac, and we don't have an OA_SYSTEM_IMAGE_CLASS cover yet.
@property (readonly) NSImage *imageWithString;
@property (readonly) NSImage *imageWithName;
@property (readonly) NSImage *imageWithNameAndBundle;
@property (readonly) NSImage *imageWithNameAndColor;

@property (readonly) NSDictionary *dictionary;
@end
