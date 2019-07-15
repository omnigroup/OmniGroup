// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIScrollView.h>
#import <OmniFoundation/OFExtent.h>

@class OUIScalingScrollView;

@protocol OUIScalingScrollViewDelegate <UIScrollViewDelegate>

@required
- (CGRect)scalingScrollViewContentViewFullScreenBounds:(OUIScalingScrollView *)scalingScrollView;
- (CGFloat)scrollBufferAsPercentOfViewportSize;
- (CGSize)unscaledContentSize;

@optional
- (void)scrollViewDidChangeFrame;

@end

@interface OUIScalingScrollView : UIScrollView

@property(readonly) CGSize scrollBufferSize;
- (CGSize)preferredScrollBufferSizeForScale:(CGFloat)scale; // for subclasses to override if needed
@property(nonatomic) OFExtent allowedEffectiveScaleExtent;
@property(nonatomic) BOOL centerContent;
@property(nonatomic) UIEdgeInsets minimumInsets;
@property(nonatomic) CGFloat temporaryBottomInset;

@property (nonatomic, assign) id<OUIScalingScrollViewDelegate> delegate;  // We'd like this to be weak, but the superclass declares it 'assign'.

- (CGFloat)fullScreenScaleForUnscaledContentSize:(CGSize)unscaledContentSize;

- (void)adjustScaleTo:(CGFloat)effectiveScale unscaledContentSize:(CGSize)unscaledContentSize;
- (void)adjustContentInsetAnimated:(BOOL)animated;

@end
