// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import "ODAVTestServer.h"

RCS_ID("$Id$")

@implementation ODAVTestServer
{
    NSString *httpd;
    NSString *apacheSroot;
    NSTask *apacheTask;
    unsigned apachePort;
}

- (instancetype)init
{
    if (!(self = [super init])) {
        return nil;
    }
    
    char *apachepath = getenv("APACHE24");
    if (!apachepath)
        apachepath = "/usr/sbin/httpd";
    if (!apachepath || access(apachepath, X_OK) != 0)
        return nil;
    httpd = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:apachepath length:strlen(apachepath)];
    apacheSroot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFSEncryptionTests-apache24"];
    apachePort = arc4random_uniform(32767) + 20000;
    
    return self;
}

@synthesize process = apacheTask;

- (int)processIdentifier;
{
    if (!apacheSroot)
        return 0;

    NSString *pidNumber = [NSString stringWithContentsOfFile:[apacheSroot stringByAppendingPathComponent:@"var/httpd.pid"] encoding:NSASCIIStringEncoding error:NULL];
    
    if (!pidNumber)
        return 0;
    
    return [pidNumber intValue];
}

- (NSURL *)baseURL;
{
    NSURLComponents *cmp = [[NSURLComponents alloc] init];
    
    cmp.scheme = @"http";
    cmp.host = @"localhost";
    cmp.port = @(apachePort);
    cmp.path = @"/";
    
    return [cmp URL];
}

- (NSString *)documentPath;
{
    return [apacheSroot stringByAppendingPathComponent:@"htdocs"];
}

- (NSDictionary *)substitutions;
{
    return @{
             @"BASE_PATH": apacheSroot,
             @"VAR_PATH": [apacheSroot stringByAppendingPathComponent:@"var"],
             @"HTDOCS_PATH": [apacheSroot stringByAppendingPathComponent:@"htdocs"],
             @"SERVER_NAME": @"localhost",
             @"LISTEN_PORT": [NSString stringWithFormat:@"%u", apachePort],
             @"MODULES": @"libexec/apache2"
    };
}

- (void)startWithConfiguration:(NSString *)configfile;
{
    OBPRECONDITION(apacheTask == nil);
    
    int oldPid = [self processIdentifier];
    if (oldPid) {
        if (kill(oldPid, SIGTERM) == 0) {
            NSLog(@"Sent SIGTERM to old process %d", oldPid);
            for (int i = 0; i < 10; i++) {
                usleep(50000 * i);
                if (kill(oldPid, 0) != 0)
                    break;
            }
        }
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:[apacheSroot stringByAppendingPathComponent:@"htdocs"] withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![fm createDirectoryAtPath:[apacheSroot stringByAppendingPathComponent:@"var"] withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Can't set up test dir: %@", error);
        return;
    }
    
    NSString *conffilePath = [apacheSroot stringByAppendingPathComponent:@"apache24.conf"];
    if (![configfile writeToFile:conffilePath atomically:NO encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"Can't set up test config: %@", error);
    }
    
    apacheTask = [[NSTask alloc] init];
    
    apacheTask.launchPath = httpd;
    apacheTask.currentDirectoryPath = apacheSroot;
    apacheTask.arguments = @[ @"-f", conffilePath,
                              @"-D", @"FOREGROUND" ];
    
    [apacheTask launch];
    NSLog(@"Starting test apache as pid %d", apacheTask.processIdentifier);
    NSLog(@"  filesystem path: %@", apacheSroot);
    
    /* Wait for Apache to write its pid to the configured path --- this lets us wait until it has finished reading its config file, etc., and is basically running, before trying to run any tests against it. */
    for(int i = 0; i < 10; i++) {
        usleep(50000);
        int pid = [self processIdentifier];
        if (pid == apacheTask.processIdentifier)
            break;
        if (!apacheTask.running) {
            NSLog(@"error: apacheTask exited (reason=%ld status=%d)",
                  (long)apacheTask.terminationReason,
                  apacheTask.terminationStatus);
            return;
        }
        if (i > 8) {
            NSLog(@"warning: launched pid %d, but httpd.pid contains %d", apacheTask.processIdentifier, pid);
        }
    }
}

- (void)stop
{
    if (apacheTask) {
        if (apacheSroot) {
            int pid = self.processIdentifier;
            if (pid) {
                if (kill(pid, SIGWINCH /* graceful-stop */) == 0) {
                    NSLog(@"Asking httpd pid %d to shut down", pid);
                    for (int i = 0; i < 10; i++) {
                        usleep(50000 * i);
                        if (kill(pid, 0) != 0)
                            break;
                    }
                }
            }
        }
        
        if (apacheTask.running) {
            if (kill(apacheTask.processIdentifier, SIGTERM) == 0) {
                NSLog(@"Stopping httpd pid %d", apacheTask.processIdentifier);
            }
            for(int i = 0; i < 10; i ++) {
                usleep(500000);
                if (!apacheTask.running)
                    break;
            }
        }
        
        if (apacheTask.running) {
            int pid = apacheTask.processIdentifier;
            NSLog(@"Gracelessly killing httpd pid %d", pid);
            if (kill(pid, SIGKILL) != 0) {
                NSLog(@"kill(%d): %s", pid, strerror(errno));
            }
        }
    }
}

@end

