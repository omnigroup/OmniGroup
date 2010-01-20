// Copyright 2001-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUCheckOperation.h"

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/OFVersionNumber.h>

#import "OSUPreferences.h"
#import "OSUChecker.h"

RCS_ID("$Id$");

#define ImpossibleTerminationStatus 0xEFFACED

@interface OSUCheckOperation (Private)
- (void)_fetchSubprocessNote:(NSNotification *)note;
@end

@implementation OSUCheckOperation

- initForQuery:(BOOL)doQuery url:(NSURL *)url licenseType:(NSString *)licenseType;
{
    OBPRECONDITION(url);
    OBPRECONDITION(licenseType); // App might not have set it yet; this is considered an error, but we should send *something*
    
    if (!licenseType)
        licenseType = OSULicenseTypeUnset;

    OFVersionNumber *versionNumber = [OSUChecker OSUVersionNumber];
    if (!versionNumber)
        versionNumber = [[[OFVersionNumber alloc] initWithVersionString:@"1.0"] autorelease];
    
#if 0
    // This doesn't work?
    NSString *helperPath = [OMNI_BUNDLE pathForAuxiliaryExecutable:@"OmniSoftwareUpdateCheck"];
#else
    NSString *helperPath = [OMNI_BUNDLE pathForResource:@"OmniSoftwareUpdateCheck" ofType:@""];
#endif
    if (helperPath == nil) {
#ifdef DEBUG
        NSLog(@"Missing resource OmniSoftwareUpdateCheck; can't check for updates");
#endif
        return nil;
    }
    
    _terminationStatus = ImpossibleTerminationStatus;

    _url = [url copy];
    _pipe = [[NSPipe pipe] retain];
    _task = [[NSTask alloc] init];
    [_task setStandardOutput:_pipe];
    
    // [wiml, march 2007]: We used to redirect stderr to /dev/null to hide a spurious warning due to an Apple bug, but that was in 2002; the warning's gone now.
    // [checker setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    
    [_task setLaunchPath:helperPath];
    
    // If we aren't actually submitting the query, this is probably due to the user popping up the sheet in the preferences to see what we *would* submit.
    BOOL includeHardwareDetails = !doQuery || [[OSUPreferences includeHardwareDetails] boolValue];
    NSString *withHardware = includeHardwareDetails ? @"with-hardware" : @"without-hardware";
    
    NSString *host = [url host];
    if ([NSString isEmptyString:host]) {
        // A file URL for testing?
        OBASSERT([url isFileURL]);
        host = @"localhost"; // needed to not have an empty array below and for the checker to determine network availability.
    }
    
    OSUChecker *checker = [OSUChecker sharedUpdateChecker];
    
    // Send the current track to the server so it can make decisions about what we'll see.  In particular, this means that we will no longer perform client side track subsumption _and_ if you switch to a final build, you'll no longer see beta/sneakypeak builds until the next time you run one of those.
    NSString *track = [checker applicationTrack];
    
    NSArray *arguments = [NSArray arrayWithObjects:host, [url absoluteString],
                          [checker applicationIdentifier],
                          [checker applicationEngineeringVersion],
                          track,
                          withHardware,
                          doQuery ? @"query" : @"report",
                          licenseType,
                          [versionNumber cleanVersionString],
                          nil];
    [_task setArguments:arguments];
    //NSLog(@"Running %@ with arguments %@", helperPath, arguments);
    
    return self;
}

- (void)dealloc;
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    [center removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:nil];
    [center removeObserver:self name:NSTaskDidTerminateNotification object:nil];
    
    if (_task) {
        if ([_task isRunning])
            [_task terminate];
        [_task release];
        _task = nil;
    }
    
    if (_pipe) {
        [[_pipe fileHandleForReading] closeFile];
        [_pipe release];
        _pipe = nil;
    }
    
    [_output release];
    _output = nil;
    
    [_url release];
    
    [super dealloc];
}

- (NSURL *)url;
{
    return _url;
}

- (void)runAsynchronously;
{
    OBPRECONDITION(_runType == OSUCheckOperationHasNotRun);
    
    if (_runType != OSUCheckOperationHasNotRun)
        return;
    
    _runType = OSUCheckOperationRunAsynchronously;
    
    NSFileHandle *taskOutput = [[_task standardOutput] fileHandleForReading];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_fetchSubprocessNote:) name:NSFileHandleReadToEndOfFileCompletionNotification object:taskOutput];
    [center addObserver:self selector:@selector(_fetchSubprocessNote:) name:NSTaskDidTerminateNotification object:_task];
    
    [taskOutput readToEndOfFileInBackgroundAndNotify];
    [_task launch];
}

- (NSData *)runSynchronously;
{
    OBPRECONDITION(_runType == OSUCheckOperationHasNotRun);

    if (_runType != OSUCheckOperationHasNotRun)
        return nil;
    
    _runType = OSUCheckOperationRunSynchronously;
    
    [_task launch];
    return [[[_task standardOutput] fileHandleForReading] readDataToEndOfFile];
}

@synthesize runType = _runType;
@synthesize initiatedByUser = _initiatedByUser;

- (void)waitUntilExit;
{
    [_task waitUntilExit];
}

- (NSData *)output;
{
    return _output;
}

@synthesize terminationStatus = _terminationStatus;

@end

NSString * const OSUCheckOperationCompletedNotification = @"OSUCheckOperationCompleted";

@implementation OSUCheckOperation (Private)

- (void)_fetchSubprocessNote:(NSNotification *)note;
{
    if ([[note name] isEqual:NSFileHandleReadToEndOfFileCompletionNotification] &&
        [note object] == [_pipe fileHandleForReading]) {
        [_output autorelease];
        _output = [[[note userInfo] objectForKey:NSFileHandleNotificationDataItem] retain];
    }
    
    if ([[note name] isEqual:NSTaskDidTerminateNotification] &&
        [note object] == _task) {
        _terminationStatus = [_task terminationStatus];
    }
    
    // We are expecting both notifications from our task/handle.  Make sure we don't send a notification for 'read all the output' and then another for 'task terminated'.
    if (_output == nil || _terminationStatus == ImpossibleTerminationStatus)
        return;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OSUCheckOperationCompletedNotification object:self userInfo:nil];
}

@end
