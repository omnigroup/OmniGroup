// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorPane.h>

@interface OUIStackedSlicesInspectorPane : OUIInspectorPane
{
@private
    CGFloat _topEdgePadding;
    NSArray *_slices;
}

@property(nonatomic,assign) CGFloat topEdgePadding;
@property(nonatomic,copy) NSArray *slices; // Managed by the OUIInspector.

- (void)inspectorSizeChanged;

@end

