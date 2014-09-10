// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

typedef enum {
    OUIButtonGridViewBorderNone,
    OUIButtonGridViewBorderTop = 0x1,
    OUIButtonGridViewBorderBottom = 0x2
} OUIButtonGridViewBorder;

@class OUIButtonGridView;

@protocol OUIButtonGridViewDataSource <NSObject>

@required

- (NSUInteger)buttonGridView:(OUIButtonGridView *)buttonGridView numberOfColumnsInRow:(NSInteger)row;
- (UIButton *)buttonGridView:(OUIButtonGridView *)buttonGridView buttonForColumnAtIndexPath:(NSIndexPath *)indexPath;
- (NSUInteger)numberOfRowsInButtonGridView:(OUIButtonGridView *)buttonGridView;

- (void)buttonGridView:(OUIButtonGridView *)buttonGridView tappedButton:(UIButton *)button atIndexPath:(NSIndexPath *)indexPath;

@end

#pragma mark

@interface OUIButtonGridView : UIView

+ (UIButton *)buttonGridViewButtonWithTitle:(NSString *)title;

@property (nonatomic, assign) IBOutlet id <OUIButtonGridViewDataSource> dataSource;
@property (nonatomic, assign) NSUInteger borderMask;

- (UIButton *)buttonAtIndexPath:(NSIndexPath *)indexPath;

// Currently exposed for AX purposes only.
@property (nonatomic, readonly, copy) NSArray *buttons;

@end

#pragma mark


// This category provides convenience methods to make it easier to use an NSIndexPath to represent rows with columns

@interface NSIndexPath (OUIButtonGridViewDataSource)

+ (NSIndexPath *)indexPathForButtonGridViewColumn:(NSInteger)column inButtonGridViewRow:(NSInteger)row;

@property(nonatomic, readonly) NSInteger buttonGridViewRow;
@property(nonatomic, readonly) NSInteger buttonGridViewColumn;

@end
