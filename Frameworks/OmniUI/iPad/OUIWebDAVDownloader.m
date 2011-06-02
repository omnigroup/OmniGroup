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
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniAppKit/NSFileWrapper-OAExtensions.h>
#import <OmniUI/OUIDocumentPicker.h>
#import "OUIWebDAVConnection.h"
#import <MobileCoreServices/MobileCoreServices.h>

RCS_ID("$Id$")

@interface OUIWebDAVDownloader (/*private*/)
- (void)_cleanupWithSuccess:(BOOL)success;
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
    [_uploadOperations release];
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

    UIImage *backgroundImage = [[UIImage imageNamed:@"OUIInspectorButton-Selected.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
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
    
    NSArray *fileInfos = [fileManager directoryContentsAtURL:[aDirectory originalURL] havingExtension:nil options:OFSDirectoryEnumerationForceRecursiveDirectoryRead error:&outError];
    if (outError) {
        OUI_PRESENT_ALERT(outError);
        [self cancelDownload:nil];
        return;
    }
    
    [_fileQueue release];
    _fileQueue = [[NSMutableArray alloc] init];
    for (OFSFileInfo *fileInfo in fileInfos)
        if (![fileInfo isDirectory])
            [_fileQueue addObject:fileInfo];
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

    OBASSERT(_downloadOperation == nil);
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
    if (_downloadOperation != nil) {
        [_downloadStream close];
        [_downloadOperation stopOperation];
    } else if (_uploadOperations != nil) {
        for (id <OFSAsynchronousOperation> uploadOperation in _uploadOperations)
            [uploadOperation stopOperation];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIWebDAVDownloadCanceledNotification object:self];
}

- (BOOL)_queueUploadFileWrapper:(OFFileWrapper *)fileWrapper atomically:(BOOL)atomically toURL:(NSURL *)targetURL usingFileManager:(OFSFileManager *)fileManager error:(NSError **)outError;
{
#ifdef DEBUG_kc
    NSLog(@"DEBUG: Queueing upload to %@", [targetURL absoluteString]);
#endif

    if ([fileWrapper isDirectory]) {
        targetURL = OFSURLWithTrailingSlash(targetURL); // RFC 2518 section 5.2 says: In general clients SHOULD use the "/" form of collection names.
        NSError *error = nil;
        if (atomically) {
            OBASSERT(_uploadTemporaryURL == nil); // Otherwise we'd need a stack of things to rename rather than just one
            OBASSERT(_uploadFinalURL == nil);

            NSString *temporaryNameSuffix = [@"-write-in-progress-" stringByAppendingString:[OFXMLCreateID() autorelease]];
            _uploadFinalURL = [targetURL retain];
            targetURL = [OFSURLWithTrailingSlash(OFSURLWithNameAffix(targetURL, temporaryNameSuffix, NO, YES)) retain];
        }
        NSURL *parentURL = [fileManager createDirectoryAtURL:targetURL attributes:nil error:&error];
        if (atomically)
            _uploadTemporaryURL = [parentURL retain];

        NSDictionary *childWrappers = [fileWrapper fileWrappers];
        for (NSString *childName in childWrappers) {
            OFFileWrapper *childWrapper = [childWrappers objectForKey:childName];
            NSURL *childURL = OFSFileURLRelativeToDirectoryURL(parentURL, childName);;
            if (![self _queueUploadFileWrapper:childWrapper atomically:NO toURL:childURL usingFileManager:fileManager error:outError])
                return NO;
        }
    } else if ([fileWrapper isRegularFile]) {
        NSData *data = [fileWrapper regularFileContents];
        _totalDataLength += [data length];
        id <OFSAsynchronousOperation> uploadOperation = [fileManager asynchronousWriteData:data toURL:targetURL atomically:NO withTarget:self];
        [_uploadOperations addObject:uploadOperation];
    } else {
        OBASSERT_NOT_REACHED("We only know how to upload files and directories; we skip symlinks and other file types");
    }
    return YES;
}

- (void)uploadFileWrapper:(OFFileWrapper *)fileWrapper toURL:(NSURL *)targetURL ;
{
    _totalDataLength = 0;
    _uploadOperations = [[NSMutableArray alloc] init];
    NSError *error = nil;
    if (![self _queueUploadFileWrapper:fileWrapper atomically:YES toURL:targetURL usingFileManager:[[OUIWebDAVConnection sharedConnection] fileManager] error:&error]) {
        OBASSERT(error != nil);
        OUI_PRESENT_ERROR(error);
        [self _cleanupWithSuccess:NO];
        return;
    }
    for (id <OFSAsynchronousOperation> uploadOperation in [NSArray arrayWithArray:_uploadOperations]) {
        [uploadOperation startOperation];
    }
}

- (void)uploadData:(NSData *)data toURL:(NSURL *)targetURL;
{
    [self uploadFileWrapper:[OFFileWrapper fileWrapperWithFilename:nil contents:data] toURL:targetURL];
}

#pragma mark -
#pragma mark OFSFileManagerAsynchronousOperationTarget

- (void)fileManager:(OFSFileManager *)fsFileManager operation:(id <OFSAsynchronousOperation>)operation didReceiveData:(NSData *)data;
{    
    OBPRECONDITION(operation == _downloadOperation);
    
    progressView.progress = (double)operation.processedLength/(double)_totalDataLength;
    
    if ([_downloadStream write:[data bytes] maxLength:[data length]] == -1) {
        OUI_PRESENT_ERROR([_downloadStream streamError]);
        [self _cleanupWithSuccess:NO];
        return;
    }
}

- (void)fileManager:(OFSFileManager *)fileManager operation:(id <OFSAsynchronousOperation>)operation didProcessBytes:(long long)processedBytes;
{    
    OBPRECONDITION(_uploadOperations == nil || [_uploadOperations containsObjectIdenticalTo:operation]);
    if (_uploadOperations == nil)
        return; // We've cancelled these uploads

    _totalUploadedBytes += processedBytes;
    progressView.progress = (double)_totalUploadedBytes/(double)_totalDataLength;
}

- (void)fileManager:(OFSFileManager *)fileManager operationDidFinish:(id <OFSAsynchronousOperation>)operation withError:(NSError *)error;
{
    // Some operation that we cancelled due to a failure in an operation before it in the queue? See <bug:///72669> (Exporting files which time out leaves you in a weird state)
    if (operation != _downloadOperation && [_uploadOperations containsObjectIdenticalTo:operation] == NO)
        return;

    if (error) {
        OUI_PRESENT_ERROR(error);
        
        [self _cleanupWithSuccess:NO];
        return;
    }
    
    if (operation == _downloadOperation) {
        // Our current download finished
        [_downloadStream close];
    
        if ([_fileQueue count] != 0) {
            [_downloadOperation release]; _downloadOperation = nil;
            OFSFileInfo *firstFile = [_fileQueue lastObject];
            [self downloadFile:firstFile];
            [_fileQueue removeObjectIdenticalTo:firstFile];
            return; // On to the next download
        }
    } else {
        // An upload finished
        OBASSERT([_uploadOperations containsObjectIdenticalTo:operation]);
        [_uploadOperations removeObjectIdenticalTo:operation];
        if ([_uploadOperations count] != 0)
            return; // Still waiting for more uploads

        // For atomic directory wrapper uploads, move our temporary URL to our final URL
        if (_uploadTemporaryURL != nil) {
            [fileManager deleteURL:_uploadFinalURL error:NULL]; // Ignore delete errors
            NSError *moveError = nil;
            if (![fileManager moveURL:_uploadTemporaryURL toURL:_uploadFinalURL error:&moveError])
                OUI_PRESENT_ERROR(moveError);

            [_uploadTemporaryURL release]; _uploadTemporaryURL = nil;
            [_uploadFinalURL release]; _uploadFinalURL = nil;
        }

        OBASSERT(_uploadTemporaryURL == nil);
        OBASSERT(_uploadFinalURL == nil);
    }

    {
        // All done!
        NSString *fileName = (_baseURL ? [[_baseURL path] lastPathComponent] : [_file name]);
        NSString *localFile = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
        NSString *fileUTI = [OFSFileInfo UTIForFilename:fileName];
        if (UTTypeConformsTo((CFStringRef)fileUTI, kUTTypeArchive)) {
            NSError *unarchiveError = nil;
            localFile = [self _unarchiveFileAtPath:localFile error:&unarchiveError];
            if (!localFile || unarchiveError)
                OUI_PRESENT_ERROR(unarchiveError);
        }
        
        if (localFile) {
            [cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Finished", @"OmniUI", OMNI_BUNDLE, @"finished") forState:UIControlStateNormal];
            UIImage *backgroundImage = [[UIImage imageNamed:@"OUIExportFinishedBadge.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
            [cancelButton setBackgroundImage:backgroundImage forState:UIControlStateNormal];
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIWebDAVDownloadFinishedNotification object:self userInfo:[NSDictionary dictionaryWithObject:[NSURL fileURLWithPath:localFile] forKey:OUIWebDAVDownloadURL]];
        }
        
        [self _cleanupWithSuccess:localFile != nil];
    }
}

#pragma mark -
#pragma mark Private

- (void)_cleanupWithSuccess:(BOOL)success;
{
    if (!success)
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIWebDAVDownloadCanceledNotification object:self];
    else if (_downloadOperation != nil || [_uploadOperations count] != 0)
        [self cancelDownload:nil];

    [_downloadOperation release];
    _downloadOperation = nil;
    [_uploadOperations release];
    _uploadOperations = nil;
    
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
