// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSSegmentedControl.h>
#import <AppKit/NSSegmentedCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSSegmentedControl (OAExtensions)

- (NSInteger)oa_segmentForTag:(NSInteger)tag; // May return NSNotFound.
- (NSInteger)oa_selectedTag; // May return NSNotFound.
- (void)oa_deselectAll;

@end


@interface NSSegmentedCell (OAExtensions)

- (NSInteger)oa_segmentForTag:(NSInteger)tag; // May return NSNotFound.
- (void)oa_setToolTip:(NSString *)toolTip forTag:(NSInteger)tag;

- (void)oa_deselectAll;

- (BOOL)oa_selectedForTag:(NSInteger)tag;
- (void)oa_setSelected:(BOOL)selected forTag:(NSInteger)tag;

@end

NS_ASSUME_NONNULL_END
