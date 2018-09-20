// Copyright 2013-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXDAVUtilities.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniFileExchange/OFXErrors.h>

RCS_ID("$Id$")

/*
 In several places we want to get the fileInfos at a directory *and* ensure we have a server date. We also want to be sure the directory exists so that our server date is valid and so that following operations can write to the directory. Finally, we may be racing against other clients (usually in the tests).
 */

ODAVMultipleFileInfoResult *OFXFetchFileInfosEnsuringDirectoryExists(ODAVConnection *connection, NSURL *originalDirectoryURL, NSError **outError)
{
    __block NSURL *directoryURL = originalDirectoryURL;
    __block ODAVMultipleFileInfoResult *resultProperties;
    __block NSError *resultError;
    
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done){
        [connection directoryContentsAtURL:directoryURL withETag:nil completionHandler:^(ODAVMultipleFileInfoResult *firstProperties, NSError *firstContentsError) {
            if (firstProperties) {
                // When the directory doesn't exist, we might have gotten a redirect, but it won't be returned to us here (so we don't bother to do this on the error path).
                if ([firstProperties.redirects count] > 0) {
                    [connection updateBaseURLWithRedirects:firstProperties.redirects];
                    directoryURL = [connection suggestRedirectedURLForURL:directoryURL];
                }
                
                resultProperties = firstProperties;
                done();
                return;
            }
            if (![firstContentsError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
                resultError = firstContentsError;
                done();
                return;
            }

            // Create the directory so that we can get a snapshot of the server date.
            [connection makeCollectionAtURL:directoryURL completionHandler:^(ODAVURLResult *createResult, NSError *createError) {
                if (createError && (![createError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_METHOD_NOT_ALLOWED] &&
                                    ![createError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_CONFLICT] &&
                                    ![createError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_FORBIDDEN])) {
                    // Some non-racing error.
                    [createError log:@"Error creating directory at %@", directoryURL];
                    resultError = createError;
                    done();
                    return;
                }
                
                if ([createResult.redirects count] > 0) {
                    [connection updateBaseURLWithRedirects:createResult.redirects];
                    directoryURL = [connection suggestRedirectedURLForURL:directoryURL];
                }

                // Otherwise, it looks like we were racing. Try the PROPFIND again, so that we get a notion of what the server thinks the time is (and whatever might have appeared in the collection while racing).
                [connection directoryContentsAtURL:directoryURL withETag:nil completionHandler:^(ODAVMultipleFileInfoResult *secondProperties, NSError *secondContentsError) {
                    if (secondProperties)
                        resultProperties = secondProperties;
                    else
                        resultError = secondContentsError;
                    done();
                }];
            }];
        }];
    });
    
    if (resultProperties) {
        // Remember any redirects encountered.
        if ([resultProperties.redirects count] > 0) {
            [connection updateBaseURLWithRedirects:resultProperties.redirects];
        }
        
        return resultProperties;
    } else {
        if (outError)
            *outError = resultError;
        return nil;
    }
}

static BOOL _parentDirectoryMightBeMissing(NSError *error)
{
    return
    [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND] || // svn's WebDAV returns 404 Not Found
    [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_FORBIDDEN] ||
    [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_METHOD_NOT_ALLOWED] ||
    [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_CONFLICT] ||
    [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_INTERNAL_SERVER_ERROR]; // Apache returns 500 when moving a collection and the destination parent directory doesn't exist. Sigh.
}

void OFXWriteDataToURLAtomically(ODAVConnection *connection, NSData *data, NSURL *destinationURL, NSURL *temporaryDirectoryURL, NSURL *accountBaseURL, BOOL overwrite, void (^completionHandler)(NSURL *url, NSError *errorOrNil))
{
    OBPRECONDITION(connection);
    OBPRECONDITION(data);
    OBPRECONDITION(destinationURL);
    OBPRECONDITION(temporaryDirectoryURL);
    OBPRECONDITION(accountBaseURL);
    OBPRECONDITION(OFURLContainsURL(accountBaseURL, temporaryDirectoryURL));
    
    // Optimistically assume the temporary directory exists.
    NSString *temporaryFilename = OFXMLCreateID();
    
    completionHandler = [completionHandler copy];
    
    void (^moveIntoPlace)(NSURL *temporaryFileURL) = [^(NSURL *temporaryFileURL){
        
        NSURL *redirectedDestinationURL = [connection suggestRedirectedURLForURL:destinationURL];
        
        // This overwrites the destination if it exists.
        if (overwrite) {
            // We could leak a temporary file if the destination collection disappears.
            [connection moveURL:temporaryFileURL toURL:redirectedDestinationURL completionHandler:^(ODAVURLResult *moveResult, NSError *moveError) {
                completionHandler(moveResult.URL, moveError);
            }];
        } else {
            [connection moveURL:temporaryFileURL toMissingURL:redirectedDestinationURL completionHandler:^(ODAVURLResult *moveResult, NSError *moveError) {
                if (moveResult) {
                    completionHandler(moveResult.URL, nil);
                    return;
                }
                
                // Don't really need to wait for this delete to finish.
                [connection deleteURL:temporaryFileURL withETag:nil completionHandler:nil];
                completionHandler(nil, moveError);
            }];
        }
    } copy];
    
    accountBaseURL = [connection suggestRedirectedURLForURL:accountBaseURL];
    temporaryDirectoryURL = [connection suggestRedirectedURLForURL:temporaryDirectoryURL];
    NSURL *temporaryURL = [temporaryDirectoryURL URLByAppendingPathComponent:temporaryFilename isDirectory:NO];
    
    [connection putData:data toURL:temporaryURL
      completionHandler:^(ODAVURLResult *firstPutResult, NSError *firstPutError) {
        if (firstPutResult) {
            // Assumption correct! Move the temporary file into place.
            moveIntoPlace(firstPutResult.URL);
            return;
        }
        
        if (!_parentDirectoryMightBeMissing(firstPutError)) {
            completionHandler(nil, firstPutError);
            return;
        }
        
        // Create the temporary directory and remember the redirection, if any. This 'if necessary' method does race recovery, so we don't need to check for conflict/method not allowed errors here.
        [connection makeCollectionAtURLIfMissing:temporaryDirectoryURL baseURL:accountBaseURL completionHandler:^(ODAVURLResult *createResult, NSError *createError) {
            if (!createResult) {
                completionHandler(nil, createError);
                return;
            }
            
            // Try writing the file again.
            [connection putData:data toURL:[createResult.URL URLByAppendingPathComponent:temporaryFilename isDirectory:NO] completionHandler:^(ODAVURLResult *secondPutResult, NSError *secondPutError) {
                if (secondPutResult)
                    moveIntoPlace(secondPutResult.URL);
                else
                    completionHandler(nil, secondPutError);
            }];
        }];
    }];
    
}

NSURL *OFXMoveURLToMissingURLCreatingContainerIfNeeded(ODAVConnection *connection, NSURL *sourceURL, NSURL *destinationURL, NSError **outError)
{
    __block NSURL *resultURL;
    __block NSError *resultError;
    
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
        // Assume the parent directory exists already.
        [connection moveURL:sourceURL toMissingURL:destinationURL completionHandler:^(ODAVURLResult *firstMovedResult, NSError *firstMoveError) {
            if (firstMovedResult) {
                resultURL = firstMovedResult.URL;
                done();
                return;
            }
            
            if (!_parentDirectoryMightBeMissing(firstMoveError)) {
                resultError = firstMoveError;
                done();
                return;
            }
            
            [connection makeCollectionAtURLIfMissing:[destinationURL URLByDeletingLastPathComponent] baseURL:connection.baseURL completionHandler:^(ODAVURLResult *parentResult, NSError *createError) {
                if (!parentResult) {
                    resultError = createError;
                    done();
                    return;
                }
                
                // Update for possible redirection
                BOOL isDirectory = [[destinationURL absoluteString] hasSuffix:@"/"];
                NSURL *redirectedDestinationURL = [parentResult.URL URLByAppendingPathComponent:[destinationURL lastPathComponent] isDirectory:isDirectory];
                
                [connection moveURL:sourceURL toMissingURL:redirectedDestinationURL completionHandler:^(ODAVURLResult *secondMoveResult, NSError *secondMoveError) {
                    if (secondMoveResult)
                        resultURL = secondMoveResult.URL;
                    else
                        resultError = secondMoveError;
                    done();
                }];
            }];
        }];
    });
    
    if (resultURL)
        return resultURL;
    if (outError)
        *outError = resultError;
    return nil;
}
