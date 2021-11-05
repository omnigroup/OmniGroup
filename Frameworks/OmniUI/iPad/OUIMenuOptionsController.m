// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIMenuOptionsController.h"

#import <OmniAppKit/OAAppearance.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <UIKit/UITableView.h>
#import <OmniFoundation/NSString-OFExtensions.h>

#import "OUIParameters.h"
#import <OmniAppKit/OAAppearanceColors.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUIMenuEmptySection : NSObject
@end
@implementation OUIMenuEmptySection
@end

@interface OUIMenuOptionSection : NSObject

- initWithTitle:(NSString *)title options:(NSArray <OUIMenuOption *> *)options;

@property(nonatomic,readonly) NSString *title;
@property(nonatomic,readonly) NSArray <OUIMenuOption *> *options;

@end

@implementation OUIMenuOptionSection

- initWithTitle:(NSString *)title options:(NSArray <OUIMenuOption *> *)options;
{
    OBPRECONDITION([options count] > 0);

    self = [super init];
    
    _title = [title copy];
    _options = [options copy];

    return self;
}

@end

@interface OUIMenuOptionTableViewCell : UITableViewCell
@property (nonatomic) BOOL showsFullwidthSeparator;
@property (nonatomic) BOOL showsTopSeparator;
@property (nonatomic) BOOL isLastRowInSection;
@property (nonatomic, strong) UIView *iconView;
@end

@implementation OUIMenuOptionTableViewCell
{
    UIView *_fullwidthSeparator;
    UIView *_topSeparator;
}

- (void)setShowsFullwidthSeparator:(BOOL)flag;
{
    _showsFullwidthSeparator = flag;
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    CGFloat horizontalPadding = 16;
    CGFloat verticalPadding = 8;
    CGFloat iconWidth = 36;
    // it would be nice to put these constant in an OAAppearance class at some point.
    // ditto for the red color
    
    if (self.iconView) {
        // we're using our own view instead of the built in imageView because we need to be able to put things other than just images in there (for attention dots, which are implemented via buttons at the moment)
        if (!self.iconView.superview) {
            [self.imageView removeFromSuperview];
            [self.contentView addSubview:self.iconView];
        }
        self.iconView.frame = CGRectMake(horizontalPadding, verticalPadding, iconWidth, self.contentView.frame.size.height - 2 * verticalPadding);
        self.textLabel.frame = CGRectMake(iconWidth + 2 * horizontalPadding, self.textLabel.frame.origin.y, self.textLabel.frame.size.width - (iconWidth + 2 * horizontalPadding), self.textLabel.frame.size.height);
    }
    
    if (_showsFullwidthSeparator) {
        CGRect ourBounds = self.bounds;
        CGFloat lineSize = 1/[[UIScreen mainScreen] scale];
        CGRect separatorFrame = (CGRect){.origin.x = CGRectGetMinX(ourBounds), .origin.y = CGRectGetMaxY(ourBounds), .size.width = CGRectGetWidth(ourBounds), .size.height = lineSize};
        if (self.isLastRowInSection) {
            separatorFrame.origin.y--;
        }
        if (_fullwidthSeparator) {
            _fullwidthSeparator.frame = separatorFrame;
        } else {
            _fullwidthSeparator = [[UIView alloc] initWithFrame:separatorFrame];
            _fullwidthSeparator.backgroundColor = [[OAAppearanceDefaultColors appearance] omniNeutralPlaceholderColor];
            _fullwidthSeparator.translatesAutoresizingMaskIntoConstraints = YES;
            _fullwidthSeparator.autoresizingMask = UIViewAutoresizingNone;
        }
        [self addSubview:_fullwidthSeparator];
    } else {
        [_fullwidthSeparator removeFromSuperview];
    }
    
    if (self.showsTopSeparator) {
        CGRect ourBounds = self.bounds;
        CGFloat lineSize = 1/[[UIScreen mainScreen] scale];
        CGRect separatorFrame = (CGRect){.origin.x = CGRectGetMinX(ourBounds), .origin.y = CGRectGetMinY(ourBounds), .size.width = CGRectGetWidth(ourBounds), .size.height = lineSize};
        if (_topSeparator) {
            _topSeparator.frame = separatorFrame;
        } else {
            _topSeparator = [[UIView alloc] initWithFrame:separatorFrame];
            _topSeparator.backgroundColor = [[OAAppearanceDefaultColors appearance] omniNeutralPlaceholderColor];
            _topSeparator.translatesAutoresizingMaskIntoConstraints = YES;
            _topSeparator.autoresizingMask = UIViewAutoresizingNone;
        }
        [self addSubview:_topSeparator];
    } else {
        [_topSeparator removeFromSuperview];
    }
}

@end

@interface OUIMenuOptionsController () <UITableViewDelegate, UITableViewDataSource>
@end

@implementation OUIMenuOptionsController
{
    __weak OUIMenuController *_weak_controller;

    // The specified options are turned into sections and the sections are then used to back the table view.
    // This is a heterogeneous collection of OUIMenuEmptySection and OUIMenuOptionSection objects
    NSArray *_sections;
}

@synthesize options = _originalOptions;

- initWithController:(OUIMenuController *)controller options:(NSArray *)options;
{
    OBPRECONDITION([options count] > 0);
    
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    // We could also get at this from our navigation controller's delegate...
    _weak_controller = controller;
    _showsDividersBetweenOptions = YES;
    _originalOptions = [options copy];
    _sections = [[[self class] sectionsFromOptions:_originalOptions] copy];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
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
    
    UIColor *menuBackgroundColor = [_weak_controller menuBackgroundColor];
    if (menuBackgroundColor != nil) {
        // Only configure the menuBackgroundColor if explicitly configured by the OUIMenuController. We want default behavior otherwise.
        tableView.backgroundColor = menuBackgroundColor;
    }
    tableView.delegate = self;
    tableView.dataSource = self;
    tableView.rowHeight = 44.0f;

    [tableView reloadData];
    OUITableViewAdjustHeightToFitContents(tableView); // -sizeToFit doesn't work after # options changes, sadly

    // We used to draw our own separators using OUIMenuOptionTableViewCell.showsFullwidthSeparator
    // tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.separatorStyle = _showsDividersBetweenOptions ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;

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
    
    tableView.scrollEnabled = YES;
    
    self.view = tableView;
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
        for (OUIMenuOptionTableViewCell *cell in tableView.visibleCells) { // should be all the cells since we adjusted height already
            // Figure out how much space is around each label
            CGRect contentViewRect = [cell.contentView convertRect:cell.contentView.bounds toView:tableView];
            CGRect labelRect = [cell.textLabel convertRect:cell.textLabel.bounds toView:tableView];
            CGRect iconViewRect = [cell.iconView convertRect:cell.iconView.bounds toView:tableView];
            padding = contentViewRect.size.width - labelRect.size.width - iconViewRect.size.width;
            
            width = MAX(width, [cell.textLabel sizeThatFits:cell.textLabel.bounds.size].width);
        }
        
        // The padding calculated is the minimum value needed to avoid ellipsis in the label. Double it to get something more like UIActionSheet.
        preferredWidth = ceil(width + 2*padding);
    }

    UIEdgeInsets contentInsets = tableView.contentInset;
    CGFloat preferredHeight = tableView.contentSize.height + contentInsets.top + contentInsets.bottom;

    self.preferredContentSize = (CGSize){.width = preferredWidth, .height = preferredHeight};
}

- (void)willMoveToParentViewController:(nullable UIViewController *)parent
{
    //When we move to our parent view controller, its view encompasses the whole screen because that is the default size. So, starting in iOS9, when we move to the parent, we also inherit that size. If we calculate our preferred content size *after* moving, our calculation that relies on our table view staying at its initial size is wrong. Calculating before the move makes our preferred content size calculation correct, and everything resizes properly.
    [self _updatePreferredContentSizeFromOptions];
    
    [super willMoveToParentViewController:parent];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    UITableView *tableView = (UITableView *)self.view;
    if (tableView.scrollEnabled)
        [tableView flashScrollIndicators];
}

#pragma mark - UITableView dataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    if (section < 0 || (NSUInteger)section >= [_sections count]) {
        OBASSERT_NOT_REACHED("Unknown section index %ld", section);
        return 0;
    }
    
    OUIMenuOptionSection *sectionObject = _sections[section];
    if ([sectionObject isKindOfClass:[OUIMenuEmptySection class]]) {
        return 0;
    }
    
    return [sectionObject.options count];
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    if (section < 0 || (NSUInteger)section >= [_sections count]) {
        OBASSERT_NOT_REACHED("Unknown section requested at %ld", section);
        return @"??";
    }

    OUIMenuOptionSection *sectionObject = _sections[section];
    if ([sectionObject isKindOfClass:[OUIMenuEmptySection class]]) {
        return @" ";
    }
    
    NSString *title = sectionObject.title;
    if ([NSString isEmptyString:title]) {
        return nil;
    }
    return title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSInteger section = indexPath.section;
    if (section < 0 || (NSUInteger)section >= [_sections count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    }
    
    OUIMenuOptionSection *sectionObject = _sections[section];
    if ([sectionObject isKindOfClass:[OUIMenuEmptySection class]]) {
        OBASSERT_NOT_REACHED("Shouldn't have actual cells for empty sections");
        OUIMenuOptionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option"];
        if (!cell) {
            cell = [[OUIMenuOptionTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
            
            cell.textLabel.font = [UIFont systemFontOfSize:17];
            cell.textLabel.textAlignment = _textAlignment;
        }
        
        // Default transparency ...
        cell.opaque = NO;
        cell.backgroundColor = nil;
        
        cell.textLabel.opaque = NO;
        cell.textLabel.backgroundColor = nil;
        return cell;
    }

    NSArray <OUIMenuOption *> *options = sectionObject.options;
    NSInteger row = indexPath.row;

    if (row < 0 || (NSUInteger)row >= [options count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    }
    
    OUIMenuOption *option = options[row];

    // This is ugly, but the OmniJS options may get mutated by the validation hook, so get this before we look at anything else.
    BOOL enabled = option.isEnabled;

    OUIMenuOptionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option"];
    if (!cell) {
        cell = [[OUIMenuOptionTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
        
        cell.textLabel.font = [UIFont systemFontOfSize:17];
        cell.textLabel.textAlignment = _textAlignment;
    }
    
    // Default transparency ...
    cell.opaque = NO;
    cell.backgroundColor = nil;

    cell.textLabel.opaque = NO;
    cell.textLabel.backgroundColor = nil;

    // ... unless a menu option background color is otherwise requested
    OUIMenuController *controller = _weak_controller;
    UIColor *menuOptionBackgroundColor = [controller menuOptionBackgroundColor];
    if (menuOptionBackgroundColor != nil) {
        cell.textLabel.backgroundColor = [controller menuOptionBackgroundColor];
        cell.backgroundColor = [controller menuOptionBackgroundColor];
    }

    // Add a selectedBackgroundView if the menu controller requests it
    UIColor *menuOptionSelectionColor = [controller menuOptionSelectionColor];
    if (menuOptionSelectionColor != nil) {
        UIView *selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
        selectedBackgroundView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        selectedBackgroundView.backgroundColor = menuOptionSelectionColor;
        cell.selectedBackgroundView = selectedBackgroundView;
    }
    
    UILabel *label = cell.textLabel;
    label.text = option.title;
    
    if (option.attentionDotView) {
        cell.iconView = option.attentionDotView;
    } else if (option.image) {
        // can get a stale view if we're dequeued by scrolling
        [cell.iconView removeFromSuperview];
        cell.iconView = [[UIImageView alloc] initWithImage:[option.image imageWithRenderingMode:UIImageRenderingModeAutomatic]];
        cell.iconView.contentMode = UIViewContentModeScaleAspectFit;
    }
    
    OBASSERT_IF(option.destructive, option.action, "Cannot have a disabled destructive action");
    if (option.destructive) {
        UIColor *omniDeleteColor = [[OAAppearanceDefaultColors appearance] omniDeleteColor];
        label.textColor = omniDeleteColor;
        cell.imageView.tintColor = omniDeleteColor;
    }
    else if (enabled || [option.options count] > 0) {
        label.textColor = _tintColor;
        cell.imageView.tintColor = _tintColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        // Placeholder; one such case is in the 'move to folder' where some folders aren't valid destinations but are listed to show hierarchy
        label.textColor = [OUIInspector disabledLabelTextColor];
        cell.imageView.tintColor = [OUIInspector disabledLabelTextColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    cell.indentationWidth = kOUIMenuOptionIndentationWidth;
    cell.indentationLevel = option.indentationLevel;

#if 0
    if (_showsDividersBetweenOptions) {
        cell.showsFullwidthSeparator = YES;
        if (row == 0) {
            // Show top separator if our section has a header
            if ([[self tableView:tableView titleForHeaderInSection:indexPath.section] length] > 0) {
                cell.showsTopSeparator = YES;
            }
        }
        if (row == (NSInteger)options.count-1) {
            cell.isLastRowInSection = YES;
        }
    }
#endif

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
        if (option.wantsCheckmark) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryView = nil;
        }
    }
    
    [cell sizeToFit];
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSInteger section = indexPath.section;
    if (section < 0 || (NSUInteger)section >= [_sections count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return NO;
    }
    OUIMenuOptionSection *sectionObject = _sections[section];
    if ([sectionObject isKindOfClass:[OUIMenuEmptySection class]]) {
        return NO;
    }
    
    NSArray <OUIMenuOption *> *options = sectionObject.options;
    NSInteger row = indexPath.row;

    if (row < 0 || (NSUInteger)row >= [options count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return NO;
    }

    OUIMenuOption *option = options[row];

    if (option.action == nil && [option.options count] == 0)
        return NO; // Disabled placeholder action
    
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSInteger section = indexPath.section;
    if (section < 0 || (NSUInteger)section >= [_sections count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return;
    }

    OUIMenuOptionSection *sectionObject = _sections[section];
    if ([sectionObject isKindOfClass:[OUIMenuEmptySection class]]) {
        return;
    }
    
    NSArray <OUIMenuOption *> *options = sectionObject.options;
    NSInteger row = indexPath.row;

    if (row < 0 || (NSUInteger)row >= [options count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return;
    }

    OUIMenuOption *option = options[row];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (option.isEnabled) {
        OUIMenuOptionAction action = option.action;
        if (action) {
            [_weak_controller dismissAndInvokeOption:option];
        } else {
            [self _showSubmenuForParentOption:option];
        }
    }
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    NSString *title = [[self tableView:tableView titleForHeaderInSection:section] stringByRemovingWhitespace];
    if (title.length == 0) {
        // All whitespace title. Treat this header as a spacer, and make it simply the table view background color
        view.backgroundColor = UIColor.clearColor;
        if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
            UITableViewHeaderFooterView *header = OB_CHECKED_CAST(UITableViewHeaderFooterView, view);
            header.backgroundView.backgroundColor = UIColor.clearColor;
            header.contentView.backgroundColor = UIColor.clearColor;
        }
    }
}

#pragma mark - Private

+ (NSArray <OUIMenuOptionSection *> *)sectionsFromOptions:(NSArray <OUIMenuOption *> *)options;
{
    NSMutableArray *sections = [NSMutableArray array];
    __block OUIMenuOption *lastSeparator = nil;
    __block NSMutableArray <OUIMenuOption *> *currentSectionOptions = [NSMutableArray array];

    void (^flushSection)(OUIMenuOption *option) = ^(OUIMenuOption *option){
        if ([currentSectionOptions count] > 0) {
            // Empty section
            NSString *title = lastSeparator ?  lastSeparator.title : @"";
            OUIMenuOptionSection *section = [[OUIMenuOptionSection alloc] initWithTitle:title options:currentSectionOptions];
            [sections addObject:section];
        } else {
            if (lastSeparator == nil) {
                // We have requested a separator at the top of the table view. Make this option's title the title for the separator above the first section
                lastSeparator.title = option.title;
            } else {
                [sections addObject:[[OUIMenuEmptySection alloc] init]];
            }
        }

        lastSeparator = option;
        currentSectionOptions = [NSMutableArray array];
    };

    for (OUIMenuOption *option in options) {
        if (option.separator) {
            flushSection(option);
        } else {
            [currentSectionOptions addObject:option];
        }
    }

    // Emit the last group
    flushSection(nil);

    return sections;
}

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
    (void)[childController view];
    
    navigationController.navigationBarHidden = NO;
    [navigationController pushViewController:childController animated:YES];
}

- (void)_showSubmenu:(UIButton *)sender;
{
    UITableView *tableView = (UITableView *)self.view;
    UITableViewCell *cell = [sender enclosingViewOfClass:[UITableViewCell class]];
    NSIndexPath *indexPath = [tableView indexPathForCell:cell];

    NSInteger section = indexPath.section;
    if (section < 0 || (NSUInteger)section >= [_sections count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return;
    }

    OUIMenuOptionSection *sectionObject = _sections[section];
    if ([sectionObject isKindOfClass:[OUIMenuEmptySection class]]) {
        OBASSERT_NOT_REACHED("No subbmenu for empty header");
        return;
    }
    
    NSArray <OUIMenuOption *> *options = sectionObject.options;
    NSInteger row = indexPath.row;

    if (row < 0 || (NSUInteger)row >= [options count]) {
        OBASSERT_NOT_REACHED("Unknown menu item row requested at index path %@", indexPath);
        return;
    }

    OUIMenuOption *option = options[row];


    [self _showSubmenuForParentOption:option];
}

@end

NS_ASSUME_NONNULL_END
