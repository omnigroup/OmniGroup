// Copyright 1997-2005, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/system.h>

// This tool looks up a host entry by name or address and returns 0 for success (or a socket library error code or generic -1 on failure).  When successful, it outputs the canonical hostname followed by the list of IP addresses.

static int lookupHostname(const char *hostname);
static int lookupAddress(const char *addressString);
static int writeHostEntry(struct hostent *hostEntry);
static void writeCanonicalHostname(const char *hostname);
static void writeHostAddresses(int family, int length, void **addresses);
static int usage(void);

RCS_ID("$Id$");

static const char *toolName;

int main(int argc, const char *argv[])
{
    int returnValue;

    toolName = argv[0];

    if (argc != 3)
        return usage();

#ifdef DEBUG_kc0
    fprintf(stderr, "ONGetHostEntry %s '%s'\n", argv[1], argv[2]);
#endif

    switch (argv[1][0]) {
        case 'n': // name
            returnValue = lookupHostname(argv[2]);
            break;
        case 'a': // address
            returnValue = lookupAddress(argv[2]);
            break;
        default:
            returnValue = usage();
            break;
    }

#ifdef DEBUG_kc0
    fprintf(stderr, "ONGetHostEntry %s '%s' returns %d\n", argv[1], argv[2], returnValue);
#endif

    return returnValue;
}

static int lookupHostname(const char *hostname)
{
    unsigned long int address;

    address = inet_addr(hostname);
    if (address != (unsigned long int)-1) {
        void *pointers[2];
        // Oh ho!  They gave us an IP number in dotted quad notation!  I guess we'll return the dotted quad as the canonical hostname, and the converted address as the address.
        // (We're not returning the real canonical hostname because it might return more addresses, and that wouldn't be what the user want since they specifically specified a single address.)
        writeCanonicalHostname(hostname);
        pointers[0] = &address;
        pointers[1] = NULL;
        writeHostAddresses(AF_INET, sizeof(address), pointers);
        return NETDB_SUCCESS;
    }

    // Attempt to get all of the addresses for the specified host
    unsigned int lookupAttempts = 1;
    struct hostent *hostEntry = NULL;

    do {
        hostEntry = gethostbyname(hostname);
#ifdef DEBUG_kc
        if (hostEntry == NULL)
            fprintf(stderr, "ONGetHostEntry name '%s': gethostbyname() returned NULL, lookupAttempts = %d\n", hostname, lookupAttempts);
#endif
    } while (hostEntry == NULL && lookupAttempts++ < 3);
    return writeHostEntry(gethostbyname(hostname));
}

static int lookupAddress(const char *addressString)
{
    unsigned long int address;

    address = inet_addr(addressString);
    if (address == (unsigned long int)-1) {
        // Hey, that's no dotted quad address
        return usage();
    }

    // Attempt to get all of the addresses for the specified host
    return writeHostEntry(gethostbyaddr((char *)&address, sizeof(address), AF_INET));
}

static int writeHostEntry(struct hostent *hostEntry)
{
    if (!hostEntry)
        return h_errno;

    writeCanonicalHostname(hostEntry->h_name);

    // Print out all of the addresses that we got back for ONHost to grab
    writeHostAddresses(hostEntry->h_addrtype, hostEntry->h_length, (void **)hostEntry->h_addr_list);
    return NETDB_SUCCESS;
}

static void writeUint32(uint32_t v)
{
    v = htonl(v);
    fwrite(&v, sizeof(v), 1, stdout);
}

static void writeCanonicalHostname(const char *hostname)
{
    size_t hostnameLength;

    if (!hostname)
        hostname = "";
    hostnameLength = strlen(hostname);
    writeUint32((uint32_t)hostnameLength);
    fwrite(hostname, hostnameLength, 1, stdout);
}

static void writeHostAddresses(int family, int length, void **addresses)
{
    unsigned int entryIndex;

    writeUint32(family);
    writeUint32(length);
    for (entryIndex = 0; addresses[entryIndex]; entryIndex++) {
        fwrite(addresses[entryIndex], length, 1, stdout);
    }
}

static int usage()
{
    fprintf(stderr, "usage:\t%s name hostname\n\t%s address n.n.n.n\n", toolName, toolName);
    return NETDB_INTERNAL;
}
