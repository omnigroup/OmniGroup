// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsController.h"

#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniAppKit/NSFileWrapper-OAExtensions.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>

#import "OUICredentials.h"
#import "OUIExportOptionsView.h"
#import "OUIOverlayView.h"
#import "OUIWebDAVConnection.h"
#import "OUIWebDAVSetup.h"
#import "OUIWebDAVSyncListController.h"

RCS_ID("$Id$")

static NSString * const OUIExportInfoFileWrapper = @"OUIExportInfoFileWrapper";
static NSString * const OUIExportInfoExportType = @"OUIExportInfoExportType";

@interface OUIExportOptionsController (/* private */)
- (void)_checkConnection;
- (void)_setInterfaceDisabledWhileExporting:(BOOL)shouldDisable;
- (void)_foreground_disableInterfaceForExportConversion;
- (void)_foreground_enableInterfaceAfterExportConversion;
@end


@implementation OUIExportOptionsController

@synthesize documentInteractionController = _documentInteractionController;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIExportOptions" bundle:OMNI_BUNDLE];
}

- (id)initWithExportType:(OUIExportOptionsType)exportType;
{
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    
    _exportType = exportType;
    
    return self;
}

- (void)dealloc;
{
    _documentInteractionController.delegate = nil;
    [_documentInteractionController release];
    
    [_exportView release];
    [_exportDescriptionLabel release];
    [_exportDestinationLabel release];
    [super dealloc];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    UIImage *paneBackground = [UIImage imageNamed:@"OUIExportPane.png"];
    OBASSERT([self.view isKindOfClass:[UIImageView class]]);
    [(UIImageView *)self.view setImage:paneBackground];
    
    if (_syncType == OUIiTunesSync) {
        self.navigationItem.rightBarButtonItem = nil;
    } else if (_exportType == OUIExportOptionsExport) {
        NSString *syncButtonTitle = NSLocalizedStringFromTableInBundle(@"Sign Out", @"OmniUI", OMNI_BUNDLE, @"sign out button title");
        UIBarButtonItem *syncBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleBordered target:self action:@selector(signOut:)];
        self.navigationItem.rightBarButtonItem = syncBarButtonItem;
        [syncBarButtonItem release];
    } 
    
    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;
    [cancel release];
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Choose Format", @"OmniUI", OMNI_BUNDLE, @"export options title");
    
    OUIDocumentPicker *picker = [[OUIAppController controller] documentPicker];
    
    [_exportFileTypes release];
    _exportFileTypes = [[NSMutableArray alloc] init];
    
    OUIDocumentStoreFileItem *fileItem = picker.singleSelectedFileItem;
    
    if (_syncType != OUIiTunesSync) {
        NSURL *documentURL = fileItem.fileURL;
        NSString *documentExtension = [[documentURL path] pathExtension];
        NSString *fileUTI = [OFSFileInfo UTIForURL:documentURL];
        UIImage *iconImage = [picker exportIconForUTI:fileUTI];
        
        NSString *nativeFileTypeLabel = [picker exportLabelForUTI:fileUTI];
        if (nativeFileTypeLabel == nil)
            nativeFileTypeLabel = documentExtension;
        
        // NOTE: Adding the native type first with a null (instead of a its non-null actual type) is important for doing exports of documents exactly as they are instead of going through the exporter. Ideally both cases would be the same, but in OO/iPad the OO3 "export" path (as opposed to normal "save") has the ability to strip hidden columns, sort sorts, calculate summary values and so on for the benefit of the XSL-based exporters. If we want "export" to the OO file format to not perform these transformations, we'll need to add flags on the OOXSLPlugin to say whether the target wants them pre-applied or not.
        [_exportFileTypes addObject:[NSNull null]];
        [_exportView addChoiceWithImage:iconImage label:nativeFileTypeLabel target:self selector:@selector(_performActionForExportOptionButton:)];
    }
    
    NSArray *exportTypes = nil;
    if (_exportType == OUIExportOptionsSendToApp) {
        exportTypes = [picker availableDocumentInteractionExportTypesForFileItem:fileItem];
    }
    else {
        exportTypes = [picker availableExportTypesForFileItem:fileItem];
    }
    
    for (NSString *exportType in exportTypes) {
        UIImage *iconImage = [picker exportIconForUTI:exportType];
        [_exportFileTypes addObject:exportType];
        [_exportView addChoiceWithImage:iconImage label:[picker exportLabelForUTI:exportType] target:self selector:@selector(_performActionForExportOptionButton:)];
    }
    
    [_exportView layoutSubviews];
}

- (void)viewDidUnload;
{
    [_exportView release];
    _exportView = nil;
    [_exportDescriptionLabel release];
    _exportDescriptionLabel = nil;
    [_exportDestinationLabel release];
    _exportDestinationLabel = nil;
    
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    OUIDocumentPicker *picker = [[OUIAppController controller] documentPicker];
    OUIDocumentStoreFileItem *fileItem = picker.singleSelectedFileItem;
    OBASSERT(fileItem != nil);
    NSString *docName = fileItem.name;
    
    NSString *actionDescription = nil;
    if (_exportType == OUIExportOptionsEmail) {
        self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUI", OMNI_BUNDLE, @"export options title");
        
        _exportDestinationLabel.text = nil;
        
        actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choose a format for emailing \"%@\":", @"OmniUI", OMNI_BUNDLE, @"email action description"), docName, nil];
    }
    else if (_exportType == OUIExportOptionsSendToApp) {
        _exportDestinationLabel.text = nil;
        
        actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Send \"%@\" to app as:", @"OmniUI", OMNI_BUNDLE, @"send to app description"), docName, nil];
    }
    else if (_exportType == OUIExportOptionsExport) {
        if (_syncType == OUIiTunesSync)
            _exportDestinationLabel.text = nil;
        else {
            NSString *addressString = [[[OUIWebDAVConnection sharedConnection] address] absoluteString];
            _exportDestinationLabel.text = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Server address: %@", @"OmniUI", OMNI_BUNDLE, @"email action description"), addressString, nil];
        }
        
        NSString *syncTypeString = nil;
        switch (_syncType) {
            case OUIiTunesSync:
                syncTypeString = NSLocalizedStringFromTableInBundle(@"iTunes", @"OmniUI", OMNI_BUNDLE, @"iTunes");
                break;
            case OUIMobileMeSync:
                syncTypeString = NSLocalizedStringFromTableInBundle(@"MobileMe", @"OmniUI", OMNI_BUNDLE, @"MobileMe");
                break;
            case OUIOmniSync:
                syncTypeString = NSLocalizedStringFromTableInBundle(@"Omni Sync", @"OmniUI", OMNI_BUNDLE, @"Omni Sync");
                break;
            case OUIWebDAVSync:
                syncTypeString = NSLocalizedStringFromTableInBundle(@"WebDAV", @"OmniUI", OMNI_BUNDLE, @"WebDAV");
                break;
            default:
                break;
        }
        
        actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Export \"%@\" to %@ as:", @"OmniUI", OMNI_BUNDLE, @"export action description"), docName, syncTypeString, nil];
    }
    
    _exportDescriptionLabel.text = actionDescription;
    
    _rectForExportOptionButtonChosen = CGRectZero;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_checkConnection) name:OUICertificateTrustUpdated object:nil];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];

    [self _checkConnection];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUICertificateTrustUpdated object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    // Overriden to allow any orientation.
    return YES;
}

- (void)didReceiveMemoryWarning;
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc. that aren't in use.
}

#pragma mark api
- (IBAction)cancel:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
    [[OUIWebDAVConnection sharedConnection] close];
}

- (void)signOut:(id)sender;
{
    OUIDeleteCredentialsForProtectionSpace([[[OUIWebDAVConnection sharedConnection] authenticationChallenge] protectionSpace]);
    [[OUIWebDAVConnection sharedConnection] close];
    
    switch (_syncType) {
        case OUIWebDAVSync:
            [[OFPreference preferenceForKey:OUIWebDAVLocation] restoreDefaultValue];
            [[OFPreference preferenceForKey:OUIWebDAVUsername] restoreDefaultValue];
            break;
        case OUIMobileMeSync:
        {
            [[OFPreference preferenceForKey:OUIMobileMeUsername] restoreDefaultValue];
            break;
        }
            
        case OUIOmniSync:
        {
            [[OFPreference preferenceForKey:OUIOmniSyncUsername] restoreDefaultValue];
            break;
        }
            
        default:
            break;
    }
    
    OUIWebDAVSetup *setupView = [[OUIWebDAVSetup alloc] init];
    [setupView setSyncType:_syncType];
    [setupView setIsExporting:YES];
    
    [self.navigationController dismissModalViewControllerAnimated:YES];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:setupView];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    OUIAppController *appController = [OUIAppController controller];
    [appController.topViewController presentModalViewController:navigationController animated:YES];
    
    [navigationController release];
    
    [setupView release];
}

- (void)_foreground_exportFileWrapper:(NSFileWrapper *)fileWrapper;
{
    OBASSERT([NSThread isMainThread]);
    
    if (_exportType != OUIExportOptionsSendToApp) {
        [self exportFileWrapper:fileWrapper];
        return;
    }
    
    // Write to temp folder (need URL of file on disk to pass off to Doc Interaction.)
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *fullTempPath = [temporaryDirectory stringByAppendingPathComponent:[fileWrapper preferredFilename]];
    NSURL *tempURL = [NSURL fileURLWithPath:fullTempPath isDirectory:[fileWrapper isDirectory]];
    
    // Get a FileManager for our Temp Directory.
    NSError *error = nil;
    OFSFileManager *tempFileManager = [[[OFSFileManager alloc] initWithBaseURL:tempURL error:&error] autorelease];
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
    
    [self _foreground_enableInterfaceAfterExportConversion];
    
    // By now we have written the project out to a temp dir. Time to handoff to Doc Interaction.
    self.documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:tempURL];
    self.documentInteractionController.delegate = self;
    [self.documentInteractionController presentOpenInMenuFromRect:_rectForExportOptionButtonChosen inView:_exportView animated:YES];
}

- (void)_background_exportDocumentOfType:(NSString *)fileType;
{
    OMNI_POOL_START {
        // OBASSERT(![NSThread isMainThread]); 
        // Sometimes not run in the background in graffle because graffle's drawing is not thread safe
        
        OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
        OUIDocumentStoreFileItem *fileItem = documentPicker.singleSelectedFileItem;
        if (!fileItem) {
            OBASSERT_NOT_REACHED("no selected document");
            [self performSelectorOnMainThread:@selector(_foreground_enableInterfaceAfterExportConversion) withObject:nil waitUntilDone:YES];
            return;
        }
        
        NSError *error = nil;
        NSFileWrapper *fileWrapper;
        
        // Using a block here so that we can easily execute the same code no matter how we get the fileWrapper below.
        void (^handler)(NSFileWrapper *fileWrapper, NSError *error) = ^(NSFileWrapper *fileWrapper, NSError *error) {
            // Need to make sure all of this happens on the mail thread.
            main_async(^{
                if (fileWrapper == nil) {
                    OUI_PRESENT_ERROR(error);
                    [self _foreground_enableInterfaceAfterExportConversion];
                } else {
                    [self _foreground_exportFileWrapper:fileWrapper];
                }
            });
        };
        
        if (OFISNULL(fileType)) {
            // The 'nil' type is always first in our list of types, so we can eport the original file as is w/o going through any app specific exporter.
            // NOTE: This is important for OO3 where the exporter has the ability to rewrite the document w/o hidden columns, in sorted order, with summary values (and eventually maybe with filtering). If we want to support untransformed exporting through the OO XML exporter, it will need to be configurable via settings on the OOXSLPlugin it uses. For now it assumes all 'exports' want all the transformations.
            fileWrapper = [[[NSFileWrapper alloc] initWithURL:fileItem.fileURL options:0 error:&error] autorelease];
            if (handler) {
                handler(fileWrapper, error);
            }
        } else {
            [documentPicker exportFileWrapperOfType:fileType forFileItem:fileItem withCompletionHandler:handler];
        }
    } OMNI_POOL_END;
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
        
        UIActivityIndicatorView *fileConversionActivityIndicator = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge] autorelease];
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
        [_fileConversionOverlayView release], _fileConversionOverlayView = nil;
    }
}

- (void)_foreground_disableInterfaceForExportConversion;
{
    OBASSERT([NSThread isMainThread]);
    [self _setInterfaceDisabledWhileExporting:YES];
}
- (void)_foreground_enableInterfaceAfterExportConversion;
{
    OBASSERT([NSThread isMainThread]);
    [self _setInterfaceDisabledWhileExporting:NO];
}

- (void)_beginBackgroundExportDocumentOfType:(NSString *)fileType;
{
    [self _foreground_disableInterfaceForExportConversion];
    
    OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
    if ([documentPicker isExportThreadSafe])
        [self performSelectorInBackground:@selector(_background_exportDocumentOfType:) withObject:fileType];
    else
        [self _background_exportDocumentOfType:fileType];
}

- (void)_foreground_finishBackgroundEmailExportWithInfo:(NSDictionary *)info;
{
    OBASSERT([NSThread isMainThread]);
    [self performSelectorOnMainThread:@selector(_foreground_enableInterfaceAfterExportConversion) withObject:nil waitUntilDone:YES];
    
    NSString *exportType = [info objectForKey:OUIExportInfoExportType];
    NSFileWrapper *fileWrapper = [info objectForKey:OUIExportInfoFileWrapper];
    
    if (fileWrapper) {
        [self.navigationController dismissModalViewControllerAnimated:YES];
        OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
        [documentPicker sendEmailWithFileWrapper:fileWrapper forExportType:exportType];
    }
}

- (void)_background_emailExportOfType:(NSString *)exportType;
{
    OMNI_POOL_START {
        if (OFISNULL(exportType)) {
            // The fileType being null means that the user selected the OO3 file. This does not require a conversion.
            main_async(^{
                [self.navigationController dismissModalViewControllerAnimated:YES];
                [[[OUIAppController controller] documentPicker] emailDocument:nil];
            });
            return;
        }
        
        OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
        OUIDocumentStoreFileItem *fileItem = documentPicker.singleSelectedFileItem;
        if (!fileItem) {
            OBASSERT_NOT_REACHED("no selected document");
            [self performSelectorOnMainThread:@selector(_foreground_enableInterfaceAfterExportConversion) withObject:nil waitUntilDone:YES];
            return;
        }
        
        [documentPicker exportFileWrapperOfType:exportType forFileItem:fileItem withCompletionHandler:^(NSFileWrapper *fileWrapper, NSError *error) {
            if (fileWrapper == nil) {
                OUI_PRESENT_ERROR(error);
                [self performSelectorOnMainThread:@selector(_foreground_enableInterfaceAfterExportConversion) withObject:nil waitUntilDone:YES];
            }
            else {
                [self performSelectorOnMainThread:@selector(_foreground_finishBackgroundEmailExportWithInfo:) 
                                       withObject:[NSDictionary dictionaryWithObjectsAndKeys:exportType, OUIExportInfoExportType,
                                                   fileWrapper, OUIExportInfoFileWrapper,
                                                   nil]
                                    waitUntilDone:YES];
            }
        }];
    } OMNI_POOL_END;
}

- (void)_performActionForExportOptionButton:(UIButton *)sender;
{
    OBPRECONDITION([sender isKindOfClass:[UIButton class]]);
    OBPRECONDITION(sender.tag >= 0 && sender.tag < (signed)_exportFileTypes.count);
    
    _rectForExportOptionButtonChosen = sender.frame;
    NSString *fileType = [_exportFileTypes objectAtIndex:sender.tag];
    
    if (_exportType == OUIExportOptionsEmail) {
        [self _foreground_disableInterfaceForExportConversion];   
        OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
        if ([documentPicker isExportThreadSafe])
            [self performSelectorInBackground:@selector(_background_emailExportOfType:) withObject:fileType];
        else 
            [self _background_emailExportOfType:fileType];
    } else {
        [self _beginBackgroundExportDocumentOfType:fileType];
    }
}

- (void)exportFileWrapper:(NSFileWrapper *)fileWrapper;
{
    [self _foreground_enableInterfaceAfterExportConversion];
    
    OUIWebDAVSyncListController *syncListController = [[OUIWebDAVSyncListController alloc] init];
    [syncListController setSyncType:_syncType];
    [syncListController setIsExporting:YES];
    syncListController.exportFileWrapper = fileWrapper;
    
    [self.navigationController pushViewController:syncListController animated:YES];
    [syncListController release];
}

@synthesize exportView = _exportView;
@synthesize exportDestinationLabel = _exportDestinationLabel;
@synthesize exportDescriptionLabel = _exportDescriptionLabel;
@synthesize syncType = _syncType;

#pragma mark private
- (void)_checkConnection;
{
    if (_exportType != OUIExportOptionsExport)
        return;
    switch ([[OUIWebDAVConnection sharedConnection] validateConnection]) {
        case OUIWebDAVCertificateTrustIssue:
        case OUIWebDAVConnectionValid:
            return; // without invalidating credentials
        case OUIWebDAVNoInternetConnection: // Stop the export, but don't invalidate credentials
            [self cancel:nil];
            break;
        default:
            [self signOut:nil];
            break;
    }
}

#pragma mark -
#pragma mark UIDocumentInteractionControllerDelegate
- (void)documentInteractionController:(UIDocumentInteractionController *)controller willBeginSendingToApplication:(NSString *)application;
{
    [self dismissModalViewControllerAnimated:NO];
}

@end
