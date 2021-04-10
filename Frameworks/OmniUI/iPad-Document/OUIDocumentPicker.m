// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
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
#import <OmniUI/OUIInspectorAppearance.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>
#import <OmniUI/UIPopoverPresentationController-OUIExtensions.h>

#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentSubfolderAnimator.h"
#import "OUIDocumentTemplateAnimator.h"

RCS_ID("$Id$")

@interface OUIDocumentPicker () <UINavigationControllerDelegate>
@property (nonatomic, readonly) UINavigationController *topLevelNavigationController;
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

- (void)showDocuments;
{
    OBFinishPorting;
}

- (void)_endEditingMode;
{
    OUIDocumentPickerViewController *topVC = (OUIDocumentPickerViewController *)self.topLevelNavigationController.topViewController;
    if ([topVC isKindOfClass:[OUIDocumentPickerViewController class]])
        topVC.editing = NO;
}

- (void)navigateToFolder:(ODSFolderItem *)folderItem animated:(BOOL)animated;
{
    OBFinishPorting;
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
    if (!scope || ![_documentStore.scopes containsObject:scope]) {
        // The item is unfindable
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
    OBFinishPorting;
}

- (void)editSettingsForAccount:(OFXServerAccount *)account;
{
    OBFinishPorting;
}

- (ODSScope *)localDocumentsScope;
{
    NSArray *sorted = [_documentStore.scopes sortedArrayUsingSelector:@selector(compareDocumentScope:)];
    return [sorted objectAtIndex:0];
}

- (ODSFolderItem *)currentFolder;
{
    return self.selectedScopeViewController.folderItem;
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
    OBFinishPorting;
#if 0
    for (UIBarButtonItem *item in self.homeScreenContainer.navigationItem.rightBarButtonItems) {
        if ([item.target isKindOfClass:[OUIAppController class]]) {
            item.enabled = enable;
        }
    }
#endif
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
        
        [popoverPresentationController setManagedBarButtonItemsFromArray:barButtonItems];
    }
    
    [super presentViewController:viewControllerToPresent animated:flag completion:completion];
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
    OBFinishPorting;
#if 0
    UIImage *backgroundImage;
    UIColor *barTintColor;
    NSDictionary *barTitleAttributes;
    BOOL wantsVisibleNavigationBarAtRoot = NO;
    
    id<OUIDocumentPickerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(documentPickerWantsVisibleNavigationBarAtRoot:)]) {
        wantsVisibleNavigationBarAtRoot = [delegate documentPickerWantsVisibleNavigationBarAtRoot:self];
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
#endif
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
    OBFinishPorting;
#if 0
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
#endif
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

- (NSArray *)availableFiltersForScope:(ODSScope *)scope;
{
    id<OUIDocumentPickerDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(documentPickerAvailableFilters:)])
        return [delegate documentPickerAvailableFilters:self];
    
    else
        return @[];
}

@end
