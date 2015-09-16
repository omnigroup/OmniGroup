// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerGroupItemView.h>

#import "OUIDocumentParameters.h"
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSStore.h>

#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import "OUIDocumentPickerItemView-Internal.h"

RCS_ID("$Id$");

@implementation OUIDocumentPickerGroupItemView
{
    CGSize _lastKnownBoundsSize;
}

static id _commonInit(OUIDocumentPickerGroupItemView *self)
{
    self.backgroundColor = [UIColor lightGrayColor];
    self->_lastKnownBoundsSize = self.contentView.bounds.size;
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    return _commonInit(self);
}

#pragma mark - OUIDocumentPickerItemView subclass

static unsigned GroupItemContext;

- (void)startObservingItem:(id)item;
{
    [super startObservingItem:item];
    [item addObserver:self forKeyPath:ODSFolderItemChildItemsBinding options:0 context:&GroupItemContext];
}

- (void)stopObservingItem:(id)item;
{
    [super stopObservingItem:item];
    [item removeObserver:self forKeyPath:ODSFolderItemChildItemsBinding context:&GroupItemContext];
}

- (OUIDocumentPreviewArea)previewArea;
{
    return OUIDocumentPreviewAreaSmall;
}

- (NSArray *)previewedItems;
{
    ODSFolderItem *item = (ODSFolderItem *)self.item;
    OBASSERT(!item || [item isKindOfClass:[ODSFolderItem class]]);
    
    OUIDocumentPickerFilter *filter = [OUIDocumentPickerViewController selectedFilterForPicker:[[OUIDocumentAppController controller] documentPicker]];
    
    NSSet *filteredItems;
    if (filter)
        filteredItems = [item.childItems filteredSetUsingPredicate:filter.predicate];
    else
        filteredItems = item.childItems;
    NSArray *sortedItems = [filteredItems sortedArrayUsingDescriptors:[OUIDocumentPickerViewController sortDescriptors]];
    return sortedItems;
}

- (void)layoutSubviews;
{
    UIView *contentView = self.contentView;
    CGRect bounds = contentView.bounds;
    
    if (!(CGSizeEqualToSize(bounds.size, _lastKnownBoundsSize))) {
        NSMutableArray *subviewsToRemove = [[NSMutableArray alloc] init];
        for (UIView *subview in contentView.subviews) {
            if ([subview isKindOfClass:[OUIDocumentPreviewView class]])
                [subviewsToRemove addObject:subview];
        }
        
        [subviewsToRemove makeObjectsPerformSelector:@selector(removeFromSuperview)];

        CGSize miniPreviewSize;
        UIEdgeInsets miniPreviewInsets;
        CGFloat spacing;

        if (self.isSmallSize) {
            miniPreviewSize = kOUIDocumentPickerFolderSmallItemMiniPreviewSize;
            miniPreviewInsets = kOUIDocumentPickerFolderSmallItemMiniPreviewInsets;
            spacing = kOUIDocumentPickerFolderSmallItemMiniPreviewSpacing;
        } else {
            miniPreviewSize = kOUIDocumentPickerFolderItemMiniPreviewSize;
            miniPreviewInsets = kOUIDocumentPickerFolderItemMiniPreviewInsets;
            spacing = kOUIDocumentPickerFolderItemMiniPreviewSpacing;
        }

        NSUInteger tag = 0;
        for (CGFloat y = miniPreviewInsets.top; y < CGRectGetMaxY(bounds) - miniPreviewInsets.bottom; y += miniPreviewSize.height + spacing) {
            for (CGFloat x = miniPreviewInsets.left; x < CGRectGetMaxX(bounds) - miniPreviewInsets.right; x += miniPreviewSize.width + spacing) {
                OUIDocumentPreviewView *previewView = [[OUIDocumentPreviewView alloc] initWithFrame:(CGRect){.origin = CGPointMake(x, y), .size = miniPreviewSize}];
                OUIDocumentPreviewViewSetNormalBorder(previewView);
                previewView.autoresizingMask = UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin;
                previewView.tag = tag++;
                [contentView addSubview:previewView];
            }
        }
        
        _lastKnownBoundsSize = bounds.size;
    }

    [super layoutSubviews];
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &GroupItemContext) {
        if (OFISEQUAL(keyPath, ODSFolderItemChildItemsBinding))
            [self previewedItemsChanged];
        else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Accessibility
- (NSString *)accessibilityValue
{
    NSString *folderType = NSLocalizedStringFromTableInBundle(@"Folder", @"OmniUIDocument", OMNI_BUNDLE, @"doc picker folder type accessibility value");
    NSString *countString = [self _accessibilityItemCount];
    NSString *superAXValue = [super accessibilityValue];
    
    return [NSString stringWithFormat:@"%@, %@, %@", folderType, countString, superAXValue];
}

- (NSString *)_accessibilityItemCount
{
    NSInteger count = [[self previewedItems] count];
    if (count == 0) {
        return NSLocalizedStringFromTableInBundle(@"No items", @"OmniUIDocument", OMNI_BUNDLE, @"doc picker no items accessibility value");
    }
    
    
    if (count > 1) {
        NSString *format = NSLocalizedStringFromTableInBundle(@"%@ items", @"OmniUIDocument", OMNI_BUNDLE, @"doc picker multiple items accessibility value");
        return [NSString stringWithFormat:format, @(count)];
    }
    
    return NSLocalizedStringFromTableInBundle(@"1 item", @"OmniUIDocument", OMNI_BUNDLE, @"doc picker single item accessibility value");
}
@end
