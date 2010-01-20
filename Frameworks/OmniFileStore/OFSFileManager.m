// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileManager.h>

#import <OmniFileStore/OFSFileFileManager.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/Errors.h>

RCS_ID("$Id$");

NSInteger OFSFileManagerDebug = 0;

@implementation OFSFileManager

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFSFileManagerDebug = [[NSUserDefaults standardUserDefaults] integerForKey:@"OFSFileManagerDebug"];
    
    // Hard to turn this on via defaults write on the device...
#if 0 && defined(DEBUG_bungi)
    OFSFileManagerDebug = 1;
#endif
}

+ (Class)fileManagerClassForURLScheme:(NSString *)scheme;
{
    if ([scheme isEqualToString:@"file"])
        return [OFSFileFileManager class];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        return [OFSDAVFileManager class];
    return Nil;
}

- initWithBaseURL:(NSURL *)baseURL error:(NSError **)outError;
{
    OBPRECONDITION(baseURL);
    OBPRECONDITION([[baseURL path] isAbsolutePath]);
    
    if ([self class] == [OFSFileManager class]) {
        NSString *scheme = [baseURL scheme];
        Class cls = [[self class] fileManagerClassForURLScheme:scheme];
        if (cls) {
            [self release];
            return [[cls alloc] initWithBaseURL:baseURL error:outError];
        }
        
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No scheme specific file manager for scheme \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), scheme];
        OFSError(outError, OFSNoFileManagerForScheme, NSLocalizedStringFromTableInBundle(@"Cannot create file manager.", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), reason);
        [self release];
        return nil;
    }
    
    _baseURL = [baseURL copy];
    return self;
}

- (void)dealloc;
{
    [_baseURL release];
    [super dealloc];
}

- (NSURL *)baseURL;
{
    return _baseURL;
}

- (id)asynchronousReadContentsOfURL:(NSURL *)url forTarget:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;
{
    NSError *error = nil;
    NSData *data = [self dataWithContentsOfURL:url error:&error];
    if (data == nil) {
        [target fileManager:self didFailWithError:error];
    } else {
        [target fileManager:self didReceiveData:data];
        [target fileManagerDidFinishLoading:self];
    }
    return nil;
}

- (id)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically forTarget:(id <OFSFileManagerAsynchronousReadTarget, NSObject>)target;
{
    NSError *error = nil;
    if (![self writeData:data toURL:url atomically:atomically error:&error]) {
        [target fileManager:self didFailWithError:error];
    } else {
        [target fileManagerDidFinishLoading:self];
    }
    return nil;
}

@end

