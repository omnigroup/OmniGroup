// Copyright 1997-2010, 2014 Omni Development, Inc. All rights reserved.
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
    CFErrorRef error = NULL;
    FILE *result = OFDataCreateReadOnlyStandardIOFile((__bridge CFDataRef)self, &error);
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        else if (error)
            CFRelease(error);
    }
    return result;
}

@end

@implementation NSMutableData (OFFileIO)

- (FILE *)openReadWriteStandardIOFile:(NSError **)outError;
{
    CFErrorRef error = NULL;
    FILE *result = OFDataCreateReadWriteStandardIOFile((__bridge CFMutableDataRef)self, &error);
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        else if (error)
            CFRelease(error);
    }
    return result;
}

@end
