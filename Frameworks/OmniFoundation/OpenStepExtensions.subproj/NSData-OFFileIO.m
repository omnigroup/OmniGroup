// Copyright 1997-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFFileIO.h>

#import <OmniFoundation/CFData-OFFileIO.h>
#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation NSData (OFFileIO)

- (FILE *)openReadOnlyStandardIOFile:(NSError **)outError;
{
    FILE *result = OFDataCreateReadOnlyStandardIOFile((CFDataRef)self, (CFErrorRef *)outError);
    if (!result && outError)
        [(id)*outError autorelease];
    return result;
}

@end

@implementation NSMutableData (OFFileIO)

- (FILE *)openReadWriteStandardIOFile:(NSError **)outError;
{
    FILE *result = OFDataCreateReadWriteStandardIOFile((CFMutableDataRef)self, (CFErrorRef *)outError);
    if (!result && outError)
        [(id)*outError autorelease];
    return result;
}

@end
