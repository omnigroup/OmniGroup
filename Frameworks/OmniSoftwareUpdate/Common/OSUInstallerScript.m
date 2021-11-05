// Copyright 2013-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <mach-o/getsect.h>
#import <mach-o/ldsyms.h>

#import <Foundation/Foundation.h>
#import "OSUErrorDomain.h"
#import "OSUInstallerScript.h"

@interface OSUInstallerScript ()

@property (nonatomic, readonly) NSBundle *localizationBundle;

@property (nonatomic, readonly) NSData *scriptData;
@property (nonatomic, readonly) NSString *scriptPath;
@property (nonatomic, readonly) NSArray *scriptArguments;

@property (nonatomic, copy) NSString *stdoutPath;
@property (nonatomic, copy) NSString *stderrPath;

@property (nonatomic, strong) NSFileHandle *stdoutFileHandle;
@property (nonatomic, strong) NSFileHandle *stderrFileHandle;

@end

#pragma mark -

@implementation OSUInstallerScript

+ (BOOL)runWithArguments:(NSArray *)arguments localizationBundle:(NSBundle *)localizationBundle error:(NSError **)error;
{
    OSUInstallerScript *installerScript = nil;
    
    @try {
        installerScript = [[OSUInstallerScript alloc] initWithArguments:arguments localizationBundle:localizationBundle error:error];;
        if (installerScript == nil) {
            return NO;
        }
        
        BOOL success = [installerScript run:error];

        installerScript = nil;

        return success;
    } @finally {
        installerScript = nil;
    }

    // Unreachable
    return NO;
}

- (id)initWithArguments:(NSArray *)arguments localizationBundle:(NSBundle *)localizationBundle error:(NSError **)error;
{
    self = [super init];
    
    NSAssert(arguments != nil, @"arguments is a required parameter");
    if (arguments == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
        }
        return nil;
    }
    
    unsigned long length = 0;
    uint8_t *ptr = getsectiondata(&_mh_execute_header, "__TEXT", "__installer_sh", &length);
    if (ptr == NULL) {
        if (error != NULL) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: NSLocalizedString(@"Unable to install update", @"error description - OSUInstaller.sh is missing"),
                NSLocalizedFailureReasonErrorKey : NSLocalizedString(@"Cannot read the installer script __TEXT section.", @"error reason - OSUInstaller.sh is missing")
            };
            *error = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToUpgrade userInfo:userInfo];
        }
        return nil;
    }
    
    NSString *tmpDirectory = NSTemporaryDirectory();
    NSString *scriptFilename = [NSString stringWithFormat:@"OSUInstaller-%d.sh", getpid()];
    NSString *scriptPath = [tmpDirectory stringByAppendingPathComponent:scriptFilename];

    _scriptData = [[NSData alloc] initWithBytes:ptr length:length];
    _scriptPath = [scriptPath copy];
    _scriptArguments = [arguments copy];
    _localizationBundle = localizationBundle;

    return self;
}


- (BOOL)run:(NSError **)error;
{
    if (![self createTemporaryScriptExecutableFile:error]) {
        return NO;
    }
    
    if (![self configureOutputFiles:error]) {
        return NO;
    }
    
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = self.scriptPath;
        task.arguments = self.scriptArguments;
        task.standardOutput = self.stdoutFileHandle;
        task.standardError = self.stderrFileHandle;
        [task launch];
        
        [task waitUntilExit];
        
        int terminationStatus = [task terminationStatus];
        
        [self.stdoutFileHandle closeFile];
        [self.stderrFileHandle closeFile];
        
        NSData *stdoutData = [NSData dataWithContentsOfFile:self.stdoutPath options:0 error:error];
        if (stdoutData == nil) {
            return NO;
        }

        NSData *stderrData = [NSData dataWithContentsOfFile:self.stderrPath options:0 error:error];
        if (stderrData == nil) {
            return NO;
        }

        if (terminationStatus != 0) {
            if (error != NULL) {
                NSBundle *bundle = self.localizationBundle;
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to install update", @"OmniSoftwareUpdate", bundle, @"error description - could not move application into place during install");
                NSString *reason = NSLocalizedStringFromTableInBundle(@"Install script failed.", @"OmniSoftwareUpdate", bundle, @"error reason");

                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                userInfo[NSLocalizedDescriptionKey] = description;
                userInfo[NSLocalizedFailureReasonErrorKey] = reason;
                userInfo[@"stderr"] = [self reportableValueForCapturedOutputData:stderrData];
                userInfo[@"stdout"] = [self reportableValueForCapturedOutputData:stdoutData];

                *error = [NSError errorWithDomain:OSUErrorDomain code:OSUUnableToUpgrade userInfo:userInfo];
            }
            
            return NO;
        }
    } @finally {
        [self cleanupTemporaryFiles];
    }

    return YES;
}

- (BOOL)createTemporaryScriptExecutableFile:(NSError **)error;
{
    if (![self.scriptData writeToFile:self.scriptPath options:0 error:error]) {
        return NO;
    }
    
    NSDictionary *attributes = @{
        NSFilePosixPermissions : @(0500)
    };
    
    return [[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:self.scriptPath error:error];
}

- (BOOL)configureOutputFiles:(NSError **)error;
{
    NSString *tmpDirectory = NSTemporaryDirectory();
    NSString *stdoutFilename = [NSString stringWithFormat:@"OSUInstaller-STDOUT-%d", getpid()];
    NSString *stderrFilename = [NSString stringWithFormat:@"OSUInstaller-STDERR-%d", getpid()];
    
    self.stdoutPath = [tmpDirectory stringByAppendingPathComponent:stdoutFilename];
    self.stderrPath = [tmpDirectory stringByAppendingPathComponent:stderrFilename];
    
    // NSFileHandle requires that the file already exist.
    
    if (![[NSData data] writeToFile:self.stdoutPath options:0 error:error]) {
        return NO;
    }

    if (![[NSData data] writeToFile:self.stderrPath options:0 error:error]) {
        return NO;
    }

    self.stdoutFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.stdoutPath];
    self.stderrFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.stderrPath];

    return YES;
}

- (void)cleanupTemporaryFiles;
{
    for (NSString *path in @[self.scriptPath, self.stdoutPath, self.stderrPath]) {
        __autoreleasing NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
            NSLog(@"Error cleaning up temporary file at path: %@ - %@", path, error);
        }
    }
}

- (id)reportableValueForCapturedOutputData:(NSData *)data;
{
    if (data == nil) {
        return @"<no data>";
    }

    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string == nil) {
        string = [[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding];
    }
    
    if (string == nil) {
        return data;
    }

    return string;
}

@end

