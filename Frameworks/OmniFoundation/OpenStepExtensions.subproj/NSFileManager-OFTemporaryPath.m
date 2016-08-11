// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

RCS_ID("$Id$")

#import <OmniFoundation/OFErrors.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniFoundation/OFXMLIdentifier.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <CoreServices/CoreServices.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#endif

NS_ASSUME_NONNULL_BEGIN

static NSLock *tempFilenameLock = nil;

@implementation NSFileManager (OFTemporaryPath)

+ (void)didLoad;
{
    tempFilenameLock = [[NSLock alloc] init];
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
// We need this since NSItemReplacementDirectory creates a new directory inside the TemporaryItems directory instead of just returning the TemporaryItems directory. Radar 13965099: Add suitable replacement for FSFindFolder/kTemporaryFolderType
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (nullable NSURL *)_specialDirectory:(OSType)whatDirectoryType forFileSystemContainingPath:(NSString *)path create:(BOOL)createIfMissing error:(NSError **)outError;
{
    OBPRECONDITION([path isAbsolutePath]);
    
    FSRef ref;
    OSStatus err;
    
    // The file in question might not exist yet.  This loop assumes that it will terminate due to '/' always being valid.
    NSURL *attempt = [NSURL fileURLWithPath:path];
    while (YES) {
        if (CFURLGetFSRef((CFURLRef)attempt, &ref))
            break;
        attempt = [attempt URLByDeletingLastPathComponent];
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
    
    NSURL *resultURL = CFBridgingRelease(temporaryItemsURL);
    
    return [resultURL URLByStandardizingPath];
}
#pragma clang diagnostic pop
#endif

- (nullable NSURL *)temporaryDirectoryForFileSystemContainingURL:(NSURL *)fileURL error:(NSError **)outError;
/*"
 Returns a URL to a temporary items directory that can be used to write a new file and then do a -replaceItemAtURL:... If there is a problem (no temporary items folder on the filesystem), nil is returned.
 Note that if this returns an error, a common course of action would be to put the temporary file in the same folder as the original file.  This has the same security problems as -uniqueFilenameFromName:, of course, so we don't want to do that by default.  The calling code should make this decision.
 The returned directory should be only readable by the calling user, so files written into this directory can be written with the desired final permissions without worrying about security (the expectation being that you'll soon call -exchangeFileAtPath:withFileAtPath:).
 "*/
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Only one filesystem. Sadly, on the simulator this returns something in / instead of the app sandbox's "tmp" directory. Radar 8137291.
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByStandardizingPath]];
#else

    // Sadly, -URLForDirectory:inDomain:appropriateForURL:create:error: creates a new '(A Document Being Saved By foo)' directory each time it is called, even if you pass create:NO! We just want the temporary items directory.
#if 0
    NSError *error;
    NSURL *temporaryDirectory = [self URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:fileURL create:NO error:&error];
    NSLog(@"temporaryDirectoryForFileSystemContainingURL:%@ -> %@", fileURL, temporaryDirectory);
    if (!temporaryDirectory) {
        [error log:@"Error finding temporary directory"];
        if (outError)
            *outError = error;
    }
#endif
    
    // We do NOT carry over the OFTemporaryDirectory/OFTemporaryVolumeOverride goop from the path-based version since those could mean the result isn't usable for -replaceItemAtURL:...
    return [self _specialDirectory:kTemporaryFolderType forFileSystemContainingPath:[[fileURL absoluteURL] path] create:YES error:outError];
#endif
}

- (nullable NSURL *)temporaryURLForWritingToURL:(NSURL *)originalURL allowOriginalDirectory:(BOOL)allowOriginalDirectory error:(NSError **)outError;
{
    OBPRECONDITION(originalURL);
    
    NSURL *containerURL = [self temporaryDirectoryForFileSystemContainingURL:originalURL error:outError];
    if (!containerURL) {
        if (!allowOriginalDirectory)
            return nil;
        containerURL = [originalURL URLByDeletingLastPathComponent];
    }
    
    // Make sure we hand back standardized URLs. This won't work unless the container exists (meaning the passed in URL's container must exist if we allow the original directory).
    if (![containerURL checkResourceIsReachableAndReturnError:outError])
        return nil;
    containerURL = [containerURL URLByStandardizingPath];
    
    // Terrible, but if the originalURL doesn't exist yet (we are getting ready to build a new file in a temporary location to swap into place, maybe), then we will get an error trying to look up if it is a directory via -getResourceValue:forKey:error:.
    BOOL isDirectory = [[originalURL absoluteString] hasSuffix:@"/"];

    NSString *originalFilename = [originalURL lastPathComponent];
    
    // We do *not* use an intecrementing counter + an existence check since we don't create the resource. A counter-based approach will happily return the same value multiple times if the caller doesn't "use up" the temporary file name by creating it. This can be a subtle bug, so let's just avoid it (though creating the resource would also avoid it, it is less convenient for the caller...).
    // Prefix the original name to avoid having to munge path extension goop.
    NSString *identifier = OFXMLCreateID();
    NSString *temporaryFilename = [[NSString alloc] initWithFormat:@"%@-%@", identifier, originalFilename];
    [identifier release];
    
    NSURL *temporaryURL = [containerURL URLByAppendingPathComponent:temporaryFilename isDirectory:isDirectory];
    [temporaryFilename release];
    
    return temporaryURL;
}

- (nullable NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory error:(NSError **)outError;
{
    return [self temporaryPathForWritingToPath:path allowOriginalDirectory:allowOriginalDirectory create:YES error:outError];
}

// Note that due to the permissions behavior of FSFindFolder, this shouldn't have the security problems that raw calls to -uniqueFilenameFromName: may have.
- (nullable NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory create:(BOOL)create error:(NSError **)outError;
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
- (nullable NSString *)temporaryDirectoryForFileSystemContainingPath:(NSString *)path error:(NSError **)outError;
/*" Returns the path to the 'Temporary Items' folder on the same filesystem as the given path.  Returns an error if there is a problem (for example, iDisk doesn't have temporary folders).  The returned directory should be only readable by the calling user, so files written into this directory can be written with the desired final permissions without worrying about security (the expectation being that you'll soon call -exchangeFileAtPath:withFileAtPath:). "*/
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Only one filesystem. Sadly, on the simulator this returns something in / instead of the app sandbox's "tmp" directory. Radar 8137291.
    return [NSTemporaryDirectory() stringByStandardizingPath];
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
    
    return [[self _specialDirectory:kTemporaryFolderType forFileSystemContainingPath:path create:YES error:outError] path];
#endif
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#endif

// Create a unique temp filename from a template filename, given a range within the template filename which identifies where the unique portion of the filename is to lie.

- (NSString *)tempFilenameFromTemplate:(NSString *)inputString andRange:(NSRange)replaceRange;
{
    NSMutableString *tempFilename = nil;
    NSString *result;
    unsigned int tempFilenameNumber = 1;
    
    [tempFilenameLock lock];
    @try {
        do {
            [tempFilename release];
            tempFilename = [inputString mutableCopy];
            [tempFilename replaceCharactersInRange:replaceRange withString:[NSString stringWithFormat:@"%d", tempFilenameNumber++]];
        } while ([self fileExistsAtPath:tempFilename]);
    } @finally {
        [tempFilenameLock unlock];
    }
    
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
- (nullable NSString *)uniqueFilenameFromName:(NSString *)filename error:(NSError **)outError;
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
- (nullable NSString *)uniqueFilenameFromName:(NSString *)filename allowOriginal:(BOOL)allowOriginal create:(BOOL)create error:(NSError **)outError;
{
#if 0 && defined(DEBUG_bungi)
    OBASSERT(create, "Avoid this use to avoid race conditions");
#endif
    
    __autoreleasing NSError *error = nil;
    
    if (allowOriginal && _tryUniqueFilename(self, filename, create, &error))
        return filename;
    else if (error) {
        // NO will be returned from _tryUniqueFilename w/o an error if we should keep trying.
        if (outError)
            *outError = error;
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
    // <bug:///89026> (Rewrite _exchangeFileAtPath:… to use non-deprecated API or remove it)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OBPRECONDITION(OFNOTEQUAL(originalFile, newFile));
    OBASSERT_NOTNULL(originalFile);
    OBASSERT_NOTNULL(newFile);

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
#pragma clang diagnostic pop
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

NS_ASSUME_NONNULL_END


