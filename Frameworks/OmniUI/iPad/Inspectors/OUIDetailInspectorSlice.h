// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIActionInspectorSlice.h>

/*
 This class supports a common pattern of having a control in an inspector to tap and expose a detail pane.
 For now this only supports creating the detail pane with a block, but we could add a subclassing point if we ever want to use this on iOS 3.x.
 */

@class OUIDetailInspectorSlice;

typedef OUIInspectorPane *(^OUIDetailInspectorSlicePaneMaker)(OUIDetailInspectorSlice *slice);

@interface OUIDetailInspectorSlice : OUIActionInspectorSlice
{
@private
    OUIDetailInspectorSlicePaneMaker _paneMaker;
}

+ (id)detailLabelWithTitle:(NSString *)title paneMaker:(OUIDetailInspectorSlicePaneMaker)paneMaker;

- initWithTitle:(NSString *)title paneMaker:(OUIDetailInspectorSlicePaneMaker)paneMaker;

@property(nonatomic,copy) OUIDetailInspectorSlicePaneMaker paneMaker;

@end
