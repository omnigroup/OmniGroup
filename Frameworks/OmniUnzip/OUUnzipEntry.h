// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSDate;

@interface OUUnzipEntry : NSObject

- initWithName:(NSString *)name fileType:(NSString *)fileType date:(NSDate *)date positionInFile:(unsigned long)positionInFile fileNumber:(unsigned long)fileNumber compressionMethod:(unsigned long)compressionMethod compressedSize:(size_t)compressedSize uncompressedSize:(size_t)uncompressedSize crc:(unsigned long)crc;

@property(nonatomic,readonly) NSString *name;
@property(nonatomic,readonly) NSString *fileType;
@property(nonatomic,readonly) NSDate *date;
@property(nonatomic,readonly) unsigned long positionInFile;
@property(nonatomic,readonly) unsigned long fileNumber;
@property(nonatomic,readonly) unsigned long compressionMethod;
@property(nonatomic,readonly) size_t compressedSize;
@property(nonatomic,readonly) size_t uncompressedSize;
@property(nonatomic,readonly) unsigned long crc;

// YES if compressionMethod == Z_DEFLATE (without having to publish that #define)
@property(nonatomic,readonly) BOOL compressedWithDeflate;

@end

NS_ASSUME_NONNULL_END
