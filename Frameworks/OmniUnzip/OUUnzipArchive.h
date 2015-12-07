// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray, NSData, NSError;
@class OUUnzipEntry;
@protocol OFByteProvider;

@interface OUUnzipArchive : NSObject

- initWithPath:(NSString *)path error:(NSError **)outError;
- initWithPath:(NSString *)path data:(NSObject <OFByteProvider> * _Nullable)store error:(NSError **)outError;

@property (readonly, nonatomic) NSString *path;
@property (readonly, nonatomic) NSArray <OUUnzipEntry *> *entries;

- (OUUnzipEntry * _Nullable)entryNamed:(NSString *)name;
- (NSArray <OUUnzipEntry *> *)entriesWithNamePrefix:(NSString * _Nullable)prefix;

- (NSData * _Nullable)dataForEntry:(OUUnzipEntry *)entry raw:(BOOL)raw error:(NSError **)outError;
- (NSData * _Nullable)dataForEntry:(OUUnzipEntry *)entry error:(NSError **)outError;

// Convenience methods for unarchiving to disk
- (BOOL)unzipArchiveToURL:(NSURL *)targetURL error:(NSError **)outError;

// Writes all entries prefixed with "name" to temp.
- (NSURL * _Nullable)URLByWritingTemporaryCopyOfTopLevelEntryNamed:(NSString *)name error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
