// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorAppearance.h>

RCS_ID("$Id$");

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

@dynamic InspectorBackgroundColor;
@dynamic InspectorSeparatorColor;
@dynamic InspectorDisabledTextColor;
@dynamic InspectorTextColor;

@dynamic PopoverBackgroundColor;

@dynamic SearchBarFieldBackgroundColor;
@dynamic SearchBarBarTintColor;

@dynamic HorizontalTabBottomStrokeColor;
@dynamic HorizontalTabSeparatorTopColor;


@dynamic TableViewSeparatorColor;
@dynamic TableCellSelectedBackgroundColor;
@dynamic TableCellBackgroundColor;
@dynamic TableCellTextColor;
@dynamic TableCellDetailTextLabelColor;
@dynamic TableCellDisclosureTint;

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

