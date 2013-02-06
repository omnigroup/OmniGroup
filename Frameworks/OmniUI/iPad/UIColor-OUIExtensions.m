// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIColor-OUIExtensions.h>

RCS_ID("$Id$");

@implementation UIColor (OUIExtensions)

+ (UIColor *)tabViewBackgroundColor;
{
    static UIColor *_tabViewBackgroundColor;
    if (_tabViewBackgroundColor == nil)
    	_tabViewBackgroundColor = [[UIColor colorWithRed:0.875 green:0.886 blue:0.906 alpha:1.0] retain];

    return _tabViewBackgroundColor;
}

@end
