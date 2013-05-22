// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileManager.h>

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

#import "OFSFileOperation.h"

RCS_ID("$Id$");

NSInteger OFSFileManagerDebug = 0;


// If the file name ends in a number, we are likely dealing with a duplicate.
void OFSFileManagerSplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter)
{
    [originalName splitName:outName andCounter:outCounter];
}

@implementation OFSFileManager

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBInitializeDebugLogLevel(OFSFileManagerDebug);
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

- (void)invalidate;
{
    _weak_delegate = nil;
}

- (id <OFSAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url;
{
    return [[OFSFileOperation alloc] initWithFileManager:self readingURL:url];
}

- (id <OFSAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically;
{
    return [[OFSFileOperation alloc] initWithFileManager:self writingData:data atomically:atomically toURL:url];
}

- (NSURL *)availableURL:(NSURL *)startingURL;
{
    BOOL isFileURL = [startingURL isFileURL];
    NSString *baseName = [OFSFileInfo nameForURL:startingURL];
    NSURL *directoryURL = OFSDirectoryURLForURL(startingURL);
    
    NSString *extension = [baseName pathExtension];
    
    BOOL shouldContainExtension = ![NSString isEmptyString:extension];
    
    __autoreleasing NSString *name;
    NSUInteger counter;
    NSString *urlName = [baseName stringByDeletingPathExtension];
    
    OFSFileManagerSplitNameAndCounter(urlName, &name, &counter);
    
    NSURL *result = nil;
    while (!result) {
        @autoreleasepool {
        
        
            NSString *fileName = nil;
            if (shouldContainExtension) {
                fileName = [[NSString alloc] initWithFormat:@"%@.%@", name, extension];
            }
            else {
                fileName = [[NSString alloc] initWithString:name];
            }
            
            NSLog(@"%@", fileName);
            
            NSURL *urlCheck = isFileURL ? OFSFileURLRelativeToDirectoryURL(directoryURL, fileName) : OFSURLRelativeToDirectoryURL(directoryURL, [fileName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);

            __autoreleasing NSError *error = nil;
            OFSFileInfo *fileCheck = [self fileInfoAtURL:urlCheck error:&error];  // all OFSFileManagers implement OFSConcreteFileManager, so this should be safe
            if (error) {
                NSLog(@"%@", error);
                return nil;
            }
            
            if (![fileCheck exists]) {
                result = [[fileCheck originalURL] copy];
            } else {
                if (counter == 0)
                    counter = 2; // First duplicate should be "Foo 2".
                
                if (shouldContainExtension) {
                    fileName = [[NSString alloc] initWithFormat:@"%@ %lu.%@", name, counter, extension];
                }
                else {
                    fileName = [[NSString alloc] initWithFormat:@"%@ %lu", name, counter];
                }
                
                counter++;
                
                urlCheck = isFileURL ? OFSFileURLRelativeToDirectoryURL(directoryURL, fileName) : OFSURLRelativeToDirectoryURL(directoryURL, [fileName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
                fileCheck = [self fileInfoAtURL:urlCheck error:&error];
                if (error){
                    NSLog(@"%@", error);
                    return nil;
                }
                
                if (![fileCheck exists])
                    result = [[fileCheck originalURL] copy];
            }
        
        }
    }
    
    return result;
}

- (NSURL *)createDirectoryAtURLIfNeeded:(NSURL *)requestedDirectoryURL error:(NSError **)outError;
{
    __autoreleasing NSError *directoryInfoError = nil;

    // Assume it exists...
    OFSFileInfo *directoryInfo = [self fileInfoAtURL:requestedDirectoryURL error:&directoryInfoError];
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

@end
