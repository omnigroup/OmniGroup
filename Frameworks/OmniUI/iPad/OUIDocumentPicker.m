// Copyright 2010-2011 The Omni Group. All rights reserved.
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
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSInvocation-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/OFPreference.h>
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
#import <OmniUI/OUIDocumentStore.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUIDocumentStoreGroupItem.h>
#import <OmniUI/OUIDragGestureRecognizer.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/OUIMainViewController.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIActionSheet.h>
#import <OmniUnzip/OUZipArchive.h>

#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerDragSession.h"
#import "OUIDocumentPickerView.h"
#import "OUIDocumentRenameViewController.h"
#import "OUIExportOptionsController.h"
#import "OUIExportOptionsView.h"
#import "OUISheetNavigationController.h"
#import "OUISyncMenuController.h"
#import "OUIToolbarTitleButton.h"

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

static NSString * const kActionSheetExportIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.ExportAction";
static NSString * const kActionSheetDeleteIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.DeleteAction";

@interface OUIDocumentPicker (/*Private*/) <MFMailComposeViewControllerDelegate, UITableViewDataSource, UITableViewDelegate, NSFilePresenter>

- (void)_updateToolbarItems;
- (void)_updateToolbarItemsEnabledness;
- (void)_setupMainItemsBinding;
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
- (BOOL)_canUseOpenInWithFileItem:(OUIDocumentStoreFileItem *)fileItem;
- (void)_applicationDidEnterBackground:(NSNotification *)note;
- (void)_startRenamingFileItem:(OUIDocumentStoreFileItem *)fileItem;
- (void)_startDragRecognizer:(OUIDragGestureRecognizer *)recognizer;
- (void)_openGroup:(OUIDocumentStoreGroupItem *)groupItem andEditTitle:(BOOL)editTitle;
- (void)_revealAndActivateNewDocumentFileItem:(OUIDocumentStoreFileItem *)createdFileItem completionHandler:(void (^)(void))completionHandler;

- (void)_beginIgnoringDocumentsDirectoryUpdates;
- (void)_endIgnoringDocumentsDirectoryUpdates;

@property (nonatomic, retain) NSMutableDictionary *openInMapCache;

@end

@implementation OUIDocumentPicker
{
    id <OUIDocumentPickerDelegate> _nonretained_delegate;

    NSOperationQueue *_filePresenterQueue;
    
    OUIDocumentPickerScrollView *_topScrollView;
    OUIDocumentPickerScrollView *_groupScrollView;
    
    id _fileItemTappedTarget;
    SEL _fileItemTappedAction;
    
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

    OUIDocumentStore *_documentStore;
    NSUInteger _ignoreDocumentsDirectoryUpdates;
    OFSetBinding *_mainScrollViewItemsBinding;
    OFSetBinding *_groupScrollViewItemsBinding;
    
    OUIDragGestureRecognizer *_startDragRecognizer;
    OUIDocumentPickerDragSession *_dragSession;
}

static id _commonInit(OUIDocumentPicker *self)
{
    // Methods removed on this class that subclasses shouldn't be overriding any more
    OBASSERT_NOT_IMPLEMENTED(self, documentActionTitle); // The new document button is just a "+" now and we don't have the new-or-duplicate button on the doc picker
    OBASSERT_NOT_IMPLEMENTED(self, duplicateActionTitle);
    OBASSERT_NOT_IMPLEMENTED(self, deleteDocumentTitle); // -deleteDocumentTitle:, taking a count
    
    OBASSERT_NOT_IMPLEMENTED(self, editNameForDocumentURL:); // Instance method on OUIDocumentStoreItem
    OBASSERT_NOT_IMPLEMENTED(self, displayNameForDocumentURL:); // Instance method on OUIDocumentStoreItem

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
    [[NSNotificationCenter defaultCenter] removeObserver:self]; // metadata queries

    [_duplicateDocumentBarButtonItem release];
    [_exportBarButtonItem release];
    [_deleteBarButtonItem release];
    [_appTitleToolbarItem release];
    [_appTitleToolbarButton release];
    
    OBASSERT(_dragSession == nil); // it retains us anyway, so we can't get here otherwise
    _startDragRecognizer.delegate = nil;
    [_startDragRecognizer release];
    _startDragRecognizer = nil;

    [_openInMapCache release];
    [_topScrollView release];
    [_groupScrollView release];
    
    [_mainScrollViewItemsBinding invalidate];
    [_mainScrollViewItemsBinding release];
    
    if (_documentStore)
        [NSFileCoordinator removeFilePresenter:self];
    [_documentStore release];
    [_filePresenterQueue release];
    
    [_fileItemTappedTarget release];
    
    [_toolbar release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark KVC

@synthesize documentStore = _documentStore;
- (void)setDocumentStore:(OUIDocumentStore *)documentStore;
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
    
    // Checks whether the document store has a file type for newly created documents
    [self _updateToolbarItems];
}

@synthesize delegate = _nonretained_delegate;

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

@synthesize fileItemTappedTarget = _fileItemTappedTarget;
@synthesize fileItemTappedAction = _fileItemTappedAction;

#pragma mark -
#pragma mark API

- (CGSize)gridSizeForOrientation:(UIInterfaceOrientation)orientation;
{
    CGSize gridSize = CGSizeZero;
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:gridSizeForOrientation:)])
        gridSize = [_nonretained_delegate documentPicker:self gridSizeForOrientation:orientation];
    if (CGSizeEqualToSize(gridSize, CGSizeZero)) {
        // Pick a default grid size
        if (UIInterfaceOrientationIsLandscape(orientation))
            gridSize = CGSizeMake(4, 3.2);
        else
            gridSize = CGSizeMake(3, 3.175);
    }
    return gridSize;
}

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
        OUIDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:targetURL];
        if (!fileItem)
            [_mainScrollView scrollsToTop];
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
        OUIDocumentStoreFileItem *fileItem = obj;
        return fileItem.selected;
    }];
}

- (NSUInteger)selectedFileItemCount;
{
    NSUInteger selectedCount = 0;
    
    for (OUIDocumentStoreFileItem *fileItem in _documentStore.fileItems)
        if (fileItem.selected)
            selectedCount++;
    
    return selectedCount;
}

- (void)clearSelection;
{
    for (OUIDocumentStoreFileItem *fileItem in _documentStore.fileItems)
        fileItem.selected = NO;
    
    [self _updateToolbarItemsEnabledness];
}

- (OUIDocumentStoreFileItem *)singleSelectedFileItem;
{
    NSSet *selectedFileItems = self.selectedFileItems;
    
    // Ensure we have one and only one selected file item.
    if ([selectedFileItems count] != 1){
        OBASSERT_NOT_REACHED("We should only have one file item in selectedFileItems at this point.");
        return nil;
    }
    
    return [selectedFileItems anyObject];
}

- (BOOL)canEditFileItem:(OUIDocumentStoreFileItem *)fileItem;
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

- (void)scrollItemToVisible:(OUIDocumentStoreItem *)item animated:(BOOL)animated;
{
    OUIDocumentPickerScrollView *scrollView = self.activeScrollView;

    [scrollView scrollItemToVisible:item animated:animated];
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
    
    [_documentStore createNewDocument:^(NSURL *createdURL, NSError *error){
        if (!createdURL) {
            [self _endIgnoringDocumentsDirectoryUpdates];
            OUI_PRESENT_ERROR(error);
            return;
        }
        
        _isRevealingNewDocument = YES;
        
        [[NSFileManager defaultManager] touchItemAtURL:createdURL error:NULL];
        
        [_documentStore scanItemsWithCompletionHandler:^{
            OUIDocumentStoreFileItem *createdFileItem = [_documentStore fileItemWithURL:createdURL];
            OBASSERT(createdFileItem);
            
            [self _revealAndActivateNewDocumentFileItem:createdFileItem completionHandler:^{
                [self _endIgnoringDocumentsDirectoryUpdates];
            }];
        }];
    }];
}

- (IBAction)duplicateDocument:(id)sender;
{
    [[OUIAppController controller] dismissActionSheetAndPopover:YES];
    
    NSSet *selectedFileItems = self.selectedFileItems;
    if ([selectedFileItems count] == 0) {
        OBASSERT_NOT_REACHED("Make this button be disabled");
        return;
    }
    
    NSMutableArray *duplicateFileItems = [NSMutableArray array];
    NSMutableArray *errors = [NSMutableArray array];
    NSMutableArray *duplicateOperations = [NSMutableArray array];

    // We'll update once at the end
    [self _beginIgnoringDocumentsDirectoryUpdates];
    
    for (OUIDocumentStoreFileItem *fileItem in selectedFileItems) {
        // The queue is concurrent, so we need to remember all the enqueued blocks and make them dependencies of our completion
        NSOperation *op = [_documentStore addDocumentFromURL:fileItem.fileURL option:OUIDocumentStoreAddByRenaming completionHandler:^(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error) {
            OBASSERT([NSThread isMainThread]); // gets enqueued on the main thread, but even if it was invoked on the background serial queue, this would be OK as long as we don't access the mutable arrays until all the blocks are done
            if (duplicateFileItem)
                [duplicateFileItems addObject:duplicateFileItem];
            else {
                OBASSERT(error);
                if (error) // let's not crash, though...
                    [errors addObject:error]; 
            }
        }];
        [duplicateOperations addObject:op];
    }

    OBASSERT([duplicateOperations count] > 0); // we checked we have items above

    NSBlockOperation *allCompleted = [NSBlockOperation blockOperationWithBlock:^{
        
        [self _endIgnoringDocumentsDirectoryUpdates];
        
        for (OUIDocumentStoreFileItem *duplicateFileItem in duplicateFileItems) {        
            // At first it should not take up space.
            //duplicateFileItem.layoutShouldAdvance = NO;
            
            // TODO: Can we still do this, now that the file item doesn't have the previews? Maybe we should just reload them and wait to start the animation until they are loaded, or some such.
#if 0
            // The duplicate has exactly the same preview as the original, avoid loading it redundantly.
            OUIDocumentStoreFileItem *originalFileItem = [duplicateURLToOriginalFileItem objectForKey:duplicateURL];
            [duplicateFileItem previewDidLoad:originalFileItem.currentPreview];
            OBASSERT(duplicateFileItem.currentPreview != nil);
#endif
        }
        
        // iWork slides the old items into their new places and then zooms the new items out from its center (the new item appears right after the thing it was copied from (in both name/date sorting mode).
        OBFinishPortingLater("Re-add a duplication animation");
        [self clearSelection];
        
        [self.activeScrollView setNeedsLayout];
        [self.activeScrollView layoutIfNeeded];

        // This may be annoying if there were several errors, but it is misleading to not do it...
        for (NSError *error in errors)
            OUI_PRESENT_ALERT(error);
    }];
    
    for (NSOperation *op in duplicateOperations)
        [allCompleted addDependency:op];
    
    [[NSOperationQueue mainQueue] addOperation:allCompleted];
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
            [_documentStore addDocumentFromURL:documentURL option:OUIDocumentStoreAddByReplacing completionHandler:^(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error) {
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
            [_documentStore addDocumentFromURL:documentURL option:OUIDocumentStoreAddByRenaming completionHandler:^(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error) {
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
    [_documentStore addDocumentFromURL:url option:OUIDocumentStoreAddNormally completionHandler:^(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error) {
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
    NSString *fileType = [OFSFileInfo UTIForURL:url];
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:shouldRevealDocumentAfterExportingType:)] && [_nonretained_delegate documentPicker:self shouldRevealDocumentAfterExportingType:fileType]) {
        [self rescanDocuments];
    }
    
    [self clearSelection];
}

- (NSArray *)availableExportTypesForFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:availableExportTypesForFileItem:)])
        return [_nonretained_delegate documentPicker:self availableExportTypesForFileItem:fileItem];

    NSMutableArray *exportTypes = [NSMutableArray array];
    BOOL canMakePDF = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)];
    BOOL canMakePNG = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)];
    if (canMakePDF)
        [exportTypes addObject:(NSString *)kUTTypePDF];
    if (canMakePNG)
        [exportTypes addObject:(NSString *)kUTTypePNG];
    return exportTypes;
}

- (NSArray *)availableImageExportTypesForFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    NSMutableArray *imageExportTypes = [NSMutableArray array];
    NSArray *exportTypes = [self availableExportTypesForFileItem:fileItem];
    for (NSString *exportType in exportTypes) {
        if (UTTypeConformsTo((CFStringRef)exportType, kUTTypeImage))
            [imageExportTypes addObject:exportType];
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
- (NSArray *)availableDocumentInteractionExportTypesForFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    NSMutableArray *docInteractionExportTypes = [NSMutableArray array];
    

    NSArray *exportTypes = [self availableExportTypesForFileItem:fileItem];
    for (NSString *exportType in exportTypes) {
        if ([self _canUseOpenInWithExportType:exportType]) {
            [docInteractionExportTypes addObject:exportType];
        }
    }
    
    return docInteractionExportTypes;
}

- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(OUIDocumentStoreFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
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

    OUIDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem){
        OBASSERT_NOT_REACHED("Make this button be disabled");
        return;
    }
    
    NSURL *url = fileItem.fileURL;
    if (url == nil)
        return;

    OUIActionSheet *actionSheet = [[[OUIActionSheet alloc] initWithIdentifier:kActionSheetExportIdentifier] autorelease];
    
    BOOL canExport = [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"OUIExportEnabled"];
    NSArray *availableExportTypes = [self availableExportTypesForFileItem:fileItem];
    NSArray *availableImageExportTypes = [self availableImageExportTypesForFileItem:fileItem];
    BOOL canSendToCameraRoll = [_nonretained_delegate respondsToSelector:@selector(documentPicker:cameraRollImageForFileItem:)];
    BOOL canPrint = NO;
    BOOL canUseOpenIn = [self _canUseOpenInWithFileItem:fileItem];
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:printFileItem:fromButton:)])
        if (NSClassFromString(@"UIPrintInteractionController") != nil)
            if ([UIPrintInteractionController isPrintingAvailable])  // "Some iOS devices do not support printing"
                canPrint = YES;
    
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

    // OBFinishPorting: decide on real UI for this
    {
        BOOL isUbiquitous = [[NSFileManager defaultManager] isUbiquitousItemAtURL:url];
        
        if (!isUbiquitous) {
            [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Move to iCloud", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                                  forAction:^{
                                      [self moveToCloud:self];
                                  }];
        } else {
            [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Move out of iCloud", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")
                                  forAction:^{
                                      [self moveOutOfCloud:self];
                                  }];
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
    
    [self->_documentStore moveFileItems:self.selectedFileItems toCloud:toCloud completionHandler:^(OUIDocumentStoreFileItem *failingItem, NSError *errorOrNil) {
        OBASSERT([NSThread isMainThread]);
        
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        [self clearSelection];

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
    OUIDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    NSData *documentData = [fileItem emailData];
    NSString *documentFilename = [fileItem emailFilename];
    NSString *documentType = [OFSFileInfo UTIForFilename:documentFilename];
    OBASSERT(documentType != nil); // UTI should be registered in the Info.plist under CFBundleDocumentTypes

    [self _sendEmailWithSubject:[fileItem name] messageBody:nil isHTML:NO attachmentName:documentFilename data:documentData fileType:documentType];
}

- (BOOL)_canUseEmailBodyForExportType:(NSString *)exportType;
{
    return ![_nonretained_delegate respondsToSelector:@selector(documentPicker:canUseEmailBodyForType:)] || [_nonretained_delegate documentPicker:self canUseEmailBodyForType:exportType];
}

- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType;
{
    OUIDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
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
                NSString *documentType = [OFSFileInfo UTIForFilename:childWrapper.preferredFilename];
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
        
        NSString *emailType = [OFSFileInfo UTIForFilename:fileWrapper.preferredFilename];
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
        emailType = [OFSFileInfo UTIForFilename:emailName];
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
    OUIDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    [_nonretained_delegate documentPicker:self printFileItem:fileItem fromButton:_exportBarButtonItem];
}

- (void)copyAsImage:(id)sender;
{
    OUIDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    NSMutableArray *items = [NSMutableArray array];
    
    BOOL canMakePDF = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)];
    BOOL canMakePNG = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)];
    
    if (canMakePDF) {
        NSError *error = nil;
        NSData *pdfData = [_nonretained_delegate documentPicker:self PDFDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    }
    
    // Don't put more than one image format on the pasteboard, because both will get pasted into iWork.  <bug://bugs/61070>
    if (!canMakePDF && canMakePNG) {
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
}

- (void)sendToCameraRoll:(id)sender;
{
    OUIDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    UIImage *image = [_nonretained_delegate documentPicker:self cameraRollImageForFileItem:fileItem];
    if (!image) {  // Delegate can return nil to get the default implementation
        Class documentClass = [[OUISingleDocumentAppController controller] documentClassForURL:fileItem.fileURL];
        OBASSERT(OBClassIsSubclassOfClass(documentClass, [OUIDocument class]));
        
        image = [documentClass cameraRollImageForFileItem:fileItem];
    }
    if (image) {
        UIImageWriteToSavedPhotosAlbum(image, self, @selector(_sendToCameraRollImage:didFinishSavingWithError:contextInfo:), NULL);
    }
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
    [[table tableView] setDelegate:self];
    [[table tableView] setDataSource:self];
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
    OBFinishPortingLater("Make sure this gets called as the selection changes, documents are added/removed, whatever.");
    
    NSString *title = [self mainToolbarTitle];
    
    // We don't have a selected item right now, but we may want to have some sort of "N of M" display for filtering based on searches. See <bug:///72896> (Need UI mockup for doc picker changes to support searching [global find])
#if 0
    OUIDocumentPicker *picker = self.documentPicker;
    OUIDocumentProxy *proxy = picker.selectedProxy;
    NSArray *proxies = picker.previewScrollView.sortedProxies;
    NSUInteger proxyCount = [proxies count];
    
    if (proxy != nil && proxyCount > 1) {
        NSUInteger proxyIndex = [proxies indexOfObjectIdenticalTo:proxy];
        if (proxyIndex == NSNotFound) {
            OBASSERT_NOT_REACHED("Missing proxy");
            proxyIndex = 1; // less terrible.
        }
        
        NSString *counterFormat = NSLocalizedStringWithDefaultValue(@"%d of %d <document index", @"OmniUI", OMNI_BUNDLE, @"%@ (%d of %d)", @"format for showing the main title, document index and document count, in that order");
        title = [NSString stringWithFormat:counterFormat, title, proxyIndex + 1, proxyCount];
    }
#endif
    
    // Had to add a space after the title to make padding between the title and the image. I tried using UIEdgeInsets on the image, title and content but could not get it to work horizontally. I did, however, get it to work to vertically align the image.
    [_appTitleToolbarButton setTitle:[title stringByAppendingString:@" "] forState:UIControlStateNormal];
    _appTitleToolbarButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
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
    CGSize gridSize = [self gridSizeForOrientation:self.interfaceOrientation];
    
    CGRect viewBounds = self.view.bounds;
    _mainScrollView.frame = viewBounds;
    [_mainScrollView setLandscape:landscape gridSize:gridSize];
    
    [_groupScrollView setLandscape:landscape gridSize:gridSize];
    [_groupScrollView removeFromSuperview]; // We'll put it back when opening a group
    
    [self updateSort];
    
    [self _setupMainItemsBinding];
    
    _startDragRecognizer = [[OUIDragGestureRecognizer alloc] initWithTarget:self action:@selector(_startDragRecognizer:)];
    _startDragRecognizer.delegate = self;
    _startDragRecognizer.holdDuration = 0.5; // taken from UILongPressGestureRecognizer.h
    _startDragRecognizer.requiresHoldToComplete = YES;

    [_mainScrollView addGestureRecognizer:_startDragRecognizer];
    [_groupScrollView addGestureRecognizer:_startDragRecognizer];
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    OBASSERT(_dragSession == nil); // No idea how we'd get here, but just in case
    [_dragSession release];
    _dragSession = nil;
    
    _startDragRecognizer.delegate = nil;
    [_startDragRecognizer release];
    _startDragRecognizer = nil;
    
    [_mainScrollView release];
    _mainScrollView = nil;
    
    [_mainScrollViewItemsBinding invalidate];
    [_mainScrollViewItemsBinding release];
    _mainScrollViewItemsBinding = nil;

    [_groupScrollView release];
    _groupScrollView = nil;
    
    [_groupScrollViewItemsBinding invalidate];
    [_groupScrollViewItemsBinding release];
    _groupScrollViewItemsBinding = nil;

    OBFinishPorting; // Just unbind our observance of the _documentStore?
    //[self _stopMetadataQuery];
    //[_proxies release];
    //_proxies = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    if (NSClassFromString(@"UIPrintInteractionController") != nil)
        [[UIPrintInteractionController sharedPrintController] dismissAnimated:NO];
    
    BOOL landscape = UIInterfaceOrientationIsLandscape(toInterfaceOrientation);
    CGSize gridSize = [self gridSizeForOrientation:toInterfaceOrientation];
    
    [_mainScrollView willRotate];
    [_mainScrollView setLandscape:landscape gridSize:gridSize];

    if (_groupScrollView.superview) {
        [_groupScrollView willRotate];
        [_groupScrollView setLandscape:landscape gridSize:gridSize];
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
        CGSize gridSize = [self gridSizeForOrientation:self.interfaceOrientation];

        [_mainScrollView setLandscape:landscape gridSize:gridSize];
        [_groupScrollView setLandscape:landscape gridSize:gridSize];
    }
}
    
- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    // This needs the ability to convert between view coordinates systems that we can't do we actually are in a window.
    if ([self isBeingPresented] || [self isMovingToParentViewController]) {
        [_mainScrollView layoutIfNeeded]; // get contentInset set correctly the first time we come on screen
        [self scrollToTopAnimated:NO];
    }
}

- (void)viewWillDisappear:(BOOL)animated;
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self 
                                                    name:UIApplicationDidEnterBackgroundNotification 
                                                  object:nil];
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
        [self clearSelection];
    }
    
    [self _updateToolbarItems];
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
    [self clearSelection];
    
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
#pragma mark UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer;
{
    if (gestureRecognizer == _startDragRecognizer) {
        if (_startDragRecognizer.wasATap)
            return NO;

        // Only start editing and float up a preview if we hit a file preview
        return ([self.activeScrollView fileItemViewHitInPreviewAreaByRecognizer:_startDragRecognizer] != nil);
    }
    
    return YES;
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"FilterCellIdentifier";
    
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

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView inArea:(OUIDocumentPickerItemViewTapArea)area;
{
    OBPRECONDITION(_renameViewController == nil); // Can't be renaming right now, so need to try to stop
        
    OBFinishPortingLater("Use the shielding view to avoid having to explicitly end editing here"); // also, if we zoom in on a preview to rename like iWork this may change
    
    if ([itemView isKindOfClass:[OUIDocumentPickerFileItemView class]]) {
        OUIDocumentPickerFileItemView *fileItemView = (OUIDocumentPickerFileItemView *)itemView;
        OUIDocumentStoreFileItem *fileItem = (OUIDocumentStoreFileItem *)itemView.item;
        OBASSERT([fileItem isKindOfClass:[OUIDocumentStoreFileItem class]]);
        
        if (area == OUIDocumentPickerItemViewTapAreaLabelAndDetails) {
            // Start editing the name of this document.
            [self _startRenamingFileItem:fileItem];
        } else {
            OBASSERT(area == OUIDocumentPickerItemViewTapAreaPreview);
            if ([self isEditing]) {
                OBFinishPortingLater("Update the title to say '5 Outlines Selected', or whatever");
                fileItem.selected = !fileItem.selected;
                
                // In addition to the border, iWork bounces the file item view down slightly on a tap (selecting or deselecting).
                [fileItemView bounceDown];
                
                [self _updateToolbarItemsEnabledness];
            } else
                [_fileItemTappedTarget performSelector:_fileItemTappedAction withObject:fileItem];
        }
    } else if ([itemView isKindOfClass:[OUIDocumentPickerGroupItemView class]]) {
        OUIDocumentStoreGroupItem *groupItem = (OUIDocumentStoreGroupItem *)itemView.item;
        OBASSERT([groupItem isKindOfClass:[OUIDocumentStoreGroupItem class]]);
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
    NSURL *url = _documentStore.directoryURL;
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

- (void)_previewsUpdatedForFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    [_mainScrollView previewsUpdatedForFileItem:fileItem];
    [_groupScrollView previewsUpdatedForFileItem:fileItem];
}

#pragma mark -
#pragma mark Private

- (void)_updateToolbarItems;
{
    OBPRECONDITION(_documentStore);
    
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
    
    if (!_appTitleToolbarItem) {
        OBASSERT(_appTitleToolbarButton == nil);
        
        _appTitleToolbarButton = [[OUIToolbarTitleButton buttonWithType:UIButtonTypeCustom] retain];
        UIImage *disclosureImage = [UIImage imageNamed:@"OUIToolbarTitleDisclosureButton.png"];
        OBASSERT(disclosureImage != nil);
        [_appTitleToolbarButton setImage:disclosureImage forState:UIControlStateNormal];
        _appTitleToolbarButton.imageEdgeInsets = (UIEdgeInsets){
            .top = 3.0,
            .left = 0.0,
            .bottom = 0.0,
            .right = 0.0
        };
        
        _appTitleToolbarButton.adjustsImageWhenHighlighted = NO;
        [_appTitleToolbarButton addTarget:self action:@selector(filterAction:) forControlEvents:UIControlEventTouchUpInside];
        
        [self updateTitle];
        
        _appTitleToolbarItem = [[UIBarButtonItem alloc] initWithCustomView:_appTitleToolbarButton];
    }
    [toolbarItems addObject:_appTitleToolbarItem];
    
    [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
    
    [toolbarItems addObject:controller.appMenuBarItem];
    [toolbarItems addObject:self.editButtonItem];
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:makeToolbarItems:)])
        [_nonretained_delegate documentPicker:self makeToolbarItems:toolbarItems];
    
    [self setToolbarItems:toolbarItems];
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

- (void)_setupMainItemsBinding;
{
    OBPRECONDITION(_documentStore);
    
    if (_mainScrollViewItemsBinding && [_mainScrollViewItemsBinding destinationPoint].object == _mainScrollView)
        return;
        
    // We might want to bind _documentStore.fileItems to us and then mirror that property to the scroll view, or force feed it. This would allow us to stage animations or whatnot.
    // NSMetadataQuery is going to send us unsolicited updates (incoming iCloud sync while we are just sitting idle in the picker), so we need to be able to handle these to some extent.
    [_mainScrollViewItemsBinding invalidate];
    [_mainScrollViewItemsBinding release];
    
    _mainScrollViewItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingPointMake(_documentStore, OUIDocumentStoreTopLevelItemsBinding)
                                                           destinationPoint:OFBindingPointMake(_mainScrollView, OUIDocumentPickerScrollViewItemsBinding)];
    [_mainScrollViewItemsBinding propagateCurrentValue];
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
    [OUIAnimationSequence runWithDuration:0.3 actions:
     ^{
         // Fade out/shrink the file item views being deleted.
         [self.activeScrollView prepareToDeleteFileItems:fileItemsToDelete];
     },
     ^{
         // Perform the actual deletion.
         [self _beginIgnoringDocumentsDirectoryUpdates];
         
         NSMutableArray *errors = [NSMutableArray array];
         NSMutableArray *deleteOperations = [NSMutableArray array];
         
         for (OUIDocumentStoreFileItem *fileItem in fileItemsToDelete) {
             // The queue is concurrent, so we need to remember all the enqueued blocks and make them dependencies of our completion
             NSOperation *op = [_documentStore deleteItem:fileItem completionHandler:^(NSError *errorOrNil) {
                 if (errorOrNil)
                     [errors addObject:errorOrNil];
             }];
             [deleteOperations addObject:op];
         }
         
         NSOperation *deletionFinished = [NSBlockOperation blockOperationWithBlock:^{
             [self _endIgnoringDocumentsDirectoryUpdates];
             
             [self rescanDocuments];
             [self _updateToolbarItemsEnabledness];
             [self.activeScrollView finishedDeletingFileItems:fileItemsToDelete];
             [self.activeScrollView layoutIfNeeded];
             
             for (NSError *error in errors)
                 OUI_PRESENT_ERROR(error);
         }];
         
         for (NSOperation *op in deleteOperations)
             [deletionFinished addDependency:op];

         [[NSOperationQueue mainQueue] addOperation:deletionFinished];
     },
     nil];
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


- (BOOL)_canUseOpenInWithFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    // Check current type.
    NSString *fileType = [OFSFileInfo UTIForURL:fileItem.fileURL];
    BOOL canUseOpenInWithCurrentType = [self _canUseOpenInWithExportType:fileType];
    if (canUseOpenInWithCurrentType) {
        return YES;
    }
    
    NSArray *types = [self availableDocumentInteractionExportTypesForFileItem:fileItem];
    return ([types count] > 0) ? YES : NO;
}

- (void)_applicationDidEnterBackground:(NSNotification *)note;
{
    [self setEditing:NO];
    
    // Reset openInMapCache incase someone adds or delets an app.
    [self.openInMapCache removeAllObjects];
}

- (void)_startRenamingFileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    // We can't be editing it already (since all the normal items are hidden if we are). We might be in Edit mode, though.
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
- (void)_didStopRenamingFileItem;
{
    OBPRECONDITION(_renameViewController);
    
    [_renameViewController willMoveToParentViewController:nil];
    
    [_renameViewController.view removeFromSuperview];
    [_renameViewController removeFromParentViewController];
    
    [_renameViewController release];
    _renameViewController = nil;
}

- (void)_startDragRecognizer:(OUIDragGestureRecognizer *)recognizer;
{
    UIGestureRecognizerState state = recognizer.state;
    
    if (state == UIGestureRecognizerStateBegan) {
        OBASSERT(_dragSession == nil);
        [_dragSession release];
        
        NSMutableSet *fileItems = [NSMutableSet setWithSet:[self selectedFileItems]];

        OUIDocumentPickerFileItemView *fileItemView = [self.activeScrollView fileItemViewHitInPreviewAreaByRecognizer:recognizer];
        OUIDocumentStoreFileItem *fileItem = (OUIDocumentStoreFileItem *)fileItemView.item;
        OBASSERT([fileItem isKindOfClass:[OUIDocumentStoreFileItem class]]);
        if (fileItem)
            [fileItems addObject:fileItem];
        
        if ([fileItems count] > 0)
            _dragSession = [[OUIDocumentPickerDragSession alloc] initWithDocumentPicker:self fileItems:fileItems recognizer:recognizer];
    }
    
    // NOTE: We do not look for ended/cancelled states here to clear out _dragSession. It sends us a -dragSessionTerminated, which will happen some time *after* these states, based on animation.
    [_dragSession handleRecognizerChange];
}

- (void)_openGroup:(OUIDocumentStoreGroupItem *)groupItem andEditTitle:(BOOL)editTitle;
{
    OBPRECONDITION(self.activeScrollView == _mainScrollView);
    OBPRECONDITION(_groupScrollViewItemsBinding == nil);
    OBPRECONDITION(groupItem);
    OBPRECONDITION([_documentStore.topLevelItems member:groupItem]);
    
    OBFinishPortingLater("Fix lots of sizing edge cases based on the position of the group in the main scroll view and the number of items in the group.");
    OBFinishPortingLater("Handle editing the title, shadow top/bottom edge views, animation, tapping out");
                         
    [_groupScrollViewItemsBinding invalidate];
    [_groupScrollViewItemsBinding release];
    
    _groupScrollViewItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingPointMake(groupItem, OUIDocumentStoreGroupItemFileItemsBinding)
                                                            destinationPoint:OFBindingPointMake(_groupScrollView, OUIDocumentPickerScrollViewItemsBinding)];
    [_groupScrollViewItemsBinding propagateCurrentValue];

    CGRect groupFrame = CGRectInset(_mainScrollView.bounds, 0, 50);
    _groupScrollView.frame = groupFrame;
    [_mainScrollView addSubview:_groupScrollView];
    [_mainScrollView layoutIfNeeded];
}

- (void)_revealAndActivateNewDocumentFileItem:(OUIDocumentStoreFileItem *)createdFileItem completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(createdFileItem);
    
    // iWork uses a grid-layout theme picker and then zooms the preview of the selected template into the full screen. We don't yet have templates, but we could do the same someday.
    
    OBFinishPortingLater("Deal with having an open group and looking in the right picker scroll view");
    
    // At first it should not take up space.
    createdFileItem.layoutShouldAdvance = NO;
    [_mainScrollView setNeedsLayout];
    [_mainScrollView layoutIfNeeded];
    
    [self scrollItemToVisible:createdFileItem animated:NO];
    
    OUIDocumentPickerFileItemView *fileItemView = [_mainScrollView fileItemViewForFileItem:createdFileItem];
    OBASSERT(fileItemView != nil); // should have had a view assigned.
    fileItemView.alpha = 0; // start out transparent
    
    // Turn on layout advancing for this file item and do an animated layout, sliding to make room for it.
    createdFileItem.layoutShouldAdvance = YES;
    
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
             
             [_fileItemTappedTarget performSelector:_fileItemTappedAction withObject:createdFileItem];
             _isRevealingNewDocument = NO;
         });
         
         if (completionHandler)
             completionHandler();
     },
     nil];
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

@end
