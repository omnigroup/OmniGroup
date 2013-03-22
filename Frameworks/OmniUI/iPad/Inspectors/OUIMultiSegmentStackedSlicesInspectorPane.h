// Copyright 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIStackedSlicesInspectorPane.h>

@interface OUIInspectorSegment : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSArray *slices;
@end

@interface OUIMultiSegmentStackedSlicesInspectorPane : OUIStackedSlicesInspectorPane

@property(nonatomic,readonly) UISegmentedControl *titleSegmentedControl;
@property(nonatomic,retain) NSArray *segments;
@property(nonatomic,retain) OUIInspectorSegment *selectedSegment;

- (NSArray *)makeAvailableSegments; // For subclasses

@end
