// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITableViewCell.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 SettingsButtonTableViewCell is a convenience UITableViewCell subclass that takes on some of the appearance of a button. It is intended for use in settings-like table views, usually in the grouped style, to offer users a call to action (e.g. "Learn More").
 
 Instances of this cell implement the textLabel property to vend the primary label it manages, so the "button" text can be changed through the `textLabel.text` property. The tint color may be changed using the `textColor` and/or `useTintColor` properties. Instances may be registered and created through a table's reuse queue, or created directly within each client's implementation of `-tableView:cellForRowAtIndexPath:`.
 */
@interface OUISettingsButtonTableViewCell : UITableViewCell

+ (instancetype)dequeueButtonTableViewCellFromTable:(UITableView *)tableView withLabelText:(NSString *)text NS_SWIFT_NAME(dequeueButtonTableViewCell(from:labelText:));
- (instancetype)initWithLabelText:(NSString *)text;

@property (nonatomic, readonly, class) UIColor *defaultTextColor;
@property (nonatomic, readonly, class) UIFont *defaultFont;

/// Set this property to customize the color of the label text. If this is nil (the default), and `useTintColor` is NO, the label will use `OUISettingsButtonTableViewCell.defaultTextColor` for its text.
@property (nonatomic, copy, nullable) UIColor *textColor;

/// Forces the cell to use its `UIView.tintColor`, overriding `textColor` if set. Defaults to NO.
@property (nonatomic) BOOL useTintColor;

/// Informs the cell that it should reapply appearance properties to its private subviews.
- (void)setNeedsAppearanceUpdate;

@end

NS_ASSUME_NONNULL_END
