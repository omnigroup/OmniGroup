// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSData.h>
#import <CoreFoundation/CFData.h>

/* This decompresses the XZ-formatted data in 'compressed' and writes it to 'fd'. All operations are performed on the given queue. When done, the completion handler is called (with nil upon success, or an NSError upon failure). It's probably called on 'queue' but might not be. */
void OFXZDecompressToFdAsync(NSData *compressed, int fd, dispatch_queue_t queue, void(^completion_handler)(NSError *));

