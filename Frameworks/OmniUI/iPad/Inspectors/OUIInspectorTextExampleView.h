// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class OQColor;
@class NSAttributedString;
@class OUITextLayout, OUIGradientView;

@interface OUIInspectorTextExampleView : UIView
{
@private
    OUITextLayout *_textLayout;
    OUIGradientView *_bottomGradientView;
}

@property(nonatomic,copy) OQColor *styleBackgroundColor;
@property(nonatomic,copy) NSAttributedString *attributedString;

@end
