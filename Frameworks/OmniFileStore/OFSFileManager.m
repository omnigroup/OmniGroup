// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileManager.h>

#import <OmniBase/OBLogger.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFPreference.h>

#import "OFSFileFileManager.h"
#import "OFSFileOperation.h"

RCS_ID("$Id$");

OBLogger *OFSFileManagerLogger;

// If the file name ends in a number, we are likely dealing with a duplicate.
void OFSFileManagerSplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter)
{
    [originalName splitName:outName andCounter:outCounter];
}

@implementation OFSFileManager

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBLoggerInitializeLogLevel(OFSFileManagerLogger);
}

+ (Class)fileManagerClassForURLScheme:(NSString *)scheme;
{
    if ([scheme isEqualToString:@"file"])
        return [OFSFileFileManager class];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        return [OFSDAVFileManager class];
    return Nil;
}

- initWithBaseURL:(NSURL *)baseURL delegate:(id <OFSFileManagerDelegate>)delegate error:(NSError **)outError;
{
    OBPRECONDITION(baseURL);
    OBPRECONDITION([[baseURL path] isAbsolutePath]);
    
    if ([self class] == [OFSFileManager class]) {
        NSString *scheme = [baseURL scheme];
        Class cls = [[self class] fileManagerClassForURLScheme:scheme];
        if (cls) {
            return [[cls alloc] initWithBaseURL:baseURL delegate:delegate error:outError];
        }
        
        NSString *title =  NSLocalizedStringFromTableInBundle(@"An error has occurred.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Ensure that the server address, user name, and password are correct and please try again.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        OFSError(outError, OFSNoFileManagerForScheme, title, description);
        
        NSLog(@"Error: No scheme specific file manager for scheme \"%@\". Cannot create file manager.", scheme);
        
        return nil;
    }
    
    if (!(self = [super init]))
        return nil;

    _baseURL = [baseURL copy];
    _weak_delegate = delegate;
    
    return self;
}

@synthesize baseURL = _baseURL;
@synthesize delegate = _weak_delegate;

- (NSString *)locationDescription;
{
    // This is just used for including locations in error messages.
    return [_baseURL absoluteString];
}

- (void)invalidate;
{
    _weak_delegate = nil;
}

- (id <ODAVAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url;
{
    return [[OFSFileOperation alloc] initWithFileManager:self readingURL:url];
}

- (id <ODAVAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url;
{
    return [[OFSFileOperation alloc] initWithFileManager:self writingData:data atomically:NO toURL:url];
}

- (id <ODAVAsynchronousOperation>)asynchronousDeleteFile:(ODAVFileInfo *)f;
{
    return [[OFSFileOperation alloc] initWithFileManager:self deletingURL:f.originalURL];
}

- (NSURL *)createDirectoryAtURLIfNeeded:(NSURL *)requestedDirectoryURL error:(NSError **)outError;
{
    __autoreleasing NSError *directoryInfoError = nil;

    // Assume it exists...
    ODAVFileInfo *directoryInfo = [self fileInfoAtURL:requestedDirectoryURL error:&directoryInfoError];
    if (directoryInfo && directoryInfo.exists && directoryInfo.isDirectory) // If there is a flat file, fall through to the MKCOL to get a 409 Conflict filled in
        return directoryInfo.originalURL;
    
    if (outError != NULL)
        *outError = directoryInfoError;

    if (directoryInfo == nil && ([directoryInfoError causedByUnreachableHost] || [directoryInfoError causedByPermissionFailure]))
        return nil; // If we're not connected to the Internet, then no other error is particularly relevant

    if (OFURLEqualToURLIgnoringTrailingSlash(requestedDirectoryURL, _baseURL)) {
        OFSErrorWithInfo(outError, OFSCannotCreateDirectory,
                         @"Unable to create remote directory for container",
                         ([NSString stringWithFormat:@"Account base URL doesn't exist at %@", _baseURL]), nil);
        return nil;
    }
    
    NSURL *parentURL = [requestedDirectoryURL URLByDeletingLastPathComponent];
    parentURL = [self createDirectoryAtURLIfNeeded:parentURL error:outError];
    if (!parentURL)
        return nil;
    
    // Try to avoid extra redirects
    NSURL *createdDirectoryURL = [parentURL URLByAppendingPathComponent:[requestedDirectoryURL lastPathComponent] isDirectory:YES];
    __autoreleasing NSError *error = nil;
    
    createdDirectoryURL = [self createDirectoryAtURL:createdDirectoryURL attributes:nil error:&error];
    if (createdDirectoryURL)
        return createdDirectoryURL;
    
    if ([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_METHOD_NOT_ALLOWED] ||
        [error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_CONFLICT]) {
        // Might be racing against another creator.
        __autoreleasing NSError *infoError;
        directoryInfo = [self fileInfoAtURL:requestedDirectoryURL error:&infoError];
        if (directoryInfo && directoryInfo.exists && directoryInfo.isDirectory) // If there is a flat file, fall through to the MKCOL to get a 409 Conflict filled in
            return directoryInfo.originalURL;
    }
    NSLog(@"Unable to create directory at %@: %@", requestedDirectoryURL, [error toPropertyList]);
    if (outError)
        *outError = error;
    return nil;
}

- (BOOL)deleteFile:(ODAVFileInfo *)fileinfo error:(NSError **)outError;
{
    return [self deleteURL:fileinfo.originalURL error:outError];
}

@end
