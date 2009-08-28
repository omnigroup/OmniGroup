// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if defined(DEBUG) && !defined(DEBUGLEVEL)
#define DEBUGLEVEL 4
#endif

#import <OmniFoundation/OFResourceFork.h>
#import <OmniFoundation/OFUtilities.h>

#import <Carbon/Carbon.h>
#import <CoreFoundation/CoreFoundation.h>

#import <OmniFoundation/OFResource.h>
#import <OmniFoundation/NSString-OFExtensions.h>

RCS_ID("$Id$")


@implementation OFResourceFork

+ (NSArray *) stringsFromSTRResourceHandle: (Handle) resourceHandle;
{
    char *str, *strEnd;
    UInt16 stringCount;
    BOOL overran;
    NSMutableArray *strings;

    OBASSERT(resourceHandle != NULL);
    if (resourceHandle == NULL)
        return nil;
    
    strings = [NSMutableArray array];
    HLock(resourceHandle);
    overran = NO;
    stringCount = *(UInt16 *)*resourceHandle;
    str = (char *)(1 + (UInt16 *)*resourceHandle);
    strEnd = ((char *)*resourceHandle) + GetHandleSize(resourceHandle);
    while (stringCount--) {
        NSString *thisString;
        unsigned thisStringLength;

        if (str >= strEnd) {
            overran = YES;
            break;
        }

        thisStringLength = (unsigned char)*str;
        str ++;

        if (str + thisStringLength > strEnd) {
            overran = YES;
            break;
        }

        thisString = [[NSString alloc] initWithBytes:str length:thisStringLength encoding:NSASCIIStringEncoding];
        [strings addObject: thisString];
        [thisString release];

        str += thisStringLength;
    }

    HUnlock(resourceHandle);

    if (overran) {
        [NSException raise: NSRangeException format: @"Truncated STR# resource"];
    }

    return strings;
}

- initWithContentsOfFile: (NSString *) aPath forkType: (OFForkType) aForkType createFork:(BOOL)shouldCreateFork;
{
    CFURLRef url;
    Boolean success;
    OSErr err;
    FSRef fsRef;
    HFSUniStr255 forkName;
    
    refNumValid = NO;
    path = [aPath copy];

    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"File doesn't exist at path %@.", aPath];
    }

    if (isDir && ![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"Directory exists, but is not executable at path %@.", aPath];
    }
    
#define RAISE(exceptionName, format...) [[NSException exceptionWithName:exceptionName reason:[NSString stringWithFormat: format] userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:err] forKey:OBExceptionCarbonErrorNumberKey]] raise]

    url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    success = CFURLGetFSRef(url, &fsRef);
    CFRelease(url);
    if (!success) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"Unable to get a FSRef from the path %@.", aPath];
    }
    
    if (aForkType == OFDataForkType) {
        err = FSGetDataForkName(&forkName);
    } else if (aForkType == OFResourceForkType) {
        err = FSGetResourceForkName(&forkName);
    } else {
        err = noErr;
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"Invalid fork type %d", aForkType];
    }
    
    if (err != noErr) {
        [self release];
        RAISE(NSInvalidArgumentException, @"Unable to get fork name for fork type %d (error code %d)", aForkType, err);
    }

    BOOL shouldReallyCreateFork = shouldCreateFork;
    if (![[NSFileManager defaultManager] isWritableFileAtPath:aPath])
        shouldReallyCreateFork = NO;
    
    err = FSOpenResourceFile(&fsRef, forkName.length, forkName.unicode, fsCurPerm, &refNum);
    if (err != noErr) {
        if (shouldReallyCreateFork) {
            err = FSCreateResourceFork(&fsRef, forkName.length, forkName.unicode, 0);
            if (err == noErr) {
                err = FSOpenResourceFile(&fsRef, forkName.length, forkName.unicode, fsCurPerm, &refNum);
            }
        }
        if (err != noErr) {
            if (shouldReallyCreateFork) {
                RAISE(NSInvalidArgumentException, @"Unable to create resource fork from fork type %d in file %@ (error code %d)", aForkType, aPath, err);
            } else {
                switch (err) {
                    case eofErr:
                    case fnfErr:
                    case errFSForkNotFound:
                        [self release];
                        return nil;
                    default:
                        [self release];

                        NSString *forkTypeDescription = (aForkType == OFDataForkType) ? @"data fork" : @"resource fork";
                        RAISE(NSInvalidArgumentException, @"Unable to open %@ in file %@ (error code %d).", forkTypeDescription, aPath, err);
                        return nil;
                }
            }
        }
    }
    refNumValid = YES;
    
    return self;
}

- initWithContentsOfFile: (NSString *) aPath forkType: (OFForkType) aForkType;
{
    return [self initWithContentsOfFile: aPath forkType: aForkType createFork:NO];
}

- initWithContentsOfFile: (NSString *) aPath;
{
    return [self initWithContentsOfFile: aPath forkType: OFResourceForkType];
}

- (void) dealloc;
{
    [path release];
    if (refNumValid)
        CloseResFile(refNum);
    [super dealloc];
}

- (NSString *) path;
{
    return path;
}

- (NSArray *) stringsForResourceWithIdentifier: (ResID) resourceIdentifier;
{
    Handle resourceHandle;
    SInt16 oldCurRsrcMap;
    NSArray *strings = nil;
    
    oldCurRsrcMap = CurResFile();
    UseResFile(refNum);
    
    resourceHandle = Get1Resource(FOUR_CHAR_CODE('STR#'), resourceIdentifier);
    if (resourceHandle)
        strings = [[self class] stringsFromSTRResourceHandle:resourceHandle];
    
    UseResFile(oldCurRsrcMap);
    
    return strings;
    //CloseResFile tosses all the handles gotten from the resID passed to it.
    //DisposeHandle(resourceHandle);
}

- (short) countForResourceType: (ResType) resourceType;
{
    short count;
    SInt16 oldCurRsrcMap;

    oldCurRsrcMap = CurResFile();
    UseResFile(refNum);

    count = Count1Resources(resourceType);

    UseResFile(oldCurRsrcMap);

    return count;
}

- (NSData *)dataForResourceType:(ResType)resourceType atIndex:(short)resourceIndex;
{
    SInt16 oldCurRsrcMap;
    Handle resourceHandle;
    NSData *data = nil;

    oldCurRsrcMap = CurResFile();
    UseResFile(refNum);

    // Get the resource, converting for 1-based indexing
    resourceHandle = Get1IndResource(resourceType, resourceIndex+1);
    
    if (resourceHandle) {
        Size size;
        
        HLock(resourceHandle);
        size = GetHandleSize(resourceHandle);
        data = [NSData dataWithBytes: *resourceHandle length: size];
        HUnlock(resourceHandle);
        
        //CloseResFile tosses all the handles gotten from the resID passed to it.
        //DisposeHandle(resourceHandle);
    }

    UseResFile(oldCurRsrcMap);
    
    return data;
}

- (void)deleteResourceOfType:(ResType)resType atIndex:(short)resourceIndex;
{
    SInt16 oldCurRsrcMap;
        
    oldCurRsrcMap = CurResFile();
    require_noerr(ResError(), delete_failed);
    UseResFile(refNum);
    require_noerr(ResError(), delete_failed);

    // Get the resource, converting for 1-based indexing
    Handle resourceHandle = Get1IndResource(resType, resourceIndex+1);
    if (resourceHandle) {
        RemoveResource(resourceHandle);
        require_noerr(ResError(), delete_failed);
        DisposeHandle(resourceHandle);
    }
        
    UpdateResFile(refNum);
    require_noerr(ResError(), delete_failed);
    UseResFile(oldCurRsrcMap);    
    require_noerr(ResError(), delete_failed);

// error out
delete_failed:
    return;
}

- (void)setData:(NSData *)contentData forResourceType:(ResType)resType;
{
    SInt16 oldCurRsrcMap;

    oldCurRsrcMap = CurResFile();
    UseResFile(refNum);

    const void *data = [contentData bytes];
    Handle dataHandle;
    PtrToHand(data, &dataHandle, [contentData length]);
    AddResource(dataHandle, resType, Unique1ID(resType), "\pOFResourceForkData");
    
    UpdateResFile(refNum);
    UseResFile(oldCurRsrcMap);
}

- (NSArray *)resourceTypes;
{
    SInt16 oldCurRsrcMap;
    NSMutableArray *types;
    short numTypes, typeIndex;
    ResType aType;
    NSString *typeString;
    
    types = [[[NSMutableArray alloc] init] autorelease];

    oldCurRsrcMap = CurResFile();
    UseResFile(refNum);
    
    numTypes = Count1Types();
    if (ResError() != noErr || numTypes < 0) {
        types = nil;
    } else {
        for (typeIndex = 1; typeIndex <= numTypes; typeIndex++) {
            Get1IndType(&aType, typeIndex);
            typeString = [NSString stringWithFourCharCode:aType];
            [types addObject:typeString];
        }
    }

    UseResFile(oldCurRsrcMap);
    
    return types;
}

- (short)numberOfResourcesOfType:(NSString *)resourceType;
{
    SInt16 resourcesCount;
    SInt16 oldCurRsrcMap;
    ResType resourceTypeCode;

    OBASSERT(resourceType != nil);
    OBASSERT([resourceType length] >= 4);
    resourceTypeCode = [resourceType fourCharCodeValue];

    oldCurRsrcMap = CurResFile();
    UseResFile(refNum);
    resourcesCount = Count1Resources(resourceTypeCode);
    UseResFile(oldCurRsrcMap);

    return resourcesCount;
}

- (NSArray *)resourcesOfType:(NSString *)resourceType;
{
    SInt16 oldCurRsrcMap;
    NSMutableArray *resources;
    short numResources, resourceIndex;
    ResType resourceTypeCode;
    
    OBASSERT(resourceType != nil);
    OBASSERT([resourceType length] >= 4);
    resourceTypeCode = [resourceType fourCharCodeValue];
    
    resources = [[[NSMutableArray alloc] init] autorelease];

    oldCurRsrcMap = CurResFile();
    UseResFile(refNum);

    NS_DURING;
    
    numResources = Count1Resources(resourceTypeCode);
    for (resourceIndex = 1; resourceIndex <= numResources; resourceIndex++) {
        Handle aResource;
        OFResource *resource;
        
        aResource = Get1IndResource(resourceTypeCode, resourceIndex);
        if (!aResource)
            continue;
        
        resource = [[OFResource alloc] initInResourceFork:self withHandle:aResource];
        [resources addObject:resource];
        [resource release];
    }

    NS_HANDLER {
        UseResFile(oldCurRsrcMap);
        [localException raise];
    } NS_ENDHANDLER;

    UseResFile(oldCurRsrcMap);
    
    return resources;
}

@end
