// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniFileStore/OFSFileManagerAsynchronousReadTarget.h>

extern NSInteger OFSFileManagerDebug;

@interface OFSFileManager : NSObject
{
@private
    NSURL *_baseURL;
}

+ (Class)fileManagerClassForURLScheme:(NSString *)scheme;

- initWithBaseURL:(NSURL *)baseURL error:(NSError **)outError;

- (NSURL *)baseURL;

- (id)asynchronousReadContentsOfURL:(NSURL *)url forTarget:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;
- (id)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically forTarget:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;

@end

@class OFSFileInfo;

@protocol OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;

- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;

// Returns an array of OFSFileInfos for the immediate children of the given URL.  The results are in no particular order.
- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;

- (BOOL)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;

- (BOOL)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;

- (BOOL)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;

@end

// Any file mananger returned from -initWithBaseURL:error: will be concrete, so just fake up a declaration that they all are
@interface OFSFileManager (OFSConcreteFileManager) <OFSConcreteFileManager>
@end

