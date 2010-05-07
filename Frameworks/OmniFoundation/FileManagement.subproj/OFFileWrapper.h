// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Availability.h>

/*
 This is only used on the iPhone/iPad, which doesn't have NSFileWrapper. We have simpler needs on the iPad (no AFP mounts disabling hard linking, etc).
 */

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    #define OFFILEWRAPPER_ENABLED 1
#else
    #define OFFILEWRAPPER_ENABLED 0
    #define OFFileWrapper NSFileWrapper // our version is in OmniFoundation for a reason...)
    #import <AppKit/NSFileWrapper.h>
#endif

#if OFFILEWRAPPER_ENABLED

typedef NSUInteger OFFileWrapperReadingOptions;

@class NSDictionary, NSString, NSData, NSURL, NSError;

@interface OFFileWrapper : OFObject
{
@private
    NSDictionary *_fileAttributes;
    NSString *_preferredFilename;
    NSString *_filename;
    
    // If a directory
    NSMutableDictionary *_fileWrappers;
    
    // If a file
    NSData *_contents;
}

- (id)initWithURL:(NSURL *)url options:(OFFileWrapperReadingOptions)options error:(NSError **)outError;
- (id)initDirectoryWithFileWrappers:(NSDictionary *)childrenByPreferredName;
- (id)initRegularFileWithContents:(NSData *)contents;

- (NSDictionary *)fileAttributes;

- (BOOL)isRegularFile;
- (BOOL)isDirectory;

@property(nonatomic,copy) NSString *filename;
- (NSData *)regularFileContents;
- (NSDictionary *)fileWrappers;

@property(nonatomic,copy) NSString *preferredFilename;

- (NSString *)addFileWrapper:(OFFileWrapper *)child;
- (void)removeFileWrapper:(OFFileWrapper *)child;
- (NSString *)keyForFileWrapper:(OFFileWrapper *)child;

@end

#endif // OFFILEWRAPPER_ENABLED
