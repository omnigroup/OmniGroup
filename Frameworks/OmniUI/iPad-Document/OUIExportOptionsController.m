// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIExportOptionsController.h"

#import <OmniUIDocument/OUIDocumentExporter.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUI/UIViewController-OUIExtensions.h>

@import OmniFoundation;

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

@interface OUIExportOptionsController () <OUIExportOptionPickerViewControllerDelegate>

@property (nonatomic, nullable, readonly) OUIExportOptionPickerViewController *optionPickerViewController;
@property (nonatomic, strong) OUIExportOption *cachedPurchaseOption;

@end


@implementation OUIExportOptionsController
{
    NSArray <NSURL *> *_fileURLs;

    // This navigation controller has a strong pointer back to us, and will be retained while it is presented on screen by the host view controller.
    __weak _OUIExportOptionsNavigationController *_navigationController;

    OUIDocumentExporter *_exporter;
    UIActivity *_activity;
    
    UIView *_optionPickerView;
    CGRect _optionPickerRect;
    
    // Processing state
    NSString *_exportFileType;
    NSEnumerator <NSURL *> *_fileURLEnumerator;
    NSMutableArray <NSURL *> *_temporaryOutputFileURLs;
    NSError *_exportError;
}

- (id)initWithFileURLs:(NSArray <NSURL *> *)fileURLs exporter:(OUIDocumentExporter *)exporter activity:(UIActivity *)activity;
{
    self = [super init];

    _fileURLs = [fileURLs copy];
    _exporter = exporter;
    _activity = activity;
    
    return self;
}

- (BOOL)hasExportOptions;
{
    NSArray <OUIExportOption *> *exportOptions = [self _exportOptions];

    // If we can only export as the 'null' native format that isn't actually converting anything, then there is no purpose to this activity.
    if (exportOptions.count == 1 && exportOptions.firstObject.requiresPurchase == NO && OFISNULL(exportOptions.firstObject.fileType))
        return NO;

    return YES;
}

- (UIViewController *)viewController;
{
    NSArray <OUIExportOption *> *exportOptions = [self _exportOptions];
    UIViewController *rootViewController = [self _makeOptionPickerViewControllerWithExportOptions:exportOptions];

    // This will keep us alive as long as it is on screen.
    _OUIExportOptionsNavigationController *navigationController = [[_OUIExportOptionsNavigationController alloc] initWithRootViewController:rootViewController];
    navigationController.optionsController = self;
    _navigationController = navigationController;

    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    return navigationController;
}

- (nullable OUIExportOptionPickerViewController *)optionPickerViewController;
{
    UIViewController *rootViewController = _navigationController.viewControllers.firstObject;
    if ([rootViewController isKindOfClass:[OUIExportOptionPickerViewController class]]) {
        return (OUIExportOptionPickerViewController *)rootViewController;
    }
    return nil;
}

#pragma mark - Private

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

- (void)_foreground_shareConvertedFileURLs;
{
    [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:_temporaryOutputFileURLs applicationActivities:nil];

        OBASSERT(_optionPickerView);
        activityViewController.modalPresentationStyle = UIModalPresentationPopover;
        activityViewController.popoverPresentationController.sourceRect = _optionPickerRect;
        activityViewController.popoverPresentationController.sourceView = _optionPickerView;
        
        activityViewController.completionWithItemsHandler = ^(UIActivityType  _Nullable UIActivityType, BOOL completed, NSArray * _Nullable returnedItems, NSError * _Nullable activityError){
            // Signal to our enclosing activity that we finished (which should dismiss our view controller).
            [_activity activityDidFinish:completed];
        };
        
        [_navigationController presentViewController:activityViewController animated:YES completion:nil];
    }];
}

- (void)_foreground_exportDocumentsOfType:(NSString *)fileType parentViewController:(UIViewController *)parentViewController;
{
    OBPRECONDITION([NSThread isMainThread]);
    @autoreleasepool {

        if ([_fileURLs count] == 0) {
            OBASSERT_NOT_REACHED("no selected document");
            [self _foreground_enableInterfaceAfterExportConversionWithCompletion:nil];
            return;
        }

        OBASSERT(_fileURLEnumerator == nil, "We don't expect to be reused");
        _fileURLEnumerator = [_fileURLs objectEnumerator];
        _temporaryOutputFileURLs = [NSMutableArray array];
        _exportFileType = fileType;
        _exportError = nil;
        
        [self _foreground_processNextFileWithParentViewController:parentViewController];
    }
}

- (void)_foreground_processNextFileWithParentViewController:(UIViewController *)parentViewController;
{
    OBPRECONDITION([NSThread isMainThread]);

    NSURL *fileURL = [_fileURLEnumerator nextObject];
    if (!fileURL) {
        [self _foreground_finishedProcessing];
        return;
    }
    
    Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:fileURL];
    if (!documentClass) {
        OBASSERT_NOT_REACHED("Should not be able to select files in the document browser that we can't open");
        [self _foreground_processNextFileWithParentViewController:parentViewController];
        return;
    }
    
    __autoreleasing NSError *initError;
    OUIDocument *document = [[documentClass alloc] initWithExistingFileURL:fileURL error:&initError];
    if (!document) {
        [initError log:@"Error creating document for %@", fileURL];
        [self _foreground_processNextFileWithParentViewController:parentViewController];
        return;
    }
    
    // Let the document know it can avoid work that isn't needed if the document isn't going to be presented to the user to edit.
    document.forExportOnly = YES;

    document.activityViewController = parentViewController;
    
    [document openWithCompletionHandler:^(BOOL openSuccess) {
        if (!openSuccess) {
            NSLog(@"Error opening document at %@", fileURL);
            [self _foreground_processNextFileWithParentViewController:parentViewController];
        }
        
        // Give apps an opportunity to override, or defer to super for the simplest cases
        [document exportFileWrapperOfType:_exportFileType parentViewController:parentViewController withCompletionHandler:^(NSFileWrapper * _Nullable fileWrapper, NSError * _Nullable exportError) {
            if (!fileWrapper) {
                _exportError = exportError;
                [self _foreground_finishedProcessing];
                return;
            }
            
            __autoreleasing NSError *writeError = nil;
            NSURL *outputURL = [self _tempURLForExportedFileWrapper:fileWrapper shouldZipDirectories:NO error:&writeError];
//            outputURL = [outputURL URLByAppendingPathComponent:document.fileURL.lastPathComponent];
            if (!outputURL) {
                _exportError = writeError;
                [self _foreground_finishedProcessing];
                return;
            }
            [_temporaryOutputFileURLs addObject:outputURL];
            
            [document closeWithCompletionHandler:^(BOOL closeSuccess) {
                OBASSERT(closeSuccess);
                
                [document didClose];
                
                [self _foreground_processNextFileWithParentViewController:parentViewController];
            }];
        }];
    }];
}

- (void)_foreground_finishedProcessing;
{
    // Need to make sure all of this happens on the main thread.
    main_async(^{
        if (_exportError) {
            [self _foreground_enableInterfaceAfterExportConversionWithCompletion:^{
                OUI_PRESENT_ERROR_FROM(_exportError, _navigationController);
            }];
            return;
        }
        [self _foreground_shareConvertedFileURLs];
    });
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

- (void)_performActionForExportOption:(OUIExportOption *)option parentViewController:(UIViewController *)parentViewController;
{
    NSString *fileType = option.fileType;

    [self _foreground_disableInterfaceForExportConversionWithCompletion:^{
        [self _foreground_exportDocumentsOfType:fileType parentViewController:parentViewController];
    }];
}

- (NSArray <OUIExportOption *> *)_exportOptions;
{
    NSMutableOrderedSet <NSString *> *inAppPurchaseExportTypes = [NSMutableOrderedSet orderedSet];
    for (NSURL *fileURL in _fileURLs) {
        NSArray *types = [_exporter availableInAppPurchaseExportTypesForFileURL:fileURL];
        if (types) {
            [inAppPurchaseExportTypes addObjectsFromArray:types];
        }
    }

    NSMutableOrderedSet <OUIExportOption *> *exportOptions = [NSMutableOrderedSet orderedSet];
    for (NSURL *fileURL in _fileURLs) {
        NSArray <NSString *> *fileTypes = [_exporter availableExportTypesForFileURL:fileURL];
        for (NSString *fileType in fileTypes) {
            
            UIImage *iconImage = nil;
            NSString *label = nil;
            
            
            if (OFISNULL(fileType)) {
                // NOTE: Adding the native type first with a null (instead of a its non-null actual type) is important for doing exports of documents exactly as they are instead of going through the exporter. Ideally both cases would be the same, but in OO/iPad the OO3 "export" path (as opposed to normal "save") has the ability to strip hidden columns, sort sorts, calculate summary values and so on for the benefit of the XSL-based exporters. If we want "export" to the OO file format to not perform these transformations, we'll need to add flags on the OOXSLPlugin to say whether the target wants them pre-applied or not.
                NSString *fileUTI = OFUTIForFileExtensionPreferringNative(fileURL.pathExtension, nil);
                iconImage = [_exporter exportIconForUTI:fileUTI];
                
                label = [_exporter exportLabelForUTI:fileUTI];
                if (label == nil) {
                    label = [_exporter exportLabelForUTI:fileUTI];
                }
                if (label == nil) {
                    label = [fileURL pathExtension];
                }
            } else {
                iconImage = [_exporter exportIconForUTI:fileType];
                label = [_exporter exportLabelForUTI:fileType];
            }
            
            BOOL requiresPurchase = [inAppPurchaseExportTypes containsObject:fileType];
            OBASSERT(requiresPurchase == NO); // The availableExportTypesForFileURL and inAppPurchaseExportTypes should be disjoint
            
            OUIExportOption *option = [[OUIExportOption alloc] initWithFileType:fileType label:label image:iconImage requiresPurchase:requiresPurchase];
            [exportOptions addObject:option];
        }
    }

    // Add on any export types that require a purchase (this will be empty if the purchase has been made already and the types will have already been added via -availableExportTypesForFileURL:.
    for (NSString *fileType in inAppPurchaseExportTypes) {
        UIImage *iconImage = [_exporter exportIconForUTI:fileType];
        NSString *label = [_exporter exportLabelForUTI:fileType];

        OUIExportOption *option = [[OUIExportOption alloc] initWithFileType:fileType label:label image:iconImage requiresPurchase:YES];
        [exportOptions addObject:option];
    }
    
    
    return [[exportOptions array] copy];
}

- (OUIExportOptionPickerViewController *)_makeOptionPickerViewControllerWithExportOptions:(NSArray <OUIExportOption *> *)exportOptions;
{
    NSArray <OUIExportOption *> *availableExportOptions = [exportOptions select:^BOOL(OUIExportOption *option) {
        return !option.requiresPurchase;
    }];

    OUIExportOptionPickerViewController *picker = [[OUIExportOptionPickerViewController alloc] initWithExportOptions:availableExportOptions];
    picker.delegate = self;

    NSArray <OUIExportOption *> *inAppPurchaseOptions = [exportOptions select:^BOOL(OUIExportOption *option) {
        return option.requiresPurchase;
    }];
    if ([inAppPurchaseOptions count] > 0) {
        OBASSERT([inAppPurchaseOptions count] == 1);    // only support for one in-app export type
        OUIExportOption *exportOption = inAppPurchaseOptions[0];

        NSString *label = [_exporter purchaseDescriptionForExportType:exportOption.fileType];
        NSString *purchaseNowLocalized = NSLocalizedStringFromTableInBundle(@"Purchase Now.", @"OmniUIDocument", OMNI_BUNDLE, @"purchase now button title");

        picker.inAppPurchaseButtonTitle = [NSString stringWithFormat:@"%@ %@", label, purchaseNowLocalized];
        picker.showInAppPurchaseButton = YES;
        self.cachedPurchaseOption = exportOption;
    } else {
        picker.showInAppPurchaseButton = NO;
    }

    // TODO: We used to include the document name here, but we can have multiple documents now. We could include the name if there is exactly one, or do a stringsdict and do "Share %d documents as..."
#if 0
    Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:_fileURL];
    
    NSString *docName = [documentClass displayNameForFileURL:_fileURL];

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
    }
#endif
    [picker setExportDestination:nil];

    return picker;
}

#pragma mark - OUIExportOptionPickerViewControllerDelegate

- (void)exportOptionPicker:(OUIExportOptionPickerViewController *)optionPicker selectedExportOption:(OUIExportOption *)exportOption inRect:(CGRect)optionRect ofView:(UIView *)optionView;
{
    _optionPickerView = optionView;
    _optionPickerRect = optionRect;

    if (exportOption.requiresPurchase) {
        [_exporter purchaseExportType:exportOption.fileType scene:_navigationController.containingScene];
    } else {
        [self _performActionForExportOption:exportOption parentViewController:optionPicker];
    }
}

- (void)exportOptionPickerPerformInAppPurchase:(OUIExportOptionPickerViewController *)optionPicker;
{
    // the activity finishing will release the navigation controller, so lets grab our scene before we let that happen, so we know what scene needs the purchase UI.
    UIScene *scene = [_navigationController containingScene];
    [_activity activityDidFinish:YES];
    _optionPickerView = nil;
    _optionPickerRect = CGRectNull;
    [_exporter purchaseExportType:_cachedPurchaseOption.fileType scene:scene];
}

@end

NS_ASSUME_NONNULL_END
