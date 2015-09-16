// Copyright 2004-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAController.h"

#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OAAboutPanelController.h"
#import "OAInternetConfig.h"
#import "OAWebPageViewer.h"

RCS_ID("$Id$")

@implementation OAController

#pragma mark -
#pragma mark OFController subclass

- (void)gotPostponedTerminateResult:(BOOL)isReadyToTerminate;
{
    if ([self status] == OFControllerPostponingTerminateStatus)
        [[NSApplication sharedApplication] replyToApplicationShouldTerminate:isReadyToTerminate];
    
    [super gotPostponedTerminateResult:isReadyToTerminate];
}

- (BOOL)shouldLogException:(NSException *)exception mask:(NSUInteger)aMask;
{
    if ([[exception name] isEqualToString:NSAccessibilityException] &&
        [[[exception userInfo] objectForKey:NSAccessibilityErrorCodeExceptionInfo] intValue] == kAXErrorAttributeUnsupported)
        return NO;
    
    return [super shouldLogException:exception mask:aMask];
}

#pragma mark -
#pragma mark API

- (OAAboutPanelController *)aboutPanelController;
{
    if (!aboutPanelController) {
	Class class = Nil;
	NSString *className = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OAAboutPanelControllerClass"];
	if (className) {
	    class = NSClassFromString(className);
	    if (!class)
		NSLog(@"Unable to find class '%@'", className);
	    if (!OBClassIsSubclassOfClass(class, [OAAboutPanelController class]))
		class = Nil;
	}
	if (!class)
	    class = [OAAboutPanelController class];
	
	aboutPanelController = [[class alloc] init];
    }
    return aboutPanelController;
}

- (NSString *)appName;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [infoDictionary objectForKey:@"CFBundleName"];
    appName = appName ? appName : @"CFBundleName not set!";
    return appName;
}

- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [infoDictionary objectForKey:@"CFBundleName"];
    NSString *appVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSString *buildVersion = [infoDictionary objectForKey:@"CFBundleVersion"];
    NSString *buildVersionSuffix = @"";
    NSString *buildRevision = [infoDictionary objectForKey:@"OABuildRevision"]; // For a possible svn revision if you aren't including that in CFBundleVersion
    
    if (![NSString isEmptyString:buildRevision])
        buildVersion = [NSString stringWithFormat:@"%@ r%@", buildVersion, buildRevision];

#if defined(MAC_APP_STORE) && MAC_APP_STORE
    buildVersionSuffix = @" Mac App Store";
#endif
    
    *feedbackAddress = [[NSUserDefaults standardUserDefaults] stringForKey:@"FeedbackAddress"];
    *subjectLine = [NSString stringWithFormat:@"%@ %@ (v%@%@) Feedback", appName, appVersion, buildVersion, buildVersionSuffix];
}

- (void)sendFeedbackEmailTo:(NSString *)feedbackAddress subject:(NSString *)subjectLine body:(NSString *)body;
{
    // Application developers should enter the feedback address in their main bundle's info dictionary.
    if (!feedbackAddress) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Unable to send feedback email.";
        alert.informativeText = @"No support email address configured in this application.";
        [alert addButtonWithTitle:@"Cancel"];
        [alert runModal];
    } else {
        OAInternetConfig *internetConfig = [[[OAInternetConfig alloc] init] autorelease];
        
        NSError *error = nil;
        if (![internetConfig launchMailTo:feedbackAddress carbonCopy:nil subject:subjectLine body:body error:&error])
            [[NSApplication sharedApplication] presentError:error];
    }
}

- (void)sendFeedbackEmailWithBody:(NSString *)body;
{
    NSString *feedbackAddress, *subjectLine;
    [self getFeedbackAddress:&feedbackAddress andSubject:&subjectLine];
    [self sendFeedbackEmailTo:feedbackAddress subject:subjectLine body:body];
}

- (BOOL)openURL:(NSURL *)url;
{
    return [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark -
#pragma mark NSApplicationDelegate protocol

- (void)applicationWillFinishLaunching:(NSNotification *)notification;
{
    [self didInitialize];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
    [self startedRunning];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
{
    OFControllerTerminateReply controllerResponse = [self requestTermination];
    switch (controllerResponse) {
        case OFControllerTerminateCancel:
            return NSTerminateCancel;
        case OFControllerTerminateLater:
            return NSTerminateLater;
        default:
            OBASSERT_NOT_REACHED("Unknown termination reply");
            // fall through
        case OFControllerTerminateNow:
            return NSTerminateNow;
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification;
{
    [self willTerminate];
}

#pragma mark - Actions

- (IBAction)showAboutPanel:(id)sender;
{
    [[self aboutPanelController] showAboutPanel:sender];
}

- (IBAction)hideAboutPanel:(id)sender;
{
    [[self aboutPanelController] hideAboutPanel:sender];
}

- (IBAction)sendFeedback:(id)sender;
{
    [self sendFeedbackEmailWithBody:nil];
}

- (NSString *)_messageOfTheDayPath;
{
    return [[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"];
}

- (IBAction)showMessageOfTheDay:(id)sender;
{
    NSString *path = [self _messageOfTheDayPath];
    if (path == nil)
        return;

    OAWebPageViewer *viewer = [OAWebPageViewer sharedViewerNamed:@"Release Notes"];

    // Allow @media {...} in the release notes to display differently when we are showing the content
    [viewer setMediaStyle:@"release-notes"];

    [viewer loadPath:path];
}

- (IBAction)openApplicationScriptsFolder:(id)sender;
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationScriptsDirectory, NSUserDomainMask, YES);
    if (paths.count == 0) {
        NSBeep();
        return;
    }

    NSString *scriptsFolder = paths[0];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:scriptsFolder withIntermediateDirectories:YES attributes:nil error:&error]) {
        [[NSApplication sharedApplication] presentError:error];
        return;
    }

    [[NSWorkspace sharedWorkspace] openFile:scriptsFolder];
}

- (void)checkMessageOfTheDay;
{
    NSString *path = [self _messageOfTheDayPath];
    if (path == nil)
        return;

    OFPreferenceWrapper *defaults = [OFPreferenceWrapper sharedPreferenceWrapper];
    if (![defaults boolForKey:@"OAMessageOfTheDayCheckOnLaunch"])
        return;

    NSData *motdData = [NSData dataWithContentsOfFile:path];
    NSData *seenSignature = [defaults objectForKey:@"OAMessageOfTheDaySignature"];
    if (motdData) {
        NSData *newSignature = NSMakeCollectable(OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)motdData));
	if (OFNOTEQUAL(newSignature, seenSignature)) {
	    [defaults setObject:newSignature forKey:@"OAMessageOfTheDaySignature"];

            // 10.5 9A410; the default policy guy has a zombie reference that gets hit sometimes.  Radar 5229858.  Setting our own policy doesn't help either.
            [defaults synchronize]; // in case WebKit is crashy, let's only crash once.
            
            // Don't show the message of the day on first launch, unless specified in the defaults (the idea being to not clutter up the first-time user experience).
            if (seenSignature || [defaults boolForKey:@"OAShowMessageOfTheDayOnFirstLaunch"]) {
                [self showMessageOfTheDay:nil];
            }
	}
        [newSignature release];
    }
}

@end
