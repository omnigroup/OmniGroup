// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
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
#import <OmniUI/OUIAppearanceColors.h>

@interface OUIMenuOptionTableViewCell : UITableViewCell
@property (nonatomic) BOOL showsFullwidthSeparator;
@end

@implementation OUIMenuOptionTableViewCell
{
    UIView *_fullwidthSeparator;
}

- (void)setShowsFullwidthSeparator:(BOOL)flag;
{
    _showsFullwidthSeparator = flag;
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    if (_showsFullwidthSeparator) {
        CGRect ourBounds = self.bounds;
        CGFloat lineSize = 1/[[UIScreen mainScreen] scale];        
        CGRect separatorFrame = (CGRect){.origin.x = CGRectGetMinX(ourBounds), .origin.y = CGRectGetMaxY(ourBounds), .size.width = CGRectGetWidth(ourBounds), .size.height = lineSize};
        if (_fullwidthSeparator) {
            _fullwidthSeparator.frame = separatorFrame;
        } else {
            _fullwidthSeparator = [[UIView alloc] initWithFrame:separatorFrame];
            _fullwidthSeparator.backgroundColor = [[OUIAppearanceDefaultColors appearance] omniNeutralPlaceholderColor];
            _fullwidthSeparator.translatesAutoresizingMaskIntoConstraints = YES;
            _fullwidthSeparator.autoresizingMask = UIViewAutoresizingNone;
        }
        [self addSubview:_fullwidthSeparator];
    } else {
        [_fullwidthSeparator removeFromSuperview];
    }
}

@end

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
    tableView.rowHeight = 44.0f;

    [tableView reloadData];
    OUITableViewAdjustHeightToFitContents(tableView); // -sizeToFit doesn't work after # options changes, sadly

    // We draw our own separators using OUIMenuOptionTableViewCell.showsFullwidthSeparator
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    // Limit the height of the menu to something reasonable (might have many folders in the 'move' menu, for example).
    if (tableView.frame.size.height > 400) {
        CGRect frame = tableView.frame;
        frame.size.height = 400;
        tableView.frame = frame;
    }
        
    tableView.backgroundView = nil;
    tableView.opaque = NO;
    
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
}

- (void)_updatePreferredContentSizeFromOptions;
{
    UITableView *tableView = (UITableView *)self.view;
    [tableView layoutIfNeeded];
    
    CGFloat preferredWidth;
    if (!_sizesToOptionWidth) {
        preferredWidth = kOUIMenuControllerTableWidth;
    } else {
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
        preferredWidth = ceil(width + 2*padding);
    }
    
    self.preferredContentSize = (CGSize){.width = preferredWidth, .height = ((UITableView *)self.view).contentSize.height};
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    [UIView performWithoutAnimation:^{
        [self _updatePreferredContentSizeFromOptions];
        [self.view layoutIfNeeded];
    }];
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
    
    OUIMenuOptionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option"];
    if (!cell) {
        cell = [[OUIMenuOptionTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
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
    else if (option.isEnabled || [option.options count] > 0) {
        label.textColor = _tintColor;
        cell.imageView.tintColor = _tintColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        // Placeholder; one such case is in the 'move to folder' where some folders aren't valid destinations but are listed to show hierarchy
        label.textColor = [OUIInspector disabledLabelTextColor];
        cell.imageView.tintColor = [OUIInspector disabledLabelTextColor];
        cell.selectionStyle = UITableViewCellEditingStyleNone;
    }
    
    cell.indentationWidth = kOUIMenuOptionIndentationWidth;
    cell.indentationLevel = option.indentationLevel;

    if (_showsDividersBetweenOptions && (NSUInteger)indexPath.row < (_options.count - 1))
        cell.showsFullwidthSeparator = YES;
    
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
        [_weak_controller dismissAndInvokeOption:option];
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
