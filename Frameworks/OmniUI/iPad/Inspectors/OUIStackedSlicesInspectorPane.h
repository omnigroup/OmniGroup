// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorPane.h>

@class OUIInspectorSlice;

@interface OUIStackedSlicesInspectorPane : OUIInspectorPane
{
@private
    NSArray *_availableSlices;
    NSArray *_slices;
}

- (NSArray *)makeAvailableSlices; // For subclasses (though the delegate hook can also be used)
@property(nonatomic,copy) NSArray *availableSlices; // All the possible slices. Will get narrowed by applicability.

- (void)sliceSizeChanged:(OUIInspectorSlice *)slice;

@end
