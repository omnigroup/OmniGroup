// Copyright 2008-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileManager.h>

#import <OmniFileStore/OFSFileFileManager.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/Errors.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>

#import "OFSFileOperation.h"
#import "OFSFileInfo.h"

RCS_ID("$Id$");

NSInteger OFSFileManagerDebug = 0;


// If the file name ends in a number, we are likely dealing with a duplicate.
void OFSFileManagerSplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter)
{
    [originalName splitName:outName andCounter:outCounter];
}

#if NS_BLOCKS_AVAILABLE
@interface OFSFileOperationBlockTarget : OFObject <OFSFileManagerAsynchronousOperationTarget>
@property (copy) void (^receiveDataBlock)(NSData *);
@property (copy) void (^progressBlock)(long long);
@property (copy) void (^completionBlock)(NSError *);
@end
#endif

@implementation OFSFileManager

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFSFileManagerDebug = [[NSUserDefaults standardUserDefaults] integerForKey:@"OFSFileManagerDebug"];
    
    // Hard to turn this on via defaults write on the device...
#ifdef DEBUG_kc
    OFSFileManagerDebug = 9;
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
        
        NSString *title =  NSLocalizedStringFromTableInBundle(@"An error has occurred.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Ensure that the server address, user name, and password are correct and please try again.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        OFSError(outError, OFSNoFileManagerForScheme, title, description);
        
        NSLog(@"Error: No scheme specific file manager for scheme \"%@\". Cannot create file manager.", scheme);
        
        [self release];
        return nil;
    }
    
    if (!(self = [super init]))
        return nil;

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

- (id <OFSAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url withTarget:(id <OFSFileManagerAsynchronousOperationTarget>)target;
{
    return [[[OFSFileOperation alloc] initWithFileManager:self readingURL:url target:target] autorelease];
}

- (id <OFSAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically withTarget:(id <OFSFileManagerAsynchronousOperationTarget>)target;
{
    return [[[OFSFileOperation alloc] initWithFileManager:self writingData:data atomically:atomically toURL:url target:target] autorelease];
}

#if NS_BLOCKS_AVAILABLE
- (id <OFSAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url receiveDataBlock:(void (^)(NSData *))receiveDataBlock progressBlock:(void (^)(long long))progressBlock completionBlock:(void (^)(NSError *))completionBlock;
{
    if (progressBlock == NULL && receiveDataBlock == NULL && completionBlock == NULL)
        return [self asynchronousReadContentsOfURL:url withTarget:nil];

    OFSFileOperationBlockTarget *blockTarget = [[OFSFileOperationBlockTarget alloc] init];
    blockTarget.receiveDataBlock = receiveDataBlock;
    blockTarget.progressBlock = progressBlock;
    blockTarget.completionBlock = completionBlock;
    id <OFSAsynchronousOperation> operation = [self asynchronousReadContentsOfURL:url withTarget:blockTarget];
    [blockTarget release];
    return operation;
}

- (id <OFSAsynchronousOperation>)asynchronousWriteData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically progressBlock:(void (^)(long long))progressBlock completionBlock:(void (^)(NSError *))completionBlock;
{
    if (progressBlock == NULL && completionBlock == NULL)
        return [self asynchronousWriteData:data toURL:url atomically:atomically withTarget:nil];

    OFSFileOperationBlockTarget *blockTarget = [[OFSFileOperationBlockTarget alloc] init];
    blockTarget.progressBlock = progressBlock;
    blockTarget.completionBlock = completionBlock;
    id <OFSAsynchronousOperation> operation = [self asynchronousWriteData:data toURL:url atomically:atomically withTarget:blockTarget];
    [blockTarget release];
    return operation;
}
#endif

- (NSURL *)availableURL:(NSURL *)startingURL;
{
    BOOL isFileURL = [startingURL isFileURL];
    NSString *baseName = [OFSFileInfo nameForURL:startingURL];
    NSURL *directoryURL = OFSDirectoryURLForURL(startingURL);
    
    NSString *extension = [baseName pathExtension];
    
    BOOL shouldContainExtension = ![NSString isEmptyString:extension];
    
    NSString *name;
    NSUInteger counter;
    NSString *urlName = [baseName stringByDeletingPathExtension];
    
    OFSFileManagerSplitNameAndCounter(urlName, &name, &counter);
    
    NSURL *result = nil;
    while (!result) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        
        NSString *fileName = nil;
        if (shouldContainExtension) {
            fileName = [[NSString alloc] initWithFormat:@"%@.%@", name, extension];
        }
        else {
            fileName = [[NSString alloc] initWithString:name];
        }
        
        NSLog(@"%@", fileName);
        
        NSURL *urlCheck = isFileURL ? OFSFileURLRelativeToDirectoryURL(directoryURL, fileName) : OFSURLRelativeToDirectoryURL(directoryURL, [fileName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
        [fileName release];

        NSError *error = nil;
        OBASSERT([self respondsToSelector:@selector(fileInfoAtURL:error:)]);
        OFSFileInfo *fileCheck = [self fileInfoAtURL:urlCheck error:&error];  // all OFSFileManagers implement OFSConcreteFileManager, so this should be safe
        if (error) {
            NSLog(@"%@", error);
            return nil;
        }
        
        if (![fileCheck exists]) {
            result = [[fileCheck originalURL] copy];
        } else {
            if (counter == 0)
                counter = 2; // First duplicate should be "Foo 2".
            
            if (shouldContainExtension) {
                fileName = [[NSString alloc] initWithFormat:@"%@ %d.%@", name, counter, extension];
            }
            else {
                fileName = [[NSString alloc] initWithFormat:@"%@ %d", name, counter];
            }
            
            counter++;
            
            urlCheck = isFileURL ? OFSFileURLRelativeToDirectoryURL(directoryURL, fileName) : OFSURLRelativeToDirectoryURL(directoryURL, [fileName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
            [fileName release];
            fileCheck = [self fileInfoAtURL:urlCheck error:&error];
            if (error){
                NSLog(@"%@", error);
                return nil;
            }
            
            if (![fileCheck exists])
                result = [[fileCheck originalURL] copy];
        }
        
        [pool release];
    }
    
    return [result autorelease];
}

@end

#if NS_BLOCKS_AVAILABLE

@implementation OFSFileOperationBlockTarget
{
    long long _processedByteCount;
}

@synthesize receiveDataBlock = _receiveDataBlock, progressBlock = _progressBlock, completionBlock = _completionBlock;

- (void)dealloc;
{
    [_receiveDataBlock release];
    [_progressBlock release];
    [_completionBlock release];
    [super dealloc];
}

- (void)fileManager:(OFSFileManager *)fileManager operationDidFinish:(id <OFSAsynchronousOperation>)operation withError:(NSError *)error;
{
    if (_completionBlock != NULL)
        _completionBlock(error);
}

// For write operations, the 'didProcessBytes' will be called. For read operations, the 'didReceiveData' will be called if present, otherwise the didProcessBytes.
- (void)fileManager:(OFSFileManager *)fileManager operation:(id <OFSAsynchronousOperation>)operation didReceiveData:(NSData *)data;
{
    if (_receiveDataBlock != NULL)
        _receiveDataBlock(data);

    if (_progressBlock != NULL) {
        _processedByteCount += [data length];
        _progressBlock(_processedByteCount);
    }
}

- (void)fileManager:(OFSFileManager *)fileManager operation:(id <OFSAsynchronousOperation>)operation didProcessBytes:(long long)processedBytes;
{
    OBASSERT(_receiveDataBlock == NULL);
    if (_progressBlock != NULL)
        _progressBlock(processedBytes);
}

@end

#endif
