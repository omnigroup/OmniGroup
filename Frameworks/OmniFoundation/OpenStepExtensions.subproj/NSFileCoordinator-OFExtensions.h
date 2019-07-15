// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileCoordinator.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^OFFileAccessor)(NSURL *newURL, NSError **outError);

@interface NSFileCoordinator (OFExtensions)

// NOTE: Due to bugs in NSFileCoordination, if you are doing case-only renames, your file presenter WILL NOT get notified of the rename (on any file system type), but will just get a generic 'changed' event. This means it is safest to (1) always pass a filePresenter to the coordination created for doing renames and notify it yourself and (2) only have one file presenter per URL (since only one presenter can be thus registered).
// The success handler will be called at the end of the move, passing in the resulting URL (possibly in a temporary location).
- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL createIntermediateDirectories:(BOOL)createIntermediateDirectories error:(NSError **)outError success:(void (NS_NOESCAPE ^ _Nullable)(NSURL *resultURL))successHandler;
- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL createIntermediateDirectories:(BOOL)createIntermediateDirectories error:(NSError **)outError; // Passes nil for successHandler

// A coordinated move of the source to some uncoordinated location (like a temporary folder or trash). The accessor should NOT call -itemAtURL:didMoveToURL:. It will be called by this method, based on the returned URL.
- (BOOL)moveItemAtURL:(NSURL *)sourceURL error:(NSError **)outError byAccessor:(nullable NSURL * (NS_NOESCAPE ^)(NSURL *newURL, NSError **outError))accessor;

- (BOOL)removeItemAtURL:(NSURL *)fileURL error:(NSError **)outError byAccessor:(NS_NOESCAPE OFFileAccessor)accessor;

- (BOOL)readItemAtURL:(NSURL *)fileURL withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(NS_NOESCAPE OFFileAccessor)accessor;
- (BOOL)writeItemAtURL:(NSURL *)fileURL withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(NS_NOESCAPE OFFileAccessor)accessor;

- (BOOL)readItemAtURL:(NSURL *)readURL withChanges:(BOOL)readWithChanges
       writeItemAtURL:(NSURL *)writeURL withChanges:(BOOL)writeWithChanges
                error:(NSError **)outError byAccessor:(BOOL (NS_NOESCAPE ^)(NSURL *newURL1, NSURL *newURL2, NSError **outError))accessor;

- (BOOL)prepareToReadItemsAtURLs:(NSArray<NSURL *> *)readingURLs withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(BOOL (NS_NOESCAPE ^)(NSError **outError))accessor;
- (BOOL)prepareToWriteItemsAtURLs:(NSArray<NSURL *> *)writingURLs withChanges:(BOOL)withChanges error:(NSError **)outError byAccessor:(BOOL (NS_NOESCAPE ^)(NSError **outError))accessor;

@end

NS_ASSUME_NONNULL_END
