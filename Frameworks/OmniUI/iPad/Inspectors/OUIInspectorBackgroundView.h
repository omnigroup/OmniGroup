// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

@interface OUIInspectorBackgroundView : UIView
/// Label has constrains which keep it both horizontally and vertically centered within the OUIInspectorBackgroundView. By default, this label will have the OUILabelStyleInspectorSliceInstructionText style applied.
@property (nonatomic, strong, readonly) UILabel *label;

- (UIColor *)inspectorBackgroundViewColor;
@end

@interface UIView (OUIInspectorBackgroundView)
- (void)containingInspectorBackgroundViewColorChanged;
@end
