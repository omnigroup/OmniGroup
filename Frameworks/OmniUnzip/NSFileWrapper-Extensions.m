// Copyright 2016 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/NSFileWrapper-Extensions.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUZipArchive.h>

#import <OmniFoundation/OFByteProviderProtocol.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation NSFileWrapper (OmniUnzipExtensions)

- (nullable NSFileWrapper *)zippedFileWrapper:(NSError **)outError;
{
    NSData *zippedData = [OUZipArchive zipDataFromFileWrappers:self.fileWrappers.allValues error:outError];
    OBASSERT(zippedData);

    if (!zippedData) {
        return nil;
    }

    return [[NSFileWrapper alloc] initRegularFileWithContents:zippedData];
}

- (nullable NSFileWrapper *)unzippedFileWrapperWithError:(NSError **)outError;
{
    if (!self.isRegularFile) {
        if (outError)
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                            code: self.isDirectory ? EISDIR : ENODEV
                                        userInfo:nil];
        return nil;
    }
    
    OUUnzipArchive *unzipArchive;
    
    NSData *zippedData = [self regularFileContents];
    if (!zippedData) {
        if (outError)
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
        return nil;
    }
    
    unzipArchive = [[OUUnzipArchive alloc] initWithPath:nil data:zippedData description:[self filename] error:outError];
    if (!unzipArchive) {
        return nil;
    }
    
    return [unzipArchive fileWrapperWithTopLevelWrapper:YES error:outError];
}

@end

NS_ASSUME_NONNULL_END
