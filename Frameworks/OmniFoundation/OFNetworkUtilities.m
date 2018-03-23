// Copyright 2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFNetworkUtilities.h"

@import OmniBase;

#include <fcntl.h>
#include <sys/socket.h>

RCS_ID("$Id$")

int OFSocketConnectedToPath(NSString *path, BOOL synchronous, NSError **outError)
{
    int fd = socket(PF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        if (outError)
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return -1;
    }
    
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    
    if (!synchronous) {
        if (fcntl(fd, F_SETFL, O_NONBLOCK) < 0) {
            goto fail_with_errno;
        }
    }
    
    const int one = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one))) {
        goto fail_with_errno;
    }
    
    struct sockaddr_un sun;
    socklen_t slen = OFFillSockaddrForPath(&sun, path);
    if (slen <= 0 || connect(fd, (struct sockaddr *)&sun, slen)) {
        goto fail_with_errno;
    }
    
    return fd;
    
fail_with_errno:
    if (outError)
        *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    close(fd);
    return -1;
}

