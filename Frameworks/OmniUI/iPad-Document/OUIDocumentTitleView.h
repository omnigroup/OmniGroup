// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

@class OFXAccountActivity;

@protocol OUIDocumentTitleViewDelegate;

@interface OUIDocumentTitleView : UIView

@property (nonatomic, weak) id<OUIDocumentTitleViewDelegate> delegate;

@property (nonatomic, strong) OFXAccountActivity *syncAccountActivity;

@property (nonatomic, copy) NSString *title;
@property (nonatomic,strong) UIColor *titleColor;
@property (nonatomic, assign) BOOL titleCanBeTapped;
@property (nonatomic, assign) BOOL hideTitle;
@property (nonatomic, assign) BOOL hideSyncButton;

@property (nonatomic, readonly, strong) UIButton *closeDocumentButton;
@property (nonatomic, assign) BOOL shouldShowCloseDocumentButton;

@property (nonatomic, readonly, strong) UIBarButtonItem *closeDocumentBarButtonItem;
@property (nonatomic, readonly, strong) UIBarButtonItem *syncBarButtonItem;

@end

@protocol OUIDocumentTitleViewDelegate <NSObject>

@optional
- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView syncButtonTapped:(id)sender;
- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView titleTapped:(id)sender;

@end
