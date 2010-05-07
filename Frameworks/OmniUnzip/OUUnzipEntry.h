// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSDate;

@interface OUUnzipEntry : OFObject
{
    NSString *_name;
    NSString *_fileType;
    NSDate *_date;
    unsigned long _positionInFile;
    unsigned long _fileNumber;
    size_t _compressedSize;
    size_t _uncompressedSize;
    unsigned long _compressionMethod;
    unsigned long _crc;
}

- initWithName:(NSString *)name fileType:(NSString *)fileType date:(NSDate *)date positionInFile:(unsigned long)positionInFile fileNumber:(unsigned long)fileNumber compressionMethod:(unsigned long)compressionMethod compressedSize:(size_t)compressedSize uncompressedSize:(size_t)uncompressedSize crc:(unsigned long)crc;

- (NSString *)name;
- (NSString *)fileType;
- (NSDate *)date;
- (unsigned long)positionInFile;
- (unsigned long)fileNumber;
- (unsigned long)compressionMethod;
- (size_t)compressedSize;
- (size_t)uncompressedSize;
- (unsigned long)crc;

@end
