// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class UIToolbar;

@interface OUIDocumentPickerView : UIView
{
@private
    UIToolbar *_bottomToolbar;
    BOOL _bottomToolbarHidden;
}

@property(nonatomic,retain) IBOutlet UIToolbar *bottomToolbar;

@property(nonatomic,assign) BOOL bottomToolbarHidden;
- (void)setBottomToolbarHidden:(BOOL)bottomToolbarHidden animated:(BOOL)animated;

@end
