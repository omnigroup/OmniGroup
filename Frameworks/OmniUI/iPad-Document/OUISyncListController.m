// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISyncListController.h"

#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSFileItem.h>

#import "OUISyncDownloader.h"

RCS_ID("$Id$");

@implementation OUISyncListController
{
    /* these are used when the download is delayed in order to scroll the view to the visible */
    NSURL *_exportURL;
    NSIndexPath *_exportIndexPath;
    
    OUIReplaceDocumentAlert *_replaceDocumentAlert;
}

- initWithServerAccount:(OFXServerAccount *)serverAccount exporting:(BOOL)exporting error:(NSError **)outError;
{
    if (!(self = [super init]))
        return nil;
    
    _serverAccount = serverAccount;
    _isExporting = exporting;
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@synthesize connectingView = _connectingView;
@synthesize connectingProgress = _connectingProgress;
@synthesize connectingLabel = _connectingLabel;

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    // Build Connecting View
    _connectingView = [[UIView alloc] initWithFrame:(CGRect){ 
        .origin.x = 0, 
        .origin.y = 0,
        .size.width = 160,
        .size.height = 32
    }];
    
    _connectingProgress = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _connectingProgress.frame = (CGRect){
        .origin.x = 2,
        .origin.y = 6,
        .size.width = _connectingProgress.frame.size.width,
        .size.height = _connectingProgress.frame.size.height
    };
    [_connectingView addSubview:_connectingProgress];
    
    _connectingLabel = [[UILabel alloc] initWithFrame:(CGRect){
        .origin.x = 28,
        .origin.y = 0,
        .size.width = 132,
        .size.height = 32
    }];
    _connectingLabel.backgroundColor = [UIColor clearColor];
    _connectingLabel.font = [UIFont systemFontOfSize:20.0];
    _connectingLabel.textColor = [UIColor blackColor];
    [_connectingView addSubview:_connectingLabel];
    
    [self _updateNavigationButtons];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    self.navigationItem.titleView = _connectingView;
    [_connectingProgress startAnimating];
    
    _connectingLabel.text = NSLocalizedStringFromTableInBundle(@"Connecting", @"OmniUIDocument", OMNI_BUNDLE, @"webdav connecting label");
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_loadFiles) name:OFCertificateTrustUpdatedNotification object:nil];
    [self performSelector:@selector(_loadFiles) withObject:nil afterDelay:0];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OFCertificateTrustUpdatedNotification object:nil];
}

#pragma mark - API

- (void)export:(id)sender;
{
    // TODO: Must override in subclass.
}

- (void)cancel:(id)sender;
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)downloadFinished:(NSNotification *)notification;
{
    OUISyncDownloader *downloader = [notification object];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadFinishedNotification object:downloader];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadCanceledNotification object:downloader];
    
    NSURL *downloadURL = [[notification userInfo] objectForKey:OUISyncDownloadURL];

    [self _fadeOutDownload:downloader];

    OUIDocumentPicker *docPicker = [OUIDocumentAppController controller].documentPicker;
    OUIDocumentPickerViewController *scopeViewController = docPicker.selectedScopeViewController;
    OBASSERT(scopeViewController);
    
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        if (_isExporting) {
            _isExporting = NO;
            [scopeViewController exportedDocumentToURL:downloadURL];
        } else if (_isDownloading) {
            _isDownloading = NO;
            // instead of just copying the file we downloaded into the current scope, we need to do any converty work on it we intend to do (.oo3 -> .graffle for example).
            BOOL shouldConvert = NO;

            NSURL *documentToAddURL = downloadURL;
            if ([docPicker.delegate respondsToSelector:@selector(documentPickerShouldOpenButNotDisplayUTType:)] && [docPicker.delegate respondsToSelector:@selector(documentPicker:saveNewFileIfAppropriateFromFile:completionHandler:)]) {
                BOOL isDirectory = NO;
                [[NSFileManager defaultManager] fileExistsAtPath:[documentToAddURL path] isDirectory:&isDirectory];
                shouldConvert = [docPicker.delegate documentPickerShouldOpenButNotDisplayUTType:OFUTIForFileExtensionPreferringNative([downloadURL pathExtension], @(isDirectory))];

                if (shouldConvert) { // convert files we claim to view, but do not display in our doc-picker?
                    [docPicker.delegate documentPicker:docPicker saveNewFileIfAppropriateFromFile:documentToAddURL completionHandler:^(BOOL success, ODSFileItem *savedItem, ODSScope *currentScope) {
                        [docPicker.documentStore moveItems:[NSSet setWithObject:savedItem] fromScope:currentScope toScope:scopeViewController.selectedScope inFolder:scopeViewController.selectedScope.rootFolder completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil) {

                        }];
                    }];
                    return;
                }
            }
            [scopeViewController addDocumentFromURL:documentToAddURL];
        }
    }];
}

- (void)downloadCanceled:(NSNotification *)notification;
{
    OUISyncDownloader *downloader = [notification object];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadFinishedNotification object:downloader];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadCanceledNotification object:downloader];
    
    [self _fadeOutDownload:downloader];
    
    _isDownloading = NO;
    
    if (_isExporting) {
        self.files = nil;
        
        [self _loadFiles];
        [self _updateNavigationButtons];
    }
}

- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
{
    // Should override in subclass.
}

- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;
{
    // Should override in subclass.
}

#pragma mark - OUIReplaceDocumentAlert

- (void)replaceDocumentAlert:(OUIReplaceDocumentAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex documentURL:(NSURL *)documentURL;
{
    _replaceDocumentAlert = nil;
    
    switch (buttonIndex) {
        case 0: /* Cancel */
            self.navigationItem.rightBarButtonItem.enabled = YES;
            break;
            
        case 1: /* Replace */
        {
            [self _exportToURL:documentURL];
            break;
        }
        case 2: /* Add */
        {
            [self _exportToNewPathGeneratedFromURL:documentURL];
            break;
        }
        default:
            break;
    }
}

#pragma mark - Private

- (void)_displayDuplicateFileAlertForFile:(NSURL *)fileURL;
{
    OBASSERT(_replaceDocumentAlert == nil); // this should never happen
    _replaceDocumentAlert = [[OUIReplaceDocumentAlert alloc] initWithDelegate:self documentURL:fileURL];
    [_replaceDocumentAlert showFromViewController:self];
}

- (void)_cancelDownloadEffectDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    OBASSERT([(OB_BRIDGE id)context isKindOfClass:[UITableViewCell class]]);
    [(OB_BRIDGE UITableViewCell *)context setAccessoryView:nil];
    
    [(UITableView *)self.view reloadData];
}

- (NSString *)_formattedFileSize:(NSUInteger)sizeinBytes;
{
    NSString *formattedString = nil;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setMaximumFractionDigits:1];
    
    if (sizeinBytes < 1e3) {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ B", @"OmniUIDocument", OMNI_BUNDLE, @"bytes"), formattedNumber];
    } else if (sizeinBytes < 1e6) {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes / 1e3]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ KB", @"OmniUIDocument", OMNI_BUNDLE, @"kilobytes"), formattedNumber];
    } else if (sizeinBytes < 1e9) {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes / 1e6]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ MB", @"OmniUIDocument", OMNI_BUNDLE, @"megabytes"), formattedNumber];
    } else {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes / 1e9]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ GB", @"OmniUIDocument", OMNI_BUNDLE, @"gigabytes"), formattedNumber];
    }
    
    return formattedString;
}

- (void)_loadFiles;
{
    if (self.files) {
        [self _stopConnectingIndicator];
        return;
    }
    
    // This should be implemented in subclasses.
}

- (void)_updateNavigationButtons;
{
    UINavigationItem *navigationItem = self.navigationItem;
    OBASSERT(navigationItem);

    if (_isExporting)
        navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"export button title") style:UIBarButtonItemStylePlain target:self action:@selector(export:)];

    UINavigationController *navigationController = self.navigationController;
    NSArray *viewControllers = navigationController.viewControllers;
    NSUInteger viewIndex = [viewControllers indexOfObjectIdenticalTo:self];
    
    if (viewIndex == 0) {
        UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
        navigationItem.leftBarButtonItem = cancel;
    }
}

- (void)_fadeOutDownload:(OUISyncDownloader *)downloader;
{
    for (UITableViewCell *cell in [(UITableView *)self.view visibleCells]) {
        if (cell.accessoryView == downloader.view) {
            
            [UIView beginAnimations:@"OUIWebDAVSyncListController_cancel_download" context:(OB_BRIDGE void *)cell];
            {
                cell.accessoryView.alpha = 0;
                
                [UIView setAnimationDelegate:self];
                [UIView setAnimationDidStopSelector:@selector(_cancelDownloadEffectDidStop:finished:context:)];
            }
            [UIView commitAnimations];
            break;
        }
    }
}

- (void)_exportToURL:(NSURL *)exportURL;
{
    ODAVFileInfo *emptyFile = [[ODAVFileInfo alloc] initWithOriginalURL:exportURL name:[ODAVFileInfo nameForURL:exportURL] exists:NO directory:NO size:0 lastModifiedDate:nil];
    NSMutableArray *newFiles = [NSMutableArray arrayWithObject:emptyFile];
    [newFiles addObjectsFromArray:self.files];
    [newFiles sortUsingSelector:@selector(compareByName:)];
    self.files = newFiles;
    
    NSIndexPath *indexPathToEmptyFile = [NSIndexPath indexPathForRow:[self.files indexOfObject:emptyFile] inSection:0];
    if ([(UITableView *)self.view cellForRowAtIndexPath:indexPathToEmptyFile] != nil) {
        UITableViewCell *cell = [(UITableView *)self.view cellForRowAtIndexPath:indexPathToEmptyFile];
        [self addDownloaderWithURL:exportURL toCell:cell];
    } else {
        _exportURL = exportURL;
        
        _exportIndexPath = indexPathToEmptyFile;
        
        [(UITableView *)self.view scrollToRowAtIndexPath:_exportIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
    }
}

- (void)_stopConnectingIndicator;
{
    self.navigationItem.titleView = nil;
    _connectingProgress.hidden = YES;
}

- (void)_goBack:(id)sender;
{
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    
    if (_isExporting) {
        cell.textLabel.textColor = [UIColor blackColor];
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (_isDownloading)
        return nil;
    
    ODAVFileInfo *fileInfo = [self.files objectAtIndex:indexPath.row];
    if (![self _canOpenFile:fileInfo] && [fileInfo isDirectory])
        return indexPath;
    
    if (_isExporting)
        return nil;
    
    return [self _canOpenFile:fileInfo] ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (!_isExporting || indexPath.row != _exportIndexPath.row || _exportURL == nil)
        return;
    
    [self addDownloaderWithURL:_exportURL toCell:cell];
    
    _exportURL = nil;
    
    _exportIndexPath = nil;
}

@end
