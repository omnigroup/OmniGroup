// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UICollectionViewCell.h>

@class ODSScope;
@class OUIDocumentPicker, OUIDocumentPickerFilter;

@interface OUIDocumentPickerHomeScreenCell : UICollectionViewCell
@property (nonatomic, retain) IBOutlet UILabel *textLabel;
@property (nonatomic, retain) ODSScope *scope;
@property (nonatomic, retain) OUIDocumentPicker *picker;
@property (readonly,nonatomic) OUIDocumentPickerFilter *documentFilter;

@property (nonatomic, retain) IBOutlet UIView *coverView;

@property (nonatomic, retain) IBOutlet UILabel *countLabel;
@property (nonatomic, retain) IBOutlet UILabel *dateLabel;

@property (nonatomic, retain) IBOutlet UIImageView *preview1;
@property (nonatomic, retain) IBOutlet UIImageView *preview2;
@property (nonatomic, retain) IBOutlet UIImageView *preview3;
@property (nonatomic, retain) IBOutlet UIImageView *preview4;
@property (nonatomic, retain) IBOutlet UIImageView *preview5;
@property (nonatomic, retain) IBOutlet UIImageView *preview6;

- (void)resortPreviews;
- (UIImage *)_generateOverflowImageWithCount:(NSUInteger)count;
- (CGRect)_rectForMiniTile:(NSUInteger)index inRect:(CGRect)rect;

@property (readonly) NSArray *itemsForPreviews;
@property (readonly) NSArray *previewViews;

@end
