// Copyright 2004-2021 Omni Development, Inc. All rights reserved.
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
    return [self handleChangePreferenceURL:url preferenceWrapper:[OFPreferenceWrapper sharedPreferenceWrapper] error:outError];
}

+ (BOOL)handleChangeGroupPreferenceURL:(NSURL *)url error:(NSError **)outError;
{
    OFPreferenceWrapper *preferenceWrapper = [OFPreferenceWrapper groupContainerIdentifierForContainingApplicationBundleIdentifierPreferenceWrapper];
    return [self handleChangePreferenceURL:url preferenceWrapper:preferenceWrapper error:outError];
}

+ (BOOL)handleChangePreferenceURL:(NSURL *)url preferenceWrapper:(OFPreferenceWrapper *)preferenceWrapper error:(NSError **)outError;
{
    OFMultiValueDictionary *parameters = [[url query] parametersFromQueryString];
    NSLog(@"Changing preferences for URL <%@>: parameters=%@; preferences database=%@", [url absoluteString], parameters, preferenceWrapper.suiteName);
    NSEnumerator *keyEnumerator = [parameters keyEnumerator];
    NSString *key = nil;

    while ((key = [keyEnumerator nextObject]) != nil) {
        NSString *stringValue = [parameters lastObjectForKey:key];
        if ([stringValue isNull])
            stringValue = nil;
        id oldValue = [preferenceWrapper valueForKey:key];
        id defaultValue = [[preferenceWrapper preferenceForKey:key] defaultObjectValue];
        id coercedValue = [OFPreference coerceStringValue:stringValue toTypeOfPropertyListValue:defaultValue error:outError];
        if (coercedValue == nil) {
            return NO;
        } else if ([coercedValue isNull]) {
            // Reset this setting
            [preferenceWrapper removeObjectForKey:key];
        } else {
            // Set this setting
            [preferenceWrapper setObject:coercedValue forKey:key];
        }
        id updatedValue = [preferenceWrapper valueForKey:key];
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
	    else if (!OBClassIsSubclassOfClass(class, [OAAboutPanelController class]))
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
    return [self applicationName];
}

- (NSString *)applicationName;
{
    static NSString *appName = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        appName = NSBundle.mainBundle.infoDictionary[(id)kCFBundleNameKey];
        
        NSString *buildSuffix = @"" OMNI_BUILD_FILE_SUFFIX;
        if ([appName hasSuffix:buildSuffix]) {
            appName = [appName stringByRemovingSuffix:buildSuffix];
        }
    });
    
    return appName;
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
    
#if MAC_APP_STORE_RETAIL_DEMO
    buildVersionSuffix = @" Retail Demo";
#elif defined(MAC_APP_STORE) && MAC_APP_STORE
    buildVersionSuffix = @" Mac App Store";
#endif
    
    NSString *fullVersionString = [NSString stringWithFormat:@"%@ %@ (v%@%@)", appName, appVersion, buildVersion, buildVersionSuffix];
    return fullVersionString;
}

- (NSString *)_deriveApplicationBundleURLScheme;
{
    // Grab the bundle identifier; if this is also a supported scheme it's preferred.
    NSString *applicationIdentifier = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleIdentifierKey];

    NSString *fallbackURLScheme = nil;
    NSArray *urlTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];
    for (NSDictionary *urlType in urlTypes) {
        NSArray *urlSchemes = [urlType objectForKey:@"CFBundleURLSchemes"];
        for (NSString *supportedScheme in urlSchemes) {
            if ([supportedScheme isEqualToString:applicationIdentifier]) {
                // Can bail immediately if the applicationIdentifier is supported.
                return supportedScheme;
            } else if (fallbackURLScheme == nil) {
                fallbackURLScheme = supportedScheme;
            }
        }
    }

    // Falling back to something that's hopefully handled though is less precise; assert and fall all the way back to the application name if necessary.
    OBASSERT(fallbackURLScheme != nil, "Expected linking application to include CFBundleURLTypes with a CFBundleURLSchemes entry");
    return fallbackURLScheme ?: [[self applicationName] lowercaseString];
}

- (NSString *)applicationBundleURLScheme;
{
    static NSString *applicationBundleURLScheme = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        applicationBundleURLScheme = [self _deriveApplicationBundleURLScheme];
    });

    return applicationBundleURLScheme;
}

- (nullable NSString *)majorVersionNumberString;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *versionString = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSArray *components = [versionString componentsSeparatedByString:@"."];
    return components.firstObject;
}

- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
{
    *feedbackAddress = [[NSUserDefaults standardUserDefaults] stringForKey:@"FeedbackAddress"];
    *subjectLine = [NSString stringWithFormat:@"%@ Feedback", [self fullReleaseString]];
}

- (void)sendFeedbackEmailTo:(NSString *)feedbackAddress subject:(NSString *)subjectLine body:(NSString *)body;
{
#if MAC_APP_STORE_RETAIL_DEMO
    [OAController runFeatureNotEnabledAlertForWindow:nil completion:nil];
#else
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
#endif
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

    OAWebPageViewer *viewer = [OAWebPageViewer sharedViewerNamed:@"Release Notes" options:OAWebPageViewerOptionsStandardReleaseNotesOptions];
    
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

    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:scriptsFolder]];
}

- (void)checkMessageOfTheDay;
{
#if MAC_APP_STORE_RETAIL_DEMO
    // Retail demos shouldn't show release notes when launching the app
    return;
#else
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
#endif
}

#pragma mark -

#if MAC_APP_STORE_RETAIL_DEMO

static int _retailDemoBlockAutoTerminationCounter = 0;

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender;
{
    return _retailDemoBlockAutoTerminationCounter == 0;
}

+ (void)retailDemoBlockAutoTermination;
{
    _retailDemoBlockAutoTerminationCounter++;
}

+ (void)retailDemoUnblockAutoTermination;
{
    if (_retailDemoBlockAutoTerminationCounter > 0) {
        _retailDemoBlockAutoTerminationCounter--;
    }
}

+ (void)runFeatureNotEnabledAlertForWindow:(nullable NSWindow *)window completion:(void (^ _Nullable)(void))completion;
{
    void (^completionBlock)(void) = [completion copy];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = OAFeatureNotEnabledForThisDemo();
    [alert addButtonWithTitle:OACancel()];
    if (window == nil) {
        [alert runModal];
        if (completionBlock != NULL) {
            completionBlock();
        }
    } else {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
            if (completionBlock != NULL) {
                completionBlock();
            }
        }];
    }
}

#endif

@end
