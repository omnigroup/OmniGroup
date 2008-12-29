// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMatrix.h>

#import <OmniFoundation/OFNull.h>

RCS_ID("$Id$")

@implementation OFMatrix;

static OFNull *null;

+ (void)initialize;
{
    OBINITIALIZE;

    null = [[OFNull nullObject] retain];
}

- init;
{
    if (![super init])
	return nil;

    rows = [[NSMutableArray alloc] initWithCapacity:0];
    rowCount = 0;
    columnCount = 0;
    rowTemplate = [[NSMutableArray alloc] initWithCapacity:0];

    return self;
}

- (void)dealloc;
{
    [rows release];
    [rowTemplate release];
    [super dealloc];
}

- (void)expandColumnsToCount:(unsigned int)count;
{
    NSEnumerator *rowEnumerator;
    NSMutableArray *row;

    if (count <= columnCount)
        return;
    
    // Expand the template, too
    [rows addObject:rowTemplate];
    rowEnumerator = [rows objectEnumerator];
    while ((row = [rowEnumerator nextObject])) {
	unsigned int columnsRemaining;

	columnsRemaining = count - columnCount;
	while (columnsRemaining--)
	    [row addObject:null];
    }
    // OK, remove that template
    [rows removeLastObject];

    columnCount = count;
}

- (void)expandRowsToCount:(unsigned int)count;
{
    unsigned int rowsRemaining;

    if (count <= rowCount)
        return;

    rowsRemaining = count - rowCount;
    while (rowsRemaining--) {
	NSMutableArray *newRow;

	newRow = [rowTemplate mutableCopy];
	[rows addObject:newRow];
	[newRow release];
    }
    rowCount = count;
}

- (id)objectAtRowIndex:(unsigned int)rowIndex columnIndex:(unsigned int)columnIndex;
{
    id anObject;

    if (columnIndex >= columnCount || rowIndex >= rowCount)
	return nil;
    anObject = [[rows objectAtIndex:rowIndex]
		objectAtIndex:columnIndex];
    if ([anObject isNull])
	return nil;
    return anObject;
}

- (void)setObject:(id)anObject atRowIndex:(unsigned int)rowIndex columnIndex:(unsigned int)columnIndex;
{
    if (columnIndex >= columnCount)
	[self expandColumnsToCount:columnIndex + 1];
    if (rowIndex >= rowCount)
	[self expandRowsToCount:rowIndex + 1];
    if (!anObject)
	anObject = null;
    [[rows objectAtIndex:rowIndex] replaceObjectAtIndex:columnIndex withObject:anObject];
}

- (void)setObject:(id)anObject atRowIndex:(unsigned int)rowIndex span:(unsigned int)rowSpan columnIndex:(unsigned int)columnIndex span:(unsigned int)columnSpan;
{
    unsigned int aRow, aColumn;

    for (aRow = rowIndex + rowSpan; aRow > rowIndex; aRow--)
        for (aColumn = columnIndex + columnSpan; aColumn > columnIndex; aColumn--)
            [self setObject:anObject atRowIndex:aRow - 1 columnIndex:aColumn - 1];
}

- (unsigned int)rowCount;
{
    return rowCount;
}

- (unsigned int)columnCount;
{
    return columnCount;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    [debugDictionary setObject:rows forKey:@"objects"];
    [debugDictionary setObject:[NSString stringWithFormat:@"%d", rowCount]
     forKey:@"_rowCount"];
    [debugDictionary setObject:[NSString stringWithFormat:@"%d", columnCount]
     forKey:@"_columnCount"];

    return debugDictionary;
}

@end
