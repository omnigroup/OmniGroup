// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIControl.h>

@class OUIInspectorSegmentedControlButton;

typedef enum {
    OUIInspectorSegmentButtonLeft,
    OUIInspectorSegmentButtonCenter,
    OUIInspectorSegmentButtonRight,
} OUIInspectorSegmentButtonPosition;

@interface OUIInspectorSegmentedControl : UIControl
{
@private
    NSMutableArray *_segments;
    BOOL _allowsMulitpleSelection;
    BOOL _allowsEmptySelection;
    BOOL _sizesSegmentsToFit;
    BOOL _dark;
}

+ (CGFloat)buttonHeight;

- (OUIInspectorSegmentedControlButton *)addSegmentWithImageNamed:(NSString *)imageName representedObject:(id)representedObject;
- (OUIInspectorSegmentedControlButton *)addSegmentWithImageNamed:(NSString *)imageName;
- (OUIInspectorSegmentedControlButton *)addSegmentWithText:(NSString *)text representedObject:(id)representedObject;
- (OUIInspectorSegmentedControlButton *)addSegmentWithText:(NSString *)text;

@property(assign,nonatomic) BOOL sizesSegmentsToFit;

@property(assign,nonatomic) BOOL allowsMulitpleSelection;
@property(assign,nonatomic) BOOL allowsEmptySelection;

@property(assign,nonatomic) OUIInspectorSegmentedControlButton *selectedSegment;
@property(readonly,nonatomic) OUIInspectorSegmentedControlButton *firstSegment;
@property(nonatomic) NSInteger selectedSegmentIndex;

@property(nonatomic,readonly) NSUInteger segmentCount;
- (OUIInspectorSegmentedControlButton *)segmentAtIndex:(NSUInteger)segmentIndex;
- (OUIInspectorSegmentedControlButton *)segmentWithRepresentedObject:(id)object;
- (void)setSegmentFont:(UIFont *)font;

@property(nonatomic) BOOL dark;

@end
