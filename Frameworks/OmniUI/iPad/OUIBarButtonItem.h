// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIBarButtonItem.h>

@class OUIToolbarButton;

@interface OUIBarButtonItem : UIBarButtonItem

+ (id)spacerWithWidth:(CGFloat)width;

+ (Class)buttonClass;
+ (NSSet *)possibleTitlesForEditBarButtonItems;
+ (NSString *)titleForEditButtonBarSystemItem:(UIBarButtonSystemItem)systemItem;

- initWithTintColor:(UIColor *)tintColor image:(UIImage *)image title:(NSString *)title target:(id)target action:(SEL)action;

@property(readonly,nonatomic) OUIToolbarButton *button; // Just returns the custom view, but typed more nicely.

@end
