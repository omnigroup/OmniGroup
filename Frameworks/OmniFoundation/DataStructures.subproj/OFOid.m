// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFOid.h>

#import <OmniBase/system.h>

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSHost-OFExtensions.h>
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFSimpleLock.h>
#import <OmniFoundation/OFUtilities.h>

#import <Foundation/NSPortCoder.h>

RCS_ID("$Id$")

@implementation OFOid

+ (OFOid *)oid;
{
    return [[[self alloc] init] autorelease];
}

+ (OFOid *)oidWithData:(NSData *)data;
{
    return [[[self alloc] initWithBytes:[data bytes] length:[data length]] autorelease];
}

+ (OFOid *)zeroOid;
{
    static OFOid *zero = nil;

    if (!zero) {
        zero = [[self alloc] initWithBytes:NULL length:0];
    }
    return zero;
}

//
// EOCustomValues protocol
//

// If the size of OFOid changes, this will need to be updated

static const char intToHex[16] = "0123456789abcdef";

static char tohex(unsigned char c)
{
    if (isupper(c))
        c = tolower(c);
    if (isdigit(c))
	return c - '0';
    else
	return c - 'a' + 0xa;
}

#define SAFE_ALLOCA_SIZE (8 * 8192)

- initWithString:(NSString *)aString
{
    BOOL useMalloc;
    unichar *buffer;
    const unichar *p;
    unsigned int characterCount, characterIndex, maximumCharacterIndex;

    [super init];

    characterCount = [aString length];
    useMalloc = characterCount * sizeof(unichar) >= SAFE_ALLOCA_SIZE;
    if (useMalloc) {
        buffer = (unichar *)NSZoneMalloc(NULL, characterCount * sizeof(unichar));
    } else {
        buffer = (unichar *)alloca(characterCount * sizeof(unichar));
    }
    [aString getCharacters:buffer];
    p = buffer;

    if (characterCount < 2)
	goto error;

    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
	p += 2;
	characterCount -= 2;
    }

    if (characterCount % 1)
        // have to have a full 8 bits in each byte!
        goto error;
    
    if (characterCount > 2 * sizeof(bytes))
	goto error;

    // Handle short strings correctly
    maximumCharacterIndex = MIN(sizeof(bytes), characterCount/2);
    for (characterIndex = 0; characterIndex < maximumCharacterIndex; characterIndex++) {
	unsigned char c1, c2;

        // Note: we're assuming here that the initialization string doesn't contain any non-ASCII characters, since it sure shouldn't.  If we were paranoid, I guess we'd test.

	c1 = (char)*p++;
	if (!isxdigit(c1))
	    goto error;
	c1 = tohex(c1);

	c2 = (char)*p++;
	if (!isxdigit(c2))
	    goto error;
	c2 = tohex(c2);

	bytes[characterIndex] = (c1 << 4) + c2;
    }

    // If we get a short string, extend it with zeros
    while (characterIndex < sizeof(bytes))
	bytes[characterIndex++] = '\0';

    if (useMalloc)
        NSZoneFree(NULL, buffer);

    return self;

error:
    if (useMalloc)
        NSZoneFree(NULL, buffer);

    [self release];
    [NSException raise: NSInvalidArgumentException
                format: @"Cannot create an OFOid from the string '%@' because is not a valid hex string.", aString];

    // Please the compiler
    return nil;
}

- (NSString *)sqlString;
{
    unichar stringBuffer[OFOID_LENGTH * 2];
    unichar *bufferPointer;
    unsigned int byteIndex;

    bufferPointer = stringBuffer;
    for (byteIndex = 0; byteIndex < OFOID_LENGTH; byteIndex++) {
        unsigned char currentByte;

	currentByte = bytes[byteIndex];
	*bufferPointer++ = intToHex[currentByte >> 4];
	*bufferPointer++ = intToHex[currentByte & 0xf];
    }

    return [NSString stringWithCharacters:stringBuffer length:OFOID_LENGTH * 2];
}

- (NSString *)description;
{
    return [self lowercaseHexString];
}


//
// NSCoding protocol
//

- initWithCoder:(NSCoder *)coder;
{
    [super init];

    [coder decodeArrayOfObjCType:@encode(unsigned char) count:OFOID_LENGTH at:&bytes];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder;
{
    [coder encodeArrayOfObjCType:@encode(unsigned char) count:OFOID_LENGTH at:&bytes];
    return;
}

// NSDistributedObjects

- (Class)classForPortCoder;
{
    return [self class];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder
{
    return self;
}

//
// NSData subclass
//

- initWithBytes:(const void *)newBytes length:(NSUInteger)length;
{
    [super init];

    if (length == OFOID_LENGTH) {
        const unsigned int *sourceInts;
        unsigned int *destInts;

	sourceInts = (const unsigned int *)newBytes;
	destInts = (unsigned int *)&bytes[0];
	*destInts++ = *sourceInts++;
	*destInts++ = *sourceInts++;
	*destInts++ = *sourceInts++;
    } else if (length < OFOID_LENGTH) {
        memset(bytes, 0, OFOID_LENGTH);
        if (length)
            memcpy(bytes, newBytes, length);
    } else {
        [NSException raise: NSInvalidArgumentException format: @"Attempted to initialize an oid with more than %d bytes (length of %d bytes was passed).", OFOID_LENGTH, length];
    }
    
    return self;
}

// The NSData version of this method doesn't do this -- it calls some private method.
- initWithData: (NSData *) data;
{
    return [self initWithBytes: [data bytes] length: [data length]];
}

- (NSUInteger)length;
{
    return OFOID_LENGTH;
}

- (const void *)bytes;
{
    return bytes;
}

- (NSUInteger)hash;
{
    unsigned int *ints;

    ints = (unsigned int *)bytes;
    return ints[0] ^ ints[1] ^ ints[2];
}

- (BOOL)isEqual:(OFOid *)anOid;
{
    if (anOid && isa == *((Class *) anOid)) {
        unsigned int *ints;
        unsigned int *otherInts;

	ints = (unsigned int *)bytes;
        otherInts = (unsigned int *)&anOid->bytes[0];
	if (*ints++ == *otherInts++)
	    if (*ints++ == *otherInts++)
		if (*ints++ == *otherInts++)
		    return YES;
    }
    return NO;
}

- (BOOL)isZero;
{
    unsigned int *ints;

    ints = (unsigned int *)bytes;
    return (ints[0] | ints[1] | ints[2]) == 0;
}

// Oids are immutable
- copyWithZone:(NSZone *)aZone;
{
    return [self retain];
}


// ObjectId get generated in the following format:
// +----------------------------------------------------------------------+
// | RANDOM    | SEQ       |  TIME                | PID       | IP (2)    |
// | byte byte | byte byte | byte byte  byte byte | byte byte | byte byte |
// +----------------------------------------------------------------------+
// RANDOM = 2 bytes of random number for distribution
// SEQ    = Unsigned short sequence counter that starts randomly.
// TIME = Seconds since epoch (1/1/1970)
// PID  = Process ID
//        This is only two bytes even though most pids are longs.
//        Here you would take the lower 2 bytes.
// IP   = IP Address of the machine (subnet.hostId)

typedef struct _BaseOid
{
    unsigned short random;
    unsigned short seq;
    unsigned long time;
    unsigned short pid;
    unsigned short ip;
} _BaseOid;

static OFSimpleLockType _baseOidLock;
static _BaseOid _lockedBaseOid = {0, 0, 0, 0, 0};   
static unsigned short saveRandomStart = 0;
static OFRandomState oidRandomState;

+ (void)initialize
{
    OBINITIALIZE;
    
    // Force +[OBObject initialize] to be called if it hasn't been called already which will
    // in turn call +[OBPostLoader processClasses], setting up the OFRandom gunk.
    [OBObject self];

    OFSimpleLockInit(&_baseOidLock);
    
    OFRandomSeed(&oidRandomState, OFRandomGenerateRandomSeed());
    
    _lockedBaseOid.pid = [[[NSProcessInfo processInfo] processNumber] unsignedShortValue];
    _lockedBaseOid.ip = OFLocalIPv4Address() & 0xffff;
    saveRandomStart = OFRandomNextState(&oidRandomState) & USHRT_MAX;
    _lockedBaseOid.seq = saveRandomStart - 1;
}

- init
{
    [super init];

    OFSimpleLock(&_baseOidLock);

    _lockedBaseOid.random = OFRandomNextState(&oidRandomState) & USHRT_MAX;

    if (++_lockedBaseOid.seq == saveRandomStart) {
        static unsigned long lastTime = 0;
        unsigned long curTime;

        curTime = time(NULL);
        if (curTime > lastTime)
            lastTime = curTime;
        else
            lastTime++;
        _lockedBaseOid.time = htonl(lastTime);
    }

    _lockedBaseOid.seq = htons(_lockedBaseOid.seq);
    if (![self initWithBytes:(unsigned char *)&_lockedBaseOid length:sizeof(_lockedBaseOid)]) {
        OFSimpleUnlock(&_baseOidLock);
	return nil;
    }
    
    _lockedBaseOid.seq = ntohs(_lockedBaseOid.seq);
    OFSimpleUnlock(&_baseOidLock);

    return self;
}


// EOF custom value initialization and archival
+ objectWithArchiveData:(NSData *)data;
{
    return [[[self alloc] initWithBytes:[data bytes] length:[data length]] autorelease];
}

- (NSData *)archiveData;
{
    return self;
}

+ (OFOid *)oidWithBytes:(const void *)newBytes length:(NSUInteger)length;
{
// TODO: OPTIMIZE: This should be optimized a bit
    return [[[self alloc] initWithBytes:newBytes length:length] autorelease];
}

+ (OFOid *) oidWithString: (NSString *) aString;
{
    return [[[self alloc] initWithString:aString] autorelease];
}

@end

@implementation OFOid (EOF2_2_BugFix)

- (int)intValue
{
    // Apple has a bug in _primaryKeyForObject:.  They errantly ask your custom primary key for its intValue, despite the fact that [primaryKey isKindOfClass:[NSNumber class]] fails. -luke
    return 1;
}

@end
