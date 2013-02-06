// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAbstractTableViewInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/UITableView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIAbstractTableViewInspectorSlice
{
    UITableView *_tableView;
}

- (void)dealloc;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    [_tableView release];
    
    [super dealloc];
}

- (UITableView *)tableView;
{
    if (!_tableView)
        [self view];
    OBASSERT(_tableView);
    return _tableView;
}

#pragma mark - OUIInspectorSlice subclass

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    [_tableView reloadData];
    OUITableViewAdjustHeightToFitContents(_tableView);
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    OBPRECONDITION(_tableView == nil);
    
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 420) style:UITableViewStyleGrouped];
    
    // Subclasses must implement these protocols -- this class just does the UIViewController and OUIInspectorSlice glue code dealing with the view property being a UITableView.
    OBASSERT([self conformsToProtocol:@protocol(UITableViewDataSource)]);
    OBASSERT([self conformsToProtocol:@protocol(UITableViewDelegate)]);
    
    _tableView.delegate = (id <UITableViewDelegate>)self;
    _tableView.dataSource = (id <UITableViewDataSource>)self;
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

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
{
    return 12;
}

@end
