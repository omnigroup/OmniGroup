// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSFileFileManager.h"

#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileStore/Errors.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>

RCS_ID("$Id$");

@implementation OFSFileFileManager

- initWithBaseURL:(NSURL *)baseURL delegate:(id <OFSFileManagerDelegate>)delegate error:(NSError **)outError;
{
    if (!(self = [super initWithBaseURL:baseURL delegate:delegate error:outError]))
        return nil;
    
    if (![[[self baseURL] path] isAbsolutePath]) {
        NSString *title =  NSLocalizedStringFromTableInBundle(@"An error has occurred.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Ensure that the address is correct and please try again.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        OFSError(outError, OFSBaseURLIsNotAbsolute, title, description);
        
        NSLog(@"Error: The path of the url \"%@\" is not absolute. Cannot create file-based file manager.", [self baseURL]);
        return nil;
    }
    
    return self;
}

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    return NO;
}

// TODO: Ensure that the input urls are within the specified URL.  Either need to check this directly, or require that they are relative.

static ODAVFileInfo *_createFileInfoAtPath(NSString *path)
{
    // TODO: Return nil here if we get an error other than 'does not exist'
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    BOOL exists = (attributes != nil);
    
    BOOL directory = [[attributes fileType] isEqualToString:NSFileTypeDirectory];
    off_t size = 0;
    if (!directory && attributes)
        size = [attributes fileSize];
    
    // +[NSURL fileURLWithPath:] will re-check whether this is a directory, but we already know.
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, directory);
    ODAVFileInfo *info = [[ODAVFileInfo alloc] initWithOriginalURL:(__bridge NSURL *)url name:[path lastPathComponent] exists:exists directory:directory size:size lastModifiedDate:[attributes fileModificationDate]];
    CFRelease(url);
    
    return info;
}

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"FILE operation: INFO at %@", url);

    ODAVFileInfo *info = _createFileInfoAtPath([url path]);

    OBLog(OFSFileManagerLogger, 1, @"    --> %@", info);
    
    return info;
}

- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    NSTimeInterval start = 0;
    if (OFSFileManagerLogger.level > 0) {
        OBLog(OFSFileManagerLogger, 2, @"FILE operation: DIR at %@, extension '%@'", url, extension);
        start = [NSDate timeIntervalSinceReferenceDate];
    }

    // Not using the OmniFoundation extension since it pulls in too much.
    NSString *basePath = [url path];
    
    BOOL errorIsNonexistenceError = NO;
    NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:basePath error:outError];
    
    if (!fileNames && outError) {
        NSString *errorDomain = [*outError domain];
        NSInteger errorCode = [*outError code];
        if (([errorDomain isEqualToString:NSCocoaErrorDomain] && (errorCode == NSFileNoSuchFileError || errorCode == NSFileReadNoSuchFileError)) ||
            ([errorDomain isEqualToString:NSPOSIXErrorDomain] && (errorCode == ENOENT))) {
            errorIsNonexistenceError = YES;
        }
    }
    
    if (!fileNames) {
        if (errorIsNonexistenceError) {
            NSURL *failingURL = url;
            NSDictionary *uinfo = [*outError userInfo];
            if ([uinfo objectForKey:NSURLErrorKey])
                failingURL = [uinfo objectForKey:NSURLErrorKey];
            else if ([uinfo objectForKey:NSFilePathErrorKey])
                failingURL = [NSURL fileURLWithPath:[uinfo objectForKey:NSFilePathErrorKey]];
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No document exists at \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason - listing a directory that doesn't exist"), basePath];
            OFSErrorWithInfo(outError, OFSNoSuchDirectory, NSLocalizedStringFromTableInBundle(@"Unable to read document.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason,
                             NSURLErrorKey, failingURL, nil);
        }
        return nil;
    }
    
    NSMutableArray<ODAVFileInfo *> *results = [NSMutableArray array];
    
    for (NSString *fileName in fileNames) {
        OBASSERT([[fileName pathComponents] count] == 1);

        if ([fileName hasPrefix:@"._"]) {
            // Ignore split resource fork files; these presumably happen when moving between filesystems.
            continue;
        }

        if (!extension || [[fileName pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame) {
            
            NSString *absolutePath = [basePath stringByAppendingPathComponent:fileName];
            ODAVFileInfo *fileInfo = _createFileInfoAtPath(absolutePath);
            [results addObject:fileInfo];
        }
    }
    
    if (OFSFileManagerLogger.level > 0) {
        static NSTimeInterval totalWait = 0;
        NSTimeInterval operationWait = [NSDate timeIntervalSinceReferenceDate] - start;
        totalWait += operationWait;
        OBLog(OFSFileManagerLogger, 1, @"    --> %gs (total %g) %@", operationWait, totalWait, results);
    }
    
    return results;
}

- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections machineDate:(NSDate **)outMachineDate error:(NSError **)outError;
{
    NSArray<ODAVFileInfo *> *result = [self directoryContentsAtURL:url havingExtension:nil error:outError];
    if (outMachineDate != NULL) {
        *outMachineDate = [NSDate date];
    }
    return result;
}

- (NSMutableArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections error:(NSError **)outError;
{
    return (NSMutableArray *)[self directoryContentsAtURL:url havingExtension:nil error:outError];
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"FILE operation: READ '%@'", url);
    
#if 0
    // This seems to leak file descriptors at the moment
    return [NSData dataWithContentsOfFile:[url path] options:NSDataReadingMapped|NSDataReadingUncached error:outError];
#else
    return [NSData dataWithContentsOfFile:[url path] options:NSDataReadingUncached error:outError];
#endif
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"FILE operation: WRITE %@ (data of %ld bytes)", url, [data length]);

    return [data writeToFile:[url path] options:(atomically ? NSDataWritingAtomic : 0) error:outError]? url : nil;
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"FILE operation: MKDIR %@", url);

    NSFileManager *manager = [NSFileManager defaultManager];
    
    // Don't create intermediate directories. Otherwise if the problem is that the user needs to mount a disk, we might spuriously create the mount point <bug://bugs/47647> (Disk syncing shouldn't automatically create a path to the target location)
    NSString *parentPath = [[url path] stringByDeletingLastPathComponent];
    if (![manager directoryExistsAtPath:parentPath traverseLink:YES]) {
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not find \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error description"), parentPath];
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Please make sure that the destination folder exists.", @"OmniFileStore", OMNI_BUNDLE, @"error reason");
        OFSError(outError, OFSCannotCreateDirectory, description, reason);
        return nil;
    }
    return [manager createPathComponents:[[url path] pathComponents] attributes:attributes error:outError]? url : nil;
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"FILE operation: RENAME %@ to %@", sourceURL, destURL);

    NSFileManager *manager = [NSFileManager defaultManager];

    if (![manager moveItemAtPath:[sourceURL path] toPath:[destURL path] error:outError]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to move \"%@\" to \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [sourceURL absoluteString], [destURL absoluteString]];
        OFSError(outError, OFSCannotMove, NSLocalizedStringFromTableInBundle(@"Unable to move file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
        return nil;
    }

    return destURL;
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"FILE operation: DELETE %@", url);

    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager removeItemAtPath:[url path] error:outError]) {
        if (outError) {
            if ([*outError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT] ||
                [*outError hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError]) {
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
                OFSError(outError, OFSNoSuchFile, NSLocalizedStringFromTableInBundle(@"Unable to delete file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
            } else {
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to delete \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
                OFSError(outError, OFSCannotDelete, NSLocalizedStringFromTableInBundle(@"Unable to delete file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
            }
        }
        return NO;
    }
    
    return YES;
}

@end
