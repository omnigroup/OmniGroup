// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorAppearance.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

OUIThemedAppearanceTheme const OUIThemedAppearanceThemeDark = @"OUIThemedAppearanceThemeDark";
OUIThemedAppearanceTheme const OUIThemedAppearanceThemeLight = @"OUIThemedAppearanceThemeLight";

static BOOL OUIInspectorAppearanceEnabled = NO;

@implementation OUIInspectorAppearance

+ (void)initialize
{
    OBINITIALIZE;
    
    [self addTheme:OUIThemedAppearanceThemeDark withAppearance:[self appearanceForClass:[OUIInspectorAppearanceDark class]]];
    [self addTheme:OUIThemedAppearanceThemeLight withAppearance:[self appearanceForClass:[OUIInspectorAppearanceLight class]]];
}

+ (BOOL)inspectorAppearanceEnabled;
{
    return OUIInspectorAppearanceEnabled;
}

+ (void)setInspectorAppearanceEnabled:(BOOL)enabled;
{
    OUIInspectorAppearanceEnabled = enabled;
}

+ (instancetype)appearance;
{
    // Make sure nobody is calling this unless they have explicitly opted in to it.
    OBASSERT(OUIInspectorAppearanceEnabled);
    
    return [super appearance];
}

@dynamic InspectorBarStyle;
@dynamic NavigationBarAccessoryBlurEffectStyle;

#define DEFINE_COLOR_ASSET(namedColorProperty) \
- (UIColor *)namedColorProperty \
{ \
    static UIColor *color; \
    static dispatch_once_t onceToken; \
    dispatch_once(&onceToken, ^{ \
        color = [UIColor colorNamed:NSSTRINGIFY(namedColorProperty) inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]; \
    }); \
    return color; \
}


DEFINE_COLOR_ASSET(InspectorBackgroundColor)
DEFINE_COLOR_ASSET(InspectorSeparatorColor)
DEFINE_COLOR_ASSET(InspectorDisabledTextColor)
DEFINE_COLOR_ASSET(InspectorTextColor)
DEFINE_COLOR_ASSET(PlaceholderTextColor)
DEFINE_COLOR_ASSET(PopoverBackgroundColor)
DEFINE_COLOR_ASSET(SearchBarFieldBackgroundColor)
DEFINE_COLOR_ASSET(SearchBarBarTintColor)
DEFINE_COLOR_ASSET(HorizontalTabBottomStrokeColor)
DEFINE_COLOR_ASSET(HorizontalTabSeparatorTopColor)
DEFINE_COLOR_ASSET(TableCellBackgroundColor)
DEFINE_COLOR_ASSET(TableCellSelectedBackgroundColor)
DEFINE_COLOR_ASSET(TableCellTextColor)
DEFINE_COLOR_ASSET(TableCellDetailTextLabelColor)
DEFINE_COLOR_ASSET(TableCellDisclosureTint)
DEFINE_COLOR_ASSET(TableViewSeparatorColor)
DEFINE_COLOR_ASSET(InterfaceActionItemSeparatorColor)

@end

@implementation OUIInspectorAppearanceDark
// empty implementation
@end

@implementation OUIInspectorAppearanceLight
// empty implementation
@end


#pragma mark -

@implementation UIPopoverPresentationController (OUIThemedAppearanceClient)

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    OUIInspectorAppearance *appearance = OB_CHECKED_CAST_OR_NIL(OUIInspectorAppearance, changedAppearance);

    UIColor *backgroundColor = nil;
    if (appearance != [OUIThemedAppearance appearance]) {
        backgroundColor = appearance.InspectorBackgroundColor;
    }
    
    self.backgroundColor = backgroundColor;
}

@end

NS_ASSUME_NONNULL_END
