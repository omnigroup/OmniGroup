// Copyright 1997-2005, 2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWFileInfo.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWContentType.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@implementation OWFileInfo

static OWContentType *OWFileInfoContentType;

+ (void)initialize;
{
    OBINITIALIZE;

    OWFileInfoContentType = [OWContentType contentTypeForString:@"OWObject/OWFileInfo"];
}

+ (OWContentType *)contentType;
{
    return OWFileInfoContentType;
}

- initWithAddress:(OWAddress *)anAddress size:(NSNumber *)aSize isDirectory:(BOOL)isDirectory isShortcut:(BOOL)isShortcut lastChangeDate:(NSDate *)aDate;
{
    if (!(self = [super init]))
        return nil;

    address = [anAddress retain];
    size = [aSize retain];
    flags.isDirectory = isDirectory;
    flags.isShortcut = isShortcut;
    flags.fileTypeKnown = 1;
    lastChangeDate = [aDate retain];

    return self;
}

- initWithLastChangeDate:(NSDate *)aDate;
{
    if (!(self = [super init]))
        return nil;

    address = nil;
    size = nil;
    flags.isDirectory = 0;
    flags.isShortcut = 0;
    flags.fileTypeKnown = 0;
    lastChangeDate = [aDate retain];

    return self;
}

- (void)dealloc;
{
    [address release];
    [size release];
    [lastChangeDate release];
    [cachedName release];
    [cachedTitle release];
    [super dealloc];
}

- (void)setName:(NSString *)fileName
{
    OBASSERT(!flags.fixed);
    [fileName retain];
    [cachedName release];
    cachedName = fileName;
}

- (void)setTitle:(NSString *)documentTitle;
{
    OBASSERT(!flags.fixed);
    [documentTitle retain];
    [cachedTitle release];
    cachedTitle = documentTitle;
}

- (OWAddress *)address;
{
    return address;
}

- (NSNumber *)size;
{
    return size;
}

- (BOOL)isDirectory;
{
    return flags.isDirectory;
}

- (BOOL)isShortcut;
{
    return flags.isShortcut;
}

- (NSDate *)lastChangeDate;
{
    return lastChangeDate;
}

// (possibly-)derived attributes

- (NSString *)name;
{
    if (cachedName == nil) {
        cachedName = [[address localFilename] lastPathComponent];
        if (!cachedName)
            cachedName = [NSString decodeURLString:[[address url] lastPathComponent]];
        [cachedName retain];
    }
    return cachedName;
}

- (NSString *)title
{
    return cachedTitle;
}

- (NSString *)addressString;
{
    return [address addressString];
}

// OWContent protocol

- (OWContentType *)contentType;
{
    return OWFileInfoContentType;
}

- (BOOL)endOfData
{
#if defined(OMNI_ASSERTIONS_ON)
    if (!flags.fixed)
        flags.fixed = 1;
#endif
    return YES;
}

- (BOOL)contentIsValid;
{
    return YES;
}

@end
