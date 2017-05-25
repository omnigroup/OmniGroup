// Copyright 2004-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAController.h>

#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/OAAboutPanelController.h>
#import <OmniAppKit/OAInternetConfig.h>
#import <OmniAppKit/OAWebPageViewer.h>
#import <OmniAppKit/OAStrings.h>

RCS_ID("$Id$")

@implementation OAController
{
@private
    OAAboutPanelController *aboutPanelController;
}

#pragma mark -
#pragma mark OFController subclass

- (void)gotPostponedTerminateResult:(BOOL)isReadyToTerminate;
{
    if ([self status] == OFControllerStatusPostponingTerminate)
        [[NSApplication sharedApplication] replyToApplicationShouldTerminate:isReadyToTerminate];
    
    [super gotPostponedTerminateResult:isReadyToTerminate];
}

#pragma mark -
#pragma mark API

+ (BOOL)handleChangePreferenceURL:(NSURL *)url error:(NSError **)outError;
{
    OFMultiValueDictionary *parameters = [[url query] parametersFromQueryString];
    NSLog(@"Changing preferences for URL <%@>: parameters=%@", [url absoluteString], parameters);
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    NSEnumerator *keyEnumerator = [parameters keyEnumerator];
    NSString *key = nil;
    while ((key = [keyEnumerator nextObject]) != nil) {
        NSString *stringValue = [parameters lastObjectForKey:key];
        if ([stringValue isNull])
            stringValue = nil;
        id oldValue = [preferences valueForKey:key];
        id defaultValue = [[preferences preferenceForKey:key] defaultObjectValue];
        id coercedValue = [OFPreference coerceStringValue:stringValue toTypeOfPropertyListValue:defaultValue];
        if (coercedValue == nil) {
            NSLog(@"Unable to update %@: failed to convert '%@' to the same type as '%@' (%@)", key, stringValue, defaultValue, [defaultValue class]);
            return NO;
        } else if ([coercedValue isNull]) {
            // Reset this setting
            [preferences removeObjectForKey:key];
        } else {
            // Set this setting
            [preferences setObject:coercedValue forKey:key];
        }
        id updatedValue = [preferences valueForKey:key];
        NSLog(@"... %@: %@ (%@) -> %@ (%@)", key, oldValue, [oldValue class], updatedValue, [updatedValue class]);
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedStringFromTableInBundle(@"Preference changed", @"OmniAppKit", OMNI_BUNDLE, @"alert title");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Changed the '%@' preference from '%@' to '%@'", @"OmniAppKit", OMNI_BUNDLE, @"alert message"), key, oldValue, updatedValue];
        [alert addButtonWithTitle:OAOK()];
        (void)[alert runModal];
    }
    return YES;
}

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
    // make sure that any name returned here doesn't include the path extension.
    // <bug:///129671> (Bug: Suppress '.app' from the announcement string in titlebar [news])
    return [NSBundle mainBundle].displayName.stringByDeletingPathExtension;
}

- (NSString *)fullReleaseString;
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
    
    NSString *fullVersionString = [NSString stringWithFormat:@"%@ %@ (v%@%@)", appName, appVersion, buildVersion, buildVersionSuffix];
    return fullVersionString;
}

- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
{
    *feedbackAddress = [[NSUserDefaults standardUserDefaults] stringForKey:@"FeedbackAddress"];
    *subjectLine = [NSString stringWithFormat:@"%@ Feedback", [self fullReleaseString]];
}

- (void)sendFeedbackEmailTo:(NSString *)feedbackAddress subject:(NSString *)subjectLine body:(NSString *)body;
{
    // Application developers should enter the feedback address in their main bundle's info dictionary.
    if (!feedbackAddress) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedStringFromTableInBundle(@"Unable to send feedback email.", @"OmniAppKit", OMNI_BUNDLE, @"Alert title when sending feedback email fails");
        alert.informativeText = NSLocalizedStringFromTableInBundle(@"No support email address configured in this application.", @"OmniAppKit", OMNI_BUNDLE, @"Alert message when sending feedback email fails");
        [alert addButtonWithTitle:OACancel()];
        [alert runModal];
    } else {
        OAInternetConfig *internetConfig = [[OAInternetConfig alloc] init];
        
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

- (NSOperationQueue *)backgroundPromptQueue;
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *promptQueue;
    dispatch_once(&onceToken, ^{
        promptQueue = [[NSOperationQueue alloc] init];
        promptQueue.maxConcurrentOperationCount = 1;
        promptQueue.name = @"Background Prompt Serialization Queue";
    });
    return promptQueue;
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
    
    // don't go fullscreen
    NSRect frame = [[viewer window] frame];
    frame.size.width = 800;
    [[viewer window] setFrame:frame display:NO];
    [[viewer window] setMinSize:NSMakeSize(800, 400)];
    [[viewer window] setMaxSize:NSMakeSize(800, FLT_MAX)];

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
        NSData *newSignature = CFBridgingRelease(OFDataCreateSHA1Digest(kCFAllocatorDefault, (__bridge CFDataRef)motdData));
	if (OFNOTEQUAL(newSignature, seenSignature)) {
	    [defaults setObject:newSignature forKey:@"OAMessageOfTheDaySignature"];

            // 10.5 9A410; the default policy guy has a zombie reference that gets hit sometimes.  Radar 5229858.  Setting our own policy doesn't help either.
            [defaults synchronize]; // in case WebKit is crashy, let's only crash once.
            
            // Don't show the message of the day on first launch, unless specified in the defaults (the idea being to not clutter up the first-time user experience).
            if (seenSignature || [defaults boolForKey:@"OAShowMessageOfTheDayOnFirstLaunch"]) {
                [self showMessageOfTheDay:nil];
            }
	}
    }
}

@end
