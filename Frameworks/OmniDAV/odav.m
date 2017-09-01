// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OmniBase.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDAV/ODAVAsynchronousOperation.h>
#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVOperation.h>
#import <OmniFoundation/OFCredentials.h>
#import <readpassphrase.h>
#import <OmniCommandLine/OCLCommand.h>

RCS_ID("$Id$");

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

#if 0
@interface OFSTool : NSObject <OFSFileManagerDelegate>
@end

static NSString * const OFSToolErrorDomain = @"com.omnigroup.framework.omnifilestore.ofs";

#define OFSToolErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OFSToolErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OFSToolError(error, code, description, reason) OFSToolErrorWithInfo((error), (code), (description), (reason), nil)

enum {
    BadCommand = 1,
};

@implementation OFSTool
{
    id <ODAVAsynchronousOperation> _asyncOperation;
    NSError *_asyncError;
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
        NSString *reason = [NSString stringWithFormat:@"Unknown command \"%@\".", command];
        OFSToolError(outError, BadCommand, @"Bad command", reason);
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
        
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url delegate:self error:outError] autorelease];
        if (!fileManager)
            return NO;
        
        NSArray *fileInfos = [fileManager directoryContentsAtURL:url havingExtension:nil error:outError];
        if (!fileInfos)
            return NO;
        
        for (ODAVFileInfo *fileInfo in fileInfos)
            _log(@"%@ %lld %@ (date:%@ ETag:%@)\n", fileInfo.isDirectory ? @"dir" : @"file", fileInfo.size, fileInfo.name, [fileInfo.lastModifiedDate xmlString], fileInfo.ETag);
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
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url delegate:self error:outError] autorelease];
        if (!fileManager)
            return NO;
        data = [fileManager dataWithContentsOfURL:url error:outError];
        if (!data)
            return NO;
    }
    
    {
        NSURL *url = _url([arguments objectAtIndex:1]);
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url delegate:self error:outError] autorelease];
        if (![fileManager writeData:data toURL:url atomically:NO error:outError])
            return NO;
    }

    return YES;
}

- (BOOL)command_acp:(NSArray *)arguments error:(NSError **)outError;
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
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url delegate:self error:outError] autorelease];
        if (!fileManager)
            return NO;
        data = [fileManager dataWithContentsOfURL:url error:outError];
        if (!data)
            return NO;
    }
    
    {
        NSURL *url = _url([arguments objectAtIndex:1]);
        OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:url delegate:self error:outError] autorelease];
        
        _asyncOperation = [[fileManager asynchronousWriteData:data toURL:url] retain];
        _asyncOperation.didSendBytes = ^(id <ODAVAsynchronousOperation> op, long long byteCount){
            long long expectedLength = op.expectedLength;
            if (expectedLength == NSURLResponseUnknownLength)
                NSLog(@"%qd bytes processed", op.processedLength);
            else
                NSLog(@"%.1f%%", 100.0 * (double)op.processedLength / expectedLength);
        };
        _asyncOperation.didFinish = ^(id <ODAVAsynchronousOperation> op, NSError *errorOrNil){
            _asyncError = [errorOrNil retain];
            [_asyncOperation autorelease];
            _asyncOperation = nil;
        };
        [_asyncOperation startOperationOnQueue:nil];
        
        while (_asyncOperation) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            [pool drain];
        }
        
        if (_asyncError) {
            *outError = [[_asyncError retain] autorelease];
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)command_mv:(NSArray *)arguments error:(NSError **)outError;
{
    if ([arguments count] != 2) {
        OFSToolError(outError, BadCommand, @"Bad command", @"Need source and destination URLs.");
        return NO;
    }
    
    NSURL *sourceURL = _url([arguments objectAtIndex:0]);
    NSURL *destinationURL = _url([arguments objectAtIndex:1]);
    
    
    OFSFileManager *fileManager = [[[OFSFileManager alloc] initWithBaseURL:sourceURL delegate:self error:outError] autorelease];
    if (!fileManager)
        return NO;
    
    if (![fileManager moveURL:sourceURL toURL:destinationURL error:outError]) {
        NSLog(@"Unable to move %@ to %@", sourceURL, destinationURL);
        return NO;
    }
    
    return YES;
}

#pragma mark -
#pragma mark ODAVFileManagerDelegate

- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // We don't prompt for credentials, just use whatever is in the keychain.
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    if ([challenge previousFailureCount] == 0) {
//        NSString *serviceIdentifier = OFMakeServiceIdentifier(manager.baseURL, username, realm);
//        NSURLCredential *credentials = OFReadCredentialsForServiceIdentifier(serviceIdentifier);
//        if (credentials)
//            return credentials;
        
        
        NSLog(@"No credentials found in keychain for protection space");
        NSLog(@"  realm:%@", protectionSpace.realm);
        NSLog(@"  receivesCredentialSecurely:%d", protectionSpace.receivesCredentialSecurely);
        NSLog(@"  isProxy:%d", protectionSpace.isProxy);
        NSLog(@"  host:%@", protectionSpace.host);
        NSLog(@"  port:%ld", protectionSpace.port);
        NSLog(@"  proxyType:%@", protectionSpace.proxyType);
        NSLog(@"  protocol:%@", protectionSpace.protocol);
        NSLog(@"  authenticationMethod:%@", protectionSpace.authenticationMethod);
        NSLog(@"  distinguishedNames:%@", protectionSpace.distinguishedNames);
        
        char username[512];
        fputs("Username: ", stdout);
        if (!fgets(username, sizeof(username), stdin))
            return nil;
        char *newline = strchr(username, '\n');
        if (newline)
            *newline = '\0';
        
        char password[512];
        if (!readpassphrase("Password: ", password, sizeof(password), 0/*options*/))
            return nil;
        
        OFWriteCredentialsForServiceIdentifier(@"ofs", [NSString stringWithUTF8String:username], [NSString stringWithUTF8String:password]);
        return OFReadCredentialsForServiceIdentifier(@"ofs");
    }
    
    return nil;
}

- (void)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBFinishPortingWithNote("<bug:///147929> (iOS-OmniOutliner Unassigned: Implement -[OFSTool fileManager:validateCertificateForChallenge:])");
}

@end
#endif

int main(int argc, char *argv[])
{
    // Could obviously go further with this.
    
    @autoreleasepool {
        OCLCommand *strongCommand = [OCLCommand command];
        __weak OCLCommand *cmd = strongCommand;

        ODAVConnection *connection = [[ODAVConnection alloc] init];
        __block NSUInteger commandsRunning = 0;
        
        connection.validateCertificateForChallenge = ^(NSURLAuthenticationChallenge *challenge){
            OBFinishPortingLater("<bug:///147928> (iOS-OmniOutliner Bug: Adding trust for certificate blindly - in validateCertificateForChallenge block)");
            OFAddTrustForChallenge(challenge, OFCertificateTrustDurationSession);
        };
        connection.findCredentialsForChallenge = ^NSURLCredential *(NSURLAuthenticationChallenge *challenge){
            OBFinishPortingLater("<bug:///147927> (iOS-OmniOutliner Bug: Just making up credentials in findCredentialsForChallenge block)");
            return [NSURLCredential credentialWithUser:@"test" password:@"password" persistence:NSURLCredentialPersistenceForSession];
        };
        
        [cmd add:@"ls url" with:^{
            NSURL *url = cmd[@"url"];
            commandsRunning++;
            [connection fileInfosAtURL:url ETag:nil depth:ODAVDepthChildren completionHandler:^(ODAVMultipleFileInfoResult *properties, NSError *errorOrNil) {
                if (errorOrNil) {
                    [errorOrNil log:@"Error getting file list for %@", url];
                } else {
                    _log(@"%@ as of %@:\n", url, [properties.serverDate xmlString]);
                    for (ODAVFileInfo *fileInfo in properties.fileInfos)
                        _log(@"%@ %lld %@ (date:%@ ETag:%@)\n", fileInfo.isDirectory ? @"dir" : @"file", fileInfo.size, fileInfo.name, [fileInfo.lastModifiedDate xmlString], fileInfo.ETag);
                }
                OBASSERT([NSThread isMainThread]);
                commandsRunning--;
            }];
        }];
        
        [cmd add:@"put file url" with:^{
            NSURL *sourceURL = cmd[@"file"];
            NSURL *destURL = cmd[@"url"];
            
            NSError *error;
            NSData *sourceData = [[NSData alloc] initWithContentsOfURL:sourceURL options:NSDataReadingMappedIfSafe error:&error];
            if (!sourceData) {
                [error log:@"Error reading %@.", sourceURL];
                return;
            }
            
            commandsRunning++;
            [connection putData:sourceData toURL:destURL completionHandler:^(ODAVURLResult *result, NSError *errorOrNil){
                if (errorOrNil) {
                    [errorOrNil log:@"Error writing to %@", destURL];
                } else {
                    _log(@"File uploaded to %@", result.URL);
                }
                OBASSERT([NSThread isMainThread]);
                commandsRunning--;
            }];
        }];

        [cmd add:@"get url file" with:^{
            NSURL *sourceURL = cmd[@"url"];
            NSURL *destURL = cmd[@"file"];
            
            commandsRunning++;
            [connection getContentsOfURL:sourceURL ETag:nil completionHandler:^(ODAVOperation *op){
                if (op.error) {
                    [op.error log:@"Error getting contents of %@", sourceURL];
                } else {
                    NSError *error;
                    if (![op.resultData writeToURL:destURL options:NSDataWritingAtomic error:&error])
                        [error log:@"Error writing to %@", destURL];
                }
                OBASSERT([NSThread isMainThread]);
                commandsRunning--;
            }];
        }];
        
        NSMutableArray *argumentStrings = [NSMutableArray array];
        for (int argi = 1; argi < argc; argi++)
            [argumentStrings addObject:[NSString stringWithUTF8String:argv[argi]]];
        [strongCommand runWithArguments:argumentStrings];
        
        while (commandsRunning > 0) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }
    }
    
    return 0;
}

