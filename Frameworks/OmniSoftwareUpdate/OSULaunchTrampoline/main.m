// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>

/*
RCS_ID("$Id$")
*/

static BOOL _IsProcessRunning(pid_t pid)
{
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid, 0};
    struct kinfo_proc kp = {};
    size_t length = sizeof(kp);
    
    int rc = sysctl((int *)mib, 4, &kp, &length, NULL, 0);
    if (rc != -1 && length == sizeof(kp)) {
        return YES;
    }
    
    return NO;
}

static BOOL _WaitForProcessToExit(pid_t pid, NSTimeInterval timeout)
{
    NSTimeInterval limit = [NSDate timeIntervalSinceReferenceDate] + timeout;
    
    while (_IsProcessRunning(pid)) {
        if ([NSDate timeIntervalSinceReferenceDate] > limit) {
            return NO;
        }
        usleep(500000);
    }
    
    return YES;
}

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        if (arguments.count != 3) {
            NSLog(@"Usage: OSULaunchTrampoline <pid> <launch_path>");
            exit(1);
        }
        
        pid_t pid = [[arguments objectAtIndex:1] intValue];
        NSString *launchPath = [arguments objectAtIndex:2];

        if (!_WaitForProcessToExit(pid, 120)) {
            NSLog(@"Timed out waiting for process PID %d to terminate.", pid);
            exit(1);
        }

        NSArray *launchArguments = @[launchPath];
        NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:launchArguments];

        [task waitUntilExit];
        
        // unlink ourselves if we are in the temp directory
        const uint32_t MAX_PATH_LEN = 1024;
        char path[MAX_PATH_LEN + 1];
        uint32_t bufsize = sizeof(path);
        int rc = _NSGetExecutablePath(path, &bufsize);
        if (rc == 0) {
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSString *toolPath = [fileManager stringWithFileSystemRepresentation:path length:strlen(path)];
            NSString *temporaryDirectoryPath = NSTemporaryDirectory();
            if ([toolPath hasPrefix:temporaryDirectoryPath]) {
                __autoreleasing NSError *error = nil;
                if (![fileManager removeItemAtPath:toolPath error:&error]) {
                    NSLog(@"Error removing temporary copy of OSULaunchTrampoline: %@", error);
                }
            }
        }
        
        int terminationStatus = [task terminationStatus];
        if (terminationStatus != 0) {
            NSLog(@"Relaunch task failed with code: %d", terminationStatus);
            exit(terminationStatus);
        }
    }
    
    return 0;
}

