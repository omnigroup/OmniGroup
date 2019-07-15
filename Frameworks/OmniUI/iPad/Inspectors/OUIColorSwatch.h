// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>
#import <OmniUI/OUIColorValue.h>

@interface OUIColorSwatch : UIButton <OUIColorValue>

+ (CGSize)swatchSize;
+ (OUIColorSwatch *)navigateToColorPickerSwatch;

- initWithColor:(OAColor *)color;

@property(nonatomic,assign) BOOL showNavigationArrow;

@end
