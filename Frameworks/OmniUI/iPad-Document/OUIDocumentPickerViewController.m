// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@import OmniBase;
@import OmniDAV;
@import OmniDocumentStore;
@import OmniFileExchange;
@import OmniFoundation;
@import OmniQuartz;
@import OmniUI;
@import OmniAppKit;
@import OmniUnzip;

#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentPickerGroupItemView.h>
#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentTitleView.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIErrors.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>
#import <OmniUIDocument/OUIDocumentPreviewingViewController.h>
#import <OmniUIDocument/OUIReplaceRenameDocumentAlertController.h>
#import "OUIDocumentOpenAnimator.h"
#import "OUIDocumentParameters.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentRenameSession.h"
#import "OUIDocumentAppController-Internal.h"
#import "OUIImportExportAccountListViewController.h"

RCS_ID("$Id$");


#if 0 && defined(DEBUG)
    #define PICKER_DEBUG(format, ...) NSLog(@"PICKER: " format, ## __VA_ARGS__)
#else
    #define PICKER_DEBUG(format, ...)
#endif

OBDEPRECATED_METHOD(-documentPicker:toolbarPromptForRenamingFileItem:);

#define GENERATE_DEFAULT_PNG 0

static NSString * const kActionSheetPickMoveDestinationScopeIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.PickMoveDestinationScope";
static NSString * const kActionSheetDeleteIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.DeleteAction";

static NSString * const FilteredItemsBinding = @"filteredItems";

@interface OUIDocumentPickerViewController () <OUIDocumentTitleViewDelegate, UIViewControllerPreviewingDelegate>

@property(nonatomic,readonly) ODSFileItem *singleSelectedFileItem;

@property(nonatomic,copy) NSSet *filteredItems;

@property(nonatomic,strong) UISegmentedControl *filtersSegmentedControl;
@property(nonatomic,strong) UISegmentedControl *sortSegmentedControl;
@property(nonatomic,strong) OUIDocumentRenameSession *renameSession;

@property(nonatomic,readonly) BOOL canPerformActions;
@property(nonatomic) BOOL wasShowingTopControlsBeforeTransition;
@property(nonatomic) BOOL isTransitioningTraitCollection;

@property (nonatomic, strong) UIBarButtonItem *emptyTrashBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *openExternalFileBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *appMenuBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *deleteBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *addDocumentButtonItem;

@property (nonatomic, weak) OUIMenuController *restoreToMenuController;

@property (nonatomic, strong) id <UIViewControllerPreviewing>previewingContext;

@property(nonatomic,readonly) UIActivityIndicatorView *activityIndicator;

@end

@implementation OUIDocumentPickerViewController
{
    UILabel *_titleLabelToUseInCompactWidth;
    UIToolbar *_toolbar;
    
    OFXAccountActivity *_accountActivity;
    OUIDocumentTitleView *_normalTitleView;
    
    UIBarButtonItem *_duplicateDocumentBarButtonItem;
    UIBarButtonItem *_exportBarButtonItem;
    UIBarButtonItem *_moveBarButtonItem;
    UIBarButtonItem *_appTitleToolbarItem;
    UIButton *_appTitleToolbarButton;

    ODSStore *_documentStore;
    ODSScope *_documentScope;
    ODSFolderItem *_folderItem;
    
    NSMutableArray *_afterDocumentStoreInitializationActions;
    
    NSUInteger _ignoreDocumentsDirectoryUpdates;
    
    OFSetBinding *_filteredItemsBinding;
    NSSet *_filteredItems;
    NSMutableSet *_explicitlyRemovedItems;
    
    UIView *_topControls;
    BOOL _isObservingKeyboardNotifier;
    BOOL _isObservingApplicationDidEnterBackground;
    
    BOOL _isAppearing;
    BOOL _needsDelayedHandleResize;
    BOOL _freezeTopControlAlpha;
    
    OUIEmptyOverlayView *_emptyOverlayView;
    NSArray *_emptyOverlayViewConstraints;

    OUIDocumentExporter *_exporter;
}

- (instancetype)_initWithDocumentPicker:(OUIDocumentPicker *)picker scope:(ODSScope *)scope folderItem:(ODSFolderItem *)folderItem;
{
    OBPRECONDITION(picker);
    OBPRECONDITION(scope);
    OBPRECONDITION(folderItem);

#if defined(DEBUG_lizard)
    if ([scope isExternal]) {
        OBStopInDebugger("<bug:///147708> (Frameworks-iOS Bug: Remove Other Documents)");
    }
#endif
    
    // Need to provide nib name explicitly, since template picker is a subclass but should use the same nib
    if (!(self = [super initWithNibName:@"OUIDocumentPickerViewController" bundle:OMNI_BUNDLE]))
        return nil;
    
    if (!picker)
        OBRejectInvalidCall(self, _cmd, @"picker must not be nil");
    if (!scope)
        OBRejectInvalidCall(self, _cmd, @"scope must not be nil");
    if (!folderItem)
        OBRejectInvalidCall(self, _cmd, @"folderItem must not be nil");
    
    _documentPicker = picker;
    
    /// --- setDocumentStore:
    
    OBASSERT(scope.documentStore == picker.documentStore);
    _documentStore = picker.documentStore;
    _documentScope = scope;
    
    OBASSERT(folderItem.scope == scope);
    _folderItem = folderItem;
    
    if ([_documentScope isKindOfClass:[OFXDocumentStoreScope class]]) {
        _accountActivity = [[OUIDocumentAppController controller].agentActivity activityForAccount:((OFXDocumentStoreScope *)_documentScope).account];
    }
    
    _documentStoreFilter = [self newDocumentStoreFilter];

    _exporter = [OUIDocumentExporter exporterForViewController:self];

    if ([picker.delegate respondsToSelector:@selector(defaultDocumentStoreFilterFilterPredicate:)])
        _documentStoreFilter.filterPredicate = [picker.delegate defaultDocumentStoreFilterFilterPredicate:picker];
    
    [self _flushAfterDocumentStoreInitializationActions];

    /// --- setSelectedScope:
    
    OFPreference *scopePreference = [[self class] scopePreference];
    [scopePreference setStringValue:scope.identifier];
    
    [self scrollToTopAnimated:NO];

    // The delegate likely wants to update the title displayed in the document picker toolbar.
    [self updateTitle];
        
    // --- _setupFilteredItemsBinding:
    
    // We might want to bind _documentStore.fileItems to us and then mirror that property to the scroll view, or force feed it. This would allow us to stage animations or whatnot.
    // ODSStore is going to send us unsolicited updates (incoming document sync while we are just sitting idle in the picker), so we need to be able to handle these
    
#if !GENERATE_DEFAULT_PNG
    _filteredItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingKeyPath(_documentStoreFilter, filteredItems)
                                                     destinationPoint:OFBindingPointMake(self, FilteredItemsBinding)];
    [_filteredItemsBinding propagateCurrentValue];
#endif
    
    return self;
}

- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)picker scope:(ODSScope *)scope;
{
    return [self _initWithDocumentPicker:picker scope:scope folderItem:scope.rootFolder];
}

- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)picker folderItem:(ODSFolderItem *)folderItem;
{
    return [self _initWithDocumentPicker:picker scope:folderItem.scope folderItem:folderItem];
}

- (ODSFolderItem *)folderItem;
{
    return _folderItem;
}

- (ODSFilter *)newDocumentStoreFilter;
{
    return [[ODSFilter alloc] initWithFolderItem:_folderItem];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    OBRejectInvalidCall(self, _cmd, @"Use -initWithDocumentPicker:scope:");
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    OBRejectInvalidCall(self, _cmd, @"Use -initWithDocumentPicker:scope:");
}

- (void)dealloc;
{
    _mainScrollView.delegate = nil;

    [OFPreference removeObserver:self forPreference:[[self class] filterPreference]];
    [OFPreference removeObserver:self forPreference:[[self class] sortPreference]];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
    [center removeObserver:self name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
    [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];

    [_filteredItemsBinding invalidate];
}

#pragma mark -
#pragma mark KVC

- (UIImageView *)backgroundView;
{
    (void)[self view];
    return _backgroundView;
}

@synthesize documentStore = _documentStore;

- (ODSScope *)selectedScope;
{
    return _documentScope;
}

- (BOOL)canAddDocuments;
{
    return _documentScope.isTrash == NO;
}

- (ODSScope *)_localDocumentsScope;
{
    for (ODSScope *scope in _documentStore.scopes) {
        if (![scope isKindOfClass:[OFXDocumentStoreScope class]])
            return scope;
    }

    return nil;
}

- (void)emptyTrashItemTapped:(id)sender;
{
    if (!self.isEditing)
        [self setEditing:YES animated:YES];

    OUIWithoutAnimating(^{
        [self clearSelection:NO];


        for (ODSItem *item in _documentStore.trashScope.topLevelItems)
            item.selected = YES;

        [self _updateToolbarItemsEnabledness];
        [self.view layoutIfNeeded];
    });

    [self deleteDocument:sender];
}

- (void)setRenameSession:(OUIDocumentRenameSession *)renameSession;
{
    _renameSession = renameSession;
    _mainScrollView.renameSession = renameSession;
}

#pragma mark -
#pragma mark API

- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL;
{
    [self rescanDocumentsScrollingToURL:targetURL animated:(_mainScrollView.window != nil) completionHandler:nil];
}

- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler;
{
    completionHandler = [completionHandler copy];
        
    // This depends on the caller to have *also* poked the file items into reloading any metadata that will be used to sort or filter them. That is, we don't reload all that info right now.
    [_documentStore scanItemsWithCompletionHandler:^{
        // We need our view if we are to do the scrolling <bug://bugs/60388> (OGS isn't restoring the the last selected document on launch)
        (void)[self view];
        
        // <bug://bugs/60005> (Document picker scrolls to empty spot after editing file)
        [_mainScrollView.window layoutIfNeeded];
        
        //OBFinishPortingLater("<bug:///147830> (iOS-OmniOutliner Bug: OUIDocumentPickerViewController.m:317 - Show/open the group scroll view if the item is in a group?)");
        ODSFileItem *fileItem = [_documentStore fileItemWithURL:targetURL];
        if (!fileItem) {
            OBFinishPortingLater("<bug:///147829> (iOS-OmniOutliner Bug: OUIDocumentPickerViewController.m:320 - Scroll to the top when there’s no fileItem)");
            //[_mainScrollView scrollsToTop]; // this is a getter
        } else
            [_mainScrollView scrollItemToVisible:fileItem animated:animated];
        
        // TODO: Needed?
        [_mainScrollView setNeedsLayout];
        
        if (completionHandler)
            completionHandler();
    }];
}

- (void)rescanDocuments;
{
    [self rescanDocumentsScrollingToURL:nil];
}

- (NSSet *)selectedItems;
{
    NSSet *candidates = _folderItem.childItems;
    return [candidates select:^(ODSItem *item){
        return item.selected;
    }];
}

- (NSSet *)selectedFolders;
{
    NSSet *candidates = _folderItem.childItems;
    return [candidates select:^BOOL(ODSItem *item){
        return item.type == ODSItemTypeFolder && item.selected;
    }];
}

- (NSUInteger)selectedItemCount;
{
    NSUInteger selectedCount = 0;
    
    NSSet *candidates = _folderItem.childItems;

    for (ODSItem *item in candidates)
        if (item.selected)
            selectedCount++;
    
    return selectedCount;
}

- (BOOL)hasSelectedFolder;
{
    NSSet *candidates = _folderItem.childItems;
    return [candidates any:^BOOL(ODSItem *item){
        return item.selected && [item isKindOfClass:[ODSFolderItem class]];
    }] != nil;
}

- (void)scrollTopControlsToVisibleWithCompletion:(void (^_Nullable)(BOOL))completion
{
    [UIView animateWithDuration:0.25
                     animations:^{
                         [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
                         [self.mainScrollView setContentOffset:CGPointMake(self.mainScrollView.contentOffset.x, [self.mainScrollView contentOffsetYToShowTopControls])];
                     } completion:completion];
}

- (void)clearSelectionAndEndEditing
{
    [self clearSelection:YES];
}

- (void)clearSelection:(BOOL)shouldEndEditing;
{
    // Clear the selection in the whole scope, just in case something out of view is still selected.
    OUIWithoutAnimating(^{
        [_documentScope.rootFolder eachItem:^(ODSItem *item){
            item.selected = NO;
        }];
        [self.view layoutIfNeeded];
    });
    
    if (shouldEndEditing) {
        [self setEditing:NO animated:YES];
        return;
    }
    
    [self _updateToolbarItemsEnabledness];
}

- (ODSFileItem *)singleSelectedFileItem;
{
    NSSet *selectedItems = self.selectedItems;
    
    // Ensure we have one and only one selected file item.
    if ([selectedItems count] != 1){
        OBASSERT_NOT_REACHED("We should only have one item in selectedItems at this point.");
        return nil;
    }
    
    ODSItem *item = [selectedItems anyObject];
    if ([item isKindOfClass:[ODSFileItem class]])
        return (ODSFileItem *)item;
    return nil;
}

- (void)scrollToTopAnimated:(BOOL)animated;
{
    OUIDocumentPickerScrollView *scrollView = self.mainScrollView;
    CGPoint topOffset = CGPointMake(-scrollView.contentInset.left, [scrollView contentOffsetYToHideTopControls]);
    [scrollView setContentOffset:topOffset animated:animated];
}

- (void)scrollItemToVisible:(ODSItem *)item animated:(BOOL)animated;
{
    [self.mainScrollView scrollItemToVisible:item animated:animated];
}

- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated completion:(void (^)(void))completion;
{
    [self.mainScrollView scrollItemsToVisible:items animated:animated completion:completion];
}

- (IBAction)newDocument:(id)sender;
{
    OBPRECONDITION(_renameSession == nil); // Can't be renaming right now, so need to try to stop

    if (![self canPerformAction:_cmd withSender:sender])
        return;

    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    ODSDocumentType type = [self _documentTypeForCurrentFilter];

    if ([delegate respondsToSelector:@selector(documentPickerTemplateDocumentFilter:)]) {
        OBASSERT([delegate documentPickerTemplateDocumentFilter:_documentPicker], @"Need to provide an actual filter for templates if you expect to use the template picker for new documents");

        OUIDocumentCreationTemplatePickerViewController *templateChooser = [[OUIDocumentCreationTemplatePickerViewController alloc] initWithDocumentPicker:_documentPicker folderItem:_folderItem documentType:type];
        templateChooser.isReadOnly = YES;
        [self.navigationController pushViewController:templateChooser animated:YES];
    } else {
        [self newDocumentWithTemplateFileItem:nil documentType:type completion:nil];
    }
}

- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem documentType:(ODSDocumentType)type completion:(void (^)(void))completion;
{
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

    OUIActivityIndicator *activityIndicator = nil;

    if (templateFileItem) {
        OUIDocumentPickerFileItemView *fileItemView = [_documentPicker.selectedScopeViewController.mainScrollView fileItemViewForFileItem:templateFileItem];
        UIView *view = _documentPicker.navigationController.topViewController.view;
        if (fileItemView)
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:fileItemView withColor:UIColor.whiteColor bezelColor:[UIColor.darkGrayColor colorWithAlphaComponent:0.9]];
        else
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:view withColor:UIColor.whiteColor];
    }

    // Instead of duplicating the template file item's URL (if we have one), we always read it into a OUIDocument and save it out, letting the document know that this is for the purposes of instantiating a new document. The OUIDocument may do extra work in this case that wouldn't get done if we just cloned the file (and this lets the work be done atomically by saving the new file to a temporary location before moving to a visible location).
    NSURL *temporaryURL = [_documentStore temporaryURLForCreatingNewDocumentOfType:type];

    completion = [completion copy];
    void (^cleanup)(void) = ^{
        [activityIndicator hide];
        [lock unlock];
        if (completion != NULL)
            completion();
    };

    void (^finish)(ODSFileItem *, NSError *) = [^(ODSFileItem *createdFileItem, NSError *error) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (createdFileItem == nil) {
                OUI_PRESENT_ERROR_FROM(error, self);
                cleanup();
                return;
            }
            
            ODSFileItem *fileItemToRevealFrom;
            if (templateFileItem != nil && ![[templateFileItem scope] isExternal]) {
                fileItemToRevealFrom = templateFileItem;
            } else {
                fileItemToRevealFrom = createdFileItem;
            }
            
            // We want the file item to have a new date, but this is the wrong place to do it. Want to do it in the document picker before it creates the item.
            // [[NSFileManager defaultManager] touchItemAtURL:createdItem.fileURL error:NULL];
            
            [self _revealAndActivateNewDocumentFileItem:createdFileItem fileItemToRevealFrom:fileItemToRevealFrom completionHandler:^{
                cleanup();
            }];
        }];
    } copy];
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperationWithBlock:^{
        Class cls = [[OUIDocumentAppController controller] documentClassForURL:temporaryURL];
        
        // This reads the document immediately, which is why we dispatch to a background queue before calling it. We do file coordination on behalf of the document here since we don't get the benefit of UIDocument's efforts during our synchronous read.
        
        __block OUIDocument *document;
        __autoreleasing NSError *readError;

        if (templateFileItem != nil) {
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            NSURL *templateURL = templateFileItem.fileURL;
            [coordinator readItemAtURL:templateURL withChanges:YES error:&readError byAccessor:^BOOL(NSURL *newURL, NSError **outError) {
                NSURL *securedURL = nil;
                if ([newURL startAccessingSecurityScopedResource])
                    securedURL = newURL;
                document = [[cls alloc] initWithContentsOfTemplateAtURL:newURL toBeSavedToURL:temporaryURL error:outError];
                [securedURL stopAccessingSecurityScopedResource];
                return (document != nil);
            }];
        } else {
            document = [[cls alloc] initWithContentsOfTemplateAtURL:nil toBeSavedToURL:temporaryURL error:&readError];
        }
        
        if (!document) {
            finish(nil, readError);
            return;
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // Save the document to our temporary location
            [document saveToURL:temporaryURL forSaveOperation:UIDocumentSaveForOverwriting completionHandler:^(BOOL saveSuccess){
                // The save completion handler isn't called on the main thread; jump over *there* to start the close (subclasses want that).
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [document closeWithCompletionHandler:^(BOOL closeSuccess){
                        [document didClose];
                        
                        if (!saveSuccess) {
                            // The document instance should have gotten the real error presented some other way
                            NSError *cancelledError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                            finish(nil, cancelledError);
                            return;
                        }

                        [_documentStore moveNewTemporaryDocumentAtURL:temporaryURL toScope:_documentScope folder:_folderItem documentType:type completionHandler:^(ODSFileItem *createdFileItem, NSError *error){
                            finish(createdFileItem, error);
                        }];
                    }];
                }];
            }];
        }];
    }];
}

- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem;
{
    [self newDocumentWithTemplateFileItem:templateFileItem documentType:ODSDocumentTypeNormal completion:NULL];
}

- (void)_duplicateItemsWithoutConfirmation:(NSSet *)selectedItems;
{
    OBASSERT([NSThread isMainThread]);

    NSMutableArray *errors = [NSMutableArray array];
    
    // We'll update once at the end
    [self _beginIgnoringDocumentsDirectoryUpdates];
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    [_documentScope copyItems:selectedItems toFolder:_folderItem  status:^(ODSFileItemMotion *originalFileItemMotion, NSURL *destionationFileURL, ODSFileItemEdit *duplicateFileItemEditOrNil, NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        OBASSERT(originalFileItemMotion); // destination is nil if there is an error
        OBASSERT(destionationFileURL);
        OBASSERT((duplicateFileItemEditOrNil == nil) ^ (errorOrNil == nil));
        
        if (!duplicateFileItemEditOrNil) {
            OBASSERT(errorOrNil);
            if (errorOrNil) // let's not crash, though...
                [errors addObject:errorOrNil];
            return;
        }
        
        if ([_documentPicker.delegate respondsToSelector:@selector(documentPicker:didDuplicateFileItem:toFileItem:)])
            [_documentPicker.delegate documentPicker:_documentPicker didDuplicateFileItem:originalFileItemMotion.fileItem toFileItem:duplicateFileItemEditOrNil.fileItem];
        
        // Copy document view state
        [OUIDocumentAppController copyDocumentStateFromFileEdit:originalFileItemMotion.originalItemEdit.originalFileEdit toFileEdit:duplicateFileItemEditOrNil.originalFileEdit];
    } completionHandler:^(NSSet *finalItems) {
        OBASSERT([NSThread isMainThread]);

        [self _endIgnoringDocumentsDirectoryUpdates];
        
        // We should have heard about the new items; if we haven't, we can't propagate them to our scroll view correctly
#ifdef OMNI_ASSERTIONS_ON
        {
            for (ODSItem *item in finalItems)
                OBASSERT([_filteredItems member:item] == item);
        }
#endif
        [self clearSelection:YES];
        [self _performDelayedItemPropagationWithCompletionHandler:^{
#ifdef OMNI_ASSERTIONS_ON
            // Make sure the duplicate items made it into the scroll view.
            for (ODSItem *item in finalItems)
                OBASSERT([self.mainScrollView.items member:item] == item);
#endif
            
            [self scrollItemsToVisible:finalItems animated:YES completion:^{
                [lock unlock];
            }];
        }];
        
        // This may be annoying if there were several errors, but it is misleading to not do it...
        for (NSError *error in errors)
            OUI_PRESENT_ALERT_FROM(error, self);
    }];
}

- (IBAction)duplicateDocument:(id)sender;
{
    // Validate each file item down the selected files and groups
    for (ODSFileItem *fileItem in self.selectedItems) {
        
        // Make sure the item is fully downloaded.
        if (!fileItem.isDownloaded) {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Cannot Duplicate Item", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error title") message:NSLocalizedStringFromTableInBundle(@"This item cannot be duplicated because it is not fully downloaded. Please tap the item and wait for it to download before trying again.", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error message") preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUIDocument", OMNI_BUNDLE, @"button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}];
            [alertController addAction:okAction];

            [self presentViewController:alertController animated:YES completion:^{}];

            return;
        }
    }

    NSSet *selectedItems = self.selectedItems;
    NSUInteger selectedItemCount = [selectedItems count];
    switch (selectedItemCount) {
        case 0:
            OBASSERT_NOT_REACHED("Make this button be disabled");
            return;
        case 1:
            [self _duplicateItemsWithoutConfirmation:selectedItems];
            break;
        default: {
            id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
            NSString *format = nil;
            {
                BOOL hasFolder = [selectedItems any:^BOOL(ODSItem *item) {
                    return item.type == ODSItemTypeFolder;
                }] != nil;

                if (hasFolder) {
                    format = NSLocalizedStringFromTableInBundle(@"Duplicate %ld Items", @"OmniUIDocument", OMNI_BUNDLE, @"title for alert option confirming duplication of multiple items");
                } else {
                    if ([delegate respondsToSelector:@selector(documentPickerAlertTitleFormatForDuplicatingFileItems:)])
                        format = [delegate documentPickerAlertTitleFormatForDuplicatingFileItems:selectedItems];
                    if ([NSString isEmptyString:format])
                        format = NSLocalizedStringFromTableInBundle(@"Duplicate %ld Documents", @"OmniUIDocument", OMNI_BUNDLE, @"title for alert option confirming duplication of multiple files");
                }
                OBASSERT([format containsString:@"%ld"]);
            }

            UIAlertController *duplicateAlert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            duplicateAlert.modalPresentationStyle = UIModalPresentationPopover;
            UIColor *tintColor = self.navigationController.navigationBar.tintColor;
            duplicateAlert.view.tintColor = tintColor;
            
            UIAlertAction *duplicateAction = [UIAlertAction actionWithTitle:[NSString stringWithFormat:format, selectedItemCount]
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action) {
                                                                     [self _duplicateItemsWithoutConfirmation:selectedItems];
                                                                 }];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"title for alert option cancel") style:UIAlertActionStyleCancel handler:nil];
            
            [duplicateAlert addAction:duplicateAction];
            [duplicateAlert addAction:cancelAction];
            duplicateAlert.popoverPresentationController.barButtonItem = sender;
            [self presentViewController:duplicateAlert animated:YES completion:^{
                duplicateAlert.popoverPresentationController.passthroughViews = nil;
            }];
        }
    }
}

- (void)addDocumentToSelectedScopeFromURL:(NSURL *)fromURL withOption:(ODSStoreAddOption)option openNewDocumentWhenDone:(BOOL)openWhenDone completion:(void (^)(void))completion
{
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    __weak OUIDocumentPickerViewController *welf = self;
    [self.selectedScope addDocumentInFolder:_folderItem fromURL:fromURL option:option
                          completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
                              if (!duplicateFileItem) {
                                  if (error){
                                      OUI_PRESENT_ERROR_FROM(error, welf);
                                  }
                                  [lock unlock];
                                  if (completion) {
                                      completion();
                                  }
                                  return;
                              }
                              
                              if (openWhenDone) {
                                  [self _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                                      [lock unlock];
                                      if (completion) {
                                          completion();
                                      }
                                  }];
                              } else {
                                  [self _revealButDontActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                                      [lock unlock];
                                      if (completion) {
                                          completion();
                                      }
                                  }];
                              }
                          }];
}

- (void)addDocumentFromURL:(NSURL *)url completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_folderItem);
    
    if (completionHandler == NULL)
        completionHandler = ^{};

    ODSItem *existingItem = [_folderItem childItemWithFilename:[url lastPathComponent]];
    if (existingItem) {
        OUIReplaceRenameDocumentAlertController *replaceDocumentAlert = [OUIReplaceRenameDocumentAlertController replaceRenameAlertForURL:url withCancelHandler:nil replaceHandler:^{
            [self addDocumentToSelectedScopeFromURL:url withOption:ODSStoreAddByCopyingSourceToReplaceDestinationURL openNewDocumentWhenDone:YES completion:nil];
        } renameHandler:^{
            [self addDocumentToSelectedScopeFromURL:url withOption:ODSStoreAddByCopyingSourceToAvailableDestinationURL openNewDocumentWhenDone:YES completion:nil];
        }];

        [self presentViewController:replaceDocumentAlert animated:YES completion:^{}];
        completionHandler();
        return;
    }
    
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    __weak id weakSelf = self;
    [_documentScope addDocumentInFolder:_folderItem fromURL:url option:ODSStoreAddByCopyingSourceToDestinationURL completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
        OUIDocumentPickerViewController *strongSelf = weakSelf;
        if (!strongSelf) {
            completionHandler();
            return;
        }
        
        if (!duplicateFileItem) {
            OUI_PRESENT_ERROR_FROM(error, weakSelf);
            [lock unlock];
            completionHandler();
            return;
        }

        [strongSelf _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
            [lock unlock];
            completionHandler();
        }];
    }];
}

- (void)addDocumentFromURL:(NSURL *)url;
{
    [self addDocumentFromURL:url completionHandler:NULL];
}

- (void)_revealButDontActivateNewDocumentFileItem:(ODSFileItem *)createdFileItem completionHandler:(void (^)(void))completionHandler;
{
    // do some scrolling
    [self ensureSelectedFilterMatchesFileItem:createdFileItem];
    [self scrollItemToVisible:createdFileItem animated:YES];
    // Force a new preview
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:createdFileItem forKey:ODSFileItemInfoKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:ODSFileItemContentsChangedNotification object:_documentStore userInfo:userInfo];
    if (completionHandler)
        completionHandler();
}

- (void)addSampleDocumentFromURL:(NSURL *)url;
{
    BOOL copyAndOpen = YES;
    if ([self.documentPicker.delegate respondsToSelector:@selector(documentPickerShouldOpenSampleDocuments)])
        copyAndOpen = [self.documentPicker.delegate documentPickerShouldOpenSampleDocuments];
    
    NSString *fileName = [url lastPathComponent];
    NSString *localizedBaseName = [[OUIDocumentAppController controller] localizedNameForSampleDocumentNamed:[fileName stringByDeletingPathExtension]];
    NSString *localizedFileName = [localizedBaseName stringByAppendingPathExtension:[fileName pathExtension]];
    
    if (!copyAndOpen) {
        ODSItem *existingItem = [_folderItem childItemWithFilename:localizedFileName];
        if (existingItem) {
            OUIReplaceRenameDocumentAlertController *replaceDocumentAlert = [OUIReplaceRenameDocumentAlertController replaceRenameAlertForURL:url withCancelHandler:nil replaceHandler:^{
                [self addDocumentToSelectedScopeFromURL:url withOption:ODSStoreAddByCopyingSourceToReplaceDestinationURL openNewDocumentWhenDone:NO completion:nil];
            } renameHandler:^{
                [self addDocumentToSelectedScopeFromURL:url withOption:ODSStoreAddByCopyingSourceToAvailableDestinationURL openNewDocumentWhenDone:NO completion:nil];
            }];
            
            [self presentViewController:replaceDocumentAlert animated:YES completion:^{}];
            return;
        }
    }

    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    ODSScope *targetScope = self.selectedScope;
    ODSFolderItem *targetFolder = _folderItem;
    if (!targetScope.canRenameDocuments) {
        targetScope = self.documentPicker.localDocumentsScope;
        targetFolder = targetScope.rootFolder;
    }

    [targetScope addDocumentInFolder:targetFolder baseName:localizedBaseName fromURL:url option:(copyAndOpen) ? ODSStoreAddByCopyingSourceToAvailableDestinationURL : ODSStoreAddByCopyingSourceToReplaceDestinationURL completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
        
        if (!duplicateFileItem) {
            [lock unlock];
            OUI_PRESENT_ERROR_FROM(error, self);
            return;
        }

        OUIDocumentPicker *documentPicker = self.documentPicker;
        [documentPicker navigateToContainerForItem:duplicateFileItem dismissingAnyOpenDocument:YES animated:YES];
        if (copyAndOpen) {
            [documentPicker.selectedScopeViewController _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                [lock unlock];
            }];
        } else {
            [documentPicker.selectedScopeViewController _revealButDontActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                [lock unlock];
            }];
        }
    }];
}

- (void)exportedDocumentToURL:(NSURL *)url;
{
    [self rescanDocuments];
    [self clearSelection:YES];
}

- (NSArray *)availableFilters;
{
    return [_documentPicker availableFiltersForScope:_documentScope];
}


- (NSString *)_deleteDocumentTitle:(NSUInteger)count;
{
    OBPRECONDITION(count > 0);
    
    if (self.selectedScope.isTrash) {
        if (count == 1)
            return NSLocalizedStringFromTableInBundle(@"Delete Document", @"OmniUIDocument", OMNI_BUNDLE, @"delete button title");
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Delete %ld Documents", @"OmniUIDocument", OMNI_BUNDLE, @"delete button title"), count];
    } else if (self.selectedScope.isExternal) {
        if (count == 1)
            return NSLocalizedStringFromTableInBundle(@"Remove Document", @"OmniUIDocument", OMNI_BUNDLE, @"remove button title");
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Remove %ld Documents", @"OmniUIDocument", OMNI_BUNDLE, @"remove button title"), count];
    } else {
        if (count == 1)
            return NSLocalizedStringFromTableInBundle(@"Move to Trash", @"OmniUIDocument", OMNI_BUNDLE, @"move to trash button title");
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Move %ld Items to Trash", @"OmniUIDocument", OMNI_BUNDLE, @"move to trash button title"), count];
    }
}

- (void)_deleteItems:(NSSet <ODSItem *> *)items sender:(id)sender;
{
    if (!self.canPerformActions)
        return;
    
    NSUInteger itemCount = [items count];
    
    if (itemCount == 0) {
        OBASSERT_NOT_REACHED("Delete toolbar item shouldn't have been enabled");
        return;
    }
    
    UIAlertController *deleteAlert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:[self _deleteDocumentTitle:itemCount]
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction *action) {
                                                             [self _deleteWithoutConfirmation:items];
                                                         }];
    [deleteAlert addAction:deleteAction];
    [deleteAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"delete confirmation cancel button") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [deleteAlert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    deleteAlert.modalPresentationStyle = UIModalPresentationPopover;
    
    if ([sender isKindOfClass:[UIBarButtonItem class]]) {
    deleteAlert.popoverPresentationController.barButtonItem = sender;
    }
    else if ([sender isKindOfClass:[UIView class]]) {
        deleteAlert.popoverPresentationController.sourceView = [(UIView *)sender superview];
        deleteAlert.popoverPresentationController.sourceRect = [(UIView *)sender frame];
    }
    else {
        deleteAlert.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    
    [self presentViewController:deleteAlert animated:YES completion:^{
        deleteAlert.popoverPresentationController.passthroughViews = nil;
    }];
}

- (IBAction)deleteDocument:(id)sender;
{
    [self _deleteItems:self.selectedItems sender:sender];
}

- (void)_moveWithDidFinishHandler:(void (^)(void))didFinishHandler;
{
    if (!self.canPerformActions)
        return;
    
    ODSScope *currentScope = self.selectedScope;
    
    BOOL willAddNewFolder = currentScope.canCreateFolders;
    
    NSString *topLevelMenuTitle;
    NSMutableArray *topLevelMenuOptions = [NSMutableArray array];
    
    // "Move" options
    NSMutableArray *moveOptions = [[NSMutableArray alloc] init];
    NSString *moveMenuTitle = [self _menuTitleAfterAddingMoveOptions:moveOptions fromCurrentScope:currentScope];
    
    // Move submenu
    if (willAddNewFolder && [moveOptions count] > 0) {
        topLevelMenuTitle = NSLocalizedStringFromTableInBundle(@"Move", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view");
        UIImage *image = [UIImage imageNamed:@"OUIMenuItemMoveToScope" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        [topLevelMenuOptions addObject:[[OUIMenuOption alloc] initWithTitle:moveMenuTitle image:image options:moveOptions destructive:NO action:nil]];
    } else {
        topLevelMenuTitle = moveMenuTitle;
        [topLevelMenuOptions addObjectsFromArray:moveOptions];
    }
    
    // New folder
    OUIMenuOption *newFolderOption = nil;
    if (willAddNewFolder) {
        newFolderOption = [OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"New folder", @"OmniUIDocument", OMNI_BUNDLE, @"Action sheet title for making a new folder from the selected documents") image:[UIImage imageNamed:@"OUIMenuItemNewFolder" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self _makeFolderFromSelectedDocuments];
        }];
        [topLevelMenuOptions addObject:newFolderOption];
    }
    
    OUIMenuController *menu = [[OUIMenuController alloc] init];
    menu.topOptions = topLevelMenuOptions;
    if (topLevelMenuTitle)
        menu.title = topLevelMenuTitle;
    menu.tintColor = self.navigationController.navigationBar.tintColor;
    menu.popoverPresentationController.barButtonItem = _moveBarButtonItem;
    menu.didFinish = didFinishHandler;
    
    [self presentViewController:menu animated:YES completion:^{
        menu.popoverPresentationController.passthroughViews = nil;
    }];
}

- (IBAction)move:(id)sender;
{
    [self _moveWithDidFinishHandler:nil];
}

- (void)_addMoveToFolderOptions:(NSMutableArray *)options candidateParentFolder:(ODSFolderItem *)candidateParentFolder currentFolder:(ODSFolderItem *)currentFolder excludedTreeFolders:(NSSet *)excludedTreeFolders;
{
    if ([excludedTreeFolders member:candidateParentFolder])
        return; // Prune this whole tree

    NSUInteger startingOptionCount = [options count];
    
    for (ODSItem *item in candidateParentFolder.childItemsSortedByName) {
        if (item.type != ODSItemTypeFolder)
            continue;

        [self _addMoveToFolderOptions:options candidateParentFolder:(ODSFolderItem *)item currentFolder:currentFolder excludedTreeFolders:excludedTreeFolders];
    }

    // The top level caller handles the root folder
    if (candidateParentFolder == candidateParentFolder.scope.rootFolder)
        return;
    
    UIImage *folderImage = [UIImage imageNamed:@"OUIMenuItemFolder" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    
    OUIMenuOption *option;
    if (candidateParentFolder == currentFolder) {
        // This folder isn't a valid location, but if one of its children is, emit a placeholder to make the indentation look nice
        if (startingOptionCount != [options count]) {
            option = [[OUIMenuOption alloc] initWithTitle:candidateParentFolder.name image:folderImage action:nil];
        }
    } else {
        // This is a valid destination. Great!
        option = [[OUIMenuOption alloc] initWithTitle:candidateParentFolder.name image:folderImage action:^(OUIMenuOption *_option, UIViewController *presentingViewController){
            [self _moveSelectedDocumentsToFolder:candidateParentFolder];
        }];
    }
    
    if (option) {
        // If we came up with an option, insert it before where our children got added
        option.indentationLevel = candidateParentFolder.depth - 1;
        OBASSERT(candidateParentFolder.depth > 0, "The root is depth zero, and top level items are depth 1");
        [options insertObject:option atIndex:startingOptionCount];
    }
}

+ (OFPreference *)scopePreference;
{
    static OFPreference *scopePreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scopePreference = [OFPreference preferenceForKey:@"OUIDocumentPickerSelectedScope"];
    });
    
    return scopePreference;
}

+ (OFPreference *)folderPreference;
{
    static OFPreference *folderPreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        folderPreference = [OFPreference preferenceForKey:@"OUIDocumentPickerSelectedFolderPath"];
    });

    return folderPreference;
}

+ (OFPreference *)filterPreference;
{
    static OFPreference *filterPreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        filterPreference = [OFPreference preferenceForKey:@"OUIDocumentPickerSelectedFilter"];
    });
    
    return filterPreference;
}

+ (OUIDocumentPickerFilter *)documentFilterForPicker:(OUIDocumentPicker *)picker scope:(ODSScope *)scope;
{
    if (scope.isTrash)
        return nil;

    NSArray *availableFilters = nil;

    if ([picker.delegate respondsToSelector:@selector(documentPickerAvailableFilters:)])
        availableFilters = [picker.delegate documentPickerAvailableFilters:picker];

    if (availableFilters.count == 1)
        return availableFilters.lastObject;

    for (OUIDocumentPickerFilter *pickerFilter in availableFilters) {
        if ([pickerFilter.identifier isEqualToString:ODSDocumentPickerFilterDocumentIdentifier])
            return pickerFilter;
    }

    return nil;
}

+ (OUIDocumentPickerFilter *)selectedFilterForPicker:(OUIDocumentPicker *)picker;
{
    if (picker.selectedScopeViewController.selectedScope.isTrash)
        return  nil;

    OFPreference *filterPreference = [self filterPreference];
    NSString *identifier = [filterPreference stringValue];
    NSArray *availableFilters = nil;
    
    if ([picker.delegate respondsToSelector:@selector(documentPickerAvailableFilters:)])
        availableFilters = [picker.delegate documentPickerAvailableFilters:picker];
    
    OUIDocumentPickerFilter *filter = nil;
    NSUInteger filterIndex = 0;
    for (filterIndex = 0; filterIndex < [availableFilters count]; filterIndex++) {
        OUIDocumentPickerFilter *possibleFilter = [availableFilters objectAtIndex:filterIndex];
        if ([possibleFilter.identifier isEqualToString:identifier]) {
            filter = possibleFilter;
            break;
        }
    }
    
    if (!filter && [availableFilters count] > 0) {
        filter = [availableFilters objectAtIndex:0];
        // Fix the preference for other readers to know what we eneded up using. We'll get called reentrantly here now.
        [filterPreference setStringValue:filter.identifier];
    }
    return filter;
}

+ (OFPreference *)sortPreference;
{
    static OFPreference *SortPreference = nil;
    if (SortPreference == nil) {
        OFEnumNameTable *enumeration = [[OFEnumNameTable alloc] initWithDefaultEnumValue:OUIDocumentPickerItemSortByDate];
        [enumeration setName:@"name" forEnumValue:OUIDocumentPickerItemSortByName];
        [enumeration setName:@"date" forEnumValue:OUIDocumentPickerItemSortByDate];
        SortPreference = [OFPreference preferenceForKey:@"OUIDocumentPickerSortKey" enumeration:enumeration];
    }
    return SortPreference;
}

+ (NSArray *)sortDescriptors;
{
    return [self sortDescriptorsForSortType:[[self sortPreference] enumeratedValue]];
}

+ (NSArray *)sortDescriptorsForSortType:(OUIDocumentPickerItemSort)sortPreference
{
    NSMutableArray *descriptors = [NSMutableArray array];
    
    if (sortPreference == OUIDocumentPickerItemSortByDate) {
        NSSortDescriptor *dateSort = [[NSSortDescriptor alloc] initWithKey:ODSItemUserModificationDateBinding ascending:NO];
        [descriptors addObject:dateSort];
    }
    
    NSSortDescriptor *nameSort = [[NSSortDescriptor alloc] initWithKey:ODSItemNameBinding ascending:YES selector:@selector(localizedStandardCompare:)];
    [descriptors addObject:nameSort];
    
    return descriptors;
}

- (BOOL)supportsUpdatingSorting;
{
    return YES;
}

- (void)ensureSelectedFilterMatchesFileURL:(NSURL *)fileURL;
{
    ODSFileItem *fileItem = [_documentStore fileItemWithURL:fileURL];
    if (fileItem) {
        [self ensureSelectedFilterMatchesFileItem:fileItem];
    } else {
        OBASSERT_NOT_REACHED(@"Unknown file URL: %@", fileURL);
    }
}

- (void)ensureSelectedFilterMatchesFileItem:(ODSFileItem *)fileItem;
{
    // If importing/making this document would leave it filtered out, switch to some available filter that would show it.
    if (_documentStoreFilter.filterPredicate && ![_documentStoreFilter.filterPredicate evaluateWithObject:fileItem]) {
        for (OUIDocumentPickerFilter *filter in [self availableFilters]) {
            if ([filter.predicate evaluateWithObject:fileItem]) {
                [[[self class] filterPreference] setStringValue:filter.identifier];
                break;
            }
        }
        OBASSERT([_documentStoreFilter.filterPredicate evaluateWithObject:fileItem]);
    }
}

- (void)animateFilterChangeTo:(NSString *)newFilterIdentifier withCompletion:(void (^)(void))completion
{
    NSArray *availableFilters = [self availableFilters];
    NSString *oldSelectedIdentifier = [[[self class] filterPreference] stringValue];
    NSUInteger oldSelectedIndex = [availableFilters indexOfObjectPassingTest:^BOOL(OUIDocumentPickerFilter *filter, NSUInteger idx, BOOL *stop) {
        return [filter.identifier isEqualToString:oldSelectedIdentifier];
    }];
    
    NSUInteger newSelectedIndex = [availableFilters indexOfObjectPassingTest:^BOOL(OUIDocumentPickerFilter *filter, NSUInteger idx, BOOL * _Nonnull stop) {
        return [filter.identifier isEqualToString:newFilterIdentifier];
    }];
    
    if (newSelectedIndex == oldSelectedIndex || newSelectedIndex == NSNotFound) {
        if (completion) {
            completion();
        }
        return;
    }
    
    UIView *snapshot = [_mainScrollView snapshotViewAfterScreenUpdates:NO];
    
    CGPoint convertedTopControlsOrigin = [self.view convertPoint:_topControls.bounds.origin fromView:_topControls];
    CGRect topControlsRect = (CGRect){
        .origin.x = 0,
        .origin.y = convertedTopControlsOrigin.y,
        .size.width = self.view.bounds.size.width,
        .size.height = _topControls.bounds.size.height + 5.0f  // very bottom edge of the controls were getting left out
    };
    UIView *topControlsSnapshot = [self.view resizableSnapshotViewFromRect:topControlsRect afterScreenUpdates:YES withCapInsets:UIEdgeInsetsZero];
    CGRect newTopControlsSnapshotFrame = topControlsSnapshot.frame;
    newTopControlsSnapshotFrame.origin.y = convertedTopControlsOrigin.y;
    topControlsSnapshot.frame = newTopControlsSnapshotFrame;
    
    CGRect frame = _mainScrollView.frame;
    BOOL movingLeft = newSelectedIndex < oldSelectedIndex;
    CGFloat movement = movingLeft ? CGRectGetWidth(frame) : -CGRectGetWidth(frame);
    
    [UIView performWithoutAnimation:^{
        snapshot.frame = frame;
        [self.view insertSubview:snapshot aboveSubview:_mainScrollView];
        [self.view insertSubview:topControlsSnapshot aboveSubview:snapshot];
        
        CGRect offscreenRect = frame;
        offscreenRect.origin.x -= movement;
        _mainScrollView.frame = offscreenRect;
        
        [[[self class] filterPreference] setStringValue:newFilterIdentifier];
        [_mainScrollView layoutIfNeeded];
    }];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        _mainScrollView.frame = frame;
        
        CGRect offscreenRect = frame;
        offscreenRect.origin.x += movement;
        snapshot.frame = offscreenRect;
    } completion:^(BOOL finished) {
        [snapshot removeFromSuperview];
        [topControlsSnapshot removeFromSuperview];
        if (completion) {
            completion();
        }
    }];
}

- (void)selectedFilterChanged;
{
    OBPRECONDITION(_documentStoreFilter);
    
    OUIDocumentPickerFilter *filter = [[self class] selectedFilterForPicker:self.documentPicker];
    [self.filtersSegmentedControl setSelectedSegmentIndex:[[self availableFilters] indexOfObject:filter]];
    
    if ([_documentStoreFilter.filterPredicate isEqual:filter.predicate])
        return;
    
    [self addDocumentStoreInitializationAction:^(OUIDocumentPickerViewController *blockSelf){
        blockSelf->_documentStoreFilter.filterPredicate = filter.predicate;
    }];

    // For now our filters are exclusive, but if they stop being so someday, we could filter our selection instead of clearing it entirely.
    [self clearSelection:NO];
    
    // The delegate likely wants to update the title displayed in the document picker toolbar.
    [self updateTitle];
    [_mainScrollView previewedItemsChangedForGroups];
}

- (void)selectedSortChanged;
{
    OUIDocumentPickerItemSort sort = [[[self class] sortPreference] enumeratedValue];
    
    if (sort == _mainScrollView.itemSort)
        return;

    [self.sortSegmentedControl setSelectedSegmentIndex:sort];
    _mainScrollView.itemSort = sort;
}

- (void)filterSegmentChanged:(id)sender;
{
    NSUInteger newSelectedIndex = ((UISegmentedControl *)sender).selectedSegmentIndex;
    OUIDocumentPickerFilter *newFilter = [[self availableFilters] objectAtIndex:newSelectedIndex];
    NSString *newFilterIdentifier = newFilter.identifier;
    
    [self animateFilterChangeTo:newFilterIdentifier withCompletion:nil];
}

- (void)sortSegmentChanged:(id)sender;
{
    [[[self class] sortPreference] setEnumeratedValue:((UISegmentedControl *)sender).selectedSegmentIndex];
}

- (void)search:(id)sender;
{
    
}

- (void)addDocumentStoreInitializationAction:(void (^)(OUIDocumentPickerViewController *blockSelf))action;
{
    if (!_afterDocumentStoreInitializationActions)
        _afterDocumentStoreInitializationActions = [[NSMutableArray alloc] init];
    [_afterDocumentStoreInitializationActions addObject:[action copy]];
    
    // ... might be able to call it right now
    [self _flushAfterDocumentStoreInitializationActions];
}

- (void)updateTitle;
{
    NSString *title;
    if (_folderItem == _folderItem.scope.rootFolder)
        title = _folderItem.scope.displayName;
    else
        title = _folderItem.name;

    NSArray *filters = [self availableFilters];
    if ([filters count] > 0) { // Template picker for new documents won't have selectable filters
        NSArray *filterTitles = [filters arrayByPerformingBlock:^(OUIDocumentPickerFilter *filter) {
            return filter.localizedFilterChooserShortButtonLabel;
        }];
        
        NSUInteger index = self.filtersSegmentedControl.selectedSegmentIndex;
        NSString *filterName = index < filterTitles.count ? [filterTitles objectAtIndex:index] : nil;
        
        OBASSERT(filterName);
        if (filterName) {
            title = [title stringByAppendingString:@" — "];
            title = [title stringByAppendingString:filterName];
        }
    }
    self.displayedTitleString = title;
}

- (void)updateToolbarItemsEnabledness
{
    [self _updateToolbarItemsEnabledness];
}

- (NSString *)nameLabelForItem:(ODSItem *)item;
{
    NSString *nameLabel = nil;
    if ([self.documentPicker.delegate respondsToSelector:@selector(documentPicker:nameLabelForItem:)]) {
        nameLabel = [self.documentPicker.delegate documentPicker:self.documentPicker nameLabelForItem:item];
    } else if ([self _documentTypeForCurrentFilter] == ODSDocumentTypeTemplate) {
        nameLabel =  NSLocalizedStringFromTableInBundle(@"Template:", @"OmniUIDocument", OMNI_BUNDLE, @"file name label for template filte types");
    }
    if (!nameLabel)
        return @"";
    return nameLabel;
}

#pragma mark - OUIDocumentExporterHost protocol

- (NSArray *)fileItemsToExport
{
    NSMutableArray *files = [NSMutableArray array];
    for (ODSFileItem *item in self.selectedItems)
        if ([item isKindOfClass:[ODSFileItem class]])
            [files addObject:item];
    return files;
}

- (ODSFileItem *)fileItemToExport
{
    ODSFileItem *selectedItem = self.singleSelectedFileItem;
    if (!selectedItem || !self.canPerformActions) {
        return nil;
    }
    
    // Make sure selected item is fully downloaded.
    if (!selectedItem.isDownloaded) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Cannot Export Item", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error title") message:NSLocalizedStringFromTableInBundle(@"This item cannot be exported because it is not fully downloaded. Please tap the item and wait for it to download before trying again.", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error message") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUIDocument", OMNI_BUNDLE, @"button title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}];
        [alertController addAction:okAction];
        
        [self presentViewController:alertController animated:YES completion:^{}];
        return nil;
    }
    
    
    return selectedItem;
}

- (UIColor *)tintColorForExportMenu
{
    return [UIColor blackColor];
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    self.view.clipsToBounds = YES;
    
    _normalTitleView = [[OUIDocumentTitleView alloc] init];
    _normalTitleView.syncAccountActivity = _accountActivity;
    _normalTitleView.delegate = self;
    _normalTitleView.hideTitle = YES;
    _normalTitleView.hideSyncButton = YES;
    self.navigationItem.titleView = _normalTitleView;
    
    _backgroundView.image = [[OUIDocumentAppController controller] documentPickerBackgroundImage];
    if (!_backgroundView.image)
        _backgroundView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    else
        _backgroundView.contentMode = UIViewContentModeTop;
    
    OFPreference *sortPreference = [[self class] sortPreference];
    [OFPreference addObserver:self selector:@selector(selectedSortChanged) forPreference:sortPreference];
    [self selectedSortChanged];
    
    if (self.selectedScope.isTrash == NO) {
        OFPreference *filterPreference = [[self class] filterPreference];
        [OFPreference addObserver:self selector:@selector(selectedFilterChanged) forPreference:filterPreference];
        [self selectedFilterChanged];
    }
    
    // if we already have filteredItems update our scrollview content so we aren't order dependent on loading views before items
    if (_filteredItems) {
        NSSet *_current = _filteredItems;
        _filteredItems = nil;
        [self setFilteredItems:_current];
    }

    self.mainScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    // We sign up for this notification in -viewDidLoad, instead of -viewWillAppear: since we want to receive it when we are off screen (previews can be updated when a document is closing and we never get on screen -- for example if a document is open and another document is opened via tapping on Mail).
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_previewsUpdateForFileItemNotification:) name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];

    [center postNotificationName:@"DocumentPickerViewControllerViewDidLoadNotification"  object:nil];
    
    [self setUpActivityIndicator];
}

@synthesize activityIndicator = _activityIndicator;
- (UIActivityIndicatorView *)activityIndicator {
    return _activityIndicator;
}

- (void)setUpActivityIndicator
{
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    UIColor *tintColor = window.tintColor;
    if (tintColor) {
        _activityIndicator.color = tintColor;
    } else {
        _activityIndicator.color = [OAAppearanceDefaultColors appearance].omniGreenColor;
    }

    _activityIndicator.hidesWhenStopped = YES;
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainScrollView.superview addSubview:_activityIndicator];
    [NSLayoutConstraint activateConstraints:@[ [_activityIndicator.centerXAnchor constraintEqualToAnchor:_activityIndicator.superview.centerXAnchor],
                                               [_activityIndicator.centerYAnchor constraintEqualToAnchor:_activityIndicator.superview.centerYAnchor]
                                               ]];
}


- (void)viewDidLayoutSubviews;
{
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if (state == UIApplicationStateBackground)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:OUISystemIsSnapshottingNotification object:nil];
    }

    if (!_renameSession && !_mainScrollView.isDecelerating  && !_mainScrollView.isDragging) {
        UIEdgeInsets insets = _mainScrollView.contentInset;
        CGFloat goodBottomInset = [self _bottomContentInsetNecessaryToAllowContentOffsetY:[_mainScrollView contentOffsetYToHideTopControls]];
        if (insets.bottom != goodBottomInset) {
            CGPoint statusQuoOffset = _mainScrollView.contentOffset;
            insets.bottom = goodBottomInset;
            _mainScrollView.contentInset = insets;
            _mainScrollView.contentOffset = statusQuoOffset;
        }
    }
    
    [super viewDidLayoutSubviews];
    if (_isAppearing || _needsDelayedHandleResize) {
        CGFloat yOffset = [self contentOffsetYAfterAdjustingInsetToShowTopControls:self.wasShowingTopControlsBeforeTransition];
        self.mainScrollView.contentOffset = CGPointMake(self.mainScrollView.contentOffset.x, yOffset);
        _isAppearing = NO;
        _needsDelayedHandleResize = NO;
    }
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)willMoveToParentViewController:(UIViewController *)parent;
{
    [super willMoveToParentViewController:parent];
    
    if (parent) {
        if (!_isObservingKeyboardNotifier) {
            _isObservingKeyboardNotifier = YES;
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardHeightWillChange:) name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
        }
    }
}

- (void)didMoveToParentViewController:(UIViewController *)parent;
{
    [super didMoveToParentViewController:parent];
    
    if (!parent) {
        if (_isObservingKeyboardNotifier) {
            _isObservingKeyboardNotifier = NO;
            [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated;
{
    _isAppearing = YES;
    [super viewWillAppear:animated];
    
    if (!_topControls) {
        [self _setupTitleLabelToUseInCompactWidth];
        [self setupTopControls];
    }
    
    _mainScrollView.shouldHideTopControlsOnNextLayout = YES;
    
    self.navigationController.navigationBar.barStyle = UIBarStyleDefault;

    [_mainScrollView retileItems];
    
    // Might have been disabled while we went off screen (like when making a new document)
    [self _performDelayedItemPropagationWithCompletionHandler:nil];

    [self _updateEmptyViewControlVisibility];
    
    if (!_isObservingApplicationDidEnterBackground) { // Don't leak observations if view state transition calls are duplicated/dropped
        _isObservingApplicationDidEnterBackground = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    
    self.wasShowingTopControlsBeforeTransition = NO;
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    [self _updateEmptyViewControlVisibility];
    [self _updateToolbarItemsForTraitCollection:self.traitCollection animated:YES];
    
    if (self.traitCollection.forceTouchCapability) {
        self.previewingContext = [self registerForPreviewingWithDelegate:self sourceView:self.view];
    }

    OFPreference *folderPreference = [[self class] folderPreference];
    [folderPreference setStringValue:_folderItem.relativePath];

#if GENERATE_DEFAULT_PNG
    OUIDisplayNeededViews();
    UIImage *image = [self.navigationController.view snapshotImage];

    CGRect bounds = self.view.bounds;
    NSString *orientation = bounds.size.height > bounds.size.width ? @"Portrait" : @"Landscape";
    NSString *scale = [[UIScreen mainScreen] scale] > 1 ? @"@2x" : @"";
    NSString *imagePath = [NSString stringWithFormat:@"/tmp/Default-%@%@.png", orientation, scale];
    [UIImagePNGRepresentation(image) writeToFile:imagePath atomically:YES];
#endif
}

- (void)viewWillDisappear:(BOOL)animated;
{
    [super viewWillDisappear:animated];
    
    if (_isObservingApplicationDidEnterBackground) { // Don't leak observations if view state transition calls are duplicated/dropped
        _isObservingApplicationDidEnterBackground = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    
    // Passing `NO` was not enought to remove the animations.
    [UIView performWithoutAnimation:^{
        [self.navigationController setToolbarHidden:YES animated:NO];
    }];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    
    // Not deciding based on traitCollection.forceTouchCapability because technically that could change and we'd still want to unregister when this view goes away.
    if (self.previewingContext != nil) {
        [self unregisterForPreviewingWithContext:self.previewingContext];
        self.previewingContext = nil;
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    [super setEditing:editing animated:animated];
    
    // If you Edit in an open group, the items in the background scroll view shouldn't wiggle.
    [self.mainScrollView setEditing:editing animated:animated];
    
    if (!editing) {
        [self clearSelection:NO];
    }
    
    [self _updateToolbarItemsForTraitCollection:self.traitCollection animated:YES];
    [self _updateToolbarItemsEnabledness];
}

- (void)setToolbarItems:(NSArray *)toolbarItems animated:(BOOL)animated;
{
    // This doesn't update our UIToolbar, but OUIDocumentRenameSession will use it to go back to the toolbar items we should be using.
    [super setToolbarItems:toolbarItems animated:animated];
    
    // The rename view controller overrides our toolbar's items. Might need a more general check for "has some other view controller taken over the toolbar" (or maybe such controller should have their own toolbar).
    if (_renameSession == nil) {
        [_toolbar setItems:toolbarItems animated:animated];
    }
}

#pragma mark UIViewControllerPreviewingDelegate

- (nullable UIViewController *)previewingContext:(id <UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location;
{
    OBPRECONDITION(_exporter);
    OBASSERT(self.previewingContext == previewingContext);
    
    if (self.isEditing || _documentScope.isTrash || self.renameSession) {
        return nil;
    }
    
    CGPoint pointToPreview = [self.mainScrollView convertPoint:location fromCoordinateSpace:self.view];
    OUIDocumentPickerItemView *itemView = [self.mainScrollView itemViewForPoint:pointToPreview];
    if (itemView == nil) {
        return nil;
    }
    
    ODSItem *item = itemView.item;
    
    if ([item isKindOfClass:[ODSFileItem class]]) {
        ODSFileItem *fileItem = (ODSFileItem *)item;
        
        if (fileItem.isDownloaded == NO) {
            return nil;
        }
        
        NSURL *fileURL = fileItem.fileURL;
        Class cls = [[OUIDocumentAppController controller] documentClassForURL:fileURL];
        OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
        
        OUIDocumentPreview *documentPreview = [OUIDocumentPreview makePreviewForDocumentClass:cls fileItem:fileItem withArea:OUIDocumentPreviewAreaLarge];
        
        OUIDocumentPreviewingViewController *documentPreviewingViewController = [[OUIDocumentPreviewingViewController alloc] initWithFileItem:fileItem preview:documentPreview];
        if (self.canPerformActions) {
            if (fileItem.scope.isTrash == NO) {
                // Export
                UIPreviewAction *exportAction = [UIPreviewAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Export…", @"OmniUIDocument", OMNI_BUNDLE, @"Export document preview action title.")
                                                                           style:UIPreviewActionStyleDefault
                                                                         handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                             [_exporter exportItem:fileItem sender:nil];
                                                                         }];
                [documentPreviewingViewController addPreviewAction:exportAction];
                
                if (fileItem.scope.isExternal == NO) {
                    // Move
                    UIPreviewAction *moveAction = [UIPreviewAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Move…", @"OmniUIDocument", OMNI_BUNDLE, @"Move document preview action title.")
                                                                             style:UIPreviewActionStyleDefault
                                                                           handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                               // The move menu acts on the selected items
                                                                               [self setEditing:YES animated:YES];
                                                                               _setItemSelectedAndBounceView(self, itemView, YES);
                                                                               
                                                                               [self _moveWithDidFinishHandler:^{
                                                                                   [self setEditing:NO animated:NO];
                                                                               }];
                                                                           }];
                    [documentPreviewingViewController addPreviewAction:moveAction];
                }
            }
            
            if ((fileItem.isDownloaded) && (fileItem.scope.isExternal == NO)) {
                // Duplicte
                UIPreviewAction *duplicateAction = [UIPreviewAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Duplicate", @"OmniUIDocument", OMNI_BUNDLE, @"Duplicate document preview action title.")
                                                                              style:UIPreviewActionStyleDefault
                                                                            handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                                [self _duplicateItemsWithoutConfirmation:[NSSet setWithObject:fileItem]];
                                                                            }];
                [documentPreviewingViewController addPreviewAction:duplicateAction];
            }
            
            // Delete
            NSSet <ODSItem *> *itemsToDelete = [NSSet <ODSItem *> setWithObject:fileItem];
            UIPreviewAction *deleteAction = [UIPreviewAction actionWithTitle:[self _deleteDocumentTitle:itemsToDelete.count]
                                                                       style:UIPreviewActionStyleDestructive
                                                                     handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                         [self _deleteItems:itemsToDelete sender:itemView];
                                                                     }];
            [documentPreviewingViewController addPreviewAction:deleteAction];
        }
        
        previewingContext.sourceRect = [self.view convertRect:itemView.frame fromView:self.mainScrollView];
        
        return documentPreviewingViewController;
    }
    else if ([item isKindOfClass:[ODSFolderItem class]]) {
        // TODO: Might eventually provide a peek/pop for folder items, but not yet.
        return nil;
    }
    
    return nil;
}

- (void)previewingContext:(id <UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit;
{
    OBASSERT(self.previewingContext == previewingContext);
    OBASSERT([viewControllerToCommit isKindOfClass:[OUIDocumentPreviewingViewController class]]);
    
    OUIDocumentPreviewingViewController *documentPreviewingViewController = (OUIDocumentPreviewingViewController *)viewControllerToCommit;
    
    
    UIView *snapshotView = [self.view snapshotViewAfterScreenUpdates:NO];
    snapshotView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [documentPreviewingViewController prepareForCommitWithBackgroundView:snapshotView];
    
    [self presentViewController:documentPreviewingViewController animated:NO completion:nil];
    
    __block UIView *documentPreviewingSnapshotView = nil;
    ODSFileItem *fileItem = documentPreviewingViewController.fileItem;
    [[OUIDocumentAppController controller] openDocument:fileItem fromPeekWithWillPresentHandler:^(OUIDocumentOpenAnimator *openAnimator) {
        // Timing matters here. We need to make sure to take the snapshot of the documentPreviewingViewController's view before asking for its previewingSnapshotView later because when we ask for the previewingSnapshotView, the act of asking for the snapshot (in that method) seems to pull it from the view hirarchy (or something) and would cause it not to be included in this snapshot (if this were below that call).
        documentPreviewingSnapshotView = [documentPreviewingViewController.view snapshotViewAfterScreenUpdates:NO];
        [self.view addSubview:documentPreviewingSnapshotView];
        [self.view bringSubviewToFront:documentPreviewingSnapshotView];
        self.navigationController.navigationBarHidden = YES;
        
        openAnimator.backgroundSnapshotView = [documentPreviewingViewController backgroundSnapshotView];
        openAnimator.previewSnapshotView = [documentPreviewingViewController previewSnapshotView];
        openAnimator.previewRect = [documentPreviewingViewController previewRect];

        [documentPreviewingViewController dismissViewControllerAnimated:NO completion:nil];
    } completionHandler:^{
        [documentPreviewingSnapshotView removeFromSuperview];
        self.navigationController.navigationBarHidden = NO;
    }];
}


#pragma mark - UIResponder subclass

// Allow this so that when a document is closed we don't have a nil first responder (which would mean that the cmd-n key command on the document controller wouldn't fire).
- (BOOL)canBecomeFirstResponder;
{
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(newDocument:)) {
        return self.canPerformActions && self.selectedScope.canRenameDocuments && !self.selectedScope.isTrash && !self.presentedViewController && [[OUIDocumentAppController sharedController] canCreateNewDocument];
    }

    return [super canPerformAction:action withSender:sender];
}

#pragma mark - UITextInputTraits

// ... this avoids flicker when opening the keyboard (renaming a document) after having closed a dark-mode document
- (UIKeyboardAppearance)keyboardAppearance;
{
    return UIKeyboardAppearanceLight;
}

#pragma mark -
#pragma mark UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller;
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return nil;
}

- (CGRect)documentInteractionControllerRectForPreview:(UIDocumentInteractionController *)controller;
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return CGRectZero;
}

- (UIView *)documentInteractionControllerViewForPreview:(UIDocumentInteractionController *)controller;
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return nil;
}

#pragma mark - OUIDocumentTitleViewDelegate

- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView syncButtonTapped:(id)sender;
{
    OFXAgent *syncAgent = ((OFXDocumentStoreScope *)_documentScope).syncAgent;
    NSError *lastSyncError = _accountActivity.lastError;
    if (lastSyncError != nil) {
        [[OUIDocumentAppController controller] presentSyncError:lastSyncError forAccount:_accountActivity.account inViewController:self retryBlock:^{
            [syncAgent sync:nil];
        }];
        return;
    }
    
    [syncAgent sync:nil];
}

#pragma mark -
#pragma mark OUIDocumentPickerScrollView delegate

- (BOOL)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView rectIsFullyVisible:(CGRect)rect;
{
    CGRect bounds = scrollView.bounds;
    if (self.navigationController) {
        bounds = [self.navigationController visibleRectOfContainedView:scrollView];
    }
    if (CGRectContainsRect(bounds, rect)) {
        return YES;
    } else {
        return NO;
    }
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewStartedEditingName:(OUIDocumentPickerItemView *)itemView;
{
    if (!_isReadOnly)
        [self _startedRenamingInItemView:itemView];
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemView:(OUIDocumentPickerItemView *)itemView finishedEditingName:(NSString *)name;
{
    self.renameSession = nil;
    [self _updateToolbarItemsForTraitCollection:self.traitCollection animated:YES];
    _topControls.userInteractionEnabled = YES;
    _mainScrollView.scrollEnabled = YES;
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView willDisplayItemView:(OUIDocumentPickerItemView *)itemView;
{
    if ([self.documentPicker.delegate respondsToSelector:@selector(documentPicker:willDisplayItemView:)])
        [self.documentPicker.delegate documentPicker:self.documentPicker willDisplayItemView:itemView];
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView willEndDisplayingItemView:(OUIDocumentPickerItemView *)itemView;
{
    if ([self.documentPicker.delegate respondsToSelector:@selector(documentPicker:willEndDisplayingItemView:)])
        [self.documentPicker.delegate documentPicker:self.documentPicker willEndDisplayingItemView:itemView];
}

- (NSArray *)sortDescriptorsForDocumentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView;
{
    return [self.class sortDescriptors];
}

- (BOOL)isReadyOnlyForDocumentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView;
{
    return self.isReadOnly;
}

- (ODSDocumentType)_documentTypeForCurrentFilter;
{
    OUIDocumentPickerFilter *currentFilter = [self.class selectedFilterForPicker:_documentPicker];
    if (currentFilter == nil || [currentFilter.identifier isEqualToString:ODSDocumentPickerFilterDocumentIdentifier]) {
        return ODSDocumentTypeNormal;
    } else if ([currentFilter.identifier isEqualToString:ODSDocumentPickerFilterTemplateIdentifier]) {
        return ODSDocumentTypeTemplate;
    } else {
        return ODSDocumentTypeOther;
    }
}

static void _setItemSelectedAndBounceView(OUIDocumentPickerViewController *self, OUIDocumentPickerItemView *itemView, BOOL selected)
{
    // Turning the selection on/off changes how the item view lays out. We don't want that to animate though -- we just want the bounce down. If we want the selection layer to fade/grow in, we'd need a 'will changed selected'/'did change selected' path that where we can change the layout but not have the selection layer appear yet (maybe fade it in) and only disable animation on the layout change.
    OUIWithoutAnimating(^{        
        itemView.item.selected = selected;
        [itemView layoutIfNeeded];
    });
    
    // In addition to the border, iWork bounces the file item view down slightly on a tap (selecting or deselecting).
    [itemView bounceDown];
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView;
{
    if (!self.canPerformActions)
        return;
    if (_renameSession){
        if (_renameSession.itemView == itemView) {
            [_renameSession endRenaming];
            return;
        } else {
            return; // Another rename might be starting (we don't have a spot to start/stop ignore user interaction there since the keyboard drives the animation).
        }
    }
    
    ODSItem *item = itemView.item;
    if (self.editing) {
        _setItemSelectedAndBounceView(self, itemView, !item.selected);
        
        [self _updateToolbarItemsForTraitCollection:self.traitCollection animated:NO]; // Update the selected file item count
        [self _updateToolbarItemsEnabledness];
        return;
    }

    if (_documentScope.isTrash) {
        NSMutableArray *options = [NSMutableArray new];
        NSString *menuTitle = [self _menuTitleAfterAddingMoveOptions:options fromCurrentScope:_documentScope];
        
        // The move menu acts on the selected items
        [self setEditing:YES animated:YES];
        _setItemSelectedAndBounceView(self, itemView, YES);

        OUIMenuController *moveToMenuController = [[OUIMenuController alloc] init];
        moveToMenuController.topOptions = options;
        moveToMenuController.title = menuTitle;
        moveToMenuController.tintColor = [OAAppearanceDefaultColors appearance].omniBlueColor; // We are in 'edit' mode
        moveToMenuController.alwaysShowsNavigationBar = YES;
        moveToMenuController.didFinish = ^{
            [self setEditing:NO animated:YES];
        };
        
        UIPopoverPresentationController *popoverController = moveToMenuController.popoverPresentationController;
        popoverController.sourceView = itemView;
        popoverController.sourceRect = itemView.bounds;
        
        [self presentViewController:moveToMenuController animated:YES completion:^{
            popoverController.passthroughViews = nil;
        }];
        self.restoreToMenuController = moveToMenuController;
        return;
    }

    if ([itemView isKindOfClass:[OUIDocumentPickerFileItemView class]]) {
        ODSFileItem *fileItem = (ODSFileItem *)itemView.item;
        OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);
        
        if (fileItem.isDownloaded == NO) {
            __autoreleasing NSError *error = nil;
            if (![fileItem requestDownload:&error]) {
                OUI_PRESENT_ERROR_FROM(error, self);
            }
            return;
        }
        
        id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
        if ([delegate respondsToSelector:@selector(documentPicker:openTappedFileItem:)])
            [delegate documentPicker:_documentPicker openTappedFileItem:fileItem];

    } else if ([itemView isKindOfClass:[OUIDocumentPickerGroupItemView class]]) {
        OBASSERT([itemView.item isKindOfClass:[ODSFolderItem class]]);
        [_documentPicker navigateToFolder:(ODSFolderItem *)itemView.item animated:YES];
    } else {
        OBASSERT_NOT_REACHED("Unknown item view class");
    }
}

-(void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewLongpressed:(OUIDocumentPickerItemView *)itemView
{
    // go into edit mode, select this item.
    _setItemSelectedAndBounceView(self, itemView, YES);
    
    // We do this last since it updates the toolbar items, including the selection count.
    [self setEditing:YES animated:YES];
}

static UIImage *ImageForScope(ODSScope *scope) {
    if ([scope isKindOfClass:[ODSLocalDirectoryScope class]]) {
        return [UIImage imageNamed:@"OUIMenuItemLocalScope" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    } else if ([scope isKindOfClass:[OFXDocumentStoreScope class]]) {
        return [UIImage imageNamed:@"OUIMenuItemPresenceScope" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    } else if ([scope isKindOfClass:[ODSExternalScope class]]) {
        return [UIImage imageNamed:@"OUIMenuItemExternalScope" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    } else {
        OBASSERT_NOT_REACHED("Unknown scope type %@", scope);
        return nil;
    }
}

- (NSString *)_menuTitleAfterAddingMoveOptions:(NSMutableArray *)options fromCurrentScope:(ODSScope *)currentScope;
{
    NSMutableArray *destinationScopes = [_documentStore.scopes mutableCopy];
    [destinationScopes removeObject:_documentStore.trashScope];
    [destinationScopes removeObject:_documentStore.templateScope];
    [destinationScopes sortUsingSelector:@selector(compareDocumentScope:)];
    
    // Want to allow moving to other folders in a scope if the selection is in a subfolder right now.
    //[destinationScopes removeObject:currentScope];
    
    // Don't allow moving items to the folder the are already in, or the subtrees defined by the possibly moving selection
    ODSFolderItem *currentFolder = _folderItem;
    NSSet *selectedFolders = self.selectedFolders;

    NSString *menuTitle;
    if (currentScope.isTrash)
        menuTitle = NSLocalizedStringFromTableInBundle(@"Restore to...", @"OmniUIDocument", OMNI_BUNDLE, @"Share menu title");
    else
        menuTitle = NSLocalizedStringFromTableInBundle(@"Move to...", @"OmniUIDocument", OMNI_BUNDLE, @"Share menu title");
    
    for (ODSScope *scope in destinationScopes) {
        NSMutableArray *folderOptions = [NSMutableArray array];
        if (scope.isExternal) {
            // bug:///147708
            continue;
        }

        [self _addMoveToFolderOptions:folderOptions candidateParentFolder:scope.rootFolder currentFolder:currentFolder excludedTreeFolders:selectedFolders];
        
        OUIMenuOptionAction moveToScopeRootAction = ^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self _moveSelectedDocumentsToFolder:scope.rootFolder];
        };
        
        UIImage *scopeImage = ImageForScope(scope);
        
        if ([folderOptions count] > 0) {
            // There are valid options -- if this scope is valid too, add an option for it.
            if (currentFolder != scope.rootFolder) {
                for (OUIMenuOption *option in folderOptions)
                    option.indentationLevel++;
                
                OUIMenuOption *moveToScopeRootOption = [OUIMenuOption optionWithTitle:scope.displayName image:scopeImage action:moveToScopeRootAction];
                [folderOptions insertObject:moveToScopeRootOption atIndex:0];
            }
            
            // If this is the only scope, don't wrap it up in another level of menus
            if ([destinationScopes count] == 1) {
                [options addObjectsFromArray:folderOptions];
            } else {
                OUIMenuOption *option = [[OUIMenuOption alloc] initWithTitle:scope.displayName image:scopeImage options:folderOptions destructive:NO action:nil];
                [options addObject:option];
            }
        } else if (currentFolder != scope.rootFolder) {
            // No valid folders in this scope, but the root is a valid destination. Make its root item selectable.
            OUIMenuOption *option = [OUIMenuOption optionWithTitle:scope.displayName image:scopeImage action:moveToScopeRootAction];
            [options addObject:option];
        }
    }
    
    return menuTitle;
}

#pragma mark - UIScrollView delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
{
    if (_freezeTopControlAlpha) {
        return;
    }
    if (_topControls.subviews.count > 0) {
        CGFloat contentYOffset = scrollView.contentOffset.y;
        CGFloat contentYOffsetForFullAlpha = [_mainScrollView contentOffsetYForTopControlsFullAlpha];
        CGFloat contentYOffsetForZeroAlpha = [_mainScrollView contentOffsetYToHideTopControls];
        _topControls.alpha = CLAMP((contentYOffset - contentYOffsetForZeroAlpha) / (contentYOffsetForFullAlpha - contentYOffsetForZeroAlpha), 0, 1);
        _titleLabelToUseInCompactWidth.alpha = 1 - _topControls.alpha;        
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView;
{
    // Hoping this solves <bug:///93404> (Not automatically put into rename mode for new folders created off the currently visible page of documents)... I'm wondering if the cause is a race between layout (which is driven by either a display link or a runloop observer) and the scroll view animation completing (and thus sending its delegate method).
    // Since -itemViewForItem: doesn't force layout, we do it here.
    [_mainScrollView setNeedsLayout];
    [_mainScrollView layoutIfNeeded];
    
    [_mainScrollView performScrollFinishedHandlers];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset;
{
    CGFloat targetContentYOffset = targetContentOffset->y;
    CGFloat halfwayPoint = ([_mainScrollView contentOffsetYToHideTopControls] - [_mainScrollView contentOffsetYToShowTopControls]) / 2.0f + [_mainScrollView contentOffsetYToShowTopControls];
    if (targetContentYOffset > halfwayPoint) {
        if ([_mainScrollView isShowingTitleLabel]) {
            // give the title some stickiness to the top of the screen.  if more than 1/2 of it will be showing at the target offset, make all of it show
            if (targetContentYOffset < (_titleLabelToUseInCompactWidth.frame.origin.y + 0.5*_titleLabelToUseInCompactWidth.frame.size.height)-_mainScrollView.contentInset.top) {
                targetContentOffset->y = [_mainScrollView contentOffsetYToHideTopControls];
            } else {
                targetContentOffset->y = MAX(targetContentYOffset, [_mainScrollView contentOffsetYToHideTopControls]);
            }
        } else {
            targetContentOffset->y = MAX(targetContentYOffset, [_mainScrollView contentOffsetYToHideTopControls]);
        }
    } else {
        CGFloat yToShowControls = [_mainScrollView contentOffsetYToShowTopControls];
        if (targetContentYOffset > yToShowControls) {
            targetContentOffset->y = yToShowControls;
        } else {
            // scrollview is bouncing
        }
    }
    [self _alterBottomContentInsetIfNecessaryToAllowContentOffsetY:targetContentOffset->y];
}

- (void)_alterBottomContentInsetIfNecessaryToAllowContentOffsetY:(CGFloat)desiredOffsetY;
{
    CGFloat neededBottomInset = [self _bottomContentInsetNecessaryToAllowContentOffsetY:desiredOffsetY];
    if (_mainScrollView.contentInset.bottom < neededBottomInset)
    {
        UIEdgeInsets workableInsets = _mainScrollView.contentInset;
        workableInsets.bottom = neededBottomInset;
        _mainScrollView.contentInset = workableInsets;
    }
}

- (CGFloat)_bottomContentInsetNecessaryToAllowContentOffsetY:(CGFloat)desiredOffsetY;
{
    CGFloat heightRemainingBelowOffset = _mainScrollView.contentSize.height - desiredOffsetY;
    if (heightRemainingBelowOffset < _mainScrollView.frame.size.height) {
        return _mainScrollView.frame.size.height - heightRemainingBelowOffset;
    }
    return 0;
}

#pragma mark - Accessibility

- (BOOL)accessibilityScroll:(UIAccessibilityScrollDirection)direction
{
    // handle accessibilty scroll to expose the sort and filter controls.
    if (direction == UIAccessibilityScrollDirectionDown) {
        if (_mainScrollView.contentOffset.y < [_mainScrollView contentOffsetYToHideTopControls]) {
            _mainScrollView.contentOffset = CGPointMake(_mainScrollView.contentOffset.x, [_mainScrollView contentOffsetYToHideTopControls]);
            
            // move the focus to either the first item in the picker, or the title label (if showing the title label)
            
            ODSItem *firstItem = [[_mainScrollView sortedItems] firstObject];
            UIView *selectionView = [self.mainScrollView itemViewForItem:firstItem];
            
            if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
                selectionView = _titleLabelToUseInCompactWidth;
            }
            
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, selectionView);
            return YES;
        }
        
    } else if (direction == UIAccessibilityScrollDirectionUp) {
        if (self.mainScrollView.isShowingTitleLabel || self.mainScrollView.contentOffset.y <= [_mainScrollView contentOffsetYToHideTopControls]) {
            _mainScrollView.contentOffset = CGPointMake(_mainScrollView.contentOffset.x, [_mainScrollView contentOffsetYToShowTopControls]);
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, _mainScrollView.topControls);
            return YES;
        }
        
    }
    return NO;
}


#pragma mark - Internal

- (ODSFileItem *)_preferredVisibleItemFromSet:(NSSet *)fileItemsNeedingPreviewUpdate;
{
    // Don't think too hard if there is just a single incoming iCloud update
    if ([fileItemsNeedingPreviewUpdate count] <= 1)
        return [fileItemsNeedingPreviewUpdate anyObject];
    
    // Find a file preview that will update something in the user's view.
    ODSFileItem *fileItem = nil;
    if (!fileItem)
        fileItem = [_mainScrollView preferredVisibleItemFromSet:fileItemsNeedingPreviewUpdate];

    return fileItem;
}

- (void)_renameItem:(ODSItem *)item baseName:(NSString *)baseName completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    completionHandler = [completionHandler copy];
    
    // We have no open documents at this point, so we don't need to synchronize with UIDocument autosaving via -performAsynchronousFileAccessUsingBlock:. We do want to prevent other documents from opening, though.
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    // We don't want a "directory changed" notification for the local documents directory.
    [self _beginIgnoringDocumentsDirectoryUpdates];

    void (^reenable)(void) = [^{
        [self _endIgnoringDocumentsDirectoryUpdates];
        [lock unlock];
    } copy];
    
    if (item.type == ODSItemTypeFile) {
        ODSFileItem *fileItem = (ODSFileItem *)item;
        
        NSString *fileType = fileItem.fileType;
        OBASSERT(fileType);
        
        [fileItem.scope renameFileItem:fileItem baseName:baseName fileType:fileType completionHandler:^(NSURL *destinationURL, NSError *error){
            
            reenable();
            
            if (destinationURL) {
                [self _didPerformRenameToFileURL:destinationURL];
                completionHandler(nil);
            } else {
                [error log:@"Error renaming document with URL \"%@\" to \"%@\" with type \"%@\"", [fileItem.fileURL absoluteString], baseName, fileType];
                OUI_PRESENT_ERROR_FROM(error, self);
                
                completionHandler(error);
            }
        }];
    } else if (item.type == ODSItemTypeFolder) {
        ODSFolderItem *folderItem = (ODSFolderItem *)item;
        
        [folderItem.scope renameFolderItem:folderItem baseName:baseName completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil){
            
            reenable();

            OUIDocumentPickerScrollView *scrollView = self.mainScrollView;
            [scrollView sortItems];
            [scrollView scrollItemToVisible:item animated:NO];

            if (errorsOrNil == nil) {
                completionHandler(nil);
            } else {
                for (NSError *error in errorsOrNil) {
                    [error log:@"Error renaming folder %@ to \"%@\"", folderItem.relativePath, baseName];
                    OUI_PRESENT_ERROR_FROM(error, self);
                }
                
                completionHandler([errorsOrNil firstObject]);
            }
        }];
    } else {
        OBASSERT_NOT_REACHED("Unknown item type");
    }
    
}

#pragma mark - Private

- (UIBarButtonItem *)emptyTrashBarButtonItem;
{
    if (_emptyTrashBarButtonItem == nil) {
        _emptyTrashBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Empty Trash", @"OmniUIDocument", OMNI_BUNDLE, @"empty trash button title") style:UIBarButtonItemStylePlain target:self action:@selector(emptyTrashItemTapped:)];
        _emptyTrashBarButtonItem.tintColor = [OAAppearanceDefaultColors appearance].omniRedColor;
    }

    return _emptyTrashBarButtonItem;
}

- (UIBarButtonItem *)appMenuBarButtonItem;
{
    if (_appMenuBarButtonItem == nil) {
        _appMenuBarButtonItem = [[OUIAppController controller] newAppMenuBarButtonItem];
    }
    return _appMenuBarButtonItem;
}

- (UIBarButtonItem *)deleteBarButtonItem;
{
    if (_deleteBarButtonItem == nil) {
        NSString *deleteLabel;
        NSString *deleteImageName;
        if (self.selectedScope.isTrash) {
            deleteLabel = NSLocalizedStringFromTableInBundle(@"Delete", @"OmniUIDocument", OMNI_BUNDLE, @"Delete toolbar item accessibility label.");
            deleteImageName = @"OUIDeleteFromTrash";
        } else if (self.selectedScope.isExternal) {
            deleteLabel = NSLocalizedStringFromTableInBundle(@"Remove", @"OmniUIDocument", OMNI_BUNDLE, @"Remove from external container toolbar item accessibility label.");
            deleteImageName = @"OUIDocumentRemoveFromExternal";
        } else {
            deleteLabel = NSLocalizedStringFromTableInBundle(@"Move to Trash", @"OmniUIDocument", OMNI_BUNDLE, @"Move to Trash toolbar item accessibility label.");
            deleteImageName = @"OUIDocumentDelete";
        }
        UIImage *deleteButtonImage = [UIImage imageNamed:deleteImageName inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
        _deleteBarButtonItem = [[UIBarButtonItem alloc] initWithImage:deleteButtonImage style:UIBarButtonItemStylePlain target:self action:@selector(deleteDocument:)];
        _deleteBarButtonItem.accessibilityLabel = deleteLabel;
    }
    
    return _deleteBarButtonItem;
}

- (void)_updateToolbarItemsForTraitCollection:(UITraitCollection *)traitCollection animated:(BOOL)animated;
{
    OBPRECONDITION(_documentStore);

#if GENERATE_DEFAULT_PNG
    self.navigationItem.leftBarButtonItems = @[];
    self.navigationItem.rightBarButtonItems = @[];
    self.navigationItem.titleView.alpha = 0.0f;
    self.navigationItem.hidesBackButton = YES;
    return;
#endif
    
    BOOL editing = self.isEditing;

    // update the bottom toolbar

    // We want the empty trash bar button item in both modes when viewing the trash.
    UIBarButtonItem *wantedButton = nil;
    if (self.selectedScope.isTrash) {
        wantedButton = [self emptyTrashBarButtonItem];
    }

    if (wantedButton != nil) {
        UIBarButtonItem *flexiSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
        OBASSERT([NSThread isMainThread]);
        // Passing `NO` was not enought to remove the animations.
        [UIView performWithoutAnimation:^{
            [self.navigationController setToolbarHidden:NO animated:NO];
        }];
        [self setToolbarItems:@[flexiSpace, wantedButton, flexiSpace] animated:NO];
    } else {
        // Passing `NO` was not enought to remove the animations.
        [UIView performWithoutAnimation:^{
            [self.navigationController setToolbarHidden:YES animated:NO];
        }];
    }
    // calculate left bar button items
    NSMutableArray *leftItems = [NSMutableArray array];
    UINavigationItem *navigationItem = self.navigationItem;

    if (_renameSession) {
        ODSItem *item = _renameSession.itemView.item;
        
        NSString *title = nil;
        id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
        if (self.mainScrollView.isShowingTitleLabel) {
            title = @"";
        } else {
            if ([delegate respondsToSelector:@selector(documentPicker:toolbarPromptForRenamingItem:)])
                title = [delegate documentPicker:_documentPicker toolbarPromptForRenamingItem:item];
            if (!title) {
                if (item.type == ODSItemTypeFolder)
                    title = NSLocalizedStringFromTableInBundle(@"Rename Folder", @"OmniUIDocument", OMNI_BUNDLE, @"toolbar prompt while renaming a folder");
                else
                    title = NSLocalizedStringFromTableInBundle(@"Rename Document", @"OmniUIDocument", OMNI_BUNDLE, @"toolbar prompt while renaming a document");
            }
        }
        _normalTitleView.hideSyncButton = YES;
        self.displayedTitleString = title;
        [navigationItem setRightBarButtonItems:@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancelRenaming:)]] animated:animated];
        [navigationItem setHidesBackButton:YES animated:animated];
        [navigationItem setLeftBarButtonItems:nil animated:animated];

        // The shield view protects us from events, so no need to disable interaction or become disabled. But, we should look disabled.
        _topControls.tintAdjustmentMode = UIViewTintAdjustmentModeDimmed;
        
        return;
    } else {
        [navigationItem setHidesBackButton:NO animated:animated];
        _topControls.tintAdjustmentMode = UIViewTintAdjustmentModeAutomatic;
        _normalTitleView.hideSyncButton = NO;
    }
    
    if (editing) {
        if (!_exportBarButtonItem) {
            // We keep pointers to a few toolbar items that we need to update enabledness on.
            _exportBarButtonItem = [_exporter barButtonItem];
            
            _moveBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIMenuItemFolder" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(move:)];
            _moveBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Move", @"OmniUIDocument", OMNI_BUNDLE, @"Move toolbar item accessibility label.");

            _duplicateDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentDuplicate" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] style:UIBarButtonItemStylePlain target:self action:@selector(duplicateDocument:)];
            _duplicateDocumentBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Duplicate", @"OmniUIDocument", OMNI_BUNDLE, @"Duplicate toolbar item accessibility label.");
        }
        
        // Delete Item
        
        [leftItems addObject:_exportBarButtonItem];
        if (!self.selectedScope.isExternal)
            [leftItems addObject:_moveBarButtonItem];
        if (!self.selectedScope.isTrash && self.selectedScope.canRenameDocuments) {
            [leftItems addObject:_duplicateDocumentBarButtonItem];
        }
        [leftItems addObject:[self deleteBarButtonItem]];
        navigationItem.leftItemsSupplementBackButton = NO;
    } else {
        [self updateTitle];
        // if we're displaying the title in the scrollview, we shouldn't use the titleview to show our sync button. instead, we add it to the right bar button items below.
        
        BOOL shouldHideNavItemTitleAndSyncButton = (traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);
        _normalTitleView.hideTitle = shouldHideNavItemTitleAndSyncButton;
        _normalTitleView.hideSyncButton = shouldHideNavItemTitleAndSyncButton;
    }
    [navigationItem setLeftBarButtonItems:leftItems animated:animated];

    //calculate right bar button items
    NSMutableArray *rightItems = [NSMutableArray array];
    if (editing) {
        NSSet *selectedItems = self.selectedItems;
        NSUInteger selectedItemCount = [selectedItems count];
        
        NSString *format = nil;
        {
            BOOL hasFolder = [selectedItems any:^BOOL(ODSItem *item) {
                return item.type == ODSItemTypeFolder;
            }] != nil;
            
            if (hasFolder) {
                if (selectedItemCount == 1)
                    format = NSLocalizedStringFromTableInBundle(@"1 Item Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a single selected folder.");
                else
                    format = NSLocalizedStringFromTableInBundle(@"%ld Items Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a multiple selected items.");
            } else {
                id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
                if ([delegate respondsToSelector:@selector(documentPickerMainToolbarSelectionFormatForFileItems:)])
                    format = [delegate documentPickerMainToolbarSelectionFormatForFileItems:selectedItems];
                
                if (OFIsEmptyString(format)) {
                    if (selectedItemCount == 0)
                        format = NSLocalizedStringFromTableInBundle(@"Select a Document", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a no selected documents.");
                    else if (selectedItemCount == 1)
                        format = NSLocalizedStringFromTableInBundle(@"1 Document Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a single selected document.");
                    else
                        format = NSLocalizedStringFromTableInBundle(@"%ld Documents Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a multiple selected documents.");
                }
            }
        }
        
        _normalTitleView.hideSyncButton = YES;
        self.displayedTitleString = [NSString stringWithFormat:format, [selectedItems count]];
        

        [rightItems addObject:self.editButtonItem]; // Done
    } else {
        // Items in the right bar items array are positioned right to left.
        
        UIBarButtonItem *editButtonItem = self.editButtonItem;
        editButtonItem.title = NSLocalizedStringFromTableInBundle(@"Select", @"OmniUIDocument", OMNI_BUNDLE, @"edit button title for doc picker in non-edit mode");
        [rightItems addObject:self.editButtonItem];
        [rightItems addObject: [self appMenuBarButtonItem]];
        
        if ((_documentStore.documentTypeForNewFiles != nil) && !self.selectedScope.isTrash && [_documentStore.scopes containsObjectIdenticalTo:_documentScope]) {
            if (self.selectedScope.isExternal) {
                UIImage *addImage = [UIImage imageNamed:@"OUIToolbarAddDocument" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
                OUIBarButtonItem *linkItem = [[OUIBarButtonItem alloc] initWithImage:addImage style:UIBarButtonItemStylePlain target:[OUIDocumentAppController controller] action:@selector(linkDocumentFromExternalContainer:)];
                linkItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Link External Document", @"OmniUIDocument", OMNI_BUNDLE, @"Link External Document toolbar item accessibility label.");
                [rightItems addObject:linkItem];
            } else {
                if (!self.addDocumentButtonItem) {
                    UIImage *addImage = [UIImage imageNamed:@"OUIToolbarAddDocument" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
                    self.addDocumentButtonItem = [[OUIBarButtonItem alloc] initWithImage:addImage style:UIBarButtonItemStylePlain target:self action:@selector(newDocument:)];
                    self.addDocumentButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"New Document", @"OmniUIDocument", OMNI_BUNDLE, @"New Document toolbar item accessibility label.");
                }
                [rightItems addObject:self.addDocumentButtonItem];
            }

            if ((traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) && _normalTitleView.syncAccountActivity != nil) { // checks to see if we're compact
                [rightItems addObject:_normalTitleView.syncBarButtonItem];
                _normalTitleView.hideSyncButton = YES;
            }
            else {
                _normalTitleView.hideSyncButton = NO;
            }
        }
    }

    if (![rightItems isEqualToArray:navigationItem.rightBarButtonItems]) {
        [navigationItem setRightBarButtonItems:rightItems animated:animated];
    }
    
    // Tint Color - OmniBlueColor when edting, otherwize nil and let the system pull from superviews.
    UIColor *editingColor = [OAAppearanceDefaultColors appearance].omniBlueColor;
    self.editButtonItem.tintColor = (editing) ? editingColor : nil;
    for (UIBarButtonItem *button in self.navigationItem.leftBarButtonItems) {
        button.tintColor = (editing) ? editingColor : nil;
    }
    
    [self _updateToolbarItemsEnabledness];
}

- (void)_updateToolbarItemsEnabledness;
{
    if (self.isEditing) {
        NSUInteger count = self.selectedItemCount;
        if (count == 0) {
            _exportBarButtonItem.enabled = NO;
            _moveBarButtonItem.enabled = NO;
            _duplicateDocumentBarButtonItem.enabled = NO;
            [self deleteBarButtonItem].enabled = NO;
        } else {
            BOOL isViewingTrash = self.selectedScope.isTrash;
            
            BOOL canMove;
            if (isViewingTrash)
                canMove = YES; // Restore from trash
            else if ([_documentStore.scopes count] > 2)
                canMove = YES; // Move between scopes
            else if (count >= 1 && !isViewingTrash)
                canMove = YES; // Make new folder
            else
                canMove = NO;

            // Exporting more than one thing is really fine, except when sending OmniPlan files via Mail. But we don't have a good way to restrict just that. bug:///147627
            _exportBarButtonItem.enabled = (!isViewingTrash && count == 1);

            _moveBarButtonItem.enabled = canMove;
            _duplicateDocumentBarButtonItem.enabled = YES;
            [self deleteBarButtonItem].enabled = YES; // Deletion while in the trash is just an immediate removal.
        }
    }
    
    // Disable adding new documents if we are not licensed
    self.addDocumentButtonItem.enabled = [[OUIAppController sharedController] canCreateNewDocument];
}

- (void)_ensureLegibilityOfSegmentedControl:(UISegmentedControl*)control{
    // compenstate for the fact that controls will be tinted grey instead of white if Darken Colors accessbility setting is on (which actually reduces contrast in this case rather than increasing it)
    if (UIAccessibilityDarkerSystemColorsEnabled()) {
        [control setTitleTextAttributes:@{NSForegroundColorAttributeName : [UIColor blackColor]} forState:UIControlStateSelected];
        [control setTitleTextAttributes:@{NSForegroundColorAttributeName : [UIColor blackColor]} forState:UIControlStateNormal];
    } else {
        [control setTitleTextAttributes:nil forState:UIControlStateSelected];
        [control setTitleTextAttributes:nil forState:UIControlStateNormal];
    }
}

#define TOP_CONTROLS_TOP_MARGIN 28.0
#define TOP_CONTROLS_SPACING 20.0
#define TOP_CONTROLS_VERTICAL_SPACING 16.0

- (void)setupTopControls;
{
    NSArray *availableFilters = [self availableFilters];
    BOOL willDisplayFilter = ([availableFilters count] > 1);

    CGRect topRect = CGRectZero;
    if (_topControls) {
        [_topControls removeFromSuperview];
        _topControls = nil;
    }
    _topControls = [[UIView alloc] initWithFrame:topRect];

    // Sort
    if ([self supportsUpdatingSorting]) {
        // Make sure to keep these in sync with the OUIDocumentPickerItemSort enum.
        NSArray *sortTitles = @[
                                NSLocalizedStringFromTableInBundle(@"Date", @"OmniUIDocument", OMNI_BUNDLE, @"sort by date"),
                                NSLocalizedStringFromTableInBundle(@"Title", @"OmniUIDocument", OMNI_BUNDLE, @"sort by title")
                                ];
        UISegmentedControl *sortSegmentedControl = [[UISegmentedControl alloc] initWithItems:sortTitles];
        [sortSegmentedControl addTarget:self action:@selector(sortSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        sortSegmentedControl.selectedSegmentIndex = [[[self class] sortPreference] enumeratedValue];
        
        NSString *sortByAXLabel = NSLocalizedStringFromTableInBundle(@"Sort by %@", @"OmniUIDocument", OMNI_BUNDLE, @"sort by accessibility label");
        for (UIView *segment in sortSegmentedControl.accessibilityElements) {
            segment.accessibilityLabel = [NSString stringWithFormat:sortByAXLabel, segment.accessibilityLabel];
        }
        
        [sortSegmentedControl sizeToFit];
        [_topControls addSubview:sortSegmentedControl];
        self.sortSegmentedControl = sortSegmentedControl;
    }
    
    // Filter
    if (willDisplayFilter) {
        NSString *identifier = [[[self class] filterPreference] stringValue];
        NSUInteger selectedIndex = [availableFilters indexOfObjectPassingTest:^BOOL(OUIDocumentPickerFilter *filter, NSUInteger idx, BOOL *stop) {
            return [filter.identifier isEqualToString:identifier];
        }];
        
        NSArray *filterTitles = [availableFilters arrayByPerformingBlock:^(OUIDocumentPickerFilter *filter) {
            return filter.localizedFilterChooserButtonLabel;
        }];
        
        self.filtersSegmentedControl = [[UISegmentedControl alloc] initWithItems:filterTitles];
        [self.filtersSegmentedControl addTarget:self action:@selector(filterSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        self.filtersSegmentedControl.selectedSegmentIndex = selectedIndex;

        // fix up the segment accessibility label to use the full title "Show foo" instead of the short title.
        for (UIView *segment in self.filtersSegmentedControl.accessibilityElements) {
            segment.accessibilityLabel = segment.accessibilityLabel;
        }
        
        [self.filtersSegmentedControl sizeToFit];
        [_topControls addSubview:self.filtersSegmentedControl];
    }
    
    [self adjustTopControlsForTraitCollection:self.traitCollection];
    
    // Search
    if (/* DISABLES CODE */ (0))
    {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setTitle:NSLocalizedStringFromTableInBundle(@"Search", @"OmniUIDocument", OMNI_BUNDLE, @"document picker button label") forState:UIControlStateNormal];
        [button addTarget:self action:@selector(search:) forControlEvents:UIControlEventTouchUpInside];
        [button sizeToFit];
        CGRect controlFrame = button.frame;
        
        controlFrame.origin = CGPointMake(CGRectGetMaxX(topRect)+TOP_CONTROLS_SPACING, TOP_CONTROLS_TOP_MARGIN + (CGRectGetHeight(topRect) -CGRectGetHeight(controlFrame))/2.0);
        topRect.size.width = CGRectGetMaxX(controlFrame);
        button.frame = controlFrame;
        [_topControls addSubview:button];
    }

    _topControls.tintColor = [[OmniUIDocumentAppearance appearance] documentPickerTintColorAgainstBackground];

    // workaround for the fact that if you don't explicitly set the tint color on all the subviews, then when we go to animate back to the doc picker, in some situations it will manually set the tint on all subviews that dont' have one, even if their superview has an explicitly set tint, and suddenly we have the app's tint-color, not the one we intend! Cascade-fail!
    // <bug:///109927> (Bug: Doc picker filter controls are tint color after screen dims on a document [orange, green])
    [_topControls applyToViewTree:^OUIViewVisitorResult(UIView *view) {
        view.tintColor = [[OmniUIDocumentAppearance appearance] documentPickerTintColorAgainstBackground];
        return OUIViewVisitorResultContinue;
    }];

    [_mainScrollView addSubview:_topControls];
    _mainScrollView.topControls = _topControls;
    
    [self _updateToolbarItemsEnabledness];
}

#pragma mark Adaptability

- (void)_setupTitleLabelToUseInCompactWidth;
{
    _titleLabelToUseInCompactWidth = [[UILabel alloc] initWithFrame:CGRectZero];
    
    UIFont *titleFont = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    NSString *title = OBUnlocalized(@"Title"); // Configured later -- possibly remove this...
    _titleLabelToUseInCompactWidth.font = titleFont;
    _titleLabelToUseInCompactWidth.textColor = [[OmniUIDocumentAppearance appearance] documentPickerTintColorAgainstBackground];
    _titleLabelToUseInCompactWidth.textAlignment = NSTextAlignmentCenter;
    _titleLabelToUseInCompactWidth.contentMode = UIViewContentModeBottom;
    _titleLabelToUseInCompactWidth.text = title;
    _mainScrollView.titleViewForCompactWidth = _titleLabelToUseInCompactWidth;
    _mainScrollView.titleViewForCompactWidth.accessibilityTraits |= UIAccessibilityTraitHeader;
    NSString *axHint =  NSLocalizedStringFromTableInBundle(@"Scroll down to show sort and filter controls", @"OmniUIDocument", OMNI_BUNDLE, @"document picker compact title view accessibility hint");
    _mainScrollView.titleViewForCompactWidth.accessibilityHint = axHint;
}

- (void)willTransitionToTraitCollection:(UITraitCollection *)newCollection withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
{
    [super willTransitionToTraitCollection:newCollection withTransitionCoordinator:coordinator];
    
    _freezeTopControlAlpha = YES;
    
    // This is a stop-gap until we implement true adaptability. For now, dismiss any presented view controller if they are presented as a popover
    if (self.presentedViewController.popoverPresentationController != nil) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:^{
            [self setEditing:NO animated:YES];
        }];
    }
    
    self.wasShowingTopControlsBeforeTransition = [self _isShowingTopControls];
    self.isTransitioningTraitCollection = YES;
    [self adjustTopControlsForTraitCollection:newCollection];
    
    [self.mainScrollView setNeedsLayout];
    [self.mainScrollView layoutIfNeeded];
    
    [self _updateToolbarItemsForTraitCollection:newCollection animated:YES];
    
    [coordinator animateAlongsideTransition:nil
                                 completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                                     CGFloat adjustedOffsetY = [self contentOffsetYAfterAdjustingInsetToShowTopControls:self.wasShowingTopControlsBeforeTransition];
                                     [self.mainScrollView setContentOffset:CGPointMake(self.mainScrollView.contentOffset.x, adjustedOffsetY) animated:NO];
                                     _freezeTopControlAlpha = NO;
                                     self.isTransitioningTraitCollection = NO;
                                 }];
}

-(void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    if (_renameSession) {
        [_renameSession endRenaming];
    }
    
    if (!self.isTransitioningTraitCollection) {
        self.wasShowingTopControlsBeforeTransition = [self _isShowingTopControls];
    }
    
    if (self.view.window) {
        [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            _freezeTopControlAlpha = YES;
            CGFloat adjustedOffsetY = [self contentOffsetYAfterAdjustingInsetToShowTopControls:self.wasShowingTopControlsBeforeTransition];
            [self.mainScrollView setContentOffset:CGPointMake(self.mainScrollView.contentOffset.x, adjustedOffsetY) animated:NO];
        } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            _freezeTopControlAlpha = NO;
            [self scrollViewDidScroll:self.mainScrollView];
            
            if (_documentScope.isTrash && self.restoreToMenuController == self.presentedViewController) {
                // Move popover to new frame of selected item. (While in trash, we only support single selection.)
                ODSItem *firstSelected = nil;
                for (ODSItem *item in self.mainScrollView.items) {
                    if (item.selected) {
                        firstSelected = item;
                        break;
                    }
                }
                
                UIView *view = [self.mainScrollView itemViewForItem:firstSelected];
                self.restoreToMenuController.popoverPresentationController.sourceView = view;
                self.restoreToMenuController.popoverPresentationController.sourceRect = view.bounds;
            }
        }];
    } else {
        _needsDelayedHandleResize = YES;
    }
}

- (BOOL)_isShowingTopControls;
{
    return self.mainScrollView.contentOffset.y < [self.mainScrollView contentOffsetYToHideTopControls];
}

- (CGFloat)contentOffsetYAfterAdjustingInsetToShowTopControls:(BOOL)showTopControls;
{
    [self _checkTitleDisplay];
    UIEdgeInsets existingInset = self.mainScrollView.contentInset;
    CGFloat existingOffsetY = self.mainScrollView.contentOffset.y;
    // set the new top inset first (because that affects the calculation of the bottom inset and the needed offset if the height of the nav bar is changing)
    UIEdgeInsets adjustedInset = existingInset;
    adjustedInset.top = CGRectGetMaxY(self.navigationController.navigationBar.frame);
    self.mainScrollView.contentInset = adjustedInset;
    adjustedInset.bottom = [self _bottomContentInsetNecessaryToAllowContentOffsetY:[self.mainScrollView contentOffsetYToHideTopControls]];
    self.mainScrollView.contentInset = adjustedInset;
    CGFloat topDiff = existingInset.top - adjustedInset.top;
    CGFloat adjustedOffsetY = existingOffsetY + topDiff;
    
    OFExtent contentOffsetYExtent = OFExtentMake(-self.mainScrollView.contentInset.top, MAX(0, self.mainScrollView.contentSize.height - self.mainScrollView.bounds.size.height + self.mainScrollView.contentInset.top + self.mainScrollView.contentInset.bottom));
    adjustedOffsetY = OFExtentClampValue(contentOffsetYExtent, adjustedOffsetY);
    
    if (!showTopControls) {
        if (adjustedOffsetY < [self.mainScrollView contentOffsetYToHideCompactTitleBehindNavBar]) {
            adjustedOffsetY = [self.mainScrollView contentOffsetYToHideTopControls];
        }
    } else {
        if (adjustedOffsetY > [self.mainScrollView contentOffsetYToShowTopControls]) {
            adjustedOffsetY = [self.mainScrollView contentOffsetYToShowTopControls];
        }
    }
    return adjustedOffsetY;
}

- (void)adjustTopControlsForTraitCollection:(UITraitCollection *)traitCollection;
{
    CGRect topRect = CGRectZero;
    
    NSArray *availableFilters = [self availableFilters];
    BOOL willDisplayFilter = ([availableFilters count] > 1);
    NSArray *filterTitles;
    
    NSMutableArray *verticalConstraints = [NSMutableArray array];
    NSMutableArray *horizontalConstraints = [NSMutableArray array];
    
    NSDictionary *metricsDict = @{ @"topMargin" : [NSNumber numberWithCGFloat:TOP_CONTROLS_TOP_MARGIN],
                                   @"verticalSpacing" : [NSNumber numberWithCGFloat:TOP_CONTROLS_VERTICAL_SPACING],
                                   @"horizontalSpacing" : [NSNumber numberWithCGFloat:TOP_CONTROLS_SPACING] };
    
    NSDictionary *viewsDict = [NSMutableDictionary dictionary];
    if (self.sortSegmentedControl) {
        [viewsDict setValue:self.sortSegmentedControl forKey:@"sort"];
    }
    if (self.filtersSegmentedControl) {
        [viewsDict setValue:self.filtersSegmentedControl forKey:@"filters"];
    }
                                 
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if (traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact || ([delegate respondsToSelector:@selector(documentPickerShouldAlwaysStackFilterControls)] && [delegate documentPickerShouldAlwaysStackFilterControls])) {
        // use short labels for the filters control
        filterTitles = [availableFilters arrayByPerformingBlock:^(OUIDocumentPickerFilter *filter) {
            return filter.localizedFilterChooserShortButtonLabel;
        }];
        for (NSUInteger i = 0; i < filterTitles.count; i++) {
            NSString *title = filterTitles[i];
            // it is possible to add filters when pro becomes unlocked, so need to handle additions
            if (self.filtersSegmentedControl.numberOfSegments <= i)
                [self.filtersSegmentedControl insertSegmentWithTitle:title atIndex:i animated:NO];
            else
                [self.filtersSegmentedControl setTitle:title forSegmentAtIndex:i];
        }
        [self.filtersSegmentedControl sizeToFit];
        
        // constraints
        if (self.sortSegmentedControl && willDisplayFilter) {
            [verticalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-topMargin-[sort]-verticalSpacing-[filters]|"
                                                                                             options:kNilOptions
                                                                                             metrics:metricsDict
                                                                                               views:viewsDict]];
            [horizontalConstraints addObject:[NSLayoutConstraint constraintWithItem:self.sortSegmentedControl
                                                                          attribute:NSLayoutAttributeCenterX
                                                                          relatedBy:NSLayoutRelationEqual
                                                                             toItem:self.filtersSegmentedControl
                                                                          attribute:NSLayoutAttributeCenterX
                                                                         multiplier:1.f constant:0.f]];
            [horizontalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[filters]|"
                                                                                               options:kNilOptions
                                                                                               metrics:nil
                                                                                                 views:viewsDict]];
            topRect.size.width = fmax(self.sortSegmentedControl.frame.size.width, self.filtersSegmentedControl.frame.size.width);
        } else {
            if (self.sortSegmentedControl) {
                [verticalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-topMargin-[sort]|"
                                                                                                 options:kNilOptions
                                                                                                 metrics:metricsDict
                                                                                                   views:viewsDict]];
                [horizontalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[sort]-0-|"
                                                                                                   options:kNilOptions
                                                                                                   metrics:nil
                                                                                                views:viewsDict]];
                topRect.size.width = self.sortSegmentedControl.frame.size.width;
            }
            if (self.filtersSegmentedControl && willDisplayFilter) {
                [verticalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-topMargin-[filters]|"
                                                                                                 options:kNilOptions
                                                                                                 metrics:metricsDict
                                                                                                   views:viewsDict]];
                [horizontalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[filters]-0-|"
                                                                                                   options:kNilOptions
                                                                                                   metrics:nil
                                                                                                     views:viewsDict]];
                topRect.size.width = self.filtersSegmentedControl.frame.size.width;
            }
        }
    } else {
        // use regular labels for the filters control
        filterTitles = [availableFilters arrayByPerformingBlock:^(OUIDocumentPickerFilter *filter) {
            return filter.localizedFilterChooserButtonLabel;
        }];
        for (NSUInteger i = 0; i < filterTitles.count; i++) {
            NSString *title = filterTitles[i];
            // it is possible to add filters when pro becomes unlocked, so need to handle additions
            if (self.filtersSegmentedControl.numberOfSegments <= i)
                [self.filtersSegmentedControl insertSegmentWithTitle:title atIndex:i animated:NO];
            else
                [self.filtersSegmentedControl setTitle:title forSegmentAtIndex:i];
        }
        [self.filtersSegmentedControl sizeToFit];
        
        // constraints
        if (self.sortSegmentedControl && willDisplayFilter) {
            [verticalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-topMargin-[sort]-0@990-|"
                                                                                             options:kNilOptions
                                                                                             metrics:metricsDict
                                                                                               views:viewsDict]];
            [verticalConstraints addObject:[NSLayoutConstraint constraintWithItem:self.sortSegmentedControl
                                                                       attribute:NSLayoutAttributeCenterY
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:self.filtersSegmentedControl
                                                                       attribute:NSLayoutAttributeCenterY
                                                                      multiplier:1.0f
                                                                        constant:0.0f]];
            [verticalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[filters]-0@990-|"
                                                                                             options:kNilOptions
                                                                                             metrics:metricsDict
                                                                                               views:viewsDict]];
            [horizontalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[sort]-horizontalSpacing-[filters]|"
                                                                                               options:kNilOptions
                                                                                               metrics:metricsDict
                                                                                                 views:viewsDict]];
            topRect.size.width = self.sortSegmentedControl.frame.size.width + TOP_CONTROLS_SPACING + self.filtersSegmentedControl.frame.size.width;
        } else {
            if (self.sortSegmentedControl) {
                [verticalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-topMargin-[sort]|"
                                                                                                 options:kNilOptions
                                                                                                 metrics:metricsDict
                                                                                                   views:viewsDict]];
                [horizontalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[sort]|"
                                                                                                   options:kNilOptions
                                                                                                   metrics:metricsDict
                                                                                                     views:viewsDict]];
                topRect.size.width = self.sortSegmentedControl.frame.size.width;
            }
            if (self.filtersSegmentedControl && willDisplayFilter) {
                [verticalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-topMargin-[filters]|"
                                                                                                 options:kNilOptions
                                                                                                 metrics:metricsDict
                                                                                                   views:viewsDict]];
                [horizontalConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[filters]|"
                                                                                                   options:kNilOptions
                                                                                                   metrics:metricsDict
                                                                                                     views:viewsDict]];
                topRect.size.width = self.filtersSegmentedControl.frame.size.width;
            }
        }
    }
    
    // add constraints
    for (UIView *subview in _topControls.subviews){
        subview.translatesAutoresizingMaskIntoConstraints = NO;
    }
    [_topControls removeConstraints:_topControls.constraints];
    
    [_topControls addConstraints:verticalConstraints];
    [_topControls addConstraints:horizontalConstraints];
    
    topRect.size.height = [_topControls systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    _topControls.frame = CGRectIntegral(topRect);
}

- (void)setDisplayedTitleString:(NSString *)displayedTitleString;
{
    if (displayedTitleString != _displayedTitleString) {
        _displayedTitleString = displayedTitleString;
    }
    [self _checkTitleDisplay];
}

- (void)_checkTitleDisplay;
{
    _titleLabelToUseInCompactWidth.text = self.displayedTitleString;
    _normalTitleView.title = self.displayedTitleString;

    // get VO to read a hint for the navigationItem's titleView
    _normalTitleView.isAccessibilityElement = YES;
    _normalTitleView.accessibilityLabel = self.displayedTitleString;
    _normalTitleView.accessibilityHint = NSLocalizedStringFromTableInBundle(@"Scroll down to show sort and filter controls", @"OmniUIDocument", OMNI_BUNDLE, @"document picker compact title view accessibility hint");
    
    [_titleLabelToUseInCompactWidth sizeToFit];
    [_mainScrollView setNeedsLayout];
}

#pragma mark - 

- (void)_deleteWithoutConfirmation:(NSSet *)selectedItems;
{
    BOOL controlsWereHiddenBeforeDeletion = self.mainScrollView.contentOffset.y >= self.mainScrollView.contentOffsetYToHideTopControls;
    
    OBPRECONDITION([NSThread isMainThread]);
 
    [self.activityIndicator startAnimating];
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

    [_documentScope deleteItems:selectedItems completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
        OBASSERT([NSThread isMainThread]); // errors array
        
        for (NSError *error in errorsOrNil)
            OUI_PRESENT_ERROR_FROM(error, self);
        
        [self _explicitlyRemoveItems:selectedItems];
        [lock unlock];
        [self clearSelection:YES];
        [self _alterBottomContentInsetIfNecessaryToAllowContentOffsetY:self.mainScrollView.contentOffsetYToHideTopControls];  // make sure we CAN hide the controls
        if (controlsWereHiddenBeforeDeletion && self.mainScrollView.contentOffset.y < self.mainScrollView.contentOffsetYToHideTopControls) {
            self.mainScrollView.contentOffset = CGPointMake(self.mainScrollView.contentOffset.x, self.mainScrollView.contentOffsetYToHideTopControls);
        }
        [self.activityIndicator stopAnimating];
    }];
}

- (void)_updateFieldsForSelectedFileItem;
{
    OBFinishPortingLater("<bug:///147828> (iOS-OmniOutliner Bug: OUIDocumentPickerViewController.m: 2919 - Update the enabledness of the export/delete bar button items based on how many file items are selected)");
#if 0
    _exportBarButtonItem.enabled = (proxy != nil);
    [self deleteBarButtonItem].enabled = (proxy != nil);
#endif
}

- (void)_applicationDidEnterBackground:(NSNotification *)note;
{
    OBPRECONDITION(self.visibility == OUIViewControllerVisibilityVisible); // We only subscribe when we are visible
    
    // Only disable editing if we are not currently presenting a modal view controller.
    // Note; needlessly setting editing=NO here when we aren't editing causes view layout invalidation while going into the background. This in turn can cause the document picker to show blank previews (since we'd look up previews while the cache had been flushed).
    if (self.editing && !self.presentedViewController) {
        [self setEditing:NO];
    }
}

 - (void)_keyboardHeightWillChange:(NSNotification *)note;
{
    OUIKeyboardNotifier *notifier = [OUIKeyboardNotifier sharedNotifier];
    
    if (_renameSession && notifier.lastKnownKeyboardHeight > 0) {
        [_mainScrollView scrollRectToVisibleAboveLastKnownKeyboard:_renameSession.itemView.frame animated:YES completion:nil];
    }else{
        [_mainScrollView adjustForKeyboardHidingWithPreferedFinalBottomContentInset:[self _bottomContentInsetNecessaryToAllowContentOffsetY:[_mainScrollView contentOffsetYToHideTopControls]] animated:YES];
    }
}
     
- (void)_previewsUpdateForFileItemNotification:(NSNotification *)note;
{
    ODSFileItem *fileItem = [note object];

    [_mainScrollView previewsUpdatedForFileItem:fileItem];
}

- (void)_startedRenamingInItemView:(OUIDocumentPickerItemView *)itemView;
{
    if (self.renameSession) {
        return;  // because this will get called on any size change
    }
    // Higher level code should have already checked this.
    OBPRECONDITION(_renameSession == nil);
    OBPRECONDITION(itemView);

    self.renameSession = [[OUIDocumentRenameSession alloc] initWithDocumentPicker:self itemView:itemView];
    
    [self _updateToolbarItemsForTraitCollection:self.traitCollection animated:YES];
    _topControls.userInteractionEnabled = NO;
    _mainScrollView.scrollEnabled = NO;
}

- (void)_cancelRenaming:(id)sender;
{
    [_renameSession cancelRenaming];
    self.renameSession = nil;
    
    [self _updateToolbarItemsForTraitCollection:self.traitCollection animated:YES];
    _topControls.userInteractionEnabled = YES;
    _mainScrollView.scrollEnabled = YES;
}

// Called by OUIDocumentRenameSession
- (void)_didPerformRenameToFileURL:(NSURL *)destinationURL;
{
    OBPRECONDITION(_renameSession);

    // We expect the file item to have been notified of its new URL already.
    ODSFileItem *fileItem = [_documentStore fileItemWithURL:destinationURL];
    OBASSERT(fileItem);
    //NSLog(@"fileItem %@", fileItem);
    
    OUIDocumentPickerScrollView *scrollView = self.mainScrollView;
    
    //NSLog(@"sort items");
    [scrollView sortItems];
    [scrollView scrollItemToVisible:fileItem animated:NO];
}

- (void)_moveItems:(NSSet *)items toFolder:(ODSFolderItem *)parentFolder;
{
    OBPRECONDITION(parentFolder);
    
    [self.activityIndicator startAnimating];
    [self _beginIgnoringDocumentsDirectoryUpdates];
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    [_documentStore moveItems:items fromScope:_documentScope toScope:parentFolder.scope inFolder:parentFolder completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil){
        [self _explicitlyRemoveItems:movedFileItems];
        [self _endIgnoringDocumentsDirectoryUpdates];
        [self _performDelayedItemPropagationWithCompletionHandler:^{
            [lock unlock];
            [self clearSelection:YES];
            
            [self.activityIndicator stopAnimating];
            
            for (NSError *error in errorsOrNil)
                OUI_PRESENT_ALERT_FROM(error, self);
        }];
    }];
}

- (void)_moveSelectedDocumentsToFolder:(ODSFolderItem *)folder;
{
    [self _moveItems:self.selectedItems toFolder:folder];
}

- (void)_makeFolderFromSelectedDocuments;
{
    NSSet *items = self.selectedItems;
    
    [self.activityIndicator startAnimating];
    
    [self _beginIgnoringDocumentsDirectoryUpdates];
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    [_documentStore makeFolderFromItems:items inParentFolder:_folderItem ofScope:_documentScope completionHandler:^(ODSFolderItem *createdFolder, NSArray *errorsOrNil){
        [self clearSelection:YES];
        [self _endIgnoringDocumentsDirectoryUpdates];
        [self _performDelayedItemPropagationWithCompletionHandler:^{
            if (createdFolder == nil) {
                [lock unlock];
                for (NSError *error in errorsOrNil)
                    OUI_PRESENT_ALERT_FROM(error, self);
                [self.activityIndicator stopAnimating];
                return;
            }
            
            [self scrollItemsToVisible:@[createdFolder] animated:YES completion:^{
                [lock unlock];
                
                OUIDocumentPickerItemView *itemView = [_mainScrollView itemViewForItem:createdFolder];
                OBASSERT(itemView, "<bug:///93404> (Not automatically put into rename mode for new folders created off the currently visible page of documents) -- Without an item view, we can't start renaming.");
                [itemView startRenaming];
                
                // In case only a portion of the moves worked
                for (NSError *error in errorsOrNil)
                    OUI_PRESENT_ALERT_FROM(error, self);
                
                [self.activityIndicator stopAnimating];
            }];
        }];
    }];
}

- (void)_revealAndActivateNewDocumentFileItem:(ODSFileItem *)createdFileItem fileItemToRevealFrom:(ODSFileItem *)fileItemToRevealFrom completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(createdFileItem);

    NSArray *viewControllers = [_documentPicker.navigationController viewControllers];
    for (id viewController in viewControllers) {
        if ([viewController isKindOfClass:[OUIDocumentPickerViewController class]])
            [viewController ensureSelectedFilterMatchesFileItem:createdFileItem];
    }

    [self scrollItemToVisible:fileItemToRevealFrom animated:YES];

    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:openCreatedFileItem:fileItemToRevealFrom:)])
        [delegate documentPicker:_documentPicker openCreatedFileItem:createdFileItem fileItemToRevealFrom:fileItemToRevealFrom];

    if (completionHandler)
        completionHandler();
}

- (void)_revealAndActivateNewDocumentFileItem:(ODSFileItem *)createdFileItem completionHandler:(void (^)(void))completionHandler;
{
    [self _revealAndActivateNewDocumentFileItem:createdFileItem fileItemToRevealFrom:createdFileItem completionHandler:completionHandler];
}

- (void)_applicationWillOpenDocument;
{
    [_renameSession cancelRenaming];
}

- (void)_beginIgnoringDocumentsDirectoryUpdates;
{
    OBPRECONDITION([NSThread isMainThread]);
    _ignoreDocumentsDirectoryUpdates++;
}

- (void)_endIgnoringDocumentsDirectoryUpdates;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_ignoreDocumentsDirectoryUpdates > 0);
    
    if (_ignoreDocumentsDirectoryUpdates > 0)
        _ignoreDocumentsDirectoryUpdates--;
}

- (OUIEmptyOverlayView *)emptyOverlayView;
{
    ODSScope *scope = self.selectedScope;
    
    if (scope.isTrash)
        return nil; // Empty trash is just fine
    
    if (_filteredItems.count > 0)
        return nil; // Not empty
    
    if (!_emptyOverlayView) {
        _emptyOverlayView = [self newEmptyOverlayView];
    }
    return _emptyOverlayView;
}

- (OUIEmptyOverlayView *)newEmptyOverlayView;
{
    OUIEmptyOverlayView *newEmptyOverlayView = nil;
    
    if (![_documentStore.scopes containsObjectIdenticalTo:_documentScope]) {
        NSString *message = NSLocalizedStringFromTableInBundle(@"This Cloud Account no longer exists.", @"OmniUIDocument", OMNI_BUNDLE, @"empty picker because of removed account text");
        newEmptyOverlayView = [OUIEmptyOverlayView overlayViewWithMessage:message buttonTitle:nil customFontColor:[[OUIDocumentAppController controller] emptyOverlayViewTextColor] action:nil];
    } else if (!_emptyOverlayView) {
        NSString *buttonTitle;
        if (_documentScope.isExternal) {
            buttonTitle = NSLocalizedStringFromTableInBundle(@"Tap on the + in the toolbar to add a document stored on iCloud Drive or provided by another app.", @"OmniUIDocument", OMNI_BUNDLE, @"empty picker text for Other Documents");
        } else {
            buttonTitle = NSLocalizedStringFromTableInBundle(@"Tap here, or on the + in the toolbar, to add a document.", @"OmniUIDocument", OMNI_BUNDLE, @"empty picker button text");
        }

        __weak OUIDocumentPickerViewController *weakSelf = self;
        newEmptyOverlayView = [OUIEmptyOverlayView overlayViewWithMessage:nil buttonTitle:buttonTitle customFontColor:[[OUIDocumentAppController controller] emptyOverlayViewTextColor] action:^{
            [weakSelf newDocument:nil];
        }];
    }
    
    return newEmptyOverlayView;
}

- (void)_updateEmptyViewControlVisibility;
{
    if (!self.viewIfLoaded.window) {
        return;  // in this situation, our constraints would be wrong
    }
    OUIEmptyOverlayView *emptyOverlayView = [self emptyOverlayView];
    
    if (!emptyOverlayView) {
        // We shouldn't be displaying one now, let's make sure to remove one if we have one already.
        if (_emptyOverlayView && _emptyOverlayView.superview) {
            _removeEmptyOverlayViewAndConstraints(self);
        }
        
        return;
    }
    
    
    if ((emptyOverlayView == _emptyOverlayView) && _emptyOverlayView.superview) {
        // Already Shown
        return;
    }
    
    if ([UIView areAnimationsEnabled] == NO) {
        // Don't show the empty hints until we can fade them in
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _updateEmptyViewControlVisibility];
        }];
    }
    else {
        _emptyOverlayView.alpha = 0.0;
        _emptyOverlayView.hidden = YES;
        
        _addEmptyOverlayViewAndConstraints(self, emptyOverlayView);
        
        [UIView animateWithDuration:1.0 delay:1.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionOverrideInheritedDuration animations:^{
            _emptyOverlayView.alpha = 1.0;
            _emptyOverlayView.hidden = NO;
        } completion:NULL];
    }
}

static void _addEmptyOverlayViewAndConstraints(OUIDocumentPickerViewController *self, OUIEmptyOverlayView *emptyOverlayView)
{
    OBPRECONDITION(self->_emptyOverlayView == emptyOverlayView);
    OBPRECONDITION(self->_emptyOverlayViewConstraints == nil);
    
    UIView *superview = self.mainScrollView;
    self->_emptyOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    [superview addSubview:emptyOverlayView];
    
    NSMutableArray *constraints = [NSMutableArray new];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:emptyOverlayView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0.0]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:emptyOverlayView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeHeight multiplier:1.0 constant:0.0]];
    [constraints addObject: [NSLayoutConstraint constraintWithItem:emptyOverlayView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeCenterX multiplier:1.0f constant:0.0f]];
    [constraints addObject: [NSLayoutConstraint constraintWithItem:emptyOverlayView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeCenterY multiplier:1.0f constant:0.0f]];
    
    self->_emptyOverlayViewConstraints = constraints;
    
    [superview addConstraints:self->_emptyOverlayViewConstraints];
    [superview setNeedsLayout];
}

static void _removeEmptyOverlayViewAndConstraints(OUIDocumentPickerViewController *self)
{
    OBPRECONDITION(self->_emptyOverlayViewConstraints);
    OBPRECONDITION(self->_emptyOverlayView);
    
    UIView *superview = self->_emptyOverlayView.superview;
    
    [superview removeConstraints:self->_emptyOverlayViewConstraints];
    self->_emptyOverlayViewConstraints = nil;
    
    [self->_emptyOverlayView removeFromSuperview];
    self->_emptyOverlayView = nil;
    
    [superview setNeedsLayout];
}

@synthesize filteredItems = _filteredItems;
- (void)setFilteredItems:(NSSet *)newItems;
{
    OBPRECONDITION(newItems != nil); // Should be the empty set instead, otherwise bindings break

    if (_explicitlyRemovedItems) {
        [_explicitlyRemovedItems intersectSet:newItems]; // take anything missing from newItems out of explicit removals so they don't hang around
        if (_explicitlyRemovedItems.count) {
            NSMutableSet *subtract = [NSMutableSet setWithSet:newItems];
            [subtract minusSet:_explicitlyRemovedItems];
            newItems = subtract;
        } else
            _explicitlyRemovedItems = nil;
    }
    
    if (OFISEQUAL(_filteredItems, newItems))
        return;
    
    NSMutableSet *removedItems = [_filteredItems mutableCopy];
    [removedItems minusSet:newItems];
    for (ODSItem *removedItem in removedItems) {
        if ([removedItem isKindOfClass:[ODSFolderItem class]])
            [self.documentPicker navigateForDeletionOfFolder:(ODSFolderItem *)removedItem animated:YES];
    }

    _filteredItems = [[NSSet alloc] initWithSet:newItems];

    if (_ignoreDocumentsDirectoryUpdates == 0 && self.isViewLoaded) {
        [self _propagateItems:_filteredItems toScrollView:_mainScrollView withCompletionHandler:nil];
        [self _updateToolbarItemsEnabledness];
        [self _updateEmptyViewControlVisibility];
    }
} 

- (void)_explicitlyRemoveItems:(NSSet *)items;
{
    // If we have already heard about the deletion of these items, we're alll set. If not, we remember the items to filter out until the underlying document store framework acknowledges their deletion.
    NSMutableSet *toRemove = [NSMutableSet setWithSet:items];
    [toRemove intersectSet:_filteredItems];
    
    if ([toRemove count] == 0)
        return;
    
    if (!_explicitlyRemovedItems)
        _explicitlyRemovedItems = [[NSMutableSet alloc] init];
    [_explicitlyRemovedItems unionSet:items];
    
    NSMutableSet *subtract = [NSMutableSet setWithSet:_filteredItems];
    [subtract minusSet:_explicitlyRemovedItems];
    _filteredItems = [[NSSet alloc] initWithSet:subtract];

    if (_ignoreDocumentsDirectoryUpdates == 0) {
        [self _propagateItems:_filteredItems toScrollView:_mainScrollView withCompletionHandler:nil];
        [self _updateToolbarItemsEnabledness];
        [self _updateEmptyViewControlVisibility];
    }
}

- (void)_propagateItems:(NSSet *)items toScrollView:(OUIDocumentPickerScrollView *)scrollView withCompletionHandler:(void (^)(void))completionHandler;
{
    NSSet *currentItems = scrollView.items;
    if (OFISEQUAL(items, currentItems)) {
        if (completionHandler)
            completionHandler();
        return;
    }
    
    completionHandler = [completionHandler copy];
    
    // If needed later, we could have a flag that says to bail on propagating and we can accumulate differences between the current state and the view state until some time later.
    BOOL isVisible = (self.visibility == OUIViewControllerVisibilityVisible);
    NSTimeInterval animationInterval = isVisible ? OUIAnimationSequenceDefaultDuration : OUIAnimationSequenceImmediateDuration;
    
    NSMutableSet *toRemove = [currentItems mutableCopy];
    [toRemove minusSet:items];
    
    NSMutableSet *toAdd = [items mutableCopy];
    [toAdd minusSet:currentItems];
    
    // We can get a sequence of add/removes and might still be in the midst of animating them. For example, we might get two back-to-back KVO cycles where one item is removed and one item its added (say, when replacing an existing document with a newly downloaded one). To avoid assertions and animation glitches, we need to be careful to filter out stuff that is already in the process of being added or removed.
    [toRemove minusSet:scrollView.itemsBeingRemoved];
    [toAdd minusSet:scrollView.itemsBeingAdded];

    if ([toRemove count] == 0 && [toAdd count] == 0) {
        // Some changes might have been sent already and still be in flight, but we should have gotten at least one extra change...
        OBASSERT_NOT_REACHED("Probably shouldn't happen -- getting redundant KVO?");
        if (completionHandler)
            completionHandler();
        return;
    }
    
    [OUIAnimationSequence runWithDuration:animationInterval actions:
     ^{
         if ([toRemove count] > 0)
             [scrollView startRemovingItems:toRemove]; // Shrink/fade or whatever
         
         // If you have the Duplicate/Delete confirmation popover up, iWork seems to block incoming edits (presumably by making -relinquishPresentedItemToWriter: not call the writer until after the popover action is done) until the action is performed or cancelled. You can select a couple files, tap duplicate, delete them on another device and they won't go away (and you can actually duplicate them) on the the confirmation-alert-in-progress device until the alert is dismissed. We could probably do the same, but for now just cancelling the confirmation alert seems safer (though this is ugly and and ugly place to do it). On the other hand, the only users likely to try this work in our QA department...
         // Added <bug:///79706> (Add a 'start blocking writers' API to the document store) to consider a real but maybe too scary fix for this.
         for (ODSItem *item in toRemove) {
             if ([item isKindOfClass:[ODSFileItem class]]) {
                 ODSFileItem *fileItem = (ODSFileItem *)item;
                 if (fileItem.selected) {
                     [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
                     break;
                 }
             }
         }
         
         if ([toAdd count] > 0) {
             // Add them and make room in the layout
             [scrollView startAddingItems:toAdd];
         }
         if ([toRemove count] > 0) {
             [scrollView finishRemovingItems:toRemove]; // Actually remove them and release the space taken
         }
         [scrollView sortItems];
         [scrollView layoutIfNeeded];
     },
     ^{
         if ([toAdd count] > 0)
             [scrollView finishAddingItems:toAdd]; // Zoom/fade them into the space made
     },
     completionHandler,
     nil];
}

- (void)_performDelayedItemPropagationWithCompletionHandler:(void (^)(void))completionHandler;
{    
    if (_ignoreDocumentsDirectoryUpdates == 0) {
        [self _updateToolbarItemsEnabledness];
        [self _propagateItems:_filteredItems toScrollView:_mainScrollView withCompletionHandler:completionHandler];
    } else {
        if (completionHandler)
            completionHandler();
    }
}

- (void)_flushAfterDocumentStoreInitializationActions;
{
    if (_documentStore) {
        NSArray *actions = _afterDocumentStoreInitializationActions;
        _afterDocumentStoreInitializationActions = nil; // Don't perform these more than once

        for (void (^action)(OUIDocumentPickerViewController *blockSelf) in actions)
            action(self);
    }
}

- (BOOL)canPerformActions;
{
    // Ugly. This can happen due to UIGestureRecognizer matching and then not immediately firing its action, but rather queuing it in a block. Some *other* event may have fired a non-recognizer action or two recognizers might fire. If one fires and starts doing something async with interaction turned off, bail here.
    if ([[UIApplication sharedApplication] isIgnoringInteractionEvents]) {
        return NO;
    }
    
    return (self.parentViewController != nil); // will still be the inner controller while scrolling to the new doc
}

@end
