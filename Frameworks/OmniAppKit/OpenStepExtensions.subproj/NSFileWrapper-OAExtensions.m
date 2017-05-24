// Copyright 2006-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSFileWrapper-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <Foundation/NSFileManager.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@implementation NSFileWrapper (OAExtensions)

+ (NSFileWrapper *)fileWrapperWithFilename:(NSString *)filename contents:(NSData *)data;
{
    NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:data];
    fileWrapper.filename = filename;
    fileWrapper.preferredFilename = filename;
    return [fileWrapper autorelease];
}

- (NSString *)fileTypeIdentifier:(BOOL *)isHFSType;
{
    // We can only use some of the HFS type API on Mac. Default to looking up the extension; only avoid it if we're on Mac *and* find an HFS type code (see below).
    BOOL lookUpExtension = YES;
    
    NSString *fileType = nil;
    BOOL isDirectory = [self isDirectory];
    
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSDictionary *attributes = [self fileAttributes];
    OSType hfsType = [attributes fileHFSTypeCode];
    
    if (hfsType) {
        CFStringRef osTypeString = UTCreateStringForOSType(hfsType);
        fileType = CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassOSType, osTypeString, NULL));
        CFRelease(osTypeString);
        lookUpExtension = NO;
        
        if (isHFSType) {
            *isHFSType = YES;
        }
    }
#endif
    
    if (lookUpExtension) {
        // No HFS type, try to look at the extension
        NSString *path = [self filename];
        if ([NSString isEmptyString:path])
            path = [self preferredFilename];
        OBASSERT(![NSString isEmptyString:path]);

        fileType = OFUTIForFileExtensionPreferringNative([path pathExtension], @(isDirectory));
        if (isHFSType) {
            *isHFSType = NO;
        }
    }
    
    if (!fileType)
        fileType = (NSString *)(isDirectory ? kUTTypeDirectory : kUTTypeData);
    return fileType;
}

// This adds the argument to the receiver.  But, if the receiver already has a file wrapper for the preferred file name of the argument, this method attempts to move the old value aside (thus hopefully yielding the name to the argument wrapper).
- (void)addFileWrapperMovingAsidePreviousWrapper:(NSFileWrapper *)wrapper;
{
    NSString *name = [wrapper preferredFilename];
    OBASSERT(![NSString isEmptyString:name]);
    
    NSDictionary *wrappers = [self fileWrappers];
    NSFileWrapper *oldWrapper = [wrappers objectForKey:name];
    if (oldWrapper) {
        [[oldWrapper retain] autorelease];
        [self removeFileWrapper:oldWrapper];
        [self addFileWrapper:wrapper];
        [self addFileWrapper:oldWrapper];
	
        OBASSERT(OFNOTEQUAL([self keyForFileWrapper:oldWrapper], name));
    } else {
        [self addFileWrapper:wrapper];
    }
    
    OBPOSTCONDITION(OFISEQUAL([self keyForFileWrapper:wrapper], name));
}

@end
