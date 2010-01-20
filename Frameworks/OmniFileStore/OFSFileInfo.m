// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileInfo.h>

#import <OmniFoundation/NSString-OFURLEncoding.h>

RCS_ID("$Id$");

@implementation OFSFileInfo

+ (NSString *)nameForURL:(NSURL *)url;
{
    // Hack for double-encoding servers.  We know none of our file names have '%' in them.
    NSString *name = [[url path] lastPathComponent];
    NSString *decodedName = [NSString decodeURLString:name];
    while (![name isEqualToString:decodedName]) {
        name = decodedName;
        decodedName = [NSString decodeURLString:name];
    }
    return name;
}

- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size;
{
    OBPRECONDITION(url);
    OBPRECONDITION(!directory || size == 0);
    
    _originalURL = [[url absoluteURL] copy];
    _name = [name copy];
    _exists = exists;
    _directory = directory;
    _size = size;
    
    return self;
}

- (void)dealloc;
{
    [_originalURL release];
    [_name release];
    [super dealloc];
}

- (NSURL *)originalURL;
{
    return _originalURL;
}

- (NSString *)name;
{
    return _name;
}

- (BOOL)exists;
{
    return _exists;
}

- (BOOL)isDirectory;
{
    return _directory;
}

- (off_t)size;
{
    return _size;
}

- (BOOL)hasExtension:(NSString *)extension;
{
    return ([[_name pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame);
}

- (NSComparisonResult)compareByURLPath:(OFSFileInfo *)otherInfo;
{
    return [[_originalURL path] compare:[[otherInfo originalURL] path]];
}

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_originalURL forKey:@"url" defaultObject:nil];
    [dict setObject:_name forKey:@"name" defaultObject:nil];
    [dict setObject:[NSNumber numberWithBool:_exists] forKey:@"exists"];
    [dict setObject:[NSNumber numberWithBool:_directory] forKey:@"directory"];
    [dict setObject:[NSNumber numberWithUnsignedLongLong:_size] forKey:@"size"];
    return dict;
}
#endif

@end


NSURL *OFSFileURLRelativeToDirectoryURL(NSURL *baseURL, NSString *fileName)
{
    NSString *quotedFileName = [NSString encodeURLString:fileName asQuery:NO leaveSlashes:NO leaveColons:NO];
    
    NSString *baseURLString = [baseURL absoluteString];
    if (![baseURLString hasSuffix:@"/"]) {
        baseURLString = [baseURLString stringByAppendingString:@"/"]; // Else, the relative bit below will replace the last path component.
        baseURL = [NSURL URLWithString:baseURLString];
    }
    
    return [[NSURL URLWithString:quotedFileName relativeToURL:baseURL] absoluteURL];
}

