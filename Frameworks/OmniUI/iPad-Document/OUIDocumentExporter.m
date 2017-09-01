// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentExporter.h>

#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIErrors.h>
#import <OmniUIDocument/ODSFileItem-OUIDocumentExtensions.h>

#import "OUIExportOptionsController.h"
#import "OUIImportExportAccountListViewController.h"

@import OmniBase;
@import OmniFoundation;
@import MessageUI;
@import MobileCoreServices;
@import Photos;
@import OmniUI;
@import OmniFileExchange;

RCS_ID("$Id$")

@implementation OUIDocumentExporter

+ (instancetype)exporterForViewController:(UIViewController<OUIDocumentExporterHost> *)hostViewController
{
    OUIDocumentAppController *appDelegate = OB_CHECKED_CAST(OUIDocumentAppController, [[UIApplication sharedApplication] delegate]);
    return [[[appDelegate documentExporterClass] alloc] initWithHostViewController:hostViewController];
}

/// Should be called when app enters background
+ (void)clearOpenInCache
{
    // Reset openInMapCache incase someone adds or deletes an app.
    [[self openInMapCache] removeAllObjects];
}

+ (NSMutableDictionary *)openInMapCache;
{
    static NSMutableDictionary *_openInMapCache;  // Used to map between an exportType (UTI string) and BOOL indicating if an app exists that we can send it to via Document Interaction.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _openInMapCache = [NSMutableDictionary dictionary];
    });
    
    return _openInMapCache;
}

- (BOOL)canExportFileItem:(ODSFileItem *)fileItem
{
    return ([[self availableExportTypesForFileItem:fileItem serverAccount:nil exportOptionsType:OUIExportOptionsNone] count] > 0);
}

- (instancetype)initWithHostViewController:(UIViewController<OUIDocumentExporterHost> *)hostViewController;
{
    if (!(self = [super init]))
        return nil;

    _hostViewController = hostViewController;
    return self;
}

- (UIBarButtonItem *)barButtonItem
{
    UIImage *image = [[OUIAppController controller] exportBarButtonItemImageInHostViewController:self.hostViewController];

    if (!_barButtonItem) {
        _barButtonItem = [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:self action:@selector(export:)];
        _barButtonItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"Export toolbar item accessibility label.");
    } else {
        _barButtonItem.image = image; // compactness might have changed
    }
    return _barButtonItem;
}

- (void)exportItem:(ODSFileItem *)fileItem
{
    [self exportItem:fileItem sender:nil];
}

- (void)exportItem:(ODSFileItem *)fileItem sender:(id)sender;
{
    if (fileItem == nil || fileItem.scope.isTrash) {
        return;
    }
    
    if ([self.hostViewController respondsToSelector:@selector(prepareToExport)]) {
        [self.hostViewController prepareToExport];
    }
    
    // Single file export options
    NSString *topLevelMenuTitle = NSLocalizedStringFromTableInBundle(@"Actions", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view");
    NSMutableArray *topLevelMenuOptions = [[NSMutableArray alloc] init];
    
    NSArray *availableExportTypes = [self availableExportTypesForFileItem:fileItem serverAccount:nil exportOptionsType:OUIExportOptionsNone];
    NSArray *availableImageExportTypes = [self availableImageExportTypesForFileItem:fileItem];
    
    BOOL canExport = [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"OUIExportEnabled"];
    BOOL canSendToCameraRoll = [self supportsSendToCameraRoll];
    BOOL canPrint = [self supportsPrinting] && [UIPrintInteractionController isPrintingAvailable];
    BOOL canUseOpenIn = [self _canUseOpenInWithFileItem:fileItem];
    
    OB_UNUSED_VALUE(availableExportTypes); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning
    
    if ([MFMailComposeViewController canSendMail]) {
        // All email options should go here (within the test for whether we can send email)
        // more than one option? Display the 'export options sheet'
        [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemSendToMail" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            if (availableExportTypes.count > 0) {
                [self _displayExportOptionsControllerForFileItem:fileItem exportType:OUIExportOptionsEmail];
            }
            else {
                [self emailFileItem:fileItem];
            }
        }]];
    }
    
    if (canExport) {
#if 0 // bug:///147708
        [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Export to WebDAV", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemExportToWebDAV" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self exportDocument:fileItem];
        }]];
#endif
        
        [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Send to Files", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemExportToWebDAV" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self _displayExportOptionsControllerForFileItem:fileItem exportType:OUIExportOptionsSendToService];
        }]];
    }
    
    if (canUseOpenIn) {
        [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Send to App", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemSendToApp" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self _displayExportOptionsControllerForFileItem:fileItem exportType:OUIExportOptionsSendToApp];
        }]];
    }
    
    if (availableImageExportTypes.count > 0) {
        [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Copy as Image", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemCopyAsImage" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self copyAsImageForFileItem:fileItem];
            [self clearSelection];
        }]];
    }
    
    if (canSendToCameraRoll) {
        [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Send to Photos", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view") image:[UIImage imageNamed:@"OUIMenuItemSendToPhotos" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self sendToCameraRollForFileItem:fileItem];
            [self clearSelection];
        }]];
    }
    
    if (canPrint) {
        NSString *printTitle = [self _printTitleForFileItem:fileItem];
        [topLevelMenuOptions addObject:[OUIMenuOption optionWithTitle:printTitle image:[UIImage imageNamed:@"OUIMenuItemPrint" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] action:^(OUIMenuOption *option, UIViewController *presentingViewController){
            [self printDocument:fileItem];
        }]];
    }
    
    NSArray *options = [self additionalExportOptionsForFileItem:fileItem];
    if (options) {
        [topLevelMenuOptions addObjectsFromArray:options];
    }
    
    OUIMenuController *menu = [[OUIMenuController alloc] init];
    menu.sizesToOptionWidth = YES;
    menu.topOptions = topLevelMenuOptions;
    if (topLevelMenuTitle)
        menu.title = topLevelMenuTitle;
    
    menu.tintColor = [self.hostViewController tintColorForExportMenu];
    
    menu.popoverPresentationController.barButtonItem = [sender isKindOfClass:[UIBarButtonItem class]] ? sender : self.barButtonItem;
    
    if (![self.hostViewController isKindOfClass:[OUIDocumentPickerViewController class]] &&  [OUIInspectorAppearance inspectorAppearanceEnabled]) {
        OUIInspectorAppearance *appearance = OUIInspectorAppearance.appearance;
        menu.popoverPresentationController.backgroundColor = appearance.PopoverBackgroundColor;
        menu.menuBackgroundColor = appearance.PopoverBackgroundColor;

        menu.navigationBarBackgroundColor = OUIInspectorAppearance.appearance.InspectorBackgroundColor;
        menu.navigationBarStyle = OUIInspectorAppearance.appearance.InspectorBarStyle;
    }

    [self.hostViewController presentViewController:menu animated:YES completion:^{
        menu.popoverPresentationController.passthroughViews = nil;
    }];
}


- (void)export:(id)sender
{
    ODSFileItem *fileItem;
    if ([self.hostViewController respondsToSelector:@selector(fileItemsToExport)]) {
        NSArray *items = [self.hostViewController fileItemsToExport];
        if (items.count > 1) {
            NSMutableArray *urls = [NSMutableArray array];

            for (ODSFileItem *item in items)
                [urls addObject:[item fileURL]];
            UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
            activityViewController.modalPresentationStyle = UIModalPresentationPopover;
            activityViewController.popoverPresentationController.barButtonItem = sender;
            [self.hostViewController presentViewController:activityViewController animated:YES completion:nil];
            return;
        }
        fileItem = items.anyObject;
    } else {
        fileItem = [self.hostViewController fileItemToExport];
    }
    [self exportItem:fileItem sender:sender];
}

- (NSArray *)availableExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType
{
    BOOL isFileExportToLocalDocuments = (exportOptionsType == OUIExportOptionsExport) && OFISEQUAL(serverAccount.type.identifier, OFXiTunesLocalDocumentsServerAccountTypeIdentifier);

    NSMutableArray *exportTypes = [[fileItem availableExportTypesForFileExportToLocalDocuments:isFileExportToLocalDocuments] mutableCopy];
    if (!exportTypes) {
        exportTypes = [NSMutableArray array];
        
        // Add the 'native' marker
        [exportTypes insertObject:[NSNull null] atIndex:0];
        
        // PDF PNG Fallbacks
        BOOL canMakePDF = [self supportsExportAsPDF];
        BOOL canMakePNG = [self supportsExportAsPNG];
        if (canMakePDF)
            [exportTypes addObject:(NSString *)kUTTypePDF];
        if (canMakePNG)
            [exportTypes addObject:(NSString *)kUTTypePNG];
    }
    
    if ((serverAccount == nil) &&
        (exportOptionsType == OUIExportOptionsNone)) {
        // We're just looking for a rough count of how many export types are available. Let's just return what we have.
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
            OFTypeConformsTo(exportType, kUTTypeImage)) {
            [imageExportTypes addObject:exportType];
        }
    }
    return imageExportTypes;
}

- (BOOL)_canUseOpenInWithFileItem:(ODSFileItem *)fileItem;
{
    // Check current type.
    OBFinishPortingLater("<bug:///75843> (Add a UTI property to ODSFileItem)");
    NSString *fileType = OFUTIForFileExtensionPreferringNative(fileItem.fileURL.pathExtension, nil); // NSString *fileType = [ODAVFileInfo UTIForURL:fileItem.fileURL];
    BOOL canUseOpenInWithCurrentType = [self _canUseOpenInWithExportType:fileType];
    if (canUseOpenInWithCurrentType) {
        return YES;
    }
    
    NSArray *types = [self availableExportTypesForFileItem:fileItem serverAccount:nil exportOptionsType:OUIExportOptionsSendToApp];
    return ([types count] > 0) ? YES : NO;
}

- (void)_displayExportOptionsControllerForFileItem:(ODSFileItem *)fileItem exportType:(OUIExportOptionsType)exportType
{
    OUIExportOptionsController *exportOptionsController = [[OUIExportOptionsController alloc] initWithServerAccount:nil fileItem:fileItem exportType:exportType exporter:self];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:exportOptionsController];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [self.hostViewController presentViewController:navController animated:YES completion:nil];
}

- (void)emailFileItem:(ODSFileItem *)fileItem
{
    if (!fileItem) {
        return;
    }
    
    NSData *documentData = [fileItem emailData];
    NSString *documentFilename = [fileItem emailFilename];
    OBFinishPortingLater("<bug:///75843> (Add a UTI property to ODSFileItem)");
    NSString *documentType = OFUTIForFileExtensionPreferringNative([documentFilename pathExtension], nil); // NSString *documentType = [ODAVFileInfo UTIForFilename:documentFilename];
    OBASSERT(documentType != nil); // UTI should be registered in the Info.plist under CFBundleDocumentTypes
    
    [self _sendEmailWithSubject:[fileItem name] messageBody:nil isHTML:NO attachmentName:documentFilename data:documentData fileType:documentType];
}

- (void)exportDocument:(ODSFileItem *)fileItem
{
    OUIImportExportAccountListViewController *accountList = [[OUIImportExportAccountListViewController alloc] initForExporting:YES];
    accountList.title = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"export options title");
    
    UINavigationController *containingNavigationController = [[UINavigationController alloc] initWithRootViewController:accountList];
    
    accountList.finished = ^(OFXServerAccount *accountOrNil){
        [containingNavigationController dismissViewControllerAnimated:YES completion:^{
            if (!accountOrNil)
                return;
            
            OUIExportOptionsController *exportController = [[OUIExportOptionsController alloc] initWithServerAccount:accountOrNil fileItem:fileItem exportType:OUIExportOptionsExport exporter:self];
            
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:exportController];
            navController.modalPresentationStyle = UIModalPresentationFormSheet;
            [self.hostViewController presentViewController:navController animated:YES completion:nil];
        }];
    };
    
    containingNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self.hostViewController presentViewController:containingNavigationController animated:YES completion:nil];
}

- (void)copyAsImageForFileItem:(ODSFileItem *)fileItem
{
    if (!fileItem) {
        OBASSERT_NOT_REACHED("must provide fileItem");
        return;
    }
    
    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    NSMutableArray *items = [NSMutableArray array];
    
    BOOL canMakeCopyAsImageSpecificPDF = [self supportsCopyAsImage];
    BOOL canMakePDF = [self supportsExportAsPDF];
    BOOL canMakePNG = [self supportsExportAsPNG];
    
    //- (NSData *)documentPicker:(OUIDocumentPicker *)picker copyAsImageDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
    if (canMakeCopyAsImageSpecificPDF) {
        __autoreleasing NSError *error = nil;
        NSData *pdfData = [self copyAsImageDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR_FROM(error, self.hostViewController);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    } else if (canMakePDF) {
        __autoreleasing NSError *error = nil;
        NSData *pdfData = [self PDFDataForFileItem:fileItem error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR_FROM(error, self.hostViewController);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    }
    
    // Don't put more than one image format on the pasteboard, because both will get pasted into iWork.  <bug://bugs/61070>
    if (!canMakeCopyAsImageSpecificPDF &&!canMakePDF && canMakePNG) {
        __autoreleasing NSError *error = nil;
        NSData *pngData = [self PNGDataForFileItem:fileItem error:&error];
        if (!pngData) {
            OUI_PRESENT_ERROR_FROM(error, self.hostViewController);
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
 
    [self clearSelection];
}

- (void)clearSelection
{
    if ([self.hostViewController respondsToSelector:@selector(clearSelectionAndEndEditing)]) {
        [self.hostViewController performSelectorOnMainThread:@selector(clearSelectionAndEndEditing) withObject:nil waitUntilDone:NO];
    }
}

- (void)sendToCameraRollForFileItem:(ODSFileItem *)fileItem;
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusRestricted || status == PHAuthorizationStatusDenied) {
        
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Photo Library permission denied.", @"OmniUIDocument", OMNI_BUNDLE, @"Photo Library permisssions error description."),
                                   NSLocalizedRecoverySuggestionErrorKey : NSLocalizedStringFromTableInBundle(@"This app does not have access to your Photo Library.", @"OmniUIDocument", OMNI_BUNDLE, @"Photo Library permisssions error suggestion.")
                                   };
        
        NSError *permissionError = [NSError errorWithDomain:OUIDocumentErrorDomain code:OUIPhotoLibraryAccessRestrictedOrDenied userInfo:userInfo];
        OUI_PRESENT_ALERT_FROM(permissionError, self.hostViewController);
        return;
    }
    
    if (!fileItem) {
        OBASSERT_NOT_REACHED("must provide fileItem");
        return;
    }
    
    UIImage *image = [self cameraRollImageForFileItem:fileItem];
    OBASSERT(image); // There is no default implementation -- the delegate should return something.
    
    if (image)
        UIImageWriteToSavedPhotosAlbum(image, self, @selector(_sendToCameraRollImage:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)_sendToCameraRollImage:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
{
    OUI_PRESENT_ERROR_FROM(error, self.hostViewController);
}

- (UIImage *)cameraRollImageForFileItem:(ODSFileItem *)fileItem
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)_printTitleForFileItem:(ODSFileItem *)fileItem;
{
    return [self printButtonTitleForFileItem:fileItem];
}

- (void)printDocument:(ODSFileItem *)fileItem;
{
    if (!fileItem) {
        OBASSERT_NOT_REACHED("must provide fileItem");
        return;
    }
    
    [self printFileItem:fileItem fromButton:_barButtonItem];
}

// Helper method for -availableDocumentInteractionExportTypesForFileItem:
- (BOOL)_canUseOpenInWithExportType:(NSString *)exportType;
{
    NSNumber *value = [[OUIDocumentExporter openInMapCache] objectForKey:exportType];
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
    BOOL isDirectory = OFTypeConformsTo(exportType, kUTTypeDirectory);
    
    NSString *owned_UTIExtension = OFPreferredPathExtensionForUTI(exportType);
    
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
    [[self openInMapCache] setObject:[NSNumber numberWithBool:success] forKey:exportType];
#endif
    return success;
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
    
    [self.hostViewController presentViewController:controller animated:YES completion:nil];
}

- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType fileName:(NSString *)fileName;
{
    if ([fileWrapper isDirectory]) {
        NSDictionary *childWrappers = [fileWrapper fileWrappers];
        if ([childWrappers count] == 1) {
            NSFileWrapper *childWrapper = [childWrappers anyObject];
            if ([childWrapper isRegularFile]) {
                // File wrapper with just one file? Let's see if it's HTML which we can send as the message body (rather than as an attachment)
                NSString *documentType = OFUTIForFileExtensionPreferringNative(childWrapper.preferredFilename.pathExtension, [NSNumber numberWithBool:childWrapper.isDirectory]);
                if (OFTypeConformsTo(documentType, kUTTypeHTML)) {
                    if ([self _canUseEmailBodyForExportType:exportType]) {
                        NSString *messageBody = [[NSString alloc] initWithData:[childWrapper regularFileContents] encoding:NSUTF8StringEncoding];
                        if (messageBody != nil) {
                            [self _sendEmailWithSubject:fileName messageBody:messageBody isHTML:YES attachmentName:nil data:nil fileType:nil];
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
        
        NSString *fileType = OFUTIForFileExtensionPreferringNative(fileWrapper.preferredFilename.pathExtension, nil);
        if (OFTypeConformsTo(fileType, kUTTypePlainText)) {
            // Plain text? Let's send that as the message body
            if ([self _canUseEmailBodyForExportType:exportType]) {
                NSString *messageBody = [[NSString alloc] initWithData:emailData encoding:NSUTF8StringEncoding];
                if (messageBody != nil) {
                    [self _sendEmailWithSubject:fileName messageBody:messageBody isHTML:NO attachmentName:nil data:nil fileType:nil];
                    return;
                }
            }
        }
    } else {
        emailName = [fileWrapper.preferredFilename stringByAppendingPathExtension:@"zip"];
        emailType = OFUTIForFileExtensionPreferringNative(@"zip", nil);
        NSString *zipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:emailName];
        @autoreleasepool {
            __autoreleasing NSError *error = nil;
            if (![OUZipArchive createZipFile:zipPath fromFileWrappers:[NSArray arrayWithObject:fileWrapper] error:&error]) {
                OUI_PRESENT_ERROR_FROM(error, self.hostViewController);
                return;
            }
        };
        __autoreleasing NSError *error = nil;
        emailData = [NSData dataWithContentsOfFile:zipPath options:NSDataReadingMappedAlways error:&error];
        if (emailData == nil) {
            OUI_PRESENT_ERROR_FROM(error, self.hostViewController);
            return;
        }
    }
    
    [self _sendEmailWithSubject:fileName messageBody:nil isHTML:NO attachmentName:emailName data:emailData fileType:emailType];
}


- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(ODSFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
{
    OBASSERT_NOTNULL(completionHandler);
    
    completionHandler = [completionHandler copy]; // preserve scope
    
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
    
    // try the older NSData API if the app-specific subclass is calling up to us
    NSData *fileData = nil;
    NSString *pathExtension = nil;
    __autoreleasing NSError *error = nil;
    
    if (OFTypeConformsTo(exportType, kUTTypePDF)) {
        fileData = [self PDFDataForFileItem:fileItem error:&error];
        pathExtension = @"pdf";
    } else if (OFTypeConformsTo(exportType, kUTTypePNG)) {
        fileData = [self PNGDataForFileItem:fileItem error:&error];
        pathExtension = @"png";
    }
    
    if (fileData == nil) {
        completionHandler(nil, error);
        return;
    }
    
    NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:fileData];
    fileWrapper.preferredFilename = [fileItem.name stringByAppendingPathExtension:pathExtension];
    
    completionHandler(fileWrapper, error);
}

#pragma mark - Subclass Overrides

- (UIImage *)iconForUTI:(NSString *)fileUTI;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)exportLabelForUTI:(NSString *)fileUTI;
{
    if (OFTypeConformsTo(fileUTI, kUTTypePDF))
        return @"PDF";
    if (OFTypeConformsTo(fileUTI, kUTTypePNG))
        return @"PNG";
    if (OFTypeConformsTo(fileUTI, kUTTypeScalableVectorGraphics))
        return @"SVG";
    return nil;
}

- (NSArray<OUIMenuOption *> *)additionalExportOptionsForFileItem:(ODSFileItem *)fileItem
{
    return nil;
}

- (BOOL)_canUseEmailBodyForExportType:(NSString *)exportType;
{
    return NO;
}

- (NSArray *)availableInAppPurchaseExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
{
    NSMutableArray *exportTypes = [NSMutableArray array];
    return exportTypes;
}

- (BOOL)supportsPrinting
{
    return NO;
}

- (void)printFileItem:(ODSFileItem *)fileItem fromButton:(UIBarButtonItem *)aButton
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)printButtonTitleForFileItem:(ODSFileItem *)fileItem
{
    return NSLocalizedStringFromTableInBundle(@"Print", @"OmniUIDocument", OMNI_BUNDLE, @"Menu option in the document picker view");
}

- (BOOL)supportsSendToCameraRoll
{
    return NO;
}

- (BOOL)supportsCopyAsImage
{
    return NO;
}

- (NSData *)copyAsImageDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError
{
    if (outError) {
        *outError = [[NSError alloc] initWithDomain:@"com.omnigroup.OUIDocumentExporter" code:1 userInfo:@{ NSLocalizedDescriptionKey : @"subclass should provide this implementation" }];
    }
    return nil;
}

- (BOOL)supportsExportAsPDF
{
    return NO;
}

- (NSData *)PDFDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)error
{
    if (error) {
        *error = [[NSError alloc] initWithDomain:@"com.omnigroup.OUIDocumentExporter" code:1 userInfo:@{ NSLocalizedDescriptionKey : @"subclass should provide this implementation" }];
    }
    return nil;
}

- (BOOL)supportsExportAsPNG
{
    return NO;
}

- (NSData *)PNGDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)error
{
    if (error) {
        *error = [[NSError alloc] initWithDomain:@"com.omnigroup.OUIDocumentExporter" code:1 userInfo:@{ NSLocalizedDescriptionKey : @"subclass should provide this implementation" }];
    }
    return nil;
}

- (void)purchaseExportType:(NSString *)fileUTI navigationController:(UINavigationController *)navigationController;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)purchaseDescriptionForExportType:(NSString *)fileUTI;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self clearSelection];
    
    [controller.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}


@end
