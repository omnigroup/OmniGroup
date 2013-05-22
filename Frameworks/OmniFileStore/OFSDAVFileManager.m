// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDAVFileManager.h>

#import <OmniFileStore/OFSDAVConnection.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDAVOperation.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

RCS_ID("$Id$");

OBDEPRECATED_METHOD(-DAVFileManager:findCredentialsForChallenge:);
OBDEPRECATED_METHOD(-DAVFileManager:validateCertificateForChallenge:);
OBDEPRECATED_METHOD(+DAVFileManager:findCredentialsForChallenge:);
OBDEPRECATED_METHOD(+DAVFileManager:validateCertificateForChallenge:);


@implementation OFSDAVFileManager
{
    OFSDAVConnection *_connection;
    NSOperationQueue *_connectionQueue;
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
    
    _connection = [[OFSDAVConnection alloc] init];
    if ([delegate respondsToSelector:@selector(fileManagerShouldAllowCellularAccess:)]) {
        _connection.shouldDisableCellularAccess = ![delegate fileManagerShouldAllowCellularAccess:self];
    }

    // If we try to spin the runloop while using NSURLConnection's operation queue scheduling, we can end up blocking some of its work and deadlocking. Instead, we have the connection do its work on a private serial queue and we wait for it with NSConditionLocks.
    _connectionQueue = [[NSOperationQueue alloc] init];
    _connectionQueue.maxConcurrentOperationCount = 1;
    _connectionQueue.name = [NSString stringWithFormat:@"OFSDAVFileManager operations for %p", self];
    
    // Bridge the delegate methods we do have to blocks on the connection. Make sure to avoid strong references back from the connection to us or our delegate (which we assume owns us).
    if ([delegate respondsToSelector:@selector(fileManager:findCredentialsForChallenge:)]) {
        __weak OFSDAVFileManager *weakSelf = self;
        _connection.findCredentialsForChallenge = ^NSURLCredential *(OFSDAVConnection *connection, NSURLAuthenticationChallenge *challenge){
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
        _connection.validateCertificateForChallenge = ^(OFSDAVConnection *connection, NSURLAuthenticationChallenge *challenge){
            OFSDAVFileManager *strongSelf = weakSelf;
            if (!strongSelf)
                return;
            id <OFSFileManagerDelegate> blockDelegate = strongSelf.delegate;
            OBASSERT(blockDelegate, "File manager delegate deallocated while DAV connection still in use.");
            [blockDelegate fileManager:strongSelf validateCertificateForChallenge:challenge];
        };
    }
    return self;
}

#pragma mark API

- (NSString *)lockURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(url);

    __block NSString *returnToken;
    __block NSError *returnError;
    
    [self _performOperation:^(OperationDone done) {
        [_connection lockURL:url completionHandler:^(NSString *resultString, NSError *errorOrNil) {
            if (resultString)
                returnToken = resultString;
            else
                returnError = errorOrNil;
            done();
        }];
    }];
    
    if (!returnToken && outError)
        *outError = returnError;
    return returnToken;
}

- (BOOL)unlockURL:(NSURL *)url token:(NSString *)lockToken error:(NSError **)outError;
{
    OBPRECONDITION(url);

    __block NSError *returnError;
    
    [self _performOperation:^(OperationDone done) {
        [_connection unlockURL:url token:lockToken completionHandler:^(NSError *errorOrNil) {
            returnError = errorOrNil;
            done();
        }];
    }];
    
    if (returnError && outError)
        *outError = returnError;
    return returnError == nil;
}

#pragma mark OFSFileManager subclass

- (id <OFSAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url;
{
    return [_connection asynchronousGetContentsOfURL:url];
}

- (id <OFSAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically;
{
    // We need to PUT to a temporary location and the MOVE for this to work.  Right now we don't need atomic support.
    OBPRECONDITION(atomically == NO);
    
    return [_connection asynchronousPutData:data toURL:url];
}

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    return YES;
}

// TODO: Ensure that the input urls are within the specified URL.  Either need to check this directly, or require that they are relative.

- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    return [self fileInfoAtURL:url serverDate:NULL error:outError];
}

- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url serverDate:(NSDate **)outServerDate error:(NSError **)outError;
{
    OBPRECONDITION(url);

    __block OFSDAVSingleFileInfoResult *returnResult;
    __block NSError *returnError;
    
    [self _performOperation:^(OperationDone done) {
        [_connection fileInfoAtURL:url ETag:nil completionHandler:^(OFSDAVSingleFileInfoResult *result, NSError *errorOrNil) {
            if (result)
                returnResult = result;
            else
                returnError = errorOrNil;
            done();
        }];
    }];
    
    if (!returnResult && outError) {
        *outError = returnError;
        return nil;
    }
    
    if (outServerDate)
        *outServerDate = returnResult.serverDate;
    return returnResult.fileInfo;
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url withETag:(NSString *)ETag error:(NSError **)outError;
{
    OBPRECONDITION(url);

    __block OFSDAVOperation *operation;
    
    [self _performOperation:^(OperationDone done) {
        [_connection getContentsOfURL:url ETag:ETag completionHandler:^(OFSDAVOperation *op) {
            operation = op;
            done();
        }];
    }];

    if (operation.error) {
        if (outError)
            *outError = operation.error;
        return nil;
    }
    
    return operation.resultData;
}

- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
{
    return [self directoryContentsAtURL:url withETag:nil collectingRedirects:redirections options:options serverDate:NULL error:outError];
}

- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url withETag:(NSString *)ETag collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options serverDate:(NSDate **)outServerDate error:(NSError **)outError;
{
    OBPRECONDITION(url);

#ifdef DEBUG_bungi
    // I'd like to make this the default, so start reviewing callers that aren't passing it.
    OBPRECONDITION(options & OFSDirectoryEnumerationSkipsSubdirectoryDescendants);
    
    // I'd like to replace this with recursive directory applier that uses the first ETag to validate the directory and then passes the ETags for sub-collections down with their ETags. Right now if you pass in an ETag and we are forced to recurse manually, we could see partial writes to subfolders. It'd be better to have a precondition failure as part of that.
    OBPRECONDITION((options & OFSDirectoryEnumerationForceRecursiveDirectoryRead) == 0);
#endif

    __block NSMutableArray *returnContents;
    __block NSDate *returnServerDate;
    __block NSError *returnError;
    
    [self _performOperation:^(OperationDone done) {
        [_connection fileInfosAtURL:url ETag:ETag depth:(options & OFSDirectoryEnumerationSkipsSubdirectoryDescendants) ? OFSDAVDepthChildren : OFSDAVDepthInfinite completionHandler:^(OFSDAVMultipleFileInfoResult *properties, NSError *errorOrNil) {
            
            if (!properties) {
                if ([errorOrNil hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND]) {
                    // The resource was legitimately not found.
                    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No document exists at \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason - listing contents of a nonexistent directory"), url];
                    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read document.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
                    __autoreleasing NSError *error = errorOrNil;
                    OFSError(&error, OFSNoSuchDirectory, description, reason);
                    returnError = error;
                    done();
                    return;
                }
                if (!(options & OFSDirectoryEnumerationSkipsSubdirectoryDescendants) &&
                    (options & OFSDirectoryEnumerationForceRecursiveDirectoryRead) &&
                    [errorOrNil hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_FORBIDDEN]) {
                    /* possible that 'depth:infinity' not supported on this server but still want results */
                    __autoreleasing NSError *recursiveError;
                    returnContents = [self _recursivelyCollectDirectoryContentsAtURL:url collectingRedirects:redirections options:options error:&recursiveError];
                    if (!returnContents)
                        returnError = recursiveError;
                    done();
                    return;
                }
                
                returnError = errorOrNil;
                done();
                return;
            }
            
            NSDictionary *lastRedirect = [redirections lastObject];
            NSURL *expectedDirectoryURL = [lastRedirect objectForKey:kOFSRedirectedTo];
            if (!expectedDirectoryURL)
                expectedDirectoryURL = url;
            
            NSArray *fileInfos = properties.fileInfos;
            if ([fileInfos count] == 1) {
                // If we only got info about one resource, and it's not a collection, then we must have done a PROPFIND on a non-collection
                OFSFileInfo *info = [fileInfos objectAtIndex:0];
                if (![info isDirectory]) {
                    // Is there a better error code for this? Do any of our callers distinguish this case from general failure?
                    returnError = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOTDIR userInfo:[NSDictionary dictionaryWithObject:url forKey:OFSURLErrorFailingURLStringErrorKey]];
                    done();
                    return;
                }
                // Otherwise, it's just that the collection is empty.
            }
            
            NSMutableArray *contents = [NSMutableArray array];
            
            OFSFileInfo *containerInfo = nil;
            
            for (OFSFileInfo *info in fileInfos) {
                if (![info exists]) {
                    OBASSERT_NOT_REACHED("Why would we list something that doesn't exist?"); // Maybe if a <prop> element comes back 404 or with some other error?  We aren't even looking at the per entry status yet.
                    continue;
                }
                
                // The directory itself will be in the property results.
                // We don't necessarily know what its name will be, though.
                if (!containerInfo && OFURLEqualsURL([info originalURL], expectedDirectoryURL)) {
                    containerInfo = info;
                    // Don't return the container itself in the results list.
                    continue;
                }
                
                if ((options & OFSDirectoryEnumerationSkipsHiddenFiles) && [[info name] hasPrefix:@"."]) {
                    continue;
                }
                
                if ([[info name] hasPrefix:@"._"]) {
                    // Ignore split resource fork files; these presumably happen when moving between filesystems.
                    continue;
                }
                
                [contents addObject:info];
            }
            
            if (!containerInfo && [contents count]) {
                // Somewhat unexpected: we never found the fileinfo corresponding to the container itself.
                // My reading of RFC4918 [5.2] is that all of the contained items MUST have URLs consisting of the container's URL plus one path component.
                // (The resources may be available at other URLs as well, but I *think* those URLs will not be returned in our multistatus.)
                // If so, and ignoring the possibility of resources with zero-length names, the container will be the item with the shortest path.
                
                NSUInteger shortestIndex = 0;
                NSUInteger shortestLength = [[[[contents objectAtIndex:shortestIndex] originalURL] path] length];
                for (NSUInteger infoIndex = 1; infoIndex < [contents count]; infoIndex ++) {
                    OFSFileInfo *contender = [contents objectAtIndex:infoIndex];
                    NSUInteger contenderLength = [[[contender originalURL] path] length];
                    if (contenderLength < shortestLength) {
                        shortestIndex = infoIndex;
                        shortestLength = contenderLength;
                    }
                }
                
                containerInfo = [contents objectAtIndex:shortestIndex];
                
                if (redirections) {
                    if (OFSFileManagerDebug > 0) {
                        NSLog(@"PROPFIND rewrite <%@> -> <%@>", expectedDirectoryURL, [containerInfo originalURL]);
                    }
                    
                    OFSAddRedirectEntry(redirections, kOFSRedirectPROPFIND, expectedDirectoryURL, [containerInfo originalURL], nil /* PROPFIND is not cacheable */ );
                }
                
                [contents removeObjectAtIndex:shortestIndex];
            }
            
            // containerInfo is still in fileInfos, so it won't have been deallocated yet
            OBASSERT([containerInfo isDirectory]);
            
            returnContents = contents;
            returnServerDate = properties.serverDate;
            [redirections addObjectsFromArray:properties.redirects];
            done();
        }];
    }];

    if (!returnContents) {
        if (outError)
            *outError = returnError;
    } else {
        if (outServerDate)
            *outServerDate = returnServerDate;
    }
    return returnContents;
}

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
{
    NSMutableArray *fileInfos = [self directoryContentsAtURL:url withETag:nil collectingRedirects:nil options:options serverDate:NULL error:outError];
    if (!fileInfos)
        return nil;
    
    if (extension) {
        NSUInteger infoIndex = [fileInfos count];
        while (infoIndex--) {
            OFSFileInfo *info = [fileInfos objectAtIndex:infoIndex];
            
            NSString *filename = [info name];
            
            // Verify the extension after decoding, in case the extension has something quote-worth.
            if ([[filename pathExtension] caseInsensitiveCompare:extension] != NSOrderedSame) {
                [fileInfos removeObjectAtIndex:infoIndex];
                continue;
            }
        }
    }

    return fileInfos;
}

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    return [self directoryContentsAtURL:url havingExtension:extension options:OFSDirectoryEnumerationSkipsSubdirectoryDescendants error:outError];
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    return [self dataWithContentsOfURL:url withETag:nil error:outError];
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    OBPRECONDITION(data, @"Pass an empty data if that's really what you want");
    OBPRECONDITION(url);

    if (OFSFileManagerDebug > 0)
        NSLog(@"DAV operation: PUT %@ (data of %ld bytes) atomically:%d", url, [data length], atomically);

    // PUT is not atomic.  By itself it will just stream the file right into place; if the transfer is interrupted, it'll just leave a partial turd there.
    if (atomically) {
        // Do a non-atomic PUT to a temporary location.  The name needs to be something that won't get picked up by XMLTransactionGraph or XMLSynchronizer (which use file extensions).  We don't have a temporary directory on the DAV server.
        // TODO: Use the "POST to unique filename" feature if this DAV server supports it --- we'll need to do discovery, but we can do that for free in our initial PROPFIND. See ftp://ftp.ietf.org/internet-drafts/draft-reschke-webdav-post-08.txt. 
        NSString *temporaryNameSuffix = [@"-write-in-progress-" stringByAppendingString:OFXMLCreateID()];
        NSURL *temporaryURL = OFSURLWithNameAffix(url, temporaryNameSuffix, NO, YES);
        
        NSURL *actualTemporaryURL = [self writeData:data toURL:temporaryURL atomically:NO error:outError];
        if (!actualTemporaryURL)
            return nil;
        
        NSURL *finalURL = url;
        if (!OFURLEqualsURL(actualTemporaryURL,temporaryURL)) {
            NSString *rewrittenFinalURL = OFSURLAnalogousRewrite(temporaryURL, [url absoluteString], actualTemporaryURL);
            if (rewrittenFinalURL)
                finalURL = [NSURL URLWithString:rewrittenFinalURL];
        }
        
        // MOVE the fully written data into place.
        // TODO: Try to delete the temporary file if MOVE fails?
        return [self moveURL:actualTemporaryURL toURL:finalURL error:outError];
    }
    
    __block NSURL *returnURL;
    __block NSError *returnError;
    
    [self _performOperation:^(OperationDone done) {
        [_connection putData:data toURL:url completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            if (resultURL)
                returnURL = resultURL;
            else
                returnError = errorOrNil;
            done();
        }];
    }];
    
    if (!returnURL && outError)
        *outError = returnError;
    return returnURL;
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    OBPRECONDITION(url);
    OBPRECONDITION(_connection);
    
    __block NSError *createError;
    __block NSURL *createdURL;

    [self _performOperation:^(OperationDone done) {
        [_connection makeCollectionAtURL:url completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            OBASSERT(resultURL || errorOrNil);
            if (resultURL)
                createdURL = resultURL;
            else
                createError = errorOrNil;
            done();
        }];
    }];
    
    if (!createdURL && outError)
        *outError = createError;
    return createdURL;
}

static NSURL *_returnURLOrError(NSURL *URL, NSError *error, NSError **outError)
{
    if (URL)
        return URL;
    if (outError)
        *outError = error;
    return nil;
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection moveURL:sourceURL toURL:destURL completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (NSURL *)copyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection copyURL:sourceURL toURL:destURL withSourceETag:ETag overwrite:overwrite completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection moveURL:sourceURL toURL:destURL withSourceLock:lock overwrite:overwrite completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection moveURL:sourceURL toURL:destURL withDestinationLock:lock overwrite:overwrite completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection moveURL:sourceURL toURL:destURL withSourceETag:ETag overwrite:overwrite completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection moveURL:sourceURL toURL:destURL withDestinationETag:ETag overwrite:overwrite completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (NSURL *)moveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection moveURL:sourceURL toMissingURL:destURL completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL ifURLExists:(NSURL *)tagURL error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destURL);

    __block NSURL *URL;
    __block NSError *error;
    
    [self _performOperation:^(OperationDone done) {
        [_connection moveURL:sourceURL toURL:destURL ifURLExists:tagURL completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            URL = resultURL;
            error = errorOrNil;
            done();
        }];
    }];
    
    return _returnURLOrError(URL, error, outError);
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    return [self deleteURL:url withETag:nil error:outError];
}

- (BOOL)deleteURL:(NSURL *)url withETag:(NSString *)ETag error:(NSError **)outError;
{
    OBPRECONDITION(_connection);
    OBPRECONDITION(url);
    
    __block BOOL success = NO;
    __block NSError *error; // strong ref to hold onto error past our autorelease pool.
    
    [self _performOperation:^(OperationDone done) {
        [_connection deleteURL:url withETag:ETag completionHandler:^(NSError *errorOrNil){
            if (errorOrNil) {
                success = NO;
                error = errorOrNil;
            } else
                success = YES;
            done();
        }];
    }];

    if (!success && outError)
        *outError = error;
    return success;
}

#pragma mark - Private

// See commentary in initializer about why we use a private operation queue.
typedef void (^OperationDone)(void);
typedef void (^Operation)(OperationDone done);

- (void)_performOperation:(Operation)op;
{
    NSConditionLock *doneLock = [[NSConditionLock alloc] initWithCondition:NO];
    
    op = [op copy];
    
    [_connectionQueue addOperationWithBlock:^{
        op(^{
            [doneLock lock];
            [doneLock unlockWithCondition:YES];
        });
    }];

    BOOL currentThreadBlocksOperationQueue = [NSOperationQueue currentQueue] == _connectionQueue;
    if (currentThreadBlocksOperationQueue) {
        _connectionQueue.maxConcurrentOperationCount = _connectionQueue.maxConcurrentOperationCount + 1;
        [doneLock lockWhenCondition:YES];
        _connectionQueue.maxConcurrentOperationCount = _connectionQueue.maxConcurrentOperationCount - 1;
        [doneLock unlock];
    } else {
        [doneLock lockWhenCondition:YES];
        [doneLock unlock];
    }
}

- (NSMutableArray *)_recursivelyCollectDirectoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
{
    OBPRECONDITION(url);

    NSMutableArray *folderContents = [self directoryContentsAtURL:url withETag:nil collectingRedirects:redirections options:(options | OFSDirectoryEnumerationSkipsSubdirectoryDescendants) serverDate:NULL error:outError];
    
    NSMutableIndexSet *directoryReferences = [[NSMutableIndexSet alloc] init];
    NSUInteger counter = 0;
    
    NSMutableArray *children = [[NSMutableArray alloc] init];
    for (OFSFileInfo *nextFile in folderContents) {
        if ([nextFile isDirectory]) {
            [directoryReferences addIndex:counter];
            
            NSMutableArray *moreFiles = [self _recursivelyCollectDirectoryContentsAtURL:[nextFile originalURL] collectingRedirects:redirections options:(options | OFSDirectoryEnumerationSkipsSubdirectoryDescendants) error:outError];
            [children addObjectsFromArray:moreFiles];
        }
        
        counter++;
    }
    [folderContents removeObjectsAtIndexes:directoryReferences];
    [folderContents addObjectsFromArray:children];
    
    return folderContents;
}

@end
