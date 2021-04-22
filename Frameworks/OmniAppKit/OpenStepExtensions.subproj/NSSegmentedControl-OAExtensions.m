// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSSegmentedControl-OAExtensions.h>

#import <AppKit/AppKit.h>

@implementation NSSegmentedControl (OAExtensions)

- (NSInteger)oa_segmentForTag:(NSInteger)tag;
{
    NSSegmentedCell *cell = (NSSegmentedCell *)([self cell]);
    return [cell oa_segmentForTag:tag];
}

- (NSInteger)oa_selectedTag;
{
    if (self.selectedSegment == -1) {
        return NSNotFound;
    }
    NSSegmentedCell *cell = (NSSegmentedCell *)([self cell]);
    return [cell tagForSegment:self.selectedSegment];
}

- (void)oa_deselectAll;
{
    NSSegmentedCell *cell = (NSSegmentedCell *)([self cell]);
    [cell oa_deselectAll];
}

@end

@implementation NSSegmentedCell (OOExtensions)

- (NSInteger)oa_segmentForTag:(NSInteger)tag;
{
    for (NSInteger i = 0; i < self.segmentCount; i++) {
        NSInteger oneTag = [self tagForSegment:i];
        if (oneTag == tag) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)oa_setToolTip:(NSString *)toolTip forTag:(NSInteger)tag;
{
    NSInteger segment = [self oa_segmentForTag:tag];
    if (segment != NSNotFound) {
        [self setToolTip:toolTip forSegment:segment];
    }
}

- (void)oa_deselectAll;
{
    for (NSInteger i = 0; i < self.segmentCount; i++) {
        [self setSelected:NO forSegment:i];
    }
}

- (BOOL)oa_selectedForTag:(NSInteger)tag;
{
    NSInteger segment = [self oa_segmentForTag:tag];
    if (segment == NSNotFound) {
        return NO;
    }
    return [self isSelectedForSegment:segment];
}

- (void)oa_setSelected:(BOOL)selected forTag:(NSInteger)tag;
{
    NSInteger segment = [self oa_segmentForTag:tag];
    if (segment == NSNotFound) {
        return;
    }
    [self setSelected:selected forSegment:segment];
}

@end
