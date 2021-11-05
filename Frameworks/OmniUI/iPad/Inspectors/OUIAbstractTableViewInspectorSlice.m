// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAbstractTableViewInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/UITableView-OUIExtensions.h>

#define UPPERCASE_LABELS    (1)

@interface OUIInspectorTableViewHeaderFooterView : UITableViewHeaderFooterView
@end

@interface OUIAbstractTableViewSectionHeaderView : UIView
@property (readwrite,nonatomic,strong) UILabel *label;
@property (readwrite,nonatomic,strong) UIButton *actionButton;
@end

@implementation OUIAbstractTableViewInspectorSlice
{
    UITableView *_tableView;
}

static NSString *_editActionButtonTitle;
static NSString *_doneActionButtonTitle;

+ (NSString *)editActionButtonTitle;
{
    if (!_editActionButtonTitle) {
        _editActionButtonTitle = [self tableViewLabelForLabel:NSLocalizedStringFromTableInBundle(@"Edit", @"OUIInspectors", OMNI_BUNDLE, @"edit action title")];
    }
    return _editActionButtonTitle;
}

+ (NSString *)doneActionButtonTitle;
{
    if (!_doneActionButtonTitle) {
        _doneActionButtonTitle = [self tableViewLabelForLabel:NSLocalizedStringFromTableInBundle(@"Done", @"OUIInspectors", OMNI_BUNDLE, @"done action title")];
    }
    return _doneActionButtonTitle;
}

+ (NSString *)tableViewLabelForLabel:(NSString *)label;
{
#if UPPERCASE_LABELS
    label = [label uppercaseStringWithLocale:[NSLocale currentLocale]];
#endif
    return label;
}

+ (void)updateHeaderButton:(UIButton *)button withTitle:(NSString *)title;
{
    title = [self tableViewLabelForLabel:title];
    [button setTitle:title forState:UIControlStateNormal];
    [button sizeToFit];
}

+ (UIButton *)headerActionButtonWithTitle:(NSString *)title section:(NSInteger)section;
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIFont *textFont = [UIFont systemFontOfSize:[UIFont systemFontSize]];
    button.titleLabel.font = textFont;
    button.tag = section;
    [self updateHeaderButton:button withTitle:title];
    return button;
}

+ (UIColor *)headerTextColor;
{
    return [OUIInspector headerTextColor];
}

+ (UILabel *)headerLabelWithText:(NSString *)labelString;
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    UIFont *textFont = [UIFont systemFontOfSize:[UIFont systemFontSize]];
    label.font = textFont;
    label.textColor = self.headerTextColor;
    labelString = [self tableViewLabelForLabel:labelString];
    label.text = labelString;
    [label sizeToFit];

    return label;
}

+ (UIView *)sectionHeaderViewWithLabelText:(NSString *)labelString actionTitle:(NSString *)actionTitle actionTarget:(id)actionTraget action:(SEL)action section:(NSInteger)section forTableView:(UITableView *)tableView;
{
    UIEdgeInsets separatorInset = tableView.separatorInset;
    CGRect headerFrame = CGRectMake(0, 0, separatorInset.left + separatorInset.right, 0);
    OUIAbstractTableViewSectionHeaderView *headerView = [[OUIAbstractTableViewSectionHeaderView alloc] initWithFrame:headerFrame];
    
    UILabel *label = [self headerLabelWithText:labelString];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textColor = [OUIInspector headerTextColor];
    headerView.label = label;

    UIEdgeInsets edgeInsets = OUIInspectorSlice.sliceAlignmentInsets;

    [headerView addSubview:label];
    CGFloat descender = label.font.descender;
    [label.leadingAnchor constraintEqualToAnchor:headerView.safeAreaLayoutGuide.leadingAnchor constant:edgeInsets.left].active = YES;
    [label.firstBaselineAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-10 + descender].active = YES;
    [headerView.heightAnchor constraintEqualToConstant:44].active = YES;
    
    if (actionTitle) {
        OBASSERT_NOTNULL(action, @"Please provde an action if you want to use a buton in the headerView");
        
        UIButton *actionButton = [OUIAbstractTableViewInspectorSlice headerActionButtonWithTitle:actionTitle section:section];
        actionButton.translatesAutoresizingMaskIntoConstraints = NO;

        headerView.actionButton = actionButton;
        [actionButton addTarget:actionTraget action:action forControlEvents:UIControlEventTouchUpInside];

        [headerView addSubview:actionButton];
        [actionButton.firstBaselineAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-10 + descender].active = YES;
        [headerView.safeAreaLayoutGuide.trailingAnchor constraintEqualToAnchor:actionButton.trailingAnchor constant:edgeInsets.right].active = YES;
        [actionButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:8.0f].active = YES;

    } else {
        [headerView.trailingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:edgeInsets.left].active = YES;
    }

    headerView.backgroundColor = [OUIInspector backgroundColor];
    OBASSERT(headerView.backgroundColor != nil, "Clear backgrounds cause the header view's text to overlap the font names, and that looks bad.");
    
    return headerView;
}

+ (UIView *)sectionHeaderViewWithLabelText:(NSString *)labelString useDefaultActionButton:(BOOL)useDefaultActionButton target:(id)target section:(NSInteger)section forTableView:(UITableView *)tableView;
{
    if (useDefaultActionButton) {
        return [self sectionHeaderViewWithLabelText:labelString actionTitle:OUIAbstractTableViewInspectorSlice.editActionButtonTitle actionTarget:target action:@selector(toggleEditingForSection:) section:section forTableView:tableView];
    } else {
        return [self sectionHeaderViewWithLabelText:labelString forTableView:tableView];
    }
}

+ (UIView *)sectionHeaderViewWithLabelText:(NSString *)labelString forTableView:(UITableView *)tableView;
{
    return [self sectionHeaderViewWithLabelText:labelString actionTitle:nil actionTarget:nil action:nil section:0 forTableView:tableView];
}

- (void)dealloc;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

- (UITableView *)tableView;
{
    if (!_tableView)
        (void)[self view];
    OBASSERT(_tableView);
    return _tableView;
}

- (void)_resizeTable;
{
    OUITableViewAdjustHeightToFitContents(_tableView);
    CGFloat currentHeight = self.tableView.contentSize.height;
    if (currentHeight == 0.0)
        return;
    
    if (self.heightConstraint == nil) {
        self.heightConstraint = [self.tableView.heightAnchor constraintEqualToConstant:currentHeight];
        self.heightConstraint.active = YES;
    } else {
        self.heightConstraint.constant = currentHeight;
    }
}

- (void)reloadTableAndResize;
{
    _tableView.editing = NO;
    [_tableView reloadData];
    [self _resizeTable];
}

- (void)toggleEditingForSection:(id)sender;
{
    UITableView *tableView = self.tableView;
    UIButton *button = nil;
    if ([sender isKindOfClass:UIButton.class]) {
        button = (UIButton *)sender;
    }
    BOOL isEditing = !tableView.isEditing;
    if (button) {
        NSString *buttonTitle = isEditing ? OUIAbstractTableViewInspectorSlice.doneActionButtonTitle : OUIAbstractTableViewInspectorSlice.editActionButtonTitle;
        [OUIAbstractTableViewInspectorSlice updateHeaderButton:button withTitle:buttonTitle];
    }
    tableView.editing = isEditing;
}

#pragma mark - OUIInspectorSlice subclass

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    [self reloadTableAndResize];
}

#pragma mark - UIViewController subclass

- (UITableViewStyle)tableViewStyle;
{
    return UITableViewStyleGrouped;
}

- (void)loadView;
{
    OBPRECONDITION(_tableView == nil);
    
    // Work around radar 35175843
    _tableView = [[UITableView alloc] initWithFrame:[UIScreen mainScreen].bounds style:[self tableViewStyle]];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Subclasses must implement these protocols -- this class just does the UIViewController and OUIInspectorSlice glue code dealing with the view property being a UITableView.
    OBASSERT([self conformsToProtocol:@protocol(UITableViewDataSource)]);
    OBASSERT([self conformsToProtocol:@protocol(UITableViewDelegate)]);

    _tableView.backgroundColor = [OUIInspector backgroundColor];
    _tableView.separatorColor = [OUIInspectorSlice sliceSeparatorColor];
    _tableView.delegate = (id <UITableViewDelegate>)self;
    _tableView.dataSource = (id <UITableViewDataSource>)self;
    
    _tableView.estimatedRowHeight = 0;
    _tableView.estimatedSectionHeaderHeight = 0;
    _tableView.estimatedSectionFooterHeight = 0;
    
    UIView *view = [[UIView alloc] init];
    [view addSubview:_tableView];

    [_tableView.topAnchor constraintEqualToAnchor:view.topAnchor].active = YES;
    [_tableView.rightAnchor constraintEqualToAnchor:view.rightAnchor].active = YES;
    [_tableView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor].active = YES;
    [_tableView.leftAnchor constraintEqualToAnchor:view.leftAnchor].active = YES;
    
    self.view = view;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [self configureTableViewBackground:_tableView];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    //If we are inspecting a new type of graphic for the first time (like tapping a graphic when we first open the document) the it is possible for the table view to have no content. We then try to resize an empty table view to fit its content size, but the table view has no contents and the resize function expects the table view to have contents. So, make sure we have contents first.
    [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self _resizeTable];

    [super viewDidAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    if ([_tableView isEditing])
        [self setEditing:NO animated:NO];

    [super viewDidDisappear:animated];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    [super setEditing:editing animated:animated]; // updates our editingButtonItem
    [_tableView setEditing:editing animated:animated];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;
{
    OUIInspectorTableViewHeaderFooterView *view = [[OUIInspectorTableViewHeaderFooterView alloc] init];
    view.backgroundColor = [OUIInspector backgroundColor];
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
{
    return 12;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section;
{
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = [OUIInspector backgroundColor];
    return view;
}

@end

@implementation OUIAbstractTableViewSectionHeaderView
@end

@implementation OUIInspectorTableViewHeaderFooterView
@end

