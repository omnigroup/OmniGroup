// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipDirectoryMember.h>

#import <OmniUnzip/OUZipArchive.h>
#import <OmniUnzip/OUZipFileMember.h>
#import <OmniUnzip/OUErrors.h>
#import <OmniFoundation/NSObject-OFExtensions.h>

#import "zip.h"
#import "unzip.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_ZIP_FILES(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_ZIP_FILES(format, ...)
#endif

NS_ASSUME_NONNULL_BEGIN

static NSString * const OUZipRootDirectoryName = @".";  // We'll want to strip this when writing so we write "foo" instead of "./foo"

@implementation OUZipDirectoryMember
{
    NSMutableArray <OUZipMember *> *_children;
    NSMutableDictionary <NSString *, OUZipMember *> *_childrenByName;
    BOOL _shouldArchive;
}

- initRootDirectoryWithChildren:(NSArray <OUZipMember *> * _Nullable)children;
{
    return [self initWithName:OUZipRootDirectoryName date:nil children:children archive:NO];
}

- initWithName:(NSString *)name date:(NSDate * _Nullable)date children:(NSArray <OUZipMember *> * _Nullable)children archive:(BOOL)shouldArchive;
{
    if (!(self = [super initWithName:name date:date]))
        return nil;
    
    _children = [[NSMutableArray alloc] init];
    _childrenByName = [[NSMutableDictionary alloc] init];
    _shouldArchive = shouldArchive;

    for (OUZipDirectoryMember *child in children)
        [self addChild:child];
    
    return self;
}

- initWithName:(NSString *)name date:(NSDate * _Nullable)date;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (BOOL)isRootDirectory;
{
    return [[self name] isEqualToString:OUZipRootDirectoryName];
}

- (NSArray <OUZipMember *> *)children;
{
    return _children;
}

- (OUZipMember * _Nullable)childNamed:(NSString *)childName;
{
    return [_childrenByName objectForKey:childName];
}

// TODO: Zip has no notion of directories or uniqueness of files, so you can totally add the same file multiple times, as far as I can tell.  Though zip does have refreshing/appending -- maybe it does replace if you do this.  Anyway, we'll assert above, but this should do something reasonable on failure of that assertion.
- (void)addChild:(OUZipMember *)child;
{
    OBPRECONDITION([self childNamed:[child name]] == nil);
    [_children addObject:child];
    [_childrenByName setObject:child forKey:[child name]];
}

- (void)prependChild:(OUZipMember *)child;
{
    OBPRECONDITION([self childNamed:[child name]] == nil);
    [_children insertObject:child atIndex:0];
    [_childrenByName setObject:child forKey:[child name]];
}

- (BOOL)appendToZipArchive:(OUZipArchive *)zip error:(NSError **)outError;
{
    return [self appendToZipArchive:zip fileNamePrefix:@"" error:outError];
}

#pragma mark - OUZipMember subclass

- (NSFileWrapper *)fileWrapperRepresentation;
{
    NSMutableDictionary *childWrappers = [NSMutableDictionary dictionary];
    for (OUZipMember *child in _children) {
        childWrappers[[child name]] = [child fileWrapperRepresentation];
    }
    
    NSFileWrapper *directoryWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:childWrappers];
    directoryWrapper.preferredFilename = [self name];
    return directoryWrapper;
}

- (BOOL)appendToZipArchive:(OUZipArchive *)zip fileNamePrefix:(NSString * _Nullable)fileNamePrefix error:(NSError **)outError;
{
    // TODO: Create a directory entry to store attributes?  The zip command line tool has a mode which skips this...

    // DO NOT sort the children.  We add them to the archive in exactly the order they were added to us.  If we sorted by name, our OAT tests would randomly have re-ordered table of contents in their zip transaction files.  This puts the zip attachments in the same order as the top-level objects were added to the transaction.

    // Not checking for duplicate member names.  Not checking for cases where the operations don't make sense (a flat file "a" followed by "a/b").  Zip files don't seem to prevent this and we shouldn't do that anyway.
    
    NSString *name = [self name];
    if (![NSString isEmptyString:fileNamePrefix])
        name = [fileNamePrefix stringByAppendingFormat:@"/%@", name];

    if (_shouldArchive && ![zip appendEntryNamed:[name stringByAppendingString:@"/"] fileType:NSFileTypeDirectory contents:[NSData data] date:[self date] error:outError])
        return NO;

    for (OUZipMember *member in _children) {
        NSString *prefix;
        if (![self isRootDirectory])
            prefix = name;
        else
            prefix = @"";
        
        if (![member appendToZipArchive:zip fileNamePrefix:prefix error:outError])
            return NO;
    }
    
    return YES;
}

@end

NS_ASSUME_NONNULL_END

