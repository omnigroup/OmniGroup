// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <UIKit/UIScrollView.h>
#import <UIKit/UIControl.h>

@class OUIInspectorOptionWheelItem, OUIInspectorOptionWheelSelectionIndicator, OUIInspectorOptionWheelScrollView;

@interface OUIInspectorOptionWheel : UIControl <UIScrollViewDelegate>
{
@private
    OUIInspectorOptionWheelSelectionIndicator *_selectionIndicator;
    OUIInspectorOptionWheelScrollView *_scrollView;
    NSMutableArray *_items;
    OUIInspectorOptionWheelItem *_selectedItem; // might be animating to this, but not there yet
}

- (OUIInspectorOptionWheelItem *)addItemWithImage:(UIImage *)image value:(id)value;
- (OUIInspectorOptionWheelItem *)addItemWithImageNamed:(NSString *)imageName value:(id)value;

@property(copy,nonatomic) NSArray *items;
@property(retain,nonatomic) id selectedValue; // animates
- (void)setSelectedValue:(id)value animated:(BOOL)animated;

@end
