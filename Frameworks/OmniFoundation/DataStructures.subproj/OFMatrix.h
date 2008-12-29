// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFMatrix.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSMutableArray;

@interface OFMatrix : OFObject
{
    NSMutableArray *rows;
    unsigned int rowCount, columnCount;
    NSMutableArray *rowTemplate;
}

- (id)objectAtRowIndex:(unsigned int)rowIndex columnIndex:(unsigned int)columnIndex;
- (void)setObject:(id)anObject atRowIndex:(unsigned int)rowIndex columnIndex:(unsigned int)columnIndex;
- (void)setObject:(id)anObject atRowIndex:(unsigned int)rowIndex span:(unsigned int)rowSpan columnIndex:(unsigned int)columnIndex span:(unsigned int)columnSpan;
- (unsigned int)rowCount;
- (unsigned int)columnCount;
- (void)expandColumnsToCount:(unsigned int)count;
- (void)expandRowsToCount:(unsigned int)count;

@end
