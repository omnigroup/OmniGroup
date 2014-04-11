// Copyright 2001-2005, 2007-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OIF/OIICCProfile.h>

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

static NSLock *sharedProfileLock = nil;
static NSMapTable *sharedProfiles = NULL;

static NSMapTableKeyCallBacks profileDataKeyCallBacks;

@implementation OIICCProfile

static NSUInteger hashData(NSMapTable *table, const void *key)
{
    NSUInteger hashValue;
    NSData *theData = (NSData *)key;
    hashValue = [theData hash];
    //NSLog(@"hash <%s %p> --> %u", theData, hashValue);
    return hashValue;
}

static BOOL compareDataEqual(NSMapTable *table, const void *a, const void *b)
{
    if (a == b)
        return YES;
    
    return [ ((NSData *)a) isEqual: ((NSData *)b) ];
}

+ (void)initialize
{
    [super initialize];

    if (!sharedProfileLock) {
        sharedProfileLock = [[NSLock alloc] init];
        
        profileDataKeyCallBacks = (NSMapTableKeyCallBacks){
            hashData,
            compareDataEqual,
            NSObjectMapKeyCallBacks.retain,
            NSObjectMapKeyCallBacks.release,
            NSObjectMapKeyCallBacks.describe,
            NSObjectMapKeyCallBacks.notAKeyMarker
        };
    }
}

// Init and dealloc
+ (OIICCProfile *)profileFromData:(NSData *)newProfileData
{
    OIICCProfile *profile;
    
    if (!newProfileData || ![newProfileData length])
        return nil;
    
    [sharedProfileLock lock];
    
    if (!sharedProfiles)
        sharedProfiles = NSCreateMapTable(profileDataKeyCallBacks, NSObjectMapValueCallBacks, 0);
    
    profile = NSMapGet(sharedProfiles, newProfileData);
    if (!profile) {
        NSLog(@"Creating profile object for profile data (%ld bytes)", [newProfileData length]);
        newProfileData = [newProfileData copy];
        profile = [[self alloc] initWithData:newProfileData];
        if ([profile isValid]) {
            NSMapInsert(sharedProfiles, newProfileData, profile);
            [profile incrementWeakRetainCount];
            [profile autorelease];
        } else {
            [profile release];
            profile = nil;
        }
        [newProfileData release];
    } else {
        NSLog(@"Re-using profile object (profile data is %ld bytes)", [newProfileData length]);
    }
    
    [sharedProfileLock unlock];
    
    return profile;
}

- initWithData:(NSData *)theProfile
{
    if (!(self = [super init]))
        return nil;

#ifdef DEBUG
    NSLog(@"Allocated %@ %p", NSStringFromClass([self class]), self);
#endif

    OWFWeakRetainConcreteImplementation_INIT;

    profileData = [theProfile retain];

    profileLooksValid = checkICCProfile(profileData, &profileComponentCount, &profileDataColorSpace);

    if (profileLooksValid && profileComponentCount > 0) {
        CGDataProviderRef profileDataProvider;
        int i;
        CGFloat ranges[2 * profileComponentCount];
        
        for(i = 0; i < profileComponentCount; i++)
            ranges[2*i] = 0, ranges[2*i + 1] = 1; // NB there is no documentation on what ranges[] should contain, this is a guess
        
        profileDataProvider = CGDataProviderCreateWithCFData((CFDataRef)profileData);
        profileColorSpace = CGColorSpaceCreateICCBased(profileComponentCount, ranges, profileDataProvider, NULL);
        /* Note that there is currently no way to tell whether CGColorSpaceCreateICCBased() succeeded or failed. If it fails, it will create a CGColorSpace for an arbitrarily-chosen color space with the right number of color components, and return that. Apple bug ID #2704127, filed on 4 June 2001. */
        CGDataProviderRelease(profileDataProvider);
    } else {
        profileColorSpace = NULL;
    }

    return self;
}

- (void)dealloc;
{
#ifdef DEBUG
    NSLog(@"Deallocated %@ %p", NSStringFromClass([self class]), self);
#endif

    OWFWeakRetainConcreteImplementation_DEALLOC;

    if (profileColorSpace)
        CGColorSpaceRelease(profileColorSpace);
    [profileData release];
    
    [super dealloc];
}

OWFWeakRetainConcreteImplementation_IMPLEMENTATION;

- (void)invalidateWeakRetains
{
    [sharedProfileLock lock];
    
#ifdef DEBUG
    NSLog(@"Weak retain zappy %@ %p", NSStringFromClass([self class]), self);
#endif
    
    OBASSERT(sharedProfiles != NULL);
    OBASSERT(NSMapGet(sharedProfiles, profileData) == self);
    
    [self decrementWeakRetainCount];
    NSMapRemove(sharedProfiles, profileData);
    
    [sharedProfileLock unlock];
}

// API

- (int)componentCount
{
    return profileComponentCount;
}

- (unsigned int)iccProfileColorSpace
{
    return profileDataColorSpace;
}

- (BOOL)isValid
{
    return profileLooksValid && (profileColorSpace != NULL);
}

- (CGColorSpaceRef)coreGraphicsColorSpace
{
    return profileColorSpace;
}
    
//static unsigned int inline parseUnsignedInt(const unsigned char *buf)
//{
//    return (((buf[0] << 8) | buf[1]) << 16) | ((buf[2] << 8) | buf[3]);
//}

#define ICC_ACSP_SIGNATURE 0x61637370

BOOL checkICCProfile(NSData *profile, int *componentCount, unsigned int *dataColorSpace)
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
    return NO;
#if 0    
    const unsigned char *bytes;
    unsigned int profileLength;
    unsigned int tagIndex, tagCount, iccDataColorSpace;
    
    if (!profile || ([profile length] < 132)) {
        /* minimum size of ICC profile is a 128-byte header plus 4-byte tag count */
        NSLog(@"ICC profile is too short: (%d bytes < %d bytes)", [profile length], 132);
        return NO;
    }
    
    bytes = [profile bytes];
    profileLength = [profile length];
    
    /* check that it has the correct magic number at offset 36 */
    if (parseUnsignedInt(bytes + 36) != ICC_ACSP_SIGNATURE) {
        NSLog(@"ICC profile does not have correct 'acsp' signature");
        return NO;
    }
    
    iccDataColorSpace = parseUnsignedInt(bytes + 16); /* The data color space is a FourCharCode at offset 16 */
    tagCount = parseUnsignedInt(bytes + 128);  /* Tag count is a 4-byte integer at offset 128 */
    
    /* check that the length field does not indicate more data than we have, and check that we have space for all the tags (each tag is 12 bytes long) */
    if ((parseUnsignedInt(bytes) > profileLength) || 
        ((tagCount*12 + 132) > profileLength)) {
        NSLog(@"ICC profile is truncated");
        return NO;
    }
    
    /* check that all tag data lies within the bounds of our NSData */
    for(tagIndex = 0; tagIndex < tagCount; tagIndex ++) {
        /* Each tag contains a 4-byte type (which we ignore), a location, and a length */
        unsigned int tagLocation = parseUnsignedInt(bytes + 132 + (tagIndex * 12) + 4);
        unsigned int tagLength = parseUnsignedInt(bytes + 132 + (tagIndex * 12) + 8);
        
        if (tagLocation < (tagCount*12 + 132) || (tagLength != 0 &&
                (tagLocation > profileLength || (tagLocation + tagLength) > profileLength))) {
            NSLog(@"ICC profile is truncated");
            return NO;
        }
    }
    
    /* compute the dimensionality of the input space (i.e. samples per pixel) */
    *dataColorSpace = iccDataColorSpace;
    switch(iccDataColorSpace) {
        /* These magic numbers come from the ICC specification ICC.1:1998-09 */
        /* they all happen to be mnemonic 4-character ASCII strings, but we'll store them as hex... */
        case 0x52474220:  /* R,G,B */
        case 0x58595A20:  /* X,Y,Z */
        case 0x4C616220:  /* L,a,b */
        case 0x4C757620:  /* L,u,v */
        case 0x59436272:  /* Y,Cb,Cr */
        case 0x59787920:  /* Y,x,y */
        case 0x48535620:  /* H,S,V */
        case 0x484C5320:  /* H,L,S */
        case 0x434D5920:  /* C,M,Y */
            *componentCount = 3;
            break;
        case 0x434D594B:  /* C,M,Y,K */
            *componentCount = 4;
            break;
        case 0x47524159:  /* grayscale */
            *componentCount = 1;
            break;
        default: /* unrecognized color space */
            /* If the profile input space is a generic N-dimensional-space we're still ok */
            if ((iccDataColorSpace & 0xFFFFFF) == 0x434C52) {
                int dimensions = ( (iccDataColorSpace & 0xFF000000) >> 12 );
                if (dimensions >= '0' && dimensions <= '9') {
                    *componentCount = dimensions - '0';
                    break;
                } else if(dimensions >= 'A' && dimensions <= 'Z') {
                    *componentCount = dimensions - 'A' + 10;
                    break;
                }
            }
            NSLog(@"Warning: ICC profile has unrecognized color space '%@'", [NSString stringWithFourCharCode:iccDataColorSpace]);
            *componentCount = -1;
            break;
    }
    
    return YES;
#endif
}

@end

