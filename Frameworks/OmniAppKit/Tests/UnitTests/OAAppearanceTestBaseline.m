// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAAppearanceTestBaseline.h"
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC;

NSString * const OAAppearanceTestBaselineTopLevelLeafKey = @"TopLevelFloat";
NSString * const OAAppearanceTestBaselineTopLevelContainerKey = @"Nested";
NSString * const OAAppearanceTestBaselineNestedLeafKey = @"Float";

NSString * const OAAppearanceTestBaselineLeafAliasKey = @"LeafAlias";
NSString * const OAAppearanceTestBaselineContainerAliasKey = @"ContainerAlias";

NSString * const OAAppearanceTestBaselineColorKey = @"Color";
NSString * const OAAppearanceTestBaselineEdgeInsetKey = @"EdgeInsets";

@implementation OAAppearanceTestBaseline

#pragma mark OAAppearancePropertyListCodeable protocol

+ (NSSet<NSString *> *)additionalLocalKeyPaths
{
    return [NSSet setWithArray:@[@"Nested.Float"]];
}

+ (NSSet<NSString *> *)localDynamicPropertyNamesToOmit
{
    return [NSSet setWithArray:@[@"SubclassFloat"]];
}

#pragma mark Dynamic Properties
@dynamic TopLevelFloat;
@dynamic Color;
@dynamic EdgeInsets;

/// Only accessible on subclass instances
@dynamic SubclassFloat;

/// Should only be used in overriding test case. Order of access matters because appearance instances are singletons.
@dynamic OverriddenFloat;

@end

@implementation OAAppearanceTestSubclass1

+ (NSSet<NSString *> *)additionalLocalKeyPaths
{
    return [NSSet new];
}

+ (BOOL)includeSuperclassKeyPaths
{
    return NO;
}

@end

@implementation OAAppearanceTestSubclass2

+ (NSSet<NSString *> *)additionalLocalKeyPaths
{
    return [NSSet new];
}

@dynamic SpecialLeafyString;

@end

@implementation OAAppearanceTestInvalidPlist
+ (NSSet<NSString *> *)additionalLocalKeyPaths
{
    return [NSSet new];
}
@end

@implementation OAAppearanceTestEncodingCoverage
+ (NSSet<NSString *> *)additionalLocalKeyPaths
{
    return [NSSet setWithArray:@[@"Parent.Child1", @"Parent.Child2", @"testAlias"]];
}

@dynamic string;
@dynamic cgFloat;
@dynamic float_;
@dynamic double_;
@dynamic integer;
@dynamic bool_;
@dynamic size;
@dynamic insets;
@dynamic colorWithWhite;
@dynamic colorWithRGB;
@dynamic colorWithHSB;
@dynamic imageWithString;
@dynamic imageWithName;
@dynamic imageWithNameAndBundle;
@dynamic imageWithNameAndColor;
@dynamic dictionary;
@end

