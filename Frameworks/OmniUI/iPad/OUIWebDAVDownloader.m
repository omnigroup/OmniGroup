// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIWebDAVDownloader.h"

#import <OmniUI/OUIAppController.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniUI/OUIDocumentPicker.h>
#import "OUIWebDAVConnection.h"
#import <MobileCoreServices/MobileCoreServices.h>

RCS_ID("$Id$")

@interface OUIWebDAVDownloader (/*private*/)
- (void)_cleanup;
- (NSString *)_downloadLocation;
- (NSString *)_unarchiveFileAtPath:(NSString *)filePathWithArchiveExtension error:(NSError **)error;
@end

NSString * const OUIWebDAVDownloadFinishedNotification = @"OUIWebDAVDownloadFinishedNotification";
NSString * const OUIWebDAVDownloadURL = @"OUIWebDAVDownloadURL";
NSString * const OUIWebDAVDownloadCanceledNotification = @"OUIWebDAVDownloadCanceledNotification";

@implementation OUIWebDAVDownloader

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUIWebDAVDownloader" bundle:OMNI_BUNDLE];
}

- (void)dealloc;
{
    [_downloadOperation release];
    [_uploadOperation release];
    [_downloadStream release];
    [_file release];
    [_baseURL release];
    [_fileQueue release];
    
    [super dealloc];
}
- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    progressView.progress = 0;

    UIImage *backgroundImage = [[UIImage imageNamed:@"OUIToggleButtonSelected.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
    [cancelButton setBackgroundImage:backgroundImage forState:UIControlStateNormal];
    [cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") forState:UIControlStateNormal];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    progressView.progress = 0;
}

- (void)readAndQueueContentsOfDirectory:(OFSFileInfo *)aDirectory;
{
    NSError *outError = nil;
    OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:[aDirectory originalURL] error:&outError] autorelease];
    if (outError) {
        OUI_PRESENT_ALERT(outError);
        [self cancelDownload:nil];
        return;
    }
    
    NSArray *fileInfos = [fileManager directoryContentsAtURL:[aDirectory originalURL] havingExtension:nil options:OFSDirectoryEnumerationForceRecusiveDirectoryRead error:&outError];
    if (outError) {
        OUI_PRESENT_ALERT(outError);
        [self cancelDownload:nil];
        return;
    }
    
    [_fileQueue release];
    _fileQueue = [[NSMutableArray alloc] initWithArray:fileInfos];
}

- (void)downloadFile:(OFSFileInfo *)aFile;
{    
    [_file release];
    _file = [aFile retain];
    
    NSError *error = nil;
    OFSFileManager *fileManager = [[OFSFileManager alloc] initWithBaseURL:[aFile originalURL] error:&error];
    if (!fileManager || error) {
        OUI_PRESENT_ERROR(error);
        [self cancelDownload:nil];
        [fileManager release];
        return;
    }
    
    NSString *localFilePath = [self _downloadLocation];
    NSString *localFileDirectory = [localFilePath stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:localFileDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        OUI_PRESENT_ALERT(error);
        [self cancelDownload:nil];
        [fileManager release];
        return;
    }
     
    [_downloadStream release];
    _downloadStream = [[NSOutputStream alloc] initToFileAtPath:localFilePath append:NO];
    [_downloadStream open];
    
    _downloadOperation = [[fileManager asynchronousReadContentsOfURL:[aFile originalURL] withTarget:self] retain];
    [_downloadOperation startOperation];
    
    [fileManager release];
}

- (void)download:(OFSFileInfo *)aFile;
{
    [_baseURL release];
    _baseURL = nil;
    [_fileQueue release];
    _fileQueue = nil;
    
    if ([aFile isDirectory]) {
        _baseURL = [[aFile originalURL] retain];
        
        [self readAndQueueContentsOfDirectory:aFile];
        
        OBASSERT([_fileQueue count]);
        for (OFSFileInfo *nextFile in _fileQueue)
            _totalDataLength += nextFile.size;
        
        OFSFileInfo *firstFile = [_fileQueue lastObject];
        [self downloadFile:firstFile];
        [_fileQueue removeObjectIdenticalTo:firstFile];
    } else {
        _totalDataLength = [aFile size];
        [self downloadFile:aFile];
    } 
}

- (IBAction)cancelDownload:(id)sender;
{
    if (_downloadOperation) {
        [_downloadStream close];
        [_downloadOperation stopOperation];
    } else if (_uploadOperation) {
        [_uploadOperation stopOperation];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIWebDAVDownloadCanceledNotification object:self];
}

- (void)upload:(NSData *)data toURL:(NSURL *)fileURL;
{
    _totalDataLength = [data length];
    
    _uploadOperation = [[[[OUIWebDAVConnection sharedConnection] fileManager] asynchronousWriteData:data toURL:fileURL atomically:NO withTarget:self] retain];
    [_uploadOperation startOperation];
}

#pragma mark -
#pragma mark OFSFileManagerAsynchronousOperationTarget

- (void)fileManager:(OFSFileManager *)fsFileManager operation:(id <OFSAsynchronousOperation>)operation didReceiveData:(NSData *)data;
{    
    OBPRECONDITION(operation == _downloadOperation);
    
    progressView.progress = (double)operation.processedLength/(double)_totalDataLength;
    
    if ([_downloadStream write:[data bytes] maxLength:[data length]] == -1) {
        OUI_PRESENT_ERROR([_downloadStream streamError]);
        [self _cleanup];
        return;
    }
}

- (void)fileManager:(OFSFileManager *)fileManager operation:(id <OFSAsynchronousOperation>)operation didProcessBytes:(long long)processedBytes;
{    
    OBPRECONDITION(operation == _uploadOperation);
    
    progressView.progress = (double)operation.processedLength/(double)_totalDataLength;
}

- (void)fileManager:(OFSFileManager *)fileManager operationDidFinish:(id <OFSAsynchronousOperation>)operation withError:(NSError *)error;
{
    if (error) {
        OUI_PRESENT_ERROR(error);
        
        [self _cleanup];
        return;
    }
    
    [_downloadStream close];
    
    if ([_fileQueue count]) {
        OFSFileInfo *firstFile = [_fileQueue lastObject];
        [self downloadFile:firstFile];
        [_fileQueue removeObjectIdenticalTo:firstFile];
    } else {
        NSString *fileName = (_baseURL ? [[_baseURL path] lastPathComponent] : [_file name]);
        NSString *localFile = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
        CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[fileName pathExtension], NULL);
        if (UTTypeConformsTo(fileUTI, kUTTypeArchive)) {
            NSError *unarchiveError = nil;
            localFile = [self _unarchiveFileAtPath:localFile error:&unarchiveError];
            if (!localFile || unarchiveError)
                OUI_PRESENT_ERROR(unarchiveError);
        }
        if (fileUTI)
            CFRelease(fileUTI);
        
        if (localFile) {
            [cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Finished", @"OmniUI", OMNI_BUNDLE, @"finished") forState:UIControlStateNormal];
            UIImage *backgroundImage = [[UIImage imageNamed:@"OUIExportFinishedBadge.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
            [cancelButton setBackgroundImage:backgroundImage forState:UIControlStateNormal];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIWebDAVDownloadFinishedNotification object:self userInfo:[NSDictionary dictionaryWithObject:[NSURL fileURLWithPath:localFile] forKey:OUIWebDAVDownloadURL]];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIWebDAVDownloadCanceledNotification object:self];
        }
        
        [self _cleanup];
    }
}

#pragma mark -
#pragma mark Private

- (void)_cleanup;
{
    [_downloadOperation release];
    _downloadOperation = nil;
    [_uploadOperation release];
    _uploadOperation = nil;
    
    [_downloadStream close];
    [_downloadStream release];
    _downloadStream = nil;
    [_file release];
    _file = nil;
    [_baseURL release];
    _baseURL = nil;
    [_fileQueue release];
    _fileQueue = nil;
}

- (NSString *)_downloadLocation;
{
    NSString *fileLocalRelativePath = nil;
    if (_baseURL) {
        NSURL *fileURL = [_file originalURL];
        fileLocalRelativePath = [[fileURL path] stringByRemovingString:[_baseURL path]]; 
        
        NSString *localBase = [NSTemporaryDirectory() stringByAppendingPathComponent:[[_baseURL path] lastPathComponent]];
        return [localBase stringByAppendingPathComponent:fileLocalRelativePath];
    } else {
        NSString *localBase = [NSTemporaryDirectory() stringByAppendingPathComponent:[_file name]];
        return localBase;
    }
}

- (NSString *)_unarchiveFileAtPath:(NSString *)filePathWithArchiveExtension error:(NSError **)error;
{
    NSString *unarchivedFolder = [filePathWithArchiveExtension stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    OUUnzipArchive *archive = [[[OUUnzipArchive alloc] initWithPath:filePathWithArchiveExtension error:error] autorelease];
    if (!archive)
        return nil;
    
    NSString *unarchivedFilePath = nil;
    for (OUUnzipEntry *entry in [archive entries]) {
        if ([[entry name] hasPrefix:@"__MACOSX/"])
            continue; // Skip over any __MACOSX metadata (resource forks, etc.)
        
        NSArray *subEntries = [archive entriesWithNamePrefix:[entry name]];
        if ([subEntries count] > 1)
            continue;
        
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        BOOL didWrite = NO;
        NSData *uncompressed = [archive dataForEntry:entry error:error];
        
        if (uncompressed) {
            NSArray *pathComponents = [[entry name] pathComponents];
            if (pathComponents && [pathComponents count]) {
                NSString *base = [pathComponents objectAtIndex:0];
                if (!unarchivedFilePath)
                    unarchivedFilePath = [[unarchivedFolder stringByAppendingPathComponent:base] retain];
                
                // not currently able to handle a zip file with more than one flat or one package file, so will end up returning the first entry unzipped
                OBASSERT([[unarchivedFolder stringByAppendingPathComponent:base] isEqualToString:unarchivedFilePath]);
            }
            
            NSString *entryPath = [unarchivedFolder stringByAppendingPathComponent:[entry name]];
            if ([fileManager createPathToFile:entryPath attributes:nil error:error])
                didWrite = [uncompressed writeToFile:entryPath options:0 error:error];
        }
        
        if (!didWrite)
            [*error retain];
        
        [pool release];
        
        if (!didWrite) {
            OBASSERT(error);
            [*error autorelease];
            break;
        }
    }
    
    return [unarchivedFilePath autorelease];
}

@end
