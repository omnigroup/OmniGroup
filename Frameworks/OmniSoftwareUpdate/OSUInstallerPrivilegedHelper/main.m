// Copyright 2013-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <mach-o/dyld.h>

#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>

#import "OSUInstallerPrivilegedHelperProtocol.h"
#import "OSUInstallerPrivilegedHelperRights.h"
#import "OSUInstallerScript.h"
#import "OSUConnectionAudit.h"

static NSString * OSUInstallerPrivilegedHelperFileNameAndNumberErrorKey = @"com.omnigroup.OmniSoftwareUpdate.OSUInstallerPrivilegedHelper.ErrorFileLineAndNumber";

#define ERROR_FILENAME_AND_NUMBER \
    ([[[NSFileManager defaultManager] stringWithFileSystemRepresentation:__FILE__ length:strlen(__FILE__)] stringByAppendingFormat:@":%d", __LINE__])

@interface OSUInstallerPrivilegedHelper : NSObject <NSXPCListenerDelegate, OSUInstallerPrivilegedHelper> {
  @private
    NSUInteger _activeConnectionCount;
}

@end

#pragma mark -

@implementation OSUInstallerPrivilegedHelper

#pragma mark OSUInstallerPrivilegedHelper

- (void)getVersionWithReply:(void (^)(NSUInteger version))reply;
{
    reply(OSUInstallerPrivilegedHelperVersion);
}

- (void)runInstallerScriptWithArguments:(NSArray *)arguments localizationBundleURL:(NSURL *)bundleURL authorizationData:(NSData *)authorizationData reply:(void (^)(BOOL success, NSError *error))reply;
{
    _activeConnectionCount++;
    
    @try {
        __autoreleasing NSError *error = nil;
        NSBundle *localizationBundle = [NSBundle bundleWithURL:bundleURL];
        
        if (![self _validateAuthorizationData:authorizationData forRightWithName:OSUInstallUpdateRightName error:&error]) {
            reply(NO, error);
            return;
        }
        
        BOOL success = [OSUInstallerScript runWithArguments:arguments localizationBundle:localizationBundle error:&error];
        reply(success, error);
    } @finally {
        _activeConnectionCount--;
    }
}

- (void)removeItemAtURL:(NSURL *)itemURL trashDirectoryURL:(NSURL *)trashDirectoryURL authorizationData:(NSData *)authorizationData reply:(void (^)(BOOL success, NSError *error))reply;
{
    _activeConnectionCount++;
    
    @try {
        __autoreleasing NSError *error = nil;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // Use the same right as we use for updating, since we only ever do this as part of the update process.
        if (![self _validateAuthorizationData:authorizationData forRightWithName:OSUInstallUpdateRightName error:&error]) {
            reply(NO, error);
            return;
        }
        
        BOOL success = NO;
        
        if (trashDirectoryURL != nil) {
            NSURL *destinationURL = [trashDirectoryURL URLByAppendingPathComponent:[itemURL lastPathComponent]];
            while ([fileManager fileExistsAtPath:[destinationURL path]]) {
                // Add a timestamp to the destination file
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@" HH-mm-ss-SSS"];
                
                NSString *timestamp = [formatter stringFromDate:[NSDate date]];
                NSString *lastPathComponent = [itemURL lastPathComponent];
                NSString *basename = [lastPathComponent stringByDeletingPathExtension];
                NSString *extension = [lastPathComponent pathExtension];
                NSString *filename = [[basename stringByAppendingString:timestamp] stringByAppendingPathExtension:extension];
                
                destinationURL = [trashDirectoryURL URLByAppendingPathComponent:filename];
            }
            
            success = [fileManager moveItemAtURL:itemURL toURL:destinationURL error:&error];
        }
        
        // If we couldn't move it the the trash, just delete it outright
        if (!success) {
            success = [fileManager removeItemAtURL:itemURL error:&error];
        }
        
        reply(success, error);
    } @finally {
        _activeConnectionCount--;
    }
}

#pragma mark Private

- (AuthorizationRef)_createAuthorizationRefFromExternalAuthorizationData:(NSData *)authorizationData error:(NSError **)error;
{
    OSStatus status = noErr;
    AuthorizationRef authorizationRef = NULL;
    AuthorizationExternalForm authorizationExternalForm;

    if ([authorizationData length] != sizeof(authorizationExternalForm)) {
        if (error != NULL) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : @"AuthorizationExternalForm was the wrong length.",
                OSUInstallerPrivilegedHelperFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
            };
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errAuthorizationInvalidRef userInfo:userInfo];
        }
        return NULL;
    }
    
    [authorizationData getBytes:&authorizationExternalForm length:sizeof(authorizationExternalForm)];
    
    status = AuthorizationCreateFromExternalForm(&authorizationExternalForm, &authorizationRef);
    if (status != errAuthorizationSuccess || authorizationRef == NULL) {
        if (error != NULL) {
            NSDictionary *userInfo = @{
                OSUInstallerPrivilegedHelperFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
            };
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:userInfo];
        }
        return NULL;
    }
    
    return authorizationRef;
}

- (BOOL)_validateAuthorizationData:(NSData *)authorizationData forRightWithName:(NSString *)rightName error:(NSError **)error;
{
    AuthorizationRef authorizationRef = [self _createAuthorizationRefFromExternalAuthorizationData:authorizationData error:error];
    if (authorizationRef == NULL) {
        return NO;
    }
    
    @try {
        AuthorizationItem items[1] = {};
        AuthorizationRights rights = { .count = 1, .items = items};
        
        items[0].name = [OSUInstallUpdateRightName UTF8String];
        items[0].valueLength = 0;
        items[0].value = NULL;
        items[0].flags = 0;

        // The client should have pre-authorized these rights, but allow interaction here as a last resort.
        AuthorizationFlags flags = kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;
        OSStatus status = AuthorizationCopyRights(authorizationRef, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
        if (status != noErr) {
            if (error != NULL) {
                NSDictionary *userInfo = @{
                    OSUInstallerPrivilegedHelperFileNameAndNumberErrorKey : ERROR_FILENAME_AND_NUMBER,
                };
                *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:userInfo];
            }
            return NO;
        }
    } @finally {
        AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
        authorizationRef = NULL;
    }
    
    return YES;
}

#pragma mark NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection
{
    NSLog(@"listener:shouldAcceptNewConnection: %p", connection);
    if (!OSUCheckConnectionAuditToken(connection)) {
        NSLog(@"audit token rejected");
        return NO;
    }

    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUInstallerPrivilegedHelper)];
    connection.exportedObject = self;

    [connection resume];

    return YES;
}

@end

#pragma mark -

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        // Remove old versions which didn't check the code signing of the remote side of the connection
        unlink("/Library/PrivilegedHelperTools/com.omnigroup.OmniSoftwareUpdate.OSUInstallerPrivilegedHelper.7");
        unlink("/Library/PrivilegedHelperTools/com.omnigroup.OmniSoftwareUpdate.OSUInstallerPrivilegedHelper.6");
        unlink("/Library/PrivilegedHelperTools/com.omnigroup.OmniSoftwareUpdate.OSUInstallerPrivilegedHelper"); // versions before 6 didn't have the version in the name

        OSUInstallerPrivilegedHelper *helper = [[OSUInstallerPrivilegedHelper alloc] init];
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:OSUInstallerPrivilegedHelperJobLabel];

        [listener setDelegate:helper];
        [listener resume];
        
        [[NSRunLoop currentRunLoop] run];
    }

    return 0;
}

