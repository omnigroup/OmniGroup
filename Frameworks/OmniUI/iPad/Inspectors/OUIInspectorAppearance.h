// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//
// $Id$

#import <OmniUI/OUIThemedAppearance.h>

extern OUIThemedAppearanceTheme const OUIThemedAppearanceThemeDark;
extern OUIThemedAppearanceTheme const OUIThemedAppearanceThemeLight;

@interface OUIInspectorAppearance : OUIThemedAppearance

@property (nonatomic, readwrite, class) BOOL inspectorAppearanceEnabled;

@property (nonatomic, readonly) UIBarStyle InspectorBarStyle;

@property (nonatomic, readonly) UIColor *InspectorBackgroundColor;
@property (nonatomic, readonly) UIColor *InspectorSeparatorColor;
@property (nonatomic, readonly) UIColor *InspectorDisabledTextColor;
@property (nonatomic, readonly) UIColor *InspectorTextColor;

@property (nonatomic, readonly) UIColor *PopoverBackgroundColor;

@property (nonatomic, readonly) UIColor *SearchBarFieldBackgroundColor;
@property (nonatomic, readonly) UIColor *SearchBarBarTintColor;

@property (nonatomic, readonly) UIColor *HorizontalTabBottomStrokeColor;
@property (nonatomic, readonly) UIColor *HorizontalTabSeparatorTopColor;

@property (nonatomic, readonly) UIColor *TableCellBackgroundColor;
@property (nonatomic, readonly) UIColor *TableCellSelectedBackgroundColor;
@property (nonatomic, readonly) UIColor *TableCellTextColor;
@property (nonatomic, readonly) UIColor *TableCellDetailTextLabelColor;
@property (nonatomic, readonly) UIColor *TableCellDisclosureTint;
@property (nonatomic, readonly) UIColor *TableViewSeparatorColor;

@end

@interface OUIInspectorAppearanceDark: OUIInspectorAppearance
@end

@interface OUIInspectorAppearanceLight: OUIInspectorAppearance
@end
