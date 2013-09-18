// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsController.h"

#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIAppController+InAppStore.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIOverlayView.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUnzip/OUZipArchive.h>

#import "OUIExportOptionsView.h"
#import "OUIWebDAVSyncListController.h"

RCS_ID("$Id$")

static NSString * const OUIExportInfoFileWrapper = @"OUIExportInfoFileWrapper";
static NSString * const OUIExportInfoExportType = @"OUIExportInfoExportType";

@interface OUIExportOptionsController () //<OFSFileManagerDelegate>
@property(nonatomic, strong) IBOutlet OUIExportOptionsView *exportView;
@property(nonatomic, strong) IBOutlet UILabel *exportDescriptionLabel;
@property(nonatomic, strong) IBOutlet UILabel *exportDestinationLabel;
@property(nonatomic, strong) IBOutlet UILabel *inAppPurchaseLabel;
@property(nonatomic, strong) IBOutlet UIButton *inAppPurchaseButton;
@end


@implementation OUIExportOptionsController
{
    OUIExportOptionsView *_exportView;
    UILabel *_exportDescriptionLabel;
    UILabel *_exportDestinationLabel;
    UILabel *_inAppPurchaseLabel;
    UIButton *_inAppPurchaseButton;
    
    OFXServerAccount *_serverAccount;
    OUIExportOptionsType _exportType;
    NSMutableArray *_exportFileTypes;
    
    UIView *_fileConversionOverlayView;
    
    UIDocumentInteractionController *_documentInteractionController;
    CGRect _rectForExportOptionButtonChosen;
    
    BOOL _needsToCheckInAppPurchaseAvailability;
    UIPopoverController *_activityPopoverController;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIExportOptions" bundle:OMNI_BUNDLE];
}

- (id)initWithServerAccount:(OFXServerAccount *)serverAccount exportType:(OUIExportOptionsType)exportType;
{
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    _serverAccount = serverAccount;
    _exportType = exportType;
    
    return self;
}

- (void)dealloc;
{
    _documentInteractionController.delegate = nil;
}

@synthesize documentInteractionController = _documentInteractionController;

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    
    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Choose Format", @"OmniUIDocument", OMNI_BUNDLE, @"export options title");
    
    OUIDocumentPickerViewController *picker = [[[OUIDocumentAppController controller] documentPicker] selectedScopeViewController];
    
    _exportFileTypes = [[NSMutableArray alloc] init];
    
    ODSFileItem *fileItem = picker.singleSelectedFileItem;
        
    NSArray *exportTypes = [picker availableExportTypesForFileItem:fileItem serverAccount:_serverAccount exportOptionsType:_exportType];
    for (NSString *exportType in exportTypes) {
        
        UIImage *iconImage = nil;
        NSString *label = nil;
        
        
        if (OFISNULL(exportType)) {
            // NOTE: Adding the native type first with a null (instead of a its non-null actual type) is important for doing exports of documents exactly as they are instead of going through the exporter. Ideally both cases would be the same, but in OO/iPad the OO3 "export" path (as opposed to normal "save") has the ability to strip hidden columns, sort sorts, calculate summary values and so on for the benefit of the XSL-based exporters. If we want "export" to the OO file format to not perform these transformations, we'll need to add flags on the OOXSLPlugin to say whether the target wants them pre-applied or not.
            NSURL *documentURL = fileItem.fileURL;
            OBFinishPortingLater("<bug:///75843> (Add a UTI property to ODSFileItem)");
            NSString *fileUTI = OFUTIForFileExtensionPreferringNative([documentURL pathExtension], NO); // NSString *fileUTI = [ODAVFileInfo UTIForURL:documentURL];
            iconImage = [picker exportIconForUTI:fileUTI];
            
            label = [picker exportLabelForUTI:fileUTI];
            if (label == nil) {
                label = [[documentURL path] pathExtension];
            }
        }
        else {
            iconImage = [picker exportIconForUTI:exportType];
            label = [picker exportLabelForUTI:exportType];
        }
        
        
        [_exportFileTypes addObject:exportType];
        [_exportView addChoiceWithImage:iconImage label:label target:self selector:@selector(_performActionForExportOptionButton:)];
    }
    
    NSArray *inAppPurchaseExportTypes = [picker availableInAppPurchaseExportTypesForFileItem:fileItem serverAccount:_serverAccount exportOptionsType:_exportType];
    if ([inAppPurchaseExportTypes count] > 0) {
        OBASSERT([inAppPurchaseExportTypes count] == 1);    // only support for one in-app export type
        NSString *storeIdentifier = [inAppPurchaseExportTypes objectAtIndex:0];

        [_exportFileTypes addObject:storeIdentifier];

        if ([[OUIAppController controller] importIsUnlocked:storeIdentifier]) {
            UIImage *iconImage = [picker exportIconForAppStoreIdentifier:storeIdentifier];
            NSString *label = [picker exportLabelForAppStoreIdentifier:storeIdentifier];

            [_exportView addChoiceWithImage:iconImage label:label target:self selector:@selector(_performActionForInAppPurchaseExportOptionButton:)];
            
            [_inAppPurchaseButton setHidden:YES];
            [_inAppPurchaseLabel setHidden:YES];
        } else {
            NSString *label = [picker exportDescriptionForAppStoreIdentifier:storeIdentifier];
            _inAppPurchaseLabel.text = label;
            
            [_inAppPurchaseButton setHidden:NO];
            [_inAppPurchaseButton setTag:([_exportFileTypes count]-1)];
            [_inAppPurchaseLabel setHidden:NO];
        }
    } else {
        [_inAppPurchaseButton setHidden:YES];
        [_inAppPurchaseLabel setHidden:YES];
    }
    
    [_exportView layoutSubviews];
    
    if (![_inAppPurchaseButton isHidden]) {
        [_inAppPurchaseButton setBackgroundImage:[[UIImage imageNamed:@"OUIToolbarButton-Black-Normal.png"] stretchableImageWithLeftCapWidth:5 topCapHeight:0] forState:UIControlStateNormal];
        [_inAppPurchaseButton setBackgroundImage:[[UIImage imageNamed:@"OUIToolbarButton-Black-Highlighted.png"] stretchableImageWithLeftCapWidth:5 topCapHeight:0] forState:UIControlStateHighlighted];
        [_inAppPurchaseButton addTarget:self action:@selector(_performActionForInAppPurchaseExportOptionButton:) forControlEvents:UIControlEventTouchUpInside];
        
        CGRect inAppPurchaseButtonRect = _inAppPurchaseButton.frame;
        inAppPurchaseButtonRect.origin.y = CGRectGetMaxY(_exportView.frame) + 8;
        [_inAppPurchaseButton setFrame:inAppPurchaseButtonRect];
        
        CGRect inAppPurchaseLabelRect = _inAppPurchaseLabel.frame;
        inAppPurchaseLabelRect.origin.y = CGRectGetMaxY(_exportView.frame) + 13;
        [_inAppPurchaseLabel setFrame:inAppPurchaseLabelRect];
    }
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    OUIDocumentPickerViewController *picker = [[[OUIDocumentAppController controller] documentPicker] selectedScopeViewController];
    ODSFileItem *fileItem = picker.singleSelectedFileItem;
    OBASSERT(fileItem != nil);
    NSString *docName = fileItem.name;
    
    NSString *actionDescription = nil;
    if (_exportType == OUIExportOptionsEmail) {
        self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUIDocument", OMNI_BUNDLE, @"export options title");
        
        _exportDestinationLabel.text = nil;
        
        actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choose a format for emailing \"%@\":", @"OmniUIDocument", OMNI_BUNDLE, @"email action description"), docName, nil];
    }
    else if (_exportType == OUIExportOptionsSendToApp) {
        _exportDestinationLabel.text = nil;
        
        actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Send \"%@\" to app as:", @"OmniUIDocument", OMNI_BUNDLE, @"send to app description"), docName, nil];
    }
    else if (_exportType == OUIExportOptionsExport) {
        if (OFISEQUAL(_serverAccount.type.identifier, OFXiTunesLocalDocumentsServerAccountTypeIdentifier)) {
            _exportDestinationLabel.text = nil;
        } else {
            NSString *addressString = [_serverAccount.remoteBaseURL absoluteString];
            _exportDestinationLabel.text = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Server address: %@", @"OmniUIDocument", OMNI_BUNDLE, @"email action description"), addressString, nil];
        }
                
        actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Export \"%@\" to %@ as:", @"OmniUIDocument", OMNI_BUNDLE, @"export action description"), docName, _serverAccount.displayName, nil];
    }
    
    _exportDescriptionLabel.text = actionDescription;
    
    _rectForExportOptionButtonChosen = CGRectZero;
    
    if (_needsToCheckInAppPurchaseAvailability && ![_inAppPurchaseButton isHidden]) {
        NSArray *inAppPurchaseExportTypes = [picker availableInAppPurchaseExportTypesForFileItem:fileItem serverAccount:_serverAccount exportOptionsType:_exportType];
        if ([inAppPurchaseExportTypes count] > 0) {
            OBASSERT([inAppPurchaseExportTypes count] == 1);    // only support for one in-app export type
            NSString *storeIdentifier = [inAppPurchaseExportTypes objectAtIndex:0];
            
            if ([[OUIAppController controller] importIsUnlocked:storeIdentifier]) {
                UIImage *iconImage = [picker exportIconForAppStoreIdentifier:storeIdentifier];
                NSString *label = [picker exportLabelForAppStoreIdentifier:storeIdentifier];

                if (![_exportFileTypes containsObject:storeIdentifier])
                    [_exportFileTypes addObject:storeIdentifier];
                [_exportView addChoiceWithImage:iconImage label:label target:self selector:@selector(_performActionForInAppPurchaseExportOptionButton:)];
                
                [_inAppPurchaseButton setHidden:YES];
                [_inAppPurchaseLabel setHidden:YES];
                
                [_exportView layoutSubviews];
            }
        }
    }
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

#pragma mark - API

- (void)exportFileWrapper:(NSFileWrapper *)fileWrapper;
{
    [self _foreground_enableInterfaceAfterExportConversion];
    
    __autoreleasing NSError *error = nil;
    OUIWebDAVSyncListController *syncListController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:_serverAccount exporting:YES error:&error];
    if (!syncListController) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    syncListController.exportFileWrapper = fileWrapper;
    
    [self.navigationController pushViewController:syncListController animated:YES];
}

#pragma mark - Private

@synthesize exportView = _exportView;
@synthesize exportDestinationLabel = _exportDestinationLabel;
@synthesize exportDescriptionLabel = _exportDescriptionLabel;
@synthesize inAppPurchaseLabel = _inAppPurchaseLabel;
@synthesize inAppPurchaseButton = _inAppPurchaseButton;

- (IBAction)_cancel:(id)sender;
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)_foreground_exportFileWrapper:(NSFileWrapper *)fileWrapper;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_exportType != OUIExportOptionsSendToApp) {
        [self exportFileWrapper:fileWrapper];
        return;
    }
    
    // Write to temp folder (need URL of file on disk to pass off to Doc Interaction.)
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *tempPath = [temporaryDirectory stringByAppendingPathComponent:[fileWrapper preferredFilename]];
    NSURL *tempURL = nil;
    
    if ([fileWrapper isDirectory]) {
        // We need to zip this mother up!
        NSString *tempZipPath = [tempPath stringByAppendingPathExtension:@"zip"];
        
        @autoreleasepool {
            __autoreleasing NSError *error = nil;
            if (![OUZipArchive createZipFile:tempZipPath fromFileWrappers:[NSArray arrayWithObject:fileWrapper] error:&error]) {
                OUI_PRESENT_ERROR(error);
                return;
            }
        }

        tempURL = [NSURL fileURLWithPath:tempZipPath];
    } else {
        tempURL = [NSURL fileURLWithPath:tempPath isDirectory:[fileWrapper isDirectory]];
        
        // Get a FileManager for our Temp Directory.
        __autoreleasing NSError *error = nil;
        NSFileManager *fileManager = [NSFileManager defaultManager];

        // If the temp file exists, we delete it.
        if ([fileManager fileExistsAtPath:[tempURL path]]) {
            if (![fileManager removeItemAtURL:tempURL error:&error]) {
                OUI_PRESENT_ERROR(error);
                return;
            }
        }
        
        // Write to temp dir.
        if (![fileWrapper writeToURL:tempURL options:0 originalContentsURL:nil error:&error]) {
            OUI_PRESENT_ERROR(error);
            return;
        }
    }
    
    [self _foreground_enableInterfaceAfterExportConversion];
    
    // By now we have written the project out to a temp dir. Time to handoff to Doc Interaction.
    self.documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:tempURL];
    self.documentInteractionController.delegate = self;
    BOOL didOpen = [self.documentInteractionController presentOpenInMenuFromRect:_rectForExportOptionButtonChosen inView:_exportView animated:YES];
    if (didOpen == NO) {
        // Show Activity View Controller instead.
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[tempURL] applicationActivities:nil];
        
        if (!_activityPopoverController) {
            _activityPopoverController = [[UIPopoverController alloc] initWithContentViewController:activityViewController];
        }
        
        [[OUIDocumentAppController controller] presentPopover:_activityPopoverController fromRect:_rectForExportOptionButtonChosen inView:_exportView permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    }
}

- (void)_foreground_exportDocumentOfType:(NSString *)fileType;
{
    OBPRECONDITION([NSThread isMainThread]);
    @autoreleasepool {
        OUIDocumentPickerViewController *documentPicker = [[[OUIDocumentAppController controller] documentPicker] selectedScopeViewController];
        ODSFileItem *fileItem = documentPicker.singleSelectedFileItem;
        if (!fileItem) {
            OBASSERT_NOT_REACHED("no selected document");
            [self _foreground_enableInterfaceAfterExportConversion];
            return;
        }
        
        [documentPicker exportFileWrapperOfType:fileType forFileItem:fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            // Need to make sure all of this happens on the main thread.
            main_async(^{
                if (fileWrapper == nil) {
                    OUI_PRESENT_ERROR(error);
                    [self _foreground_enableInterfaceAfterExportConversion];
                } else {
                    [self _foreground_exportFileWrapper:fileWrapper];
                }
            });
        }];
    }
}

- (void)_setInterfaceDisabledWhileExporting:(BOOL)shouldDisable;
{
    self.navigationItem.leftBarButtonItem.enabled = !shouldDisable;
    self.navigationItem.rightBarButtonItem.enabled = !shouldDisable;
    self.view.userInteractionEnabled = !shouldDisable;
    
    
    if (shouldDisable) {
        OBASSERT_NULL(_fileConversionOverlayView)
        _fileConversionOverlayView = [[UIView alloc] initWithFrame:_exportView.frame];
        [self.view addSubview:_fileConversionOverlayView];
        
        UIActivityIndicatorView *fileConversionActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        // Figure out center of overlay view.
        CGPoint overlayCenter = _fileConversionOverlayView.center;
        CGPoint actualCenterForActivityIndicator = (CGPoint){
            .x = overlayCenter.x - _fileConversionOverlayView.frame.origin.x,
            .y = overlayCenter.y - _fileConversionOverlayView.frame.origin.y
        };
        
        fileConversionActivityIndicator.center = actualCenterForActivityIndicator;
        
        [_fileConversionOverlayView addSubview:fileConversionActivityIndicator];
        [fileConversionActivityIndicator startAnimating];
    }
    else {
        OBASSERT_NOTNULL(_fileConversionOverlayView);
        [_fileConversionOverlayView removeFromSuperview];
        _fileConversionOverlayView = nil;
    }
}

- (void)_foreground_disableInterfaceForExportConversion;
{
    OBPRECONDITION([NSThread isMainThread]);
    [self _setInterfaceDisabledWhileExporting:YES];
}
- (void)_foreground_enableInterfaceAfterExportConversion;
{
    OBPRECONDITION([NSThread isMainThread]);
    [self _setInterfaceDisabledWhileExporting:NO];
}

- (void)_beginBackgroundExportDocumentOfType:(NSString *)fileType;
{
    [self _foreground_disableInterfaceForExportConversion];
    [self performSelector:@selector(_foreground_exportDocumentOfType:) withObject:fileType afterDelay:0.0];
    //[self _foreground_exportDocumentOfType:fileType];
}

- (void)_foreground_finishBackgroundEmailExportWithExportType:(NSString *)exportType fileWrapper:(NSFileWrapper *)fileWrapper;
{
    OBPRECONDITION([NSThread isMainThread]);
    [self _foreground_enableInterfaceAfterExportConversion];
    
    if (fileWrapper) {
        [self.navigationController dismissViewControllerAnimated:YES completion:^{
            OUIDocumentPickerViewController *documentPicker = [[[OUIDocumentAppController controller] documentPicker] selectedScopeViewController];
            [documentPicker sendEmailWithFileWrapper:fileWrapper forExportType:exportType];
        }];
    }
}

- (void)_foreground_emailExportOfType:(NSString *)exportType;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    @autoreleasepool {
        if (OFISNULL(exportType)) {
            // The fileType being null means that the user selected the OO3 file. This does not require a conversion.
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [[[[OUIDocumentAppController controller] documentPicker] selectedScopeViewController] emailDocument:nil];
            }];
            return;
        }
        
        OUIDocumentPickerViewController *documentPicker = [[[OUIDocumentAppController controller] documentPicker] selectedScopeViewController];
        ODSFileItem *fileItem = documentPicker.singleSelectedFileItem;
        if (!fileItem) {
            OBASSERT_NOT_REACHED("no selected document");
            [self _foreground_enableInterfaceAfterExportConversion];
            return;
        }
        
        [documentPicker exportFileWrapperOfType:exportType forFileItem:fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            if (fileWrapper == nil) {
                OUI_PRESENT_ERROR(error);
                [self _foreground_enableInterfaceAfterExportConversion];
            }
            else {
                [self _foreground_finishBackgroundEmailExportWithExportType:exportType fileWrapper:fileWrapper];
            }
        }];
    }
}

- (void)_performActionForExportOptionButton:(UIButton *)sender;
{
    OBPRECONDITION([sender isKindOfClass:[UIButton class]]);
    OBPRECONDITION(sender.tag >= 0 && sender.tag < (signed)_exportFileTypes.count);
    
    _rectForExportOptionButtonChosen = sender.frame;
    NSString *fileType = [_exportFileTypes objectAtIndex:sender.tag];
    
    if (_exportType == OUIExportOptionsEmail) {
        [self _foreground_disableInterfaceForExportConversion];   
        [self _foreground_emailExportOfType:fileType];
    } else {
        [self _beginBackgroundExportDocumentOfType:fileType];
    }
}

- (void)_performActionForInAppPurchaseExportOptionButton:(UIButton *)sender;
{
    OBPRECONDITION([sender isKindOfClass:[UIButton class]]);
    OBPRECONDITION(sender.tag >= 0 && sender.tag < (signed)_exportFileTypes.count);
    
    NSString *productIdentifier = [_exportFileTypes objectAtIndex:sender.tag];
    if ([[OUIAppController controller] importIsUnlocked:productIdentifier]) {
        OBASSERT([[OUIAppController controller] documentUTIForInAppStoreProductIdentifier:productIdentifier] != nil);
        NSString *fileType = [[OUIAppController controller] documentUTIForInAppStoreProductIdentifier:productIdentifier];
        if (_exportType == OUIExportOptionsEmail) {
            [self _foreground_disableInterfaceForExportConversion];
            [self _foreground_emailExportOfType:fileType];
        } else {
            [self _beginBackgroundExportDocumentOfType:fileType];
        }
    } else {
        _needsToCheckInAppPurchaseAvailability = YES;
        [[OUIAppController controller] showInAppPurchases:productIdentifier navigationController:[self navigationController]];
    }
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (void)documentInteractionController:(UIDocumentInteractionController *)controller willBeginSendingToApplication:(NSString *)application;
{
    [self dismissViewControllerAnimated:NO completion:nil];
}

@end
