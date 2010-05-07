// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIScrollView.h>

@class OQColor;

@interface OUIColorSwatchPicker : UIView
{
@private
    NSString *_palettePreferenceKey;
    NSMutableArray *_colors;
    OQColor *_swatchSelectionColor;
    
    NSMutableArray *_colorSwatches;

    BOOL _wraps;
    BOOL _showsNavigationSwatch;
}

@property(copy,nonatomic) NSString *palettePreferenceKey;

@property(copy,nonatomic) NSArray *colors;

@property(assign,nonatomic) BOOL wraps;
@property(assign,nonatomic) BOOL showsNavigationSwatch;

- (void)sizeHeightToFit;

- (void)setSwatchSelectionColor:(OQColor *)color;
@property(readonly) BOOL hasSelectedSwatch;
- (void)addColor:(OQColor *)color replacingRecentlyAdded:(BOOL)replacingRecentlyAdded;
//- (OUIColorSwatch *)swatchForColor:(OQColor *)color;


@end
