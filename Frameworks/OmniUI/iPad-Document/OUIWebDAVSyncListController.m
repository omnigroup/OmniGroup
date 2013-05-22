// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVSyncListController.h"

#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniUI/OUIAppController.h>

#import "OUIWebDAVSyncDownloader.h"

RCS_ID("$Id$");

@interface OUIWebDAVSyncListController () <OFSFileManagerDelegate>
@end

@implementation OUIWebDAVSyncListController
{
    OFSFileManager *_fileManager;
}

- initWithServerAccount:(OFXServerAccount *)serverAccount exporting:(BOOL)exporting error:(NSError **)outError;
{
    if (!(self = [super initWithServerAccount:serverAccount exporting:exporting error:outError]))
        return nil;
    
    _fileManager = [[OFSFileManager alloc] initWithBaseURL:serverAccount.remoteBaseURL delegate:self error:outError];
    if (!_fileManager)
        return nil;
    
    return self;
}


- (void)dealloc;
{
    [_fileManager invalidate];
}

#pragma mark -
#pragma mark API

- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
{
    self.downloader = [[OUIWebDAVSyncDownloader alloc] initWithFileManager:_fileManager];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadFinished:) name:OUISyncDownloadFinishedNotification object:self.downloader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadCanceled:) name:OUISyncDownloadCanceledNotification object:self.downloader];
    
    cell.accessoryView = self.downloader.view;
    
    [self.downloader uploadFileWrapper:self.exportFileWrapper toURL:exportURL];
}

- (void)export:(id)sender;
{
    OBASSERT(self.exportFileWrapper != nil);
        
    self.navigationItem.rightBarButtonItem.enabled = NO; /* 'Copy' button */
    
    NSURL *directoryURL = (self.address != nil) ? self.address : [_fileManager baseURL];
    NSURL *fileURL = nil;
    // gotta use the CF version, beacuse it allows us to specify extra character's to escape, in this case '?'
    CFStringRef tempString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef )self.exportFileWrapper.preferredFilename, NULL, CFSTR("?"), kCFStringEncodingUTF8);
    fileURL = OFSURLRelativeToDirectoryURL(directoryURL, (__bridge NSString *)tempString);
    CFRelease(tempString);
    __autoreleasing NSError *error = nil;
    
    OBFinishPortingLater("Avoid synchronous API here");
    OFSFileInfo *fileCheck = [_fileManager fileInfoAtURL:fileURL error:&error];
    if (!fileCheck) {
        OUI_PRESENT_ALERT(error);
        return;
    }
    
    // to account for any redirecty goodness that we might've enjoyed.
    fileURL = [fileCheck originalURL];
    
    if ([fileCheck exists]) {
        [self _displayDuplicateFileAlertForFile:fileURL];
        
        return;
    }
    
    [self _exportToURL:fileURL];
}

#pragma mark -
#pragma mark Private

- (void)_loadFiles;
{
    [super _loadFiles];
    
    OBFinishPortingLater("Test changing credentials on another device"); // Used to validate the connection here; what if we add the account, change the password elsewhere and then try to use the account here?
        
    NSURL *url = (self.address != nil) ? self.address : [_fileManager baseURL];
    __autoreleasing NSError *error = nil;
    // TODO: would be nice if -directoryContentsAtURL was asynchronous
    NSArray *fileInfos = [_fileManager directoryContentsAtURL:url havingExtension:nil options:(OFSDirectoryEnumerationSkipsSubdirectoryDescendants | OFSDirectoryEnumerationSkipsHiddenFiles) error:&error];
    if (!fileInfos) {
        OUI_PRESENT_ALERT(error);
        return;
    }
    
    [self setFiles:[fileInfos sortedArrayUsingSelector:@selector(compareByName:)]];
    [self _stopConnectingIndicator];
}

- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;
{
    NSURL *newURL = [_fileManager availableURL:documentURL];
    OBASSERT(newURL);
    [self _exportToURL:newURL];
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (_isDownloading)
        return;
    
    OFSFileInfo *fileInfo = [self.files objectAtIndex:indexPath.row];
    if (![self _canOpenFile:fileInfo] && [fileInfo isDirectory]) {
        __autoreleasing NSError *error = nil;
        OUIWebDAVSyncListController *subfolderController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:self.serverAccount exporting:self.isExporting error:&error];
        if (!subfolderController) {
            OUI_PRESENT_ERROR(error);
            return;
        }
        subfolderController.title = fileInfo.name;
        subfolderController.contentSizeForViewInPopover = self.contentSizeForViewInPopover;
        subfolderController.address = fileInfo.originalURL;
        subfolderController.exportFileWrapper = self.exportFileWrapper;
        
        [self.navigationController pushViewController:subfolderController animated:YES];
    } else {
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        
        self.downloader = [[OUIWebDAVSyncDownloader alloc] initWithFileManager:_fileManager];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadFinished:) name:OUISyncDownloadFinishedNotification object:self.downloader];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadCanceled:) name:OUISyncDownloadCanceledNotification object:self.downloader];
        
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        cell.accessoryView = self.downloader.view;
        _isDownloading = YES;
        [self.downloader download:fileInfo];
    }
}

#pragma mark - OFSFileManagerDelegate

- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    return self.serverAccount.credential;
}

- (void)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBFinishPortingLater("Could get this if a server changes its certificate after we create & validate it");
}

@end
