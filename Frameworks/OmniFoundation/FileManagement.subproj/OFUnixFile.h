// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFUnixFile.h 103776 2008-08-06 01:00:30Z wiml $

#import <OmniFoundation/OFFile.h>

typedef enum {
    OFFILETYPE_DIRECTORY, OFFILETYPE_CHARACTER, OFFILETYPE_BLOCK, OFFILETYPE_REGULAR, OFFILETYPE_SOCKET
} OFFileType;

@interface OFUnixFile : OFFile
{
    BOOL hasInfo, symLink;
    OFFileType fileType;
    NSNumber *size;
    NSCalendarDate *lastChanged;
}

- (NSString *)shortcutDestination;
- (BOOL)copyToPath:(NSString *)destinationPath error:(NSError **)outError;

@end

extern NSString * const OFUnixFileGenericFailureException;
