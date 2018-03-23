// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIExportOptionsController.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniUIDocument/OUIDocumentExporter.h>

@import OmniFoundation;

#import "OUIWebDAVSyncListController.h"
#import "OUIExportOption.h"
#import "OUIExportOptionPickerViewController.h"

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

#pragma mark - OUIExportOptionsController

@interface _OUIExportOptionsNavigationController : UINavigationController
@property(nonatomic,strong) OUIExportOptionsController *optionsController;
@end
@implementation _OUIExportOptionsNavigationController

- (void)dealloc;
{
    OBExpectDeallocation(_optionsController);
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (BOOL)shouldBeDismissedTransitioningToTraitCollection:(UITraitCollection *)traitCollection;
{
    // We should avoid losing progress while exporting.
    return NO;
}

@end

@interface OUIExportOptionsController () <UIDocumentPickerDelegate, UIDocumentInteractionControllerDelegate, OUIExportOptionPickerViewControllerDelegate> //<OFSFileManagerDelegate>

@property (nonatomic, strong) UIDocumentInteractionController *documentInteractionController;
@property (nonatomic, nullable, readonly) OUIExportOptionPickerViewController *optionPickerViewController;

@end


@implementation OUIExportOptionsController
{
    OFXServerAccount * _Nullable _serverAccount;
    ODSFileItem *_fileItem;
    OUIExportOptionsType _exportType;

    // This navigation controller has a strong pointer back to us, and will be retained while it is presented on screen by the host view controller.
    __weak _OUIExportOptionsNavigationController *_navigationController;

    // _navigationController will be nil in the case of a single export type option; in that case we need to present off the original host view controller.
    UIViewController *_hostViewController;
    UIBarButtonItem *_presentingBarButtonItem;

    OUIDocumentExporter *_exporter;

    UIView *_optionPickerView;
    CGRect _optionPickerRect;
}

- (id)initWithServerAccount:(nullable OFXServerAccount *)serverAccount fileItem:(ODSFileItem *)fileItem exportType:(OUIExportOptionsType)exportType exporter:(OUIDocumentExporter *)exporter;
{
    self = [super init];

    _serverAccount = serverAccount;
    _fileItem = fileItem;
    _exportType = exportType;
    _exporter = exporter;

    return self;
}

- (void)dealloc;
{
    _documentInteractionController.delegate = nil;
}

- (void)presentInViewController:(UIViewController *)hostViewController barButtonItem:(nullable UIBarButtonItem *)barButtonItem;
{
    NSArray <OUIExportOption *> *exportOptions = [self _exportOptions];

    _hostViewController = hostViewController;
    _presentingBarButtonItem = barButtonItem;

    // If there is exactly one option, and no purchases available, then skip the option picker.
    if (exportOptions.count == 1 && exportOptions.firstObject.requiresPurchase == NO) {
        NSArray *inAppPurchaseExportTypes = [_exporter availableInAppPurchaseExportTypesForFileItem:_fileItem serverAccount:_serverAccount exportOptionsType:_exportType];
        if (inAppPurchaseExportTypes.count == 0) {
            OUIExportOption *singleExportOption = exportOptions.firstObject;
            OBASSERT(OFISNULL(singleExportOption.fileType), "Expecting the conversion to be 'fast' since it is a native type");

            [self _performActionForExportOption:singleExportOption];
            return;
        }
    }

    UIViewController *rootViewController = [self _makeOptionPickerViewControllerWithExportOptions:exportOptions];

    // This will keep us alive as long as it is on screen.
    _OUIExportOptionsNavigationController *navigationController = [[_OUIExportOptionsNavigationController alloc] initWithRootViewController:rootViewController];
    navigationController.optionsController = self;
    _navigationController = navigationController;

    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    [hostViewController presentViewController:navigationController animated:YES completion:nil];
}

- (nullable OUIExportOptionPickerViewController *)optionPickerViewController;
{
    UIViewController *rootViewController = _navigationController.viewControllers.firstObject;
    if ([rootViewController isKindOfClass:[OUIExportOptionPickerViewController class]]) {
        return (OUIExportOptionPickerViewController *)rootViewController;
    }
    return nil;
}

#pragma mark - API

- (void)_exportFileWrapper:(NSFileWrapper *)fileWrapper;
{
    [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
        __autoreleasing NSError *error = nil;
        OUIWebDAVSyncListController *syncListController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:_serverAccount exporting:YES error:&error];
        _OUIExportOptionsNavigationController *navigationController = _navigationController;
        if (!syncListController) {
            OUI_PRESENT_ERROR_FROM(error, navigationController);
            return;
        }

        syncListController.exportFileWrapper = fileWrapper;

        [navigationController pushViewController:syncListController animated:YES];
    }];
}

#pragma mark - Private

- (void)_foreground_exportFileWrapper:(NSFileWrapper *)fileWrapper;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    switch (_exportType) {
        case OUIExportOptionsNone:
            OBASSERT_NOT_REACHED("We shouldn't have built a file wrapper if we're not exporting");
            break;
        case OUIExportOptionsExport:
            [self _exportFileWrapper:fileWrapper];
            break;
        case OUIExportOptionsEmail:
            OBASSERT_NOT_REACHED("The email option takes another path: -_performActionForExportOption: calls -_foreground_emailExportOfType: directly");
            break;
        case OUIExportOptionsSendToApp:
            [self _foreground_exportSendToAppWithFileWrapper:fileWrapper];
            break;
        case OUIExportOptionsSendToService:
            [self _foreground_exportSendToServiceWithFileWrapper:fileWrapper];
            break;
    }
}

- (nullable NSURL *)_tempURLForExportedFileWrapper:(NSFileWrapper *)fileWrapper shouldZipDirectories:(BOOL)shouldZipDirectories error:(NSError **)outError;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Write to temp folder (need URL of file on disk to pass off to Doc Interaction.)
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *tempPath = [temporaryDirectory stringByAppendingPathComponent:[fileWrapper preferredFilename]];
    NSURL *tempURL = nil;
    
    if (shouldZipDirectories && [fileWrapper isDirectory]) {
        // We need to zip this mother up!
        NSString *tempZipPath = [tempPath stringByAppendingPathExtension:@"zip"];
        
        @autoreleasepool {
            if (![OUZipArchive createZipFile:tempZipPath fromFileWrappers:[NSArray arrayWithObject:fileWrapper] error:outError]) {
                return nil;
            }
        }

        tempURL = [NSURL fileURLWithPath:tempZipPath];
    } else {
        tempURL = [NSURL fileURLWithPath:tempPath isDirectory:[fileWrapper isDirectory]];
        
        // Get a FileManager for our Temp Directory.
        NSFileManager *fileManager = [NSFileManager defaultManager];

        // If the temp file exists, we delete it.
        if ([fileManager fileExistsAtPath:[tempURL path]]) {
            if (![fileManager removeItemAtURL:tempURL error:outError]) {
                return nil;
            }
        }
        
        // Write to temp dir.
        if (![fileWrapper writeToURL:tempURL options:0 originalContentsURL:nil error:outError]) {
            return nil;
        }
    }
    return tempURL;
}

- (void)_foreground_exportSendToAppWithFileWrapper:(NSFileWrapper *)fileWrapper;
{
    __autoreleasing NSError *error;
    NSURL *tempURL = [self _tempURLForExportedFileWrapper:fileWrapper shouldZipDirectories:YES error:&error];
    if (tempURL == nil) {
        NSError *strongError = error;
        [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
            OUI_PRESENT_ERROR_FROM(strongError, _navigationController);
        }];
        return;
    }
    
    [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
        // By now we have written the project out to a temp dir. Time to handoff to Doc Interaction.
        self.documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:tempURL];
        self.documentInteractionController.delegate = self;

        BOOL didOpen;
        if (_optionPickerView) {
            didOpen = [self.documentInteractionController presentOpenInMenuFromRect:_optionPickerRect inView:_optionPickerView animated:YES];
        } else {
            didOpen = [self.documentInteractionController presentPreviewAnimated:YES];
        }

        if (didOpen == NO) {
            // Show Activity View Controller instead.
            UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[tempURL] applicationActivities:nil];

            if (_optionPickerView) {
                activityViewController.modalPresentationStyle = UIModalPresentationPopover;
                activityViewController.popoverPresentationController.sourceRect = _optionPickerRect;
                activityViewController.popoverPresentationController.sourceView = _optionPickerView;
            } else if (_presentingBarButtonItem) {
                activityViewController.modalPresentationStyle = UIModalPresentationPopover;
                activityViewController.popoverPresentationController.barButtonItem = _presentingBarButtonItem;
            }

            [[self _viewControllerForPresenting] presentViewController:activityViewController animated:YES completion:nil];
        }
    }];
}

- (UIViewController *)_viewControllerForPresenting;
{
    _OUIExportOptionsNavigationController *navigationController = _navigationController;
    if (navigationController) {
        return navigationController;
    }
    OBASSERT(_hostViewController);
    return _hostViewController;
}

- (void)_foreground_exportSendToServiceWithFileWrapper:(NSFileWrapper *)fileWrapper;
{
    __autoreleasing NSError *error;
    NSURL *tempURL = [self _tempURLForExportedFileWrapper:fileWrapper shouldZipDirectories:NO error:&error];
    if (tempURL == nil) {
        NSError *strongError = error;
        [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
            OUI_PRESENT_ERROR_FROM(strongError, _navigationController);
        }];
        return;
    }
    
    [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
        UIDocumentPickerViewController *pickerViewController = [[UIDocumentPickerViewController alloc] initWithURL:tempURL inMode:UIDocumentPickerModeExportToService];
        pickerViewController.delegate = self;
        [[self _viewControllerForPresenting] presentViewController:pickerViewController animated:YES completion:nil];
    }];
}

- (void)_foreground_exportDocumentOfType:(NSString *)fileType;
{
    OBPRECONDITION([NSThread isMainThread]);
    @autoreleasepool {

        if (!_fileItem) {
            OBASSERT_NOT_REACHED("no selected document");
            [self _foreground_enableInterfaceAfterExportConversionWithCompletion:nil];
            return;
        }

        void (^finish)(NSFileWrapper * _Nullable, NSError * _Nullable) = ^(NSFileWrapper * _Nullable fileWrapper, NSError * _Nullable error){
            // Need to make sure all of this happens on the main thread.
            main_async(^{
                if (fileWrapper == nil) {
                    [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
                        OUI_PRESENT_ERROR_FROM(error, _navigationController);
                    }];
                } else {
                    [self _foreground_exportFileWrapper:fileWrapper];
                }
            });
        };

        // Give apps an opportunity to override, or defer to super for the simplest cases
        [_exporter exportFileWrapperOfType:fileType forFileItem:_fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            finish(fileWrapper, error);
        }];
    }
}

- (void)_foreground_disableInterfaceForExportConversionWithCompletion:(void (^ _Nullable)(void))completion;
{
    OUIExportOptionPickerViewController *picker = self.optionPickerViewController;
    if (picker) {
        [picker setInterfaceDisabledWhileExporting:YES completion:completion];
    } else if (completion) {
        main_async(^{
            completion();
        });
    }
}
- (void)_foreground_enableInterfaceAfterExportConversionWithCompletion:(void (^ _Nullable)(void))completion;
{
    OUIExportOptionPickerViewController *picker = self.optionPickerViewController;
    if (picker) {
        [picker setInterfaceDisabledWhileExporting:NO completion:completion];
    } else if (completion) {
        main_async(^{
            completion();
        });
    }
}

- (void)_foreground_emailExportOfType:(NSString *)exportType;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    @autoreleasepool {
        if (OFISNULL(exportType)) {
            // The fileType being null means that the user selected the OO3 file. This does not require a conversion.
            [_navigationController.presentingViewController dismissViewControllerAnimated:YES completion:^{
                [_exporter emailFileItem:_fileItem];
            }];
            return;
        }

        if (!_fileItem) {
            OBASSERT_NOT_REACHED("no selected document");
            [self _foreground_enableInterfaceAfterExportConversionWithCompletion:nil];
            return;
        }
        
        [_exporter exportFileWrapperOfType:exportType forFileItem:_fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            if (fileWrapper == nil) {
                [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
                    OUI_PRESENT_ERROR_FROM(error, _navigationController);
                }];
                return;
            }

            [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
                [_navigationController.presentingViewController dismissViewControllerAnimated:YES completion:^{
                    [_exporter sendEmailWithFileWrapper:fileWrapper forExportType:exportType fileName:_fileItem.name];
                }];
            }];
        }];
    }
}

- (void)_performActionForExportOption:(OUIExportOption *)option;
{
    NSString *fileType = option.fileType;

    [self _foreground_disableInterfaceForExportConversionWithCompletion:^{
        if (_exportType == OUIExportOptionsEmail) {
            [self _foreground_emailExportOfType:fileType];
        } else {
            [self _foreground_exportDocumentOfType:fileType];
        }
    }];
}

- (NSArray <OUIExportOption *> *)_exportOptions;
{
    NSArray *inAppPurchaseExportTypes = [_exporter availableInAppPurchaseExportTypesForFileItem:_fileItem serverAccount:_serverAccount exportOptionsType:_exportType];

    NSMutableArray <OUIExportOption *> *exportOptions = [NSMutableArray array];
    NSArray <NSString *> *fileTypes = [_exporter availableExportTypesForFileItem:_fileItem serverAccount:_serverAccount exportOptionsType:_exportType];
    for (NSString *fileType in fileTypes) {

        UIImage *iconImage = nil;
        NSString *label = nil;


        if (OFISNULL(fileType)) {
            // NOTE: Adding the native type first with a null (instead of a its non-null actual type) is important for doing exports of documents exactly as they are instead of going through the exporter. Ideally both cases would be the same, but in OO/iPad the OO3 "export" path (as opposed to normal "save") has the ability to strip hidden columns, sort sorts, calculate summary values and so on for the benefit of the XSL-based exporters. If we want "export" to the OO file format to not perform these transformations, we'll need to add flags on the OOXSLPlugin to say whether the target wants them pre-applied or not.
            NSURL *documentURL = _fileItem.fileURL;
            OBFinishPortingLater("<bug:///75843> (Add a UTI property to ODSFileItem)");
            NSString *fileUTI = OFUTIForFileExtensionPreferringNative([documentURL pathExtension], nil); // NSString *fileUTI = [ODAVFileInfo UTIForURL:documentURL];
            iconImage = [_exporter exportIconForUTI:fileUTI];

            label = [_exporter exportLabelForUTI:fileUTI];
            if (label == nil) {
                label = [[documentURL path] pathExtension];
            }
        }
        else {
            iconImage = [_exporter exportIconForUTI:fileType];
            label = [_exporter exportLabelForUTI:fileType];
        }

        BOOL requiresPurchase = [inAppPurchaseExportTypes containsObject:fileType];
        OUIExportOption *option = [[OUIExportOption alloc] initWithFileType:fileType label:label image:iconImage requiresPurchase:requiresPurchase];
        [exportOptions addObject:option];
    }

    return [exportOptions copy];
}

- (OUIExportOptionPickerViewController *)_makeOptionPickerViewControllerWithExportOptions:(NSArray <OUIExportOption *> *)exportOptions;
{
    OUIExportOptionPickerViewController *picker = [[OUIExportOptionPickerViewController alloc] initWithExportOptions:exportOptions];
    picker.delegate = self;

    NSArray *inAppPurchaseExportTypes = [_exporter availableInAppPurchaseExportTypesForFileItem:_fileItem serverAccount:_serverAccount exportOptionsType:_exportType];

    if ([inAppPurchaseExportTypes count] > 0) {
        OBASSERT([inAppPurchaseExportTypes count] == 1);    // only support for one in-app export type
        NSString *exportType = [inAppPurchaseExportTypes objectAtIndex:0];

        NSString *label = [_exporter purchaseDescriptionForExportType:exportType];
        NSString *purchaseNowLocalized = NSLocalizedStringFromTableInBundle(@"Purchase Now.", @"OmniUIDocument", OMNI_BUNDLE, @"purchase now button title");

        picker.inAppPurchaseButtonTitle = [NSString stringWithFormat:@"%@ %@", label, purchaseNowLocalized];
        picker.showInAppPurchaseButton = YES;
    } else {
        picker.showInAppPurchaseButton = NO;
    }

    NSString *docName = _fileItem.name;

    NSString *actionDescription = nil;
    switch (_exportType) {
        case OUIExportOptionsNone:
            OBASSERT_NOT_REACHED("We don't present a controller if we're not exporting");
            break;

        case OUIExportOptionsEmail:
            picker.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUIDocument", OMNI_BUNDLE, @"export options title");
            [picker setExportDestination:nil];
            actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choose a format for emailing \"%@\":", @"OmniUIDocument", OMNI_BUNDLE, @"email action description"), docName, nil];
            break;

        case OUIExportOptionsSendToApp:
            [picker setExportDestination:nil];
            actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Send \"%@\" to app as:", @"OmniUIDocument", OMNI_BUNDLE, @"send to app description"), docName, nil];
            break;

        case OUIExportOptionsSendToService:
            [picker setExportDestination:nil];
            actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Export \"%@\" as:", @"OmniUIDocument", OMNI_BUNDLE, @"export to description"), docName, nil];
            break;

        case OUIExportOptionsExport:
            if (OFISEQUAL(_serverAccount.type.identifier, OFXiTunesLocalDocumentsServerAccountTypeIdentifier)) {
                [picker setExportDestination:nil];
            } else {
                NSString *addressString = [_serverAccount.remoteBaseURL absoluteString];
                [picker setExportDestination:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Server address: %@", @"OmniUIDocument", OMNI_BUNDLE, @"email action description"), addressString, nil]];
            }
            actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Export \"%@\" to %@ as:", @"OmniUIDocument", OMNI_BUNDLE, @"export action description"), docName, _serverAccount.displayName, nil];
            break;
    }

    [picker setActionDescription:actionDescription];

    return picker;
}

#pragma mark - OUIExportOptionPickerViewControllerDelegate

- (void)exportOptionPicker:(OUIExportOptionPickerViewController *)optionPicker selectedExportOption:(OUIExportOption *)exportOption inRect:(CGRect)optionRect ofView:(UIView *)optionView;
{
    _optionPickerView = optionView;
    _optionPickerRect = optionRect;

    if (exportOption.requiresPurchase) {
        [_exporter purchaseExportType:exportOption.fileType navigationController:_navigationController];
    } else {
        [self _performActionForExportOption:exportOption];
    }
}

- (void)exportOptionPickerPerformInAppPurchase:(OUIExportOptionPickerViewController *)optionPicker;
{
    _optionPickerView = nil;
    _optionPickerRect = CGRectNull;

    NSArray *inAppPurchaseExportTypes = [_exporter availableInAppPurchaseExportTypesForFileItem:_fileItem serverAccount:_serverAccount exportOptionsType:_exportType];
    OBASSERT(inAppPurchaseExportTypes.count == 1);

    [_exporter purchaseExportType:inAppPurchaseExportTypes.firstObject navigationController:_navigationController];
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (void)documentInteractionController:(UIDocumentInteractionController *)controller didEndSendingToApplication:(nullable NSString *)application;
{
    main_async(^{
        [_exporter clearSelection];
    });
    [_navigationController.presentingViewController dismissViewControllerAnimated:NO completion:nil];
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller;
{
    return _navigationController;
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(nonnull NSArray<NSURL *> *)urls
{
    [_navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller;
{
    [_navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
