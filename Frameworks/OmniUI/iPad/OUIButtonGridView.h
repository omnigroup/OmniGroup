// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, OUIButtonGridViewBorder) {
    OUIButtonGridViewBorderNone,
    OUIButtonGridViewBorderTop = 0x1,
    OUIButtonGridViewBorderBottom = 0x2
};

@class OUIButtonGridView;

@protocol OUIButtonGridViewDataSource <NSObject>

@required

- (NSUInteger)buttonGridView:(OUIButtonGridView *)buttonGridView numberOfColumnsInRow:(NSInteger)row;
- (UIButton *)buttonGridView:(OUIButtonGridView *)buttonGridView buttonForIndexPath:(NSIndexPath *)indexPath;
- (NSUInteger)numberOfRowsInButtonGridView:(OUIButtonGridView *)buttonGridView;

- (void)buttonGridView:(OUIButtonGridView *)buttonGridView tappedButton:(UIButton *)button atIndexPath:(NSIndexPath *)indexPath;

@end

#pragma mark

@interface OUIButtonGridView : UIView

+ (UIButton *)buttonGridViewButtonWithTitle:(NSString *)title;

@property (nonatomic, assign, nullable) IBOutlet id <OUIButtonGridViewDataSource> dataSource;
@property (nonatomic, assign) OUIButtonGridViewBorder borderMask;
@property (nonatomic, copy, nullable) UIColor *buttonSeparatorStrokeColor;

- (nullable UIButton *)buttonAtIndexPath:(NSIndexPath *)indexPath;

@property (nonatomic, readonly, copy, nullable) NSArray <UIButton *> *buttons;

@end

#pragma mark


// This category provides convenience methods to make it easier to use an NSIndexPath to represent rows with columns

@interface NSIndexPath (OUIButtonGridViewDataSource)

+ (NSIndexPath *)indexPathForButtonGridViewColumn:(NSInteger)column inButtonGridViewRow:(NSInteger)row;

@property(nonatomic, readonly) NSInteger buttonGridViewRow;
@property(nonatomic, readonly) NSInteger buttonGridViewColumn;

@end

NS_ASSUME_NONNULL_END
