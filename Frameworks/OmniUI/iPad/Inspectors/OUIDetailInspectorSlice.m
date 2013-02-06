// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDetailInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorPane.h>
#import <OmniUI/UITableView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIDetailInspectorSliceItem

@synthesize title, value, image, enabled, boldValue;

- (void)dealloc;
{
    [title release];
    [value release];
    [image release];
    [super dealloc];
}

@end

@interface OUIDetailInspectorSliceTableViewCell : UITableViewCell
@property(nonatomic,assign) BOOL enabled;
@end

@implementation OUIDetailInspectorSliceTableViewCell
@synthesize enabled;
@end

@interface OUIDetailInspectorSlice() <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic,retain) UITableView *tableView;
@end

@implementation OUIDetailInspectorSlice

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    // Subclass responsibility
    OBASSERT([self respondsToSelector:@selector(itemCount)]);
    OBASSERT([self respondsToSelector:@selector(updateItem:atIndex:)]);
    
    return self;
}

- (void)dealloc;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    [_tableView release];

    [super dealloc];
}

@synthesize tableView = _tableView;

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
- (NSArray *)inspectedObjectsForItemAtIndex:(NSUInteger)itemIndex;
{
    return nil;
}

- (NSString *)placeholderTitleForItemAtIndex:(NSUInteger)itemIndex;
{
    return nil;
}

- (NSString *)placeholderValueForItemAtIndex:(NSUInteger)itemIndex;
{
    return nil;
}

- (NSString *)groupTitle;
{
    return nil;
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (void)showDetails:(id)sender;
{
    OBFinishPorting;
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    [_tableView reloadData];
    OUITableViewAdjustHeightToFitContents(_tableView);
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    OBPRECONDITION(_tableView == nil);
    
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 420) style:UITableViewStyleGrouped];
    
    _tableView.delegate = self;
    _tableView.dataSource = self;
    self.view = _tableView;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [self configureTableViewBackground:_tableView];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    // Might be coming back from a detail pane that edited a displayed value
    [_tableView reloadData];
    OUITableViewAdjustHeightToFitContents(_tableView);
}

#pragma mark -
#pragma mark UITableViewDataSource

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
        cell = [[[OUIDetailInspectorSliceTableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier] autorelease];
        
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
    [reuseIdentifier release];
    
    NSUInteger itemIndex = (NSUInteger)indexPath.row;
    OUIDetailInspectorSliceItem *item = [[OUIDetailInspectorSliceItem alloc] init];
    item.title = self.title;
    item.enabled = YES;
    item.boldValue = NO;
    
    [self updateItem:item atIndex:itemIndex];
    
    BOOL placeholder;
    
    NSString *title = item.title;
    placeholder = NO;
    if ([NSString isEmptyString:title]) {
        placeholder = YES;
        title = [self placeholderTitleForItemAtIndex:itemIndex];
    }
    cell.textLabel.text = title;
    cell.textLabel.textColor = placeholder ? [OUIInspector disabledLabelTextColor] : nil;
    cell.textLabel.font = [OUIInspectorTextWell defaultLabelFont];
    
    NSString *value = item.value;
    placeholder = NO;
    if ([NSString isEmptyString:value]) {
        placeholder = YES;
        value = [self placeholderValueForItemAtIndex:itemIndex];
    }

    if (item.image != nil) 
        cell.imageView.image = item.image;
    
    // No entry in UIInterface for this.
    static UIColor *defaultDetailTextColor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultDetailTextColor = [cell.detailTextLabel.textColor retain];
    });
    
    cell.detailTextLabel.text = value;
    cell.detailTextLabel.textColor = placeholder ? [OUIInspector disabledLabelTextColor] : defaultDetailTextColor;
    if (item.boldValue == YES)
        cell.detailTextLabel.font = [OUIInspectorTextWell defaultLabelFont];
    else
        cell.detailTextLabel.font = [OUIInspectorTextWell defaultFont];

    cell.enabled = item.enabled;
    
    [item release];
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    return [self groupTitle];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
{
    return 12;
}

#pragma mark -
#pragma mark UITableViewDelegate protocol

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIDetailInspectorSliceTableViewCell *cell = (OUIDetailInspectorSliceTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
    return cell.enabled ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(self.detailPane == nil); // I want to get rid of this property, but we definitely shouldn't have one here since we might have multiple items
    
    NSUInteger itemIndex = (NSUInteger)indexPath.row;
    
    OUIInspectorPane *details = [self makeDetailsPaneForItemAtIndex:itemIndex];
    
    OBASSERT(details.parentSlice == nil); // The implementation shouldn't bother to set this up, we just pass it in case the detail needs to get some info from the parent
    details.parentSlice = self;
    
    // Maybe just call -updateItemAtIndex:with: again rather than grunging it back out of the UI...
    OUIDetailInspectorSliceTableViewCell *selectedCell = (OUIDetailInspectorSliceTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
    OBASSERT(selectedCell); // just got tapped, so it should be around!
    details.title = selectedCell.textLabel.text;
    
    [self.inspector pushPane:details inspectingObjects:[self inspectedObjectsForItemAtIndex:itemIndex]];
    
    [_tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
