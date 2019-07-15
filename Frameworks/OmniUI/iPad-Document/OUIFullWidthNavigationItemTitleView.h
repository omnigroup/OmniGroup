// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

/*!
 * @class OUINavigationItemTitleView
 * @brief The OUINavigationItemTitleView's only purpose is to take up all available space as a UINavigationItem's titleView.
 * @details OUINavigationItemTitleView overrides -sizeThatFits: to pass back the size passed into it. By doing this, it's telling the UINavigationBar that it would like to be as big as possible. Later, if the UINavigationBar decides this is too big (maybe the user has set some navigation items) the UINavigationBar will resize us to an appropriate size. This will happen before -layoutSubviews is called.
 */
@interface OUIFullWidthNavigationItemTitleView : UIView

@end
