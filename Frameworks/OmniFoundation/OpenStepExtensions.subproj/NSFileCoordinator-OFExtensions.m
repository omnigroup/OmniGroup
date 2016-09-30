// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation NSFileCoordinator (OFExtensions)

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
- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL createIntermediateDirectories:(BOOL)createIntermediateDirectories error:(NSError **)outError success:(void (^ _Nullable)(NSURL *resultURL))successHandler;
{
    __block BOOL success = NO;

    /*
     The NSFileCoordinator header says:
     
     "For another example, the most accurate and safe way to coordinate a move is to invoke -coordinateWritingItemAtURL:options:writingItemAtURL:options:error:byAccessor: using the NSFileCoordinatorWritingForMoving option with the source URL and NSFileCoordinatorWritingForReplacing with the destination URL."
     
     But we really don't want to replace the destination (and on OS X 10.9 and iOS 7.0, a case-only rename would provoke -accommodatePresentedItemDeletionWithCompletionHandler: since the destination 'exists' -- haven't retested this bit on 10.10/8.0 since we pass NSFileCoordinatorWritingForMerging now).
     
     NOTE: Case-only renames were very busted in OS X 10.9 and iOS 7.0. In 10.10 and 8.0 they are better. But, file presenters still get the wrong sequence of notifications. No -presentedSubitemAtURL:didMoveToURL: is sent at all in a case-only rename, but a couple 'did change' messages are sent.
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

         if (successHandler)
             successHandler(destinationURL);
         
         [self itemAtURL:sourceURL didMoveToURL:destinationURL];
         
         success = YES;
    }];
    
    return success;
}

- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL createIntermediateDirectories:(BOOL)createIntermediateDirectories error:(NSError **)outError;
{
    return [self moveItemAtURL:sourceURL toURL:destinationURL createIntermediateDirectories:createIntermediateDirectories error:outError success:nil];
}

- (BOOL)moveItemAtURL:(NSURL *)sourceURL error:(NSError **)outError byAccessor:(nullable NSURL * (^)(NSURL *newURL, NSError **outError))accessor;
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

- (BOOL)removeItemAtURL:(NSURL *)fileURL error:(NSError **)outError byAccessor:(OFFileAccessor)accessor;
{
    __block BOOL success = NO;
    [self coordinateWritingItemAtURL:fileURL options:NSFileCoordinatorWritingForDeleting error:outError byAccessor:^(NSURL *newURL){
        success = accessor(newURL, outError);
    }];
    return success;
}

- (BOOL)readItemAtURL:(NSURL *)fileURL withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(OFFileAccessor)accessor;
{
    __block BOOL success = NO;
    
    NSFileCoordinatorReadingOptions options = withChanges ? 0 : NSFileCoordinatorReadingWithoutChanges;
    [self coordinateReadingItemAtURL:fileURL options:options error:outError byAccessor:^(NSURL *newURL) {
        success = accessor(newURL, outError);
    }];
    return success;
}

- (BOOL)writeItemAtURL:(NSURL *)fileURL withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(OFFileAccessor)accessor;
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
    [self prepareForReadingItemsAtURLs:readingURLs options:options writingItemsAtURLs:@[] options:0 error:outError byAccessor:^(void (^completionHandler)(void)){
        success = accessor(outError);
        completionHandler();
    }];
    return success;
}

- (BOOL)prepareToWriteItemsAtURLs:(NSArray *)writingURLs withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(BOOL (^)(NSError **outError))accessor;
{
    __block BOOL success = NO;
    NSFileCoordinatorWritingOptions options = withChanges ? NSFileCoordinatorWritingForMerging : 0;
    [self prepareForReadingItemsAtURLs:@[] options:0 writingItemsAtURLs:writingURLs options:options error:outError byAccessor:^(void (^completionHandler)(void)){
        success = accessor(outError);
        completionHandler();
    }];
    return success;
}

@end

NS_ASSUME_NONNULL_END
