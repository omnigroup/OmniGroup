// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIFont.h>

@interface UIFont (OUIExtensions)

+ (UIFont *)mediumSystemFontOfSize:(CGFloat)size NS_DEPRECATED_IOS(8_2, 8_2, "Use +systemFontOfSize:weight: instead.");
+ (UIFont *)lightSystemFontOfSize:(CGFloat)size NS_DEPRECATED_IOS(8_2, 8_2, "Use +systemFontOfSize:weight: instead.");

+ (UIFont *)preferredItalicFontForTextStyle:(NSString *)style NS_REFINED_FOR_SWIFT;
+ (UIFont *)preferredBoldFontForTextStyle:(NSString *)style NS_REFINED_FOR_SWIFT;

- (UIFont *)fontByAddingProportionalNumberAttributes; // already default on iOS 9+
- (UIFont *)fontByAddingMonospacedNumberAttributes;
- (UIFont *)fontByAddingTimeAttributes;

@end
