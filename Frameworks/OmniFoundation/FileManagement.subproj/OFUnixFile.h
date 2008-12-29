// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
