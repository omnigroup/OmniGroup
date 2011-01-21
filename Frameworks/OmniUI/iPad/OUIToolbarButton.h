// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIButton.h>
#import <OmniUI/OUIBarButtonItemBackgroundType.h>

@interface OUIToolbarButton : UIButton

+ (UIImage *)normalBackgroundImage;
+ (UIImage *)highlightedBackgroundImage;

+ (CGFloat)leftImageStretchCapForBackgroundType:(OUIBarButtonItemBackgroundType)backgroundType;
- (void)configureForBackgroundType:(OUIBarButtonItemBackgroundType)backgroundType;

- (void)setNormalBackgroundImage:(UIImage *)image;
- (void)setHighlightedBackgroundImage:(UIImage *)image;

@end
