// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUIDocument/OUIDocumentPickerBackgroundView.h>

@interface OUIMainViewControllerBackgroundView : OUIDocumentPickerBackgroundView
{
@private
    UIToolbar *_toolbar;
    UIView *_contentView;
    CGFloat _avoidedBottomHeight;
}

@property(nonatomic,strong) UIToolbar *toolbar;
@property(nonatomic,readonly) UIView *contentView;

@property(nonatomic,assign) CGFloat avoidedBottomHeight; // Used for OUIToolbarContentController's keyboard avoidance. Set to zero to use all available height.

- (CGRect)contentViewFullScreenBounds;  // used when scaling to the full screen but keyboard is visible

@end
