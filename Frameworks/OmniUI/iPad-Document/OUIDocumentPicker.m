// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPicker.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreFilter.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>
#import <OmniFileStore/OFSDocumentStoreScope.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
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
#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniUI/OUIActionSheet.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIAnimationSequence.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentPickerGroupItemView.h>
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
#import <OmniUI/OUIDragGestureRecognizer.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUIDocument/OUIMainViewController.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUnzip/OUZipArchive.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

#import "OUIDocument-Internal.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerDragSession.h"
#import "OUIDocumentPickerSettings.h"
#import "OUIDocumentPickerView.h"
#import "OUIDocumentRenameViewController.h"
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

static NSString * const kActionSheetExportIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.ExportAction";
static NSString * const kActionSheetPickMoveDestinationScopeIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.PickMoveDestinationScope";
static NSString * const kActionSheetDeleteIdentifier = @"com.omnigroup.OmniUI.OUIDocumentPicker.DeleteAction";

static NSString * const TopItemsBinding = @"topItems";
static NSString * const OpenGroupItemsBinding = @"openGroupItems";

@interface OUIDocumentPicker () <MFMailComposeViewControllerDelegate>

@property(nonatomic,copy) NSSet *topItems;
@property(nonatomic,copy) NSSet *openGroupItems;
@property(nonatomic,strong) NSMutableDictionary *openInMapCache;

@property(nonatomic,readonly) BOOL canPerformActions;

@end

@implementation OUIDocumentPicker
{
    OUIDocumentPickerScrollView *_topScrollView;
    OUIDocumentPickerScrollView *_groupScrollView;
    
    OUIDocumentRenameViewController *_renameViewController;
    
    OUIReplaceDocumentAlert *_replaceDocumentAlert;
    
    BOOL _loadingFromNib;
    
    // Used to map between an exportType (UTI string) and BOOL indicating if an app exists that we can send it to via Document Interaction.
    NSMutableDictionary *_openInMapCache;
    
    UIToolbar *_toolbar;
    
    OFXAgentActivity *_agentActivity;
    UIBarButtonItem *_omniPresenceBarButtonItem;
    
    NSTimer *_omniPresenceAnimationTimer;
    NSUInteger _omniPresenceAnimationState;
    BOOL _omniPresenceAnimationLastLoop;
    
    UIBarButtonItem *_duplicateDocumentBarButtonItem;
    UIBarButtonItem *_exportBarButtonItem;
    UIBarButtonItem *_deleteBarButtonItem;
    UIBarButtonItem *_appTitleToolbarItem;
    UIButton *_appTitleToolbarButton;

    OFSDocumentStore *_documentStore;
    
    NSMutableArray *_afterDocumentStoreInitializationActions;
    
    NSUInteger _ignoreDocumentsDirectoryUpdates;
    
    OFSetBinding *_topItemsBinding;
    NSSet *_topItems;
    OFSetBinding *_openGroupItemsBinding;
    NSSet *_openGroupItems;
    
    OUIDocumentPickerDragSession *_dragSession;
}

static id _commonInit(OUIDocumentPicker *self)
{
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

static void _startObservingAgentActivity(OUIDocumentPicker *self, OFXAgentActivity *activity)
{
    [activity addObserver:self forKeyPath:OFValidateKeyPath(activity, isActive) options:0 context:&SyncActivityContext];
    [activity addObserver:self forKeyPath:OFValidateKeyPath(activity, accountUUIDsWithErrors) options:0 context:&SyncActivityContext];
}

static void _stopObservingAgentActivity(OUIDocumentPicker *self, OFXAgentActivity *activity)
{
    [activity removeObserver:self forKeyPath:OFValidateKeyPath(activity, isActive) context:&SyncActivityContext];
    [activity removeObserver:self forKeyPath:OFValidateKeyPath(activity, accountUUIDsWithErrors) context:&SyncActivityContext];
}

- (void)dealloc;
{
    OBPRECONDITION(_dragSession == nil, "it retains us anyway, so we can't get here otherwise");

    [OFPreference removeObserver:self forPreference:[[self class] filterPreference]];
    [OFPreference removeObserver:self forPreference:[[self class] sortPreference]];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:OUIDocumentPreviewsUpdatedForFileItemNotification object:nil];
    
    [_topItemsBinding invalidate];
    [_openGroupItemsBinding invalidate];
    
    if (_agentActivity) {
        _stopObservingAgentActivity(self, _agentActivity);
        _agentActivity = nil;
    }
        
}

#pragma mark -
#pragma mark KVC

@synthesize documentStore = _documentStore;
- (void)setDocumentStore:(OFSDocumentStore *)documentStore;
{
    OBPRECONDITION(![self isViewLoaded]); // Otherwise we'd need to fix the binding
    
    if (_documentStore == documentStore)
        return;

    _documentStore = documentStore;
    
    // I don't like doing this here, but it shouldn't actually change for the life of the documentPicker so...
    _documentStoreFilter = [[OFSDocumentStoreFilter alloc] initWithDocumentStore:_documentStore scope:_documentStore.defaultUsableScope];

    [self _flushAfterDocumentStoreInitializationActions];
    // Checks whether the document store has a file type for newly created documents
    [self _updateToolbarItemsAnimated:NO];
}

@synthesize delegate = _weak_delegate;

- (OFSDocumentStoreScope *)selectedScope;
{
    return _documentStoreFilter.scope;
}
- (void)setSelectedScope:(OFSDocumentStoreScope *)scope;
{
    self.emptyPickerView.hidden = YES; // Any time we change scope, we hide our overlay

    _documentStoreFilter.scope = scope;

    OFPreference *scopePreference = [[self class] _scopePreference];
    [scopePreference setStringValue:scope.identifier];

    [self scrollToTopAnimated:NO];
    
    // The delegate likely wants to update the title displayed in the document picker toolbar.
    [self updateTitle];

    // And we might need to show or hide the OmniPresence "sync now" button
    [self _updateToolbarItemsAnimated:NO];
    [self _updateOmniPresenceToolbarIcon];
    [self _updateViewControls];
}

- (OUIDocumentPickerScrollView *)activeScrollView;
{
    if ([_groupScrollView window])
        return _groupScrollView;
    return _mainScrollView;
}

- (OFSDocumentStoreScope *)_localDocumentsScope;
{
    for (OFSDocumentStoreScope *scope in _documentStore.scopes) {
        if (![scope isKindOfClass:[OFXDocumentStoreScope class]])
            return scope;
    }

    return nil;
}

- (IBAction)emptyTrash:(id)sender;
{
    OUIWithoutAnimating(^{
        [self clearSelection:YES];

        for (OFSDocumentStoreFileItem *fileItem in _documentStore.trashScope.fileItems)
            fileItem.selected = YES;

        [self.view layoutIfNeeded];
    });

    [self setEditing:YES animated:YES];
    [self deleteDocument:self.emptyTrashButton];
}

- (IBAction)moveAllDocumentsToCloudButtonTapped:(id)sender;
{
    [self _beginIgnoringDocumentsDirectoryUpdates];
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    NSSet *fileItems = [[self _localDocumentsScope] fileItems];
    [_documentStore moveFileItems:fileItems toScope:self.selectedScope completionHandler:^(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil) {
        [self clearSelection:YES];
        [self _endIgnoringDocumentsDirectoryUpdates];
        [self _performDelayedItemPropagationWithCompletionHandler:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            if (failingItem)
                OUI_PRESENT_ALERT(errorOrNil);
        }];
    }];
}

@synthesize openInMapCache = _openInMapCache;

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
        OFSDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:targetURL];
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

- (NSSet *)selectedFileItems;
{
    return [self.selectedScope.fileItems select:^(id obj){
        OFSDocumentStoreFileItem *fileItem = obj;
        return fileItem.selected;
    }];
}

- (NSUInteger)selectedFileItemCount;
{
    NSUInteger selectedCount = 0;
    
    for (OFSDocumentStoreFileItem *fileItem in self.selectedScope.fileItems)
        if (fileItem.selected)
            selectedCount++;
    
    return selectedCount;
}

- (void)clearSelection:(BOOL)shouldEndEditing;
{
    // Clear selection on ALL scopes, just in case.
    for (OFSDocumentStoreFileItem *fileItem in _documentStore.mergedFileItems) {
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

- (IBAction)newDocument:(id)sender;
{
    OBPRECONDITION(_renameViewController == nil); // Can't be renaming right now, so need to try to stop

    if (!self.canPerformActions)
        return;
    
    // Get rid of any visible popovers immediately
    [[OUIAppController controller] dismissPopoverAnimated:NO];
    
    [self _beginIgnoringDocumentsDirectoryUpdates];
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    [_documentStore createNewDocumentInScope:_documentStoreFilter.scope completionHandler:^(OFSDocumentStoreFileItem *createdFileItem, NSError *error){

        if (!createdFileItem) {
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            [self _endIgnoringDocumentsDirectoryUpdates];
            OUI_PRESENT_ERROR(error);
            return;
        }
                
        // We want the file item to have a new date, but this is the wrong place to do it. Want to do it in the document picker before it creates the item.
        // [[NSFileManager defaultManager] touchItemAtURL:createdItem.fileURL error:NULL];
        
        [self _revealAndActivateNewDocumentFileItem:createdFileItem completionHandler:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            [self _endIgnoringDocumentsDirectoryUpdates];
        }];
    }];
}

- (void)_didDuplicateFileItem:(OFSDocumentStoreFileItem *)originalItem toFileItem:(OFSDocumentStoreFileItem *)newItem;
{
    // do nothing extra here, just available for subclasses
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
        [fileItem.scope addDocumentInFolderAtURL:nil fromURL:fileItem.fileURL option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
            OBASSERT([NSThread isMainThread]); // gets enqueued on the main thread, but even if it was invoked on the background serial queue, this would be OK as long as we don't access the mutable arrays until all the blocks are done
            
            if (!duplicateFileItem) {
                OBASSERT(error);
                if (error) // let's not crash, though...
                    [errors addObject:error];
                return;
            }
            
            [self _didDuplicateFileItem:fileItem toFileItem:duplicateFileItem];
            [duplicateFileItems addObject:duplicateFileItem];
            
            // Copy the previews for the original file item to be the previews for the duplicate.
            [OUIDocumentPreview cachePreviewImagesForFileURL:duplicateFileItem.fileURL date:duplicateFileItem.fileModificationDate
                                    byDuplicatingFromFileURL:fileItem.fileURL date:fileItem.fileModificationDate];
            
            // Copy document view state
            [OUIDocumentAppController moveDocumentStateFromURL:fileItem.fileURL toURL:duplicateFileItem.fileURL deleteOriginal:NO];
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
    
    // Validate each item
    for (OFSDocumentStoreFileItem *fileItem in selectedFileItems) {
        
        // Make sure the item is fully downloaded.
        if (!fileItem.isDownloaded) {
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

    
    switch (fileItemCount) {
        case 0:
            OBASSERT_NOT_REACHED("Make this button be disabled");
            return;
        case 1:
            [self _duplicateFileItemsWithoutConfirmation:selectedFileItems];
            break;
        default: {
            OUIActionSheet *prompt = [[OUIActionSheet alloc] initWithIdentifier:nil];
            id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
            
            NSString *format = nil;
            if ([delegate respondsToSelector:@selector(documentPickerAlertTitleFormatForDuplicatingFileItems:)])
                format = [delegate documentPickerAlertTitleFormatForDuplicatingFileItems:selectedFileItems];
            if ([NSString isEmptyString:format])
                format = NSLocalizedStringFromTableInBundle(@"Duplicate %ld Documents", @"OmniUIDocument", OMNI_BUNDLE, @"title for alert option confirming duplication of multiple files");
            OBASSERT([format containsString:@"%ld"]);

            [prompt addButtonWithTitle:[NSString stringWithFormat:format, fileItemCount] forAction:^{
                [self _duplicateFileItemsWithoutConfirmation:selectedFileItems];
            }];
            [[OUIAppController controller] showActionSheet:prompt fromSender:sender animated:NO];
        }
    }
}

- (void)replaceDocumentAlert:(OUIReplaceDocumentAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex documentURL:(NSURL *)documentURL;
{
    OFSDocumentStoreScope *scope = self.selectedScope;
    
    // TODO: Would like to find a better way to code this so we don't have so much duplicated.
    switch (buttonIndex) {
        case 0: /* Cancel */
            break;
        
        case 1: /* Replace */
        {
            [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
            [scope addDocumentInFolderAtURL:nil fromURL:documentURL option:OFSDocumentStoreAddByReplacing completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
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

            [scope addDocumentInFolderAtURL:nil fromURL:documentURL option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
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
    
    _replaceDocumentAlert = nil;
}

- (void)addDocumentFromURL:(NSURL *)url;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    OFSDocumentStoreScope *existingScope = [_documentStore scopeForFileName:[url lastPathComponent] inFolder:nil];
    if (existingScope) {
        OBASSERT(_replaceDocumentAlert == nil); // this should never happen
        _replaceDocumentAlert = [[OUIReplaceDocumentAlert alloc] initWithDelegate:self documentURL:url];
        [_replaceDocumentAlert show];
        return;

    }
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    OFSDocumentStoreScope *scope = _documentStoreFilter.scope;
    OBASSERT(scope);
    
    [scope addDocumentInFolderAtURL:nil fromURL:url option:OFSDocumentStoreAddNormally completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
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

- (void)addSampleDocumentFromURL:(NSURL *)url;
{
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    NSString *fileName = [url lastPathComponent];
    NSString *localizedBaseName = [[OUIDocumentAppController controller] localizedNameForSampleDocumentNamed:[fileName stringByDeletingPathExtension]];
    
    OFSDocumentStoreScope *scope = self.selectedScope;
    [scope addDocumentInFolderAtURL:nil baseName:localizedBaseName fromURL:url option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) {
        
        if (!duplicateFileItem) {
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            OUI_PRESENT_ERROR(error);
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

- (NSArray *)availableFilters;
{
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPickerAvailableFilters:)])
        return [delegate documentPickerAvailableFilters:self];
    return nil;
}

- (NSArray *)availableExportTypesForFileItem:(OFSDocumentStoreFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
{
    NSMutableArray *exportTypes = [NSMutableArray array];
    
    // Get All Available Export Types
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:availableExportTypesForFileItem:serverAccount:exportOptionsType:)]) {
        [exportTypes addObjectsFromArray:[delegate documentPicker:self availableExportTypesForFileItem:fileItem serverAccount:serverAccount exportOptionsType:exportOptionsType]];
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

- (NSArray *)availableImageExportTypesForFileItem:(OFSDocumentStoreFileItem *)fileItem;
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

// Helper method for -availableDocuentInteractionExportTypesForFileItem:
- (BOOL)_canUseOpenInWithExportType:(NSString *)exportType;
{
    NSNumber *value = [self.openInMapCache objectForKey:exportType];
    if (value) {
        // We have a cached value, so immediately return it.
        return [value boolValue];
    }
    
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
    completionHandler = [completionHandler copy]; // preserve scope
    
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:exportFileWrapperOfType:forFileItem:withCompletionHandler:)]) {
        [delegate documentPicker:self exportFileWrapperOfType:exportType forFileItem:fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
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
        fileData = [delegate documentPicker:self PDFDataForFileItem:fileItem error:&error];
        pathExtension = @"pdf";
    } else if (UTTypeConformsTo((__bridge CFStringRef)exportType, kUTTypePNG) && [delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)]) {
        fileData = [delegate documentPicker:self PNGDataForFileItem:fileItem error:&error];
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

// OBFinishPortingLater -- move this into OFUTI?
static NSDictionary *_findTypeDeclaration(NSString *fileType) 
{
    // Look at our type declarations, where we can use -[UIImage imageNamed:] to get the right image (at the right scale).
    // We do _not_ fall back to UTTypeCopyDeclaration() since if we would, the image isn't in our bundle and we can't look it up (so we need to fall back to UIDIC anyway).
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    
    NSArray *exportedTypes = [infoDictionary objectForKey:@"UTExportedTypeDeclarations"];
    for (NSDictionary *type in exportedTypes) {
        if ([[type objectForKey:@"UTTypeIdentifier"] caseInsensitiveCompare:fileType] == NSOrderedSame)
            return type;
    }
    
    NSArray *importedTypes = [infoDictionary objectForKey:@"UTImportedTypeDeclarations"];
    for (NSDictionary *type in importedTypes) {
        if ([[type objectForKey:@"UTTypeIdentifier"] caseInsensitiveCompare:fileType] == NSOrderedSame)
            return type;
    }
    
    return nil;
}

static UIImage *_findUnscaledIconForUTI(NSString *fileUTI, NSUInteger targetSize)
{
    // UIDocumentInteractionController seems to only return a single icon.
    NSDictionary *utiDecl = _findTypeDeclaration(fileUTI);
    if (utiDecl) {
        // Look for an icon with the specified size.
        NSArray *iconFiles = [utiDecl objectForKey:@"UTTypeIconFiles"];
        NSString *sizeString = [NSString stringWithFormat:@"%lu", targetSize]; // This is a little optimistic, but unlikely to fail.
        for (NSString *iconName in iconFiles) {
            // Skip the 2x variant. -imageNamed: will give us that if we find a point-size match.
            if ([iconName containsString:@"@2x"])
                continue;

            if ([iconName rangeOfString:sizeString].location != NSNotFound) {
                UIImage *image = [UIImage imageNamed:iconName];
                if (image)
                    return image;
            }
        }
    }
    
    if (UTTypeConformsTo((__bridge CFStringRef)fileUTI, kUTTypePDF)) {
        UIImage *image = [UIImage imageNamed:@"OUIPDF.png"];
        if (image)
            return image;
    }
    if (UTTypeConformsTo((__bridge CFStringRef)fileUTI, kUTTypePNG)) {
        UIImage *image = [UIImage imageNamed:@"OUIPNG.png"];
        if (image)
            return image;
    }
    
    
    // Might be a system type or type defined by another app
#if 0 && defined(DEBUG_bungi)
    {
        CFURLRef url = UTTypeCopyDeclaringBundleURL((CFStringRef)fileUTI);
        NSLog(@"Trying to find an image for type \"%@\" defined by bundle %@", fileUTI, url);
        CFRelease(url);
        
        CFDictionaryRef utiDecl = UTTypeCopyDeclaration((CFStringRef)fileUTI);
        if (utiDecl) {
            NSLog(@"Declaration %@", utiDecl);
            CFRelease(utiDecl);
        }
    }
#endif
    UIDocumentInteractionController *documentInteractionController = [[UIDocumentInteractionController alloc] init];
    documentInteractionController.UTI = fileUTI;
    if (documentInteractionController.icons.count == 0) {
        CFStringRef extension = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileUTI, kUTTagClassFilenameExtension);
        if (extension != NULL) {
            documentInteractionController.name = [@"Untitled" stringByAppendingPathExtension:(__bridge NSString *)extension];
            CFRelease(extension);
        }
        if (documentInteractionController.icons.count == 0) {
            documentInteractionController.UTI = nil;
            documentInteractionController.name = @"Untitled";
        }
    }

    OBASSERT(documentInteractionController.icons.count != 0); // Or we should attach our own default icon
    UIImage *bestImage = nil;
    CGFloat scale = [[UIScreen mainScreen] scale];
    for (UIImage *image in documentInteractionController.icons) {
#if 0 && defined(DEBUG_bungi)
        NSLog(@"  image %@ %@, scale %f", image, NSStringFromCGSize([image size]), [image scale]);
#endif
        if (CGSizeEqualToSize(image.size, CGSizeMake(targetSize, targetSize)) && [image scale] == scale) {
            bestImage = image; // This image fits our target size and device scale
            break;
        }
    }

    if (bestImage == nil) {
        // Pick something -- we might want to ensure we aren't picking a tiny image and scaling it up.
        bestImage = [documentInteractionController.icons lastObject];
    }


    if (bestImage != nil)
        return bestImage;
    else
        return [UIImage imageNamed:@"OUIDocument.png"];
}

- (UIImage *)_iconForUTI:(NSString *)fileUTI size:(NSUInteger)targetSize cache:(NSCache *)cache;
{
    UIImage *unscaledImage = _findUnscaledIconForUTI(fileUTI, targetSize);
    if (!unscaledImage)
        return nil;
    
    CGSize size = [unscaledImage size];
    OBASSERT(size.width == size.height);
    
    if (targetSize == size.width)
        return unscaledImage;
    
    // Cache these: if we have a WebDAV server with a bunch of the same file, this will be a scrolling win
    UIImage *resultImage = [cache objectForKey:fileUTI];
    if (!resultImage) {
        //NSLog(@"Filling cache for %@ at %ld, starting from %@", fileUTI, targetSize, NSStringFromCGSize(size));
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(targetSize, targetSize), NO/*opaque*/, 0/*device scale*/);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGRect bounds = CGRectMake(0, 0, targetSize, targetSize);
        CGContextClearRect(ctx, bounds);
        CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
        [unscaledImage drawInRect:bounds];
        resultImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        [cache setObject:resultImage forKey:fileUTI];
    }
    
    return resultImage;
}

- (UIImage *)iconForUTI:(NSString *)fileUTI;
{
    UIImage *icon = nil;
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:iconForUTI:)])
        icon = [delegate documentPicker:self iconForUTI:(CFStringRef)fileUTI];
    if (icon == nil) {
        static NSCache *cache = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            cache = [[NSCache alloc] init];
            [cache setName:@"OUIDocumentPicker iconForUTI:"];
        });
        icon = [self _iconForUTI:fileUTI size:32 cache:cache];
    }
    return icon;
}

- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
{
    UIImage *icon = nil;
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:exportIconForUTI:)])
        icon = [delegate documentPicker:self exportIconForUTI:(CFStringRef)fileUTI];
    if (icon == nil) {
        static NSCache *cache = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            cache = [[NSCache alloc] init];
            [cache setName:@"OUIDocumentPicker exportIconForUTI:"];
        });
        icon = [self _iconForUTI:fileUTI size:128 cache:cache];
    }
    return icon;
}

- (NSString *)exportLabelForUTI:(NSString *)fileUTI;
{
    NSString *customLabel = nil;
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:labelForUTI:)])
        customLabel = [delegate documentPicker:self labelForUTI:(CFStringRef)fileUTI];
    if (customLabel != nil)
        return customLabel;
    if (UTTypeConformsTo((__bridge CFStringRef)fileUTI, kUTTypePDF))
        return @"PDF";
    if (UTTypeConformsTo((__bridge CFStringRef)fileUTI, kUTTypePNG))
        return @"PNG";
    return nil;
}

- (NSString *)deleteDocumentTitle:(NSUInteger)count;
{
    OBPRECONDITION(count > 0);
    
    if (count == 1)
        return NSLocalizedStringFromTableInBundle(@"Delete Document", @"OmniUIDocument", OMNI_BUNDLE, @"delete button title");
    return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Delete %ld Documents", @"OmniUIDocument", OMNI_BUNDLE, @"delete button title"), count];
}

- (IBAction)deleteDocument:(id)sender;
{
    NSSet *fileItemsToDelete = [self selectedFileItems];
    
    if ([fileItemsToDelete count] == 0) {
        OBASSERT_NOT_REACHED("Delete toolbar item shouldn't have been enabled");
        return;
    }
    
    if (!self.canPerformActions)
        return;

    OUIActionSheet *actionSheet = [[OUIActionSheet alloc] initWithIdentifier:kActionSheetDeleteIdentifier];
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
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:printButtonTitleForFileItem:)]) {
        return [delegate documentPicker:self printButtonTitleForFileItem:nil];
    }
    
    return NSLocalizedStringFromTableInBundle(@"Print", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view");
}

- (IBAction)export:(id)sender;
{
    if (!self.canPerformActions)
        return;

    OUIActionSheet *actionSheet = [[OUIActionSheet alloc] initWithIdentifier:kActionSheetExportIdentifier];

    // "Move to" for each scope that isn't the selected scope
    if ([_documentStore.scopes count] > 1) {
        NSMutableArray *otherScopes = [_documentStore.scopes mutableCopy];
        [otherScopes removeObject:self.selectedScope];
        [otherScopes removeObject:_documentStore.trashScope];
        [otherScopes sortUsingSelector:@selector(compareDocumentScope:)];
        
        switch ([otherScopes count]) {
            case 0:
                // Nowhere to move
                break;
            case 1:
            {
                OFSDocumentStoreScope *otherScope = otherScopes[0];
                [actionSheet addButtonWithTitle:[otherScope moveToActionLabelWhenInList:NO] forAction:^{
                    [self _moveSelectedDocumentsToScope:otherScope];
                }];
                break;
            }
            default:
                [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Move to...", @"OmniUIDocument", OMNI_BUNDLE, @"Action sheet button title") forAction:^{
                    [self _showMoveMenuWithScopes:otherScopes fromSender:sender];
                }];
                break;
        }
    }

    if (self.selectedFileItems.count > 1) {
        [[OUIAppController controller] showActionSheet:actionSheet fromSender:sender animated:YES];
        return;
    }

    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem){
        OBASSERT_NOT_REACHED("Make this button be disabled");
        return;
    }

    // Make sure selected item is fully downloaded.
    if (!fileItem.isDownloaded) {
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
    
    NSURL *url = fileItem.fileURL;
    if (url == nil)
        return;

    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    
    BOOL canExport = [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"OUIExportEnabled"];
    NSArray *availableExportTypes = [self availableExportTypesForFileItem:fileItem serverAccount:nil exportOptionsType:OUIExportOptionsNone];
    NSArray *availableImageExportTypes = [self availableImageExportTypesForFileItem:fileItem];
    BOOL canSendToCameraRoll = [delegate respondsToSelector:@selector(documentPicker:cameraRollImageForFileItem:)];
    BOOL canPrint = NO;
    BOOL canUseOpenIn = [self _canUseOpenInWithFileItem:fileItem];
    
    if ([delegate respondsToSelector:@selector(documentPicker:printFileItem:fromButton:)])
        if ([UIPrintInteractionController isPrintingAvailable])  // "Some iOS devices do not support printing"
            canPrint = YES;
    
    OB_UNUSED_VALUE(availableExportTypes); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning

    if ([MFMailComposeViewController canSendMail]) {
        // All email options should go here (within the test for whether we can send email)
        // more than one option? Display the 'export options sheet'
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  if (availableExportTypes.count > 0)
                                      [self emailDocumentChoice:self];
                                  else
                                      [self emailDocument:self];
                              }];
    }
    
    if (canExport) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  [self exportDocument:self];
                              }];
    }
    
    if (canUseOpenIn) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send to App", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  [self sendToApp:self];
                              }];
    }
    
    if (availableImageExportTypes.count > 0) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Copy as Image", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view")
                              forAction:^{
                                  [self copyAsImage:self];
        }];
    }
    
    if (canSendToCameraRoll) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send to Photos", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view")
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

    if ([delegate respondsToSelector:@selector(documentPicker:addExportActions:)]) {
        [delegate documentPicker:self addExportActions:^(NSString *title, void (^action)(void)){
            [actionSheet addButtonWithTitle:title
                                  forAction:action];
        }];
     }
    
    [[OUIAppController controller] showActionSheet:actionSheet fromSender:sender animated:YES];
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
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    return ![delegate respondsToSelector:@selector(documentPicker:canUseEmailBodyForType:)] || [delegate documentPicker:self canUseEmailBodyForType:exportType];
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
    [OUISyncMenuController displayInSheet];
}

- (void)emailDocumentChoice:(id)sender;
{
    OUIExportOptionsController *exportController = [[OUIExportOptionsController alloc] initWithServerAccount:nil exportType:OUIExportOptionsEmail];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:exportController];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    OUIAppController *appController = [OUIAppController controller];
    [appController.topViewController presentViewController:navigationController animated:YES completion:nil];
    
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
    OFSDocumentStoreFileItem *fileItem = self.singleSelectedFileItem;
    if (!fileItem) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    [delegate documentPicker:self printFileItem:fileItem fromButton:_exportBarButtonItem];
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

    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    BOOL canMakeCopyAsImageSpecificPDF = [delegate respondsToSelector:@selector(documentPicker:copyAsImageDataForFileItem:error:)];
    BOOL canMakePDF = [delegate respondsToSelector:@selector(documentPicker:PDFDataForFileItem:error:)];
    BOOL canMakePNG = [delegate respondsToSelector:@selector(documentPicker:PNGDataForFileItem:error:)];

    //- (NSData *)documentPicker:(OUIDocumentPicker *)picker copyAsImageDataForFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
    if (canMakeCopyAsImageSpecificPDF) {
        __autoreleasing NSError *error = nil;
        NSData *pdfData = [delegate documentPicker:self copyAsImageDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    } else if (canMakePDF) {
        __autoreleasing NSError *error = nil;
        NSData *pdfData = [delegate documentPicker:self PDFDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    }
    
    // Don't put more than one image format on the pasteboard, because both will get pasted into iWork.  <bug://bugs/61070>
    if (!canMakeCopyAsImageSpecificPDF &&!canMakePDF && canMakePNG) {
        __autoreleasing NSError *error = nil;
        NSData *pngData = [delegate documentPicker:self PNGDataForFileItem:fileItem error:&error];
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

    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    UIImage *image = [delegate documentPicker:self cameraRollImageForFileItem:fileItem];
    OBASSERT(image); // There is no default implementation -- the delegate should return something.

    if (image)
        UIImageWriteToSavedPhotosAlbum(image, self, @selector(_sendToCameraRollImage:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)_sendToCameraRollImage:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
{
    OUI_PRESENT_ERROR(error);
}

+ (OFPreference *)_scopePreference;
{
    static OFPreference *scopePreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scopePreference = [OFPreference preferenceForKey:@"OUIDocumentPickerSelectedScope"];
    });
    
    return scopePreference;
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

- (void)ensureSelectedFilterMatchesFileURL:(NSURL *)fileURL;
{
    OFSDocumentStoreFileItem *fileItem = [_documentStore fileItemWithURL:fileURL];
    if (fileItem) {
        [self ensureSelectedFilterMatchesFileItem:fileItem];
    } else {
        OBASSERT_NOT_REACHED("Unknown file URL");
    }
}

- (void)ensureSelectedFilterMatchesFileItem:(OFSDocumentStoreFileItem *)fileItem;
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

- (void)_loadScopeFromPreference;
{
    OBPRECONDITION(_documentStore);
    OBPRECONDITION(_documentStoreFilter);
    
    OFPreference *scopePreference = [[self class] _scopePreference];
    NSString *identifier = [scopePreference stringValue];
    NSArray *availableScopes = _documentStore.scopes;
    
    OFSDocumentStoreScope *scope = [availableScopes first:^BOOL(OFSDocumentStoreScope *scope) {
        return [scope.identifier isEqualToString:identifier];
    }];

    [self addDocumentStoreInitializationAction:^(OUIDocumentPicker *blockSelf){
        blockSelf.selectedScope = scope;
    }];
}

- (void)selectedFilterChanged;
{
    OBPRECONDITION(_documentStoreFilter);
    
    OFPreference *filterPreference = [[self class] filterPreference];
    NSString *identifier = [filterPreference stringValue];
    NSArray *availableFilters = self.availableFilters;
    
    OUIDocumentPickerFilter *filter = [availableFilters first:^BOOL(OUIDocumentPickerFilter *filter) {
        return [filter.identifier isEqualToString:identifier];
    }];
    if (!filter && [availableFilters count] > 0) {
        filter = [availableFilters objectAtIndex:0];
        
        // Fix the preference for other readers to know what we eneded up using. We'll get called reentrantly here now.
        [filterPreference setStringValue:filter.identifier];
    }
    
    [self scrollToTopAnimated:NO];
    
    [self addDocumentStoreInitializationAction:^(OUIDocumentPicker *blockSelf){
        blockSelf->_documentStoreFilter.filterPredicate = filter.predicate;
    }];

    // The delegate likely wants to update the title displayed in the document picker toolbar.
    [self updateTitle];
}

- (void)selectedSortChanged;
{
    [self scrollToTopAnimated:NO];
    
    OUIDocumentPickerItemSort sort = [[[self class] sortPreference] enumeratedValue];
    _mainScrollView.itemSort = sort;
    _groupScrollView.itemSort = sort;
}

- (void)filterSegmentChanged:(id)sender;
{
    OUIDocumentPickerFilter *filter = [[self availableFilters] objectAtIndex:((UISegmentedControl *)sender).selectedSegmentIndex];
    [[[self class] filterPreference] setStringValue:filter.identifier];
}

- (void)sortSegmentChanged:(id)sender;
{
    [[[self class] sortPreference] setEnumeratedValue:((UISegmentedControl *)sender).selectedSegmentIndex];
}

- (void)addDocumentStoreInitializationAction:(void (^)(OUIDocumentPicker *blockSelf))action;
{
    if (!_afterDocumentStoreInitializationActions)
        _afterDocumentStoreInitializationActions = [[NSMutableArray alloc] init];
    [_afterDocumentStoreInitializationActions addObject:[action copy]];
    
    // ... might be able to call it right now
    [self _flushAfterDocumentStoreInitializationActions];
}

- (NSString *)mainToolbarTitle;
{
    if ([_documentStore.scopes count] > 1)
        return self.selectedScope.displayName;

    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPickerMainToolbarTitle:)]) {
        return [delegate documentPickerMainToolbarTitle:self];
    }
    
    return NSLocalizedStringWithDefaultValue(@"Documents <main toolbar title>", @"OmniUIDocument", OMNI_BUNDLE, @"Documents", @"Main toolbar title");
}

- (void)updateTitle;
{    
    NSString *title = [self mainToolbarTitle];
    
    // Had to add a space after the title to make padding between the title and the image. I tried using UIEdgeInsets on the image, title and content but could not get it to work horizontally. I did, however, get it to work to vertically align the image.
    [_appTitleToolbarButton setTitle:[title stringByAppendingString:@" "] forState:UIControlStateNormal];
    [_appTitleToolbarButton sizeToFit];
    [_appTitleToolbarButton layoutIfNeeded];
}

- (NSError *)selectedScopeError;
{
    OFSDocumentStoreScope *selectedScope = self.selectedScope;
    
    if (![selectedScope isKindOfClass:[OFXDocumentStoreScope class]])
        return nil;
    OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)selectedScope;
    
    OFXAgentActivity *agentActivity = [OUIDocumentAppController controller].agentActivity;
    OFXAccountActivity *accountActivity = [agentActivity activityForAccount:scope.account];
    return accountActivity.lastError;
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    _toolbar.items = self.toolbarItems;

    BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
    
    // This isn't necessary and it makes the scroll view extend behind the bottom toolbar.
    // CGRect viewBounds = self.view.bounds;
    // _mainScrollView.frame = viewBounds;
    
    _mainScrollView.landscape = landscape;
    
    _groupScrollView.landscape = landscape;
    [_groupScrollView removeFromSuperview]; // We'll put it back when opening a group
    
    [self _loadScopeFromPreference];
    
    OFPreference *sortPreference = [[self class] sortPreference];
    [OFPreference addObserver:self selector:@selector(selectedSortChanged) forPreference:sortPreference];
    [self selectedSortChanged];
    
    OFPreference *filterPreference = [[self class] filterPreference];
    [OFPreference addObserver:self selector:@selector(selectedFilterChanged) forPreference:filterPreference];
    [self selectedFilterChanged];
    
    [self _setupTopItemsBinding];
    
    [self _setupBottomToolbar];
    
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
    
    [self _updateViewControls];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];

    [self _updateViewControls];
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
    
    // The rename view controller overrides our toolbar's items. Might need a more general check for "has some other view controller taken over the toolbar" (or maybe such controller should have their own toolbar).
    if (_renameViewController == nil) {
        [_toolbar setItems:toolbarItems animated:animated];
    }
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self clearSelection:YES];
    
    [[[OUIAppController controller] topViewController] dismissViewControllerAnimated:YES completion:nil];
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

#pragma mark -
#pragma mark OUIDocumentPickerScrollView delegate

static void _setItemSelectedAndBounceView(OUIDocumentPicker *self, OUIDocumentPickerFileItemView *fileItemView, BOOL selected)
{
    OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)fileItemView.item;
    OBASSERT([fileItem isKindOfClass:[OFSDocumentStoreFileItem class]]);

    // Turning the selection on/off changes how the file item view lays out. We don't want that to animate though -- we just want the bounch down. If we want the selection layer to fade/grow in, we'd need a 'will changed selected'/'did change selected' path that where we can change the layout but not have the selection layer appear yet (maybe fade it in) and only disable animation on the layout change.
    OUIWithoutAnimating(^{        
        fileItem.selected = selected;
        [fileItemView layoutIfNeeded];
    });
    
    // In addition to the border, iWork bounces the file item view down slightly on a tap (selecting or deselecting).
    [fileItemView bounceDown];
}

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView inArea:(OUIDocumentPickerItemViewTapArea)area;
{
    if (!self.canPerformActions || _renameViewController) // Another rename might be starting (we don't have a spot to start/stop ignore user interaction there since the keyboard drives the animation).
        return;
            
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
                // Only allow selection if the file is already downloaded.
                _setItemSelectedAndBounceView(self, fileItemView, !fileItem.selected);
                
                [self _updateToolbarItemsAnimated:NO]; // Update the selected file item count
                [self _updateToolbarItemsEnabledness];
            } else {
                id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
                if ([delegate respondsToSelector:@selector(documentPicker:openTappedFileItem:)])
                    [delegate documentPicker:self openTappedFileItem:fileItem];
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

#pragma mark - OUIDocumentPickerDragSession callbacks

- (void)dragSessionTerminated;
{
    _dragSession = nil;
}

#pragma mark - Internal

- (OUIMainViewController *)mainViewController;
{
    OUIMainViewController *vc = (OUIMainViewController *)self.parentViewController;
    OBASSERT([vc isKindOfClass:[OUIMainViewController class]]); // Don't call this method when we aren't currently its child (and warn if we get a different parent).
    return vc;
}

- (OFSDocumentStoreFileItem *)_preferredVisibleItemFromSet:(NSSet *)fileItemsNeedingPreviewUpdate;
{
    // Don't think too hard if there is just a single incoming iCloud update
    if ([fileItemsNeedingPreviewUpdate count] <= 1)
        return [fileItemsNeedingPreviewUpdate anyObject];
    
    // Find a file preview that will update something in the user's view.
    OFSDocumentStoreFileItem *fileItem = nil;
    if ([_groupScrollView window])
        fileItem = [_groupScrollView preferredVisibleItemFromSet:fileItemsNeedingPreviewUpdate];
    if (!fileItem)
        fileItem = [_mainScrollView preferredVisibleItemFromSet:fileItemsNeedingPreviewUpdate];

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
    
    OUIDocumentAppController *controller = [OUIDocumentAppController controller];
    BOOL editing = self.isEditing;
    
    NSMutableArray *toolbarItems = [NSMutableArray array];
    
    if (editing) {
        if (!_exportBarButtonItem) {
            // We keep pointers to a few toolbar items that we need to update enabledness on.
            _exportBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentExport.png"] style:UIBarButtonItemStylePlain target:self action:@selector(export:)];
            _exportBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"Export toolbar item accessibility label.");
            _duplicateDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentDuplicate.png"] style:UIBarButtonItemStylePlain target:self action:@selector(duplicateDocument:)];
            _duplicateDocumentBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Duplicate", @"OmniUIDocument", OMNI_BUNDLE, @"Duplicate toolbar item accessibility label.");
            _deleteBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIDocumentDelete.png"] style:UIBarButtonItemStylePlain target:self action:@selector(deleteDocument:)];
            _deleteBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Delete", @"OmniUIDocument", OMNI_BUNDLE, @"Delete toolbar item accessibility label.");
        }
        
        _exportBarButtonItem.enabled = NO;
        _duplicateDocumentBarButtonItem.enabled = NO;
        _deleteBarButtonItem.enabled = NO;
        
        [toolbarItems addObject:_exportBarButtonItem];
        [toolbarItems addObject:_duplicateDocumentBarButtonItem];
        [toolbarItems addObject:_deleteBarButtonItem];
    } else {
        if (_documentStore.documentTypeForNewFiles != nil) {
            UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarAddDocument.png"] 
                                                                         style:UIBarButtonItemStylePlain 
                                                                        target:controller action:@selector(makeNewDocument:)];
            addItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"New Document", @"OmniUIDocument", OMNI_BUNDLE, @"New Document toolbar item accessibility label.");
            [toolbarItems addObject:addItem];
        }
    }
    
    [toolbarItems addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL]];
    
    if (editing) {
        NSSet *selectedFileItems = self.selectedFileItems;
        NSUInteger selectedFileItemCount = [selectedFileItems count];

        NSString *format = nil;
        id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
        if ([delegate respondsToSelector:@selector(documentPickerMainToolbarSelectionFormatForFileItems:)])
            format = [delegate documentPickerMainToolbarSelectionFormatForFileItems:selectedFileItems];
        if ([NSString isEmptyString:format]) {
            if (selectedFileItemCount == 0)
                format = NSLocalizedStringFromTableInBundle(@"Select a Document", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a no selected documents.");
            else if (selectedFileItemCount == 1)
                format = NSLocalizedStringFromTableInBundle(@"1 Document Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a single selected document.");
            else
                format = NSLocalizedStringFromTableInBundle(@"%ld Documents Selected", @"OmniUIDocument", OMNI_BUNDLE, @"Main toolbar title for a multiple selected documents.");
        }

        NSString *title = [NSString stringWithFormat:format, [selectedFileItems count]];
        
        
        UILabel *label = [[UILabel alloc] init];
        label.text = title;
        label.backgroundColor = [UIColor clearColor];
        label.font = [UIFont boldSystemFontOfSize:20.0];
        label.textColor = [UIColor whiteColor];
        [label sizeToFit];
        
        
        UIBarButtonItem *selectionItem = [[UIBarButtonItem alloc] initWithCustomView:label];
        
        [toolbarItems addObject:selectionItem];
    } else {
        if ([self.selectedScope isKindOfClass:[OFXDocumentStoreScope class]]) {
#ifdef OMNI_ASSERTIONS_ON
            OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)self.selectedScope;
#endif
            if (!_omniPresenceBarButtonItem) {
                _omniPresenceBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon.png"] style:UIBarButtonItemStylePlain target:controller action:@selector(manualSync:)];
                _omniPresenceBarButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Sync Now", @"OmniUIDocument", OMNI_BUNDLE, @"Presence toolbar item accessibility label.");
            }
            
            if (!_agentActivity) {
                _agentActivity = [OUIDocumentAppController controller].agentActivity;
                _startObservingAgentActivity(self, _agentActivity);
            }
            [self _updateOmniPresenceToolbarIcon];
            
            OBASSERT(scope.syncAgent == _agentActivity.agent);
            [toolbarItems addObject:_omniPresenceBarButtonItem];
        } else {
            _stopObservingAgentActivity(self, _agentActivity);
            _agentActivity = nil;
        }

        if (!_appTitleToolbarItem) {
            OBASSERT(_appTitleToolbarButton == nil);
            
            _appTitleToolbarButton = [OUIToolbarTitleButton buttonWithType:UIButtonTypeCustom];
            UIImage *disclosureImage = [UIImage imageNamed:@"OUIToolbarTitleDisclosureButton.png"];
            OBASSERT(disclosureImage != nil);
            [_appTitleToolbarButton setImage:disclosureImage forState:UIControlStateNormal];
            
            _appTitleToolbarButton.imageEdgeInsets = (UIEdgeInsets){.top = 4}; // Push the button down a bit to line up with the x height
            
            _appTitleToolbarButton.titleLabel.font = [UIFont boldSystemFontOfSize:20.0];

            _appTitleToolbarButton.adjustsImageWhenHighlighted = NO;
            [_appTitleToolbarButton addTarget:self action:@selector(_showViewSettings:) forControlEvents:UIControlEventTouchUpInside];
            _appTitleToolbarButton.accessibilityHint = NSLocalizedStringFromTableInBundle(@"Displays view options", @"OmniUIDocument", OMNI_BUNDLE, @"App Title Toolbar Button accessibility hint.");
            
            [self updateTitle];
            
            _appTitleToolbarItem = [[UIBarButtonItem alloc] initWithCustomView:_appTitleToolbarButton];
        }
        [toolbarItems addObject:_appTitleToolbarItem];
    }
    
    [toolbarItems addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL]];
    
    if (!editing)
        [toolbarItems addObject:controller.appMenuBarItem];
    
    [toolbarItems addObject:self.editButtonItem];
    
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:makeToolbarItems:)])
        [delegate documentPicker:self makeToolbarItems:toolbarItems];
    
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
        } else {
            BOOL canExport;
            if ([_documentStore.scopes count] > 1)
                canExport = YES;
            else if (count == 1)
                canExport = ([[self availableExportTypesForFileItem:[self singleSelectedFileItem] serverAccount:nil exportOptionsType:OUIExportOptionsNone] count] > 0);
            else
                canExport = NO;

            _exportBarButtonItem.enabled = canExport;
            _duplicateDocumentBarButtonItem.enabled = YES;
            _deleteBarButtonItem.enabled = YES;
        }
    }
}

- (void)_setupBottomToolbar
{
    NSMutableArray *bottomToolbarItems = [NSMutableArray array];
    
    // Sort
    {
        // Make sure to keep these in sync with the OUIDocumentPickerItemSort enum.
        NSArray *sortTitles = @[
                                NSLocalizedStringFromTableInBundle(@"Sort by date", @"OmniUIDocument", OMNI_BUNDLE, @"sort by date"),
                                NSLocalizedStringFromTableInBundle(@"Sort by title", @"OmniUIDocument", OMNI_BUNDLE, @"sort by title")
                                ];
        UISegmentedControl *sortSegmentedControl = [[UISegmentedControl alloc] initWithItems:sortTitles];
        [sortSegmentedControl addTarget:self action:@selector(sortSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        sortSegmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
        sortSegmentedControl.selectedSegmentIndex = [[[self class] sortPreference] enumeratedValue];
        
        UIBarButtonItem *sortsItem = [[UIBarButtonItem alloc] initWithCustomView:sortSegmentedControl];
        [bottomToolbarItems addObject:sortsItem];
    }

    // Filter
    NSArray *availableFilters = [self availableFilters];
    if ([availableFilters count] > 0) {
        // First add flexy spacer to move the filters item all the way right.
        UIBarButtonItem *flexySpacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        [bottomToolbarItems addObject:flexySpacer];
        
        
        // Now time to add the actual filter items.
        NSString *identifier = [[[self class] filterPreference] stringValue];
        NSUInteger selectedIndex = [availableFilters indexOfObjectPassingTest:^BOOL(OUIDocumentPickerFilter *filter, NSUInteger idx, BOOL *stop) {
            return [filter.identifier isEqualToString:identifier];
        }];
        
        NSArray *filterTitles = [availableFilters valueForKey:@"title"];
        UISegmentedControl *filtersSegmentedControl = [[UISegmentedControl alloc] initWithItems:filterTitles];
        [filtersSegmentedControl addTarget:self action:@selector(filterSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        filtersSegmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
        filtersSegmentedControl.selectedSegmentIndex = selectedIndex;
        
        UIBarButtonItem *filtersItem = [[UIBarButtonItem alloc] initWithCustomView:filtersSegmentedControl];
        [bottomToolbarItems addObject:filtersItem];
    }
    
    
    [self.bottomToolbar setItems:bottomToolbarItems
                        animated:NO];
}

- (IBAction)_showViewSettings:(UIView *)sender;
{
    if (!self.canPerformActions)
        return;
    
    OBASSERT(_renameViewController == nil); // Can't be renaming now; no need to try to stop.
    
    OUIDocumentPickerSettings *settings = [[OUIDocumentPickerSettings alloc] init];
    settings.availableScopes = [_documentStore.scopes sortedArrayUsingSelector:@selector(compareDocumentScope:)];
    settings.availableFilters = self.availableFilters;
    [settings showFromView:sender];
}

- (void)_setupTopItemsBinding;
{
    OBPRECONDITION(_documentStore);
    
    if (_topItemsBinding)
        return;
        
    // We might want to bind _documentStore.fileItems to us and then mirror that property to the scroll view, or force feed it. This would allow us to stage animations or whatnot.
    // OFSDocumentStore is going to send us unsolicited updates (incoming document sync while we are just sitting idle in the picker), so we need to be able to handle these
    [_topItemsBinding invalidate];
    
    _topItemsBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingKeyPath(_documentStoreFilter, filteredTopLevelItems)
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
        NSString *mimeType = (NSString *)CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileType, kUTTagClassMIMEType));
        OBASSERT(mimeType != nil); // The UTI's mime type should be registered in the Info.plist under UTExportedTypeDeclarations:UTTypeTagSpecification
        if (mimeType == nil)
            mimeType = @"application/octet-stream"; 

        [controller addAttachmentData:attachmentData mimeType:mimeType fileName:attachmentFileName];
    }
    [[[OUIAppController controller] topViewController] presentViewController:controller animated:YES completion:nil];
}

- (void)_deleteWithoutConfirmation:(NSSet *)fileItemsToDelete;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    NSMutableArray *errors = [NSMutableArray array];

    // Wait for the deletions to finish and possibly emit errors. Since the action queue is serial, we just enqueue another action, and that then enqueues an action on the main queue.
    NSBlockOperation *fullCompletion = [NSBlockOperation blockOperationWithBlock:^{
        OBASSERT([NSThread isMainThread]); // errors array

        for (NSError *error in errors)
            OUI_PRESENT_ERROR(error);
        
        // By this time, our file items binding should have been poked and the animation started.
        [self clearSelection:YES];
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    }];
    
    for (OFSDocumentStoreFileItem *fileItem in fileItemsToDelete) {
        NSBlockOperation *completion = [NSBlockOperation blockOperationWithBlock:^{}];
        
        [fullCompletion addDependency:completion];
        
        [fileItem.scope deleteItem:fileItem completionHandler:^(NSError *errorOrNil) {
            OBASSERT([NSThread isMainThread]); // errors array

            if (errorOrNil)
                [errors addObject:errorOrNil];
            
            [[NSOperationQueue mainQueue] addOperation:completion];
        }];
    }

    // Get ready to do the full completion, now that it has dependencies set up.
    [[NSOperationQueue mainQueue] addOperation:fullCompletion];
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


- (BOOL)_canUseOpenInWithFileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    // Check current type.
    OBFinishPortingLater("<bug:///75843> (Add a UTI property to OFSDocumentStoreFileItem)");
    NSString *fileType = OFUTIForFileExtensionPreferringNative(fileItem.fileURL.pathExtension, NO); // NSString *fileType = [OFSFileInfo UTIForURL:fileItem.fileURL];
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
    
    _renameViewController = nil;
}

- (void)_moveSelectedDocumentsToScope:(OFSDocumentStoreScope *)scope;
{
    [self _beginIgnoringDocumentsDirectoryUpdates];
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    [_documentStore moveFileItems:self.selectedFileItems toScope:scope completionHandler:^(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil){
        [self clearSelection:YES];
        [self _endIgnoringDocumentsDirectoryUpdates];
        [self _performDelayedItemPropagationWithCompletionHandler:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
            if (failingItem)
                OUI_PRESENT_ALERT(errorOrNil);
        }];
    }];
}

- (void)_showMoveMenuWithScopes:(NSArray *)scopes fromSender:(id)sender;
{
    NSMutableArray *options = [NSMutableArray new];
    
    for (OFSDocumentStoreScope *scope in scopes) {
        OUIMenuOption *option = [[OUIMenuOption alloc] initWithTitle:[scope moveToActionLabelWhenInList:YES] image:nil action:^{
            [self _moveSelectedDocumentsToScope:scope];
        }];
        [options addObject:option];
    }
    
    OUIMenuController *menu = [[OUIMenuController alloc] initWithOptions:options];
    menu.title = NSLocalizedStringFromTableInBundle(@"Move to...", @"OmniUIDocument", OMNI_BUNDLE, @"Menu popover title");
    [menu showMenuFromBarItem:_exportBarButtonItem];
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
    OBFinishPorting;
#if 0
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
#endif
}

- (void)_revealAndActivateNewDocumentFileItem:(OFSDocumentStoreFileItem *)createdFileItem completionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(createdFileItem);
    
    // Trying a fade in of the new document instead of having all the scrolling/sliding previews
#if 1
    id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentPicker:openCreatedFileItem:)])
        [delegate documentPicker:self openCreatedFileItem:createdFileItem];
        
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
             
             id <OUIDocumentPickerDelegate> delegate = _weak_delegate;
             if ([delegate respondsToSelector:@selector(documentPicker:openCreatedFileItem:)])
                 [delegate documentPicker:self openCreatedFileItem:createdFileItem];
         });
         
         if (completionHandler)
             completionHandler();
     },
     nil];
#endif
}

- (void)_applicationWillOpenDocument;
{
    [_renameViewController cancelRenaming];
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

- (void)_setupClearButton:(UIButton *)button;
{
    UIImage *backgroundImage = [[UIImage imageNamed:@"OUIContentAreaButtonClear.png"] resizableImageWithCapInsets:(UIEdgeInsets) {
        .top = 0.0f,
        .right = 7.0f,
        .bottom = 0.0f,
        .left = 7.0f
    }];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setBackgroundImage:backgroundImage forState:UIControlStateNormal];
}

- (void)_updateViewControls;
{
    BOOL isEmpty = self.selectedScope.fileItems.count == 0;

    // "Empty Trash" control
    BOOL trashControlsAreVisible = self.trashControls.superview != nil;
    BOOL trashControlsShouldBeVisible = self.selectedScope.isTrash && !isEmpty;
    if (trashControlsAreVisible != trashControlsShouldBeVisible) {
        if (trashControlsShouldBeVisible) {
            [self _setupClearButton:self.emptyTrashButton];
            CGRect bounds = self.view.bounds;
            CGFloat controlHeight = CGRectGetHeight(self.trashControls.frame);
            CGRect controlFrame, scrollFrame;
            CGRectDivide(bounds, &controlFrame, &scrollFrame, controlHeight, CGRectMinYEdge);

            [self.trashControls setFrame:controlFrame];
            [self.mainScrollView setFrame:scrollFrame];
            [self.view addSubview:self.trashControls];
        } else {
            [self.trashControls removeFromSuperview];
            [self.mainScrollView setFrame:self.view.bounds];
        }
    }

    // Empty view overlay hints
    BOOL emptyOverlayShouldBeVisible = isEmpty;
    if (emptyOverlayShouldBeVisible) {
        BOOL showMoveButton = !self.selectedScope.isTrash && [[[self _localDocumentsScope] fileItems] count] != 0;
        self.emptyPickerViewMoveView.hidden = !showMoveButton;

        if (self.view.superview != nil && (self.emptyPickerView.superview == nil || self.emptyPickerView.hidden)) {
            if (![UIView areAnimationsEnabled]) {
                // Don't show the empty hints until we can fade them in
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self _updateViewControls];
                }];
            } else {
                [self _setupClearButton:self.emptyPickerViewMoveButton];
                CGRect newFrame = (CGRect){
                    .origin = self.view.bounds.origin,
                    .size.width = self.view.bounds.size.width,
                    .size.height = self.view.bounds.size.height - self.bottomToolbar.frame.size.height
                };
                self.emptyPickerView.frame = newFrame;
                OUIWithoutAnimating(^{
                    self.emptyPickerView.alpha = 0.0;
                    self.emptyPickerView.hidden = YES;
                });
                [self.view addSubview:self.emptyPickerView];
                [self.view setNeedsLayout];
                [UIView animateWithDuration:1.0 delay:1.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionOverrideInheritedDuration animations:^{
                    self.emptyPickerView.alpha = 1.0;
                    self.emptyPickerView.hidden = NO;
                } completion:NULL];
            }
        }

    } else {
        self.emptyPickerView.hidden = YES;
    }
}

@synthesize topItems = _topItems;
- (void)setTopItems:(NSSet *)topItems;
{
    if (OFISEQUAL(_topItems, topItems))
        return;
    
    _topItems = [[NSSet alloc] initWithSet:topItems];

    if (_ignoreDocumentsDirectoryUpdates == 0) {
        [self _propagateItems:_topItems toScrollView:_mainScrollView withCompletionHandler:nil];
        [self _updateToolbarItemsEnabledness];
        [self _updateViewControls];
    }
}

@synthesize openGroupItems = _openGroupItems;
- (void)setOpenGroupItems:(NSSet *)openGroupItems;
{
    if (OFISEQUAL(_openGroupItems, openGroupItems))
        return;
    
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
         for (OFSDocumentStoreItem *item in toRemove) {
             if ([item isKindOfClass:[OFSDocumentStoreFileItem class]]) {
                 OFSDocumentStoreFileItem *fileItem = (OFSDocumentStoreFileItem *)item;
                 if (fileItem.selected) {
                     [[OUIAppController controller] dismissActionSheetAndPopover:YES];
                     break;
                 }
             }
         }
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

- (void)_flushAfterDocumentStoreInitializationActions;
{
    if (_documentStore) {
        NSArray *actions = _afterDocumentStoreInitializationActions;
        _afterDocumentStoreInitializationActions = nil; // Don't perform these more than once

        for (void (^action)(OUIDocumentPicker *blockSelf) in actions)
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

- (void)_updateOmniPresenceAnimationState;
{
    _omniPresenceAnimationState++;
    if (_omniPresenceAnimationState > 3) {
        if (_omniPresenceAnimationLastLoop) {
            [_omniPresenceAnimationTimer invalidate];
            _omniPresenceAnimationTimer = nil;
            _omniPresenceAnimationState = 0;
            [_omniPresenceBarButtonItem setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon.png"]];
            return;
        }
        _omniPresenceAnimationState = 1;
    }
    [_omniPresenceBarButtonItem setImage:[UIImage imageNamed:[NSString stringWithFormat:@"OmniPresenceToolbarIconAnimation-%lu.png", _omniPresenceAnimationState]]];
}

- (void)_rescheduleAnimationTimer;
{
    NSTimeInterval newTimeInterval = (_omniPresenceAnimationLastLoop ? 0.15 : 0.45);
    NSDate *newFireDate = nil;
    if (_omniPresenceAnimationTimer != nil) {
        NSTimeInterval oldTimeInterval = [_omniPresenceAnimationTimer timeInterval];
        if (oldTimeInterval == newTimeInterval)
            return; // No change needed

        NSDate *oldFireDate = [_omniPresenceAnimationTimer fireDate];
        newFireDate = [oldFireDate dateByAddingTimeInterval:newTimeInterval - oldTimeInterval];
    }
    [_omniPresenceAnimationTimer invalidate];
    _omniPresenceAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:newTimeInterval target:self selector:@selector(_updateOmniPresenceAnimationState) userInfo:nil repeats:YES];
    if (newFireDate != nil)
        [_omniPresenceAnimationTimer setFireDate:newFireDate];
}

- (void)_updateOmniPresenceToolbarIcon;
{
    OFXAgentActivity *agentActivity = [OUIDocumentAppController controller].agentActivity;
    NSError *selectedScopeError = self.selectedScopeError;
    
    if (selectedScopeError != nil) {
        [_omniPresenceAnimationTimer invalidate];
        _omniPresenceAnimationTimer = nil;
        if ([selectedScopeError causedByUnreachableHost]) {
            [_omniPresenceBarButtonItem setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon-Offline.png"]];
        } else {
            [_omniPresenceBarButtonItem setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon-Error.png"]];
        }
    } else if (agentActivity.isActive) {
        if (!_omniPresenceAnimationTimer) {
            _omniPresenceAnimationState = 0;
            _omniPresenceAnimationLastLoop = NO;
            [self _updateOmniPresenceAnimationState];
            [self _rescheduleAnimationTimer];
        }
    } else {
        if (_omniPresenceAnimationTimer) {
            _omniPresenceAnimationLastLoop = YES;
            [self _rescheduleAnimationTimer];
        } else
            [_omniPresenceBarButtonItem setImage:[UIImage imageNamed:@"OmniPresenceToolbarIcon.png"]];
    }
}

static unsigned SyncActivityContext;

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (object == _agentActivity && context == &SyncActivityContext) {
        [self _updateOmniPresenceToolbarIcon];
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


@end
