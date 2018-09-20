// Copyright 2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSArrayController-OAExtensions.h>

RCS_ID("$Id$");

@implementation NSArrayController (OAExtensions)

- (void)moveObjectsAtArrangedObjectIndexes:(NSIndexSet *)rowIndexes toArrangedObjectIndex:(NSInteger)row;
{
    NSArray *movingObjects = [[self arrangedObjects] objectsAtIndexes:rowIndexes];
    
    // adjust the drop row by the number of movingObjects above it.
    __block NSInteger dropRow = row;
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger sourceRow, BOOL * _Nonnull stop) {
        if (sourceRow < (NSUInteger)row)
            dropRow--;
        else
            *stop = YES;
    }];
    
    [self removeObjectsAtArrangedObjectIndexes:rowIndexes];
    [self insertObjects:movingObjects atArrangedObjectIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(dropRow, movingObjects.count)]];
}

@end
