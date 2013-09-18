// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIMenuOptionsController.h"

RCS_ID("$Id$");

#import <OmniUI/OUIAppearance.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <UIKit/UITableView.h>

#import "OUIParameters.h"

@interface OUIMenuOptionsController () <UITableViewDelegate, UITableViewDataSource>
@end

@implementation OUIMenuOptionsController
{
    __weak OUIMenuController *_weak_controller;
}

- initWithController:(OUIMenuController *)controller options:(NSArray *)options;
{
    OBPRECONDITION([options count] > 0);
    
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    // We could also get at this from our navigation controller's delegate...
    _weak_controller = controller;
    _showsDividersBetweenOptions = YES;
    _options = [options copy];

    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (void)setTintColor:(UIColor *)tintColor;
{
    if (OFISEQUAL(_tintColor, tintColor))
        return;
    
    _tintColor = [tintColor copy];
    
    if ([self isViewLoaded])
        self.view.tintColor =_tintColor; // UITableView doesn't propagate this to its rows, but it seems good to pass it on anyway.
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, kOUIMenuControllerTableWidth, 0) style:UITableViewStylePlain];
    tableView.delegate = self;
    tableView.dataSource = self;

    if (_padTopAndBottom) {
        CGFloat padding = 15;
        tableView.contentInset = UIEdgeInsetsMake(padding, 0, padding, 0);
    }
    
    [tableView reloadData];
    OUITableViewAdjustHeightToFitContents(tableView); // -sizeToFit doesn't work after # options changes, sadly

    if (_showsDividersBetweenOptions == NO) {
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    
    // Limit the height of the menu to something reasonable (might have many folders in the 'move' menu, for example).
    if (tableView.frame.size.height > 400) {
        CGRect frame = tableView.frame;
        frame.size.height = 400;
        tableView.frame = frame;
    }
        
    tableView.backgroundView = nil;
    tableView.backgroundColor = nil;
    tableView.opaque = NO;
    
    CGSize preferredContentSize = tableView.frame.size;
    if (_sizesToOptionWidth) {
        [tableView layoutIfNeeded];
        
        CGFloat width = 0;
        CGFloat padding = 0;
        for (UITableViewCell *cell in tableView.visibleCells) { // should be all the cells since we adjusted height already
            // Figure out how much space is around each label
            CGRect contentViewRect = [cell.contentView convertRect:cell.contentView.bounds toView:tableView];
            CGRect labelRect = [cell.textLabel convertRect:cell.textLabel.bounds toView:tableView];
            padding = contentViewRect.size.width - labelRect.size.width;
            
            width = MAX(width, [cell.textLabel sizeThatFits:cell.textLabel.bounds.size].width);
        }
        
        // The padding calculated is the minimum value needed to avoid ellipsis in the label. Double it to get something more like UIActionSheet.
        preferredContentSize.width = ceil(width + 2*padding);
    }
    
    self.preferredContentSize = preferredContentSize;

    // Doesn't do anything currently since our cells have UILabels which ignore the tint color (we set their text color).
    tableView.tintColor = _tintColor;
    
    self.view = tableView;
}

- (void)viewDidLayoutSubviews;
{
    [super viewDidLayoutSubviews];
    
    UITableView *tableView = (UITableView *)self.view;
    
    // If we or our popover limited our height, make sure all the options are visible (most common on submenus).
    CGRect bounds = tableView.bounds;
    tableView.scrollEnabled = (tableView.contentSize.height > bounds.size.height);
    
    // Default to "no" separator in case we get stuck in a popover that is taller than we need.
    tableView.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(bounds)/*left*/, 0, 0);
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    UITableView *tableView = (UITableView *)self.view;
    if (tableView.scrollEnabled)
        [tableView flashScrollIndicators];
}

#pragma mark - UITableView dataSource

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    if (section == 0) {
        OBASSERT(_options);
        return [_options count];
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // Returning a nil cell will cause UITableView to throw an exception
    if (indexPath.section != 0)
        return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    
    if (indexPath.row >= (NSInteger)[_options count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested");
        return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    }
    OUIMenuOption *option = [_options objectAtIndex:indexPath.row];
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
        cell.backgroundColor = nil;
        cell.opaque = NO;
        
        // We want this match UIActionSheet, but it doesn't use dynamic type. Also, none of the methods in UIInterface.h return the size to use.
        cell.textLabel.backgroundColor = nil;
        cell.textLabel.opaque = NO;
        cell.textLabel.font = [UIFont systemFontOfSize:20];
        cell.textLabel.textAlignment = _textAlignment;
    }
    
    UILabel *label = cell.textLabel;
    label.text = option.title;
    
    UIImage *image = [option.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.image = image;
    
    OBASSERT_IF(option.destructive, option.action, "Cannot have a disabled destructive action");
    if (option.destructive) {
        label.textColor = [UIColor omniDeleteColor];
        cell.imageView.tintColor = [UIColor omniDeleteColor];
    }
    else if (option.action || [option.options count] > 0) {
        label.textColor = _tintColor;
        cell.imageView.tintColor = _tintColor;
    } else {
        // Placeholder; one such case is in the 'move to folder' where some folders aren't valid destinations but are listed to show hierarchy
        label.textColor = [OUIInspector disabledLabelTextColor];
        cell.imageView.tintColor = [OUIInspector disabledLabelTextColor];
    }
    
    NSUInteger imageIndentLevels = 0;
    if (image) {
        // The indentation the title is the MAX of the image width and indentationLevel*indentationWidth, which is silly. To account for this, we assume all the options have images (or not) of the same width.
        imageIndentLevels = ceil(image.size.width / kOUIMenuOptionIndentationWidth);
    }
    
    cell.indentationWidth = kOUIMenuOptionIndentationWidth;
    cell.indentationLevel = imageIndentLevels + option.indentationLevel;
    
    // We pull the left edge of the last separator all the way to the left edge so it doesn't look goofy vs the bottom of the popover. But, this means we have to do an anti-adjustment on the indentation of the last cell.
    UIEdgeInsets separatorInset = cell.separatorInset;
    static CGFloat defaultSeparatorInsetLeft = 0;
    if (defaultSeparatorInsetLeft == 0) {
        defaultSeparatorInsetLeft = separatorInset.left;
    }
    
    // We pull the left edge of the last separator all the way to the left edge so it doesn't look goofy vs the bottom of the popover. But, this means we have to do an anti-adjustment on the indentation of the last cell.
    // But, we only do this if the last cell really is at the bottom of the view
    if ((NSUInteger)indexPath.row == [_options count] - 1 && tableView.bounds.size.height == tableView.contentSize.height) {
        CGFloat indentation = defaultSeparatorInsetLeft + cell.indentationLevel * cell.indentationWidth;
        cell.indentationLevel = 1;
        cell.indentationWidth = indentation;
        separatorInset.left = 0;
    } else {
        separatorInset.left = defaultSeparatorInsetLeft;
    }
    cell.separatorInset = separatorInset;
    
    if (option.options) {
        if (!cell.accessoryView) {
            UIImage *image = [[OUIInspectorWell navigationArrowImage] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setImage:image forState:UIControlStateNormal];
            [button sizeToFit];
        
            // -tableView:accessoryButtonTappedForRowWithIndexPath: is not called when there is a custom view, so we need our own action.
            [button addTarget:self action:@selector(_showSubmenu:) forControlEvents:UIControlEventTouchUpInside];
            
            cell.accessoryView = button;
        }
    } else {
        cell.accessoryView = nil;
    }
    
    [cell sizeToFit];
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIMenuOption *option = [_options objectAtIndex:indexPath.row];

    if (option.action == nil && [option.options count] == 0)
        return NO; // Disabled placeholder action
    
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(indexPath.section == 0);

    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    OUIMenuOption *option = [_options objectAtIndex:indexPath.row];
    
    OUIMenuOptionAction action = option.action;
    if (action) {
        action();
        [_weak_controller didInvokeOption:option];
    } else
        [self _showSubmenuForParentOption:option];
}

#pragma mark - Private

- (void)_showSubmenuForParentOption:(OUIMenuOption *)parentOption;
{
    OUIMenuOptionsController *childController = [[OUIMenuOptionsController alloc] initWithController:_weak_controller options:parentOption.options];
    childController.tintColor = _tintColor;
    childController.title = parentOption.title;
    childController.sizesToOptionWidth = _sizesToOptionWidth;
    childController.textAlignment = _textAlignment;
    childController.showsDividersBetweenOptions = _showsDividersBetweenOptions;
    childController.padTopAndBottom = _padTopAndBottom;

    childController.navigationItem.backBarButtonItem.title = self.title;
    
    UINavigationController *navigationController = self.navigationController;
    [childController view];
    
    navigationController.navigationBarHidden = NO;
    [navigationController pushViewController:childController animated:YES];
}

- (void)_showSubmenu:(UIButton *)sender;
{
    UITableView *tableView = (UITableView *)self.view;
    UITableViewCell *cell = [sender containingViewOfClass:[UITableViewCell class]];
    NSIndexPath *indexPath = [tableView indexPathForCell:cell];
    
    [self _showSubmenuForParentOption:_options[indexPath.row]];
}

@end
