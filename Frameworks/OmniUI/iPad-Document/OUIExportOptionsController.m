// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsController.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIOverlayView.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUnzip/OUZipArchive.h>

#import "OUIExportOptionsView.h"
#import "OUIWebDAVSyncListController.h"

RCS_ID("$Id$")

static NSString * const OUIExportInfoFileWrapper = @"OUIExportInfoFileWrapper";
static NSString * const OUIExportInfoExportType = @"OUIExportInfoExportType";

@interface OUIExportOptionsController () <OFSFileManagerDelegate>
@property(nonatomic, strong) IBOutlet OUIExportOptionsView *exportView;
@property(nonatomic, strong) IBOutlet UILabel *exportDescriptionLabel;
@property(nonatomic, strong) IBOutlet UILabel *exportDestinationLabel;
@end


@implementation OUIExportOptionsController
{
    OUIExportOptionsView *_exportView;
    UILabel *_exportDescriptionLabel;
    UILabel *_exportDestinationLabel;
    
    OFXServerAccount *_serverAccount;
    OUIExportOptionsType _exportType;
    NSMutableArray *_exportFileTypes;
    
    OUIOverlayView *_fileConversionOverlayView;
    
    UIDocumentInteractionController *_documentInteractionController;
    CGRect _rectForExportOptionButtonChosen;
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
    
    UIImage *paneBackground = [UIImage imageNamed:@"OUIExportPane.png"];
    OBASSERT([self.view isKindOfClass:[UIImageView class]]);
    [(UIImageView *)self.view setImage:paneBackground];
    
    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Choose Format", @"OmniUIDocument", OMNI_BUNDLE, @"export options title");
    
    OUIDocumentPicker *picker = [[OUIDocumentAppController controller] documentPicker];
    
    _exportFileTypes = [[NSMutableArray alloc] init];
    
    OFSDocumentStoreFileItem *fileItem = picker.singleSelectedFileItem;
        
    NSArray *exportTypes = [picker availableExportTypesForFileItem:fileItem serverAccount:_serverAccount exportOptionsType:_exportType];
    for (NSString *exportType in exportTypes) {
        
        UIImage *iconImage = nil;
        NSString *label = nil;
        
        
        if (OFISNULL(exportType)) {
            // NOTE: Adding the native type first with a null (instead of a its non-null actual type) is important for doing exports of documents exactly as they are instead of going through the exporter. Ideally both cases would be the same, but in OO/iPad the OO3 "export" path (as opposed to normal "save") has the ability to strip hidden columns, sort sorts, calculate summary values and so on for the benefit of the XSL-based exporters. If we want "export" to the OO file format to not perform these transformations, we'll need to add flags on the OOXSLPlugin to say whether the target wants them pre-applied or not.
            NSURL *documentURL = fileItem.fileURL;
            OBFinishPortingLater("<bug:///75843> (Add a UTI property to OFSDocumentStoreFileItem)");
            NSString *fileUTI = OFUTIForFileExtensionPreferringNative([documentURL pathExtension], NO); // NSString *fileUTI = [OFSFileInfo UTIForURL:documentURL];
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
    
    [_exportView layoutSubviews];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    OUIDocumentPicker *picker = [[OUIDocumentAppController controller] documentPicker];
    OFSDocumentStoreFileItem *fileItem = picker.singleSelectedFileItem;
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
    }
    else {
        tempURL = [NSURL fileURLWithPath:tempPath isDirectory:[fileWrapper isDirectory]];
        
        // Get a FileManager for our Temp Directory.
        __autoreleasing NSError *error = nil;
        OFSFileManager *tempFileManager = [[OFSFileManager alloc] initWithBaseURL:tempURL delegate:self error:&error];
        if (error) {
            OUI_PRESENT_ERROR(error);
            return;
        }
        
        // Get the FileInfo for where we want to place the temp file.
        OFSFileInfo *fileInfo = [tempFileManager fileInfoAtURL:tempURL error:&error];
        if (error) {
            OUI_PRESENT_ERROR(error);
            return;
        }
        
        // If the temp file exists, we delete it.
        if ([fileInfo exists] == YES) {
            [tempFileManager deleteURL:tempURL error:&error];
            
            if (error) {
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
    [self.documentInteractionController presentOpenInMenuFromRect:_rectForExportOptionButtonChosen inView:_exportView animated:YES];
}

- (void)_foreground_exportDocumentOfType:(NSString *)fileType;
{
    OBPRECONDITION([NSThread isMainThread]);
    @autoreleasepool {
        OUIDocumentPicker *documentPicker = [[OUIDocumentAppController controller] documentPicker];
        OFSDocumentStoreFileItem *fileItem = documentPicker.singleSelectedFileItem;
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
        _fileConversionOverlayView = [[OUIOverlayView alloc] initWithFrame:_exportView.frame];
        [self.view addSubview:_fileConversionOverlayView];
        
        UIActivityIndicatorView *fileConversionActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
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
    [self _foreground_exportDocumentOfType:fileType];
}

- (void)_foreground_finishBackgroundEmailExportWithExportType:(NSString *)exportType fileWrapper:(NSFileWrapper *)fileWrapper;
{
    OBPRECONDITION([NSThread isMainThread]);
    [self _foreground_enableInterfaceAfterExportConversion];
    
    if (fileWrapper) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
        OUIDocumentPicker *documentPicker = [[OUIDocumentAppController controller] documentPicker];
        [documentPicker sendEmailWithFileWrapper:fileWrapper forExportType:exportType];
    }
}

- (void)_foreground_emailExportOfType:(NSString *)exportType;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    @autoreleasepool {
        if (OFISNULL(exportType)) {
            // The fileType being null means that the user selected the OO3 file. This does not require a conversion.
            [self.navigationController dismissViewControllerAnimated:YES completion:nil];
            [[[OUIDocumentAppController controller] documentPicker] emailDocument:nil];
            return;
        }
        
        OUIDocumentPicker *documentPicker = [[OUIDocumentAppController controller] documentPicker];
        OFSDocumentStoreFileItem *fileItem = documentPicker.singleSelectedFileItem;
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

#pragma mark - UIDocumentInteractionControllerDelegate

- (void)documentInteractionController:(UIDocumentInteractionController *)controller willBeginSendingToApplication:(NSString *)application;
{
    [self dismissViewControllerAnimated:NO completion:nil];
}

@end
