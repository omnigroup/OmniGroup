// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFileWrapper.h>

#if OFFILEWRAPPER_ENABLED

#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@implementation OFFileWrapper

- (id)initWithURL:(NSURL *)url options:(OFFileWrapperReadingOptions)options error:(NSError **)outError;
{
    OBPRECONDITION(options == 0); // we don't handle any options

    if (!(self = [super init]))
        return nil;

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
    if (!(self = [super init]))
        return nil;

    // NSFileWrapper will automatically propagate the preferred names to the child wrappers "if any file wrapper in the directory doesn't have a preferred filename". It isn't clear what happens if you pass in a dictionary like { "a" = <wrapper preferredName="b">; }.  We'll assert this isn't the case and override it.
    // It isn't clear at what point NSFileWrapper updates its dictionary if you change the preferred file name on a wrapper. Scary.
    
    _fileWrappers = [[NSMutableDictionary alloc] initWithDictionary:childrenByPreferredName];
    
    for (NSString *preferredName in _fileWrappers) {
        // Should be a single component.
        OBASSERT(![NSString isEmptyString:preferredName]);
        OBASSERT([[preferredName pathComponents] count] == 1);
        OBASSERT(![preferredName isAbsolutePath]);
        
        OFFileWrapper *childWrapper = [childrenByPreferredName objectForKey:preferredName];
        OBASSERT([childWrapper.preferredFilename isEqualToString:preferredName]);
        childWrapper.preferredFilename = preferredName;
    }

    return self;
}

- (id)initRegularFileWithContents:(NSData *)contents;
{
    OBPRECONDITION(contents);
    
    if (!(self = [super init]))
        return nil;
    
    _contents = [contents copy];

    return self;
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

static void _updateWrapperNamesFromURL(OFFileWrapper *self)
{
    // We should be a directory
    OBPRECONDITION(self->_fileWrappers);
    
    for (NSString *childKey in self->_fileWrappers) {
        OFFileWrapper *childWrapper = [self->_fileWrappers objectForKey:childKey];
        
        childWrapper.filename = childKey;
        
        if (childWrapper->_fileWrappers)
            _updateWrapperNamesFromURL(childWrapper);
    }
}

- (BOOL)writeToURL:(NSURL *)url options:(OFFileWrapperWritingOptions)options originalContentsURL:(NSURL *)originalContentsURL error:(NSError **)outError;
{
    OBPRECONDITION((options & ~(OFFileWrapperWritingAtomic|OFFileWrapperWritingWithNameUpdating)) == 0); // Only two defined flags
    OBPRECONDITION((options & OFFileWrapperWritingAtomic) == 0); // assuming higher level APIs will do this
    OBPRECONDITION(url);

    // Only update file names from the top level, on success.
    BOOL updateFilenames = (options & OFFileWrapperWritingWithNameUpdating) != 0;
    options &= ~OFFileWrapperWritingWithNameUpdating;
    
    // In testing, NSFileWrapper won't allow overwriting of a destination unless the source and destination are both flat files. So, we'll not intentionally allow this at all.
    url = [url absoluteURL];

    if (_contents) {
        if (![[NSFileManager defaultManager] createFileAtPath:[url path] contents:_contents attributes:_fileAttributes])
            return NO;
    } else if (_fileWrappers) {
        NSString *path = [url path];
        
        if (![[NSFileManager defaultManager] createDirectoryAtPath:[url path] withIntermediateDirectories:NO attributes:_fileAttributes error:outError])
            return NO;

        for (NSString *childKey in _fileWrappers) {
            OFFileWrapper *childWrapper = [_fileWrappers objectForKey:childKey];
            
            // Not doing any name remapping right now.
            OBASSERT([childWrapper preferredFilename] == nil || [childKey isEqualToString:[childWrapper preferredFilename]]);
            OBASSERT([childWrapper filename] == nil || [childKey isEqualToString:[childWrapper filename]]);
            
            if (![childWrapper writeToURL:[NSURL fileURLWithPath:[path stringByAppendingPathComponent:childKey]]
                                  options:options
                      originalContentsURL:[NSURL fileURLWithPath:[[originalContentsURL path] stringByAppendingPathComponent:childKey]]
                                    error:outError])
                return NO;
        }
    } else {
        OBRequestConcreteImplementation(self, _cmd); // Not supporting symlinks, for example.
    }
    
    [_preferredFilename release];
    _preferredFilename = [[[url path] lastPathComponent] copy];
    [_filename release];
    _filename = [_preferredFilename copy];

    if (_fileWrappers && updateFilenames) {
        // On success, update the child file wrappers file names too.
        // Might need to build some mapping of actual names written as we recurse if we allow conflicting preferred file names and uniquing on write.
        _updateWrapperNamesFromURL(self);
    }
    
    return YES;
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
    // NSFileWrapper docs:
    // This method raises NSInternalInconsistencyException if the receiver is not a directory file wrapper.
    // This method raises NSInvalidArgumentException if the child file wrapper doesn’t have a preferred name.
            
            
    if (!_fileWrappers)
        [NSException raise:NSInternalInconsistencyException reason:@"Attempted to add a child wrapper to a non-directory parent."];
    
    NSString *childPreferredFilename = child.preferredFilename;
    if (!childPreferredFilename)
        [NSException raise:NSInvalidArgumentException reason:@"Child doesn't have a preferred filename."];
        

    // NSFileWrapper will unique names; we won't bother for now.
    // Return: Dictionary key used to store fileWrapper in the directory’s list of file wrappers. The dictionary key is a unique filename, which is the same as the passed-in file wrapper's preferred filename unless that name is already in use as a key in the directory’s dictionary of children. See “Working With Directory Wrappers” in Application File Management for more information about the file-wrapper list structure.
    if ([_fileWrappers objectForKey:childPreferredFilename])
        [NSException raise:NSInvalidArgumentException reason:@"Child's preferred file name duplicates an existing file."];

    [_fileWrappers setObject:child forKey:childPreferredFilename];

    return childPreferredFilename;
}

- (void)removeFileWrapper:(OFFileWrapper *)child;
{
    OBFinishPorting;
}

- (NSString *)keyForFileWrapper:(OFFileWrapper *)child;
{
    // "This method raises NSInternalInconsistencyException if the receiver is not a directory file wrapper."
    if (!_fileWrappers)
        [NSException raise:NSInternalInconsistencyException reason:@"-keyForFileWrapper: called on non-directory wrapper."];
        
    NSString *key = [_fileWrappers keyForObjectEqualTo:child];
    OBASSERT(key); // Don't ask unless it really is our child
    
    return key;
}

- (BOOL)matchesContentsOfURL:(NSURL *)url;
{
    OBFinishPorting;
}

@end

#endif
