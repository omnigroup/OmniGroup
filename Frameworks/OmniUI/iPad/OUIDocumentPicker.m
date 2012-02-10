// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPicker.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSInvocation-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreFilter.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniUI/OUIAnimationSequence.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocument.h>
#import <OmniUI/OUIDocumentPickerDelegate.h>
#import <OmniUI/OUIDocumentPickerScrollView.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIDocumentPickerFileItemView.h>
#import <OmniUI/OUIDocumentPickerGroupItemView.h>
#import <OmniUI/OUIDragGestureRecognizer.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/OUIMainViewController.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUI/OUIActionSheet.h>
#import <OmniUnzip/OUZipArchive.h>

#import "OUIDocument-Internal.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerDragSession.h"
#import "OUIDocumentPickerView.h"
#import "OUIDocumentRenameViewController.h"
#import "OUIExportOptionsController.h"
#import "OUIExportOptionsView.h"
#import "OUISheetNavigationController.h"
#import "OUISyncMenuController.h"
#import "OUIToolbarTitleButton.h"
#import "OUIFeatures.h"

RCS_ID("$Id$");


#if 0 && defined(DEBUG)
    #define PICKER_DEBUG(format, ...) NSLog(@"PICKER: " format, ## __VA_ARGS__)
#else
    #define PICKER_DEBUG(format, ...)
#endif

// OUIDocumentPickerDelegate
OBDEPRECATED_METHOD(-documentPicker:didSelectProxy:);
OBDEPRECATED_METHOD(-createNewDocumentAtURL:error:); // -createNewDocumentAtURL:completionHandler:
OBDEPRECATED_METHOD(-documentPicker:scannedProxies:); // -documentStore:scannedFileItems:
OBDEPRECATED_METHOD(-documentPicker:proxyClassForURL:); // -documentStore:fileItemClassForURL:
OBDEPRECATED_METHOD(-documentPickerBaseNameForNewFiles:); // -documentStoreBaseNameForNewFiles:;
OBDEPRECATED_METHOD(-documentPickerDocumentTypeForNewFiles:); // -documentStoreDocumentTypeForNewFiles:
OBDEPRECATED_METHOD(-documentPicker:addExportActionsToSheet:invocations:invocations); // -documentPicker:addExportActions:

OBDEPRECATED_METHOD(-documentPicker:availableExportTypesForProxy:); // proxy -> file item
OBDEPRECATED_METHOD(-documentPicker:exportFileWrapperOfType:forProxy:withCompletionHandler:); // proxy -> file item
OBDEPRECATED_METHOD(-documentPicker:PDFDataForProxy:error:); // proxy -> file item
OBDEPRECATED_METHOD(-documentPicker:PNGDataForProxy:error:); // proxy -> file item
OBDEPRECATED_METHOD(-documentPicker:cameraRollImageForProxy:); // proxy -> file item
OBDEPRECATED_METHOD(-documentPicker:printProxy:fromButton:); // proxy -> file item
OBDEPRECATED_METHOD(-documentPicker:printButtonTitleForProxy:); // proxy -> file item
OBDEPRECATED_METHOD(-documentPicker:toolbarPromptForRenamingProxy:); // proxy -> file item

OBDEPRECATED_METHOD(-availableDocumentInteractionExportTypesForFileItem:); // -availableExportTypesForFileItem:withSyncType:exportOptionType: 
OBDEPRECATED_METHOD(-availableExportTypesForFileItem:); // -availableExportTypesForFileItem:withSyncType:exportOptionType: 

static NSString * const kActionSheetExportIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.ExportAction";
static NSString * const kActionSheetDeleteIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.DeleteAction";

static NSString * const TopItemsBinding = @"topItems";
static NSString * const OpenGroupItemsBinding = @"openGroupItems";

@interface OUIDocumentPicker (/*Private*/) <MFMailComposeViewControllerDelegate, UITableViewDataSource, UITableViewDelegate, NSFilePresenter>

- (void)_updateToolbarItemsAnimated:(BOOL)animated;
- (void)_updateToolbarItemsEnabledness;
- (void)_setupTopItemsBinding;
- (void)_sendEmailWithSubject:(NSString *)subject messageBody:(NSString *)messageBody isHTML:(BOOL)isHTML attachmentName:(NSString *)attachmentFileName data:(NSData *)attachmentData fileType:(NSString *)fileType;
- (void)_deleteWithoutConfirmation:(NSSet *)fileItemsToDelete;
- (void)_updateFieldsForSelectedFileItem;
- (void)exportDocument:(id)sender;
- (void)emailDocumentChoice:(id)sender;
- (void)sendToApp:(id)sender;
- (void)printDocument:(id)sender;
- (void)copyAsImage:(id)sender;
- (void)sendToCameraRoll:(id)sender;
- (void)moveToCloud:(id)sender;
- (void)moveOutOfCloud:(id)sender;
- (BOOL)_canUseOpenInWithExportType:(NSString *)exportType;
- (BOOL)_canUseOpenInWithFileItem:(OFSDocumentStoreFileItem *)fileItem;
- (void)_applicationDidEnterBackground:(NSNotification *)note;
- (void)_previewsUpdateForFileItemNotification:(NSNotification *)note;
- (void)_startRenamingFileItem:(OFSDocumentStoreFileItem *)fileItem;
- (void)_openGroup:(OFSDocumentStoreGroupItem *)groupItem andEditTitle:(BOOL)editTitle;
- (void)_revealAndActivateNewDocumentFileItem:(OFSDocumentStoreFileItem *)createdFileItem completionHandler:(void (^)(void))completionHandler;

@property(nonatomic,copy) NSSet *topItems;
@property(nonatomic,copy) NSSet *openGroupItems;
- (void)_propagateItems:(NSSet *)items toScrollView:(OUIDocumentPickerScrollView *)scrollView withCompletionHandler:(void (^)(void))completionHandler;
- (void)_performDelayedItemPropagationWithCompletionHandler:(void (^)(void))completionHandler;

@property(nonatomic,retain) NSMutableDictionary *openInMapCache;

@end

@implementation OUIDocumentPicker
{
    id <OUIDocumentPickerDelegate> _nonretained_delegate;

    NSOperationQueue *_filePresenterQueue;
    
    OUIDocumentPickerScrollView *_topScrollView;
    OUIDocumentPickerScrollView *_groupScrollView;
    
    UIPopoverController *_filterPopoverController;
    OUIDocumentRenameViewController *_renameViewController;
    BOOL _isRevealingNewDocument;
    
    OUIReplaceDocumentAlert *_replaceDocumentAlert;
    
    BOOL _loadingFromNib;
    
    // Used to map between an exportType (UTI string) and BOOL indicating if an app exists that we can send it to via Document Interaction.
    NSMutableDictionary *_openInMapCache;
    
    CGSize _filterViewContentSize;

    UIToolbar *_toolbar;
    
    UIBarButtonItem *_duplicateDocumentBarButtonItem;
    UIBarButtonItem *_exportBarButtonItem;
    UIBarButtonItem *_deleteBarButtonItem;
    UIBarButtonItem *_appTitleToolbarItem;
    UIButton *_appTitleToolbarButton;

    OFSDocumentStore *_documentStore;
    OFSDocumentStoreFilter *_documentStoreFilter;
    NSUInteger _ignoreDocumentsDirectoryUpdates;
    
    OFSetBinding *_topItemsBinding;
    NSSet *_topItems;
    OFSetBinding *_openGroupItemsBinding;
    NSSet *_openGroupItems;
    
    OUIDocumentPickerDragSession *_dragSession;
}

static id _commonInit(OUIDocumentPicker *self)
{
    // Methods removed on this class that subclasses shouldn't be overriding any more
    OBASSERT_NOT_IMPLEMENTED(self, documentActionTitle); // The new document button is just a "+" now and we don't have the new-or-duplicate button on the doc picker
    OBASSERT_NOT_IMPLEMENTED(self, duplicateActionTitle);
    OBASSERT_NOT_IMPLEMENTED(self, deleteDocumentTitle); // -deleteDocumentTitle:, taking a count
    
    OBASSERT_NOT_IMPLEMENTED(self, editNameForDocumentURL:); // Instance method on OFSDocumentStoreItem
    OBASSERT_NOT_IMPLEMENTED(self, displayNameForDocumentURL:); // Instance method on OFSDocumentStoreItem

    self->_filePresenterQueue = [[NSOperationQueue alloc] init];
    self->_filePresenterQueue.name = @"OUIDocumentPicker NSFilePresenter notifications";
    self->_filePresenterQueue.maxConcurrentOperationCount = 1;
    
    self.filterViewContentSize = CGSizeMake(320, 110);
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    
    _loadingFromNib = YES;
    
    return _commonInit(self);
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self]; // In case -viewDidUnload isn't called.

    [_duplicateDocumentBarButtonItem release];
    [_exportBarButtonItem release];
    [_deleteBarButtonItem release];
    [_appTitleToolbarItem release];
    [_appTitleToolbarButton release];
    
    OBASSERT(_dragSession == nil); // it retains us anyway, so we can't get here otherwise

    [_openInMapCache release];
    [_topScrollView release];
    [_groupScrollView release];
    
    [_topItemsBinding invalidate];
    [_topItemsBinding release];
    [_topItems release];
    
    [_openGroupItemsBinding invalidate];
    [_openGroupItemsBinding release];
    [_openGroupItems release];
    
    if (_documentStore)
        [NSFileCoordinator removeFilePresenter:self];
    [_documentStore release];
    [_filePresenterQueue release];
    
    [_documentStoreFilter release];
    [_toolbar release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark KVC

@synthesize documentStore = _documentStore;
- (void)setDocumentStore:(OFSDocumentStore *)documentStore;
{
    OBPRECONDITION(![self isViewLoaded]); // Otherwise we'd need to fix the binding
    
    if (_documentStore == documentStore)
        return;

    if (_documentStore)
        [NSFileCoordinator removeFilePresenter:self];
    
    [_documentStore release];
    _documentStore = [documentStore retain];
    
    if (_documentStore)
        [NSFileCoordinator addFilePresenter:self];
    
    // I don't like doing this here, but it shouldn't actually change for the life of the documentPicker so...
    [_documentStoreFilter release];
    _documentStoreFilter = [[OFSDocumentStoreFilter alloc] initWithDocumentStore:_documentStore];

    // Checks whether the document store has a file type for newly created documents
    [self _updateToolbarItemsAnimated:NO];
}

@synthesize delegate = _nonretained_delegate;
@synthesize documentStoreFilter = _documentStoreFilter;
@synthesize toolbar = _toolbar;
@synthesize mainScrollView = _mainScrollView;
@synthesize groupScrollView = _groupScrollView;

- (OUIDocumentPickerScrollView *)activeScrollView;
{
    if ([_groupScrollView window])
        return _groupScrollView;
    return _mainScrollView;
}

@synthesize openInMapCache = _openInMapCache;

#pragma mark -
#pragma mark API

- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL;
{
    [self rescanDocumentsScrollingToURL:targetURL animated:(_mainScrollView.window != nil)];
}

- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL animated:(BOOL)animated;
{
    [[targetURL retain] autorelease];
    
    OBFinishPortingLater("Allow the caller to pass in a completion handler for its following work (and so it can block/unblock interactions?");
    
    // This depends on the caller to have *also* poked the file items into reloading any metadata that will be used to sort or filter them. That is, we don't reload all that info right now.
    [_documentStore scanItemsWithCompletionHandler:^{
        // We need our view if we are to do the scrolling <bug://bugs/60388> (OGS isn't restoring the the last selected document on launch)
        [self view];
        
        // <bug://bugs/60005> (Document picker scrolls to empty spot after editing file)
        [_mainScrollView.window layoutIfNeeded];
        
        OBFinishPortingLater("Show/open the group scroll view if the item is in a group?");
        OFSDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:targetURL];
        if (!fileItem)
            [_mainScrollView scrollsToTop]; // OBFinishPorting -- this is a getter
        else
            [_mainScrollView scrollItemToVisible:fileItem animated:animated];
        
        // TODO: Needed?
        [_mainScrollView setNeedsLayout];
    }];
}

- (void)rescanDocuments;
{
    [self rescanDocumentsScrollingToURL:nil];
}

- (NSSet *)selectedFileItems;
{
    return [_documentStore.fileItems select:^(id obj){
        OFSDocumentStoreFileItem *fileItem = obj;
        return fileItem.selected;
    }];
}

- (NSUInteger)selectedFileItemCount;
{
    NSUInteger selectedCount = 0;
    
    for (OFSDocumentStoreFileItem *fileItem in _documentStore.fileItems)
        if (fileItem.selected)
            selectedCount++;
    
    return selectedCount;
}

- (void)clearSelection:(BOOL)shouldEndEditing;
{
    for (OFSDocumentStoreFileItem *fileItem in _documentStore.fileItems) {
        OUIWithoutAnimating(^{
            fileItem.selected = NO;
            [self.view layoutIfNeeded];
        });
    }
    
    if (shouldEndEditing) {
        [self setEditing:NO animated:YES];
        return;
    }
    
    [self _updateToolbarItemsEnabledness];
}

- (OFSDocumentStoreFileItem *)singleSelectedFileItem;
{
    NSSet *selectedFileItems = self.selectedFileItems;
    
    // Ensure we have one and only one selected file item.
    if ([selectedFileItems count] != 1){
        OBASSERT_NOT_REACHED("We should only have one file item in selectedFileItems at this point.");
        return nil;
    }
    
    return [selectedFileItems anyObject];
}

- (BOOL)canEditFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    OBFinishPortingLater("Needs to allow deleting iCloud stuff, which isn't in the user documents directory");
    return YES;
#if 0
    NSString *documentsPath = [[[self class] userDocumentsDirectory] stringByExpandingTildeInPath];
    if (![documentsPath hasSuffix:@"/"])
        documentsPath = [documentsPath stringByAppendingString:@"/"];
    
    NSString *filePath = [[[fileItem.url absoluteURL] path] stringByExpandingTildeInPath];
    return [filePath hasPrefix:documentsPath];
#endif
}

- (void)scrollToTopAnimated:(BOOL)animated;
{
    OUIDocumentPickerScrollView *scrollView = self.activeScrollView;
    
    UIEdgeInsets insets = scrollView.contentInset;
    [scrollView setContentOffset:CGPointMake(-insets.left, -insets.top) animated:animated];
}

- (void)scrollItemToVisible:(OFSDocumentStoreItem *)item animated:(BOOL)animated;
{
    [self.activeScrollView scrollItemToVisible:item animated:animated];
}

- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated;
{
    [self.activeScrollView scrollItemsToVisible:items animated:animated];
}

- (BOOL)okayToOpenMenu;
{
    return (!_isRevealingNewDocument && self.parentViewController != nil);  // will still be the inner controller while scrolling to the new doc
}

- (IBAction)newDocument:(id)sender;
{
    OBPRECONDITION(_renameViewController == nil); // Can't be renaming right now, so need to try to stop

    if (![self okayToOpenMenu])
        return;
    
    // Get rid of any visible popovers immediately
    [[OUIAppController controller] dismissPopoverAnimated:NO];
    
    [self _beginIgnoringDocumentsDirectoryUpdates];
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    [_documentStore createNewDocument:^(OFSDocumentStoreFileItem *createdFileItem, NSError *error){

        if (!createdFileItem) {
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            [self _endIgnoringDocumentsDirectoryUpdates];
            OUI_PRESENT_ERROR(error);
            return;
        }
        
        _isRevealingNewDocument = YES;
        
        // We want the file item to have a new date, but this is the wrong place to do it. Want to do it in the document picker before it creates the item.
        // [[NSFileManager defaultManager] touchItemAtURL:createdItem.fileURL error:NULL];
        
        [self _revealAndActivateNewDocumentFileItem:createdFileItem completionHandler:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            [self _endIgnoringDocumentsDirectoryUpdates];
        }];
    }];
}

- (void)_duplicateFileItemsWithoutConfirmation:(NSSet *)selectedFileItems;
{
    NSMutableArray *duplicateFileItems = [NSMutableArray array];
    NSMutableArray *errors = [NSMutableArray array];
    
    // We'll update once at the end
    [self _beginIgnoringDocumentsDirectoryUpdates];
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    for (OFSDocumentStoreFileItem *fileItem in selectedFileItems) {
        // The queue is concurrent, so we need to remember all the enqueued blocks and make them dependencies of our completion
        [_documentStore addDocumentFromURL:fileItem.fileURL option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
            OBASSERT([NSThread isMainThread]); // gets enqueued on the main thread, but even if it was invoked on the background serial queue, this would be OK as long as we don't access the mutable arrays until all the blocks are done
            
            if (!duplicateFileItem) {
                OBASSERT(error);
                if (error) // let's not crash, though...
                    [errors addObject:error];
                return;
            }
            
            [duplicateFileItems addObject:duplicateFileItem];
            
            // Copy the previews for the original file item to be the previews for the duplicate.
            [OUIDocumentPreview cachePreviewImagesForFileURL:duplicateFileItem.fileURL date:duplicateFileItem.date
                                    byDuplicatingFromFileURL:fileItem.fileURL date:fileItem.date];

        }];
    }
    
    // Wait for all the duplications to complete
    [_documentStore afterAsynchronousFileAccessFinishes:^{
        [self _endIgnoringDocumentsDirectoryUpdates];
        
        // We should have heard about the new file items; if we haven't, we can't propagate them to our scroll view correctly
#ifdef OMNI_ASSERTIONS_ON
        {
            NSSet *items = _openGroupItemsBinding ? _openGroupItems : _topItems;
            for (OFSDocumentStoreFileItem *fileItem in duplicateFileItems)
                OBASSERT([items member:fileItem] == fileItem);
        }
#endif
        [self clearSelection:YES];            
        [self _performDelayedItemPropagationWithCompletionHandler:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            
            // Make sure the duplicate items made it into the scroll view.
            for (OFSDocumentStoreFileItem *fileItem in duplicateFileItems)
                OBASSERT([self.activeScrollView.items member:fileItem] == fileItem);
            
            
            [self scrollItemsToVisible:duplicateFileItems animated:YES];
        }];
        
        // This may be annoying if there were several errors, but it is misleading to not do it...
        for (NSError *error in errors)
            OUI_PRESENT_ALERT(error);
    }];
}

- (IBAction)duplicateDocument:(id)sender;
{
    [[OUIAppController controller] dismissActionSheetAndPopover:YES];
    
    NSSet *selectedFileItems = self.selectedFileItems;
    NSUInteger fileItemCount = [selectedFileItems count];
    
    switch (fileItemCount) {
        case 0:
            OBASSERT_NOT_REACHED("Make this button be disabled");
            return;
        case 1:
            [self _duplicateFileItemsWithoutConfirmation:selectedFileItems];
            break;
        default: {
            OUIActionSheet *prompt = [[OUIActionSheet alloc] initWithIdentifier:nil];
            
            NSString *format = nil;
            if ([_nonretained_delegate respondsToSelector:@selector(documentPickerAlertTitleFormatForDuplicatingFileItems:)])
                format = [_nonretained_delegate documentPickerAlertTitleFormatForDuplicatingFileItems:selectedFileItems];
            if ([NSString isEmptyString:format])
                format = NSLocalizedStringFromTableInBundle(@"Duplicate %ld Documents", @"OmniUI", OMNI_BUNDLE, @"title for alert option confirming duplication of multiple files");
            OBASSERT([format containsString:@"%ld"]);

            [prompt addButtonWithTitle:[NSString stringWithFormat:format, fileItemCount] forAction:^{
                [self _duplicateFileItemsWithoutConfirmation:selectedFileItems];
            }];
            [[OUIAppController controller] showActionSheet:prompt fromSender:sender animated:NO];
            [prompt release];
        }
    }
}

- (void)replaceDocumentAlert:(OUIReplaceDocumentAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex documentURL:(NSURL *)documentURL;
{
    // TODO: Would like to find a better way to code this so we don't have so much duplicated.
    switch (buttonIndex) {
        case 0: /* Cancel */
            break;
        
        case 1: /* Replace */
        {
            [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
            [_documentStore addDocumentFromURL:documentURL option:OFSDocumentStoreAddByReplacing completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
                if (!duplicateFileItem) {
                    OUI_PRESENT_ERROR(error);
                    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                    return;
                }
                
                [self _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                }];
            }];
            break;
        }
        case 2: /* Rename */
        {
            [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
            [_documentStore addDocumentFromURL:documentURL option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
                if (!duplicateFileItem) {
                    OUI_PRESENT_ERROR(error);
                    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                    return;
                }
                
                [self _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
                    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                }];
            }];
            break;
        }
        default:
            break;
    }
    
    [_replaceDocumentAlert release];
    _replaceDocumentAlert = nil;
}

- (void)addDocumentFromURL:(NSURL *)url;
{
    if ([_documentStore userFileExistsWithFileNameOfURL:url]) {
        // If a file with the same name already exists, we need to ask the user if they want to cancel, replace, or rename the document.
        OBASSERT(_replaceDocumentAlert == nil); // this should never happen
        _replaceDocumentAlert = [[OUIReplaceDocumentAlert alloc] initWithDelegate:self documentURL:url];
        [_replaceDocumentAlert show];
        return;
    }
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    [_documentStore addDocumentFromURL:url option:OFSDocumentStoreAddNormally completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
        if (!duplicateFileItem) {
            OUI_PRESENT_ERROR(error);
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            return;
        }
        
        [self _revealAndActivateNewDocumentFileItem:duplicateFileItem completionHandler:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        }];
    }];
}

- (void)exportedDocumentToURL:(NSURL *)url;
{
    [self rescanDocuments];
    [self clearSelection:YES];
}

- (NSArray *)availableExportTypesForFileItem:(OFSDocumentStoreFileItem *)fileItem withSyncType:(OUISyncType)syncType exportOptionsType:(OUIExportOptionsType)exportOptionsType;
{
    NSMutableArray *exportTypes = [NSMutableArray array];
    
    // Get All Available Export Types
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:availableExportTypesForFileItem:withSyncType:exportOptionsType:)]) {
        [exportTypes addObjectsFromArray:[_nonretained_delegate documentPicker:self availableExportTypesForFileItem:fileItem withSyncType:syncType exportOptionsType:exportOptionsType]];
    } else {
        // PDF PNG Fallbacks
        BOOL canMakePDF = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)];
        BOOL canMakePNG = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)];
        if (canMakePDF)
            [exportTypes addObject:(NSString *)kUTTypePDF];
        if (canMakePNG)
            [exportTypes addObject:(NSString *)kUTTypePNG];
    }
    
    if ((syncType == OUISyncTypeNone) &&
        (exportOptionsType == OUIExportOptionsNone)) {
        // We're just looking for a rough count of how export types are available. Let's just return what we have.
        return exportTypes;
    }
    
    // Using Send To App
    if (exportOptionsType == OUIExportOptionsSendToApp) {
        NSMutableArray *docInteractionExportTypes = [NSMutableArray array];
        
        // check our own type here
        OBFinishPortingLater("<bug:///75843> (Add a UTI property to OFSDocumentStoreFileItem)");
        if ([self _canUseOpenInWithExportType:OFUTIForFileExtensionPreferringNative([fileItem.fileURL pathExtension], NO)]) // if ([self _canUseOpenInWithExportType:[OFSFileInfo UTIForURL:fileItem.fileURL]])
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

- (NSArray *)availableImageExportTypesForFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    NSMutableArray *imageExportTypes = [NSMutableArray array];
    NSArray *exportTypes = [self availableExportTypesForFileItem:fileItem withSyncType:OUISyncTypeNone exportOptionsType:OUIExportOptionsNone];
    for (NSString *exportType in exportTypes) {
        if (OFNOTNULL(exportType) &&
            UTTypeConformsTo((CFStringRef)exportType, kUTTypeImage)) {
                [imageExportTypes addObject:exportType];
        }
    }
    return imageExportTypes;
}

- (BOOL)isExportThreadSafe;
{
    return YES;
}

// Helper method for -availableDocuentInteractionExportTypesForFileItem:
- (BOOL)_canUseOpenInWithExportType:(NSString *)exportType;
{
    NSNumber *value = [self.openInMapCache objectForKey:exportType];
    if (value) {
        // We have a cached value, so immediately return it.
        return [value boolValue];
    }
    
    // We don't have a cache for this exportType. We need to do our Doc Interaction hack to find out if this export type has an available app to send to.
    OUISingleDocumentAppController *sharedAppDelegate = (OUISingleDocumentAppController *)[UIApplication sharedApplication].delegate;
    UIWindow *mainWindow = sharedAppDelegate.window;
    
    NSString *tempDirectory = NSTemporaryDirectory();
    
    NSError *error = nil;
    OFSFileManager *tempFileManager = [[[OFSFileManager alloc] initWithBaseURL:[NSURL fileURLWithPath:tempDirectory isDirectory:YES] error:&error] autorelease];
    if (error) {
        OUI_PRESENT_ERROR(error);
        return NO;
    }

    NSString *dummyPath = [tempDirectory stringByAppendingPathComponent:@"dummy"];
    BOOL isDirectory = YES;
    if (!UTTypeConformsTo((CFStringRef)exportType, kUTTypeDirectory)) {
        isDirectory = NO;
        NSString *owned_UTIExtension = (NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)exportType, kUTTagClassFilenameExtension);
        
        if (owned_UTIExtension) {
            dummyPath = [dummyPath stringByAppendingPathExtension:owned_UTIExtension];
        }
        
        [owned_UTIExtension release];
    }
    
    // First check to see if the dummyURL already exists.
    NSURL *dummyURL = [NSURL fileURLWithPath:dummyPath isDirectory:isDirectory];
    OFSFileInfo *dummyInfo = [tempFileManager fileInfoAtURL:dummyURL error:&error];
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
    
    return success;
}

- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(OFSDocumentStoreFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
{
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:exportFileWrapperOfType:forFileItem:withCompletionHandler:)]) {
        [_nonretained_delegate documentPicker:self exportFileWrapperOfType:exportType forFileItem:fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            if (completionHandler) {
                completionHandler(fileWrapper, error);
            }
        }];
        return;
    }
    
    // If the delegate doesn't implement the new file wrapper export API, try the older NSData API
    NSData *fileData = nil;
    NSString *pathExtension = nil;
    NSError *error = nil;
    
    if (UTTypeConformsTo((CFStringRef)exportType, kUTTypePDF) && [_nonretained_delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)]) {
        fileData = [_nonretained_delegate documentPicker:self PDFDataForFileItem:fileItem error:&error];
        pathExtension = @"pdf";
    } else if (UTTypeConformsTo((CFStringRef)exportType, kUTTypePNG) && [_nonretained_delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)]) {
        fileData = [_nonretained_delegate documentPicker:self PNGDataForFileItem:fileItem error:&error];
        pathExtension = @"png";
    }
    
    if (fileData == nil)
        completionHandler(nil, error);
    
    NSFileWrapper *fileWrapper = [[[NSFileWrapper alloc] initRegularFileWithContents:fileData] autorelease];
    fileWrapper.preferredFilename = [fileItem.name stringByAppendingPathExtension:pathExtension];
    
    if (completionHandler) {
        completionHandler(fileWrapper, error);
    }
}

- (UIImage *)_iconForUTI:(NSString *)fileUTI targetSize:(NSUInteger)targetSize;
{
    // UIDocumentInteractionController seems to only return a single icon.
    CFDictionaryRef utiDecl = UTTypeCopyDeclaration((CFStringRef)fileUTI);
    if (utiDecl) {
        // Look for an icon with the specified size.
        CFArrayRef iconFiles = CFDictionaryGetValue(utiDecl, CFSTR("UTTypeIconFiles"));
        NSString *sizeString = [NSString stringWithFormat:@"%lu", targetSize]; // This is a little optimistic, but unlikely to fail.
        for (NSString *iconName in (NSArray *)iconFiles) {
            if ([iconName rangeOfString:sizeString].location != NSNotFound) {
                UIImage *image = [UIImage imageNamed:iconName];
                if (image) {
                    CFRelease(utiDecl);
                    return image;
                }
            }
        }
        CFRelease(utiDecl);
    }
    
    if (UTTypeConformsTo((CFStringRef)fileUTI, kUTTypePDF)) {
        UIImage *image = [UIImage imageNamed:@"OUIPDF.png"];
        if (image)
            return image;
    }
    if (UTTypeConformsTo((CFStringRef)fileUTI, kUTTypePNG)) {
        UIImage *image = [UIImage imageNamed:@"OUIPNG.png"];
        if (image)
            return image;
    }
    
    
    // Might be a system type.
    UIDocumentInteractionController *documentInteractionController = [[UIDocumentInteractionController alloc] init];
    documentInteractionController.UTI = fileUTI;
    if (documentInteractionController.icons.count == 0) {
        CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)fileUTI, kUTTagClassFilenameExtension);
        if (extension != NULL) {
            documentInteractionController.name = [@"Untitled" stringByAppendingPathExtension:(NSString *)extension];
            CFRelease(extension);
        }
        if (documentInteractionController.icons.count == 0) {
            documentInteractionController.UTI = nil;
            documentInteractionController.name = @"Untitled";
        }
    }

    OBASSERT(documentInteractionController.icons.count != 0); // Or we should attach our own default icon
    UIImage *bestImage = nil;
    for (UIImage *image in documentInteractionController.icons) {
        if (CGSizeEqualToSize(image.size, CGSizeMake(targetSize, targetSize))) {
            bestImage = image; // This image fits our target size
            break;
        }
    }

    if (bestImage == nil)
        bestImage = [documentInteractionController.icons lastObject];

    [documentInteractionController release];

    if (bestImage != nil)
        return bestImage;
    else
        return [UIImage imageNamed:@"OUIDocument.png"];
}

- (UIImage *)iconForUTI:(NSString *)fileUTI;
{
    UIImage *icon = nil;
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:iconForUTI:)])
        icon = [_nonretained_delegate documentPicker:self iconForUTI:(CFStringRef)fileUTI];
    if (icon == nil)
        icon = [self _iconForUTI:fileUTI targetSize:32];
    return icon;
}

- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
{
    UIImage *icon = nil;
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:exportIconForUTI:)])
        icon = [_nonretained_delegate documentPicker:self exportIconForUTI:(CFStringRef)fileUTI];
    if (icon == nil)
        icon = [self _iconForUTI:fileUTI targetSize:128];
    return icon;
}

- (NSString *)exportLabelForUTI:(NSString *)fileUTI;
{
    NSString *customLabel = nil;
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:labelForUTI:)])
        customLabel = [_nonretained_delegate documentPicker:self labelForUTI:(CFStringRef)fileUTI];
    if (customLabel != nil)
        return customLabel;
    if (UTTypeConformsTo((CFStringRef)fileUTI, kUTTypePDF))
        return @"PDF";
    if (UTTypeConformsTo((CFStringRef)fileUTI, kUTTypePNG))
        return @"PNG";
    return nil;
}

- (NSString *)deleteDocumentTitle:(NSUInteger)count;
{
    OBPRECONDITION(count > 0);
    
    if (count == 1)
        return NSLocalizedStringFromTableInBundle(@"Delete Document", @"OmniUI", OMNI_BUNDLE, @"delete button title");
    return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Delete %ld Documents", @"OmniUI", OMNI_BUNDLE, @"delete button title"), count];
}

- (IBAction)deleteDocument:(id)sender;
{
    NSSet *fileItemsToDelete = [[self selectedFileItems] select:^(id obj){
        return [self canEditFileItem:obj];
    }];
    
    if ([fileItemsToDelete count] == 0) {
        OBASSERT_NOT_REACHED("Delete toolbar item shouldn't have been enabled");
        return;
    }
    
    if (![self okayToOpenMenu])
        return;

    OUIActionSheet *actionSheet = [[[OUIActionSheet alloc] initWithIdentifier:kActionSheetDeleteIdentifier] autorelease];
    [actionSheet setDestructiveButtonTitle:[self deleteDocumentTitle:[fileItemsToDelete count]]
                                 andAction:^{
                                     [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
                                     [self _deleteWithoutConfirmation:fileItemsToDelete];
                                 }];


    [[OUIAppController controller] showActionSheet:actionSheet fromSender:sender animated:YES];
}

- (NSString *)printTitle;
// overridden by Graffle to return "Print (landscape) or Print (portrait)"
{
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:printButtonTitleForFileItem:)]) {
        return [_nonretained_delegate documentPicker:self printButtonTitleForFileItem:nil];
    }
    
    return NSLocalizedStringFromTableInBundle(@"Print", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view");
}

- (IBAction)export:(id)sender;
{
    if (![self okayToOpenMenu])
        return;

    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem){
        OBASSERT_NOT_REACHED("Make this button be disabled");
        return;
    }
    
    NSURL *url = fileItem.fileURL;
    if (url == nil)
        return;

    OUIActionSheet *actionSheet = [[[OUIActionSheet alloc] initWithIdentifier:kActionSheetExportIdentifier] autorelease];
    
    BOOL canExport = [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"OUIExportEnabled"];
    NSArray *availableExportTypes = [self availableExportTypesForFileItem:fileItem withSyncType:OUISyncTypeNone exportOptionsType:OUIExportOptionsNone];
    NSArray *availableImageExportTypes = [self availableImageExportTypesForFileItem:fileItem];
    BOOL canSendToCameraRoll = [_nonretained_delegate respondsToSelector:@selector(documentPicker:cameraRollImageForFileItem:)];
    BOOL canPrint = NO;
    BOOL canUseOpenIn = [self _canUseOpenInWithFileItem:fileItem];
    BOOL ubiquityEnabled = [OFSDocumentStore isUbiquityAccessEnabled];
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:printFileItem:fromButton:)])
        if ([UIPrintInteractionController isPrintingAvailable])  // "Some iOS devices do not support printing"
            canPrint = YES;
    
    OB_UNUSED_VALUE(availableExportTypes); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning

    if ([MFMailComposeViewController canSendMail]) {
        // All email options should go here (within the test for whether we can send email)
        // more than one option? Display the 'export options sheet'
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  if (availableExportTypes.count > 0)
                                      [self emailDocumentChoice:self];
                                  else
                                      [self emailDocument:self];
                              }];
    }
    
    if (canExport) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Export", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  [self exportDocument:self];
                              }];
    }
    
    if (canUseOpenIn) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send to App", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  [self sendToApp:self];
                              }];
    }
    
    if (availableImageExportTypes.count > 0) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Copy as Image", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  [self copyAsImage:self];
        }];
    }
    
    if (canSendToCameraRoll) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send to Photos", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  [self sendToCameraRoll:self];
                              }];
    }
    
    if (canPrint) {
        NSString *printTitle = [self printTitle];
        [actionSheet addButtonWithTitle:printTitle
                              forAction:^{
                                  [self printDocument:self];
                              }];
    }

    if (ubiquityEnabled) {
        // OBFinishPorting: decide on real UI for this
        {
            BOOL isUbiquitous = [[NSFileManager defaultManager] isUbiquitousItemAtURL:url];
            
            if (!isUbiquitous) {
                [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Move to iCloud", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                                      forAction:^{
                                          [self moveToCloud:self];
                                      }];
            } else {
                // We only want to display the 'Move out of iCloud' option if the file has been fully downloaded locally.
                NSNumber *isDownloadedValue = nil;
                NSError *error = nil;
                if (![url getResourceValue:&isDownloadedValue forKey:NSURLUbiquitousItemIsDownloadedKey error:&error]) {
                    NSLog(@"Failed to query URL for NSURLUbiquitousItemIsDownloadedKey: %@", [error toPropertyList]);
                    isDownloadedValue = [NSNumber numberWithBool:NO]; // Don't show the option if we don't know for sure.
                }
                
                if ([isDownloadedValue boolValue]) {
                    [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Move out of iCloud", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                                          forAction:^{
                                              [self moveOutOfCloud:self];
                                          }];
                }
            }
        }
    }
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:addExportActions:)]) {
        [_nonretained_delegate documentPicker:self addExportActions:^(NSString *title, void (^action)(void)){
            [actionSheet addButtonWithTitle:title
                                  forAction:action];
        }];
     }
    
    [[OUIAppController controller] showActionSheet:actionSheet fromSender:sender animated:YES];
}

static void _setSelectedDocumentsInCloud(OUIDocumentPicker *self, BOOL toCloud)
{
    // The move to iCloud will happen on a background thread; don't let the user muck with documents while it is happening.
    OBASSERT([NSThread isMainThread]);
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    [self->_documentStore moveFileItems:self.selectedFileItems toCloud:toCloud completionHandler:^(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil) {
        OBASSERT([NSThread isMainThread]);
        
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        [self clearSelection:YES];

        if (failingItem) {
            NSLog(@"Failed to move %@ toCloud:%d: %@", [failingItem shortDescription], toCloud, errorOrNil);
            OUI_PRESENT_ALERT(errorOrNil);
        }
    }];
}

- (void)moveToCloud:(id)sender;
{
    _setSelectedDocumentsInCloud(self, YES);
}

- (void)moveOutOfCloud:(id)sender;
{
    _setSelectedDocumentsInCloud(self, NO);
}

- (IBAction)emailDocument:(id)sender;
{
    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    NSData *documentData = [fileItem emailData];
    NSString *documentFilename = [fileItem emailFilename];
    OBFinishPortingLater("<bug:///75843> (Add a UTI property to OFSDocumentStoreFileItem)");
    NSString *documentType = OFUTIForFileExtensionPreferringNative([documentFilename pathExtension], NO); // NSString *documentType = [OFSFileInfo UTIForFilename:documentFilename];
    OBASSERT(documentType != nil); // UTI should be registered in the Info.plist under CFBundleDocumentTypes

    [self _sendEmailWithSubject:[fileItem name] messageBody:nil isHTML:NO attachmentName:documentFilename data:documentData fileType:documentType];
}

- (BOOL)_canUseEmailBodyForExportType:(NSString *)exportType;
{
    return ![_nonretained_delegate respondsToSelector:@selector(documentPicker:canUseEmailBodyForType:)] || [_nonretained_delegate documentPicker:self canUseEmailBodyForType:exportType];
}

- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType;
{
    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
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
                NSString *documentType = OFUTIForFileExtensionPreferringNative(childWrapper.preferredFilename.pathExtension, childWrapper.isDirectory);
                if (UTTypeConformsTo((CFStringRef)documentType, kUTTypeHTML)) {
                    if ([self _canUseEmailBodyForExportType:exportType]) {
                        NSString *messageBody = [[[NSString alloc] initWithData:[childWrapper regularFileContents] encoding:NSUTF8StringEncoding] autorelease];
                        if (messageBody != nil) {
                            [self _sendEmailWithSubject:fileItem.name messageBody:messageBody isHTML:YES attachmentName:nil data:nil fileType:nil];
                            return;
                        }
                    } else {
                        // Though we're not sending this as the HTML body, we really only need to attach the HTML itself
                        // When we try to change the preferredFilename on the childWrapper we are getting a '*** Collection <NSConcreteHashTable: 0x58b59b0> was mutated while being enumerated.' error. Tim and I tried a few things to get past this but decided to create a new NSFileWrapper.
                        NSFileWrapper *singleChildFileWrapper = [[[NSFileWrapper alloc] initRegularFileWithContents:[childWrapper regularFileContents]] autorelease];
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
        if (UTTypeConformsTo((CFStringRef)emailType, kUTTypePlainText)) {
            // Plain text? Let's send that as the message body
            if ([self _canUseEmailBodyForExportType:exportType]) {
                NSString *messageBody = [[[NSString alloc] initWithData:emailData encoding:NSUTF8StringEncoding] autorelease];
                if (messageBody != nil) {
                    [self _sendEmailWithSubject:fileItem.name messageBody:messageBody isHTML:NO attachmentName:nil data:nil fileType:nil];
                    return;
                }
            }
        }
    } else {
        NSError *error = nil;
        emailName = [fileWrapper.preferredFilename stringByAppendingPathExtension:@"zip"];
        emailType = OFUTIForFileExtensionPreferringNative(@"zip", NO);
        NSString *zipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:emailName];
        OMNI_POOL_START {
            if (![OUZipArchive createZipFile:zipPath fromFileWrappers:[NSArray arrayWithObject:fileWrapper] error:&error]) {
                OUI_PRESENT_ERROR(error);
                return;
            }
        } OMNI_POOL_END;
        emailData = [NSData dataWithContentsOfMappedFile:zipPath];
    }
    
    [self _sendEmailWithSubject:fileItem.name messageBody:nil isHTML:NO attachmentName:emailName data:emailData fileType:emailType];
}

- (void)emailExportType:(NSString *)exportType;
{
    OMNI_POOL_START {
        [self exportFileWrapperOfType:exportType forFileItem:self.singleSelectedFileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            if (fileWrapper == nil) {
                OUI_PRESENT_ERROR(error);
                return;
            }
            [self sendEmailWithFileWrapper:fileWrapper forExportType:exportType];
        }];
    } OMNI_POOL_END;
}

- (void)exportDocument:(id)sender;
{
    [OUISyncMenuController displayInSheet];
}

- (void)emailDocumentChoice:(id)sender;
{
    OUIExportOptionsController *exportController = [[OUIExportOptionsController alloc] initWithExportType:OUIExportOptionsEmail];
    OUISheetNavigationController *navigationController = [[OUISheetNavigationController alloc] initWithRootViewController:exportController];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    OUIAppController *appController = [OUIAppController controller];
    [appController.topViewController presentModalViewController:navigationController animated:YES];
    
    [navigationController release];
    [exportController release];
}

- (void)sendToApp:(id)sender;
{
    OUIExportOptionsController *exportOptionsController = [[OUIExportOptionsController alloc] initWithExportType:OUIExportOptionsSendToApp];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:[exportOptionsController autorelease]];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [self presentModalViewController:navController animated:YES];
    [navController release];
}

- (void)printDocument:(id)sender;
{
    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    [_nonretained_delegate documentPicker:self printFileItem:fileItem fromButton:_exportBarButtonItem];
}

- (void)copyAsImage:(id)sender;
{
    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    NSMutableArray *items = [NSMutableArray array];

    BOOL canMakeCopyAsImageSpecificPDF = [_nonretained_delegate respondsToSelector:@selector(documentPicker:copyAsImageDataForFileItem:error:)];
    BOOL canMakePDF = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)];
    BOOL canMakePNG = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)];

    //- (NSData *)documentPicker:(OUIDocumentPicker *)picker copyAsImageDataForFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
    if (canMakeCopyAsImageSpecificPDF) {
        NSError *error = nil;
        NSData *pdfData = [_nonretained_delegate documentPicker:self copyAsImageDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    } else if (canMakePDF) {
        NSError *error = nil;
        NSData *pdfData = [_nonretained_delegate documentPicker:self PDFDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    }
    
    // Don't put more than one image format on the pasteboard, because both will get pasted into iWork.  <bug://bugs/61070>
    if (!canMakeCopyAsImageSpecificPDF &&!canMakePDF && canMakePNG) {
        NSError *error = nil;
        NSData *pngData = [_nonretained_delegate documentPicker:self PNGDataForFileItem:fileItem error:&error];
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
    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    UIImage *image = [_nonretained_delegate documentPicker:self cameraRollImageForFileItem:fileItem];
    OBASSERT(image); // There is no default implementation -- the delegate should return something.

    if (image)
        UIImageWriteToSavedPhotosAlbum(image, self, @selector(_sendToCameraRollImage:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)_sendToCameraRollImage:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
{
    OUI_PRESENT_ERROR(error);
}

@synthesize filterViewContentSize = _filterViewContentSize;
- (IBAction)filterAction:(UIView *)sender;
{
    if (![self okayToOpenMenu])
        return;
    
/*
    if (skipAction)
        return;
*/
    
    OBASSERT(_renameViewController == nil); // Can't be renaming now; no need to try to stop.
    
    if (_filterPopoverController && [_filterPopoverController isPopoverVisible]) {
        [_filterPopoverController dismissPopoverAnimated:YES];
        [_filterPopoverController release];
        _filterPopoverController = nil;
        return;
    }

    UITableViewController *table = [[UITableViewController alloc] initWithStyle:UITableViewStyleGrouped];
    UITableView *tableView = table.tableView;
    tableView.autoresizingMask = 0;
    [tableView setDelegate:self];
    [tableView setDataSource:self];

    [tableView reloadData];
    OUITableViewAdjustHeightToFitContents(tableView);
    tableView.scrollEnabled = NO;

    [table setContentSizeForViewInPopover:_filterViewContentSize];
    // [table setContentSizeForViewInPopover:[[table tableView] rectForSection:0].size];
    _filterPopoverController = [[UIPopoverController alloc] initWithContentViewController:table];
    [table release];
    
    [[OUIAppController controller] presentPopover:_filterPopoverController fromRect:[sender frame] inView:[sender superview] permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

+ (OFPreference *)sortPreference;
{
    static OFPreference *SortPreference = nil;
    if (SortPreference == nil) {
        OFEnumNameTable *enumeration = [[OFEnumNameTable alloc] initWithDefaultEnumValue:OUIDocumentPickerItemSortByDate];
        [enumeration setName:@"name" forEnumValue:OUIDocumentPickerItemSortByName];
        [enumeration setName:@"date" forEnumValue:OUIDocumentPickerItemSortByDate];
        SortPreference = [[OFPreference preferenceForKey:@"OUIDocumentPickerSortKey" enumeration:enumeration] retain];
        [enumeration release];
    }
    return SortPreference;
}

- (void)updateSort;
{
    OUIDocumentPickerItemSort sort = [[[self class] sortPreference] enumeratedValue];
    _mainScrollView.itemSort = sort;
    _groupScrollView.itemSort = sort;
}

- (NSString *)mainToolbarTitle;
{
    if ([_nonretained_delegate respondsToSelector:@selector(documentPickerMainToolbarTitle:)]) {
        return [_nonretained_delegate documentPickerMainToolbarTitle:self];
    }
    
    return NSLocalizedStringWithDefaultValue(@"Documents <main toolbar title>", @"OmniUI", OMNI_BUNDLE, @"Documents", @"Main toolbar title");
}

- (void)updateTitle;
{    
    NSString *title = [self mainToolbarTitle];
    
    // Had to add a space after the title to make padding between the title and the image. I tried using UIEdgeInsets on the image, title and content but could not get it to work horizontally. I did, however, get it to work to vertically align the image.
    [_appTitleToolbarButton setTitle:[title stringByAppendingString:@" "] forState:UIControlStateNormal];
    [_appTitleToolbarButton sizeToFit];
    [_appTitleToolbarButton layoutIfNeeded];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    _toolbar.items = self.toolbarItems;

    BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
    
    CGRect viewBounds = self.view.bounds;
    _mainScrollView.frame = viewBounds;
    _mainScrollView.landscape = landscape;
    
    _groupScrollView.landscape = landscape;
    [_groupScrollView removeFromSuperview]; // We'll put it back when opening a group
    
    [self updateSort];
    
    [self _setupTopItemsBinding];

    // We sign up for this notification in -viewDidLoad, instead of -viewWillAppear: since we want to receive it when we are off screen (previews can be updated when a document is closing and we never get on screen -- for example if a document is open and another document is opened via tapping on Mail).
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_previewsUpdateForFileItemNotification:) name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    OBASSERT(_dragSession == nil); // No idea how we'd get here, but just in case
    [_dragSession release];
    _dragSession = nil;
    
    [_mainScrollView release];
    _mainScrollView = nil;
    
    [_topItemsBinding invalidate];
    [_topItemsBinding release];
    _topItemsBinding = nil;
    [_topItems release];
    _topItems = nil;
    
    [_groupScrollView release];
    _groupScrollView = nil;
    
    [_openGroupItemsBinding invalidate];
    [_openGroupItemsBinding release];
    _openGroupItemsBinding = nil;

    [_openGroupItems release];
    _openGroupItems = nil;
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
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

    if (_groupScrollView.superview) {
        [_groupScrollView willRotateWithDuration:duration];
        _groupScrollView.landscape = landscape;
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
{
    [_mainScrollView didRotate];
    
    if (_groupScrollView.superview)
        [_groupScrollView didRotate];

    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

- (void)willMoveToParentViewController:(UIViewController *)parent;
{
    [super willMoveToParentViewController:parent];
    
    // Start out with the right grid size. Also, the device might be rotated while we a document was open and we weren't in the view controller tree
    if (parent) {
        BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);

        _mainScrollView.landscape = landscape;
        _groupScrollView.landscape = landscape;
        
        // Might have been disabled while we went off screen (like when making a new document)
        [self _performDelayedItemPropagationWithCompletionHandler:nil];
    }
}

- (void)didMoveToParentViewController:(UIViewController *)parent;
{
    [super didMoveToParentViewController:parent];
    
    if (parent) {
        // If the user starts closing a document and then rotates the device before the close finishes, we can get send {will,did}MoveToParentViewController: where the "will" has one orientation and the "did" has another, but we are not sent -willRotateToInterfaceOrientation:duration:, but we *are* sent the "didRotate...".
        BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
        
        _mainScrollView.landscape = landscape;
        _groupScrollView.landscape = landscape;
    }
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    // If we are being exposed rather than added (Help modal view controller being dismissed), we might have missed an orientation change
    if ([self isMovingToParentViewController] == NO) {
        BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
        
        if (_mainScrollView.landscape ^ landscape) {
            _mainScrollView.landscape = landscape;
            _groupScrollView.landscape = landscape;
        }
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated;
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    [super setEditing:editing animated:animated];
    
    // Dismiss any Popovers or Action Sheets.
    [[OUIAppController controller] dismissActionSheetAndPopover:YES];

    // If you Edit in an open group, the items in the background scroll view shouldn't wiggle.
    OBFinishPortingLater("If you drag an item out of an Edit-ing group scroll view, then the main scroll view *should* start the wiggle animation");
    [self.activeScrollView setEditing:editing animated:animated];
    
    if (!editing) {
        [self clearSelection:NO];
    }
    
    [self _updateToolbarItemsAnimated:YES];
    [self _updateToolbarItemsEnabledness];
}

- (void)setToolbarItems:(NSArray *)toolbarItems animated:(BOOL)animated;
{
    // This doesn't update our UIToolbar, but OUIDocumentRenameViewController will use it to go back to the toolbar items we should be using.
    [super setToolbarItems:toolbarItems animated:animated];
    
    // The remain view controller overrides our toolbar's items. Might need a more general check for "has some other view controller taken over the toolbar" (or maybe such controller should have their own toolbar).
    if (_renameViewController == nil) {
        [_toolbar setItems:toolbarItems animated:animated];
    }
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self clearSelection:YES];
    
    [[[OUIAppController controller] topViewController] dismissModalViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark UIViewController (OUIMainViewControllerExtensions)

- (UIToolbar *)toolbarForMainViewController;
{
    if (!_toolbar)
        [self view]; // it's in our xib.
    OBASSERT(_toolbar);
    return _toolbar;
}

- (BOOL)isEditingViewController;
{
    return NO;
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

- (BOOL)documentInteractionController:(UIDocumentInteractionController *)controller canPerformAction:(SEL)action;
{
    NSLog(@"%s %@", __PRETTY_FUNCTION__, NSStringFromSelector(action));
    return NO;
}

- (BOOL)documentInteractionController:(UIDocumentInteractionController *)controller performAction:(SEL)action;
{
    NSLog(@"%s %@", __PRETTY_FUNCTION__, NSStringFromSelector(action));

    if (action == @selector(copy:))
        return YES;
    return NO;
}

#pragma mark -
#pragma mark UITableViewDataSource protocol

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)aTableView numberOfRowsInSection:(NSInteger)section
{
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    static NSString * const CellIdentifier = @"FilterCellIdentifier";
    
    // Dequeue or create a cell of the appropriate type.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil)
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = (indexPath.row == OUIDocumentPickerItemSortByName) ? NSLocalizedStringFromTableInBundle(@"Sort by title", @"OmniUI", OMNI_BUNDLE, @"sort by title") : NSLocalizedStringFromTableInBundle(@"Sort by date", @"OmniUI", OMNI_BUNDLE, @"sort by date");
    cell.imageView.image = (indexPath.row == OUIDocumentPickerItemSortByName) ? [UIImage imageNamed:@"OUIDocumentSortByName.png"] : [UIImage imageNamed:@"OUIDocumentSortByDate.png"];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    OUIDocumentPickerItemSort sortPref = [[[self class] sortPreference] enumeratedValue];
    if ((indexPath.row == 0) == (sortPref == 0))  // or indexPath.row == sortPref
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    else
        cell.accessoryType = UITableViewCellAccessoryNone;        
}

#pragma mark -
#pragma mark OUIDocumentPickerScrollView delegate

static void _setItemSelectedAndBounceView(OUIDocumentPicker *self, OUIDocumentPickerFileItemView *fileItemView, BOOL selected)
{
    // Turning the selection on/off changes how the file item view lays out. We don't want that to animate though -- we just want the bounch down. If we want the selection layer to fade/grow in, we'd need a 'will changed selected'/'did change selected' path that where we can change the layout but not have the selection layer appear yet (maybe fade it in) and only disable animation on the layout change.
    OUIWithoutAnimating(^{
        OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)fileItemView.item;
        OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
        
        fileItem.selected = selected;
        [fileItemView layoutIfNeeded];
    });
    
    // In addition to the border, iWork bounces the file item view down slightly on a tap (selecting or deselecting).
    [fileItemView bounceDown];
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView inArea:(OUIDocumentPickerItemViewTapArea)area;
{
    //OBPRECONDITION(_renameViewController == nil); // Can't be renaming right now, so need to try to stop
    
    // Actually, if you touch two view names at the same time we can get here... UIGestureRecognizer actions seem to be sent asynchronously via queued block, so other events can trickle in and cause another recognizer to fire before the first queued action has run.
    if (_renameViewController)
        return;

    OBFinishPortingLater("Use the shielding view to avoid having to explicitly end editing here"); // also, if we zoom in on a preview to rename like iWork this may change
    
    if ([itemView isKindOfClass:[OUIDocumentPickerFileItemView class]]) {
        OUIDocumentPickerFileItemView *fileItemView = (OUIDocumentPickerFileItemView *)itemView;
        OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)itemView.item;
        OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
        
        if (area == OUIDocumentPickerItemViewTapAreaLabelAndDetails) {
            // Start editing the name of this document.
            [self _startRenamingFileItem:fileItem];
        } else {
            OBASSERT(area == OUIDocumentPickerItemViewTapAreaPreview);
            if ([self isEditing]) {
                _setItemSelectedAndBounceView(self, fileItemView, !fileItem.selected);
                
                [self _updateToolbarItemsAnimated:NO]; // Update the selected file item count
                [self _updateToolbarItemsEnabledness];
            } else {
                if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:openTappedFileItem:)])
                    [_nonretained_delegate documentPicker:self openTappedFileItem:fileItem];
            }
        }
    } else if ([itemView isKindOfClass:[OUIDocumentPickerGroupItemView class]]) {
        OFSDocumentStoreGroupItem *groupItem = (OFSDocumentStoreGroupItem *)itemView.item;
        OBASSERT([groupItem isKindOfClass:[OFSDocumentStoreGroupItem class]]);
        [self _openGroup:groupItem andEditTitle:(area == OUIDocumentPickerItemViewTapAreaLabelAndDetails)];
    } else {
        OBASSERT_NOT_REACHED("Unknown item view class");
    }
}

#pragma mark -
#pragma mark - OUIDocumentPickerDragSession callbacks

- (void)dragSessionTerminated;
{
    [_dragSession release];
    _dragSession = nil;
}

#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)aTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OFPreference *sortPreference = [[self class] sortPreference];
    [sortPreference setEnumeratedValue:indexPath.row];

    [self updateSort];
    [self scrollToTopAnimated:NO];
    
    UITableViewCell *cell = [aTableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
    
    NSIndexPath *otherPath = (indexPath.row == 0) ? [NSIndexPath indexPathForRow:1 inSection:indexPath.section] : [NSIndexPath indexPathForRow:0 inSection:indexPath.section];
    [[aTableView cellForRowAtIndexPath:otherPath] setAccessoryType:UITableViewCellAccessoryNone];
    
    [_filterPopoverController dismissPopoverAnimated:YES];
    [_filterPopoverController release];
    _filterPopoverController = nil;
}

#pragma mark -
#pragma mark NSFilePresenter

// We become the file presentor for our document store's directory (which we assume won't change...)
// Under iOS 5, when iTunes fiddles with your files, your app no longer gets deactivated and reactivated. Instead, the operations seem to happen via NSFileCoordinator.
// Sadly, we don't get subitem changes just -presentedItemDidChange, no matter what set of NSFilePresenter methods we implement (at least as of beta 7).

- (NSURL *)presentedItemURL;
{
    OBPRECONDITION(_documentStore);
    NSURL *url = _documentStore.localScope.url;
    OBASSERT(url);
    return url;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    return _filePresenterQueue;
}

- (void)presentedItemDidChange;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        OBPRECONDITION([NSThread isMainThread]);
        
        if ([self parentViewController] == nil)
            return; // We'll rescan when the currently open document closes
        
        if (_ignoreDocumentsDirectoryUpdates > 0)
            return; // Some other operation is going on that is provoking this change and that wants to do the rescan manually.
        
        // Note: this will get called when the app is returned to the foreground, if coordinated writes were made while it was backgrounded.
        [self rescanDocuments];
    }];
}

#pragma mark -
#pragma mark Internal

- (OUIMainViewController *)mainViewController;
{
    OUIMainViewController *vc = (OUIMainViewController *)self.parentViewController;
    OBASSERT([vc isKindOfClass:[OUIMainViewController class]]); // Don't call this method when we aren't currently its child (and warn if we get a different parent).
    return vc;
}

- (OFSDocumentStoreFileItem *)_preferredFileItemForNextPreviewUpdate:(NSSet *)fileItemsNeedingPreviewUpdate;
{
    // Don't think too hard if there is just a single incoming iCloud update
    if ([fileItemsNeedingPreviewUpdate count] <= 1)
        return [fileItemsNeedingPreviewUpdate anyObject];
    
    // Find a file preview that will update something in the user's view.
    OFSDocumentStoreFileItem *fileItem = nil;
    if ([_groupScrollView window])
        fileItem = [_groupScrollView preferredFileItemForNextPreviewUpdate:fileItemsNeedingPreviewUpdate];
    if (!fileItem)
        fileItem = [_mainScrollView preferredFileItemForNextPreviewUpdate:fileItemsNeedingPreviewUpdate];

    return fileItem;
}

#pragma mark -
#pragma mark Private

- (void)_updateToolbarItemsAnimated:(BOOL)animated;
{
    OBPRECONDITION(_documentStore);

    // Don't ask for animation while off screen
    if (_toolbar.window == nil)
        animated = NO;
    
    OUISingleDocumentAppController *controller = [OUISingleDocumentAppController controller];
    BOOL editing = self.isEditing;
    
    NSMutableArray *toolbarItems = [NSMutableArray array];
    
    if (editing) {
        if (!_exportBarButtonItem) {
            // We keep pointers to a few toolbar items that we need to update enabledness on.
            _exportBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentExport.png"] style:UIBarButtonItemStylePlain target:self action:@selector(export:)];
            _duplicateDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentDuplicate.png"] style:UIBarButtonItemStylePlain target:self action:@selector(duplicateDocument:)];
            _deleteBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentDelete.png"] style:UIBarButtonItemStylePlain target:self action:@selector(deleteDocument:)];
        }
        
        _exportBarButtonItem.enabled = NO;
        _duplicateDocumentBarButtonItem.enabled = NO;
        _deleteBarButtonItem.enabled = NO;
        
        [toolbarItems addObject:_exportBarButtonItem];
        [toolbarItems addObject:_duplicateDocumentBarButtonItem];
        [toolbarItems addObject:_deleteBarButtonItem];
    } else {
        if (_documentStore.documentTypeForNewFiles != nil) {
            UIBarButtonItem *addItem = [[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarAddDocument.png"] 
                                                                         style:UIBarButtonItemStylePlain 
                                                                        target:controller action:@selector(makeNewDocument:)] autorelease];
            [toolbarItems addObject:addItem];
        }
        
        if ([[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"OUIImportEnabled"]) {
            UIBarButtonItem *importItem = [[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarButtonImport.png"] 
                                                                            style:UIBarButtonItemStylePlain 
                                                                           target:controller action:@selector(showSyncMenu:)] autorelease];
            [toolbarItems addObject:importItem];
        }
    }
    
    [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
    
    if (editing) {
        NSSet *selectedFileItems = self.selectedFileItems;
        NSUInteger selectedFileItemCount = [selectedFileItems count];

        NSString *format = nil;
        if ([_nonretained_delegate respondsToSelector:@selector(documentPickerMainToolbarSelectionFormatForFileItems:)])
            format = [_nonretained_delegate documentPickerMainToolbarSelectionFormatForFileItems:selectedFileItems];
        if ([NSString isEmptyString:format]) {
            if (selectedFileItemCount == 0)
                format = NSLocalizedStringFromTableInBundle(@"Select a Document", @"OmniUI", OMNI_BUNDLE, @"Main toolbar title for a no selected documents.");
            else if (selectedFileItemCount == 1)
                format = NSLocalizedStringFromTableInBundle(@"1 Document Selected", @"OmniUI", OMNI_BUNDLE, @"Main toolbar title for a single selected document.");
            else
                format = NSLocalizedStringFromTableInBundle(@"%ld Documents Selected", @"OmniUI", OMNI_BUNDLE, @"Main toolbar title for a multiple selected documents.");
        }

        NSString *title = [NSString stringWithFormat:format, [selectedFileItems count]];
        
        UIBarButtonItem *selectionItem = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain target:nil action:NULL];
        [toolbarItems addObject:selectionItem];
        [selectionItem release];
    } else {
        if (!_appTitleToolbarItem) {
            OBASSERT(_appTitleToolbarButton == nil);
            
            _appTitleToolbarButton = [[OUIToolbarTitleButton buttonWithType:UIButtonTypeCustom] retain];
            UIImage *disclosureImage = [UIImage imageNamed:@"OUIToolbarTitleDisclosureButton.png"];
            OBASSERT(disclosureImage != nil);
            [_appTitleToolbarButton setImage:disclosureImage forState:UIControlStateNormal];
            
            _appTitleToolbarButton.titleEdgeInsets = (UIEdgeInsets){.bottom = 2}; // bring the baseline up to be the same as the selected item count in edit mode
            _appTitleToolbarButton.imageEdgeInsets = (UIEdgeInsets){.top = 2}; // Push the button down a bit to line up with the x height
            
            _appTitleToolbarButton.titleLabel.font = [UIFont boldSystemFontOfSize:20.0];

            _appTitleToolbarButton.adjustsImageWhenHighlighted = NO;
            [_appTitleToolbarButton addTarget:self action:@selector(filterAction:) forControlEvents:UIControlEventTouchUpInside];
            
            [self updateTitle];
            
            _appTitleToolbarItem = [[UIBarButtonItem alloc] initWithCustomView:_appTitleToolbarButton];
        }
        [toolbarItems addObject:_appTitleToolbarItem];
    }
    
    [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
    
    if (!editing)
        [toolbarItems addObject:controller.appMenuBarItem];
    
    [toolbarItems addObject:self.editButtonItem];
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:makeToolbarItems:)])
        [_nonretained_delegate documentPicker:self makeToolbarItems:toolbarItems];
    
    [self setToolbarItems:toolbarItems animated:animated];
}

- (void)_updateToolbarItemsEnabledness;
{
    if (self.isEditing) {
        NSUInteger count = [self selectedFileItemCount];
        if (count == 0) {
            _exportBarButtonItem.enabled = NO;
            _duplicateDocumentBarButtonItem.enabled = NO;
            _deleteBarButtonItem.enabled = NO;
        }
        else if (count == 1) {
            _exportBarButtonItem.enabled = YES;
            _duplicateDocumentBarButtonItem.enabled = YES;
            _deleteBarButtonItem.enabled = YES;
        }
        else if (count > 1) {
            _exportBarButtonItem.enabled = NO;
            _duplicateDocumentBarButtonItem.enabled = YES;
            _deleteBarButtonItem.enabled = YES;
        }
    }
}

- (void)_setupTopItemsBinding;
{
    OBPRECONDITION(_documentStore);
    
    if (_topItemsBinding)
        return;
        
    // We might want to bind _documentStore.fileItems to us and then mirror that property to the scroll view, or force feed it. This would allow us to stage animations or whatnot.
    // NSMetadataQuery is going to send us unsolicited updates (incoming iCloud sync while we are just sitting idle in the picker), so we need to be able to handle these to some extent.
    [_topItemsBinding invalidate];
    [_topItemsBinding release];
    
    _topItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingPointMake(_documentStoreFilter, OFSFilteredDocumentStoreTopLevelItemsBinding)
                                                destinationPoint:OFBindingPointMake(self, TopItemsBinding)];
    [_topItemsBinding propagateCurrentValue];
}

- (void)_sendEmailWithSubject:(NSString *)subject messageBody:(NSString *)messageBody isHTML:(BOOL)isHTML attachmentName:(NSString *)attachmentFileName data:(NSData *)attachmentData fileType:(NSString *)fileType;
{
    MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
    controller.navigationBar.barStyle = UIBarStyleBlack;
    controller.mailComposeDelegate = self;
    [controller setSubject:subject];
    if (messageBody != nil)
        [controller setMessageBody:messageBody isHTML:isHTML];
    if (attachmentData != nil) {
        NSString *mimeType = [(NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)fileType, kUTTagClassMIMEType) autorelease];
        OBASSERT(mimeType != nil); // The UTI's mime type should be registered in the Info.plist under UTExportedTypeDeclarations:UTTypeTagSpecification
        if (mimeType == nil)
            mimeType = @"application/octet-stream"; 

        [controller addAttachmentData:attachmentData mimeType:mimeType fileName:attachmentFileName];
    }
    [[[OUIAppController controller] topViewController] presentModalViewController:controller animated:YES];
    [controller autorelease];
}

- (void)_deleteWithoutConfirmation:(NSSet *)fileItemsToDelete;
{
    NSMutableArray *errors = [NSMutableArray array];
    for (OFSDocumentStoreFileItem *fileItem in fileItemsToDelete) {
        [_documentStore deleteItem:fileItem completionHandler:^(NSError *errorOrNil) {
            if (errorOrNil)
                [errors addObject:errorOrNil];
        }];
    }
    
    // Wait for the deletions to finish and possibly emit errors. Since the action queue is serial, we just enqueue another action, and that then enqueues an action on the main queue.
    [_documentStore performAsynchronousFileAccessUsingBlock:^{
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            for (NSError *error in errors)
                OUI_PRESENT_ERROR(error);
            
            // Provoke a scan, which will poke our file items binding, which will cause the animation to start
            [_documentStore scanItemsWithCompletionHandler:^{
                [self clearSelection:YES];
                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            }];
        }];
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
        _openInMapCache = [[NSMutableDictionary dictionary] retain];
    }
    
    return _openInMapCache;
}


- (BOOL)_canUseOpenInWithFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    // Check current type.
    OBFinishPortingLater("<bug:///75843> (Add a UTI property to OFSDocumentStoreFileItem)");
    NSString *fileType = OFUTIForFileExtensionPreferringNative(fileItem.fileURL.pathExtension, NO); // NSString *fileType = [OFSFileInfo UTIForURL:fileItem.fileURL];
    BOOL canUseOpenInWithCurrentType = [self _canUseOpenInWithExportType:fileType];
    if (canUseOpenInWithCurrentType) {
        return YES;
    }
    
    NSArray *types = [self availableExportTypesForFileItem:fileItem withSyncType:OUISyncTypeNone exportOptionsType:OUIExportOptionsSendToApp];
    return ([types count] > 0) ? YES : NO;
}

- (void)_applicationDidEnterBackground:(NSNotification *)note;
{
    OBPRECONDITION(self.visibility == OUIViewControllerVisibilityVisible); // We only subscribe when we are visible
    
    // Only disable editing if we are not currently presenting a modal view controller.
    if (!self.modalViewController) {
        [self setEditing:NO];
    }
    
    // Reset openInMapCache incase someone adds or delets an app.
    [self.openInMapCache removeAllObjects];
}

- (void)_previewsUpdateForFileItemNotification:(NSNotification *)note;
{
    OFSDocumentStoreFileItem *fileItem = [note object];

    [_mainScrollView previewsUpdatedForFileItem:fileItem];
    [_groupScrollView previewsUpdatedForFileItem:fileItem];
}

- (void)_startRenamingFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    // Higher level code should have already checked this.
    OBPRECONDITION(_renameViewController == nil);
    
    OBPRECONDITION(fileItem);

    // Get the rename controller into its initial state
    _renameViewController = [[OUIDocumentRenameViewController alloc] initWithDocumentPicker:self fileItem:fileItem];
    [self addChildViewController:_renameViewController];
    
    _renameViewController.view.frame = self.view.bounds;
    [self.view addSubview:_renameViewController.view];
    
    [_renameViewController didMoveToParentViewController:self];
    
    [_renameViewController startRenaming];
}

// Called by OUIDocumentRenameViewController
- (void)_didPerformRenameToFileURL:(NSURL *)destinationURL;
{
    OBPRECONDITION(_renameViewController);

    // We expect the file item to have been notified of its new URL already.
    OFSDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:destinationURL];
    OBASSERT(fileItem);
    //NSLog(@"fileItem %@", fileItem);
    
    OUIDocumentPickerScrollView *scrollView = self.activeScrollView;
    
    //NSLog(@"sort items");
    [scrollView sortItems];
    [scrollView scrollItemToVisible:fileItem animated:NO];
}

- (void)_didStopRenamingFileItem;
{
    OBPRECONDITION(_renameViewController);
    
    [_renameViewController willMoveToParentViewController:nil];
    
    [_renameViewController.view removeFromSuperview];
    [_renameViewController removeFromParentViewController];
    
    [_renameViewController release];
    _renameViewController = nil;
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView dragWithRecognizer:(OUIDragGestureRecognizer *)recognizer;
{
    OBPRECONDITION(scrollView == self.activeScrollView);
    
    if (recognizer.state == UIGestureRecognizerStateBegan) {
#if !OUI_DOCUMENT_GROUPING
        // For now we just go into edit mode, select this item, and don't drag anything.
        OUIDocumentPickerFileItemView *fileItemView = [scrollView fileItemViewHitInPreviewAreaByRecognizer:recognizer];
        _setItemSelectedAndBounceView(self, fileItemView, YES);
#else
        OBASSERT(_dragSession == nil);
        [_dragSession release];
        
        NSMutableSet *fileItems = [NSMutableSet setWithSet:[self selectedFileItems]];

        OUIDocumentPickerFileItemView *fileItemView = [scrollView fileItemViewHitInPreviewAreaByRecognizer:recognizer];
        OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)fileItemView.item;
        OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);
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

- (void)_openGroup:(OFSDocumentStoreGroupItem *)groupItem andEditTitle:(BOOL)editTitle;
{
    OBPRECONDITION(self.activeScrollView == _mainScrollView);
    OBPRECONDITION(_openGroupItemsBinding == nil);
    OBPRECONDITION(groupItem);
    OBPRECONDITION([_documentStore.topLevelItems member:groupItem]);
    
    OBFinishPortingLater("Fix lots of sizing edge cases based on the position of the group in the main scroll view and the number of items in the group.");
    OBFinishPortingLater("Handle editing the title, shadow top/bottom edge views, animation, tapping out");
                         
    [_openGroupItemsBinding invalidate];
    [_openGroupItemsBinding release];
    
    _openGroupItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingPointMake(groupItem, OFSDocumentStoreGroupItemFileItemsBinding)
                                                      destinationPoint:OFBindingPointMake(self, OpenGroupItemsBinding)];
    [_openGroupItemsBinding propagateCurrentValue];

    CGRect groupFrame = CGRectInset(_mainScrollView.bounds, 0, 50);
    _groupScrollView.frame = groupFrame;
    [_mainScrollView addSubview:_groupScrollView];
    [_mainScrollView layoutIfNeeded];
}

- (void)_revealAndActivateNewDocumentFileItem:(OFSDocumentStoreFileItem *)createdFileItem completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(createdFileItem);
    
    // Trying a fade in of the new document instead of having all the scrolling/sliding previews
#if 1
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:openCreatedFileItem:)])
        [_nonretained_delegate documentPicker:self openCreatedFileItem:createdFileItem];
    
    _isRevealingNewDocument = NO;
    
    if (completionHandler)
        completionHandler();
#else
    // iWork uses a grid-layout theme picker and then zooms the preview of the selected template into the full screen. We don't yet have templates, but we could do the same someday.
    
    OBFinishPortingLater("Deal with having an open group and looking in the right picker scroll view");
    
    // At first it should not take up space.
    [_mainScrollView startIgnoringItemForLayout:createdFileItem];
    [_mainScrollView setNeedsLayout];
    [_mainScrollView layoutIfNeeded];
    
    [self scrollItemToVisible:createdFileItem animated:NO];
    
    OUIDocumentPickerFileItemView *fileItemView = [_mainScrollView fileItemViewForFileItem:createdFileItem];
    OBASSERT(fileItemView != nil); // should have had a view assigned.
    fileItemView.alpha = 0; // start out transparent
    
    // Turn on layout advancing for this file item and do an animated layout, sliding to make room for it.
    [_mainScrollView stopIgnoringItemForLayout:createdFileItem];
    
    OBFinishPortingLater("rewrite this with OUIAnimationSequence and with the right animation");
    
    [OUIAnimationSequence runWithDuration:0.3 actions:
     ^{
         [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
         [_mainScrollView layoutSubviews];
     },
     ^{
         OUIDocumentPickerFileItemView *fileItemView = [_mainScrollView fileItemViewForFileItem:createdFileItem];
         OBASSERT(fileItemView);
         fileItemView.alpha = 1;
     },
     ^{
         OUIWithoutAnimating(^{
             [_mainScrollView setNeedsLayout];
             [_mainScrollView layoutIfNeeded];
             
             if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:openCreatedFileItem:)])
                 [_nonretained_delegate documentPicker:self openCreatedFileItem:createdFileItem];

             _isRevealingNewDocument = NO;
         });
         
         if (completionHandler)
             completionHandler();
     },
     nil];
#endif
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

@synthesize topItems = _topItems;
- (void)setTopItems:(NSSet *)topItems;
{
    if (OFISEQUAL(_topItems, topItems))
        return;
    
    [_topItems release];
    _topItems = [[NSSet alloc] initWithSet:topItems];
    
    if (_ignoreDocumentsDirectoryUpdates == 0) {
        [self _propagateItems:_topItems toScrollView:_mainScrollView withCompletionHandler:nil];
        [self _updateToolbarItemsEnabledness];
    }
}

@synthesize openGroupItems = _openGroupItems;
- (void)setOpenGroupItems:(NSSet *)openGroupItems;
{
    if (OFISEQUAL(_openGroupItems, openGroupItems))
        return;
    
    [_openGroupItems release];
    _openGroupItems = [[NSSet alloc] initWithSet:openGroupItems];
    
    if (_ignoreDocumentsDirectoryUpdates == 0) {
        [self _propagateItems:_openGroupItems toScrollView:_groupScrollView withCompletionHandler:nil];
        [self _updateToolbarItemsEnabledness];
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
    
    completionHandler = [[completionHandler copy] autorelease];
    
    // If needed later, we could have a flag that says to bail on propagating and we can accumulate differences between the current state and the view state until some time later.
    BOOL isVisible = (self.visibility == OUIViewControllerVisibilityVisible);
    NSTimeInterval animationInterval = isVisible ? OUIAnimationSequenceDefaultDuration : OUIAnimationSequenceImmediateDuration;
    
    NSMutableSet *toRemove = [[currentItems mutableCopy] autorelease];
    [toRemove minusSet:items];
    
    NSMutableSet *toAdd = [[items mutableCopy] autorelease];
    [toAdd minusSet:currentItems];

    [OUIAnimationSequence runWithDuration:animationInterval actions:
     ^{
         if ([toRemove count] > 0)
             [scrollView startRemovingItems:toRemove]; // Shrink/fade or whatever
     },
     ^{
         if ([toRemove count] > 0) {
             [scrollView finishRemovingItems:toRemove]; // Actually remove them and release the space taken
             if (isVisible)
                 [scrollView layoutIfNeeded]; // If we aren't visible, we might not be fully configured for layout yet
         }
     },
     ^{
         if ([toAdd count] > 0) {
             // Add them and make room in the layout
             [scrollView startAddingItems:toAdd];
             if (isVisible)
                 [scrollView layoutIfNeeded]; // If we aren't visible, we might not be fully configured for layout yet
         }
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
        [self _propagateItems:_topItems toScrollView:_mainScrollView withCompletionHandler:^{
            if (_openGroupItemsBinding)
                [self _propagateItems:_openGroupItems toScrollView:_groupScrollView withCompletionHandler:completionHandler];
            else if (completionHandler)
                completionHandler();
        }];
    } else {
        if (completionHandler)
            completionHandler();
    }
}

@end
