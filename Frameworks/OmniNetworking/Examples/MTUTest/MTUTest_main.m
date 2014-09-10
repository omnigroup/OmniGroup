// Copyright 1997-2006, 2014 Omni Development, Inc. All rights reserved.
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
    fprintf(stderr, "usage: %s [-server | -client ] ip-multicast-host port-number maxMTU \n", pgm);
    exit(1);
}

/*
 This attempts to fine the effective MTU between a client and server by empirical observation.
 This test is written to use IP multicast (so you could run multiple clients against a single
 server), but it could be modified to use vanilla UDP.

 This test reports the MTU for the payload data, and doesn't include the number of bytes
 used by any of the network layers in each packet.
 */

static void runServer(ONPortAddress *portAddress, unsigned int maxMTU);
static void runClient(ONPortAddress *portAddress, unsigned int maxMTU);

int main (int argc, const char *argv[])
{
    NSAutoreleasePool *pool;
    ONPortAddress     *portAddress;
    unsigned int       maxMTU;
    ONHost            *host;
    
    pool = [[NSAutoreleasePool alloc] init];

    if (argc != 5)
        usage(argv[0]);

    host = [ONHost hostForHostname: [NSString stringWithCString: argv[2]]];
    portAddress = [[ONPortAddress alloc] initWithHost: host
                                           portNumber: atoi(argv[3])];
    maxMTU = atoi(argv[4]);
    
    if (![portAddress isMulticastAddress]) {
        fprintf(stderr, "%s is not a valid multicast address.\n", argv[2]);
        exit(1);
    }

    if (!strcmp("-server", argv[1]))
        runServer(portAddress, maxMTU);
    else if (!strcmp("-client", argv[1]))
        runClient(portAddress, maxMTU);
    else {
        usage(argv[0]);
        return 1;
    }

    [pool release];
    exit(0);       // insure the process exit status is 0
    return 0;      // ...and make main fit the ANSI spec.
}


static void runServer(ONPortAddress *portAddress, unsigned int maxMTU)
{
    // We are going to spray the network here.  A better algorithm could use let bandwidth
    // be having the client ask the server to send increasing powers of two packets
    // and the timeout if it doesn't get any packets.  It could then narrow in on the range
    // by recursiving subdividing the last success and last failure.
    // That would take more code, though.
    ONMulticastSocket *socket;
    void              *packet;
    unsigned int       mtuIndex, lengthWritten;
    
    socket = [[ONMulticastSocket socket] retain];
    [socket setLocalPortNumber];

    // Allocate the biggest packet we'll need.  We'll just send subchunks of it.
    packet = malloc(maxMTU);

    while (YES) {
        for (mtuIndex = 1; mtuIndex < maxMTU; mtuIndex++) {
            lengthWritten = [socket writeBytes: mtuIndex fromBuffer: packet toPortAddress: portAddress];
            if (lengthWritten != mtuIndex) {
                NSLog(@"Error writing packet of length %d.", mtuIndex);
            }
        }
    }
}

static void runClient(ONPortAddress *portAddress, unsigned int maxMTU)
{
    ONMulticastSocket *socket;
    void              *packet;
    unsigned int       bytesRead, maxReceived = 0;
    
    socket = [[ONMulticastSocket socket] retain];
    [socket setLocalPortNumber: [portAddress portNumber] allowingAddressReuse: YES];
    [socket joinReceiveGroup: [ONHostAddress hostAddressWithInternetAddress: [portAddress hostAddress]]];

    // Allocate the biggest packet we'll need.  We'll just send subchunks of it.
    packet = malloc(maxMTU);


    while ([socket waitForInputWithTimeout: 40000.0]) {
        bytesRead = [socket readBytes: maxMTU intoBuffer: packet];
        if (bytesRead > maxReceived) {
            maxReceived = bytesRead;
            NSLog(@"New maximum received = %d.", maxReceived);
            if (maxReceived >= maxMTU)
                NSLog(@"Met or exceeded maximum tested MTU of %d.", maxMTU);
        }
    }
}

