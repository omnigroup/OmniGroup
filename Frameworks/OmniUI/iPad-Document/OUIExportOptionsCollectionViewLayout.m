// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsCollectionViewLayout.h"

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@interface OUIExportOptionsCollectionViewLayout ()

@property NSMutableArray *itemAttributes;
@property CGSize contentSize;
@end

@implementation OUIExportOptionsCollectionViewLayout

- (CGSize)collectionViewContentSize;
{
    return self.contentSize;
}

- (nullable NSArray *)layoutAttributesForElementsInRect:(CGRect)rect;
{
    return [self.itemAttributes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UICollectionViewLayoutAttributes *evaluatedObject, NSDictionary *bindings) {
        return CGRectIntersectsRect(rect, [evaluatedObject frame]);
    }]];
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath;
{
    return [self.itemAttributes objectAtIndex:[indexPath indexAtPosition:1]];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds;
{
    return YES;
}

- (void)prepareLayout;
{
    self.itemAttributes = [[NSMutableArray alloc] init];

    // (# of items * width of item) + ((# of items + 1) * min spacing) < maxWidth
    NSUInteger numberOfColumns = 0;

    CGFloat itemWidth = 128.0; // magic number. you should change
    CGFloat itemHeight = 136.0; // magic number you should change
    CGRect layoutFrame = self.collectionView.layoutMarginsGuide.layoutFrame;
    CGFloat maxWidth = layoutFrame.size.width;
    CGFloat currentWidth = self.minimumInterItemSpacing; // lets add leading space to start with
    CGFloat widthToAdd = itemWidth + self.minimumInterItemSpacing;

    while (currentWidth < maxWidth) {
        currentWidth += widthToAdd;
        if (currentWidth > maxWidth)
            break;
        numberOfColumns++;
    }

    CGFloat extraWidth = maxWidth - (currentWidth - widthToAdd); // we know we've overshot, so step back 1 column's worth
    CGFloat actualInterItemSpacing = self.minimumInterItemSpacing + extraWidth / (numberOfColumns + 1);

    NSUInteger numberOfItems = [self.collectionView numberOfItemsInSection:0];
    NSUInteger currentColumn = 0;

    CGFloat currentYPosition = 8;
    CGFloat currentXPosition = 8;

    for (NSUInteger index = 0; index < numberOfItems; index++) {
        UICollectionViewLayoutAttributes *newAttributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:[[NSIndexPath indexPathWithIndex:0] indexPathByAddingIndex:index]];
        newAttributes.frame = CGRectMake(floor(currentXPosition), floor(currentYPosition), floor(itemWidth), floor(itemHeight));
        currentColumn++;

        if (currentColumn < numberOfColumns) { // if we're not ready to wrap
            currentXPosition += actualInterItemSpacing + itemWidth;
        } else {
            currentColumn = 0;
            currentXPosition = CGRectGetMinX(layoutFrame); // left edge of the first column
            currentYPosition += actualInterItemSpacing + itemHeight;
        }

        self.itemAttributes[index] = newAttributes;
    }

    currentYPosition += itemHeight; // we need to add another cell height to include the height of the last row in the content size. the Y-position is the top of the row we're adding items into, but the content size needs to include the height of that cell.

    self.contentSize = CGSizeMake(maxWidth, currentYPosition);

#if 0 && defined(DEBUG_rachael)
    NSLog(@"item attributes = %@", self.itemAttributes);
    NSLog(@"contentSize = %@", NSStringFromCGSize(self.contentSize));
#endif
}

@end

NS_ASSUME_NONNULL_END
