// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniBase/OmniBase.h>

#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerHomeScreenViewController.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>

#import "OUIDocumentHomeScreenAnimator.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerAdaptableContainerViewController.h"
#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentSubfolderAnimator.h"
#import "OUIDocumentTemplateAnimator.h"

RCS_ID("$Id$")

@interface OUIDocumentPicker () <UINavigationControllerDelegate>
@property (nonatomic, readonly) UINavigationController *topLevelNavigationController;
@property (nonatomic, strong) OUIDocumentPickerAdaptableContainerViewController *homeScreenContainer;
@property (nonatomic, strong) OUIDocumentPickerHomeScreenViewController *homeScreenViewController;
@end

@implementation OUIDocumentPicker
{
    BOOL _isSetUpForCompact;
    BOOL _receivedShowDocuments;
    NSString *scopeIdentifierToSelect;
}

- (instancetype)init;
{
    OBRejectUnusedImplementation(self, _cmd); // use -initWithDocumentStore:
}

- (instancetype)initWithDocumentStore:(ODSStore *)documentStore;
{
    if (!(self = [super init]))
        return nil;
    
    _documentStore = documentStore;
    
    return self;
}

#pragma mark - API

- (UINavigationController *)topLevelNavigationController;
{
    return OB_CHECKED_CAST(UINavigationController, self.wrappedViewController);
}

@synthesize homeScreenViewController = _homeScreenViewController;

- (OUIDocumentPickerHomeScreenViewController *)homeScreenViewController;
{
    if (!_homeScreenViewController) {
        if ([_delegate respondsToSelector:@selector(documentPickerHomeViewController:)])
            _homeScreenViewController = [_delegate documentPickerHomeViewController:self];
        else
            _homeScreenViewController = [[OUIDocumentPickerHomeScreenViewController alloc] initWithDocumentPicker:self];
    }
    
    return _homeScreenViewController;
}

@synthesize homeScreenContainer = _homeScreenContainer;

- (OUIDocumentPickerAdaptableContainerViewController *)homeScreenContainer;
{
    if (!_homeScreenContainer) {
        _homeScreenContainer = [[OUIDocumentPickerAdaptableContainerViewController alloc] init];
        _homeScreenContainer.backgroundView.image = [[OUIDocumentAppController controller] documentPickerBackgroundImage];
    }
    
    return _homeScreenContainer;
}

- (void)_populateHomeScreenAndNavigationToScopeFromPreferences;
{
    ODSScope *selectScope = nil;
    NSString *identifier = [[OUIDocumentPickerViewController scopePreference] stringValue];
    NSString *folderPath = [[OUIDocumentPickerViewController folderPreference] stringValue];
    
    [_homeScreenViewController finishedLoading];
    
    for (ODSScope *scope in _documentStore.scopes) {
        if ([identifier isEqualToString:scope.identifier]) {
            selectScope = scope;
            break;
        }
    }
    if (selectScope) {
        ODSItem *folder = [selectScope.rootFolder itemWithRelativePath:folderPath];
        if (folder && folder.type == ODSItemTypeFolder) {
            [self navigateToFolder:(ODSFolderItem *)folder animated:NO];
        } else
            [self navigateToScope:selectScope animated:NO];
    }
}

- (void)showDocuments;
{
    _receivedShowDocuments = YES;
    
    if (_homeScreenViewController) {
        // We got -showDocuments after -viewWillAppear:
        [self _populateHomeScreenAndNavigationToScopeFromPreferences];
    }
}

- (void)_endEditingMode;
{
    OUIDocumentPickerViewController *topVC = (OUIDocumentPickerViewController *)self.topLevelNavigationController.topViewController;
    if ([topVC isKindOfClass:[OUIDocumentPickerViewController class]])
        topVC.editing = NO;
}

- (void)navigateToFolder:(ODSFolderItem *)folderItem animated:(BOOL)animated;
{
    OBPRECONDITION(folderItem.scope != nil);
    
    [self _endEditingMode];
    
    NSMutableArray *newViewControllers = [[NSMutableArray alloc] init];
    
    NSArray *existingViewControllers = self.topLevelNavigationController.viewControllers;
    while (folderItem) {
        OUIDocumentPickerViewController *viewController = nil;
        for (NSUInteger i = 1; i < existingViewControllers.count; i++) {
            OUIDocumentPickerViewController *candidateViewController = existingViewControllers[i];
            OBASSERT([candidateViewController isKindOfClass:[OUIDocumentPickerViewController class]]);
            if (candidateViewController.folderItem == folderItem) {
                viewController = candidateViewController;
                break;
            }
        }
        
        if (!viewController) {
            ODSScope *scope = folderItem.scope;
            if (folderItem == scope.rootFolder)
                viewController = [[OUIDocumentPickerViewController alloc] initWithDocumentPicker:self scope:scope];
            else
                viewController = [[OUIDocumentPickerViewController alloc] initWithDocumentPicker:self folderItem:folderItem];
        }
        
        [newViewControllers insertObject:viewController atIndex:0];
        folderItem = folderItem.parentFolder;
    }
    
    [newViewControllers insertObject:existingViewControllers[0] atIndex:0];
    [self.topLevelNavigationController setViewControllers:newViewControllers animated:animated];
}

- (void)navigateToContainerForItem:(ODSItem *)item animated:(BOOL)animated;
{
    UINavigationController *topLevelNavController = self.topLevelNavigationController;
    
    ODSScope *scope = item.scope;
    if (!scope || ![_documentStore.scopes containsObject:scope]) {
        [topLevelNavController popToRootViewControllerAnimated:animated];
        return;
    } else if (topLevelNavController.viewControllers.count > 1 && ![topLevelNavController.viewControllers.lastObject isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]] && [[(OUIDocumentPickerViewController *)topLevelNavController.viewControllers.lastObject filteredItems] containsObject:item]) {
        return;
    } else {
        ODSFolderItem *folder = [scope folderItemContainingItem:item];
        if (folder)
            [self navigateToFolder:folder animated:animated];
        else {
            OBASSERT([scope.rootFolder.childItems containsObject:item], @"Item %@ is contained by scope %@ but isn't at the root or in any descendant folders", item, scope);
            [self navigateToScope:scope animated:animated];
        }
    }
}

- (void)navigateToScope:(ODSScope *)scope animated:(BOOL)animated;
{
    [self _endEditingMode];
    
    OUIDocumentPickerViewController *picker = [[OUIDocumentPickerViewController alloc] initWithDocumentPicker:self scope:scope];
    [self.topLevelNavigationController popToRootViewControllerAnimated:NO];
    [self.topLevelNavigationController pushViewController:picker animated:animated];
}


- (ODSScope *)localDocumentsScope;
{
    NSArray *sorted = [_documentStore.scopes sortedArrayUsingSelector:@selector(compareDocumentScope:)];
    return [sorted objectAtIndex:0];
}

- (OUIDocumentPickerViewController *)selectedScopeViewController;
{
    if (self.topLevelNavigationController.viewControllers.count < 2)
        return nil;
    else {
        UIViewController *viewController = self.topLevelNavigationController.topViewController;
        OBASSERT([viewController isKindOfClass:[OUIDocumentPickerViewController class]]);
        return (OUIDocumentPickerViewController *)viewController;
    }
}

- (void)enableAppMenuBarButtonItem:(BOOL)enable;
{
    for (UIBarButtonItem *item in self.homeScreenContainer.navigationItem.rightBarButtonItems) {
        if ([item.target isKindOfClass:[OUIAppController class]]) {
            item.enabled = enable;
        }
    }
}

#pragma mark - UIViewController subclass

- (void)_setUpNavigationControllerForTraitCollection:(UITraitCollection *)traitCollection unconditionally:(BOOL)unconditional;
{
    BOOL traitCollectionIsCompact = traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact || traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
    
    if (!unconditional && (traitCollectionIsCompact == _isSetUpForCompact))
        return;
 
    UINavigationController *topLevelNavController = self.topLevelNavigationController;
    OUIDocumentPickerHomeScreenViewController *home = self.homeScreenViewController;
    OUIDocumentPickerAdaptableContainerViewController *container = self.homeScreenContainer;
    
    if (traitCollectionIsCompact) {
        // In a compact environment, we want all view controllers to exist in the outer navigation controller, and to promote the homeScreenViewController out of its homeScreenContainer.
        
        NSMutableArray *viewControllersToPromote = [[container popViewControllersForTransitionToCompactSizeClass] mutableCopy];
        OBASSERT_IF(viewControllersToPromote.count > 1, [topLevelNavController.viewControllers count] <= 1, "Somehow we are navigated into both a storage location and something in the home screen. Should only be navigated into one controller at a time!");
        
        if (viewControllersToPromote.count == 0)
            [viewControllersToPromote addObject:home];
        else
            viewControllersToPromote[0] = home;
        
        [topLevelNavController setViewControllers:viewControllersToPromote];
    } else {
        // In the regular-regular environment, we want an outer navigation controller that contains only the homeScreenContainer and any storage-location navigation. The homeScreenContainer's navigation controller should contain any view controllers for editing details of storage locations.
        
        NSMutableArray *topLevelNavStack = [NSMutableArray arrayWithArray:topLevelNavController.viewControllers];
        NSUInteger topLevelCount = topLevelNavStack.count;
        NSMutableArray *innerNavStack = [NSMutableArray arrayWithObject:home];

        if (topLevelCount == 0)
            [topLevelNavStack addObject:container];
        else
            topLevelNavStack[0] = container;
            
        if (topLevelCount > 1) {
            if ([topLevelNavStack[1] isKindOfClass:[OUIDocumentPickerViewController class]]) {
                // We're navigated into a storage location; all view controllers stay in the outer navigation controller.
            } else {
                NSRange rangeToMove = NSMakeRange(1, topLevelCount - 1);
                [innerNavStack addObjectsFromArray:[topLevelNavStack subarrayWithRange:rangeToMove]];
                [topLevelNavStack removeObjectsInRange:rangeToMove];
            }
        }
        
        [topLevelNavController setViewControllers:topLevelNavStack];
        [container pushViewControllersForTransitionToRegularSizeClass:innerNavStack];
    }
    
    _isSetUpForCompact = traitCollectionIsCompact;
}

- (void)willTransitionToTraitCollection:(UITraitCollection *)newCollection withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
{
    [self _setUpNavigationControllerForTraitCollection:newCollection unconditionally:NO];
    [super willTransitionToTraitCollection:newCollection withTransitionCoordinator:coordinator];
}

- (void)viewWillAppear:(BOOL)animated;
{
    if (!self.wrappedViewController) {
        UINavigationController *navigationController = [[UINavigationController alloc] init];
        navigationController.delegate = self;
        self.wrappedViewController = navigationController;
        
        [self _setUpNavigationControllerForTraitCollection:self.traitCollection unconditionally:YES];
        
        if (_receivedShowDocuments) {
            // We got -showDocuments before -viewWillAppear:
            [self _populateHomeScreenAndNavigationToScopeFromPreferences];
        }
    }
    
    [super viewWillAppear:animated];
}

- (UIStatusBarStyle)preferredStatusBarStyle;
{
    if (((UINavigationController *)self.wrappedViewController).viewControllers.count == 1)
        return UIStatusBarStyleLightContent;
    else
        return UIStatusBarStyleDefault;
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    UINavigationBar *navBar = navigationController.navigationBar;
    UIImage *backgroundImage;
    UIColor *barTintColor;
    NSDictionary *barTitleAttributes;
    
    if (!_isSetUpForCompact && (viewController == _homeScreenContainer || viewController == _homeScreenViewController)) {
        static UIImage *blankImage;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            blankImage = [UIImage new];
        });
        
        backgroundImage = blankImage;
        barTintColor = [[OmniUIDocumentAppearance appearance] documentPickerTintColorAgainstBackground];
        barTitleAttributes = @{NSForegroundColorAttributeName : barTintColor};
    } else {
        backgroundImage = nil;
        barTintColor = nil;
        barTitleAttributes = nil;
    }
    
    [navBar setBackgroundImage:backgroundImage forBarMetrics:UIBarMetricsCompact];
    [navBar setBackgroundImage:backgroundImage forBarMetrics:UIBarMetricsCompactPrompt];
    [navBar setBackgroundImage:backgroundImage forBarMetrics:UIBarMetricsDefault];
    [navBar setBackgroundImage:backgroundImage forBarMetrics:UIBarMetricsDefaultPrompt];
    
    [navBar setShadowImage:backgroundImage];
    
    navBar.tintColor = barTintColor;
    navBar.titleTextAttributes = barTitleAttributes;
    
    [self setNeedsStatusBarAppearanceUpdate];
}

- (id <UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                   animationControllerForOperation:(UINavigationControllerOperation)operation
                                                fromViewController:(UIViewController *)fromVC
                                                  toViewController:(UIViewController *)toVC;
{
    if ([fromVC isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]] || [toVC isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]]) {
        return [OUIDocumentTemplateAnimator sharedAnimator];
    } else if ([toVC isKindOfClass:[OUIDocumentPickerViewController class]] && [fromVC isKindOfClass:[OUIDocumentPickerViewController class]]) {
        return [OUIDocumentSubfolderAnimator sharedAnimator];
    } else if (self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact && self.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassCompact && operation != UINavigationControllerOperationNone) {
        OUIDocumentHomeScreenAnimator *animator = [[OUIDocumentHomeScreenAnimator alloc] init];
        animator.pushing = (operation == UINavigationControllerOperationPush);
        return animator;
    }
    return nil;
}

#pragma mark - Internal

- (void)navigateForDeletionOfFolder:(ODSFolderItem *)deletedItem animated:(BOOL)animated;
{
    ODSFolderItem *parentFolder = nil;
    
    for (UIViewController *vc in self.topLevelNavigationController.viewControllers) {
        if (![vc isKindOfClass:[OUIDocumentPickerViewController class]])
            continue;
        else {
            ODSFolderItem *folderItem = ((OUIDocumentPickerViewController *)vc).folderItem;
            if (folderItem == deletedItem)
                break;
            else
                parentFolder = folderItem;
        }
    }
    
    if (parentFolder)
        [self navigateToFolder:parentFolder animated:animated];
    else
        [self navigateToScope:deletedItem.scope animated:animated];
}

- (ODSFileItem *)preferredVisibleItemForNextPreviewUpdate:(NSSet *)eligibleItems;
{
    UIViewController *top = self.topLevelNavigationController.topViewController;
    
    if ([top isKindOfClass:[OUIDocumentPickerViewController class]])
        return [(OUIDocumentPickerViewController *)top _preferredVisibleItemFromSet:eligibleItems];
    else
        return nil;
}

- (NSArray *)availableFiltersForScope:(ODSScope *)scope;
{
    // do not allow filtering on the trash scope.
    if (scope.isTrash)
        return @[];
    
    if ([_delegate respondsToSelector:@selector(documentPickerAvailableFilters:)])
        return [_delegate documentPickerAvailableFilters:self];
    
    else
        return @[];
}

@end
