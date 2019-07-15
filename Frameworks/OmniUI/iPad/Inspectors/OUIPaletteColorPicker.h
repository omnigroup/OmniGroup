// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorPicker.h>

NS_ASSUME_NONNULL_BEGIN

@class OUIPaletteTheme;

@interface OUIPaletteColorPicker : OUIColorPicker <OUIColorValue>

@property (nonatomic) BOOL showThemeDisplayNames;
@property (nonatomic, copy) NSArray<OUIPaletteTheme *> *themes;

@end

NS_ASSUME_NONNULL_END
