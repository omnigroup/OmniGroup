// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class OFXAccountActivity;

@protocol OUIDocumentTitleViewDelegate;

@interface OUIDocumentTitleView : UIView

@property (nonatomic, weak) id<OUIDocumentTitleViewDelegate> delegate;

@property (nonatomic, strong) OFXAccountActivity *syncAccountActivity;

@property (nonatomic, copy) NSString *title;
@property UIColor *titleColor;
@property BOOL titleCanBeTapped;
@property BOOL hideTitle;

@property (nonatomic, strong) UIBarButtonItem *syncBarButtonItem;

@end

@protocol OUIDocumentTitleViewDelegate <NSObject>

@optional
- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView syncButtonTapped:(id)sender;
- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView titleTapped:(id)sender;

@end
