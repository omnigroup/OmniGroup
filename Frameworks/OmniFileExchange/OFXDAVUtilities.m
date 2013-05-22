// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXDAVUtilities.h"

#import <OmniFileExchange/OFXErrors.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/Errors.h>

RCS_ID("$Id$")

/*
 In several places we want to get the fileInfos at a directory *and* ensure we have a server date. We also want to be sure the directory exists so that our server date is valid and so that following operations can write to the directory. Finally, we may be racing against other clients (usually in the tests).
 */

NSArray *OFXFetchFileInfosEnsuringDirectoryExists(OFSDAVFileManager *fileManager, NSURL *directoryURL, NSDate **outServerDate, NSError **outError)
{
    __autoreleasing NSError *fetchError;
    NSArray *fileInfos = [fileManager directoryContentsAtURL:directoryURL withETag:nil collectingRedirects:nil options:OFSDirectoryEnumerationSkipsSubdirectoryDescendants|OFSDirectoryEnumerationSkipsHiddenFiles serverDate:outServerDate error:&fetchError];
    if (fileInfos)
        return fileInfos;
    
    if (![fetchError hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND]) {
        if (outError) {
            *outError = fetchError;
            OBChainError(outError);
        }
        return nil;
    }
    
    // Go ahead and create the directory so that our later writes will work and so that we can do a follow-up PROPFIND.
    // No worry, but let's go ahead and create the directory here so that our write below will work.
    __autoreleasing NSError *createError;
    if (![fileManager createDirectoryAtURL:directoryURL attributes:nil error:&createError]) {
        if ([createError hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_METHOD_NOT_ALLOWED] ||
            [createError hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_CONFLICT]) {
            // Might be racing with another agent (most likely in tests). If we get a conflict or not allowed error, go ahead and try the PROPFIND again.
        } else {
            [createError log:@"Error creating directory at %@", directoryURL];
            if (outError) {
                *outError = createError;
                OBChainError(outError);
            }
            return nil;
        }
    }
    
    // Redo the PROPFIND so that we get a notion of what the server thinks the time is.
    fileInfos = [fileManager directoryContentsAtURL:directoryURL withETag:nil collectingRedirects:nil options:OFSDirectoryEnumerationSkipsSubdirectoryDescendants|OFSDirectoryEnumerationSkipsHiddenFiles serverDate:outServerDate error:&fetchError];
    if (!fileInfos) {
        if (outError)
            *outError = fetchError;
        OBChainError(outError);
        return nil;
    }
    return fileInfos;
}

static BOOL _parentDirectoryMightBeMissing(NSError *error)
{
    return
    [error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND] || // svn's WebDAV returns 404 Not Found
    [error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_FORBIDDEN] ||
    [error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_METHOD_NOT_ALLOWED] ||
    [error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_CONFLICT] ||
    [error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_INTERNAL_SERVER_ERROR]; // Apache returns 500 when moving a collection and the destination parent directory doesn't exist. Sigh.
}

NSURL *OFXWriteDataToURLAtomically(OFSDAVFileManager *fileManager, NSData *data, NSURL *destinationURL, NSURL *temporaryDirectoryURL, BOOL overwrite, NSError **outError)
{
    // Optimistically assume the temporary directory exists.
    NSString *temporaryFilename = OFXMLCreateID();
    NSURL *temporaryFileURL = [temporaryDirectoryURL URLByAppendingPathComponent:temporaryFilename isDirectory:NO];
    __autoreleasing NSError *writeError;
    
    temporaryFileURL = [fileManager writeData:data toURL:temporaryFileURL atomically:NO error:&writeError];
    if (!temporaryFileURL) {
        if (!_parentDirectoryMightBeMissing(writeError)) {
            if (outError)
                *outError = writeError;
            return nil;
        }
        
        // Create the temporary directory and remember the redirection, if any.
        __autoreleasing NSError *mkdirError;
        temporaryDirectoryURL = [fileManager createDirectoryAtURLIfNeeded:temporaryDirectoryURL error:&mkdirError];
        if (!temporaryDirectoryURL) {
            if (outError)
                *outError = mkdirError;
            return nil;
        }
        
        // Try writing the file again.
        temporaryFileURL = [temporaryDirectoryURL URLByAppendingPathComponent:temporaryFilename isDirectory:NO];
        writeError = nil;
        temporaryFileURL = [fileManager writeData:data toURL:temporaryFileURL atomically:NO error:&writeError];
        if (!temporaryFileURL) {
            if (outError)
                *outError = writeError;
            return nil;
        }
    }

    // This overwrites the destination if it exists.
    if (overwrite)
        return [fileManager moveURL:temporaryFileURL toURL:destinationURL error:outError];
    else {
        __autoreleasing NSError *moveError;
        if ((destinationURL = [fileManager moveURL:temporaryFileURL toMissingURL:destinationURL error:&moveError]))
            return destinationURL;
        
        [fileManager deleteURL:temporaryFileURL error:NULL];
        if (outError)
            *outError = moveError;
        return nil;
    }
}

NSURL *OFXMoveURLToMissingURLCreatingContainerIfNeeded(OFSDAVFileManager *fileManager, NSURL *sourceURL, NSURL *destinationURL, NSError **outError)
{
    // Assume the parent directory exists already.
    __autoreleasing NSError *moveError;
    NSURL *movedURL = [fileManager moveURL:sourceURL toMissingURL:destinationURL error:&moveError];
    if (movedURL)
        return movedURL;
    
    if (!_parentDirectoryMightBeMissing(moveError)) {
        if (outError)
            *outError = moveError;
        return nil;
    }
    
    __autoreleasing NSError *mkdirError;
    NSURL *parentDirectory = [fileManager createDirectoryAtURLIfNeeded:[destinationURL URLByDeletingLastPathComponent] error:&mkdirError];
    if (!parentDirectory) {
        if (outError)
            *outError = mkdirError;
        return nil;
    }

    // Update for possible redirection
    BOOL isDirectory = [[destinationURL absoluteString] hasSuffix:@"/"];
    destinationURL = [parentDirectory URLByAppendingPathComponent:[destinationURL lastPathComponent] isDirectory:isDirectory];

    return [fileManager moveURL:sourceURL toMissingURL:destinationURL error:outError];
}
