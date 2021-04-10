// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUILabeledValueCell : UIView

+ (UIFont *)labelFont;
+ (UIFont *)valueFont;

+ (UIColor *)labelColorForHighlighted:(BOOL)highlighted;
+ (UIColor *)valueColorForHighlighted:(BOOL)highlighted;

@property (nonatomic) CGFloat minimumLabelWidth;
@property (nonatomic) BOOL usesActualLabelWidth;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) NSTextAlignment labelAlignment;
@property (nonatomic, nullable, copy) NSString *value;
@property (nonatomic, nullable, copy) NSString *valuePlaceholder;
@property (nonatomic, getter=isHighlighted) BOOL highlighted;

- (void)labelChanged;

- (CGRect)labelFrameInRect:(CGRect)bounds;
- (CGRect)valueFrameInRect:(CGRect)bounds;

@property(nonatomic,assign) BOOL valueHidden;

/*!
 * @description Convenience for calling -[UIView-OUIExtensions containingViewMatching:]
 * @return Returns the UITableView that contains the view.
 */
- (UITableView *)containingTableView;

/*!
 * @description Convenience for calling -[UIView-OUIExtensions containingViewMatching:]
 * @return Returns the UITableViewCell that contains the view.
 */
- (UITableViewCell *)containingTableViewCell;

@end

NS_ASSUME_NONNULL_END
