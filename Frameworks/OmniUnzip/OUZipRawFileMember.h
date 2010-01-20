// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUnzip/OUZipMember.h>

@class OUUnzipEntry, OUUnzipArchive;

@interface OUZipRawFileMember : OUZipMember
{
@private
    OUUnzipEntry *_entry;
    OUUnzipArchive *_archive;
}

- initWithName:(NSString *)name entry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;
- initWithEntry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;

@property(readonly) OUUnzipArchive *archive;
@property(readonly) OUUnzipEntry *entry;

@end
