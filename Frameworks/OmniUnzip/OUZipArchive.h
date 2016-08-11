// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSFileWrapper;
@protocol OFByteAcceptor;

NS_ASSUME_NONNULL_BEGIN

@interface OUZipArchive : OFObject

+ (BOOL)createZipFile:(NSString *)zipPath fromFilesAtPaths:(NSArray <NSString *> *)paths error:(NSError **)outError;
+ (BOOL)createZipFile:(NSString *)zipPath fromFileWrappers:(NSArray <NSFileWrapper *> *)fileWrappers error:(NSError **)outError;
+ (NSData * _Nullable)zipDataFromFileWrappers:(NSArray <NSFileWrapper *> *)fileWrappers error:(NSError **)outError;

- (instancetype _Nullable)initWithPath:(NSString *)path error:(NSError **)outError;
- (instancetype _Nullable)initWithByteAcceptor:(NSObject <OFByteAcceptor> *)fh error:(NSError **)outError;

- (BOOL)appendEntryNamed:(NSString *)name fileType:(NSString *)fileType contents:(NSData *)contents raw:(BOOL)raw compressionMethod:(unsigned long)comparessionMethod uncompressedSize:(size_t)uncompressedSize crc:(unsigned long)crc date:(NSDate * _Nullable)date error:(NSError **)outError;
- (BOOL)appendEntryNamed:(NSString *)name fileType:(NSString *)fileType contents:(NSData *)contents date:(NSDate * _Nullable)date error:(NSError **)outError;

- (BOOL)close:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
