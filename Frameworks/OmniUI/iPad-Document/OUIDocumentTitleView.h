// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

@protocol OUIDocumentTitleViewDelegate;

@interface OUIDocumentTitleView : UIView

@property (nonatomic, weak) id<OUIDocumentTitleViewDelegate> delegate;

@property (nonatomic, copy) NSString *title;
@property (nonatomic,strong) UIColor *titleColor;
@property (nonatomic, assign) BOOL titleCanBeTapped;
@property (nonatomic, assign) BOOL hideTitle;

@property (nonatomic, readonly, strong) UIButton *closeDocumentButton;
@property (nonatomic, assign) BOOL shouldShowCloseDocumentButton;

@property (nonatomic, readonly, strong) UIBarButtonItem *closeDocumentBarButtonItem;

@end

@protocol OUIDocumentTitleViewDelegate <NSObject>

@optional
- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView titleTapped:(id)sender OB_DEPRECATED_ATTRIBUTE;

@end
