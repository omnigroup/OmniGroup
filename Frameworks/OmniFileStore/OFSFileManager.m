// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSFileManager.h>

#import <OmniFileStore/OFSFileFileManager.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/Errors.h>

#import "OFSFileOperation.h"
#import "OFSFileInfo.h"

RCS_ID("$Id$");

NSInteger OFSFileManagerDebug = 0;


// If the file name ends in a number, we are likely dealing with a duplicate.
void OFSFileManagerSplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter)
{
    NSString *name = originalName;
    NSUInteger counter = 0;
    NSRange notNumberRange = [name rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet] options:NSBackwardsSearch];
    
    // Has at least one digit at the end and isn't all digits?
    if (notNumberRange.length > 0 && NSMaxRange(notNumberRange) < [name length]) {
        // Is there a space before the digits?
        if ([name characterAtIndex:NSMaxRange(notNumberRange) - 1] == ' ') {
            counter = [[name substringFromIndex:NSMaxRange(notNumberRange)] intValue];
            name = [name substringToIndex:NSMaxRange(notNumberRange) - 1];
        }
    }
    
    *outName = name;
    *outCounter = counter;
}

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

- (NSURL *)availableURL:(NSURL *)startingURL;
{
    BOOL isFileURL = [startingURL isFileURL];
    NSString *baseName = [OFSFileInfo nameForURL:startingURL];
    NSURL *directoryURL = OFSDirectoryURLForURL(startingURL);
    
    NSString *extension = [baseName pathExtension];
    
    NSString *name;
    NSUInteger counter;
    NSString *urlName = [baseName stringByDeletingPathExtension];
    
    OFSFileManagerSplitNameAndCounter(urlName, &name, &counter);
    
    NSURL *result = nil;
    while (!result) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSString *fileName = [[NSString alloc] initWithFormat:@"%@.%@", name, extension];
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
            
            fileName = [[NSString alloc] initWithFormat:@"%@ %d.%@", name, counter, extension];
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

