// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUUnzipEntry.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>

RCS_ID("$Id$");

@implementation OUUnzipEntry

- initWithName:(NSString *)name fileType:(NSString *)fileType date:(NSDate *)date positionInFile:(unsigned long)positionInFile fileNumber:(unsigned long)fileNumber compressionMethod:(unsigned long)compressionMethod compressedSize:(size_t)compressedSize uncompressedSize:(size_t)uncompressedSize crc:(unsigned long)crc;
{
    OBPRECONDITION([name length] > 0);
    OBPRECONDITION(positionInFile > 0); // would be the zip header...
    
    if (!(self = [super init]))
        return nil;
    
    _name = [name copy];
    _fileType = [fileType copy];
    _date = [date copy];
    _positionInFile = positionInFile;
    _fileNumber = fileNumber;
    _compressionMethod = compressionMethod;
    _compressedSize = compressedSize;
    _uncompressedSize = uncompressedSize;
    _crc = crc;
    
    return self;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' offset:%lu file number:%lu>", NSStringFromClass([self class]), self, _name, _positionInFile, _fileNumber];
}

- (NSString *)debugDescription;
{
    return [self shortDescription];
}

@end
