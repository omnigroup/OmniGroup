// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OUIActivityIndicator : NSObject

+ (OUIActivityIndicator *)showActivityIndicatorInView:(UIView *)view;
+ (OUIActivityIndicator *)showActivityIndicatorInView:(UIView *)view withColor:(UIColor *)color;


/**
 @param view View to insert the activity indicator into
 @param color Color of the activity indicator
 @param bezelColor Color for the bezel. If nil, no bezel will be drawn.
 */
+ (OUIActivityIndicator *)showActivityIndicatorInView:(UIView *)view withColor:(UIColor *)color bezelColor:(UIColor *)bezelColor;

- (void)hide;

@end
