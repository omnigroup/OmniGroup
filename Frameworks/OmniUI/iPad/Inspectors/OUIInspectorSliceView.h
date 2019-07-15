// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>
#import <OmniUI/OUIInspectorSlice.h>


#define DEBUG_OUIINSPECTORSLICEVIEW (0)


@protocol OUIInspectorSliceView
@property(nonatomic,assign) UIEdgeInsets inspectorSliceAlignmentInsets;
@property(nonatomic,assign) OUIInspectorSliceGroupPosition inspectorSliceGroupPosition;
@property(nonatomic,copy) UIColor *inspectorSliceSeparatorColor;
- (CGFloat)inspectorSliceTopBorderHeight;
- (CGFloat)inspectorSliceBottomBorderHeight;
@end


@interface OUIInspectorSliceView : UIView <OUIInspectorSliceView>
+ (instancetype)tableSectionSeparatorView;
@property(nonatomic,retain) UIView *contentView;
#if DEBUG_OUIINSPECTORSLICEVIEW
@property(nonatomic,copy) NSString *debugIdentifier;
#endif // DEBUG_OUIINSPECTORSLICEVIEW
@end


@interface UIView (OUIInspectorSliceExtensions)
@property(nonatomic,readonly) UIEdgeInsets inspectorSliceAlignmentInsets;
@property(nonatomic,readonly) OUIInspectorSliceGroupPosition inspectorSliceGroupPosition;
@property(nonatomic,readonly) UIColor *inspectorSliceSeparatorColor;
- (CGFloat)inspectorSliceTopBorderHeight;
- (CGFloat)inspectorSliceBottomBorderHeight;
- (void)drawInspectorSliceBackground;
- (void)drawInspectorSliceBorder;
@end
