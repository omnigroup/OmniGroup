// Copyright 2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipRawFileMember.h>

#import <OmniUnzip/OUZipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUErrors.h>

RCS_ID("$Id$");

@implementation OUZipRawFileMember

- initWithName:(NSString *)name entry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;
{
    OBPRECONDITION(![NSString isEmptyString:name]);
    OBPRECONDITION(entry);
    OBPRECONDITION(archive);
    
    // TODO: OUUnzipEntry should have the date available.
    if (!(self = [super initWithName:name date:[NSDate date]]))
        return nil;
    
    _entry = [entry retain];
    _archive = [archive retain];
    
    return self;
}

- initWithEntry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;
{
    return [self initWithName:[entry name] entry:entry archive:archive];
}

- (void)dealloc;
{
    [_entry release];
    [_archive release];
    [super dealloc];
}

#pragma mark -
#pragma mark OUZipMember subclass

- (BOOL)appendToZipArchive:(OUZipArchive *)zip fileNamePrefix:(NSString *)fileNamePrefix error:(NSError **)outError;
{
    OMNI_POOL_START {
        NSData *rawData = [_archive dataForEntry:_entry raw:YES error:outError];
        if (!rawData) {
            OBASSERT(outError && *outError);
            return NO;
        }
        OBASSERT([rawData length] == [_entry compressedSize]);
        
        // TODO: propagate the data from the source zip file
        if (![zip appendEntryNamed:[self name] fileType:[_entry fileType] contents:rawData raw:YES compressionMethod:[_entry compressionMethod] uncompressedSize:[_entry uncompressedSize] crc:[_entry crc] date:[_entry date] error:outError])
            return NO;
    } OMNI_POOL_ERROR_END;
    
    return YES;
}

@end
