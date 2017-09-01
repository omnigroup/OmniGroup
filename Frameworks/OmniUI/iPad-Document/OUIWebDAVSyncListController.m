// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVSyncListController.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFCredentialChallengeDispositionProtocol.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUICertificateTrustAlert.h>

#import "OUIWebDAVSyncDownloader.h"

RCS_ID("$Id$");

@interface OUIWebDAVSyncListController () // <OFSFileManagerDelegate>
@end

@implementation OUIWebDAVSyncListController
{
    ODAVConnection *_connection;
    NSURLAuthenticationChallenge *_certificateChallenge;
}

- initWithServerAccount:(OFXServerAccount *)serverAccount exporting:(BOOL)exporting error:(NSError **)outError;
{
    if (!(self = [super initWithServerAccount:serverAccount exporting:exporting error:outError]))
        return nil;
    
    NSURLCredential *credentials = OFReadCredentialsForServiceIdentifier(serverAccount.credentialServiceIdentifier, outError);
    if (!credentials)
        return nil;
    
    self.navigationItem.title = serverAccount.displayName;
    ODAVConnectionConfiguration *configuration = [[ODAVConnectionConfiguration alloc] init];
    
    _connection = [[ODAVConnection alloc] initWithSessionConfiguration:configuration baseURL:serverAccount.remoteBaseURL];
    
    __weak OUIWebDAVSyncListController *weakSelf = self;
    _connection.validateCertificateForChallenge = ^NSURLCredential *(NSURLAuthenticationChallenge *challenge){
        OUIWebDAVSyncListController *strongSelf = weakSelf;
        if (strongSelf)
            strongSelf->_certificateChallenge = challenge;
        return nil;
    };
    
    _connection.findCredentialsForChallenge = ^NSOperation <OFCredentialChallengeDisposition> *(NSURLAuthenticationChallenge *challenge){
        if ([challenge previousFailureCount] < 2)
            return OFImmediateCredentialResponse(NSURLSessionAuthChallengeUseCredential, credentials);
        return OFImmediateCredentialResponse(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    };
    
    return self;
}

#pragma mark - API

- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
{
    self.downloader = [[OUIWebDAVSyncDownloader alloc] initWithConnection:_connection];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadFinished:) name:OUISyncDownloadFinishedNotification object:self.downloader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadCanceled:) name:OUISyncDownloadCanceledNotification object:self.downloader];
    
    cell.accessoryView = self.downloader.view;
    
    [self.downloader uploadFileWrapper:self.exportFileWrapper toURL:exportURL];
}

- (void)export:(id)sender;
{
    OBASSERT(self.exportFileWrapper != nil);
        
    self.navigationItem.rightBarButtonItem.enabled = NO; /* 'Copy' button */
    
    NSURL *directoryURL = self.address ?: self.serverAccount.remoteBaseURL;
    NSURL *fileURL = nil;
    
    OBFinishPortingLater("Why are we doing this instead of using the URL path utilities? - <bug:///147826> (iOS-OmniOutliner Unassigned: OUIWebDavSyncListController.m:86: use URL path utilities)");
    NSMutableCharacterSet *allowedChars = [NSMutableCharacterSet characterSetWithCharactersInString:@"?"];
    [allowedChars formUnionWithCharacterSet:[NSCharacterSet URLPathAllowedCharacterSet]];

    NSString *tempString = [self.exportFileWrapper.preferredFilename stringByAddingPercentEncodingWithAllowedCharacters:allowedChars];
    fileURL = OFURLRelativeToDirectoryURL(directoryURL, tempString);

    [_connection fileInfoAtURL:fileURL ETag:nil completionHandler:^(ODAVSingleFileInfoResult *result, NSError *error) {
        if (!self.parentViewController)
            return; // Cancelled
        
        if (!result) {
            OUI_PRESENT_ALERT_FROM(error, self);
            return;
        }
        
        ODAVFileInfo *fileInfo = result.fileInfo;
        NSURL *redirectedURL = fileInfo.originalURL;
        if (fileInfo.exists) {
            [self _displayDuplicateFileAlertForFile:redirectedURL];
            return;
        }
        
        [self _exportToURL:redirectedURL];
    }];
}

#pragma mark -
#pragma mark Private

- (void)_loadFiles;
{
    [super _loadFiles];
    
    OBFinishPortingLater("<bug:///147801> (iOS-OmniOutliner Engineering: OUIWebDAVSyncListController - Test changing credentials on another device (OBFinishPortingLater))"); // Used to validate the connection here; what if we add the account, change the password elsewhere and then try to use the account here?
        
    NSURL *url = self.address ?: self.serverAccount.remoteBaseURL;
    
    [_connection directoryContentsAtURL:url withETag:nil completionHandler:^(ODAVMultipleFileInfoResult *properties, NSError *errorOrNil) {
        if (!self.parentViewController)
            return; // Cancelled
        
        if (!properties) {
            if (_certificateChallenge) {
                NSURLAuthenticationChallenge *challenge = _certificateChallenge;
                _certificateChallenge =  nil;
                
                OUICertificateTrustAlert *certAlert = [[OUICertificateTrustAlert alloc] initForChallenge:challenge];
                certAlert.shouldOfferTrustAlwaysOption = YES;
                certAlert.trustBlock = ^(OFCertificateTrustDuration trustDuration) {
                    // Our superclass will reload its list of files when this happens, due to OFCertificateTrustUpdatedNotification being posted.
                    OFAddTrustForChallenge(challenge, trustDuration);
                };
                certAlert.cancelBlock = ^{
                    [self cancel:nil];
                };
                [certAlert findViewController:^{ return self; }];
                [[[OUIAppController sharedController] backgroundPromptQueue] addOperation:certAlert];
            } else {
                OUI_PRESENT_ALERT_FROM(errorOrNil, self);
            }
            return;
        }
        
        NSArray *files = [properties.fileInfos select:^BOOL(ODAVFileInfo *fileInfo) {
            return [fileInfo.name hasPrefix:@"."] == NO;
        }];
        
        [self setFiles:[files sortedArrayUsingSelector:@selector(compareByName:)]];
        [self _stopConnectingIndicator];
    }];
}

- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;
{
    [_connection directoryContentsAtURL:[documentURL URLByDeletingLastPathComponent] withETag:nil completionHandler:^(ODAVMultipleFileInfoResult *properties, NSError *errorOrNil) {
        if (!self.parentViewController)
            return; // Cancelled
        
        if (!properties) {
            OUI_PRESENT_ALERT_FROM(errorOrNil, self);
            return;
        }
            
        NSURL *url = [ODAVFileInfo availableURL:documentURL avoidingFileInfos:properties.fileInfos];
        OBASSERT(url);
        [self _exportToURL:url];
    }];
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (_isDownloading)
        return;
    
    ODAVFileInfo *fileInfo = [self.files objectAtIndex:indexPath.row];
    if (![self _canOpenFile:fileInfo] && [fileInfo isDirectory]) {
        __autoreleasing NSError *error = nil;
        OUIWebDAVSyncListController *subfolderController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:self.serverAccount exporting:self.isExporting error:&error];
        if (!subfolderController) {
            OUI_PRESENT_ERROR_FROM(error, self);
            return;
        }
        subfolderController.title = fileInfo.name;
        subfolderController.preferredContentSize = self.preferredContentSize;
        subfolderController.address = fileInfo.originalURL;
        subfolderController.exportFileWrapper = self.exportFileWrapper;
        
        [self.navigationController pushViewController:subfolderController animated:YES];
    } else {
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        
        self.downloader = [[OUIWebDAVSyncDownloader alloc] initWithConnection:_connection];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadFinished:) name:OUISyncDownloadFinishedNotification object:self.downloader];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadCanceled:) name:OUISyncDownloadCanceledNotification object:self.downloader];
        
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        cell.accessoryView = self.downloader.view;
        _isDownloading = YES;
        [self.downloader download:fileInfo];
    }
}

@end
