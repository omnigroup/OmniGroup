// Copyright 2014-2015 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAAppearanceTestBaseline.h"
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

NSString * const OAAppearanceTestBaselineTopLevelLeafKey = @"TopLevelFloat";
NSString * const OAAppearanceTestBaselineTopLevelContainerKey = @"Nested";
NSString * const OAAppearanceTestBaselineNestedLeafKey = @"Float";

NSString * const OAAppearanceTestBaselineLeafAliasKey = @"LeafAlias";
NSString * const OAAppearanceTestBaselineContainerAliasKey = @"ContainerAlias";

NSString * const OAAppearanceTestBaselineColorKey = @"Color";
NSString * const OAAppearanceTestBaselineEdgeInsetKey = @"EdgeInsets";

@implementation OAAppearanceTestBaseline

@dynamic TopLevelFloat;
@dynamic Color;
@dynamic EdgeInsets;

/// Only accessible on subclass instances
@dynamic SubclassFloat;

/// Should only be used in overriding test case. Order of access matters because appearnace instances are singletons.
@dynamic OverriddenFloat;

@end

@implementation OAAppearanceTestSubclass1
@end

@implementation OAAppearanceTestSubclass2
@end
