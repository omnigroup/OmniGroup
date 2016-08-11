// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAutosizingSegmentedControl.h>

RCS_ID("$Id$");

@implementation OAAutosizingSegmentedControl

- (void)setFrameSize:(NSSize)newSize;
{
    [super setFrameSize:newSize];
    
    NSUInteger segmentCount = self.segmentCount;
    double segmentWidth = self.frame.size.width/segmentCount - 2;
    
    for (NSUInteger segmentIndex = 0; segmentIndex < segmentCount; segmentIndex++) {
        [self setWidth:segmentWidth forSegment:segmentIndex];
    }
}

@end
