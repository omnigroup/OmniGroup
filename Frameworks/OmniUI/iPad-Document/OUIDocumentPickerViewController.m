// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerViewController.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniBase/OmniBase.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFilter.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniDocumentStore/ODSLocalDirectoryScope.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniFileExchange/OmniFileExchange.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSInvocation-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniUI/OUIActionSheet.h>
#import <OmniUI/OUIActivityIndicator.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIAnimationSequence.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDragGestureRecognizer.h>
#import <OmniUI/OUIEmptyOverlayView.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUI/OUIInteractionLock.h>
#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUI/OUIToolbarButton.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentPickerGroupItemView.h>
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
#import <OmniUnzip/OUZipArchive.h>

#import "OUIDocumentParameters.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentPickerDragSession.h"
#import "OUIDocumentRenameSession.h"
#import "OUIDocumentTitleView.h"
#import "OUIExportOptionsController.h"
#import "OUIExportOptionsView.h"
#import "OUIDocumentAppController-Internal.h"
#import "OUISyncMenuController.h"

RCS_ID("$Id$");


#if 0 && defined(DEBUG)
    #define PICKER_DEBUG(format, ...) NSLog(@"PICKER: " format, ## __VA_ARGS__)
#else
    #define PICKER_DEBUG(format, ...)
#endif

OBDEPRECATED_METHOD(-documentPicker:toolbarPromptForRenamingFileItem:);

typedef NS_ENUM(NSInteger, OUIIconSize) {
    OUIIconSizeNormal,
    OUIIconSizeLarge,
};

#define GENERATE_DEFAULT_PNG 0

static NSString * const kActionSheetPickMoveDestinationScopeIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.PickMoveDestinationScope";
static NSString * const kActionSheetDeleteIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.DeleteAction";

static NSString * const FilteredItemsBinding = @"filteredItems";

@interface OUIDocumentPickerViewController () <MFMailComposeViewControllerDelegate, OUIDocumentTitleViewDelegate>

@property(nonatomic,copy) NSSet *filteredItems;
@property(nonatomic,strong) NSMutableDictionary *openInMapCache;

@property(nonatomic,strong) UISegmentedControl *filtersSegmentedControl;
@property(nonatomic,strong) UISegmentedControl *sortSegmentedControl;
@property(nonatomic,strong) OUIDocumentRenameSession *renameSession;

@property(nonatomic,readonly) BOOL canPerformActions;

@property (nonatomic, strong) UIBarButtonItem *emptyTrashBarButtonItem;

@end

@implementation OUIDocumentPickerViewController
{
    OUIReplaceDocumentAlert *_replaceDocumentAlert;
    
    // Used to map between an exportType (UTI string) and BOOL indicating if an app exists that we can send it to via Document Interaction.
    NSMutableDictionary *_openInMapCache;
    
    UIToolbar *_toolbar;
    
    OFXAccountActivity *_accountActivity;
    OUIDocumentTitleView *_normalTitleView;
    
    UIBarButtonItem *_duplicateDocumentBarButtonItem;
    UIBarButtonItem *_exportBarButtonItem;
    UIBarButtonItem *_moveBarButtonItem;
    UIBarButtonItem *_deleteBarButtonItem;
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
    
    OUIDocumentPickerDragSession *_dragSession;
    UIView *_topControls;
    BOOL _isObservingKeyboardNotifier;
    BOOL _isObservingApplicationDidEnterBackground;
    
    OUIEmptyOverlayView *_emptyOverlayView;
    NSArray *_emptyOverlayViewConstraints;
}

- (instancetype)_initWithDocumentPicker:(OUIDocumentPicker *)picker scope:(ODSScope *)scope folderItem:(ODSFolderItem *)folderItem;
{
    OBPRECONDITION(picker);
    OBPRECONDITION(scope);
    OBPRECONDITION(folderItem);
    
    if (!(self = [super initWithNibName:@"OUIDocumentPicker" bundle:OMNI_BUNDLE]))
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
    
    [self _flushAfterDocumentStoreInitializationActions];
    
    // Checks whether the document store has a file type for newly created documents
    [self _updateToolbarItemsAnimated:NO];

    /// --- setSelectedScope:
    
    OFPreference *scopePreference = [[self class] scopePreference];
    [scopePreference setStringValue:scope.identifier];
    
    [self scrollToTopAnimated:NO];

    // The delegate likely wants to update the title displayed in the document picker toolbar.
    [self updateTitle];
    
    // And we might need to show or hide the OmniPresence "sync now" button
    [self _updateToolbarItemsAnimated:NO];
    
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
    OBPRECONDITION(_dragSession == nil, "it retains us anyway, so we can't get here otherwise");
    
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

@synthesize openInMapCache = _openInMapCache;

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
        [self view];
        
        // <bug://bugs/60005> (Document picker scrolls to empty spot after editing file)
        [_mainScrollView.window layoutIfNeeded];
        
        //OBFinishPortingLater("Show/open the group scroll view if the item is in a group?");
        ODSFileItem *fileItem = [_documentStore fileItemWithURL:targetURL];
        if (!fileItem)
            [_mainScrollView scrollsToTop]; // OBFinishPorting -- this is a getter
        else
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

- (NSSet *)recursivelySelectedFileItems;
{
    NSMutableSet *fileItems = [NSMutableSet new];
    NSSet *candidates = _folderItem.childItems;
    for (ODSItem *item in candidates) {
        if (item.selected)
            [item addFileItems:fileItems];
    }
    return fileItems;
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
    
    UIEdgeInsets insets = scrollView.contentInset;
    [scrollView setContentOffset:CGPointMake(-insets.left, -insets.top) animated:animated];
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

    if (!self.canPerformActions)
        return;
    
    // Get rid of any visible popovers immediately
    [[OUIAppController controller] dismissPopoverAnimated:NO];

    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPickerTemplateDocumentFilter:)]) {
        OBASSERT([delegate documentPickerTemplateDocumentFilter:_documentPicker], @"Need to provide an actual filter for templates if you expect to use the template picker for new documents");

        ODSDocumentType type = [self _documentTypeForCurrentFilter];
        
        OUIDocumentCreationTemplatePickerViewController *templateChooser = [[OUIDocumentCreationTemplatePickerViewController alloc] initWithDocumentPicker:_documentPicker folderItem:_folderItem documentType:type];
        templateChooser.isReadOnly = YES;
        [self.navigationController pushViewController:templateChooser animated:YES];
        
        return;
    }

    [self newDocumentWithTemplateURL:nil];
}

- (void)newDocumentWithTemplateURL:(NSURL *)templateURL documentType:(ODSDocumentType)type;
{
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

    OUIActivityIndicator *activityIndicator = nil;

    if (templateURL) {
        ODSFileItem *fileItem = [_documentStore fileItemWithURL:templateURL];
        OUIDocumentPickerFileItemView *fileItemView = [_documentPicker.selectedScopeViewController.mainScrollView fileItemViewForFileItem:fileItem];
        UIView *view = _documentPicker.navigationController.topViewController.view;
        if (fileItemView)
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:fileItemView withColor:view.window.tintColor];
        else
            activityIndicator = [OUIActivityIndicator showActivityIndicatorInView:view withColor:view.window.tintColor];
    }

    [_documentStore createNewDocumentInScope:_documentScope folder:_folderItem documentType:type templateURL:templateURL completionHandler:^(ODSFileItem *createdFileItem, NSError *error){

        if (!createdFileItem) {
            [lock unlock];
            OUI_PRESENT_ERROR(error);
            return;
        }

        ODSFileItem *fileItemToRevealFrom = templateURL ? [self.documentStore fileItemWithURL:templateURL] : createdFileItem;

        // We want the file item to have a new date, but this is the wrong place to do it. Want to do it in the document picker before it creates the item.
        // [[NSFileManager defaultManager] touchItemAtURL:createdItem.fileURL error:NULL];

        [self _revealAndActivateNewDocumentFileItem:createdFileItem fileItemToRevealFrom:fileItemToRevealFrom completionHandler:^{
            [activityIndicator hide];
            [lock unlock];
        }];
    }];
}

- (void)newDocumentWithTemplateURL:(NSURL *)templateURL;
{
    [self newDocumentWithTemplateURL:templateURL documentType:ODSDocumentTypeNormal];
}

- (void)_duplicateItemsWithoutConfirmation:(NSSet *)selectedItems;
{
    OBASSERT([NSThread isMainThread]);

    NSMutableArray *errors = [NSMutableArray array];
    
    // We'll update once at the end
    [self _beginIgnoringDocumentsDirectoryUpdates];
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    [_documentScope copyItems:selectedItems toFolder:_folderItem  status:^(ODSFileItem *originalFileItem, ODSFileItem *duplicateFileItem, NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        OBASSERT(originalFileItem); // destination is nil if there is an error
        
        if (!duplicateFileItem) {
            OBASSERT(errorOrNil);
            if (errorOrNil) // let's not crash, though...
                [errors addObject:errorOrNil];
            return;
        }
        
        if ([_documentPicker.delegate respondsToSelector:@selector(documentPicker:didDuplicateFileItem:toFileItem:)])
            [_documentPicker.delegate documentPicker:_documentPicker didDuplicateFileItem:originalFileItem toFileItem:duplicateFileItem];
        
        // Copy document view state
        [OUIDocumentAppController moveDocumentStateFromURL:originalFileItem.fileURL toURL:duplicateFileItem.fileURL deleteOriginal:NO];
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
            // Make sure the duplicate items made it into the scroll view.
            for (ODSItem *item in finalItems)
                OBASSERT([self.mainScrollView.items member:item] == item);
            
            [self scrollItemsToVisible:finalItems animated:YES completion:^{
                [lock unlock];
            }];
        }];
        
        // This may be annoying if there were several errors, but it is misleading to not do it...
        for (NSError *error in errors)
            OUI_PRESENT_ALERT(error);
    }];
}

- (IBAction)duplicateDocument:(id)sender;
{
    // Validate each file item down the selected files and groups
    for (ODSFileItem *fileItem in self.recursivelySelectedFileItems) {
        
        // Make sure the item is fully downloaded.
        if (!fileItem.isDownloaded) {
            OUIAlert *alert = [[OUIAlert alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Cannot Duplicate Item", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error title")
                                                      message:NSLocalizedStringFromTableInBundle(@"This item cannot be duplicated because it is not fully downloaded. Please tap the item and wait for it to download before trying again.", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error message")
                                            cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUIDocument", OMNI_BUNDLE, @"button title")
                                                 cancelAction:^{
                                                     // Do nothing.
                                                     // Can't provide nil becuase it will brake OUIAlertView. This should be fixed at some point.
                                                 }];
            
            [alert show];
            
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

            UIColor *tintColor = self.navigationController.navigationBar.tintColor;
            [OUIMenuController showPromptFromSender:sender title:[NSString stringWithFormat:format, selectedItemCount] tintColor:tintColor action:^{
                [self _duplicateItemsWithoutConfirmation:selectedItems];
            }];
        }
    }
}

- (void)replaceDocumentAlert:(OUIReplaceDocumentAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex documentURL:(NSURL *)documentURL;
{
    ODSScope *scope = self.selectedScope;
    
    // TODO: Would like to find a better way to code this so we don't have so much duplicated.
    switch (buttonIndex) {
        case 0: /* Cancel */
            break;
        
        case 1: /* Replace */
        {
            OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
            [scope addDocumentInFolder:_folderItem fromURL:documentURL option:ODSStoreAddByReplacing completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
                if (!duplicateFileItem) {
                    OUI_PRESENT_ERROR(error);
                    [lock unlock];
                    return;
                }
                
                [self _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                    [lock unlock];
                }];
            }];
            break;
        }
        case 2: /* Rename */
        {
            OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

            [scope addDocumentInFolder:_folderItem fromURL:documentURL option:ODSStoreAddByRenaming completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
                if (!duplicateFileItem) {
                    OUI_PRESENT_ERROR(error);
                    [lock unlock];
                    return;
                }
                
                [self _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                    [lock unlock];
                }];
            }];
            break;
        }
        default:
            break;
    }
    
    _replaceDocumentAlert = nil;
}

- (void)addDocumentFromURL:(NSURL *)url;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_folderItem);
    
    ODSItem *existingItem = [_folderItem childItemWithFilename:[url lastPathComponent]];
    if (existingItem) {
        OBASSERT(_replaceDocumentAlert == nil); // this should never happen
        _replaceDocumentAlert = [[OUIReplaceDocumentAlert alloc] initWithDelegate:self documentURL:url];
        [_replaceDocumentAlert show];
        return;

    }
    
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    __weak id weakSelf = self;
    [_documentScope addDocumentInFolder:_folderItem fromURL:url option:ODSStoreAddNormally completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
        OUIDocumentPickerViewController *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        if (!duplicateFileItem) {
            OUI_PRESENT_ERROR(error);
            [lock unlock];
            return;
        }

        [strongSelf _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
            [lock unlock];
        }];
    }];
}

- (void)addSampleDocumentFromURL:(NSURL *)url;
{
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    NSString *fileName = [url lastPathComponent];
    NSString *localizedBaseName = [[OUIDocumentAppController controller] localizedNameForSampleDocumentNamed:[fileName stringByDeletingPathExtension]];
    
    ODSScope *scope = self.selectedScope;
    [scope addDocumentInFolder:_folderItem baseName:localizedBaseName fromURL:url option:ODSStoreAddByRenaming completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error) {
        
        if (!duplicateFileItem) {
            [lock unlock];
            OUI_PRESENT_ERROR(error);
            return;
        }
        
        [self _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
            [lock unlock];
        }];
    }];
}

- (void)exportedDocumentToURL:(NSURL *)url;
{
    [self rescanDocuments];
    [self clearSelection:YES];
}

- (NSArray *)availableFilters;
{
    // do not allow filtering on the trash scope.
    if (self.selectedScope.isTrash)
        return nil;

    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPickerAvailableFilters:)])
        return [delegate documentPickerAvailableFilters:_documentPicker];

    return nil;
}

- (NSArray *)availableExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
{
    NSMutableArray *exportTypes = [NSMutableArray array];
    
    // Get All Available Export Types
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:availableExportTypesForFileItem:serverAccount:exportOptionsType:)]) {
        [exportTypes addObjectsFromArray:[delegate documentPicker:_documentPicker availableExportTypesForFileItem:fileItem serverAccount:serverAccount exportOptionsType:exportOptionsType]];
    } else {
        // Add the 'native' marker
        [exportTypes insertObject:[NSNull null] atIndex:0];

        // PDF PNG Fallbacks
        BOOL canMakePDF = [delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)];
        BOOL canMakePNG = [delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)];
        if (canMakePDF)
            [exportTypes addObject:(NSString *)kUTTypePDF];
        if (canMakePNG)
            [exportTypes addObject:(NSString *)kUTTypePNG];
    }
    
    if ((serverAccount == nil) &&
        (exportOptionsType == OUIExportOptionsNone)) {
        // We're just looking for a rough count of how export types are available. Let's just return what we have.
        return exportTypes;
    }
    
    // Using Send To App
    if (exportOptionsType == OUIExportOptionsSendToApp) {
        NSMutableArray *docInteractionExportTypes = [NSMutableArray array];
        
        // check our own type here
        if ([self _canUseOpenInWithExportType:fileItem.fileType]) 
            [docInteractionExportTypes addObject:[NSNull null]];
        
        for (NSString *exportType in exportTypes) {
            if (OFNOTNULL(exportType) &&
                [self _canUseOpenInWithExportType:exportType]) {
                    [docInteractionExportTypes addObject:exportType];
            }
        }
        
        return docInteractionExportTypes;
    }
    
    return exportTypes;
}

- (NSArray *)availableImageExportTypesForFileItem:(ODSFileItem *)fileItem;
{
    NSMutableArray *imageExportTypes = [NSMutableArray array];
    NSArray *exportTypes = [self availableExportTypesForFileItem:fileItem serverAccount:nil exportOptionsType:OUIExportOptionsNone];
    for (NSString *exportType in exportTypes) {
        if (OFNOTNULL(exportType) &&
            UTTypeConformsTo((__bridge CFStringRef)exportType, kUTTypeImage)) {
                [imageExportTypes addObject:exportType];
        }
    }
    return imageExportTypes;
}

- (NSArray *)availableInAppPurchaseExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
{
    NSMutableArray *exportTypes = [NSMutableArray array];
    
    // Get All Available Export Types
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:availableInAppPurchaseExportTypesForFileItem:serverAccount:exportOptionsType:)]) {
        [exportTypes addObjectsFromArray:[delegate documentPicker:_documentPicker availableInAppPurchaseExportTypesForFileItem:fileItem serverAccount:serverAccount exportOptionsType:exportOptionsType]];
    }
    
    return exportTypes;
}

// Helper method for -availableDocuentInteractionExportTypesForFileItem:
- (BOOL)_canUseOpenInWithExportType:(NSString *)exportType;
{
    NSNumber *value = [self.openInMapCache objectForKey:exportType];
    if (value) {
        // We have a cached value, so immediately return it.
        return [value boolValue];
    }

    BOOL success = YES;
#if 0 // UNDONE
    // We don't have a cache for this exportType. We need to do our Doc Interaction hack to find out if this export type has an available app to send to.
    OUIDocumentAppController *sharedAppDelegate = (OUIDocumentAppController *)[UIApplication sharedApplication].delegate;
    UIWindow *mainWindow = sharedAppDelegate.window;
    
    NSString *tempDirectory = NSTemporaryDirectory();
    
    __autoreleasing NSError *error = nil;
    OFSFileManager *tempFileManager = [[OFSFileManager alloc] initWithBaseURL:[NSURL fileURLWithPath:tempDirectory isDirectory:YES] delegate:nil error:&error];
    if (error) {
        OUI_PRESENT_ERROR(error);
        return NO;
    }

    NSString *dummyPath = [tempDirectory stringByAppendingPathComponent:@"dummy"];
    BOOL isDirectory = UTTypeConformsTo((__bridge CFStringRef)exportType, kUTTypeDirectory);
    
    NSString *owned_UTIExtension = (NSString *)CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)exportType, kUTTagClassFilenameExtension));
    
    if (owned_UTIExtension) {
        dummyPath = [dummyPath stringByAppendingPathExtension:owned_UTIExtension];
    }
    
    
    // First check to see if the dummyURL already exists.
    NSURL *dummyURL = [NSURL fileURLWithPath:dummyPath isDirectory:isDirectory];
    ODAVFileInfo *dummyInfo = [tempFileManager fileInfoAtURL:dummyURL error:&error];
    if (error) {
        OUI_PRESENT_ERROR(error);
        return NO;
    }
    if ([dummyInfo exists] == NO) {
        if (isDirectory) {
            // Create dummy dir.
            [tempFileManager createDirectoryAtURL:dummyURL attributes:nil error:&error];
            if (error) {
                OUI_PRESENT_ERROR(error);
                return NO;
            }
        }
        else {
            // Create dummy file.
            [tempFileManager writeData:nil toURL:dummyURL atomically:YES error:&error];
            if (error) {
                OUI_PRESENT_ERROR(error);
                return NO;
            }
        }
    }
    
    // Try to popup UIDocumentInteractionController
    UIDocumentInteractionController *documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:dummyURL];
    BOOL success = [documentInteractionController presentOpenInMenuFromRect:CGRectZero inView:mainWindow animated:YES];
    if (success == YES) {
        [documentInteractionController dismissMenuAnimated:NO];
    }
    
    // Time to cache the result.
    [self.openInMapCache setObject:[NSNumber numberWithBool:success] forKey:exportType];
#endif
    return success;
}

- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(ODSFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
{
    completionHandler = [completionHandler copy]; // preserve scope
    
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:exportFileWrapperOfType:forFileItem:withCompletionHandler:)]) {
        [delegate documentPicker:_documentPicker exportFileWrapperOfType:exportType forFileItem:fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            if (completionHandler) {
                completionHandler(fileWrapper, error);
            }
        }];
        return;
    }
    
    if (OFISNULL(exportType)) {
        // The 'nil' type is always first in our list of types, so we can eport the original file as is w/o going through any app specific exporter.
        // NOTE: This is important for OO3 where the exporter has the ability to rewrite the document w/o hidden columns, in sorted order, with summary values (and eventually maybe with filtering). If we want to support untransformed exporting through the OO XML exporter, it will need to be configurable via settings on the OOXSLPlugin it uses. For now it assumes all 'exports' want all the transformations.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                       ^{
                           __autoreleasing NSError *error = nil;
                           NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initWithURL:fileItem.fileURL options:0 error:&error];
                           
                           if (completionHandler) {
                               completionHandler(fileWrapper, error);
                           }

                       });
        return;
    }

    
    // If the delegate doesn't implement the new file wrapper export API, try the older NSData API
    NSData *fileData = nil;
    NSString *pathExtension = nil;
    __autoreleasing NSError *error = nil;
    
    if (UTTypeConformsTo((__bridge CFStringRef)exportType, kUTTypePDF) && [delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)]) {
        fileData = [delegate documentPicker:_documentPicker PDFDataForFileItem:fileItem error:&error];
        pathExtension = @"pdf";
    } else if (UTTypeConformsTo((__bridge CFStringRef)exportType, kUTTypePNG) && [delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)]) {
        fileData = [delegate documentPicker:_documentPicker PNGDataForFileItem:fileItem error:&error];
        pathExtension = @"png";
    }
    
    if (fileData == nil)
        completionHandler(nil, error);
    
    NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:fileData];
    fileWrapper.preferredFilename = [fileItem.name stringByAppendingPathExtension:pathExtension];
    
    if (completionHandler) {
        completionHandler(fileWrapper, error);
    }
}

- (UIImage *)_iconForUTI:(NSString *)fileUTI size:(OUIIconSize)iconSize cache:(NSCache *)cache;
{
    static NSDictionary *imageUTIMap;
    static dispatch_once_t imageUTIMapdispatchOnceToken;
    dispatch_once(&imageUTIMapdispatchOnceToken, ^{
        NSArray *imageUTINormaliedMappings = [NSArray arrayWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"OUIDocumentImageUTIMap" withExtension:@"plist"]];
        
        NSMutableDictionary *mutableImageUTIMap = [NSMutableDictionary dictionary];
        for (NSDictionary *imageUTINormalizedMapping in imageUTINormaliedMappings) {
            NSString *normalImageName = imageUTINormalizedMapping[@"normalImageName"];
            NSArray *UTIs = imageUTINormalizedMapping[@"UTIs"];
            
            for (NSString *UTI in UTIs) {
                [mutableImageUTIMap setObject:normalImageName forKey:UTI];
            }
        }
        imageUTIMap = [NSDictionary dictionaryWithDictionary:mutableImageUTIMap];
    });
    
    NSString *imageName = nil;
    switch (iconSize) {
        case OUIIconSizeNormal:
            imageName = imageUTIMap[fileUTI];
            break;
        case OUIIconSizeLarge:
            imageName = [NSString stringWithFormat:@"%@-Large", imageUTIMap[fileUTI]];
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown icon size.");
            break;
    }
    
    UIImage *resultImage = [UIImage imageNamed:imageName];
    OBASSERT_NOTNULL(resultImage);
    
    return resultImage;
}

- (UIImage *)iconForUTI:(NSString *)fileUTI;
{
    UIImage *icon = nil;
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:iconForUTI:)])
        icon = [delegate documentPicker:_documentPicker iconForUTI:(CFStringRef)fileUTI];
    if (icon == nil) {
        static NSCache *cache = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            cache = [[NSCache alloc] init];
            [cache setName:@"OUIDocumentPicker iconForUTI:"];
        });
        icon = [self _iconForUTI:fileUTI size:OUIIconSizeNormal cache:cache];
    }
    return icon;
}

- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
{
    UIImage *icon = nil;
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:exportIconForUTI:)])
        icon = [delegate documentPicker:_documentPicker exportIconForUTI:(CFStringRef)fileUTI];
    if (icon == nil) {
        static NSCache *cache = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            cache = [[NSCache alloc] init];
            [cache setName:@"OUIDocumentPicker exportIconForUTI:"];
        });
        icon = [self _iconForUTI:fileUTI size:OUIIconSizeLarge cache:cache];
    }
    return icon;
}

- (NSString *)exportLabelForUTI:(NSString *)fileUTI;
{
    NSString *customLabel = nil;
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:labelForUTI:)])
        customLabel = [delegate documentPicker:_documentPicker labelForUTI:(CFStringRef)fileUTI];
    if (customLabel != nil)
        return customLabel;
    if (UTTypeConformsTo((__bridge CFStringRef)fileUTI, kUTTypePDF))
        return @"PDF";
    if (UTTypeConformsTo((__bridge CFStringRef)fileUTI, kUTTypePNG))
        return @"PNG";
    return nil;
}

- (UIImage *)exportIconForAppStoreIdentifier:(NSString *)appStoreIdentifier;
{
    UIImage *icon = nil;
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:exportIconForAppStoreIdentifier:)])
        icon = [delegate documentPicker:_documentPicker exportIconForAppStoreIdentifier:appStoreIdentifier];
    if (icon == nil)
        icon = [self exportIconForUTI:appStoreIdentifier];  // this will fall through to a default icon
    
    return icon;
}

- (NSString *)exportLabelForAppStoreIdentifier:(NSString *)appStoreIdentifier;
{
    NSString *customLabel = nil;
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:exportLabelForAppStoreIdentifier:)])
        customLabel = [delegate documentPicker:_documentPicker exportLabelForAppStoreIdentifier:appStoreIdentifier];
    if (customLabel != nil)
        return customLabel;
    
    return nil;
}

- (NSString *)exportDescriptionForAppStoreIdentifier:(NSString *)appStoreIdentifier;
{
    NSString *customLabel = nil;
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:exportDescriptionForAppStoreIdentifier:)])
        customLabel = [delegate documentPicker:_documentPicker exportDescriptionForAppStoreIdentifier:appStoreIdentifier];
    if (customLabel != nil)
        return customLabel;
    
    return nil;
}

- (NSString *)deleteDocumentTitle:(NSUInteger)count;
{
    OBPRECONDITION(count > 0);
    
    if (self.selectedScope.isTrash) {
        if (count == 1)
            return NSLocalizedStringFromTableInBundle(@"Delete Document", @"OmniUIDocument", OMNI_BUNDLE, @"delete button title");
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Delete %ld Documents", @"OmniUIDocument", OMNI_BUNDLE, @"delete button title"), count];
    } else {
        if (count == 1)
            return NSLocalizedStringFromTableInBundle(@"Move to Trash", @"OmniUIDocument", OMNI_BUNDLE, @"move to trash button title");
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Move %ld Items to Trash", @"OmniUIDocument", OMNI_BUNDLE, @"move to trash button title"), count];
    }
}

- (IBAction)deleteDocument:(id)sender;
{
    if (!self.canPerformActions)
        return;

    NSSet *selectedItems = self.selectedItems;
    NSUInteger selectedItemCount = [selectedItems count];
    
    if (selectedItemCount == 0) {
        OBASSERT_NOT_REACHED("Delete toolbar item shouldn't have been enabled");
        return;
    }
    
    [OUIMenuController showPromptFromSender:sender title:[self deleteDocumentTitle:selectedItemCount] destructive:YES action:^{
        [self _deleteWithoutConfirmation:selectedItems];
    }];
}

- (NSString *)printTitle;
// overridden by Graffle to return "Print (landscape) or Print (portrait)"
{
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:printButtonTitleForFileItem:)]) {
        return [delegate documentPicker:_documentPicker printButtonTitleForFileItem:self.singleSelectedFileItem];
    }
    
    return NSLocalizedStringFromTableInBundle(@"Print", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view");
}

- (IBAction)move:(id)sender;
{
    if (!self.canPerformActions)
        return;
    
    ODSScope *currentScope = self.selectedScope;

    BOOL willAddNewFolder = !currentScope.isTrash;
    
    NSString *topLevelMenuTitle;
    NSMutableArray *topLevelMenuOptions = [NSMutableArray array];

    // "Move" options
    NSMutableArray *moveOptions = [[NSMutableArray alloc] init];
    NSString *moveMenuTitle = [self _menuTitleAfterAddingMoveOptions:moveOptions fromCurrentScope:currentScope willAddOtherOptions:willAddNewFolder];
    
    // Move submenu
    if (willAddNewFolder && [moveOptions count] > 0) {
        topLevelMenuTitle = NSLocalizedStringFromTableInBundle(@"Move", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view");
        [topLevelMenuOptions addObject:[[OUIMenuOption alloc] initWithTitle:moveMenuTitle image:[UIImage imageNamed:@"OUIMenuItemMoveToScope"]
                                                                    options:moveOptions destructive:NO action:nil]];
    } else {
        topLevelMenuTitle = moveMenuTitle;
        [topLevelMenuOptions addObjectsFromArray:moveOptions];
    }
    
    // New folder
    OUIMenuOption *newFolderOption = nil;
    if (willAddNewFolder) {
        newFolderOption = [OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"New folder", @"OmniUIDocument", OMNI_BUNDLE, @"Action sheet title for making a new folder from the selected documents") image:[UIImage imageNamed:@"OUIMenuItemNewFolder"] action:^{
            [self _makeFolderFromSelectedDocuments];
        }];
        [topLevelMenuOptions addObject:newFolderOption];
    }
    
    OUIMenuController *menu = [[OUIMenuController alloc] initWithOptions:topLevelMenuOptions];
    if (topLevelMenuTitle)
        menu.title = topLevelMenuTitle;
    menu.tintColor = self.navigationController.navigationBar.tintColor;
    
    [menu showMenuFromSender:sender];
}

- (IBAction)export:(id)sender;
{
    if (!self.canPerformActions)
        return;

    ODSScope *currentScope = self.selectedScope;
    ODSFileItem *exportableFileItem;
    if (!currentScope.isTrash && self.selectedItemCount == 1 && !self.hasSelectedFolder) {
        // Single file selected. Early out here if the file isn't downloaded. We *can* move undownloaded files with OmniPresence, but this gives the user an indication of why the other sharing operations aren't listed.
        exportableFileItem = self.singleSelectedFileItem;
        OBASSERT(exportableFileItem);
        
        // Make sure selected item is fully downloaded.
        if (!exportableFileItem.isDownloaded) {
            OUIAlert *alert = [[OUIAlert alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Cannot Export Item", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error title")
                                                      message:NSLocalizedStringFromTableInBundle(@"This item cannot be exported because it is not fully downloaded. Please tap the item and wait for it to download before trying again.", @"OmniUIDocument", OMNI_BUNDLE, @"item not fully downloaded error message")
                                            cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUIDocument", OMNI_BUNDLE, @"button title")
                                                 cancelAction:^{
                                                     // Do nothing.
                                                     // Can't provide nil becuase it will brake OUIAlertView. This should be fixed at some point.
                                                 }];
            
            [alert show];
            
            return;
        }
    }
    
    NSMutableArray *topLevelMenuOptions;
    NSString *topLevelMenuTitle;
    
    if (!exportableFileItem) {
        OBASSERT_NOT_REACHED("Should be disabled");
        return;
    } else {
        // Single file export options
        topLevelMenuTitle = NSLocalizedStringFromTableInBundle(@"Actions", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view");
        topLevelMenuOptions = [[NSMutableArray alloc] init];
        
        id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
        
        BOOL canExport = [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"OUIExportEnabled"];
        NSArray *availableExportTypes = [self availableExportTypesForFileItem:exportableFileItem serverAccount:nil exportOptionsType:OUIExportOptionsNone];
        NSArray *availableImageExportTypes = [self availableImageExportTypesForFileItem:exportableFileItem];
        BOOL canSendToCameraRoll = [delegate respondsToSelector:@selector(documentPicker:cameraRollImageForFileItem:)];
        BOOL canPrint = [delegate respondsToSelector:@selector(documentPicker:printFileItem:fromButton:)] && [UIPrintInteractionController isPrintingAvailable];
        BOOL canUseOpenIn = [self _canUseOpenInWithFileItem:exportableFileItem];
        
        OB_UNUSED_VALUE(availableExportTypes); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning
        
        if ([MFMailComposeViewController canSendMail]) {
            // All email options should go here (within the test for whether we can send email)
            // more than one option? Display the 'export options sheet'
            [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemSendToMail"] action:^{
                if (availableExportTypes.count > 0)
                    [self emailDocumentChoice:self];
                else
                    [self emailDocument:self];
            }]];
        }
        
        if (canExport) {
            [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Export to WebDAV", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemExportToWebDAV"] action:^{
                [self exportDocument:self];
            }]];
        }
        
        if (canUseOpenIn) {
            [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Send to App", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemSendToApp"] action:^{
                [self sendToApp:self];
            }]];
        }
        
        if (availableImageExportTypes.count > 0) {
            [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Copy as Image", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemCopyAsImage"] action:^{
                [self copyAsImage:self];
            }]];
        }
        
        if (canSendToCameraRoll) {
            [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Send to Photos", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemSendToPhotos"] action:^{
                [self sendToCameraRoll:self];
            }]];
        }
        
        if (canPrint) {
            NSString *printTitle = [self printTitle];
            [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:printTitle image:[UIImage imageNamed:@"OUIMenuItemPrint"] action:^{
                [self printDocument:self];
            }]];
        }
        
        if ([delegate respondsToSelector:@selector(documentPicker:addExportActions:)]) {
            [delegate documentPicker:_documentPicker addExportActions:^(NSString *title, UIImage *image, void (^action)(void)){
                [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:title image:image action:action]];
            }];
        }
    }
    
    OUIMenuController *menu = [[OUIMenuController alloc] initWithOptions:topLevelMenuOptions];
    if (topLevelMenuTitle)
        menu.title = topLevelMenuTitle;
    menu.tintColor = self.navigationController.navigationBar.tintColor;
    
    [menu showMenuFromSender:sender];
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
    
    UIImage *folderImage = [UIImage imageNamed:@"OUIMenuItemFolder.png"];
    
    OUIMenuOption *option;
    if (candidateParentFolder == currentFolder) {
        // This folder isn't a valid location, but if one of its children is, emit a placeholder to make the indentation look nice
        if (startingOptionCount != [options count]) {
            option = [[OUIMenuOption alloc] initWithTitle:candidateParentFolder.name image:folderImage action:nil];
        }
    } else {
        // This is a valid destination. Great!
        option = [[OUIMenuOption alloc] initWithTitle:candidateParentFolder.name image:folderImage action:^{
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

- (IBAction)emailDocument:(id)sender;
{
    ODSFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    NSData *documentData = [fileItem emailData];
    NSString *documentFilename = [fileItem emailFilename];
    OBFinishPortingLater("<bug:///75843> (Add a UTI property to ODSFileItem)");
    NSString *documentType = OFUTIForFileExtensionPreferringNative([documentFilename pathExtension], NO); // NSString *documentType = [ODAVFileInfo UTIForFilename:documentFilename];
    OBASSERT(documentType != nil); // UTI should be registered in the Info.plist under CFBundleDocumentTypes

    [self _sendEmailWithSubject:[fileItem name] messageBody:nil isHTML:NO attachmentName:documentFilename data:documentData fileType:documentType];
}

- (BOOL)_canUseEmailBodyForExportType:(NSString *)exportType;
{
    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    return ![delegate respondsToSelector:@selector(documentPicker:canUseEmailBodyForType:)] || [delegate documentPicker:_documentPicker canUseEmailBodyForType:exportType];
}

- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType;
{
    ODSFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }
    
    if ([fileWrapper isDirectory]) {
        NSDictionary *childWrappers = [fileWrapper fileWrappers];
        if ([childWrappers count] == 1) {
            NSFileWrapper *childWrapper = [childWrappers anyObject];
            if ([childWrapper isRegularFile]) {
                // File wrapper with just one file? Let's see if it's HTML which we can send as the message body (rather than as an attachment)
                NSString *documentType = OFUTIForFileExtensionPreferringNative(childWrapper.preferredFilename.pathExtension, [NSNumber numberWithBool:childWrapper.isDirectory]);
                if (UTTypeConformsTo((__bridge CFStringRef)documentType, kUTTypeHTML)) {
                    if ([self _canUseEmailBodyForExportType:exportType]) {
                        NSString *messageBody = [[NSString alloc] initWithData:[childWrapper regularFileContents] encoding:NSUTF8StringEncoding];
                        if (messageBody != nil) {
                            [self _sendEmailWithSubject:fileItem.name messageBody:messageBody isHTML:YES attachmentName:nil data:nil fileType:nil];
                            return;
                        }
                    } else {
                        // Though we're not sending this as the HTML body, we really only need to attach the HTML itself
                        // When we try to change the preferredFilename on the childWrapper we are getting a '*** Collection <NSConcreteHashTable: 0x58b59b0> was mutated while being enumerated.' error. Tim and I tried a few things to get past this but decided to create a new NSFileWrapper.
                        NSFileWrapper *singleChildFileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:[childWrapper regularFileContents]];
                        singleChildFileWrapper.preferredFilename = [fileWrapper.preferredFilename stringByAppendingPathExtension:[childWrapper.preferredFilename pathExtension]];
                        fileWrapper = singleChildFileWrapper;
                    }
                }
            }
        }
    }
    
    NSData *emailData;
    NSString *emailType;
    NSString *emailName;
    if ([fileWrapper isRegularFile]) {
        emailName = fileWrapper.preferredFilename;
        emailType = exportType;
        emailData = [fileWrapper regularFileContents];
        
        NSString *emailType = OFUTIForFileExtensionPreferringNative(fileWrapper.preferredFilename.pathExtension, NO);
        if (UTTypeConformsTo((__bridge CFStringRef)emailType, kUTTypePlainText)) {
            // Plain text? Let's send that as the message body
            if ([self _canUseEmailBodyForExportType:exportType]) {
                NSString *messageBody = [[NSString alloc] initWithData:emailData encoding:NSUTF8StringEncoding];
                if (messageBody != nil) {
                    [self _sendEmailWithSubject:fileItem.name messageBody:messageBody isHTML:NO attachmentName:nil data:nil fileType:nil];
                    return;
                }
            }
        }
    } else {
        emailName = [fileWrapper.preferredFilename stringByAppendingPathExtension:@"zip"];
        emailType = OFUTIForFileExtensionPreferringNative(@"zip", NO);
        NSString *zipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:emailName];
        @autoreleasepool {
            __autoreleasing NSError *error = nil;
            if (![OUZipArchive createZipFile:zipPath fromFileWrappers:[NSArray arrayWithObject:fileWrapper] error:&error]) {
                OUI_PRESENT_ERROR(error);
                return;
            }
        };
        emailData = [NSData dataWithContentsOfMappedFile:zipPath];
    }
    
    [self _sendEmailWithSubject:fileItem.name messageBody:nil isHTML:NO attachmentName:emailName data:emailData fileType:emailType];
}

- (void)emailExportType:(NSString *)exportType;
{
    @autoreleasepool {
        [self exportFileWrapperOfType:exportType forFileItem:self.singleSelectedFileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            if (fileWrapper == nil) {
                OUI_PRESENT_ERROR(error);
                return;
            }
            [self sendEmailWithFileWrapper:fileWrapper forExportType:exportType];
        }];
    }
}

- (void)exportDocument:(id)sender;
{
    [OUISyncMenuController displayAsSheetInViewController:[OUIDocumentAppController controller].window.rootViewController];
}

- (void)emailDocumentChoice:(id)sender;
{
    OUIExportOptionsController *exportController = [[OUIExportOptionsController alloc] initWithServerAccount:nil exportType:OUIExportOptionsEmail];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:exportController];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [self presentViewController:navigationController animated:YES completion:nil];
    
}

- (void)sendToApp:(id)sender;
{
    OUIExportOptionsController *exportOptionsController = [[OUIExportOptionsController alloc] initWithServerAccount:nil exportType:OUIExportOptionsSendToApp];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:exportOptionsController];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)printDocument:(id)sender;
{
    ODSFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    [delegate documentPicker:_documentPicker printFileItem:fileItem fromButton:_exportBarButtonItem];
}

- (void)copyAsImage:(id)sender;
{
    ODSFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    NSMutableArray *items = [NSMutableArray array];

    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    BOOL canMakeCopyAsImageSpecificPDF = [delegate respondsToSelector:@selector(documentPicker:copyAsImageDataForFileItem:error:)];
    BOOL canMakePDF = [delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)];
    BOOL canMakePNG = [delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)];

    //- (NSData *)documentPicker:(OUIDocumentPicker *)picker copyAsImageDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
    if (canMakeCopyAsImageSpecificPDF) {
        __autoreleasing NSError *error = nil;
        NSData *pdfData = [delegate documentPicker:_documentPicker copyAsImageDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    } else if (canMakePDF) {
        __autoreleasing NSError *error = nil;
        NSData *pdfData = [delegate documentPicker:_documentPicker PDFDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    }
    
    // Don't put more than one image format on the pasteboard, because both will get pasted into iWork.  <bug://bugs/61070>
    if (!canMakeCopyAsImageSpecificPDF &&!canMakePDF && canMakePNG) {
        __autoreleasing NSError *error = nil;
        NSData *pngData = [delegate documentPicker:_documentPicker PNGDataForFileItem:fileItem error:&error];
        if (!pngData) {
            OUI_PRESENT_ERROR(error);
        }
        else {
            // -setImage: will register our image as being for the JPEG type. But, our image isn't a photo.
            [items addObject:[NSDictionary dictionaryWithObject:pngData forKey:(id)kUTTypePNG]];
        }
    }
    
    // -setImage: also puts a title on the pasteboard, so we might as well. They append .jpg, but it isn't clear whether we should append .pdf or .png. Appending nothing.
    NSString *title = fileItem.name;
    if (![NSString isEmptyString:title])
        [items addObject:[NSDictionary dictionaryWithObject:title forKey:(id)kUTTypeUTF8PlainText]];
    
    if ([items count] > 0)
        pboard.items = items;
    else
        OBASSERT_NOT_REACHED("No items?");
    
    [self clearSelection:YES];
}

- (void)sendToCameraRoll:(id)sender;
{
    ODSFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
    UIImage *image = [delegate documentPicker:_documentPicker cameraRollImageForFileItem:fileItem];
    OBASSERT(image); // There is no default implementation -- the delegate should return something.

    if (image)
        UIImageWriteToSavedPhotosAlbum(image, self, @selector(_sendToCameraRollImage:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)_sendToCameraRollImage:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
{
    OUI_PRESENT_ERROR(error);
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
    NSMutableArray *descriptors = [NSMutableArray array];
    
    if ([[self sortPreference] enumeratedValue] == OUIDocumentPickerItemSortByDate) {
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

- (void)selectedFilterChanged;
{
    OBPRECONDITION(_documentStoreFilter);
    
    OUIDocumentPickerFilter *filter = [[self class] selectedFilterForPicker:self.documentPicker];
    [self.filtersSegmentedControl setSelectedSegmentIndex:[[self availableFilters] indexOfObject:filter]];
    
    if ([_documentStoreFilter.filterPredicate isEqual:filter.predicate])
        return;
    
    [self scrollToTopAnimated:NO];
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
    
    [self scrollToTopAnimated:NO];
    [self.sortSegmentedControl setSelectedSegmentIndex:sort];
    _mainScrollView.itemSort = sort;
}

- (void)filterSegmentChanged:(id)sender;
{
    NSArray *availableFilters = [self availableFilters];
    NSString *identifier = [[[self class] filterPreference] stringValue];
    NSUInteger oldSelectedIndex = [availableFilters indexOfObjectPassingTest:^BOOL(OUIDocumentPickerFilter *filter, NSUInteger idx, BOOL *stop) {
        return [filter.identifier isEqualToString:identifier];
    }];
    
    NSUInteger newSelectedIndex = ((UISegmentedControl *)sender).selectedSegmentIndex;
    OUIDocumentPickerFilter *filter = [[self availableFilters] objectAtIndex:newSelectedIndex];
    
    UIView *snapshot = [_mainScrollView snapshotViewAfterScreenUpdates:NO];
    CGRect frame = _mainScrollView.frame;
    BOOL movingLeft = newSelectedIndex < oldSelectedIndex;
    CGFloat movement = movingLeft ? CGRectGetWidth(frame) : -CGRectGetWidth(frame);
    
    [UIView performWithoutAnimation:^{
        snapshot.frame = frame;
        [self.view insertSubview:snapshot aboveSubview:_mainScrollView];
        
        CGRect offscreenRect = frame;
        offscreenRect.origin.x -= movement;
        _mainScrollView.frame = offscreenRect;
        
        [[[self class] filterPreference] setStringValue:filter.identifier];
        [_mainScrollView layoutIfNeeded];
    }];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        _mainScrollView.frame = frame;
        
        CGRect offscreenRect = frame;
        offscreenRect.origin.x += movement;
        snapshot.frame = offscreenRect;
    } completion:^(BOOL finished) {
        [snapshot removeFromSuperview];
    }];
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
    if (!_normalTitleView) {
        _normalTitleView = [[OUIDocumentTitleView alloc] init];
        _normalTitleView.syncAccountActivity = _accountActivity;
        _normalTitleView.delegate = self;
    }
    
    NSString *title;
    if (_folderItem == _folderItem.scope.rootFolder)
        title = _folderItem.scope.displayName;
    else
        title = _folderItem.name;
    
    _normalTitleView.title = title;
    self.navigationItem.title = title; // for the Back button
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

#pragma mark -
#pragma mark UIViewController subclass

- (BOOL)automaticallyAdjustsScrollViewInsets;
{
    return NO;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
    

    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"OUIDocumentPickerBackgroundTile.png"]];

    // motion tilt under it all
    CGFloat maxTilt = 50;
    UIView *mobileBackground = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, -maxTilt, -maxTilt)];
    mobileBackground.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    mobileBackground.backgroundColor = self.view.backgroundColor;
    [mobileBackground addMotionMaxTilt:-maxTilt];
    [self.view insertSubview:mobileBackground atIndex:0];
    self.backgroundView = mobileBackground;
    
    _mainScrollView.landscape = landscape;
        
    [self _setupTopControls];
    
    OFPreference *sortPreference = [[self class] sortPreference];
    [OFPreference addObserver:self selector:@selector(selectedSortChanged) forPreference:sortPreference];
    [self selectedSortChanged];
    
    if (self.selectedScope.isTrash) {
        self.emptyTrashBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Empty Trash", @"OmniUIDocument", OMNI_BUNDLE, @"empty trash button title") style:UIBarButtonItemStylePlain target:self action:@selector(emptyTrashItemTapped:)];
    } else {
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
    
    // We sign up for this notification in -viewDidLoad, instead of -viewWillAppear: since we want to receive it when we are off screen (previews can be updated when a document is closing and we never get on screen -- for example if a document is open and another document is opened via tapping on Mail).
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_previewsUpdateForFileItemNotification:) name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    [[UIPrintInteractionController sharedPrintController] dismissAnimated:NO];
    
    BOOL landscape = UIInterfaceOrientationIsLandscape(toInterfaceOrientation);
    
    [_mainScrollView willRotateWithDuration:duration];
    _mainScrollView.landscape = landscape;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
{
    [_mainScrollView didRotate];
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

- (void)willMoveToParentViewController:(UIViewController *)parent;
{
    [super willMoveToParentViewController:parent];
    
    // Start out with the right grid size. Also, the device might be rotated while we a document was open and we weren't in the view controller tree
    if (parent) {
        BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);

        _mainScrollView.landscape = landscape;

        if (!_isObservingKeyboardNotifier) {
            _isObservingKeyboardNotifier = YES;
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardHeightWillChange:) name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
        }
    }
}

- (void)didMoveToParentViewController:(UIViewController *)parent;
{
    [super didMoveToParentViewController:parent];
    
    if (parent) {
        // If the user starts closing a document and then rotates the device before the close finishes, we can get send {will,did}MoveToParentViewController: where the "will" has one orientation and the "did" has another, but we are not sent -willRotateToInterfaceOrientation:duration:, but we *are* sent the "didRotate...".
        BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
        
        _mainScrollView.landscape = landscape;
    } else {
        if (_isObservingKeyboardNotifier) {
            _isObservingKeyboardNotifier = NO;
            [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    self.view.frame = self.view.superview.bounds;
    _mainScrollView.frame = self.view.bounds;
    
    _mainScrollView.shouldHideTopControlsOnNextLayout = YES;
    
    self.navigationController.navigationBar.barStyle = UIBarStyleDefault;

    // If we are being exposed rather than added (Help modal view controller being dismissed), we might have missed an orientation change
    if ([self isMovingToParentViewController] == NO) {
        BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
        
        if (_mainScrollView.landscape ^ landscape) {
            _mainScrollView.landscape = landscape;
        }
    }
    
    // Might have been disabled while we went off screen (like when making a new document)
    [self _performDelayedItemPropagationWithCompletionHandler:nil];

    [self _updateEmptyViewControlVisibility];
    [self _updateToolbarItemsAnimated:animated];
    
    if (!_isObservingApplicationDidEnterBackground) { // Don't leak observations if view state transition calls are duplicated/dropped
        _isObservingApplicationDidEnterBackground = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:NO];
    [self _updateEmptyViewControlVisibility];


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
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    [super setEditing:editing animated:animated];
    
    // Tint Color - OmniBlueColor when edting, otherwize nil and let the system pull from superviews.
    UIColor *tintColor = (editing) ? [UIColor omniBlueColor] : nil;
    self.navigationController.navigationBar.tintColor = tintColor;
    _topControls.tintColor = tintColor;
    
    // Dismiss any Popovers or Action Sheets.
    [[OUIAppController controller] dismissActionSheetAndPopover:YES];

    // If you Edit in an open group, the items in the background scroll view shouldn't wiggle.
    [self.mainScrollView setEditing:editing animated:animated];
    
    if (!editing) {
        [self clearSelection:NO];
    }
    
    [self _updateToolbarItemsAnimated:YES];
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

#pragma mark - UIResponder subclass

// Allow this so that when a document is closed we don't have a nil first responder (which would mean that the cmd-n key command on the document controller wouldn't fire).
- (BOOL)canBecomeFirstResponder;
{
    return YES;
}

#pragma mark - UITextInputTraits

// ... this avoids flicker when opening the keyboard (renaming a document) after having closed a dark-mode document
- (UIKeyboardAppearance)keyboardAppearance;
{
    return UIKeyboardAppearanceLight;
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self clearSelection:YES];
    
    [controller.presentingViewController dismissViewControllerAnimated:YES completion:nil];
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
        [[OUIDocumentAppController controller] presentSyncError:lastSyncError inViewController:self retryBlock:^{
            [syncAgent sync:nil];
        }];
        return;
    }
    
    [syncAgent sync:nil];
}

#pragma mark -
#pragma mark OUIDocumentPickerScrollView delegate

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewStartedEditingName:(OUIDocumentPickerItemView *)itemView;
{
    if (!_isReadOnly)
        [self _startedRenamingInItemView:itemView];
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemView:(OUIDocumentPickerItemView *)itemView finishedEditingName:(NSString *)name;
{
    self.renameSession = nil;
    [self _updateToolbarItemsAnimated:YES];
    _topControls.userInteractionEnabled = YES;
    _mainScrollView.scrollEnabled = YES;
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView willDisplayItemView:(OUIDocumentPickerItemView *)itemView;
{
    itemView.metadataView.label = [self nameLabelForItem:itemView.item];

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
    return [currentFilter.identifier isEqualToString:ODSDocumentPickerFilterTemplateIdentifier] ? ODSDocumentTypeTemplate : ODSDocumentTypeNormal;
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
    if (!self.canPerformActions || _renameSession) // Another rename might be starting (we don't have a spot to start/stop ignore user interaction there since the keyboard drives the animation).
        return;
    
    ODSItem *item = itemView.item;
    if (self.editing) {
        _setItemSelectedAndBounceView(self, itemView, !item.selected);
        
        [self _updateToolbarItemsAnimated:NO]; // Update the selected file item count
        [self _updateToolbarItemsEnabledness];
        return;
    }

    if (_documentScope.isTrash) {
        NSMutableArray *options = [NSMutableArray new];
        NSString *menuTitle = [self _menuTitleAfterAddingMoveOptions:options fromCurrentScope:_documentScope willAddOtherOptions:NO];
        
        // The move menu acts on the selected items
        [self setEditing:YES animated:YES];
        _setItemSelectedAndBounceView(self, itemView, YES);

        OUIMenuController *moveToMenuController = [[OUIMenuController alloc] initWithOptions:options];
        moveToMenuController.title = menuTitle;
        moveToMenuController.tintColor = [UIColor omniBlueColor]; // We are in 'edit' mode
        moveToMenuController.didFinish = ^{
            [self setEditing:NO animated:YES];
        };
        
        [moveToMenuController showMenuFromSender:itemView];
        return;
    }

    if ([itemView isKindOfClass:[OUIDocumentPickerFileItemView class]]) {
        ODSFileItem *fileItem = (ODSFileItem *)itemView.item;
        OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);
        
        if (fileItem.isDownloaded == NO) {
            NSError *error = nil;
            if (![fileItem requestDownload:&error]) {
                OUI_PRESENT_ERROR(error);
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

static UIImage *ImageForScope(ODSScope *scope) {
    OBFinishPortingLater("TODO: Add a category to ODSScope that vends an icon");
    if ([scope isKindOfClass:[ODSLocalDirectoryScope class]]) {
        return [UIImage imageNamed:@"OUIMenuItemLocalScope"];
    } else if ([scope isKindOfClass:[OFXDocumentStoreScope class]]) {
        return [UIImage imageNamed:@"OUIMenuItemPresenceScope"];
    } else {
        OBASSERT_NOT_REACHED("Unknown scope type %@", scope);
        return nil;
    }
}

- (NSString *)_menuTitleAfterAddingMoveOptions:(NSMutableArray *)options fromCurrentScope:(ODSScope *)currentScope willAddOtherOptions:(BOOL)willAddOtherOptions;
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
        [self _addMoveToFolderOptions:folderOptions candidateParentFolder:scope.rootFolder currentFolder:currentFolder excludedTreeFolders:selectedFolders];
        
        void (^moveToScopeRootAction)(void) = ^{
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
    CGFloat contentYOffset = scrollView.contentOffset.y;
    CGFloat topInset = _mainScrollView.contentInset.top;
    CGRect topControlsFrame = _topControls.frame;
    CGFloat contentYOffsetAtHalfwayHidden = CGRectGetMidY(topControlsFrame) - topInset;
    CGFloat contentYOffsetAtCompletelyHidden = CGRectGetMaxY(topControlsFrame) - topInset;

    _topControls.alpha = CLAMP((contentYOffset - contentYOffsetAtCompletelyHidden) / (contentYOffsetAtHalfwayHidden - contentYOffsetAtCompletelyHidden), 0, 1);
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
    CGFloat topInset = _mainScrollView.contentInset.top;
    CGRect topControlsFrame = _topControls.frame;
    
    if (targetContentYOffset + topInset < CGRectGetMidY(topControlsFrame)) {
        targetContentYOffset = CGRectGetMinY(topControlsFrame) - topInset;
    } else {
        targetContentYOffset = MAX(targetContentYOffset, CGRectGetMaxY(topControlsFrame) - topInset);
    }
    
    targetContentOffset->y = targetContentYOffset;
}

#pragma mark - OUIDocumentPickerDragSession callbacks

- (void)dragSessionTerminated;
{
    _dragSession = nil;
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
                OUI_PRESENT_ERROR(error);
                
                completionHandler(error);
            }
        }];
    } else if (item.type == ODSItemTypeFolder) {
        ODSFolderItem *folderItem = (ODSFolderItem *)item;
        
        [folderItem.scope renameFolderItem:folderItem baseName:baseName completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil){
            
            reenable();
            
            if (movedFileItems) {
                [self _didPerformRenameOfFolderItems:movedFileItems];
                completionHandler(nil);
            } else {
                for (NSError *error in errorsOrNil) {
                    [error log:@"Error renaming folder %@ to \"%@\"", folderItem.relativePath, baseName];
                    OUI_PRESENT_ERROR(error);
                }
                
                completionHandler([errorsOrNil firstObject]);
            }
        }];
    } else {
        OBASSERT_NOT_REACHED("Unknown item type");
    }
    
}

#pragma mark - Private

static UIBarButtonItem *NewSpacerBarButtonItem()
{
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    item.width = kOUIDocumentPickerNavBarItemsAdditionalSpace;
    return item;
}

- (void)_updateToolbarItemsAnimated:(BOOL)animated;
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
    
    NSMutableArray *leftItems = [NSMutableArray array];
    UINavigationItem *navigationItem = self.navigationItem;

    if (_renameSession) {
        ODSItem *item = _renameSession.itemView.item;
        
        NSString *title = nil;
        id <OUIDocumentPickerDelegate> delegate = _documentPicker.delegate;
        if ([delegate respondsToSelector:@selector(documentPicker:toolbarPromptForRenamingItem:)])
            title = [delegate documentPicker:_documentPicker toolbarPromptForRenamingItem:item];
        if (!title) {
            if (item.type == ODSItemTypeFolder)
                title = NSLocalizedStringFromTableInBundle(@"Rename Folder", @"OmniUIDocument", OMNI_BUNDLE, @"toolbar prompt while renaming a folder");
            else
                title = NSLocalizedStringFromTableInBundle(@"Rename Document", @"OmniUIDocument", OMNI_BUNDLE, @"toolbar prompt while renaming a document");
        }
        navigationItem.title = title;
        navigationItem.titleView = nil;
        [navigationItem setRightBarButtonItems:@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancelRenaming:)]] animated:animated];
        [navigationItem setHidesBackButton:YES animated:animated];
        [navigationItem setLeftBarButtonItems:nil animated:animated];

        // The shield view protects us from events, so no need to disable interaction or become disabled. But, we should look disabled.
        _topControls.tintAdjustmentMode = UIViewTintAdjustmentModeDimmed;
        
        return;
    } else {
        [navigationItem setHidesBackButton:NO animated:animated];
        _topControls.tintAdjustmentMode = UIViewTintAdjustmentModeAutomatic;
    }
    
    if (editing) {
        if (!_exportBarButtonItem) {
            // We keep pointers to a few toolbar items that we need to update enabledness on.
            _exportBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentExport.png"] style:UIBarButtonItemStylePlain target:self action:@selector(export:)];
            _exportBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"Export toolbar item accessibility label.");
            
            _moveBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIMenuItemFolder"] style:UIBarButtonItemStylePlain target:self action:@selector(move:)];
            _moveBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Move", @"OmniUIDocument", OMNI_BUNDLE, @"Move toolbar item accessibility label.");

            _duplicateDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentDuplicate.png"] style:UIBarButtonItemStylePlain target:self action:@selector(duplicateDocument:)];
            _duplicateDocumentBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Duplicate", @"OmniUIDocument", OMNI_BUNDLE, @"Duplicate toolbar item accessibility label.");
        }
        
        // Delete Item
        UIImage *deleteButtonImage = self.selectedScope.isTrash ? [UIImage imageNamed:@"OUIDeleteFromTrash"] : [UIImage imageNamed:@"OUIDocumentDelete"];
        _deleteBarButtonItem = [[UIBarButtonItem alloc] initWithImage:deleteButtonImage style:UIBarButtonItemStylePlain target:self action:@selector(deleteDocument:)];
        if (self.selectedScope.isTrash) {
            _deleteBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Delete", @"OmniUIDocument", OMNI_BUNDLE, @"Delete toolbar item accessibility label.");
        } else {
            _deleteBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Move to Trash", @"OmniUIDocument", OMNI_BUNDLE, @"Move to Trash toolbar item accessibility label.");
        }
        
        _exportBarButtonItem.enabled = NO;
        _duplicateDocumentBarButtonItem.enabled = NO;
        _deleteBarButtonItem.enabled = NO;
        
        [leftItems addObject:_exportBarButtonItem];
        [leftItems addObject:_moveBarButtonItem];
        if (!self.selectedScope.isTrash) {
            [leftItems addObject:_duplicateDocumentBarButtonItem];
        }
        [leftItems addObject:_deleteBarButtonItem];
        navigationItem.leftItemsSupplementBackButton = NO;
    } else {
        [self updateTitle];
        self.navigationItem.titleView = _normalTitleView;
    }
    [navigationItem setLeftBarButtonItems:leftItems animated:animated];
    
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
                
                if ([NSString isEmptyString:format]) {
                    if (selectedItemCount == 0)
                        format = NSLocalizedStringFromTableInBundle(@"Select a Document", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a no selected documents.");
                    else if (selectedItemCount == 1)
                        format = NSLocalizedStringFromTableInBundle(@"1 Document Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a single selected document.");
                    else
                        format = NSLocalizedStringFromTableInBundle(@"%ld Documents Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a multiple selected documents.");
                }
            }
        }

        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
            OBFinishPortingLater("We used to hide the title when in edit mode on the iPhone to save space, but it appears to be no larger than the name of the folder/scope");
        
        navigationItem.title = [NSString stringWithFormat:format, [selectedItems count]];
        navigationItem.titleView = nil;

        [rightItems addObject:self.editButtonItem]; // Done
        
        // We want the empty trash bar button item in both modes.
        if (self.emptyTrashBarButtonItem) {
            self.emptyTrashBarButtonItem.enabled = (_filteredItems.count > 0);
            [rightItems addObject:NewSpacerBarButtonItem()];
            [rightItems addObject:self.emptyTrashBarButtonItem];
        }
    } else {
        // Items in the right bar items array are positioned right to left.
        
        // on iPhone to save space, show "Done" button, but not "Edit" button (user can press-and-hold on doc instead)
        if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPhone) {
            UIBarButtonItem *editButtonItem = self.editButtonItem;
            editButtonItem.title = NSLocalizedStringFromTableInBundle(@"Select", @"OmniUIDocument", OMNI_BUNDLE, @"edit button title for doc picker in non-edit mode");
            [rightItems addObject:self.editButtonItem];
            [rightItems addObject:NewSpacerBarButtonItem()];
        }

        // We want the empty trash bar button item in both modes.
        if (self.emptyTrashBarButtonItem) {
            self.emptyTrashBarButtonItem.enabled = (_filteredItems.count > 0);
            [rightItems addObject:self.emptyTrashBarButtonItem];
            [rightItems addObject:NewSpacerBarButtonItem()];
        }

        [rightItems addObject:[[OUIAppController controller] newAppMenuBarButtonItem]];
        
        if ((_documentStore.documentTypeForNewFiles != nil) && (self.selectedScope.isTrash == NO) && [_documentStore.scopes containsObjectIdenticalTo:_documentScope]) {
            [rightItems addObject:NewSpacerBarButtonItem()];
            OUIBarButtonItem *addItem = [[OUIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarAddDocument.png"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(newDocument:)];

            addItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"New Document", @"OmniUIDocument", OMNI_BUNDLE, @"New Document toolbar item accessibility label.");
            [rightItems addObject:addItem];
        }
    }
    
    [navigationItem setRightBarButtonItems:rightItems animated:animated];
}

- (void)_updateToolbarItemsEnabledness;
{
    if (self.isEditing) {
        NSUInteger count = self.selectedItemCount;
        if (count == 0) {
            _exportBarButtonItem.enabled = NO;
            _moveBarButtonItem.enabled = NO;
            _duplicateDocumentBarButtonItem.enabled = NO;
            _deleteBarButtonItem.enabled = NO;
        } else {
            BOOL isViewingTrash = self.selectedScope.isTrash;
            ODSFileItem *singleSelectedFileItem = (count == 1) ? self.singleSelectedFileItem : nil;
            
            // Disable the export option while in the trash. We also don't support exporting multiple documents at the same time.
            BOOL canExport = !isViewingTrash && (singleSelectedFileItem != nil);
            if (canExport)
                canExport = ([[self availableExportTypesForFileItem:singleSelectedFileItem serverAccount:nil exportOptionsType:OUIExportOptionsNone] count] > 0);
            
            BOOL canMove;
            if (isViewingTrash)
                canMove = YES; // Restore from trash
            else if ([_documentStore.scopes count] > 2)
                canMove = YES; // Move between scopes
            else if (count > 1 && !isViewingTrash)
                canMove = YES; // Make new folder
            else
                canMove = NO;
            
            _exportBarButtonItem.enabled = canExport;
            _moveBarButtonItem.enabled = canMove;
            _duplicateDocumentBarButtonItem.enabled = YES;
            _deleteBarButtonItem.enabled = YES; // Deletion while in the trash is just an immediate removal.
        }
    }
}

#define TOP_CONTROLS_TOP_MARGIN 28.0
#define TOP_CONTROLS_SPACING 20.0

- (void)_setupTopControls;
{
    NSArray *availableFilters = [self availableFilters];
    BOOL willDisplayFilter = ([availableFilters count] > 1);

    CGRect topRect = CGRectZero;
    _topControls = [[UIView alloc] initWithFrame:topRect];
    
    // Sort
    if ([self supportsUpdatingSorting]) {
        // Make sure to keep these in sync with the OUIDocumentPickerItemSort enum.
        NSArray *sortTitles = @[
                                NSLocalizedStringFromTableInBundle(@"Sort by date", @"OmniUIDocument", OMNI_BUNDLE, @"sort by date"),
                                NSLocalizedStringFromTableInBundle(@"Sort by title", @"OmniUIDocument", OMNI_BUNDLE, @"sort by title")
                                ];
        UISegmentedControl *sortSegmentedControl = [[UISegmentedControl alloc] initWithItems:sortTitles];
        [sortSegmentedControl addTarget:self action:@selector(sortSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        sortSegmentedControl.selectedSegmentIndex = [[[self class] sortPreference] enumeratedValue];
        [sortSegmentedControl sizeToFit];
        
        CGRect controlFrame = sortSegmentedControl.frame;
        
        controlFrame.origin = CGPointMake(CGRectGetMaxX(topRect), TOP_CONTROLS_TOP_MARGIN);
        topRect.size.width = CGRectGetMaxX(controlFrame);
        topRect.size.height = CGRectGetHeight(controlFrame);
        sortSegmentedControl.frame = controlFrame;
        [_topControls addSubview:sortSegmentedControl];
        self.sortSegmentedControl = sortSegmentedControl;
    }
    
    // Filter
    if (willDisplayFilter) {
        NSString *identifier = [[[self class] filterPreference] stringValue];
        NSUInteger selectedIndex = [availableFilters indexOfObjectPassingTest:^BOOL(OUIDocumentPickerFilter *filter, NSUInteger idx, BOOL *stop) {
            return [filter.identifier isEqualToString:identifier];
        }];
        
        NSArray *filterTitles = [availableFilters valueForKey:@"title"];
        self.filtersSegmentedControl = [[UISegmentedControl alloc] initWithItems:filterTitles];
        [self.filtersSegmentedControl addTarget:self action:@selector(filterSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        self.filtersSegmentedControl.selectedSegmentIndex = selectedIndex;

        [self.filtersSegmentedControl sizeToFit];
        CGRect controlFrame = self.filtersSegmentedControl.frame;
        
        controlFrame.origin = CGPointMake(CGRectGetMaxX(topRect)+TOP_CONTROLS_SPACING, TOP_CONTROLS_TOP_MARGIN);
        topRect.size.width = CGRectGetMaxX(controlFrame);
        self.filtersSegmentedControl.frame = controlFrame;
        [_topControls addSubview:self.filtersSegmentedControl];
    }
    
    // Search
    if (0)
    {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setTitle:@"Search" forState:UIControlStateNormal];
        [button addTarget:self action:@selector(search:) forControlEvents:UIControlEventTouchUpInside];
        [button sizeToFit];
        CGRect controlFrame = button.frame;
        
        controlFrame.origin = CGPointMake(CGRectGetMaxX(topRect)+TOP_CONTROLS_SPACING, TOP_CONTROLS_TOP_MARGIN + (CGRectGetHeight(topRect) -CGRectGetHeight(controlFrame))/2.0);
        topRect.size.width = CGRectGetMaxX(controlFrame);
        button.frame = controlFrame;
        [_topControls addSubview:button];
    }
    topRect.size.height += TOP_CONTROLS_TOP_MARGIN;
    _topControls.frame = topRect;
    
    _mainScrollView.topControls = _topControls;
}

- (void)_sendEmailWithSubject:(NSString *)subject messageBody:(NSString *)messageBody isHTML:(BOOL)isHTML attachmentName:(NSString *)attachmentFileName data:(NSData *)attachmentData fileType:(NSString *)fileType;
{
    MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
    controller.mailComposeDelegate = self;
    [controller setSubject:subject];
    if (messageBody != nil)
        [controller setMessageBody:messageBody isHTML:isHTML];
    if (attachmentData != nil) {
        NSString *mimeType = (NSString *)CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileType, kUTTagClassMIMEType));
        OBASSERT(mimeType != nil); // The UTI's mime type should be registered in the Info.plist under UTExportedTypeDeclarations:UTTypeTagSpecification
        if (mimeType == nil)
            mimeType = @"application/octet-stream"; 

        [controller addAttachmentData:attachmentData mimeType:mimeType fileName:attachmentFileName];
    }
    
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)_deleteWithoutConfirmation:(NSSet *)selectedItems;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];

    [_documentScope deleteItems:selectedItems completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
        OBASSERT([NSThread isMainThread]); // errors array
        
        for (NSError *error in errorsOrNil)
            OUI_PRESENT_ERROR(error);
        
        [self _explicitlyRemoveItems:selectedItems];
        [lock unlock];
        [self clearSelection:YES];
    }];
}

- (void)_updateFieldsForSelectedFileItem;
{
    OBFinishPortingLater("Update the enabledness of the export/delete bar button items based on how many file items are selected");
#if 0
    _exportBarButtonItem.enabled = (proxy != nil);
    _deleteBarButtonItem.enabled = (proxy != nil);
#endif
}

- (NSMutableDictionary *)openInMapCache;
{
    if (_openInMapCache == nil) {
        _openInMapCache = [NSMutableDictionary dictionary];
    }
    
    return _openInMapCache;
}


- (BOOL)_canUseOpenInWithFileItem:(ODSFileItem *)fileItem;
{
    // Check current type.
    OBFinishPortingLater("<bug:///75843> (Add a UTI property to ODSFileItem)");
    NSString *fileType = OFUTIForFileExtensionPreferringNative(fileItem.fileURL.pathExtension, NO); // NSString *fileType = [ODAVFileInfo UTIForURL:fileItem.fileURL];
    BOOL canUseOpenInWithCurrentType = [self _canUseOpenInWithExportType:fileType];
    if (canUseOpenInWithCurrentType) {
        return YES;
    }
    
    NSArray *types = [self availableExportTypesForFileItem:fileItem serverAccount:nil exportOptionsType:OUIExportOptionsSendToApp];
    return ([types count] > 0) ? YES : NO;
}

- (void)_applicationDidEnterBackground:(NSNotification *)note;
{
    OBPRECONDITION(self.visibility == OUIViewControllerVisibilityVisible); // We only subscribe when we are visible
    
    // Only disable editing if we are not currently presenting a modal view controller.
    if (!self.presentedViewController) {
        [self setEditing:NO];
    }
    
    // Reset openInMapCache incase someone adds or delets an app.
    [self.openInMapCache removeAllObjects];
}

 - (void)_keyboardHeightWillChange:(NSNotification *)note;
{
    OUIKeyboardNotifier *notifier = [OUIKeyboardNotifier sharedNotifier];
    UIEdgeInsets insets = _mainScrollView.contentInset;
    insets.bottom = notifier.lastKnownKeyboardHeight;
    
    [UIView animateWithDuration:notifier.lastAnimationDuration delay:0 options:0 animations:^{
        [UIView setAnimationCurve:notifier.lastAnimationCurve];
        
        _mainScrollView.contentInset = insets;
        
        if (_renameSession)
            [self scrollItemToVisible:_renameSession.itemView.item animated:YES];
    } completion:nil];
}
     
- (void)_previewsUpdateForFileItemNotification:(NSNotification *)note;
{
    ODSFileItem *fileItem = [note object];

    [_mainScrollView previewsUpdatedForFileItem:fileItem];
}

- (void)_startedRenamingInItemView:(OUIDocumentPickerItemView *)itemView;
{
    // Higher level code should have already checked this.
    OBPRECONDITION(_renameSession == nil);
    OBPRECONDITION(itemView);

    self.renameSession = [[OUIDocumentRenameSession alloc] initWithDocumentPicker:self itemView:itemView];
    
    [self _updateToolbarItemsAnimated:YES];
    _topControls.userInteractionEnabled = NO;
    _mainScrollView.scrollEnabled = NO;
}

- (void)_cancelRenaming:(id)sender;
{
    [_renameSession cancelRenaming];
    self.renameSession = nil;
    
    [self _updateToolbarItemsAnimated:YES];
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

- (void)_didPerformRenameOfFolderItems:(NSSet *)folderItems;
{
    OBASSERT(folderItems);

    OUIDocumentPickerScrollView *scrollView = self.mainScrollView;

    [scrollView sortItems];
    [scrollView scrollItemsToVisible:folderItems animated:NO];
}

- (void)_moveItems:(NSSet *)items toFolder:(ODSFolderItem *)parentFolder;
{
    OBPRECONDITION(parentFolder);
    
    [self _beginIgnoringDocumentsDirectoryUpdates];
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    [_documentStore moveItems:items fromScope:_documentScope toScope:parentFolder.scope inFolder:parentFolder completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil){
        [self _explicitlyRemoveItems:movedFileItems];
        [self _endIgnoringDocumentsDirectoryUpdates];
        [self _performDelayedItemPropagationWithCompletionHandler:^{
            [lock unlock];
            [self clearSelection:YES];
            
            for (NSError *error in errorsOrNil)
                OUI_PRESENT_ALERT(error);
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
    
    [self _beginIgnoringDocumentsDirectoryUpdates];
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    [_documentStore makeFolderFromItems:items inParentFolder:_folderItem ofScope:_documentScope completionHandler:^(ODSFolderItem *createdFolder, NSArray *errorsOrNil){
        [self clearSelection:YES];
        [self _endIgnoringDocumentsDirectoryUpdates];
        [self _performDelayedItemPropagationWithCompletionHandler:^{
            if (createdFolder == nil) {
                [lock unlock];
                for (NSError *error in errorsOrNil)
                    OUI_PRESENT_ALERT(error);
                return;
            }
            
            [self scrollItemsToVisible:@[createdFolder] animated:YES completion:^{
                [lock unlock];
                
                OUIDocumentPickerItemView *itemView = [_mainScrollView itemViewForItem:createdFolder];
                OBASSERT(itemView, "<bug:///93404> (Not automatically put into rename mode for new folders created off the currently visible page of documents) -- Without an item view, we can't start renaming.");
                [itemView startRenaming];
                
                // In case only a portion of the moves worked
                for (NSError *error in errorsOrNil)
                    OUI_PRESENT_ALERT(error);
            }];
        }];
    }];
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView dragWithRecognizer:(OUIDragGestureRecognizer *)recognizer;
{
    OBPRECONDITION(scrollView == self.mainScrollView);
    
    if (recognizer.state == UIGestureRecognizerStateBegan) {

        // For now we just go into edit mode, select this item, and don't drag anything.
        OUIDocumentPickerItemView *itemView = [scrollView itemViewHitByRecognizer:recognizer];
        _setItemSelectedAndBounceView(self, itemView, YES);
#if 0 // Old/not yet finished document dragging support
        OBASSERT(_dragSession == nil);
        [_dragSession release];
        
        NSMutableSet *fileItems = [NSMutableSet setWithSet:[self selectedFileItems]];

        OUIDocumentPickerFileItemView *fileItemView = [scrollView fileItemViewHitInPreviewAreaByRecognizer:recognizer];
        ODSFileItem *fileItem = (ODSFileItem *)fileItemView.item;
        OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);
        if (fileItem)
            [fileItems addObject:fileItem];
        
        if ([fileItems count] > 0)
            _dragSession = [[OUIDocumentPickerDragSession alloc] initWithDocumentPicker:self fileItems:fileItems recognizer:recognizer];
#endif

        // We do this last since it updates the toolbar items, including the selection count.
        [self setEditing:YES animated:YES];
    }
    
    // NOTE: We do not look for ended/cancelled states here to clear out _dragSession. It sends us a -dragSessionTerminated, which will happen some time *after* these states, based on animation.
    [_dragSession handleRecognizerChange];
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

    if (scope.fileItems.count > 0)
        return nil; // Not empty
    
    if (![_documentStore.scopes containsObjectIdenticalTo:_documentScope]) {
        NSString *message = NSLocalizedStringFromTableInBundle(@"This Cloud Account no longer exists.", @"OmniUIDocument", OMNI_BUNDLE, @"empty picker because of removed account text");
        _emptyOverlayView = [OUIEmptyOverlayView overlayViewWithMessage:message buttonTitle:nil action:nil];
    } else if (!_emptyOverlayView) {
        NSString *buttonTitle = NSLocalizedStringFromTableInBundle(@"Tap here, or on the + in the toolbar, to add a document.", @"OmniUIDocument", OMNI_BUNDLE, @"empty picker button text");

        __weak OUIDocumentPickerViewController *weakSelf = self;
        _emptyOverlayView = [OUIEmptyOverlayView overlayViewWithMessage:nil buttonTitle:buttonTitle action:^{
            [weakSelf newDocument:nil];
        }];
    }
    
    return _emptyOverlayView;
}

- (void)_updateEmptyViewControlVisibility;
{
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
    
    UIView *superview = self.view;
    self->_emptyOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self->_emptyOverlayViewConstraints = @[
                                           [NSLayoutConstraint constraintWithItem:self->_emptyOverlayView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeCenterX multiplier:1 constant:0],
                                           [NSLayoutConstraint constraintWithItem:self->_emptyOverlayView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]
                                           ];
    
    [superview addSubview:emptyOverlayView];
    [superview addConstraints:self->_emptyOverlayViewConstraints];
    [superview setNeedsLayout];
}

static void _removeEmptyOverlayViewAndConstraints(OUIDocumentPickerViewController *self)
{
    OBPRECONDITION(self->_emptyOverlayViewConstraints);
    OBPRECONDITION(self->_emptyOverlayView);
    
    [self.view removeConstraints:self->_emptyOverlayViewConstraints];
    self->_emptyOverlayViewConstraints = nil;
    
    [self->_emptyOverlayView removeFromSuperview];
    self->_emptyOverlayView = nil;
    
    [self.view setNeedsLayout];
}

@synthesize filteredItems = _filteredItems;
- (void)setFilteredItems:(NSSet *)newItems;
{
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

    if (_ignoreDocumentsDirectoryUpdates == 0) {
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
                     [[OUIAppController controller] dismissActionSheetAndPopover:YES];
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
