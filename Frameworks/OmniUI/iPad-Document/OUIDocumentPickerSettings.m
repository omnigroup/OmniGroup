// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPickerSettings.h"

#import <OmniFileStore/OFSDocumentStoreScope.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentPickerItemSort.h>
#import <OmniUI/UITableView-OUIExtensions.h>

RCS_ID("$Id$");

enum {
    SettingSectionScope,
    SettingSectionFilter,
    SettingSectionSort,
    SettingSectionCount,
};

@interface OUIDocumentPickerSettings () <UITableViewDataSource, UITableViewDelegate, UIPopoverControllerDelegate>
@end

@implementation OUIDocumentPickerSettings
{
    UIPopoverController *_filterPopoverController;
    CGFloat _defaultSectionHeaderHeight;
    CGFloat _defaultSectionFooterHeight;
}

- (void)showFromView:(UIView *)view;
{
    OBStrongRetain(self); // Stay alive while our popover is up
    
    if ([[OUIAppController controller] dismissPopover:_filterPopoverController animated:YES]) {
        OBASSERT(_filterPopoverController == nil); // delegate method should have been called
        return;
    }
    
    UIViewController *viewController = [[UIViewController alloc] init];

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 0) style:UITableViewStyleGrouped];

    // Remember the default heights and set the fallbacks to zero (returning zero from the delegate uses these properties).
    _defaultSectionHeaderHeight = tableView.sectionHeaderHeight;
    _defaultSectionFooterHeight = tableView.sectionFooterHeight;
    tableView.sectionHeaderHeight = 0;
    tableView.sectionFooterHeight = 0;
    
    viewController.view = tableView;
    
    tableView.autoresizingMask = 0;
    tableView.delegate = self;
    tableView.dataSource = self;
    
    [tableView reloadData];
    OUITableViewAdjustHeightToFitContents(tableView);
    tableView.scrollEnabled = NO;
    
    CGSize contentSize = CGSizeMake(320, tableView.frame.size.height);
    [viewController setContentSizeForViewInPopover:contentSize];

    _filterPopoverController = [[UIPopoverController alloc] initWithContentViewController:viewController];
    _filterPopoverController.delegate = self;
    
    [[OUIAppController controller] presentPopover:_filterPopoverController fromRect:view.bounds inView:view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)dealloc;
{
    OBPRECONDITION(_filterPopoverController == nil); // We are retained while it is up...
}

#pragma mark - UITableViewDataSource protocol

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return SettingSectionCount;
}

- (NSInteger)tableView:(UITableView *)aTableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case SettingSectionScope:
            return [_availableScopes count];
            
        case SettingSectionFilter:
            return [_availableFilters count];
            
        case SettingSectionSort:
            return OUIDocumentPickerItemSortCount;
            
        default:
            OBASSERT_NOT_REACHED("Unknown setting section");
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    static NSString * const CellIdentifier = @"FilterCellIdentifier";
    
    // Dequeue or create a cell of the appropriate type.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }

    NSInteger row = indexPath.row;
    NSString *title;
    NSString *imageName;
    BOOL checked;
    
    switch (indexPath.section) {
        case SettingSectionScope: {
            OFSDocumentStoreScope *scope = [_availableScopes objectAtIndex:row];
            title = scope.displayName;
            imageName = scope.settingsImageName;
            checked = [[[OUIDocumentPicker scopePreference] stringValue] isEqualToString:scope.identifier];
            break;
        }
            
        case SettingSectionFilter: {
            OUIDocumentPickerFilter *filter = [_availableFilters objectAtIndex:row];
            title = filter.title;
            imageName = filter.imageName;
            checked = [[[OUIDocumentPicker filterPreference] stringValue] isEqualToString:filter.identifier];
            break;
        }
            
        case SettingSectionSort:
            title = (row == OUIDocumentPickerItemSortByName) ? NSLocalizedStringFromTableInBundle(@"Sort by title", @"OmniUIDocument", OMNI_BUNDLE, @"sort by title") : NSLocalizedStringFromTableInBundle(@"Sort by date", @"OmniUIDocument", OMNI_BUNDLE, @"sort by date");
            imageName = (row == OUIDocumentPickerItemSortByName) ? @"OUIDocumentSortByName.png" : @"OUIDocumentSortByDate.png";
            checked = ([[OUIDocumentPicker sortPreference] enumeratedValue] == row);
            break;
            
        default:
            OBASSERT_NOT_REACHED("Unknown setting section");
            return 0;
    }
    
    UIImage *image = nil;
    if (imageName) {
        image = [UIImage imageNamed:imageName];
        OBASSERT(image);
    }
    cell.textLabel.text = title;
    cell.imageView.image = image;
    cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

#pragma mark - UITableViewDelegate protocol

- (void)tableView:(UITableView *)aTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSInteger section = indexPath.section;
    NSInteger row = indexPath.row;
    
    switch (section) {
        case SettingSectionScope: {
            OFSDocumentStoreScope *scope = [_availableScopes objectAtIndex:row];
            [[OUIDocumentPicker scopePreference] setStringValue:scope.identifier];
            break;
        }
        case SettingSectionFilter: {
            OUIDocumentPickerFilter *filter = [_availableFilters objectAtIndex:row];
            [[OUIDocumentPicker filterPreference] setStringValue:filter.identifier];
            break;
        }
        case SettingSectionSort:
            [[OUIDocumentPicker sortPreference] setEnumeratedValue:row];
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown settion section");
            break;
    }
    
    NSUInteger rowsInSection = [self tableView:aTableView numberOfRowsInSection:section];
    for (NSUInteger rowIndex = 0; rowIndex < rowsInSection; rowIndex++) {
        UITableViewCell *cell = [aTableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:rowIndex inSection:section]];
        cell.accessoryType = (row == rowIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    
    [_filterPopoverController dismissPopoverAnimated:YES];
    _filterPopoverController = nil;
}

// Pack the table view so that empty sections don't leave extra padding
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section;
{
    if ([self tableView:tableView numberOfRowsInSection:section] == 0)
        return 0;
    return _defaultSectionHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
{
    if (section == SettingSectionCount - 1)
        return _defaultSectionFooterHeight;
    return 0;
}

#pragma mark - UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    _filterPopoverController = nil;
    
    // We are done!
    OBStrongRelease(self);
}

@end

#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>

@implementation OFSDocumentStoreScope (OUIDocumentPickerSettings)
- (NSString *)settingsImageName;
{
    OBASSERT_NOT_REACHED("No default settings image defined for scopes");
    return nil;
}
@end

@implementation OFSDocumentStoreLocalDirectoryScope (OUIDocumentPickerSettings)
- (NSString *)settingsImageName;
{
    // We expect each application to provide images (so no "OUI" prefix on the image names)
    return @"DocumentStoreScope-Local.png";
}
@end
