// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFileWrapper.h>

#if OFFILEWRAPPER_ENABLED

#import <OmniFoundation/OFNull.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@interface OFDirectoryFileWrapper : OFFileWrapper
{
@private
    NSDictionary *_children;
}
@end

@implementation OFFileWrapper

- (id)initWithURL:(NSURL *)url options:(OFFileWrapperReadingOptions)options error:(NSError **)outError;
{
    OBPRECONDITION(options == 0); // we don't handle any options

    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = [[url absoluteURL] path];
    
    _filename = [[path lastPathComponent] copy];
    _preferredFilename = [_filename copy];
    
    _fileAttributes = [[manager attributesOfItemAtPath:path error:outError] copy];
    if (!_fileAttributes) {
        [self release];
        return nil;
    }
    
    NSString *fileType = [_fileAttributes fileType];
    if (OFISEQUAL(fileType, NSFileTypeDirectory)) {
        NSArray *contents = [manager contentsOfDirectoryAtPath:path error:outError];
        if (!contents) {
            [self release];
            return nil;
        }

        _fileWrappers = [[NSMutableDictionary alloc] init];
        for (NSString *file in contents) {
            OFFileWrapper *childWrapper = [[OFFileWrapper alloc] initWithURL:[NSURL fileURLWithPath:[path stringByAppendingPathComponent:file]] options:options error:outError];
            if (!childWrapper) {
                [self release];
                return nil;
            }
            
            [_fileWrappers setObject:childWrapper forKey:file];
            [childWrapper release];
        }
        
        return self;
    }
    
    if (OFISEQUAL(fileType, NSFileTypeRegular)) {
        _contents = [[NSData alloc] initWithContentsOfURL:url options:0 error:outError];
        if (!_contents) {
            [self release];
            return nil;
        }
        
        return self;
    }
    
    NSLog(@"Not handling file type %@", fileType);
    OBFinishPorting;
    return nil;
}

- (id)initDirectoryWithFileWrappers:(NSDictionary *)childrenByPreferredName;
{
    OBFinishPorting;
}

- (id)initRegularFileWithContents:(NSData *)contents;
{
    OBFinishPorting;
}

- (void)dealloc;
{
    [_fileWrappers release];
    [_contents release];
    [_fileAttributes release];
    [_preferredFilename release];
    [_filename release];
    [super dealloc];
}

- (NSDictionary *)fileAttributes;
{
    return _fileAttributes;
}

- (BOOL)isRegularFile;
{
    return _contents != nil;
}

- (BOOL)isDirectory;
{
    return _fileWrappers != nil;
}

@synthesize filename = _filename;

- (NSData *)regularFileContents;
{
    OBPRECONDITION(_contents); // Don't ask this unless it is a file. Real class might even raise.
    return _contents;
}

- (NSDictionary *)fileWrappers;
{
    OBPRECONDITION(_fileWrappers); // Don't ask this unless it is a directory. Real class might even raise.
    return _fileWrappers;
}

@synthesize preferredFilename = _preferredFilename;

- (NSString *)addFileWrapper:(OFFileWrapper *)child;
{
    OBFinishPorting;
}

- (void)removeFileWrapper:(OFFileWrapper *)child;
{
    OBFinishPorting;
}

- (NSString *)keyForFileWrapper:(OFFileWrapper *)child;
{
    OBFinishPorting;
}

@end

#endif
