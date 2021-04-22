// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDAVFileManager.h>

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVOperation.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/Errors.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

RCS_ID("$Id$");

OBDEPRECATED_METHOD(-DAVFileManager:findCredentialsForChallenge:);
OBDEPRECATED_METHOD(-DAVFileManager:validateCertificateForChallenge:);
OBDEPRECATED_METHOD(+DAVFileManager:findCredentialsForChallenge:);
OBDEPRECATED_METHOD(+DAVFileManager:validateCertificateForChallenge:);

@implementation OFSDAVFileManager
{
    ODAVConnection *_connection;
}

- initWithBaseURL:(NSURL *)baseURL delegate:(id <OFSFileManagerDelegate>)delegate error:(NSError **)outError;
{
    OBPRECONDITION(baseURL);

    // Good form requires that DAV file managers have a delegate for authentication and at least be able to provide credentials
    OBPRECONDITION(delegate);
    OBPRECONDITION([delegate conformsToProtocol:@protocol(OFSFileManagerDelegate)]);
    OBPRECONDITION([delegate respondsToSelector:@selector(fileManager:findCredentialsForChallenge:)]);

    if (!(self = [super initWithBaseURL:baseURL delegate:delegate error:outError]))
        return nil;
    
    if (![[[self baseURL] path] isAbsolutePath]) {
        NSString *title =  NSLocalizedStringFromTableInBundle(@"An error has occurred.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Ensure that the server address, user name, and password are correct and please try again.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        OFSError(outError, OFSBaseURLIsNotAbsolute, title, description);
        
        NSLog(@"Error: The path of the url \"%@\" is not absolute. Cannot create DAV-based file manager.", [self baseURL]);
        return nil;
    }
    
    ODAVConnectionConfiguration *configuration = [[ODAVConnectionConfiguration alloc] init];
    configuration.HTTPShouldUsePipelining = YES;
    
    if ([delegate respondsToSelector:@selector(maximumChallengeRetryCountForFileManager:)]) {
        // This is a little early to be passing `self` back into a delegate method (since we're not really done with init yet), but we've called super and have initialized all of our public properties.
        configuration.maximumChallengeRetryCount = [delegate maximumChallengeRetryCountForFileManager:self];
    }
    
    _connection = [[ODAVConnection alloc] initWithSessionConfiguration:configuration baseURL:baseURL];
    
    // Bridge the delegate methods we do have to blocks on the connection. Make sure to avoid strong references back from the connection to us or our delegate (which we assume owns us).
    if ([delegate respondsToSelector:@selector(fileManager:findCredentialsForChallenge:)]) {
        __weak OFSDAVFileManager *weakSelf = self;
        _connection.findCredentialsForChallenge = ^NSOperation <OFCredentialChallengeDisposition> *(NSURLAuthenticationChallenge *challenge){
            OFSDAVFileManager *strongSelf = weakSelf;
            if (!strongSelf)
                return nil;
            id <OFSFileManagerDelegate> blockDelegate = strongSelf.delegate;
            OBASSERT(blockDelegate, "File manager delegate deallocated while DAV connection still in use.");
            return [blockDelegate fileManager:strongSelf findCredentialsForChallenge:challenge];
        };
    }
    if ([delegate respondsToSelector:@selector(fileManager:validateCertificateForChallenge:)]) {
        __weak OFSDAVFileManager *weakSelf = self;
        _connection.validateCertificateForChallenge = ^NSURLCredential *(NSURLAuthenticationChallenge *challenge){
            OFSDAVFileManager *strongSelf = weakSelf;
            if (!strongSelf)
                return nil;
            id <OFSFileManagerDelegate> blockDelegate = strongSelf.delegate;
            OBASSERT(blockDelegate, "File manager delegate deallocated while DAV connection still in use.");
            return [blockDelegate fileManager:strongSelf validateCertificateForChallenge:challenge];
        };
    }
    return self;
}

#pragma mark OFSFileManager subclass

- (id <ODAVAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url;
{
    return [_connection asynchronousGetContentsOfURL:url];
}

- (id <ODAVAsynchronousOperation>)asynchronousReadContentsOfFile:(ODAVFileInfo *)f range:(NSString *)range;
{
    return [_connection asynchronousGetContentsOfURL:f.originalURL withETag:f.ETag range:range];
}

- (id <ODAVAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url;
{
    return [_connection asynchronousPutData:data toURL:url];
}

- (id <ODAVAsynchronousOperation>)asynchronousDeleteFile:(ODAVFileInfo *)f;
{
    OBPRECONDITION(f);
    NSURL *url = f.originalURL;
    OBPRECONDITION(url);
    return [_connection asynchronousDeleteURL:url withETag:f.ETag];
}

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    return YES;
}

// TODO: Ensure that the input urls are within the specified URL.  Either need to check this directly, or require that they are relative.

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    return [self fileInfoAtURL:url collectingRedirects:nil error:outError];
}

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirects error:(NSError **)outError;
{
    return [self fileInfoAtURL:url collectingRedirects:redirects serverDate:NULL error:outError];
}

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirects serverDate:(NSDate **)outServerDate error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"DAV operation: PROPFIND %@", url);
    
    ODAVSingleFileInfoResult* result = [_connection synchronousMetaFileInfoAtURL:url serverDate:outServerDate error:outError];
    [redirects addObjectsFromArray:result.redirects];
    return result.fileInfo;
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url withETag:(NSString *)ETag error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"DAV operation: GET %@", url);
    
    return [_connection synchronousGetContentsOfURL:url ETag:ETag error:outError];
}

- (NSMutableArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections error:(NSError *__autoreleasing *)outError
{
    return [self directoryContentsAtURL:url withETag:nil collectingRedirects:redirections serverDate:NULL error:outError];
}

- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections machineDate:(NSDate **)outMachineDate error:(NSError **)outError;
{
    return [self directoryContentsAtURL:url withETag:nil collectingRedirects:redirections serverDate:outMachineDate error:outError];
}

- (NSMutableArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url withETag:(NSString *)ETag collectingRedirects:(NSMutableArray *)redirections serverDate:(NSDate **)outServerDate error:(NSError **)outError;
{
    OBPRECONDITION(url);
    
    OBLog(OFSFileManagerLogger, 2, @"DAV operation: PROPFIND %@ (ETag: %@)", url, ETag);

    _connection.operationReason = self.operationReason;
    ODAVMultipleFileInfoResult *results = [_connection synchronousDirectoryContentsAtURL:url withETag:ETag error:outError];
    if (!results)
        return nil;
    
    if (redirections)
        [redirections addObjectsFromArray:results.redirects];
    if (outServerDate)
        *outServerDate = results.serverDate;
    
    OBLog(OFSFileManagerLogger, 1, @"    --> %@", results.fileInfos);
    return [results.fileInfos mutableCopy];
}

- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    NSArray *fileInfos = [self directoryContentsAtURL:url withETag:nil collectingRedirects:nil serverDate:NULL error:outError];
    if (!fileInfos)
        return nil;
    
    if (extension) {
        return [fileInfos select:^BOOL(ODAVFileInfo *info){
            NSString *filename = [info name];
            return [[filename pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame;
        }];
    }

    return fileInfos;
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    return [self dataWithContentsOfURL:url withETag:nil error:outError];
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    OBPRECONDITION(data, @"Pass an empty data if that's really what you want");
    OBPRECONDITION(url);

    OBLog(OFSFileManagerLogger, 2, @"DAV operation: PUT %@ (data of %ld bytes) atomically:%d", url, [data length], atomically);

    // PUT is not atomic.  By itself it will just stream the file right into place; if the transfer is interrupted, it'll just leave a partial turd there.
    if (atomically) {
        // Do a non-atomic PUT to a temporary location.  The name needs to be something that won't get picked up by XMLTransactionGraph or XMLSynchronizer (which use file extensions).  We don't have a temporary directory on the DAV server.
        // TODO: Use the "POST to unique filename" feature if this DAV server supports it --- we'll need to do discovery, but we can do that for free in our initial PROPFIND. See ftp://ftp.ietf.org/internet-drafts/draft-reschke-webdav-post-08.txt. 
        NSString *temporaryNameSuffix = [@"-write-in-progress-" stringByAppendingString:OFXMLCreateID()];
        NSURL *temporaryURL = OFURLWithNameAffix(url, temporaryNameSuffix, NO, YES);
        
        NSURL *actualTemporaryURL = [self writeData:data toURL:temporaryURL atomically:NO error:outError];
        if (!actualTemporaryURL)
            return nil;
        
        NSURL *finalURL = url;
        if (!OFURLEqualsURL(actualTemporaryURL,temporaryURL)) {
            NSString *rewrittenFinalURL = OFURLAnalogousRewrite(temporaryURL, [url absoluteString], actualTemporaryURL);
            if (rewrittenFinalURL)
                finalURL = [NSURL URLWithString:rewrittenFinalURL];
        }
        
        // MOVE the fully written data into place.
        // TODO: Try to delete the temporary file if MOVE fails?
        return [self moveURL:actualTemporaryURL toURL:finalURL error:outError];
    }
    
    return [_connection synchronousPutData:data toURL:url error:outError];
}

- (NSURL *)writeData:(NSData *)data atomicallyReplacing:(ODAVFileInfo *)destination error:(NSError **)outError;
{
    // Do a non-atomic PUT to a temporary location.  The name needs to be something that won't get picked up by XMLTransactionGraph or XMLSynchronizer (which use file extensions).  We don't have a temporary directory on the DAV server.
    // TODO: Use the "POST to unique filename" feature if this DAV server supports it --- we'll need to do discovery, but we can do that for free in our initial PROPFIND. See ftp://ftp.ietf.org/internet-drafts/draft-reschke-webdav-post-08.txt.
    NSString *temporaryNameSuffix = [@"-write-in-progress-" stringByAppendingString:OFXMLCreateID()];
    NSURL *temporaryURL = OFURLWithNameAffix(destination.originalURL, temporaryNameSuffix, NO, YES);
    
    NSURL *actualTemporaryURL = [self writeData:data toURL:temporaryURL atomically:NO error:outError];
    if (!actualTemporaryURL)
        return nil;
    
    NSURL *finalURL = destination.originalURL;
    if (!OFURLEqualsURL(actualTemporaryURL,temporaryURL)) {
        NSString *rewrittenFinalURL = OFURLAnalogousRewrite(temporaryURL, [finalURL absoluteString], actualTemporaryURL);
        if (rewrittenFinalURL)
            finalURL = [NSURL URLWithString:rewrittenFinalURL];
    }
    
    // MOVE the fully written data into place.
    // TODO: Try to delete the temporary file if MOVE fails?
    return [_connection synchronousMoveURL:actualTemporaryURL toURL:finalURL withDestinationETag:destination.ETag overwrite:destination.exists error:outError];
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    OBPRECONDITION(url);
    OBPRECONDITION(_connection);
    
    OBLog(OFSFileManagerLogger, 2, @"DAV operation: MKCOL %@", url);
    
    return [_connection synchronousMakeCollectionAtURL:url error:outError].URL;
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);
    
    OBLog(OFSFileManagerLogger, 2, @"DAV operation: MOVE %@ -> %@", sourceURL, destURL);

    return [_connection synchronousMoveURL:sourceURL toURL:destURL withDestinationETag:nil overwrite:YES error:outError];
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(url);
    
    OBLog(OFSFileManagerLogger, 2, @"DAV operation: DELETE %@", url);
    
    return [_connection synchronousDeleteURL:url withETag:nil error:outError];
}

- (BOOL)deleteFile:(ODAVFileInfo *)fileinfo error:(NSError **)outError;
{
    NSURL *url = fileinfo.originalURL;
    OBPRECONDITION(url);
    
    OBLog(OFSFileManagerLogger, 2, @"DAV operation: DELETE %@ (ETag %@)", url, fileinfo.ETag);
    
    return [_connection synchronousDeleteURL:url withETag:fileinfo.ETag error:outError];
}

@end
