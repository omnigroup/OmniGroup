// Copyright 2008, 2010, 2013 Omni Development, Inc. All rights reserved.
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

- initWithName:(NSString *)name entry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;
- initWithEntry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;

@property(nonatomic,readonly) OUUnzipArchive *archive;
@property(nonatomic,readonly) OUUnzipEntry *entry;

@end
