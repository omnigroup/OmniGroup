// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIControl.h>

@class OUISegmentedControlButton;

@interface OUISegmentedControl : UIControl

+ (CGFloat)buttonHeight;

- (OUISegmentedControlButton *)addSegmentWithImage:(UIImage *)image representedObject:(id)representedObject;
- (OUISegmentedControlButton *)addSegmentWithImage:(UIImage *)image;
- (OUISegmentedControlButton *)addSegmentWithText:(NSString *)text representedObject:(id)representedObject;
- (OUISegmentedControlButton *)addSegmentWithText:(NSString *)text;
- (void)removeAllSegments;

@property(assign,nonatomic) BOOL sizesSegmentsToFit;

@property(assign,nonatomic) BOOL allowsMultipleSelection;
@property(assign,nonatomic) BOOL allowsEmptySelection;

@property(nonatomic,strong) OUISegmentedControlButton *selectedSegment;
@property(readonly,nonatomic) OUISegmentedControlButton *firstSegment;
@property(nonatomic) NSInteger selectedSegmentIndex;
@property (nonatomic, copy) NSIndexSet *selectedSegmentsIndexSet;

@property(nonatomic,readonly) NSUInteger segmentCount;
- (NSUInteger)indexOfSegment:(OUISegmentedControlButton *)segment;
- (OUISegmentedControlButton *)segmentAtIndex:(NSUInteger)segmentIndex;
- (OUISegmentedControlButton *)segmentWithRepresentedObject:(id)object;
@property(nonatomic, strong) UIFont *segmentFont;

@end
