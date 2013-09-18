// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniBase/OmniBase.h>

#import "OUIDocumentPicker-Internal.h"
#import <OmniUIDocument/OUIDocumentPickerHomeScreenViewController.h>
#import <OmniUIDocument/OUIDocumentPickerHomeScreenCell.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import "OUIDocumentPickerViewController-Internal.h"
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import "OUIDocumentSubfolderAnimator.h"
#import "OUIDocumentTemplateAnimator.h"
#import "OUIDocumentHomeScreenAnimator.h"
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

@interface OUIDocumentPicker () <UINavigationControllerDelegate>
@end

@implementation OUIDocumentPicker

- (instancetype)initWithDocumentStore:(ODSStore *)documentStore;
{
    if (!(self = [super init]))
        return nil;
    
    _documentStore = documentStore;
    
    return self;
}

@synthesize navigationController=_navigationController;

- (UINavigationController *)navigationController;
{
    if (!_navigationController) {
        UIViewController *home;
        
        if ([_delegate respondsToSelector:@selector(documentPickerHomeViewController:)])
            home = [_delegate documentPickerHomeViewController:self];
        else
            home = [[OUIDocumentPickerHomeScreenViewController alloc] initWithDocumentPicker:self];
        _navigationController = [[UINavigationController alloc] initWithRootViewController:home];
        _navigationController.delegate = self;
    }
    return _navigationController;
}

- (void)showDocuments;
{
    ODSScope *selectScope = nil;
    NSString *identifier = [[OUIDocumentPickerViewController scopePreference] stringValue];
    NSString *folderPath = [[OUIDocumentPickerViewController folderPreference] stringValue];

    [(OUIDocumentPickerHomeScreenViewController *)self.navigationController.viewControllers[0] finishedLoading];
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

- (void)_endEditingMode;
{
    OUIDocumentPickerViewController *topVC = (OUIDocumentPickerViewController *)self.navigationController.topViewController;
    if ([topVC isKindOfClass:[OUIDocumentPickerViewController class]])
        topVC.editing = NO;
}

- (void)navigateToFolder:(ODSFolderItem *)folderItem animated:(BOOL)animated;
{
    OBPRECONDITION(folderItem.scope != nil);
    
    [self _endEditingMode];
    
    NSMutableArray *newViewControllers = [[NSMutableArray alloc] init];
    
    NSArray *existingViewControllers = self.navigationController.viewControllers;
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
    [self.navigationController setViewControllers:newViewControllers animated:animated];
}

- (void)navigateToContainerForItem:(ODSItem *)item animated:(BOOL)animated;
{
    ODSScope *scope = item.scope;
    if (!scope || ![_documentStore.scopes containsObject:scope]) {
        [self.navigationController popToRootViewControllerAnimated:animated];
        return;
    } else if (self.navigationController.viewControllers.count > 1 && ![self.navigationController.viewControllers.lastObject isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]] && [[(OUIDocumentPickerViewController *)self.navigationController.viewControllers.lastObject filteredItems] containsObject:item]) {
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
    [self.navigationController popToRootViewControllerAnimated:NO];
    [self.navigationController pushViewController:picker animated:animated];
}


- (ODSScope *)localDocumentsScope;
{
    NSArray *sorted = [_documentStore.scopes sortedArrayUsingSelector:@selector(compareDocumentScope:)];
    return [sorted objectAtIndex:0];
}

- (id <UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                   animationControllerForOperation:(UINavigationControllerOperation)operation
                                                fromViewController:(UIViewController *)fromVC
                                                  toViewController:(UIViewController *)toVC;
{
    if ([fromVC isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]] || [toVC isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]]) {
        return [OUIDocumentTemplateAnimator sharedAnimator];
    } else if ([fromVC isKindOfClass:[OUIDocumentPickerHomeScreenViewController class]] && [toVC isKindOfClass:[OUIDocumentPickerViewController class]]) {
        return [OUIDocumentHomeScreenAnimator sharedAnimator];
    } else if ([toVC isKindOfClass:[OUIDocumentPickerHomeScreenViewController class]] && [fromVC isKindOfClass:[OUIDocumentPickerViewController class]]) {
        ODSScope *scope = [(OUIDocumentPickerViewController *)fromVC selectedScope];
        OUIDocumentPickerHomeScreenViewController *home = (OUIDocumentPickerHomeScreenViewController *)toVC;
        
        [home selectCellForScope:scope];
        return [OUIDocumentHomeScreenAnimator sharedAnimator];
    } else if ([toVC isKindOfClass:[OUIDocumentPickerViewController class]] && [fromVC isKindOfClass:[OUIDocumentPickerViewController class]]) {
        return [OUIDocumentSubfolderAnimator sharedAnimator];
    }
    return nil;
}

- (OUIDocumentPickerViewController *)selectedScopeViewController;
{
    if (_navigationController.viewControllers.count < 2)
        return nil;
    else {
        UIViewController *viewController = _navigationController.topViewController;
        OBASSERT([viewController isKindOfClass:[OUIDocumentPickerViewController class]]);
        return (OUIDocumentPickerViewController *)viewController;
    }
}

#pragma mark - Internal

- (void)navigateForDeletionOfFolder:(ODSFolderItem *)deletedItem animated:(BOOL)animated;
{
    ODSFolderItem *parentFolder = nil;
    
    for (UIViewController *vc in self.navigationController.viewControllers) {
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

@end
