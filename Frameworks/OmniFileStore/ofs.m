// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManagerAsynchronousReadTarget.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFSTool : NSObject <OFSDAVFileManagerAuthenticationDelegate>
@end

static NSString * const OFSToolErrorDomain = @"com.omnigroup.framework.omnifilestore.ofs";

#define OFSToolErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OFSToolErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OFSToolError(error, code, description, reason) OFSToolErrorWithInfo((error), (code), (description), (reason), nil)

enum {
    BadCommand = 1,
};

@implementation OFSTool

static void _log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void _log(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    CFStringRef str = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL/*formatOptions*/, (CFStringRef)format, args);
    va_end(args);
    
    CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault, str, kCFStringEncodingUTF8, 0/*lossByte*/);
    CFRelease(str);
    
    fwrite(CFDataGetBytePtr(data), 1, CFDataGetLength(data), stderr);
    CFRelease(data);
    fflush(stderr);
}

static NSURL *_url(NSString *str)
{
    NSURL *url = [NSURL URLWithString:str];
    if (![url scheme])
        url = [NSURL fileURLWithPath:str];
    return url;
}

- (BOOL)run:(NSError **)outError;
{
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];

    // cmd arg ...
    NSUInteger argumentCount = [arguments count];
    if (argumentCount < 2) {
        OFSToolError(outError, BadCommand, @"Bad command", @"No arguments given");
        return NO;
    }

    NSString *command = [arguments objectAtIndex:1];
    
    // +methodForSelector: always returns non-NULL these days (a forwarding IMP).
    SEL action = NSSelectorFromString([NSString stringWithFormat:@"command_%@:error:", command]);
    BOOL (*imp)(id self, SEL _cmd, NSArray *arguments, NSError **outError) = NULL;
    if ([self respondsToSelector:action])
        imp = (typeof(imp))[self methodForSelector:action];
    
    if (!imp) {
        OFSToolError(outError, BadCommand, @"Bad command", @"Unknown command");
        return NO;
    }
    return imp(self, action, [arguments subarrayWithRange:NSMakeRange(2, argumentCount - 2)], outError);
}

- (BOOL)command_ls:(NSArray *)arguments error:(NSError **)outError;
{
    if ([arguments count] == 0)
        arguments = [NSArray arrayWithObject:[[NSFileManager defaultManager] currentDirectoryPath]];
    
    for (NSString *arg in arguments) {
        NSURL *url = _url(arg);
        
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url error:outError] autorelease];
        if (!fileManager)
            return NO;
        
        NSArray *fileInfos = [fileManager directoryContentsAtURL:url havingExtension:nil error:outError];
        if (!fileInfos)
            return NO;
        
        for (OFSFileInfo *fileInfo in fileInfos)
            _log(@"%@ %ld %@\n", [fileInfo isDirectory] ? @"dir" : @"file", [fileInfo size], [fileInfo name]);
    }
    
    return YES;
}

- (BOOL)command_cp:(NSArray *)arguments error:(NSError **)outError;
{
    // For now, only supporting source->dst
    if ([arguments count] != 2) {
        OFSToolError(outError, BadCommand, @"Bad command", @"Need source and destination URLs.");
        return NO;
    }

    // Don't have streaming; just doing the lamest thing that could work.
    
    NSData *data;
    {
        NSURL *url = _url([arguments objectAtIndex:0]);
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url error:outError] autorelease];
        if (!fileManager)
            return NO;
        data = [fileManager dataWithContentsOfURL:url error:outError];
        if (!data)
            return NO;
    }
    
    {
        NSURL *url = _url([arguments objectAtIndex:1]);
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url error:outError] autorelease];
        if (![fileManager writeData:data toURL:url atomically:NO error:outError])
            return NO;
    }

    return YES;
}

#pragma mark -
#pragma mark OFSDAVFileManagerDelegate

- (NSURLCredential *)DAVFileManager:(OFSDAVFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // We don't prompt for credentials, just use whatever is in the keychain.
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    if ([challenge previousFailureCount] == 0)
        return [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:protectionSpace];
    return nil;
}

@end

int main(int argc, char *argv[])
{
    // Could obviously go further with this.
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    @try {
        NSError *error = nil;
        OFSTool *tool = [[[OFSTool alloc] init] autorelease];
        
        [OFSDAVFileManager setAuthenticationDelegate:tool];

        if (![tool run:&error]) {
            NSLog(@"Error: %@", [error toPropertyList]);
            return 1;
        }
        return 0;
    } @finally {
        [pool release];
    }
}
