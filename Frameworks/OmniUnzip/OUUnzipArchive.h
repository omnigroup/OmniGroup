// Copyright 2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray, NSData, NSError;
@class OUUnzipEntry;
@protocol OFByteProvider;

@interface OUUnzipArchive : OFObject
{
    NSString *_path;
    NSObject <OFByteProvider> *_store;
    NSArray *_entries;
}

- initWithPath:(NSString *)path error:(NSError **)outError;
- initWithPath:(NSString *)path data:(NSObject <OFByteProvider> *)store error:(NSError **)outError;

@property (readonly, nonatomic) NSString *path;
@property (readonly, nonatomic) NSArray *entries;

- (OUUnzipEntry *)entryNamed:(NSString *)name;
- (NSArray *)entriesWithNamePrefix:(NSString *)prefix;

- (NSData *)dataForEntry:(OUUnzipEntry *)entry raw:(BOOL)raw error:(NSError **)outError;
- (NSData *)dataForEntry:(OUUnzipEntry *)entry error:(NSError **)outError;

// Convenience methods for unarchiving to disk
- (BOOL)unzipArchiveToURL:(NSURL *)targetURL error:(NSError **)outError;

// Writes all entries prefixed with "name" to temp.
- (NSURL *)URLByWritingTemporaryCopyOfTopLevelEntryNamed:(NSString *)name error:(NSError **)outError;

@end
