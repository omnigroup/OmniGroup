// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerHomeScreenCell.h>

#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniFoundation/OFBindingPoint.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import "OUIDocument-Internal.h"

#import <OmniUIDocument/OUIDocumentPickerHomeScreenViewController.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import "OUIDocumentParameters.h"
#import <OmniUIDocument/OUIDocumentPickerItemSort.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>

#import <OmniQuartz/CALayer-OQExtensions.h>

RCS_ID("$Id$")

@interface OUIDocumentPickerHomeScreenCell ()
{
    OFSetBinding *_topItemsBinding;
    NSMutableArray *_previewViews;
    NSMutableArray *_itemsForPreviews;
    NSArray *_displayedPreviews;
}

@property (nonatomic, retain) NSSet *fileItems;

@end

@implementation OUIDocumentPickerHomeScreenCell

static NSDateFormatter *dateFormatter;

+ (void)initialize;
{
    OBINITIALIZE;
    
    dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    [dateFormatter setDoesRelativeDateFormatting:YES];
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
    [_topItemsBinding invalidate];
    _topItemsBinding = nil;
    
    for (OUIDocumentPreview *preview in _displayedPreviews)
        [preview decrementDisplayCount];
}

- (void)prepareForReuse;
{
    _textLabel.text = @"";
    _dateLabel.text = @"";
    _countLabel.text = @"";
    _scope = nil;
    
    [super prepareForReuse];
}

- (ODSFileItem *)_preferredVisibleItemFromSet:(NSSet *)set;
{
    for (ODSFileItem *item in _itemsForPreviews)
        if ([set containsObject:item])
            return item;
    return nil;
}

- (NSArray *)_previewedItemsForFolder:(ODSFolderItem *)folder;
{
    OUIDocumentPickerFilter *filter = [OUIDocumentPickerViewController documentFilterForPicker:_picker scope:folder.scope];

    NSSet *filteredItems;
    if (filter)
        filteredItems = [folder.childItems filteredSetUsingPredicate:filter.predicate];
    else
        filteredItems = folder.childItems;
    NSArray *sortedItems = [filteredItems sortedArrayUsingDescriptors:[OUIDocumentPickerViewController sortDescriptors]];
    if (sortedItems.count > 9)
        return [sortedItems subarrayWithRange:NSMakeRange(0, 9)];
    else
        return sortedItems;
}

- (void)_animateNewImage:(UIImage *)image forView:(UIImageView *)view;
{
    if (self.window == nil) {
        view.image = image;
        [_coverView.superview bringSubviewToFront:_coverView];
        return;
    }
    
    UIView *oldView = [view snapshotViewAfterScreenUpdates:YES];
    [UIView performWithoutAnimation:^{
        oldView.frame = view.frame;
        [_coverView.superview insertSubview:oldView belowSubview:_coverView];
        view.image = image;
    }];
    [UIView animateWithDuration:0.5 animations:^{
        oldView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [oldView removeFromSuperview];
        [_coverView.superview bringSubviewToFront:_coverView];
    }];
}

- (void)_previewsUpdateForFileItemNotification:(NSNotification *)notification;
{
    ODSFileItem *item = [notification object];
    
    NSUInteger index = 0;
    for (ODSFolderItem *folder in _itemsForPreviews) {
        if ([folder isKindOfClass:[ODSFolderItem class]] && [[self _previewedItemsForFolder:folder] containsObject:item]) {
            // preview update for folder
            UIImage *newImage = [self _generateFolderImageWithFolder:folder];
            UIImageView *view = [_previewViews objectAtIndex:index];
            [self _animateNewImage:newImage forView:view];
            return;
        } else if ((id)folder == item) {
            break;
        }
        index++;
    }
    if (index >= _displayedPreviews.count)
        return;
    
    OUIDocumentPreview *formerPreview = [_displayedPreviews objectAtIndex:index];
    formerPreview.superseded = YES;
    Class docClass = [_scope.documentStore fileItemClassForURL:item.fileURL];
    OUIDocumentPreview *preview = [OUIDocumentPreview makePreviewForDocumentClass:docClass fileURL:item.fileURL date:item.fileModificationDate withArea:OUIDocumentPreviewAreaMedium];
    [preview incrementDisplayCount];

    UIImageView *view = [_previewViews objectAtIndex:index];
    OBASSERT(preview.type == OUIDocumentPreviewTypeEmpty || CGSizeEqualToSize(preview.size, view.bounds.size), "Make sure the image isn't going to be stretched");
    
    view.layer.minificationFilter = kCAFilterLinear;
    [self _animateNewImage:[UIImage imageWithCGImage:preview.image] forView:view];
    
    NSMutableArray *newPreviews = [NSMutableArray arrayWithArray:_displayedPreviews];
    [newPreviews replaceObjectAtIndex:index withObject:preview];
    _displayedPreviews = [newPreviews copy];
    
    [formerPreview decrementDisplayCount];
}

- (void)setScope:(ODSScope *)scope;
{
    _scope = scope;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
    [_topItemsBinding invalidate];
    _topItemsBinding = nil;

    _coverView.layer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:kOUIDocumentPickerHomeScreenCellBackgroundOpacity].CGColor;
    _coverView.layer.borderWidth = kOUIDocumentPickerHomeScreenCellBorderWidth;
    [self _updateCoverViewBorderColor];
    
    if (_scope) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(_previewsUpdateForFileItemNotification:) name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
        _topItemsBinding = [[OFSetBinding alloc] initWithSourceObject:_scope sourceKeyPath:OFValidateKeyPath(_scope, topLevelItems) destinationObject:self destinationKeyPath:OFValidateKeyPath(self, fileItems)];
        [_topItemsBinding propagateCurrentValue];
    } else {
        self.fileItems = nil;
    }
}

- (OUIDocumentPickerFilter *)documentFilter;
{
    return [OUIDocumentPickerViewController documentFilterForPicker:_picker scope:_scope];
}

- (CGRect)_rectForMiniTile:(NSUInteger)index inRect:(CGRect)rect;
{
    if (index > 24)
        index = 24;
    
    CGFloat spaceWidth = MAX(floor(CGRectGetWidth(rect) / 5.0), 2.0f);
    CGFloat gapWidth = MAX(ceil(spaceWidth / 11.0), 1.0f);
    CGRect miniRect = rect;
    
    miniRect.size.width = miniRect.size.height = spaceWidth - gapWidth;
    NSUInteger row = index / 5;
    NSUInteger column = index % 5;
    miniRect.origin.x = CGRectGetMinX(rect) + spaceWidth * column;
    miniRect.origin.y = CGRectGetMinY(rect) + spaceWidth * row;
    return miniRect;
}

- (void)_drawMiniTiles:(NSUInteger)count inRect:(CGRect)rect;
{
    CGFloat borderWidth = 1.0 / [self contentScaleFactor];
    NSUInteger index, drawAtThisScale = MIN(24u, count);
    
    UIColor *gray = [UIColor colorWithWhite:0.5 alpha:1.0];
    for (index = 0; index < drawAtThisScale; index++) {
        CGRect miniRect = [self _rectForMiniTile:index inRect:rect];
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectInset(miniRect, borderWidth/2.0, borderWidth/2.0)];
        [[UIColor whiteColor] set];
        [path fill];
        [gray set];
        [path stroke];
    }
    
    count -= drawAtThisScale;
    if (count) {
        [self _drawMiniTiles:count inRect:[self _rectForMiniTile:24 inRect:rect]];
    }
}

- (UIImage *)_generateOverflowImageWithCount:(NSUInteger)count;
{
    CGRect rect = _preview6.bounds;
    UIGraphicsBeginImageContext(rect.size);
    [[UIColor clearColor] set];
    UIRectFill(rect);
    [self _drawMiniTiles:count inRect:rect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (UIImage *)_generateFolderImageWithFolder:(ODSFolderItem *)folder;
{
    NSArray *sortedItems = [self _previewedItemsForFolder:folder];
    NSUInteger count = sortedItems.count;
    
    CGRect rect = _preview6.bounds;
    if (rect.size.height < 1 || rect.size.width < 1)
        return nil;
    
    UIGraphicsBeginImageContextWithOptions(rect.size, YES/*opaque*/, 0/*scale*/);
    
    [[UIColor lightGrayColor] set];
    UIRectFill(rect);
    
    NSUInteger itemsPerRow = 3;
    CGFloat childLength = 28.0;
    CGFloat gap = 4.0;

    CGFloat contentWidthExcludingBorders = itemsPerRow * childLength + (itemsPerRow - 1) * gap;
    CGFloat leftBorder = (rect.size.width - contentWidthExcludingBorders) * 0.5f;
    OBASSERT(leftBorder >= 3.0f); // Each row should have enough space for its content. If not, we need to adjust our parameters.

    UIColor *gray = [UIColor colorWithWhite:0.5 alpha:1.0];
    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger row = index / 3;
        NSUInteger column = index % 3;
        CGRect miniRect = CGRectMake(leftBorder + column * (childLength + gap), gap + row * (childLength + gap), childLength, childLength);
        
        ODSFileItem *item = [sortedItems objectAtIndex:index];
        if (item.type == ODSItemTypeFile) {
            Class docClass = [_scope.documentStore fileItemClassForURL:item.fileURL];
            OUIDocumentPreview *preview = [OUIDocumentPreview makePreviewForDocumentClass:docClass fileURL:item.fileURL date:item.fileModificationDate withArea:OUIDocumentPreviewAreaTiny];
            [preview incrementDisplayCount];
            CGImageRef image = preview.image; // Can't ask for the size until after this forces the image to load.
            OBASSERT(CGSizeEqualToSize(preview.size, miniRect.size), "Scaling a preview will result in blurring");
            [[UIImage imageWithCGImage:image] drawInRect:miniRect];
            [preview decrementDisplayCount];
        } else {
            UIBezierPath *path = [UIBezierPath bezierPathWithRect:miniRect];
            [[UIColor whiteColor] set];
            [path fill];
            [gray set];
            [path stroke];
        }
    }
    
    
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)resortPreviews;
{
    _itemsForPreviews = [NSMutableArray array];

    OUIDocumentPickerFilter *filter = self.documentFilter;
    NSSet *filteredItems;
    if (filter)
        filteredItems = [_fileItems filteredSetUsingPredicate:filter.predicate];
    else
        filteredItems = _fileItems;
    
    NSArray *sortedItems = [filteredItems sortedArrayUsingDescriptors:[OUIDocumentPickerViewController sortDescriptors]];
    
    if (!_fileItems) {
        _countLabel.text = @"";
        _dateLabel.text = @"";
    } else {
        NSString *countString;
        if (sortedItems.count == 1)
            countString = @"1 Item";
        else
            countString = [NSString stringWithFormat:@"%lu Items", sortedItems.count];
        
        if (sortedItems.count) {
            NSDate *latestDate = [NSDate distantPast];
            for (ODSFileItem *item in sortedItems)
                latestDate = [latestDate laterDate:item.userModificationDate];
            _countLabel.text = [NSString stringWithFormat:@"%@ \u2022 %@", countString, [dateFormatter stringFromDate:latestDate]];
        } else
            _countLabel.text = countString;
    }
    
    if (!_previewViews) {
        _previewViews = [[NSMutableArray alloc] init];
        [_previewViews addObject:_preview1];
        [_previewViews addObject:_preview2];
        [_previewViews addObject:_preview3];
        [_previewViews addObject:_preview4];
        [_previewViews addObject:_preview5];
        [_previewViews addObject:_preview6];
        
    }
    
    NSMutableArray *displayedPreviews = [NSMutableArray new];
    NSEnumerator *itemEnumerator = [sortedItems objectEnumerator];
    for (UIImageView *view in _previewViews) {
        if (view == _preview6 && sortedItems.count > 6) {
            view.layer.borderColor = nil;
            view.layer.borderWidth = 0.0;
            view.backgroundColor = [UIColor clearColor];
            [view setHidden:NO];            
            view.image = [self _generateOverflowImageWithCount:(sortedItems.count - 5)];
            break;
        } else {
            view.layer.borderColor = [[UIColor colorWithWhite:0.5 alpha:1.0] CGColor];
            view.layer.borderWidth = 1.0 / [self contentScaleFactor];
        }
        
        ODSFileItem *item = [itemEnumerator nextObject];
        if ([item isKindOfClass:[ODSFileItem class]]) {
            Class docClass = [_scope.documentStore fileItemClassForURL:item.fileURL];
            OUIDocumentPreview *preview = [OUIDocumentPreview makePreviewForDocumentClass:docClass fileURL:item.fileURL date:item.fileModificationDate withArea:OUIDocumentPreviewAreaMedium];
            [displayedPreviews addObject:preview];
            [preview incrementDisplayCount];
            
            CGImageRef image = preview.image; // Calling -size before this forces the image to load will not return the right size
            OBASSERT(preview.type == OUIDocumentPreviewTypeEmpty || CGSizeEqualToSize(preview.size, view.bounds.size), "Make sure the image isn't going to be stretched");
            view.layer.minificationFilter = kCAFilterLinear;
            view.image = [UIImage imageWithCGImage:image];
            [_itemsForPreviews addObject:item];
            [view setHidden:NO];
        } else if ([item isKindOfClass:[ODSFolderItem class]]) {
            view.image = [self _generateFolderImageWithFolder:(ODSFolderItem *)item];
            [_itemsForPreviews addObject:item];
            [view setHidden:NO];
        } else {
            view.backgroundColor = nil;
            view.image = nil;
            [view setHidden:YES];
        }
    }
    
    for (OUIDocumentPreview *preview in _displayedPreviews)
        [preview decrementDisplayCount];
    _displayedPreviews = [displayedPreviews copy];
    [_coverView.superview bringSubviewToFront:_coverView];
}

- (void)setFileItems:(NSSet *)fileItems;
{
    _fileItems = [fileItems copy];
    [self resortPreviews];
}

#pragma mark - UIView subclass

- (void)_updateCoverViewBorderColor;
{
    _coverView.layer.borderColor = self.tintColor.CGColor;
}

- (void)tintColorDidChange;
{
    [self _updateCoverViewBorderColor];
    [super tintColorDidChange];
}

@end
