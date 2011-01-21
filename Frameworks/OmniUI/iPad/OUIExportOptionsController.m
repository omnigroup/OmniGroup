// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsController.h"

#import <OmniFileStore/OFSFileInfo.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniFoundation/OFPreference.h>

#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>

#import "OUICredentials.h"
#import "OUIExportOptionsView.h"
#import "OUIWebDAVConnection.h"
#import "OUIWebDAVController.h"
#import "OUIWebDAVSetup.h"

RCS_ID("$Id$")
    
@interface OUIExportOptionsController (/* private */)
- (void)_checkConnection;
@end


@implementation OUIExportOptionsController

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
        UIBarButtonItem *syncBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleDone target:self action:@selector(signOut:)];
        self.navigationItem.rightBarButtonItem = syncBarButtonItem;
        [syncBarButtonItem release];
    } 
    
    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;
    [cancel release];
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Choose Format", @"OmniUI", OMNI_BUNDLE, @"export options title");
    
    OUIDocumentPicker *picker = [[OUIAppController controller] documentPicker];
    BOOL addPDF = [[picker delegate] respondsToSelector:@selector(documentPicker:PDFDataForProxy:error:)];
    BOOL addPNG = [[picker delegate] respondsToSelector:@selector(documentPicker:PNGDataForProxy:error:)];
    BOOL hasCustomIcons = [[picker delegate] respondsToSelector:@selector(documentPicker:exportIconForUTI:)];
    
    NSUInteger choiceIndex = 0;
    if (_syncType != OUIiTunesSync) {
        OUIDocumentProxy *documentProxy = [picker selectedProxy];
        NSURL *documentURL = [documentProxy url];
        NSString *documentExtension = [[documentURL path] pathExtension];
        CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)documentExtension, NULL);
        
        UIImage *iconImage = nil;
        if (hasCustomIcons)
            iconImage = [[picker delegate] documentPicker:picker exportIconForUTI:fileUTI];
        if (!iconImage)
            iconImage = [UIImage imageNamed:@"OUIDocument.png"];
        
        NSString *nativeFileTypeLabel = nil;
        if ([[picker delegate] respondsToSelector:@selector(documentPicker:labelForUTI:)]) {
            nativeFileTypeLabel = [[picker delegate] documentPicker:picker labelForUTI:fileUTI];
        }
        if (!nativeFileTypeLabel) {
            nativeFileTypeLabel = [documentExtension capitalizedString];
        }
        
        [_exportView addChoiceToIndex:choiceIndex image:iconImage label:nativeFileTypeLabel target:self selector:(_exportType == OUIExportOptionsEmail) ? @selector(emailDocument:) : @selector(exportDocument:)];
        choiceIndex++;
        
        if (fileUTI)
            CFRelease(fileUTI);
    }
    
    if (addPDF) {
        UIImage *iconImage = nil;
        if (hasCustomIcons)
            iconImage = [[picker delegate] documentPicker:picker exportIconForUTI:kUTTypePDF];
        if (!iconImage)
            iconImage = [UIImage imageNamed:@"OUIPDF.png"];

        [_exportView addChoiceToIndex:choiceIndex image:iconImage label:@"PDF" target:self selector:(_exportType == OUIExportOptionsEmail) ? @selector(emailPDF:) : @selector(exportPDF:)];
        choiceIndex++;
    }
    
    if (addPNG) {
        UIImage *iconImage = nil;
        if (hasCustomIcons)
            iconImage = [[picker delegate] documentPicker:picker exportIconForUTI:kUTTypePNG];
        if (!iconImage)
            iconImage = [UIImage imageNamed:@"OUIPNG.png"];

        [_exportView addChoiceToIndex:choiceIndex image:iconImage label:@"PNG" target:self selector:(_exportType == OUIExportOptionsEmail) ? @selector(emailPNG:) : @selector(exportPNG:)];
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
    OUIDocumentPicker *picker = [[OUIAppController controller] documentPicker];
    OUIDocumentProxy *proxy = [picker selectedProxy];
    OBASSERT(proxy != nil);
    NSString *docName = [proxy name];
    
    NSString *actionDescription = nil;
    if ((_exportType == OUIExportOptionsEmail)) {
        self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUI", OMNI_BUNDLE, @"export options title");
        
        _exportDestinationLabel.text = nil;

        actionDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choose a format for emailing \"%@\":", @"OmniUI", OMNI_BUNDLE, @"email action description"), docName, nil];
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_checkConnection) name:OUICertificateTrustUpdated object:nil];
    
}

- (void)viewDidAppear:(BOOL)animated;
{
    [self _checkConnection];
}

- (void)viewDidDisappear:(BOOL)animated;
{
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

- (void)exportDocument:(id)sender;
{
    OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
    OUIDocumentProxy *documentProxy = [documentPicker selectedProxy];
    if (!documentProxy) {
        OBASSERT_NOT_REACHED("no selected document proxy");
        return;
    }
    
    [self exportData:[documentProxy emailData] toFileNamed:[OFSFileInfo nameForURL:[documentProxy url]]];
}

- (void)exportPDF:(id)sender;
{
    OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
    OUIDocumentProxy *documentProxy = [documentPicker selectedProxy];
    if (!documentProxy) {
        OBASSERT_NOT_REACHED("no selected document proxy");
        return;
    }
    
    NSError *error = nil;
    NSData *pdfData = [[documentPicker delegate] documentPicker:documentPicker PDFDataForProxy:documentProxy error:&error];
    if (!pdfData) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    NSString *docName = [OFSFileInfo nameForURL:[documentProxy url]];
    docName = [docName stringByDeletingPathExtension];
    docName = [docName stringByAppendingPathExtension:@"pdf"];
    [self exportData:pdfData toFileNamed:docName];
}

- (void)exportPNG:(id)sender;
{
    OUIDocumentPicker *documentPicker = [[OUIAppController controller] documentPicker];
    OUIDocumentProxy *documentProxy = [documentPicker selectedProxy];
    if (!documentProxy) {
        OBASSERT_NOT_REACHED("no selected document proxy");
        return;
    }
    
    NSError *error = nil;
    NSData *pngData = [[documentPicker delegate] documentPicker:documentPicker PNGDataForProxy:documentProxy error:&error];
    if (!pngData) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    NSString *docName = [OFSFileInfo nameForURL:[documentProxy url]];
    docName = [docName stringByDeletingPathExtension];
    docName = [docName stringByAppendingPathExtension:@"png"];
    [self exportData:pngData toFileNamed:docName];
}

- (void)exportData:(NSData *)data toFileNamed:(NSString *)filename;
{
    OUIWebDAVController *davController = [[OUIWebDAVController alloc] init];
    [davController setSyncType:_syncType];
    [davController setIsExporting:YES];
    [davController setExportingData:data];
    [davController setExportingFilename:filename];
    
    [self.navigationController pushViewController:davController animated:YES];
    [davController release];
}

- (void)emailDocument:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
    [[[OUIAppController controller] documentPicker] emailDocument:nil];
}

- (void)emailPDF:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
    [[[OUIAppController controller] documentPicker] emailPDF:nil];
}

- (void)emailPNG:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
    [[[OUIAppController controller] documentPicker] emailPNG:nil];
}

@synthesize exportView = _exportView;
@synthesize exportDestinationLabel = _exportDestinationLabel;
@synthesize exportDescriptionLabel = _exportDescriptionLabel;
@synthesize syncType = _syncType;

#pragma mark private
- (void)_checkConnection;
{
    if (_exportType == OUIExportOptionsExport && ![[OUIWebDAVConnection sharedConnection] validConnection]) {
        if (![[OUIWebDAVConnection sharedConnection] trustAlertVisible])
            [self signOut:nil];
    }
}

@end
