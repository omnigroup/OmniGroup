// Copyright 2014-2015 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniAppKit/OAAppearance.h>

// Constant strings that we use in the baseline .plist. All values are non-zero floats unless otherwise specified.
extern NSString * const OAAppearanceTestBaselineTopLevelLeafKey;
extern NSString * const OAAppearanceTestBaselineTopLevelContainerKey;
extern NSString * const OAAppearanceTestBaselineNestedLeafKey;

extern NSString * const OAAppearanceTestBaselineLeafAliasKey;
extern NSString * const OAAppearanceTestBaselineContainerAliasKey;

extern NSString * const OAAppearanceTestBaselineColorKey; // color object instead of a float
extern NSString * const OAAppearanceTestBaselineEdgeInsetKey; // edge inset struct instead of a float

// Trivial subclass for tests
@interface OAAppearanceTestBaseline : OAAppearance

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
@end
