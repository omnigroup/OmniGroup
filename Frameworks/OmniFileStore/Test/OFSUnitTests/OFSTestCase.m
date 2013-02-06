// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSTestCase.h"

#import <readpassphrase.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <sys/socket.h>
#import <sys/types.h>
#import <netdb.h>

RCS_ID("$Id$")

@implementation OFSTestCase
{
    NSString *_username;
    NSString *_password;
}

static NSUInteger NextUsernameNumber = 0;
static const NSUInteger UsernameCount = 100;

- (void)setUp;
{
    [super setUp];

    const char *env;
    
    if ((env = getenv("OFSAccountUsername")))
        _username = [NSString stringWithUTF8String:env];
    if ([NSString isEmptyString:_username])
        [NSException raise:NSGenericException reason:@"OFSAccountUsername not specified in environment"];
    _username = [_username stringByAppendingFormat:@"%ld", NextUsernameNumber];
    
    if ((env = getenv("OFSAccountPassword")))
        _password = [NSString stringWithUTF8String:env];
    if ([NSString isEmptyString:_password])
        [NSException raise:NSGenericException reason:@"OFSAccountPassword not specified in environment"];

    // This requires that subclasses call [super setUp] before they call -accountRemoteBaseURL or -accountCredential
    NextUsernameNumber++;
    if (NextUsernameNumber >= UsernameCount)
        NextUsernameNumber = 0;
}

- (void)tearDown;
{
    _username = nil;
    _password = nil;
    
    [super tearDown];
}

- (NSURL *)accountRemoteBaseURL;
{
    OBPRECONDITION(_username); // Only call after -setUp
    OBPRECONDITION(_password);

    const char *env = getenv("OFSAccountRemoteBaseURL");
    if (!env)
        [NSException raise:NSGenericException format:@"OFSAccountRemoteBaseURL must be set"];
    
    NSURL *remoteBaseURL = [NSURL URLWithString:[NSString stringWithUTF8String:env]];
    if (!remoteBaseURL)
        [NSException raise:NSGenericException format:@"OFSAccountRemoteBaseURL set to an invalid URL"];
    
    return [remoteBaseURL URLByAppendingPathComponent:_username isDirectory:YES];
}

- (NSURLCredential *)accountCredential;
{
    OBPRECONDITION(_username); // Only call after -setUp
    OBPRECONDITION(_password);
    
    return [[NSURLCredential alloc] initWithUser:_username password:_password persistence:NSURLCredentialPersistenceNone];
}

// Horrifying attempt to defeat NSURLConnection's lack of API to close connections to https servers when credentials are removed.

typedef union {
    struct sockaddr generic;
    struct sockaddr_in in4;
    struct sockaddr_in6 in6;
} GenericAddress;

static void _closeIfMatchesAddress(int fd, GenericAddress addr, in_port_t port, socklen_t len, struct addrinfo *addresses)
{
    for (struct addrinfo *a = addresses; a; a = a->ai_next) {
        if (a->ai_addrlen != len)
            continue;
        
        GenericAddress *targetAddress = (GenericAddress *)a->ai_addr;
        
        // Socket to the specified host... does it have the right port?
        if (a->ai_family == AF_INET && memcmp(&targetAddress->in4.sin_addr, &addr.in4.sin_addr, sizeof(addr.in4.sin_addr)) == 0) {
            if (ntohs(addr.in4.sin_port) == port) {
                fprintf(stderr, "  closing IPv4 socket at fd %d\n", fd);
                close(fd);
                return;
            }
        } else if (a->ai_family == AF_INET6 && memcmp(&targetAddress->in6.sin6_addr, &addr.in6.sin6_addr, sizeof(addr.in6.sin6_addr)) == 0) {
            if (ntohs(addr.in6.sin6_port) == port) {
                fprintf(stderr, "  closing IPv6 socket at fd %d\n", fd);
                close(fd);
                return;
            }
        } else {
            fprintf(stderr, "   unknown address family %d\n", a->ai_family);
        }
    }
}

- (void)closeSocketsConnectedToURL:(NSURL *)url;
{
    NSLog(@"scanning for %d sockets for connections to %@", FD_SETSIZE, url);
    
    struct addrinfo hints = {0};
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    
    struct addrinfo *addresses = NULL;
    
    in_port_t port = [[url port] shortValue];
    
    int rc = getaddrinfo([[url host] UTF8String], NULL/*service*/, &hints, &addresses);
    if (rc < 0) {
        fprintf(stderr, "getaddrinfo -> %d %s\n", errno, strerror(errno));
        return;
    }
    
    for (int fd = 0; fd < FD_SETSIZE; fd++) {
        GenericAddress addr;
        socklen_t len;
        
        memset(&addr, 0, sizeof(addr));
        len = sizeof(addr);
        rc = getsockname(fd, &addr.generic, &len);
        if (rc < 0) {
            if (errno == EBADF || errno == ENOTSOCK)
                continue; // Not a valid file descriptor or is, but isn't a socket
            
            if (errno == EOPNOTSUPP)
                continue; // unbound/datagram
            
            fprintf(stderr, "getsockname(%d) -> %d %s\n", fd, errno, strerror(errno));
            continue;
        }
        
        if (addr.generic.sa_family == AF_UNIX)
            continue;

        //fprintf(stderr, "%d is a socket\n", fd);
        rc = getpeername(fd, &addr.generic, &len);
        if (rc < 0) {
            fprintf(stderr, "getpeername(%d) -> %d %s\n", fd, errno, strerror(errno));
            continue;
        }
        
        _closeIfMatchesAddress(fd, addr, port, len, addresses);
    }
    
    freeaddrinfo(addresses);

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    
    NSLog(@"done");
}

@end
