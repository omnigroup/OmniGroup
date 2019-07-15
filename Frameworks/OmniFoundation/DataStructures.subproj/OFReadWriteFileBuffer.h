// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <CoreFoundation/CFError.h>
#import <CoreFoundation/CFData.h>
#import <stdio.h>

typedef struct _OFReadWriteFileBuffer OFReadWriteFileBuffer;
extern OFReadWriteFileBuffer *OFCreateReadWriteFileBuffer(FILE **outFile, CFErrorRef *outError);
extern void OFDestroyReadWriteFileBuffer(OFReadWriteFileBuffer *buffer, CFAllocatorRef dataAllocator, CFDataRef *outData);
