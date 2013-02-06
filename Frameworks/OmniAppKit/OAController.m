// Copyright 2004-2008, 2011-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAController.h"

#import "OAAboutPanelController.h"
#import "OAInternetConfig.h"

#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OAController

#pragma mark -
#pragma mark OFController subclass

- (void)gotPostponedTerminateResult:(BOOL)isReadyToTerminate;
{
    if ([self status] == OFControllerPostponingTerminateStatus)
        [NSApp replyToApplicationShouldTerminate:isReadyToTerminate];
    
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

#ifdef MAC_APP_STORE
    buildVersionSuffix = @" Mac App Store";
#endif
    
    *feedbackAddress = [[NSUserDefaults standardUserDefaults] stringForKey:@"FeedbackAddress"];
    *subjectLine = [NSString stringWithFormat:@"%@ %@ (v%@%@) Feedback", appName, appVersion, buildVersion, buildVersionSuffix];
}

- (void)sendFeedbackEmailTo:(NSString *)feedbackAddress subject:(NSString *)subjectLine body:(NSString *)body;
{
    // Application developers should enter the feedback address in their main bundle's info dictionary.
    if (!feedbackAddress) {
        NSRunAlertPanel(@"Unable to send feedback email.", @"No support email address configured in this application.", @"Cancel", nil, nil);
    } else {
        OAInternetConfig *internetConfig = [[[OAInternetConfig alloc] init] autorelease];
        
        NSError *error = nil;
        if (![internetConfig launchMailTo:feedbackAddress carbonCopy:nil subject:subjectLine body:body error:&error])
            [NSApp presentError:error];
    }
}

- (void)sendFeedbackEmailWithBody:(NSString *)body;
{
    NSString *feedbackAddress, *subjectLine;
    [self getFeedbackAddress:&feedbackAddress andSubject:&subjectLine];
    [self sendFeedbackEmailTo:feedbackAddress subject:subjectLine body:body];
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

#pragma mark -
#pragma mark Actions

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

@end
