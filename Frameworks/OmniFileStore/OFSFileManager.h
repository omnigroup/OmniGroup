// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSMutableArray;

@class OBLogger;
@protocol ODAVAsynchronousOperation;
@class ODAVFileInfo;
@protocol OFByteProvider;

// levels: 1=extra debug info, 2=operation logging, 3=errors only
extern OBLogger *OFSFileManagerLogger;

@protocol OFSFileManagerDelegate;

@interface OFSFileManager : NSObject

+ (Class)fileManagerClassForURLScheme:(NSString *)scheme;

- initWithBaseURL:(NSURL *)baseURL delegate:(id <OFSFileManagerDelegate>)delegate error:(NSError **)outError;

@property(nonatomic,readonly) NSURL *baseURL;
@property(nonatomic,weak,readonly) id <OFSFileManagerDelegate> delegate;
@property(nonatomic,readonly) NSString *locationDescription;
@property(nonatomic,copy) NSString *operationReason;

- (void)invalidate;

- (id <ODAVAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url;
- (id <ODAVAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url;
- (id <ODAVAsynchronousOperation>)asynchronousDeleteFile:(ODAVFileInfo *)f;

- (NSURL *)createDirectoryAtURLIfNeeded:(NSURL *)directoryURL error:(NSError **)outError;

@end

@protocol OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;

// Returns an ODAVFileInfo. If we determine that the file does not exist, returns an ODAVFileInfo with exists=NO.
- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;

// For the following methods, a few underlying scheme-specific errors are translated/wrapped into XMLData error codes for consistency:
//   Directory operation on nonexistent directory  -->  OFSNoSuchDirectory
// 

// Returns an array of ODAVFileInfos for the immediate children of the given URL.  The results are in no particular order.
// Returns nil and sets *outError if the URL does not refer to a directory/folder/collection (among other possible reasons).
- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;

// Returns an array of ODAVFileInfos for the immediate children of the given URL.  The results are in no particular order. Also returns an approximation of the current machine date at the time of the request via `outMachineDate`.
// Returns nil and sets *outError if the URL does not refer to a directory/folder/collection (among other possible reasons).
- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections machineDate:(NSDate **)outMachineDate error:(NSError **)outError;

// Only published since OmniFocus was using this method on a generic OFSFileManager (for test cases that run vs. file: URLs). Once we switch that to always using DAV, this could go away
- (NSMutableArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections error:(NSError **)outError;

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;

// Failure due to the URL not existing will be mapped to OFSNoSuchFile (with an underlying Cocoa/POSIX or HTTP error).
- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
- (BOOL)deleteFile:(ODAVFileInfo *)fileinfo error:(NSError **)outError;

@optional

- (NSURL *)writeData:(NSData *)data atomicallyReplacing:(ODAVFileInfo *)destination error:(NSError **)outError;

- (id <ODAVAsynchronousOperation>)asynchronousReadContentsOfFile:(ODAVFileInfo *)f range:(NSString *)range;

- (NSObject <OFByteProvider> *)byteProviderWithContentsOfURL:(NSURL *)url error:(NSError **)outError;

@end

// Any file mananger returned from -initWithBaseURL:error: will be concrete, so just fake up a declaration that they all are
@interface OFSFileManager (OFSConcreteFileManager) <OFSConcreteFileManager>
@end

extern void OFSFileManagerSplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter); // just calls -[NSString splitName:andCounter:]

