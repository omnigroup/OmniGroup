// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerHomeScreenViewController.h>

#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIActivityIndicator.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniFileExchange/OFXDocumentStoreScope.h>
#import <OmniFileExchange/OFXServerAccount.h>

#import "OUIDocumentParameters.h"
#import "OUICloudSetupViewController.h"
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentPickerHomeScreenCell.h>

RCS_ID("$Id$")

#pragma mark Layout constants

static const CGFloat RowHeight = 250.0f;

#pragma mark - Cells

NSString *const HomeScreenCellReuseIdentifier = @"documentPickerHomeScreenCell";

#pragma mark - View Controller
@implementation OUIDocumentPickerHomeScreenViewController
{
    BOOL _finishedLoading;
    BOOL _includeTrash;
    NSMutableArray *_orderedScopes;
    NSIndexPath *_selectedIndexPath;
}

- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)documentPicker;
{
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(768, RowHeight);
    if (!(self = [super initWithCollectionViewLayout:layout]))
        return nil;
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Locations", @"OmniUIDocument", OMNI_BUNDLE, @"top level doc picker title");
    self.navigationItem.rightBarButtonItem = [[OUIAppController controller] newAppMenuBarButtonItem];
    
    if (!documentPicker)
        OBRejectInvalidCall(self, _cmd, @"documentPicker must not be nil");
    
    _documentPicker = documentPicker;
    [_documentPicker.documentStore addObserver:self forKeyPath:OFValidateKeyPath(_documentPicker.documentStore, scopes) options:0 context:nil];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    OBRejectInvalidCall(self, _cmd, @"Use -initWithDocumentPicker:");
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    OBRejectInvalidCall(self, _cmd, @"Use -initWithDocumentPicker:");
}

- (void)dealloc;
{
    ODSScope *trashScope = _documentPicker.documentStore.trashScope;
    [trashScope removeObserver:self forKeyPath:OFValidateKeyPath(trashScope, fileItems)];
    
    for (OFXDocumentStoreScope *scope in _orderedScopes)
        if ([scope isKindOfClass:[OFXDocumentStoreScope class]])
            [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, account.nickname)];
    
    [_documentPicker.documentStore removeObserver:self forKeyPath:OFValidateKeyPath(_documentPicker.documentStore, scopes)];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    ODSScope *trashScope = _documentPicker.documentStore.trashScope;
    if (object == trashScope) {
        BOOL newIncludeTrash = trashScope.fileItems.count > 0;
        
        if (newIncludeTrash != _includeTrash) {
            _includeTrash = newIncludeTrash;
            [self _updateOrderedScopes];
        }
    } else if (object == _documentPicker.documentStore) {
        [self _updateOrderedScopes];
    } else if ([object isKindOfClass:[OFXDocumentStoreScope class]]) {
        [_orderedScopes sortUsingSelector:@selector(compareDocumentScope:)];
        [self.collectionView reloadData];
    } else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    UICollectionView *collectionView = self.collectionView;

    collectionView.backgroundColor = [UIColor clearColor];
    [collectionView registerNib:[UINib nibWithNibName:@"OUIDocumentPickerHomeScreenCell" bundle:OMNI_BUNDLE] forCellWithReuseIdentifier:HomeScreenCellReuseIdentifier];

    // motion tilt under it all
    CGFloat maxTilt = 50;
    UIView *mobileBackground = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, -maxTilt, -maxTilt)];
    mobileBackground.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    mobileBackground.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"OUIDocumentPickerBackgroundTile.png"]];
    [mobileBackground addMotionMaxTilt:-maxTilt];
    [self.view insertSubview:mobileBackground atIndex:0];
    self.backgroundView = mobileBackground;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    [self.collectionView.visibleCells makeObjectsPerformSelector:@selector(resortPreviews)];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    [[OUIDocumentPickerViewController scopePreference] setStringValue:@""];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:NO];
}

#pragma mark - API

- (NSArray *)additionalScopeItems;
{
    return [NSArray array];
}

- (void)additionalScopeItemsDidChange;
{
    [self _updateOrderedScopes];
}

- (NSArray *)orderedScopeItems;
{
    return _orderedScopes;
}

- (void)_updateOrderedScopes;
{
    for (OFXDocumentStoreScope *scope in _orderedScopes)
        if ([scope isKindOfClass:[OFXDocumentStoreScope class]])
            [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, account.nickname)];
    
    _orderedScopes = [NSMutableArray arrayWithArray:_documentPicker.documentStore.scopes];
    if (!_includeTrash)
        [_orderedScopes removeObject:_documentPicker.documentStore.trashScope];
    [_orderedScopes removeObject:_documentPicker.documentStore.templateScope];
    
    for (OFXDocumentStoreScope *scope in _orderedScopes)
        if ([scope isKindOfClass:[OFXDocumentStoreScope class]])
           [scope addObserver:self forKeyPath:OFValidateKeyPath(scope, account.nickname) options:0 context:nil];

    [_orderedScopes sortUsingSelector:@selector(compareDocumentScope:)];
    
    NSUInteger additionalInsertionIndex = _orderedScopes.count;
    if (_includeTrash)
        additionalInsertionIndex--;
    [_orderedScopes replaceObjectsInRange:NSMakeRange(additionalInsertionIndex, 0) withObjectsFromArray:[self additionalScopeItems]];
    [self.collectionView reloadData];
}

- (void)finishedLoading;
{
    if (!_finishedLoading) {
        _finishedLoading = YES;

        ODSScope *trashScope = _documentPicker.documentStore.trashScope;
        [trashScope addObserver:self forKeyPath:OFValidateKeyPath(trashScope, fileItems) options:0 context:NULL];
        _includeTrash = trashScope.fileItems.count > 0;
        [self _updateOrderedScopes];
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView;
{
    if (!_finishedLoading)
        return 0;
    else
        return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
{
    OBPRECONDITION(_finishedLoading, "Asked for the number of rows when we haven't loaded yet!");
    OBPRECONDITION(section == 0);
    
    return _orderedScopes.count;
}

- (ODSScope <ODSConcreteScope> *)_scopeAtIndex:(NSUInteger)index;
{
    return _orderedScopes[index];
}

- (ODSFileItem *)_preferredVisibleItemFromSet:(NSSet *)set;
{
    for (id cell in self.collectionView.visibleCells) {
        if ([cell respondsToSelector:@selector(_preferredVisibleItemFromSet:)]) {
            ODSFileItem *result = [cell _preferredVisibleItemFromSet:set];
            if (result)
                return result;
        }
    }
    return nil;
}

- (OUIDocumentPickerHomeScreenCell *)selectedCell;
{
    [self.collectionView layoutIfNeeded];
    return (OUIDocumentPickerHomeScreenCell *)[self.collectionView cellForItemAtIndexPath:_selectedIndexPath];
}

- (void)selectCellForScope:(ODSScope *)scope;
{
    NSUInteger index = [_orderedScopes indexOfObjectIdenticalTo:scope];
    _selectedIndexPath = [NSIndexPath indexPathForRow:index inSection:0];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(indexPath.section == 0);
    
    OUIDocumentPickerHomeScreenCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:HomeScreenCellReuseIdentifier forIndexPath:indexPath];
    
    ODSScope<ODSConcreteScope> *scope = [self _scopeAtIndex:indexPath.item];
    cell.textLabel.text = scope.displayName;
    cell.picker = _documentPicker;
    cell.scope = scope;
    
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIDocumentPickerHomeScreenCell *cell = (OUIDocumentPickerHomeScreenCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
    if ([cell isKindOfClass:[OUIDocumentPickerHomeScreenCell class]])
        cell.coverView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:0.95];
}

- (void)collectionView:(UICollectionView *)collectionView didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIDocumentPickerHomeScreenCell *cell = (OUIDocumentPickerHomeScreenCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
    if ([cell isKindOfClass:[OUIDocumentPickerHomeScreenCell class]])
        cell.coverView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.95];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(_finishedLoading);
    OBPRECONDITION(indexPath.section == 0);
    
    [self collectionView:collectionView didHighlightItemAtIndexPath:indexPath];
    OUIDisplayNeededViews();
    
    _selectedIndexPath = indexPath;
    
    ODSScope *scope = [self _scopeAtIndex:indexPath.item];

    OUIDocumentPickerFilter *filter ;
    OFPreference *filterPreference = [OUIDocumentPickerViewController filterPreference];
    [filterPreference setStringValue:filter.identifier];

    OUIDocumentPickerViewController *picker = [[OUIDocumentPickerViewController alloc] initWithDocumentPicker:_documentPicker scope:scope];
    [self.navigationController pushViewController:picker animated:YES];
    
    [self collectionView:collectionView didUnhighlightItemAtIndexPath:indexPath];
}

@end
