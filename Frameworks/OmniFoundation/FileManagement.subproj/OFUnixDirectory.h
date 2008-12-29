// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFUnixDirectory.h 103776 2008-08-06 01:00:30Z wiml $

#import <OmniFoundation/OFDirectory.h>

@interface OFUnixDirectory : OFDirectory
{
    NSMutableArray *files;
}

- (void)scanDirectory;
- (BOOL)copyToPath:(NSString *)destinationPath error:(NSError **)outError;

@end

extern NSString * const OFUnixDirectoryCannotReadDirectoryException;
