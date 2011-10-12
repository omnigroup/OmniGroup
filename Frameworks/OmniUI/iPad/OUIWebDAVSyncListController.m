// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVSyncListController.h"

#import <OmniFileStore/OFSFileManager.h>
#import <OmniUI/OUIAppController.h>
#import <OmniFileStore/OFSFileInfo.h>

#import "OUIWebDAVConnection.h"
#import "OUIWebDAVSyncDownloader.h"

RCS_ID("$Id$");

@implementation OUIWebDAVSyncListController

#pragma mark -
#pragma mark API

- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
{
    self.downloader = [[[OUIWebDAVSyncDownloader alloc] init] autorelease];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadFinished:) name:OUISyncDownloadFinishedNotification object:self.downloader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadCanceled:) name:OUISyncDownloadCanceledNotification object:self.downloader];
    
    cell.accessoryView = self.downloader.view;
    
    [self.downloader uploadFileWrapper:self.exportFileWrapper toURL:exportURL];
}

- (void)downloadFinished:(NSNotification *)notification;
{
    [super downloadFinished:notification];
    
    [[OUIWebDAVConnection sharedConnection] close];
}

- (void)export:(id)sender;
{
    OBASSERT(self.exportFileWrapper != nil);
    
    OFSFileManager *fileManager = [[OUIWebDAVConnection sharedConnection] fileManager];
    if (!fileManager) {
        return;
    }
    
    self.navigationItem.rightBarButtonItem.enabled = NO; /* 'Copy' button */
    
    NSURL *directoryURL = (self.address != nil) ? self.address : [fileManager baseURL];
    NSURL *fileURL = nil;
    // gotta use the CF version, beacuse it allows us to specify extra character's to escape, in this case '?'
    CFStringRef tempString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef )self.exportFileWrapper.preferredFilename, NULL, CFSTR("?"), kCFStringEncodingUTF8);
    fileURL = OFSURLRelativeToDirectoryURL(directoryURL, (NSString *)tempString);
    CFRelease(tempString);
    NSError *error = nil;
    OFSFileInfo *fileCheck = [fileManager fileInfoAtURL:fileURL error:&error];
    if (!fileCheck) {
        OUI_PRESENT_ALERT(error);
        return;
    }
    
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
    
    OFSFileManager *fileManager = [[OUIWebDAVConnection sharedConnection] fileManager];
    if (!fileManager) {
        switch ([[OUIWebDAVConnection sharedConnection] validateConnection]) {
            case OUIWebDAVConnectionValid:
                fileManager = [[OUIWebDAVConnection sharedConnection] fileManager];
                break;
            case OUIWebDAVNoInternetConnection:
            case OUIWebDAVCertificateTrustIssue:
                return; // without invalidating credentials
            default:
                [self signOut:nil];
                return;
        }
    }
    
    NSURL *url = (self.address != nil) ? self.address : [fileManager baseURL];
    NSError *outError = nil;
    // TODO: would be nice if -directoryContentsAtURL was asynchronous
    NSArray *fileInfos = [fileManager directoryContentsAtURL:url havingExtension:nil options:(OFSDirectoryEnumerationSkipsSubdirectoryDescendants | OFSDirectoryEnumerationSkipsHiddenFiles) error:&outError];
    if (outError) {
        OUI_PRESENT_ALERT(outError);
        return;
    }
    
    [self setFiles:[fileInfos sortedArrayUsingSelector:@selector(compareByName:)]];
    [self _stopConnectingIndicator];
}

- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;
{
    NSURL *newURL = [[[OUIWebDAVConnection sharedConnection] fileManager] availableURL:documentURL];
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
        NSURL *subFolder = [fileInfo originalURL];
        OUIWebDAVSyncListController *subfolderController = [[OUIWebDAVSyncListController alloc] init];
        subfolderController.address = subFolder;
        subfolderController.syncType = self.syncType;
        subfolderController.exportFileWrapper = self.exportFileWrapper;
        subfolderController.isExporting = self.isExporting;
        
        [self.navigationController pushViewController:subfolderController animated:YES];
        [subfolderController release];
    } else {
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        
        self.downloader = [[[OUIWebDAVSyncDownloader alloc] init] autorelease];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadFinished:) name:OUISyncDownloadFinishedNotification object:self.downloader];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadCanceled:) name:OUISyncDownloadCanceledNotification object:self.downloader];
        
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        cell.accessoryView = self.downloader.view;
        _isDownloading = YES;
        [self.downloader download:fileInfo];
    }
}

@end
