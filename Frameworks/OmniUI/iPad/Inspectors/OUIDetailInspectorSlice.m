// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDetailInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIThemedTableViewCell.h>
#import <OmniUI/OUIInspectorPane.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OUIDetailInspectorSliceItem
@end

@interface OUIDetailInspectorSliceTableViewCell : OUIThemedTableViewCell
@property(nonatomic,assign) BOOL enabled;
@property(nonatomic,strong) UIImage *valueImage;
@property(nonatomic,strong) UIImageView *valueImageView;

@end

@implementation OUIDetailInspectorSliceTableViewCell

- (void)setValueImage:(UIImage *)valueImage;
{
    _valueImage = valueImage;
    [self setNeedsLayout];
}

- (void)updateConstraints
{
    [super updateConstraints];
}

- (void)safeAreaInsetsDidChange
{
    [super safeAreaInsetsDidChange];
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    if (_valueImage) {
        if (!self.valueImageView) {
            self.valueImageView = [[UIImageView alloc] initWithImage:_valueImage];
            [self.contentView addSubview:self.valueImageView];
        } else {
            [self.valueImageView setImage:_valueImage];
        }
        [self.valueImageView sizeToFit];
        CGRect frame = self.valueImageView.frame;
        frame.origin.x = CGRectGetMaxX(self.detailTextLabel.frame) - frame.size.width;
        frame.origin.y = CGRectGetMidY(self.contentView.frame) - frame.size.height/2.0;
        self.valueImageView.frame = frame;
        self.valueImageView.hidden = NO;
    } else {
        self.valueImageView.hidden = YES;
    }

#ifdef DEBUG_rachael0
    self.detailTextLabel.backgroundColor = [UIColor redColor];
#endif
    CGRect detailFrame = self.detailTextLabel.frame;
    detailFrame.size = self.detailTextLabel.intrinsicContentSize;
    // The detail label should start where it will fit the whole label in front of the arrow, without obscuring the rest of the row.

    // MAGIC NUMBERS AHOY
    CGFloat leftSideSpacing = 3.0;
    CGFloat minimumLeftLabelLength = 35;

    CGFloat rightmostPoint = CGRectGetMaxX(self.contentView.bounds);
    CGFloat possibleX = rightmostPoint - detailFrame.size.width;
    CGFloat smallestAllowableX = self.imageView.image == nil ? 0 : CGRectGetMaxX(self.imageView.frame) + leftSideSpacing;
    if (self.textLabel.text.length > 0) {
        smallestAllowableX += MIN(minimumLeftLabelLength, self.textLabel.frame.size.width) + leftSideSpacing;
    }
    detailFrame.origin.x = MAX(possibleX, smallestAllowableX);
    detailFrame.size.width = rightmostPoint - detailFrame.origin.x;
    self.detailTextLabel.frame = detailFrame;
    CGRect textFrame = self.textLabel.frame;
    CGSize contentSize = self.textLabel.intrinsicContentSize;
    if (textFrame.origin.x + contentSize.width > detailFrame.origin.x) {
        textFrame.size.width = detailFrame.origin.x - textFrame.origin.x;
        self.textLabel.frame = textFrame;
    }
}

@end

@implementation OUIDetailInspectorSlice

- (id)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    // Subclass responsibility
    OBASSERT([self respondsToSelector:@selector(itemCount)]);
    OBASSERT([self respondsToSelector:@selector(updateItem:atIndex:)]);
    
    return self;
}

// The most common case is that there is only one, but subclasses might have a whole group of related options.
- (NSUInteger)itemCount;
{
    return 1;
}

- (void)updateItem:(OUIDetailInspectorSliceItem *)item atIndex:(NSUInteger)itemIndex;
{
    // just leave the title.
}

// Let subclasses filter/adjust the inspection set for their details. Returning nil uses the default behavior of passing the same inspection set along.
- (nullable NSArray *)inspectedObjectsForItemAtIndex:(NSUInteger)itemIndex;
{
    return nil;
}

- (nullable NSString *)placeholderTitleForItemAtIndex:(NSUInteger)itemIndex;
{
    return nil;
}

- (nullable NSString *)placeholderValueForItemAtIndex:(NSUInteger)itemIndex;
{
    return nil;
}

@synthesize placeholderTextColor = _placeholderTextColor;
- (UIColor *)placeholderTextColor;
{
    if (_placeholderTextColor)
        return _placeholderTextColor;
    
    return [OUIInspector placeholderTextColor];
}

- (void)setPlaceholderTextColor:(UIColor * _Nullable)placeholderTextColor;
{
    if (_placeholderTextColor == placeholderTextColor)
        return;
    _placeholderTextColor = placeholderTextColor;
}

- (nullable NSString *)groupTitle;
{
    return nil;
}

#pragma mark - OUIInspectorSlice subclass

- (void)showDetails:(id)sender;
{
    OBFinishPortingWithNote("<bug:///147849> (iOS-OmniOutliner Bug: Implement -[OUIDetailInspectorSlice showDetails:])");
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    [self reloadTableAndResize];
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    [super loadView];
    
    // Work around radar 35175843
    self.view.frame = [UIScreen mainScreen].bounds;
    
    // iOS 7 GM bug: separators are not reliably drawn. This doesn't actually fix the color after the first display, but at least it gets the separators to show up.
    if ([OUIStackedSlicesInspectorPane implicitSeparators])
        self.tableView.separatorStyle = [self itemCount] == 1 ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [OUIInspectorSlice sliceSeparatorColor];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [self configureTableViewBackground:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    CGFloat currentHeight = self.tableView.contentSize.height;
    OBASSERT(currentHeight > 0.0);
    if (self.heightConstraint == nil) {
        self.heightConstraint = [self.tableView.heightAnchor constraintEqualToConstant:currentHeight];
        self.heightConstraint.active = YES;
    } else {
        self.heightConstraint.constant = currentHeight;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    if (section == 0)
        return [self itemCount];
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSString *reuseIdentifier = [[NSString alloc] initWithFormat:@"%ld", indexPath.row];
    OUIDetailInspectorSliceTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[OUIDetailInspectorSliceTableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
        
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
    cell.hasTintableDisclosureIndicator = YES;

    NSUInteger itemIndex = (NSUInteger)indexPath.row;
    OUIDetailInspectorSliceItem *item = [[OUIDetailInspectorSliceItem alloc] init];
    item.title = self.title;
    item.enabled = YES;
    item.boldValue = NO;
    item.drawImageAsTemplate = YES;
    
    [self updateItem:item atIndex:itemIndex];
    
    BOOL placeholder;
    
    NSString *title = item.title;
    placeholder = NO;
    if ([NSString isEmptyString:title]) {
        placeholder = YES;
        title = [self placeholderTitleForItemAtIndex:itemIndex];
    }
    cell.textLabel.text = title;
    if (placeholder) {
        cell.textLabel.textColor = [OUIInspector placeholderTextColor];
    } else {
        // Use the default dynamic color assigned by the table view.
    }
    cell.textLabel.font = [OUIInspectorTextWell defaultLabelFont];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    cell.backgroundColor = [self sliceBackgroundColor];

    NSString *value = item.value;
    UIImage *valueImage = item.valueImage;
    
    placeholder = NO;
    if (valueImage) {
        value = @"";
        cell.valueImage = valueImage;
    } else if ([NSString isEmptyString:value]) {
        placeholder = YES;
        value = [self placeholderValueForItemAtIndex:itemIndex];
    }

    if (item.image != nil) {
        if (item.drawImageAsTemplate) {
            cell.imageView.image = [item.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        } else {
            cell.imageView.image = item.image;
        }
    }
    cell.detailTextLabel.text = value;
    if (placeholder) {
        cell.detailTextLabel.textColor = [OUIInspector disabledLabelTextColor];
    } else if (cell.accessoryType == UITableViewCellAccessoryDisclosureIndicator) {
        cell.detailTextLabel.textColor = [OUIInspector valueTextColor];
    } else {
        cell.detailTextLabel.textColor = [OUIInspector valueTextColor];
    }
    if (item.boldValue == YES)
        cell.detailTextLabel.font = [OUIInspectorTextWell defaultLabelFont];
    else
        cell.detailTextLabel.font = [OUIInspectorTextWell defaultFont];

    cell.enabled = item.enabled;
    
    return cell;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    return [self groupTitle];
}

#pragma mark - UITableViewDelegate protocol

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // If our inspector slice group position is Alone or Last we want the bottom cell to draw its bottom separator for the full width (instead of inset).
    OUIInspectorSliceGroupPosition groupPosition = self.groupPosition;
    if ((groupPosition == OUIInspectorSliceGroupPositionAlone) || (groupPosition == OUIInspectorSliceGroupPositionLast)) {
        if (indexPath.row == [self tableView:tableView numberOfRowsInSection:indexPath.section] - 1) {
            UIEdgeInsets separatorInsets = tableView.separatorInset;
            separatorInsets.left = 0.0f;
            separatorInsets.right = 0.0f;
            cell.separatorInset = separatorInsets;
        }
    }
}

- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIDetailInspectorSliceTableViewCell *cell = (OUIDetailInspectorSliceTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
    return cell.enabled ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(self.detailPane == nil); // I want to get rid of this property, but we definitely shouldn't have one here since we might have multiple items
    
    NSUInteger itemIndex = (NSUInteger)indexPath.row;
    
    OUIInspectorPane *details = [self makeDetailsPaneForItemAtIndex:itemIndex];
    if (details != nil) {
        
        OBASSERT(details.parentSlice == nil); // The implementation shouldn't bother to set this up, we just pass it in case the detail needs to get some info from the parent
        details.parentSlice = self;
        
        // Maybe just call -updateItemAtIndex:with: again rather than grunging it back out of the UI...
        OUIDetailInspectorSliceTableViewCell *selectedCell = (OUIDetailInspectorSliceTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
        OBASSERT(selectedCell); // just got tapped, so it should be around!
        details.title = selectedCell.textLabel.text;
        
        [self.inspector pushPane:details inspectingObjects:[self inspectedObjectsForItemAtIndex:itemIndex]];
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UITableViewStyle)tableViewStyle; // The style to use when creating the table view
{
    return UITableViewStylePlain;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForFooterInSection:(NSInteger)section;
{
    return 0;
}

-(CGFloat)tableView:(UITableView *)tableView estimatedHeightForHeaderInSection:(NSInteger)section;
{
    return 0;
}

- (BOOL)shouldPushDetailsPaneForItemAtIndex:(NSUInteger)itemIndex {
    return YES;
}
@end

NS_ASSUME_NONNULL_END
