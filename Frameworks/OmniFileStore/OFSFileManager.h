// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniFileStore/OFSFileManagerAsynchronousOperationTarget.h>
#import <OmniFileStore/OFSAsynchronousOperation.h>

extern NSInteger OFSFileManagerDebug;

// intentionally similar to NSFileManager NSDirectoryEnumerationOptions
enum {
    OFSDirectoryEnumerationSkipsSubdirectoryDescendants = 1UL << 0,     /* shallow, non-deep */
    /* OFSDirectoryEnumerationSkipsPackageDescendants = 1UL << 1, */    /* no package contents, not currently supported */
    OFSDirectoryEnumerationSkipsHiddenFiles = 1UL << 2,                 /* no hidden files */
    OFSDirectoryEnumerationForceRecursiveDirectoryRead = 1UL << 3,       /* useful when the server does not implement PROPFIND requests with Depth:infinity */
};
typedef NSUInteger OFSDirectoryEnumerationOptions;


@interface OFSFileManager : NSObject
{
@private
    NSURL *_baseURL;
}

+ (Class)fileManagerClassForURLScheme:(NSString *)scheme;

- initWithBaseURL:(NSURL *)baseURL error:(NSError **)outError;

- (NSURL *)baseURL;

- (id <OFSAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url withTarget:(id <OFSFileManagerAsynchronousOperationTarget>)target;
- (id <OFSAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically withTarget:(id <OFSFileManagerAsynchronousOperationTarget>)target;

- (NSURL *)availableURL:(NSURL *)startingURL;

@end

@class OFSFileInfo;

@protocol OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;

// Returns an OFSFileInfo. If we determine that the file does not exist, returns an OFSFileInfo with exists=NO.
- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;

// For the following methods, a few underlying scheme-specific errors are translated/wrapped into XMLData error codes for consistency:
//   Directory operation on nonexistent directory  -->  OFSNoSuchDirectory
// 

// Returns an array of OFSFileInfos for the immediate children of the given URL.  The results are in no particular order.
// Returns nil and sets *outError if the URL does not refer to a directory/folder/collection (among other possible reasons).
- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;
- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;  // passes OFSDirectoryEnumerationSkipsSubdirectoryDescendants for option

// As above, but with extension=nil (matches all files) and collecting information about redirects encountered on the way.
- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options error:(NSError **)outError;

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;

- (BOOL)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;

@end

// Any file mananger returned from -initWithBaseURL:error: will be concrete, so just fake up a declaration that they all are
@interface OFSFileManager (OFSConcreteFileManager) <OFSConcreteFileManager>
@end

extern void OFSFileManagerSplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter);

