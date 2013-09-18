// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXDAVUtilities.h"

#import <OmniDAV/ODAVErrors.h>
#import <OmniFileExchange/OFXErrors.h>

#import "OFXConnection.h"

RCS_ID("$Id$")

/*
 In several places we want to get the fileInfos at a directory *and* ensure we have a server date. We also want to be sure the directory exists so that our server date is valid and so that following operations can write to the directory. Finally, we may be racing against other clients (usually in the tests).
 */

NSArray *OFXFetchFileInfosEnsuringDirectoryExists(OFXConnection *connection, NSURL *directoryURL, NSDate **outServerDate, NSError **outError)
{
    __block ODAVMultipleFileInfoResult *resultProperties;
    __block NSError *resultError;
    
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done){
        [connection directoryContentsAtURL:directoryURL withETag:nil completionHandler:^(ODAVMultipleFileInfoResult *firstProperties, NSError *firstContentsError) {
            if (firstProperties) {
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
            [connection makeCollectionAtURL:directoryURL completionHandler:^(NSURL *createdURL, NSError *createError) {
                if (createError && (![createError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_METHOD_NOT_ALLOWED] &&
                                    ![createError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_CONFLICT])) {
                    // Some non-racing error.
                    [createError log:@"Error creating directory at %@", directoryURL];
                    resultError = createError;
                    done();
                    return;
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
        if (outServerDate)
            *outServerDate = resultProperties.serverDate;
        return resultProperties.fileInfos;
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

void OFXWriteDataToURLAtomically(OFXConnection *connection, NSData *data, NSURL *destinationURL, NSURL *temporaryDirectoryURL, NSURL *accountBaseURL, BOOL overwrite, void (^completionHandler)(NSURL *url, NSError *errorOrNil))
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
        // This overwrites the destination if it exists.
        if (overwrite) {
            // We could leak a temporary file if the destination collection disappears.
            [connection moveURL:temporaryFileURL toURL:destinationURL completionHandler:^(NSURL *movedURL, NSError *moveError) {
                completionHandler(movedURL, moveError);
            }];
        } else {
            [connection moveURL:temporaryFileURL toMissingURL:destinationURL completionHandler:^(NSURL *movedURL, NSError *moveError) {
                if (movedURL) {
                    completionHandler(movedURL, nil);
                    return;
                }
                
                // Don't really need to wait for this delete to finish.
                [connection deleteURL:temporaryFileURL withETag:nil completionHandler:nil];
                completionHandler(nil, moveError);
            }];
        }
    } copy];
    

    [connection putData:data toURL:[temporaryDirectoryURL URLByAppendingPathComponent:temporaryFilename isDirectory:NO]
      completionHandler:^(NSURL *firstPutURL, NSError *firstPutError) {
        if (firstPutURL) {
            // Assumption correct! Move the temporary file into place.
            moveIntoPlace(firstPutURL);
            return;
        }
        
        if (!_parentDirectoryMightBeMissing(firstPutError)) {
            completionHandler(nil, firstPutError);
            return;
        }
        
        // Create the temporary directory and remember the redirection, if any. This 'if necessary' method does race recovery, so we don't need to check for conflict/method not allowed errors here.
        [connection makeCollectionAtURLIfMissing:temporaryDirectoryURL baseURL:accountBaseURL completionHandler:^(NSURL *createdURL, NSError *createError) {
            if (!createdURL) {
                completionHandler(nil, createError);
                return;
            }
            
            // Try writing the file again.
            [connection putData:data toURL:[createdURL URLByAppendingPathComponent:temporaryFilename isDirectory:NO] completionHandler:^(NSURL *secondPutURL, NSError *secondPutError) {
                if (secondPutURL)
                    moveIntoPlace(secondPutURL);
                else
                    completionHandler(nil, secondPutError);
            }];
        }];
    }];
    
}

NSURL *OFXMoveURLToMissingURLCreatingContainerIfNeeded(OFXConnection *connection, NSURL *sourceURL, NSURL *destinationURL, NSError **outError)
{
    __block NSURL *resultURL;
    __block NSError *resultError;
    
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
        // Assume the parent directory exists already.
        [connection moveURL:sourceURL toMissingURL:destinationURL completionHandler:^(NSURL *firstMovedURL, NSError *firstMoveError) {
            if (firstMovedURL) {
                resultURL = firstMovedURL;
                done();
                return;
            }
            
            if (!_parentDirectoryMightBeMissing(firstMoveError)) {
                resultError = firstMoveError;
                done();
                return;
            }
            
            [connection makeCollectionAtURLIfMissing:[destinationURL URLByDeletingLastPathComponent] baseURL:connection.baseURL completionHandler:^(NSURL *parentDirectory, NSError *createError) {
                if (!parentDirectory) {
                    resultError = createError;
                    done();
                    return;
                }
                
                // Update for possible redirection
                BOOL isDirectory = [[destinationURL absoluteString] hasSuffix:@"/"];
                NSURL *redirectedDestinationURL = [parentDirectory URLByAppendingPathComponent:[destinationURL lastPathComponent] isDirectory:isDirectory];
                
                [connection moveURL:sourceURL toMissingURL:redirectedDestinationURL completionHandler:^(NSURL *secondMovedURL, NSError *secondMoveError) {
                    if (secondMovedURL)
                        resultURL = secondMovedURL;
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
