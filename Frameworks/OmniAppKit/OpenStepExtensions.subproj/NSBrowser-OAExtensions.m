// Copyright 1997-2005, 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSBrowser-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation NSBrowser (OAExtensions)

- (NSString *)pathToCurrentItem;
{
    NSBrowserCell *aCell = [self selectedCell];
    if (!aCell)
	return @"";
    
    return [NSString stringWithFormat:@"%@/%@", [self pathToColumn:[self lastColumn]], [aCell stringValue]];
}

- (NSString *)pathToNextItem;
{
    NSInteger column = [self selectedColumn];
    if (column == -1)
	return @"";
    
    NSMatrix *aMatrix = [self matrixInColumn:column];
    NSInteger numRows = [aMatrix numberOfRows];
    NSInteger row = [aMatrix selectedRow] + 1;
    if (row >= numRows)
	return nil;
    return [NSString stringWithFormat:@"%@/%@", [self pathToColumn:column],
        [[aMatrix cellAtRow:row column:0] stringValue]];
}

- (NSString *)pathToPreviousItem;
{
    NSInteger column = [self selectedColumn];
    if (column == -1)
	return @"";
    
    NSMatrix *aMatrix = [self matrixInColumn:column];
    NSArray *selectedCells = [self selectedCells];

    NSInteger row, dummy;
    if (selectedCells)
	[aMatrix getRow:&row column:&dummy ofCell:[selectedCells objectAtIndex:0]];
    else  // does not return list if only 1 selected? (or set to allow only 1?)
	row = [aMatrix selectedRow];
    row--;
    if (row < 0)
	return nil;
    return [NSString stringWithFormat:@"%@/%@", [self pathToColumn:column],
        [[aMatrix cellAtRow:row column:0] stringValue]];
}

- (NSString *)pathToNextOrPreviousItem;
{
    NSString *path = [self pathToNextItem];
    if (!path)
	path = [self pathToPreviousItem];
    if (!path)
	path = [self pathToCurrentItem];
    
    return path;
}

- (NSString *)pathToCurrentColumn;
{
    return [self pathToColumn:[self lastColumn]];
}

- (id)cellAtPoint:(NSPoint) point;
{
    NSInteger firstColumn = [self firstVisibleColumn];
    NSInteger lastColumn = [self lastVisibleColumn];
    
    for (NSInteger column = firstColumn; column <= lastColumn; column++) {
        NSRect columnFrame = [self frameOfInsideOfColumn: column];
        if (NSPointInRect(point, columnFrame)) {
            NSInteger matrixRow, matrixColumn;
            
            NSMatrix *matrix = [self matrixInColumn: column];
            NSPoint localPoint = [matrix convertPoint:point fromView:self];
            if ([matrix getRow:&matrixRow column:&matrixColumn forPoint:localPoint])
                return [matrix cellAtRow:matrixRow column:matrixColumn];
            return nil;
        }
    }
    
    return nil;
}

@end
