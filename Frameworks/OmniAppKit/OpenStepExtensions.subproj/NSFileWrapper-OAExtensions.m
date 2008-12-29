// Copyright 2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSFileWrapper-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

@implementation NSFileWrapper (OAExtensions)

- (NSString *)fileType:(BOOL *)isHFSType;
{
    NSString *fileType;
    NSDictionary *attributes = [self fileAttributes];
    OSType hfsType = [attributes fileHFSTypeCode];
    if (hfsType) {
        fileType = NSFileTypeForHFSTypeCode(hfsType);
        if (isHFSType)
            *isHFSType = YES;
    } else {
        // No HFS type, try to look at the extension
        NSString *path = [self filename];
        if ([NSString isEmptyString:path] || ![[NSFileManager defaultManager] fileExistsAtPath:path])
            path = [self preferredFilename];
        OBASSERT(![NSString isEmptyString:path]);
        fileType = [path pathExtension];
        if ([NSString isEmptyString:fileType])
            fileType = @"";
        if (isHFSType)
            *isHFSType = NO;
    }
    return fileType;
}

// TODO: Add an error: argument (assuming we still need this method)
- (BOOL)recursivelyWriteHFSAttributesToFile:(NSString *)file;
{
    // This method should be called AFTER the normal writing method!
    OBPRECONDITION([[NSFileManager defaultManager] fileExistsAtPath:file isDirectory:NULL]);
    
    NSDictionary *attributes = [self fileAttributes];
    
    BOOL success = YES;
    
    id type = [attributes objectForKey:NSFileHFSTypeCode];
    id creator = [attributes objectForKey:NSFileHFSCreatorCode];
    if (type || creator) {
        NSMutableDictionary *hfsAttributes = [[NSMutableDictionary alloc] init];
        if (type)
            [hfsAttributes setObject:type forKey:NSFileHFSTypeCode];
        if (creator)
            [hfsAttributes setObject:creator forKey:NSFileHFSCreatorCode];
	
        // Don't fail immediately on the first failure -- try to update other sub-wrappers
        if (![[NSFileManager defaultManager] setAttributes:hfsAttributes ofItemAtPath:file error:NULL])
            success = NO;
        [hfsAttributes release];
    }
    
    OBASSERT([[NSFileManager defaultManager] directoryExistsAtPath:file] == [self isDirectory]);
    if ([self isDirectory]) {
        NSDictionary *wrappers = [self fileWrappers];
        NSEnumerator *keyEnum = [wrappers keyEnumerator];
        NSString *wrapperKey;
        while ((wrapperKey = [keyEnum nextObject])) {
            NSFileWrapper *wrapper = [wrappers objectForKey:wrapperKey];
            
            // We use the key in the dictionary instead of the wrapper's -filename since NSDocument doesn't pass 'updateFilenames == YES' when writing the main wrapper.
            OBASSERT(![NSString isEmptyString:wrapperKey]);
            success &= [wrapper recursivelyWriteHFSAttributesToFile:[file stringByAppendingPathComponent:wrapperKey]];
        }
    }
    
    return success;
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
