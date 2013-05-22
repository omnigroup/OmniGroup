// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSFileCoordinator (OFExtensions)

static id _getResourceValue(NSURL *url, NSString *resourceKey, BOOL expectedOK, NSError **outError)
{
    NSError *resourceError = nil;
    id resourceValue = nil;
    if (![url getResourceValue:&resourceValue forKey:resourceKey error:&resourceError]) {
        if (expectedOK)
            NSLog(@"Error getting the resource %@ for %@: %@", url, resourceKey, [resourceError toPropertyList]);
        if (outError)
            *outError = resourceError;
        return nil;
    }
    OBASSERT(resourceValue);
    return resourceValue;
}

static NSNumber *_URLsReferToSameResource(NSURL *URL1, NSURL *URL2, NSError **outError)
{
    OBPRECONDITION([URL1 isFileURL]);
    OBPRECONDITION([URL2 isFileURL]);
    
    // We expect that the source URL exists, but can't assume the destination does. So, we early out on the destination here.
    NSError *error = nil;
    id volumeIdentifier1 = _getResourceValue(URL1, NSURLVolumeIdentifierKey, NO, &error);
    if (!volumeIdentifier1) {
        if ([error causedByMissingFile])
            return @NO;
        NSLog(@"Error getting the resource %@ for %@: %@", URL1, NSURLVolumeIdentifierKey, [error toPropertyList]);
        if (outError)
            *outError = error;
        return nil;
    }

    id volumeIdentifier2 = _getResourceValue(URL2, NSURLVolumeIdentifierKey, NO, &error);
    if (!volumeIdentifier2) {
        if ([error causedByMissingFile])
            return @NO;
        NSLog(@"Error getting the resource %@ for %@: %@", URL2, NSURLVolumeIdentifierKey, [error toPropertyList]);
        if (outError)
            *outError = error;
        return nil;
    }

    if (OFNOTEQUAL(volumeIdentifier1, volumeIdentifier2))
        return @NO;

    // Past this point, we assume that the URLs exist. Of course, we're doing all of this outside of the scope of file coordination (so that we can figure out what coordinated move approach to use). We *could* try to 'prepare' with both the source and destination URL, but in at least some cases, filecoordinationd will crash if you pass the same URL twice. (12993597: filecoordinationd crashes under some circumstances). I've only seen this in the case of passing the same URL to the reading/writing list, but here we'd be passing a URL that is possibly the same (or points to the same resource) in the writing list. Worth considering for the future once the fix for the filecoordinationd bug is shipped and part of our required minimum OS.
    
    id resourceIdentifier1 = _getResourceValue(URL1, NSURLFileResourceIdentifierKey, YES, outError);
    if (!resourceIdentifier1)
        return nil;
    id resourceIdentifier2 = _getResourceValue(URL1, NSURLFileResourceIdentifierKey, YES, outError);
    if (!resourceIdentifier2)
        return nil;

    if (OFNOTEQUAL(resourceIdentifier1, resourceIdentifier2))
        return @NO;
    return @YES;
}

// If the result is @YES, then outIsCaseSenstiveFileSystem will be set. Otherwise, it might not be.
static NSNumber *_isCaseOnlyRename(NSURL *sourceURL, NSURL *destinationURL, BOOL *outIsCaseSenstiveFileSystem, NSError **outError)
{
    // Early out avoiding filesystem access...
    if ([[sourceURL lastPathComponent] caseInsensitiveCompare:[destinationURL lastPathComponent]])
        return @NO;
    
    // NSFileCoordinator treats URLs case insensitively even on case-sensitive filesystems. If you do specify "replace" for the options for the second URL in the two-URL write method, your moving item will get -accommodatePresentedItemDeletionWithCompletionHandler:. But, NSFileManager's move support will fail if the destination exists, so for case-only renames on case-insensitive filesystems, we need to know to go through a temporary name.
    if (outIsCaseSenstiveFileSystem) {
        NSNumber *caseSensitiveNumber = _getResourceValue(sourceURL, NSURLVolumeSupportsCaseSensitiveNamesKey, YES, outError);
        if (!caseSensitiveNumber)
            return nil;
        *outIsCaseSenstiveFileSystem = [caseSensitiveNumber boolValue];
    }
    
    // Check if both URLs point to the same volume and resource identifier. We could try to compare their parent paths, but the case sensitivity on the path only matters up to the mount point, so doing this any other way would be less accurate or a ton of code.
    // But, we want to do this based on what NSFileCoordinator will do -- it treats NSURLs case-insensitively even when on a case-senstive filesystem. So, we check if the parent directories are the same (since we know the last path components are the same already). Otherwise moving "foo" -> "Foo" would return a file-not-found on iOS.
    return _URLsReferToSameResource([sourceURL URLByDeletingLastPathComponent], [destinationURL URLByDeletingLastPathComponent], outError);
}

static BOOL _ensureParentDirectory(NSURL *url, NSError **outError)
{
    NSError *error;
    NSURL *parentDirectoryURL = [url URLByDeletingLastPathComponent];
    if ([[NSFileManager defaultManager] createDirectoryAtURL:parentDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error])
        return YES;
    NSLog(@"Error creating directory %@: %@", parentDirectoryURL, [error toPropertyList]);
    if (outError)
        *outError = error;
    return NO;
}

// TODO: Rename this method to make it clear that it is a user-initated rename where it is OK that the destinationURL exists, if it is the same as the sourceURL (in the case insensitivity case).
- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL createIntermediateDirectories:(BOOL)createIntermediateDirectories error:(NSError **)outError;
{
    // If fileURL is on a case-insenstive filesystem and destinationURL is the same except for case, then doing a move/replace here will cause presenters of fileURL to be told to accommodate for deletion (somewhat reasonably). So, we need to check if we are on a case-insenstive filesystem and just do a single URL move if we hit this case.
    // Radar 10686553: Coordinated renaming to fix filename case provokes accomodate for deletion

    BOOL isCaseSenstiveFileSystem = NO;
    NSNumber *caseOnlyRename = _isCaseOnlyRename(sourceURL, destinationURL, &isCaseSenstiveFileSystem, outError);
    if (!caseOnlyRename)
        return NO;
    
    __block BOOL success = NO;
    if ([caseOnlyRename boolValue]) {
        [self coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving error:outError
                              byAccessor:
         ^(NSURL *newURL){
             OBASSERT([newURL isEqual:sourceURL], @"It isn't clear what destinationURL should be in the case that NSFileCoordinator remaps our source here");
             
             NSError *moveError = nil;

             // Don't create the parent directory here -- this is a case-only rename, so the directory is the same.
             // If we are on a case-insensitive filesystem, a plain rename with NSFileManager will spuriously fail with EEXIST.
             // A rename(2) will work in this case, but no file presenter notification will be sent (either to direct presenters or sub-item presenters). Presumably NSFileCoordinator is discarding case-only renames? Note that this discarding happens on both case-insensitive and case-sensitive filesystems (NSFC is probably not checking, just always doing it).
             // We cannot bounce through a temporary name since even if we only notify file coordination of src->dst, our registered file presenters will magically be notified of src->tmp and then tmp->dst. This happens on both the Simulator and actual device (and presumably the Mac). This happens if we do the temporary -itemAtURL:didMoveToURL: or if we don't.
             // The safest thing to do is to pass a file presenter to the coordinator and notify yourself, but if there are multiple presenters for the same URL, this doesn't work either.
             if (!isCaseSenstiveFileSystem) {
                 const char *path1 = [[NSFileManager defaultManager] fileSystemRepresentationWithPath:[[newURL absoluteURL] path]];
                 const char *path2 = [[NSFileManager defaultManager] fileSystemRepresentationWithPath:[[destinationURL absoluteURL] path]];
                 
                 if (rename(path1, path2) != 0) {
                     if (outError) {
                         NSString *description = @"Error renaming file.";
                         NSString *reason = [NSString stringWithFormat:@"rename(2) returned %d.", errno];
                         NSDictionary *userInfo = @{
                                                    NSLocalizedDescriptionKey: description,
                                                    NSLocalizedFailureReasonErrorKey: reason,
                                                    @"source": @(path1),
                                                    @"destination": @(path2),
                                                    };
                         *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:userInfo];
                         return;
                     }
                 }
             } else {
                 if (![[NSFileManager defaultManager] moveItemAtURL:newURL toURL:destinationURL error:&moveError]) {
                     //NSLog(@"Error moving %@ to %@: %@", newURL, destinationURL, [moveError toPropertyList]);
                     if (outError)
                         *outError = moveError;
                     return;
                 }
             }
             
             [self itemAtURL:newURL didMoveToURL:destinationURL];
             success = YES;
         }];
    } else {
        /*
         The NSFileCoordinator header says:
         
         "For another example, the most accurate and safe way to coordinate a move is to invoke -coordinateWritingItemAtURL:options:writingItemAtURL:options:error:byAccessor: using the NSFileCoordinatorWritingForMoving option with the source URL and NSFileCoordinatorWritingForReplacing with the destination URL."
         
         But we really don't want to replace the destination. If there is something there we want to error out. Additionally, NSFileCoordinator treats URLs case insensitively (even on a case-insenstive filesystem like iOS!) and will send -accommodatePresentedItemDeletionWithCompletionHandler: if you are doing a case-only rename ("foo" -> "Foo").

         */
        
        [self coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                        writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForMerging error:outError
                              byAccessor:
         ^(NSURL *newURL1, NSURL *newURL2){
             if (createIntermediateDirectories && !_ensureParentDirectory(destinationURL, outError)) {
                 OBChainError(outError);
                 return;
             }

                 NSError *moveError = nil;
             if (![[NSFileManager defaultManager] moveItemAtURL:newURL1 toURL:newURL2 error:&moveError]) {
                 //NSLog(@"Error moving %@ to %@: %@", newURL1, newURL2, [moveError toPropertyList]);
                 if (outError)
                     *outError = moveError;
                 return;
             }
             
             [self itemAtURL:sourceURL didMoveToURL:destinationURL];
             success = YES;
         }];
    }
    
    return success;
}

- (BOOL)moveItemAtURL:(NSURL *)sourceURL error:(NSError **)outError byAccessor:(NSURL * (^)(NSURL *newURL, NSError **outError))accessor;
{
    __block BOOL success = NO;
    [self coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving error:outError byAccessor:^(NSURL *newURL){
        NSURL *destinationURL = accessor(newURL, outError);
        if (!destinationURL)
            return;
        [self itemAtURL:newURL didMoveToURL:destinationURL];
        success = YES;
    }];
    return success;
}

- (BOOL)removeItemAtURL:(NSURL *)fileURL error:(NSError **)outError byAccessor:(BOOL (^)(NSURL *newURL, NSError **outError))accessor;
{
    __block BOOL success = NO;
    [self coordinateWritingItemAtURL:fileURL options:NSFileCoordinatorWritingForDeleting error:outError byAccessor:^(NSURL *newURL){
        success = accessor(newURL, outError);
    }];
    return success;
}

- (BOOL)readItemAtURL:(NSURL *)fileURL withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(BOOL (^)(NSURL *newURL, NSError **outError))accessor;
{
    __block BOOL success = NO;
    
    NSFileCoordinatorReadingOptions options = withChanges ? 0 : NSFileCoordinatorReadingWithoutChanges;
    [self coordinateReadingItemAtURL:fileURL options:options error:outError byAccessor:^(NSURL *newURL) {
        success = accessor(newURL, outError);
    }];
    return success;
}

- (BOOL)writeItemAtURL:(NSURL *)fileURL withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(BOOL (^)(NSURL *newURL, NSError **outError))accessor;
{
    __block BOOL success = NO;
    
    NSFileCoordinatorWritingOptions options = withChanges ? NSFileCoordinatorWritingForMerging : 0;
    [self coordinateWritingItemAtURL:fileURL options:options error:outError byAccessor:^(NSURL *newURL) {
        success = accessor(newURL, outError);
    }];
    return success;
}

- (BOOL)readItemAtURL:(NSURL *)readURL withChanges:(BOOL)readWithChanges
       writeItemAtURL:(NSURL *)writeURL withChanges:(BOOL)writeWithChanges
                error:(NSError **)outError byAccessor:(BOOL (^)(NSURL *newURL1, NSURL *newURL2, NSError **outError))accessor;
{
    NSFileCoordinatorReadingOptions readOptions = readWithChanges ? 0 : NSFileCoordinatorReadingWithoutChanges;
    NSFileCoordinatorWritingOptions writeOptions = writeWithChanges ? NSFileCoordinatorWritingForMerging : 0;

    __block BOOL success = NO;
    [self coordinateReadingItemAtURL:readURL options:readOptions
                    writingItemAtURL:writeURL options:writeOptions
                               error:outError byAccessor:
     ^(NSURL *newURL1, NSURL *newURL2){
         success = accessor(newURL1, newURL2, outError);
     }];
    
    return success;
}

- (BOOL)prepareToReadItemsAtURLs:(NSArray *)readingURLs withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(BOOL (^)(NSError **outError))accessor;
{
    __block BOOL success = NO;
    NSFileCoordinatorReadingOptions options = withChanges ? 0 : NSFileCoordinatorReadingWithoutChanges;
    [self prepareForReadingItemsAtURLs:readingURLs options:options writingItemsAtURLs:nil options:0 error:outError byAccessor:^(void (^completionHandler)(void)){
        success = accessor(outError);
        completionHandler();
    }];
    return success;
}

- (BOOL)prepareToWriteItemsAtURLs:(NSArray *)writingURLs withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(BOOL (^)(NSError **outError))accessor;
{
    __block BOOL success = NO;
    NSFileCoordinatorWritingOptions options = withChanges ? NSFileCoordinatorWritingForMerging : 0;
    [self prepareForReadingItemsAtURLs:nil options:0 writingItemsAtURLs:writingURLs options:options error:outError byAccessor:^(void (^completionHandler)(void)){
        success = accessor(outError);
        completionHandler();
    }];
    return success;
}

@end
