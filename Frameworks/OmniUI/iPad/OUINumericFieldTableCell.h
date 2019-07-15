// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITableViewCell.h>

#import <OmniUI/OUIThemedTableViewCell.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OUINumericFieldTableCellValueKey;


@interface OUINumericFieldTableCell : OUIThemedTableViewCell

+ (instancetype)numericFieldTableCell NS_SWIFT_NAME(makeNumericFieldTableCell());

/// Opt-in support for dynamic type. (Defaults to NO until all/most of the places we use this want to opt in.)
@property (nonatomic) BOOL supportsDynamicType;

@property (nullable, nonatomic, copy) NSString *labelText;
@property (nonatomic) NSInteger value; // KVO enabled
@property (nonatomic) NSInteger minimumValue;
@property (nonatomic) NSInteger maximumValue;
@property (nonatomic) NSUInteger stepValue; // Increment/decrement by this amount. Default is 1; 0 is not allowed.
@property (nullable, nonatomic, copy) NSString *unitsSuffixStringSingular; // like @"day"
@property (nullable, nonatomic, copy) NSString *unitsSuffixStringPlural; // like @"days"

// Exposed for adjusting font, color, etc. Should generally manipulate values using labelText and value properties
@property (retain, nonatomic) IBOutlet UILabel *label;
@property (retain, nonatomic) IBOutlet UITextField *valueTextField;
@property (retain, nonatomic, readonly) IBOutlet UILabel *editingUnitsLabel;

@end

NS_ASSUME_NONNULL_END
