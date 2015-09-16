// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class OAColor;
@class NSAttributedString;

@interface OUIInspectorTextExampleView : UIView

@property(nonatomic,copy) OAColor *styleBackgroundColor;
@property(nonatomic,copy) NSAttributedString *attributedString;

@end
