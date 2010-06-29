// Copyright 1997-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

RCS_ID("$Id$")

#import <OmniFoundation/OFErrors.h>
#import <OmniBase/NSError-OBExtensions.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <CoreServices/CoreServices.h>
#endif

static NSLock *tempFilenameLock = nil;

@implementation NSFileManager (OFTemporaryPath)

+ (void)didLoad;
{
    tempFilenameLock = [[NSLock alloc] init];
}

- (NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory error:(NSError **)outError;
{
    return [self temporaryPathForWritingToPath:path allowOriginalDirectory:allowOriginalDirectory create:YES error:outError];
}

// Note that due to the permissions behavior of FSFindFolder, this shouldn't have the security problems that raw calls to -uniqueFilenameFromName: may have.
- (NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory create:(BOOL)create error:(NSError **)outError;
/*" Returns a unique filename in the -temporaryDirectoryForFileSystemContainingPath: for the filesystem containing the given path.  The returned path is suitable for writing to and then replacing the input path using -replaceFileAtPath:withFileAtPath:handler:.  This means that the result should never be equal to the input path.  If no suitable temporary items folder is found and allowOriginalDirectory is NO, this will raise.  If allowOriginalDirectory is YES, on the other hand, this will return a file name in the same folder.  Note that passing YES for allowOriginalDirectory could potentially result in security implications of the form noted with -uniqueFilenameFromName:. "*/
{
    OBPRECONDITION(![NSString isEmptyString:path]);
    
    NSString *temporaryFilePath = nil;
    NSString *dir = [self temporaryDirectoryForFileSystemContainingPath:path error:outError];
    if (dir) {
        temporaryFilePath = [dir stringByAppendingPathComponent:[path lastPathComponent]];
        
        temporaryFilePath = [self uniqueFilenameFromName:temporaryFilePath allowOriginal:NO create:create error:outError];

        // Don't pass in paths that are already inside Temporary Items or you might get back the same path you passed in (with create == NO)
        OBASSERT(![temporaryFilePath isEqualToString:path]);
    }
    
    if (!temporaryFilePath && allowOriginalDirectory) {
        if (outError)
            *outError = nil; // Ignore any previous error
        
        // Try to use the same directory.  Can't just call -uniqueFilenameFromName:path since we want a NEW file name (-uniqueFilenameFromName: would just return the input path and the caller expecting a path where it can put something temporarily, i.e., different from the input path).
        temporaryFilePath = [self uniqueFilenameFromName:path allowOriginal:NO create:create error:outError];
    }
    
    OBPOSTCONDITION(!temporaryFilePath || (!create ^ [self fileExistsAtPath:temporaryFilePath]));
    OBPOSTCONDITION(!temporaryFilePath || (![path isEqualToString:temporaryFilePath]));
    
    return temporaryFilePath;
}

// Note that if this returns an error, a common course of action would be to put the temporary file in the same folder as the original file.  This has the same security problems as -uniqueFilenameFromName:, of course, so we don't want to do that by default.  The calling code should make this decision.
- (NSString *)temporaryDirectoryForFileSystemContainingPath:(NSString *)path error:(NSError **)outError;
/*" Returns the path to the 'Temporary Items' folder on the same filesystem as the given path.  Returns an error if there is a problem (for example, iDisk doesn't have temporary folders).  The returned directory should be only readable by the calling user, so files written into this directory can be written with the desired final permissions without worrying about security (the expectation being that you'll soon call -exchangeFileAtPath:withFileAtPath:). "*/
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Only one filesystem. Sadly, on the simulator this returns something in / instead of the app sandbox's "tmp" directory. Radar 8137291.
    return NSTemporaryDirectory();
#else
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Allow for a *specific* temporary items directory, no matter what volume was proposed.
    NSString *stringValue = [defaults stringForKey:@"OFTemporaryDirectory"];
    if (![NSString isEmptyString:stringValue])
        return [stringValue stringByStandardizingPath];
    
    // If an alternate temporary volume has been specified, use the 'Temporary Items' folder on that volume rather than on the same volume as the specified file
    stringValue = [defaults stringForKey:@"OFTemporaryVolumeOverride"];
    if (![NSString isEmptyString:stringValue])
        path = [stringValue stringByStandardizingPath];
    
    return [[self specialDirectory:kTemporaryFolderType forFileSystemContainingPath:path create:YES error:outError] path];
#endif
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSURL *)specialDirectory:(OSType)whatDirectoryType forFileSystemContainingPath:(NSString *)path create:(BOOL)createIfMissing error:(NSError **)outError;
{
    FSRef ref;
    OSStatus err;
    
    // The file in question might not exist yet.  This loop assumes that it will terminate due to '/' always being valid.
    NSString *attempt = path;
    while (YES) {
        const char *posixPath = [self fileSystemRepresentationWithPath:attempt];
        err = FSPathMakeRefWithOptions((const unsigned char *)posixPath, kFSPathMakeRefDoNotFollowLeafSymlink, &ref, NULL);
        if (err == noErr)
            break;
        attempt = [attempt stringByDeletingLastPathComponent];
    }
    
    // Find the path's volume number.
    FSCatalogInfo catalogInfo;
    err = FSGetCatalogInfo(&ref, kFSCatInfoVolume, &catalogInfo, NULL, NULL, NULL);
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]; // underlying error
        OFError(outError, OFCannotFindTemporaryDirectoryError, ([NSString stringWithFormat:@"Unable to get catalog info for '%@' (for '%@')", attempt, path]), nil);
        return nil;
    }
    
    // Actually look up the folder.
    FSRef folderRef;
    err = FSFindFolder(catalogInfo.volume, whatDirectoryType, createIfMissing? kCreateFolder : kDontCreateFolder, &folderRef);
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]; // underlying error
        OFError(outError, OFCannotFindTemporaryDirectoryError, ([NSString stringWithFormat:@"Unable to find temporary items directory for '%@'", attempt]), nil);
        return nil;
    }
    
    CFURLRef temporaryItemsURL;
    temporaryItemsURL = CFURLCreateFromFSRef(kCFAllocatorDefault, &folderRef);
    if (!temporaryItemsURL) {
        OFError(outError, OFCannotFindTemporaryDirectoryError, ([NSString stringWithFormat:@"Unable to create URL to temporary items directory for '%@'", attempt]), nil);
        return nil;
    }

    return [NSMakeCollectable(temporaryItemsURL) autorelease];
}
#endif

// Create a unique temp filename from a template filename, given a range within the template filename which identifies where the unique portion of the filename is to lie.

- (NSString *)tempFilenameFromTemplate:(NSString *)inputString andRange:(NSRange)replaceRange;
{
    NSMutableString *tempFilename = nil;
    NSString *result;
    unsigned int tempFilenameNumber = 1;
    
    [tempFilenameLock lock];
    NS_DURING {
        do {
            [tempFilename release];
            tempFilename = [inputString mutableCopy];
            [tempFilename replaceCharactersInRange:replaceRange withString:[NSString stringWithFormat:@"%d", tempFilenameNumber++]];
        } while ([self fileExistsAtPath:tempFilename]);
    } NS_HANDLER {
        [tempFilenameLock unlock];
        [tempFilename release];
        [localException raise];
    } NS_ENDHANDLER;
    [tempFilenameLock unlock];
    
    result = [[tempFilename copy] autorelease]; // Make a nice immutable string
    [tempFilename release];
    return result;
}

// Create a unique temp filename from a template string, given a position within the template filename which identifies where the unique portion of the filename is to begin.

- (NSString *)tempFilenameFromTemplate:(NSString *)inputString
                           andPosition:(int)position;
{
    NSRange replaceRange;
    
    replaceRange.location = position;
    replaceRange.length = 6;
    return [self tempFilenameFromTemplate:inputString andRange:replaceRange];
}

// Create a unique temp filename from a template string, given a substring within the template filename which is to be replaced by the unique portion of the filename.

- (NSString *)tempFilenameFromTemplate:(NSString *)inputString andSubstring:(NSString *)substring;
{
    NSRange replaceRange;
    
    replaceRange = [inputString rangeOfString:substring];
    return [self tempFilenameFromTemplate:inputString andRange:replaceRange];
}

// Create a unique temp filename from a template string which contains a substring of six hash marks which are to be replaced by the unique portion of the filename.

- (NSString *)tempFilenameFromHashesTemplate:(NSString *)inputString;
{
    return [self tempFilenameFromTemplate:inputString andSubstring:@"######"];
}

// Generate a unique filename based on a suggested name, possibly returning the same name.

// [WIML]: This function is kinda bogus and could represent a security problem. If we're opening+creating the file anyway (which some callers of this function depend on) we should return the opened fd instead of forcing the caller to re-open the file. We shouldn't create the file world-read, in case it's destined to hold sensitive info (there will be a window of opportunity before the file's permissions are reset). We're inefficiently testing for existence twice, once with lstat() and once with O_CREAT|O_EXCL. We should check into the algorithm used by e.g. mkstemp() or other secure scratch file functions and duplicate it.
- (NSString *)uniqueFilenameFromName:(NSString *)filename error:(NSError **)outError;
{
    return [self uniqueFilenameFromName:filename allowOriginal:YES create:YES error:outError];
}

static BOOL _tryUniqueFilename(NSFileManager *self, NSString *candidate, BOOL create, NSError **outError)
{
    if (outError)
        *outError = nil;
    
    const char *fsRep = [self fileSystemRepresentationWithPath:candidate];
    if (create) {
        int fd = open(fsRep, O_EXCL | O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd != -1) {
            close(fd); // no unlink, were are on the 'create' branch
            return YES;
        }
        
        if (errno == EEXIST) {
            // Can't use it; but leave *outError nil so another variant can be tried
            return NO;
        }
        
        // TODO: Not sure whether EACCES or EEXIST has precedence if both could be returned.
        // TODO: EINTR?
        // Probably EACCES, we aren't going to recover.
        if (outError)
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; // underlying error
        OFError(outError, OFCannotUniqueFileNameError, ([NSString stringWithFormat:@"Unable to create unique file from %@.", candidate]), nil);
        return NO;
    } else {
        // We can use the original if it doesn't exist in this case.  We do _not_ want to probe whether we can create this here since the caller is just trying to determine a name to try to create.  They'll get the creation failure; we don't want to get it.  We do want to know if we can't even determine if the file exists (directory unreadable, etc).
        // This variant doesn't traverse symlinks, which is what we want.
        struct stat statBuf;
        if (lstat(fsRep, &statBuf) == 0)
            // File exists and we can't use this path
            return NO;
        
        if (errno == ENOENT)
            return YES;
        
        // Don't know how to recover from any other errors.  Most likely this is EACCES and we don't have permissions to even check if the file exists.
        if (outError)
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; // underlying error
        OFError(outError, OFCannotUniqueFileNameError, ([NSString stringWithFormat:@"Unable to check for existence of %@.", candidate]), nil);
        return NO;
    }
}

// If 'create' is NO, the returned path will not exist.  This could allow another thread/process to steal the filename.
- (NSString *)uniqueFilenameFromName:(NSString *)filename allowOriginal:(BOOL)allowOriginal create:(BOOL)create error:(NSError **)outError;
{
    NSError *dummy = nil;
    if (!outError)
        outError = &dummy;
    
    if (allowOriginal && _tryUniqueFilename(self, filename, create, outError))
        return filename;
    else if (*outError) {
        // NO will be returned from _tryUniqueFilename w/o an error if we should keep trying.
        return nil;
    }
    
    // We either aren't allowing the original, or it exists.
    NSString *directory = [filename stringByDeletingLastPathComponent];
    NSString *name = [filename lastPathComponent];
    NSRange periodRange = [name rangeOfString:@"."];
    
    NSString *nameWithHashes;
    if (periodRange.length != 0)
        nameWithHashes = [NSString stringWithFormat:@"%@-######.%@", [name substringToIndex:periodRange.location], [name substringFromIndex:periodRange.location + 1]];
    else
        nameWithHashes = [NSString stringWithFormat:@"%@-######", name];
    
    NSString *pathWithHashes = [directory stringByAppendingPathComponent:nameWithHashes];
    
    unsigned int triesLeft = 10;
    while (triesLeft--) {
        NSString *variant = [self tempFilenameFromHashesTemplate:pathWithHashes];
        
        if (_tryUniqueFilename(self, variant, create, outError))
            return variant;
        else if (*outError) {
            // NO will be returned from _tryUniqueFilename w/o an error if we should keep trying.
            return nil;
        }
    }
    
    OFError(outError, OFCannotUniqueFileNameError, ([NSString stringWithFormat:@"Unable to find a variant of %@ that didn't already exist.", filename]), nil);
    return nil;
}

- (BOOL)_exchangeFileAtPath:(NSString *)originalFile withFileAtPath:(NSString *)newFile deleteOriginal:(BOOL)deleteOriginal error:(NSError **)outError;
/*" Replaces the orginal file with the new file, possibly using underlying filesystem features to do so atomically. "*/
{
    OBPRECONDITION(OFNOTEQUAL(originalFile, newFile));
    
    NSDictionary *originalAttributes = [self attributesOfItemAtPath:originalFile error:outError];
    if (!originalAttributes)
        return NO;
    
    NSDictionary *newAttributes = [self attributesOfItemAtPath:newFile error:outError];
    if (!newAttributes)
        return NO;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSURL *originalURL = [[[NSURL alloc] initFileURLWithPath:originalFile] autorelease];
    NSURL *newURL = [[[NSURL alloc] initFileURLWithPath:newFile] autorelease];
    
    // Try FSExchangeObjects.  Under 10.2 this will only work if both files are on the same filesystem and both are files (not folders).  We could check for these conditions up front, but they might fix/extend FSExchangeObjects, so we'll just try it.
    FSRef originalRef, newRef;
    if (!CFURLGetFSRef((CFURLRef)originalURL, &originalRef)) {
        OFError(outError, OFCannotExchangeFileError, ([NSString stringWithFormat:@"Unable to get file reference for '%@'", originalFile]), nil);
        return NO;
    }
    
    if (!CFURLGetFSRef((CFURLRef)newURL, &newRef)) {
        OFError(outError, OFCannotExchangeFileError, ([NSString stringWithFormat:@"Unable to get file reference for '%@'", newFile]), nil);
        return NO;
    }
    
    OSErr err = FSExchangeObjects(&originalRef, &newRef);
    if (err == noErr) {
        // Delete the original file which is now at the new file path.
        NSError *nErr;
        if (deleteOriginal && ![self removeItemAtPath:newFile error:&nErr]) {
            // We assume that failing to remove the temporary file is not a fatal error and don't raise.
            NSLog(@"Ignoring inability to remove '%@': %@", newFile, nErr);
        }
        return YES;
    }
#endif
    
    // Do a file renaming dance instead.
    {
        originalFile = [originalFile stringByStandardizingPath];
        
        // There is only one filesystem on iOS, so this extra move isn't necessary on the device. However, on the simulator there NSTemporaryDirectory() returns a value on the root filesystem instead of the app sandboxed "tmp" directory. It seems possible (though unlikely) that they'll add multiple filesystems on the device later, so we'll check at runtime.
        
        if ([originalAttributes fileSystemNumber] != [newAttributes fileSystemNumber]) {
            // Move the new file to the same directory as the original file.  If the files are on different filesystems, this may involve copying.  We do this before renaming the original to ensure that the destination filesystem has enough room for the new file.
            NSString *originalDir = [originalFile stringByDeletingLastPathComponent];
            NSString *temporaryPath = [self uniqueFilenameFromName:[originalDir stringByAppendingPathComponent:[newFile lastPathComponent]] allowOriginal:NO create:NO error:outError];
            if (!temporaryPath)
                return NO;
            
            if (![self moveItemAtPath:newFile toPath:temporaryPath error:outError]) {
                // Wrap the *outError from -moveItemAtPath:toPath:error: in an OFCannotExchangeFileError
                OFError(outError, OFCannotExchangeFileError, ([NSString stringWithFormat:@"Unable to move '%@' to '%@'", newFile, temporaryPath]), nil);
                return NO;
            }
            
            newFile = temporaryPath;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
            newURL = [[[NSURL alloc] initFileURLWithPath:newFile] autorelease];
#endif
            
            // Probably not necessary to refresh newAttributes these since we are done checking them. But we'll double-check that the filesystem is right now.
            OBASSERT([[self attributesOfItemAtPath:newFile error:outError] fileSystemNumber] == [originalAttributes fileSystemNumber]);
        }
        
        NSString *originalAside = nil;
        
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
        if (err == diffVolErr) {
            // Try FSExchangeObjects again, now that we know the files are on the same filesystem.
            
            if (CFURLGetFSRef((CFURLRef)newURL, &newRef)) {
                err = FSExchangeObjects(&originalRef, &newRef);
                if (err == noErr) {
                    originalAside = newFile; // This is the file we'll delete below, if we do. On successful swap, the old file is in the 'new' spot.
                }
            }
        }            
#endif
        
        if (!originalAside) {
            // Move the original file aside (in the same directory)
            originalAside = [self uniqueFilenameFromName:originalFile allowOriginal:NO create:NO error:outError];
            if (!originalAside)
                return NO;
            
            if (![self moveItemAtPath:originalFile toPath:originalAside error:outError]) {
                // Wrap the *outError from -moveItemAtPath:toPath:error: in an OFCannotExchangeFileError
                OFError(outError, OFCannotExchangeFileError, ([NSString stringWithFormat:@"Unable to move '%@' to '%@'", originalFile, originalAside]), nil);
                return NO;
            }
            
            // Move the new to the original
            if (![self moveItemAtPath:newFile toPath:originalFile error:outError]) {
                // Move the original back, hopefully.  This still leaves the new file in the original's directory.  Don't really want to move it back (might be across filesystems and might be big).  Maybe we should delete it?
                [self moveItemAtPath:originalAside toPath:originalFile error:NULL];
                
                // Wrap the *outError from -moveItemAtPath:toPath:error: in an OFCannotExchangeFileError
                OFError(outError, OFCannotExchangeFileError, ([NSString stringWithFormat:@"Unable to move '%@' to '%@'", newFile, originalFile]), nil);
                return NO;
            }
        }
        
        // Finally, delete the old original (which has successfully been replaced)
        if (deleteOriginal) {
            if (![self removeItemAtPath:originalAside error:NULL]) {
                // We assume failure isn't fatal
                NSLog(@"Ignoring inability to remove '%@'", originalAside);
            }
        } else {
            // Doing an exchange.
            if (![self moveItemAtPath:originalAside toPath:newFile error:NULL]) {
                NSLog(@"Ignoring inability to move preserved old file from '%@' to the new file's original location '%@'", originalAside, newFile);
            }
        }
        
        return YES;
    }
}

- (BOOL)replaceFileAtPath:(NSString *)originalFile withFileAtPath:(NSString *)newFile error:(NSError **)outError;
{
    return [self _exchangeFileAtPath:originalFile withFileAtPath:newFile deleteOriginal:YES error:outError];
}

- (BOOL)exchangeFileAtPath:(NSString *)originalFile withFileAtPath:(NSString *)newFile error:(NSError **)outError;
{
    return [self _exchangeFileAtPath:originalFile withFileAtPath:newFile deleteOriginal:NO error:outError];
}

@end
