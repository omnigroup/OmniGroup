// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileFileManager.h>

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSFileInfo.h>

#import <Foundation/NSFileManager.h>

RCS_ID("$Id$");

@implementation OFSFileFileManager

- initWithBaseURL:(NSURL *)baseURL error:(NSError **)outError;
{
    if (!(self = [super initWithBaseURL:baseURL error:outError]))
        return nil;
    
    if (![[[self baseURL] path] isAbsolutePath]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The path of the url \"%@\" is not absolute.", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [self baseURL]];
        OFSError(outError, OFSBaseURLIsNotAbsolute, NSLocalizedStringFromTableInBundle(@"Cannot create file-based file manager.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
        [self release];
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

static OFSFileInfo *_createFileInfoAtPath(NSString *path)
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
    OFSFileInfo *info = [[OFSFileInfo alloc] initWithOriginalURL:(NSURL *)url name:[path lastPathComponent] exists:exists directory:directory size:size];
    CFRelease(url);
    
    return info;
}

- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"FILE operation: INFO at %@", url);

    OFSFileInfo *info = [_createFileInfoAtPath([url path]) autorelease];

    if (OFSFileManagerDebug > 1)
        NSLog(@"  --> %@", info);
    
    return info;
}

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    NSTimeInterval start = 0;
    if (OFSFileManagerDebug > 0) {
        NSLog(@"FILE operation: DIR at %@, extension '%@'", url, extension);
        start = [NSDate timeIntervalSinceReferenceDate];
    }

    // Not using the OmniFoundation extension since it pulls in too much.
    NSString *basePath = [url path];
    
    NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:basePath error:outError];
    if (!fileNames) {
        // TODO: Log an error?  The current callers do for us already, though.
        return nil;
    }
    
    NSMutableArray *results = [NSMutableArray array];
    
    for (NSString *fileName in fileNames) {
        OBASSERT([[fileName pathComponents] count] == 1);

        if ([fileName hasPrefix:@"._"]) {
            // Ignore split resource fork files; these presumably happen when moving between filesystems.
            continue;
        }

        if (!extension || [[fileName pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame) {
            
            NSString *absolutePath = [basePath stringByAppendingPathComponent:fileName];
            OFSFileInfo *fileInfo = _createFileInfoAtPath(absolutePath);
            [results addObject:fileInfo];
            [fileInfo release];
        }
    }
    
    if (OFSFileManagerDebug > 0) {
        static NSTimeInterval totalWait = 0;
        NSTimeInterval operationWait = [NSDate timeIntervalSinceReferenceDate] - start;
        totalWait += operationWait;
        NSLog(@"  ... %gs (total %g)", operationWait, totalWait);
        if (OFSFileManagerDebug > 1)
            NSLog(@"  --> %@", results);
    }
    
    return results;
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"FILE operation: READ '%@'", url);
    
#if 0
    // This seems to leak file descriptors at the moment
    return [NSData dataWithContentsOfFile:[url path] options:NSMappedRead|NSUncachedRead error:outError];
#else
    return [NSData dataWithContentsOfFile:[url path] options:NSUncachedRead error:outError];
#endif
}

- (BOOL)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"FILE operation: WRITE %@ (data of %ld bytes)", url, [data length]);

    return [data writeToFile:[url path] options:(atomically ? NSAtomicWrite : 0) error:outError];
}

- (BOOL)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"FILE operation: MKDIR %@", url);

    NSFileManager *manager = [NSFileManager defaultManager];
    
    // Don't create intermediate directories. Otherwise if the problem is that the user needs to mount a disk, we might spuriously create the mount point <bug://bugs/47647> (Disk syncing shouldn't automatically create a path to the target location)
    if (![manager createDirectoryAtPath:[url path] withIntermediateDirectories:NO attributes:attributes error:outError]) {
	NSString *parentPath = [[url path] stringByDeletingLastPathComponent];
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not find \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error description"), parentPath];
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Please make sure that the location set in your Sync preferences actually exists.", @"OmniFileStore", OMNI_BUNDLE, @"error reason");
        OFSError(outError, OFSCannotCreateDirectory, description, reason);
        return NO;
    }
    return YES;
}

- (BOOL)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"FILE operation: RENAME %@ to %@", sourceURL, destURL);

    NSFileManager *manager = [NSFileManager defaultManager];

    if (![manager moveItemAtPath:[sourceURL path] toPath:[destURL path] error:outError]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to move \"%@\" to \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [sourceURL absoluteString], [destURL absoluteString]];
        OFSError(outError, OFSCannotMove, NSLocalizedStringFromTableInBundle(@"Unable to move file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
        return NO;
    }
    return YES;
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    if (OFSFileManagerDebug > 0)
        NSLog(@"FILE operation: DELETE %@", url);

    NSFileManager *manager = [NSFileManager defaultManager];

    if (![manager removeItemAtPath:[url path] error:outError]) {
	NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to delete \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
	OFSError(outError, OFSCannotDelete, NSLocalizedStringFromTableInBundle(@"Unable to delete file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), reason);
	return NO;
    }
    return YES;
}

@end
