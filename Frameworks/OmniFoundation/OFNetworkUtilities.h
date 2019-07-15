// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <stddef.h>
#import <sys/un.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSPort.h>
#import <netinet/in.h>

static inline socklen_t OFFillSockaddrForPath(struct sockaddr_un * __nonnull sa, NSString * __nonnull path)
{
    bzero(sa, sizeof(*sa));
    sa->sun_family = AF_UNIX;
    
    if (![path getFileSystemRepresentation:sa->sun_path maxLength:sizeof(sa->sun_path)]) {
        errno = ENAMETOOLONG;
        return 0;
    }
    
    /* We should theoretically set sun_len here, but it's not used on most systems, including Darwin (in the kernel, the length field is reset to be the socklen passed to connect()/bind()). */

    return (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(sa->sun_path));
}

int OFSocketConnectedToPath(NSString * __nonnull path, BOOL synchronous, OBNSErrorOutType outError)
    CF_SWIFT_NAME(SocketConnectedTo(path:synchronous:error:));

static inline in_port_t OFSocketPortGetPort(NSSocketPort * __nonnull socketPort) {
    struct sockaddr_in addr;
    bzero(&addr, sizeof(addr));
    NSData *address = socketPort.address;
    size_t length = MIN([address length], sizeof(addr));
    [address getBytes:&addr length:length];
    return ntohs(addr.sin_port);
}

