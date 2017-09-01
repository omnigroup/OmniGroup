// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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
#import <OmniUI/UIPopoverPresentationController-OUIExtensions.h>

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

#if 0 && defined(DEBUG_shannon)
- (NSString*)description{
    __block NSString *usefulDescription = [super description];
    usefulDescription = _isSetUpForCompact ? [usefulDescription stringByAppendingString:@" (compact)"] : [usefulDescription stringByAppendingString:@" (regular)"];
    usefulDescription = [usefulDescription stringByAppendingFormat:@"\n\ttopLevelNavController: %@ {", self.topLevelNavigationController];
    if (self.topLevelNavigationController.viewControllers.count) {
        [self.topLevelNavigationController.viewControllers enumerateObjectsUsingBlock:^(__kindof UIViewController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            usefulDescription  = [usefulDescription stringByAppendingFormat:@"\n\t\t[%lu]%@", (unsigned long)idx, obj];
        }];
    } else {
        usefulDescription = [usefulDescription stringByAppendingFormat:@"\n\t\tno view controllers"];
    }
    usefulDescription = [usefulDescription stringByAppendingString:@"\n\t}"];
    return usefulDescription;
}
#endif

- (UINavigationController *)topLevelNavigationController;
{
    return OB_CHECKED_CAST_OR_NIL(UINavigationController, self.wrappedViewController);
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
    if ([existingViewControllers count] == 0) {
        OBASSERT_NOT_REACHED("How can this happen? Cold launch of some sort?");
        [self _setUpNavigationControllerForTraitCollection:self.traitCollection unconditionally:YES];
    }
    existingViewControllers = self.topLevelNavigationController.viewControllers;

    while (folderItem) {
        OUIDocumentPickerViewController *viewController = nil;
        for (NSUInteger i = 1; i < existingViewControllers.count; i++) {
            // This won't be a OUIDocumentPickerViewController in the case that you've navigated into something like settings or OUIAddCloudAccountViewController.
            __kindof UIViewController *candidateViewController = existingViewControllers[i];
            if ([candidateViewController isKindOfClass:[OUIDocumentPickerViewController class]]) {
                if ([candidateViewController folderItem] == folderItem) {
                    viewController = candidateViewController;
                    break;
                }
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

    // <bug:///121867> (Crasher: Crash launching from Spotlight or 3D Touch to a document save in a subfolder -[__NSArrayM insertObject:atIndex:]: object cannot be nil)
    // This is not actually true when launching from a shortcut. It would be good to make this true in another way (since other code might depend on it being in the stack), but for now, we'll just use the home screen controller directly.
    UIViewController *homeViewController = [existingViewControllers firstObject];
    OBASSERT(homeViewController == self.homeScreenViewController || homeViewController == self.homeScreenContainer);

    if (homeViewController)
        [newViewControllers insertObject:homeViewController atIndex:0];

    [self.topLevelNavigationController setViewControllers:newViewControllers animated:animated];
}


/**
 @param item The thing we want visible in the document picker
 @param dismissOpenDocument Should we go ahead and hide the document?
 @param animated
 @return Did we find a container to navigate to?
 */
- (BOOL)navigateToContainerForItem:(ODSItem *)item dismissingAnyOpenDocument:(BOOL)dismissOpenDocument animated:(BOOL)animated;
{
    UINavigationController *topLevelNavController = self.topLevelNavigationController;

    __block ODSScope *scope = item.scope;
    if (!scope || [scope isExternal] || ![_documentStore.scopes containsObject:scope]) {
        // The item is external or otherwise unfindable
        return NO;
    }

    ODSFolderItem* containingFolder = [scope folderItemContainingItem:item];
    if (containingFolder == nil && ![scope.rootFolder.childItems containsObject:item]) {
        // The scope doesn't have it.
        return NO;
    }

    void (^completionBlock)(void) = ^() {
        if (topLevelNavController.viewControllers.count > 1
                   && ![topLevelNavController.viewControllers.lastObject isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]]
                   && [topLevelNavController.viewControllers.lastObject respondsToSelector:@selector(filteredItems)]
                   && [[(OUIDocumentPickerViewController *)topLevelNavController.viewControllers.lastObject filteredItems] containsObject:item]) {
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
    };


    if ([topLevelNavController presentedViewController] && dismissOpenDocument) {
        [topLevelNavController dismissViewControllerAnimated:NO completion:completionBlock];
    } else {
        completionBlock();
    }
    return YES;
}

// Navigate to the item if possible, otherwise navigate *somewhere* sensible
- (void)navigateToBestEffortContainerForItem:(ODSFileItem *)fileItem
{
    BOOL success = [self navigateToContainerForItem:fileItem dismissingAnyOpenDocument:NO animated:NO];
    if (!success) {
        [self navigateToScope:[self localDocumentsScope] animated:NO];
    }
}

- (void)navigateToScope:(ODSScope *)scope animated:(BOOL)animated;
{
#if defined(DEBUG_lizard)
    if ([scope isExternal]) {
        OBStopInDebugger("<bug:///147708> (Frameworks-iOS Bug: Remove Other Documents)");
    }
#endif
    [self _endEditingMode];
    
    // dismiss any modals
    [self dismissViewControllerAnimated:NO completion:nil];
    // make sure that the OUIDocumentPickerHomeScreenViewController is at the root of the navigation stack
    UIViewController *topController = self.topLevelNavigationController.topViewController;
    UINavigationController *actualNavController;
    if ([topController isKindOfClass:[OUIDocumentPickerAdaptableContainerViewController class]]) {
        OUIDocumentPickerAdaptableContainerViewController *adaptableContainerViewController = OB_CHECKED_CAST(OUIDocumentPickerAdaptableContainerViewController, self.topLevelNavigationController.topViewController);
        actualNavController = OB_CHECKED_CAST(UINavigationController, adaptableContainerViewController.wrappedViewController);
    } else {
        actualNavController = self.topLevelNavigationController;
    }
    [actualNavController popToRootViewControllerAnimated:NO];

    OUIDocumentPickerViewController *picker = [[OUIDocumentPickerViewController alloc] initWithDocumentPicker:self scope:scope];
    [self.topLevelNavigationController pushViewController:picker animated:animated];
}

- (void)editSettingsForAccount:(OFXServerAccount *)account;
{
    [self _endEditingMode];
    
#ifdef OMNI_ASSERTIONS_ON
    // We need to pop to either the homeScreenContainer or the homeScreenViewController. This depends on size classes, but one of those should ALWAYS be at the root of topLevelNavigationController. So now we just assert and unconditionally call -popToRootViewController:.
    UIViewController *navRootVC = [self.topLevelNavigationController.viewControllers firstObject];
    OBASSERT([navRootVC isKindOfClass:[self.homeScreenContainer class]] || [navRootVC isKindOfClass:[self.homeScreenViewController class]]);
#endif
    
    // This was originally setup to pop non-animated and then -editSettingsForAccount: below would end up pushing a new view controller on. Under some circumstances, this was causing our view/view controllers to be left in an unuseable state. (See bug:///111954) Popping with animation and using the transition coordinator to push the new view controller once the pop animation completes seems to work, and we have the added bonus of keeping the user's context. (They get to see the pop and push to the 'edit creds' screen.)
    [self.topLevelNavigationController popToRootViewControllerAnimated:YES];
    [self.topLevelNavigationController.transitionCoordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Nothing to do here, we just want the completion handler
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.homeScreenViewController editSettingsForAccount:account];
    }];
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
        if ([viewController isKindOfClass:[OUIDocumentPickerViewController class]]) {
            return (OUIDocumentPickerViewController *)viewController;
        }else{
            return nil;
        }
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

- (void) presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion
{
    if (viewControllerToPresent.popoverPresentationController) {
        UIPopoverPresentationController *popoverPresentationController = viewControllerToPresent.popoverPresentationController;
        
        UINavigationController *navController = (UINavigationController *) self.wrappedViewController;
        NSMutableArray *barButtonItems = [[NSMutableArray alloc] initWithArray:navController.topViewController.navigationItem.leftBarButtonItems];
        [barButtonItems addObjectsFromArray:navController.topViewController.navigationItem.rightBarButtonItems];
        
        for (UIBarButtonItem *barButtonItem in barButtonItems) {
            if (barButtonItem.action == NSSelectorFromString(@"_showAppMenu:")) {
                [barButtonItems removeObject:barButtonItem];
                break;
            }
        }
        
        popoverPresentationController.managedBarButtonItems = [[NSSet alloc] initWithArray:barButtonItems];
    }
    
    [super presentViewController:viewControllerToPresent animated:flag completion:completion];
}

- (void)_setUpNavigationControllerForTraitCollection:(UITraitCollection *)traitCollection unconditionally:(BOOL)unconditional;
{
    BOOL traitCollectionIsCompact = traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact || traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
    
    if (!unconditional && (traitCollectionIsCompact == _isSetUpForCompact))
        return;
 
    UINavigationController *rootNavController = self.topLevelNavigationController;
    OUIDocumentPickerHomeScreenViewController *home = self.homeScreenViewController;
    OUIDocumentPickerAdaptableContainerViewController *foregroundContainer = self.homeScreenContainer;
    
    if (traitCollectionIsCompact) {
        // In a compact environment, we want all view controllers to exist in the outer navigation controller, and to promote the homeScreenViewController out of its homeScreenContainer.
        
        NSMutableArray *viewControllersToPromote = [[foregroundContainer popViewControllersForTransitionToCompactSizeClass] mutableCopy];
        OBASSERT_IF(viewControllersToPromote.count > 1, [rootNavController.viewControllers count] <= 1, "Somehow we are navigated into both a storage location and something in the home screen. Should only be navigated into one controller at a time!");
        
        if (viewControllersToPromote.count == 0){
            [viewControllersToPromote addObject:home];
        }
        else{
            OBASSERT(viewControllersToPromote[0] == home, @"Expected home screen controller at root of foreground container's nav stack");
            OBASSERT([rootNavController.viewControllers containsObject:foregroundContainer], @"Expected foreground container to be in root navigation controller's stack.");
        }
        

        NSMutableArray *viewControllersToPresent = [viewControllersToPromote mutableCopy];
        if (rootNavController.viewControllers.count > 1) {
            [viewControllersToPresent addObjectsFromArray:[rootNavController.viewControllers subarrayWithRange:NSMakeRange(1, rootNavController.viewControllers.count - 1)]];
        }
        [rootNavController setViewControllers:viewControllersToPresent];
    } else {
        // In the regular-regular environment, we want an outer navigation controller that contains only the homeScreenContainer and any storage-location navigation. The homeScreenContainer's navigation controller should contain any view controllers for editing details of storage locations.
        
        NSMutableArray *navStackToPresentDirectlyFromRootNavController = [NSMutableArray arrayWithArray:rootNavController.viewControllers];
        NSUInteger rootPresentedCount = navStackToPresentDirectlyFromRootNavController.count;
        NSMutableArray *navStackToPresentFromForegroundContainer = [NSMutableArray arrayWithObject:home];

        if (rootPresentedCount == 0)
            [navStackToPresentDirectlyFromRootNavController addObject:foregroundContainer];
        else
            navStackToPresentDirectlyFromRootNavController[0] = foregroundContainer;
            
        if (rootPresentedCount > 1) {
            if ([navStackToPresentDirectlyFromRootNavController[1] isKindOfClass:[OUIDocumentPickerViewController class]]) {
                // We're navigated into a storage location; all view controllers stay in the outer navigation controller.
            } else {
                NSRange rangeToMove = NSMakeRange(1, rootPresentedCount - 1);
                [navStackToPresentFromForegroundContainer addObjectsFromArray:[navStackToPresentDirectlyFromRootNavController subarrayWithRange:rangeToMove]];
                [navStackToPresentDirectlyFromRootNavController removeObjectsInRange:rangeToMove];
            }
        }
        
        [rootNavController setViewControllers:navStackToPresentDirectlyFromRootNavController];
        [foregroundContainer pushViewControllersForTransitionToRegularSizeClass:navStackToPresentFromForegroundContainer];
        // fix the autoresizingMask for some reason it was set to UIViewAutoresizingFlexibleRightMargin	| UIViewAutoresizingFlexibleBottomMargin.
        if (foregroundContainer.view.autoresizingMask != UIViewAutoresizingNone) {
            foregroundContainer.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        }
    }

    _isSetUpForCompact = traitCollectionIsCompact;
    [self _updateNavigationBar:rootNavController.navigationBar forViewController:rootNavController.topViewController];
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
    
    if ([_delegate respondsToSelector:@selector(documentPicker:viewWillAppear:)])
        [_delegate documentPicker:self viewWillAppear:animated];

    [super viewWillAppear:animated];
}

- (UIStatusBarStyle)preferredStatusBarStyle;
{
    if ([(((UINavigationController *)self.wrappedViewController).navigationBar.tintColor) isEqual:[UIColor whiteColor]])
        return UIStatusBarStyleLightContent;
    else
        return UIStatusBarStyleDefault;
}

#pragma mark - UINavigationControllerDelegate

- (void)_updateNavigationBar:(UINavigationBar *)navBar forViewController:(UIViewController *)viewController;
{
    UIImage *backgroundImage;
    UIColor *barTintColor;
    NSDictionary *barTitleAttributes;
    BOOL wantsVisibleNavigationBarAtRoot = NO;
    
    if ([self.delegate respondsToSelector:@selector(documentPickerWantsVisibleNavigationBarAtRoot:)]) {
        wantsVisibleNavigationBarAtRoot = [self.delegate documentPickerWantsVisibleNavigationBarAtRoot:self];
    }
    
    if (!wantsVisibleNavigationBarAtRoot && (!_isSetUpForCompact && (viewController == _homeScreenContainer || viewController == _homeScreenViewController))) {
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

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    UINavigationBar *navBar = navigationController.navigationBar;
    [self _updateNavigationBar:navBar forViewController:viewController];
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
