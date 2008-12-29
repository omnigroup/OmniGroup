// Copyright 1997-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniNetworking/OmniNetworking.h>

RCS_ID("$Id$")

volatile void usage(const char *pgm)
{
    fprintf(stderr, "usage: %s [-send tcp-host | -receive] tcp-port\n", pgm);
    exit(1);
}

static void _sendLoop(ONHostAddress *hostAddress, unsigned short port);
static void _receiveLoop(ONHostAddress *hostAddress, unsigned short port);

int main (int argc, const char *argv[])
{
    NSAutoreleasePool *pool;
    BOOL isSending = NO;
    NSString *hostName;
    unsigned short hostPort;
    ONHostAddress *hostAddress;
    ONHost *host;
    
    pool = [[NSAutoreleasePool alloc] init];

    if (argc < 2)
        usage(argv[0]);

    if (!strcmp("-send", argv[1])) {
        if (argc != 4)
            usage(argv[0]);

        hostName = [[NSString alloc] initWithCString:argv[2]];
        hostPort = atoi(argv[3]);
        isSending = YES;
    } else if (!strcmp("-receive", argv[1])) {
        if (argc != 3)
            usage(argv[0]);

        hostName = [ONHost localHostname];
        hostPort = atoi(argv[2]);
        isSending = NO;
    } else {
        usage(argv[0]);
        return 1;
    }



    host = [ONHost hostForHostname:hostName];
    if (![[host addresses] count]) {
        fprintf(stderr, "Cannot determine an address for %s\n", argv[2]);
        exit(1);
    }

    hostAddress = [[host addresses] objectAtIndex:0];

    if (isSending)
        _sendLoop(hostAddress, hostPort);
    else
        _receiveLoop(hostAddress, hostPort);
    
    [pool release];
    exit(0);       // insure the process exit status is 0
    return 0;      // ...and make main fit the ANSI spec.
}

static void _sendLoop(ONHostAddress *hostAddress, unsigned short port)
{
    NSFileHandle *stdinHandle;
    NSData *data;
    ONTCPSocket *tcpSocket;

    tcpSocket = (ONTCPSocket *)[ONTCPSocket socket];
    [tcpSocket connectToAddress:hostAddress port:port];
    
    stdinHandle = [NSFileHandle fileHandleWithStandardInput];

    while (YES) {
        NSAutoreleasePool *pool;

        pool = [[NSAutoreleasePool alloc] init];

        data = [stdinHandle availableData];

        // NSFileHandle will return an empty data upon EOF rather than nil.
        // Note that if you try to read past the end of file on a file handle, it can hang in read() forever waiting for that additional data (at least, in OPENSTEP 4.2).
        if ([data length] == 0)
            break;

        [tcpSocket writeData:data];
        [pool release];
    }
}

static void _receiveLoop(ONHostAddress *hostAddress, unsigned short port)
{
    NSFileHandle *stdoutHandle;
    ONTCPSocket *serverTCPSocket, *connectionTCPSocket;

    serverTCPSocket = (ONTCPSocket *)[ONTCPSocket tcpSocket];
    [serverTCPSocket startListeningOnLocalPort:port allowingAddressReuse:YES];

    stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];

    while (YES) {
        NSAutoreleasePool *pool;

        pool = [[NSAutoreleasePool alloc] init];

        connectionTCPSocket = [serverTCPSocket acceptConnectionOnNewSocket];
        NSLog(@"Accepted connection from host %@", [connectionTCPSocket remoteAddressHost]);

        while (YES) {
            NSAutoreleasePool *subPool;
            NSData *data;

            subPool = [[NSAutoreleasePool alloc] init];

            NS_DURING {
                data = [connectionTCPSocket readData];
            } NS_HANDLER {
                // Probably disconnected
                NSLog(@"Exception raised: %@", localException);
                break;
            } NS_ENDHANDLER;

            [stdoutHandle writeData:data];

            [subPool release];
        }

        [pool release];
    }
}
