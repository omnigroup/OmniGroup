// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUController.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniFoundation/OFMultipleOptionErrorRecovery.h>

#import <OmniSoftwareUpdate/OSUChecker.h>
#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSUDownloadController.h>
#import "OSUAvailableUpdateController.h"
#import "OSUErrors.h"
#import "OSUItem.h"
#import <OmniSoftwareUpdate/OSUCheckOperation.h>
#import "OSUSendFeedbackErrorRecovery.h"
#import "OSUPrivacyAlertWindowController.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG_bungi)
#define USE_NOTIFICATION_CENTER 1
#else
#define USE_NOTIFICATION_CENTER 0
#endif


NSString * const OSUReleaseDisplayVersionKey = @"displayVersion";
NSString * const OSUReleaseDownloadPageKey = @"downloadPage";
NSString * const OSUReleaseEarliestCompatibleLicenseKey = @"earliestCompatibleLicense";
NSString * const OSUReleaseRequiredOSVersionKey = @"requiredOSVersion";
NSString * const OSUReleaseVersionKey = @"version";
NSString * const OSUReleaseSpecialNotesKey = @"specialNotes";
NSString * const OSUReleaseMajorSummaryKey = @"majorReleaseSummary";
NSString * const OSUReleaseMinorSummaryKey = @"minorReleaseSummary";
NSString * const OSUReleaseApplicationSummaryKey = @"applicationSummary";  //  Do we really want this, or just the majorReleaseSummary?

// If we start showing a version number in each notification, we can add a '.' here and either a unique random string or the version number. Then, on launch, we'd want to remove any notifications for versions that are superseded by this running version.
#define OSUUserNotificationIdentifierPrefix @"com.omnigroup.OmniSoftwareUpdate.UserNotification."

@interface OSUController ()
#if USE_NOTIFICATION_CENTER
<OFNotificationOwner>
#endif
@end

@implementation OSUController
{
    OSUDownloadController *_currentDownloadController;
    OSUAvailableUpdateController *_pendingAvailableUpdateController;

#if USE_NOTIFICATION_CENTER
    // Info gathered from the most recent check if we opted to display a user notification instead
    void (^_displayAvailbleVersionsFromPreviouslyFinishedOperation)(void);
#endif
}

// API

+ (OSUController *)sharedController;
{
    static OSUController *sharedController = nil;
    if (sharedController == nil)
        sharedController = [[self alloc] init];
    
    return sharedController;
}

+ (void)checkSynchronouslyWithUIAttachedToWindow:(NSWindow *)aWindow;
{
    [[OSUChecker sharedUpdateChecker] checkSynchronously];
}

- init;
{
    if (!(self = [super init]))
        return nil;
    
#if USE_NOTIFICATION_CENTER
    [[OAController sharedController] addNotificationOwner:self];
#endif
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];

    return self;
}

- (BOOL)beginDownloadAndInstallFromPackageAtURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;
{
    return [OSUDownloadController beginWithPackageURL:packageURL item:item error:outError];
}

#pragma mark -
#pragma mark OSUCheckerTarget

- (void)checkerDidStart:(OSUChecker *)checker;
{
    {
        NSString *packageURLString = [[NSUserDefaults standardUserDefaults] stringForKey:@"OSUDownloadAndInstallFromURL"];
        if (![NSString isEmptyString:packageURLString]) {
            NSURL *packageURL = [NSURL URLWithString:packageURLString];
            __autoreleasing NSError *error = nil;
            if (![[OSUController sharedController] beginDownloadAndInstallFromPackageAtURL:packageURL item:nil error:&error])
                [[NSApplication sharedApplication] presentError:error];
        }
    }
    
#ifdef DEBUG
    {
        // Warn developers if they are on a funky track ('sneakpeek' and 'sneakypeak' being the most common typos).
        NSString *runningTrack = [checker applicationTrack];
        
        if (![NSString isEmptyString:runningTrack]) {
            NSDictionary *info = [OSUItem informationForTrack:runningTrack];
            
            if (!info || ![info boolForKey:@"isKnown"]) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = OBUnlocalized(@"Unknown software update track");
                alert.informativeText = [NSString stringWithFormat:@"Specified the track \"%@\" but that isn't a track we know about.  Typo?", runningTrack];
                [alert addButtonWithTitle:OAOK()];
                [alert runModal];
            }
        }
    }
#endif
}

- (BOOL)checkerShouldStartCheck:(OSUChecker *)checker;
{
    OSUDownloadController *currentDownload = [OSUDownloadController currentDownloadController];
    if (currentDownload) {
        [currentDownload showWindow:nil];
        NSBeep();
        return NO;
    }
    
    return YES;
}

- (void)checker:(OSUChecker *)checker didStartCheck:(OSUCheckOperation *)op;
{
    /* This method is only called for explicit user requests, not for background operations. So go ahead and pop up the window. */
    OSUAvailableUpdateController *availableUpdateController = [OSUAvailableUpdateController availableUpdateController:YES];
    [availableUpdateController setValue:nil forKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    [availableUpdateController showWindow:nil];
}

- (OSUPrivacyNoticeResult)checker:(OSUChecker *)checker runPrivacyNoticePanelHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;
{
    OSUPrivacyAlertWindowController *alert = [[OSUPrivacyAlertWindowController alloc] init];
    return [alert runHavingSeenPreviousVersion:hasSeenPreviousVersion];
    
}

- (void)checker:(OSUChecker *)checker check:(OSUCheckOperation *)op failedWithError:(NSError *)error;
{
    OSUAvailableUpdateController *availableUpdateController = [OSUAvailableUpdateController availableUpdateController:NO];
    if (availableUpdateController) {
        // If there is a controller, update its status.
        [availableUpdateController setValue:[NSNumber numberWithBool:op.initiatedByUser]
                                     forKey:OSUAvailableUpdateControllerLastCheckUserInitiatedBinding];
        [availableUpdateController setValue:[NSNumber numberWithBool:YES]
                                     forKey:OSUAvailableUpdateControllerLastCheckFailedBinding];
    }
    
    // Disabling the errors from the asynchronous check until the UI is improved.  <bug://bugs/40635> (Warn users if they haven't successfully connected to software update in N days)
    // Also, don't show the error if the user initiated the check and subsequently closed the Check for Updates window
    BOOL shouldReport = op.initiatedByUser && availableUpdateController.window.visible;
    
    if (shouldReport) {
        // NOTE: OSUSendFeedbackErrorRecovery will recuse itself for errors that aren't things we can help with.
        error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:nil options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
        
        [[NSApplication sharedApplication] presentError:error];
    } else {
#ifdef DEBUG	
        NSLog(@"Error interpreting response from software update server: %@", error);
#endif	    
    }
}

#if USE_NOTIFICATION_CENTER
static NSString * const OSUUserNotificationInstallActionIdentifier = @"install";
static NSString * const OSUUserNotificationInstallURLInfoKey = @"url";
#endif

- (void)checker:(OSUChecker *)checker newVersionsAvailable:(NSArray *)versionInfos fromCheck:(OSUCheckOperation *)op;
{
#if defined(DEBUG)
    if (OSUItemDebug) {
        for (OSUItem *item in versionInfos) {
            NSLog(@"  %@ - avail=%d superseded=%d ignored=%d old=%d",
                  [item shortDescription],
                  item.available, item.superseded, item.isIgnored, item.isOldStable);
        }
    }
#endif
    
    __block BOOL quiet = YES; // __block so that the block below gets the written value below
    
    void (^displayAvailableUpdates)(void) = ^{
        // In the common case, there are no new versions available, and we don't want to create the OSUAvailableUpdateController (and all its GUI goo) for nothing.
        OSUAvailableUpdateController *availableUpdateController = [OSUAvailableUpdateController availableUpdateController:!quiet];
        if (availableUpdateController) {
            // If there is a controller, update it even if quiet=YES
            [availableUpdateController setValue:versionInfos forKey:OSUAvailableUpdateControllerAvailableItemsBinding];
            [availableUpdateController setValue:@(op.initiatedByUser) forKey:OSUAvailableUpdateControllerLastCheckUserInitiatedBinding];
            [availableUpdateController setValue:@NO forKey:OSUAvailableUpdateControllerLastCheckFailedBinding];
        }
        
        if (!quiet) {
            [self _showAvailableUpdateWhenActive:availableUpdateController];
        }
    };
    
#if USE_NOTIFICATION_CENTER
    [_displayAvailbleVersionsFromPreviouslyFinishedOperation release];
    _displayAvailbleVersionsFromPreviouslyFinishedOperation = nil;
#endif
    
    // If this is an asynchronous run (not prompted by the user), and there are no sufficiently interesting items that would be displayed with the default predicate, don't call the target/action.
    if (!op.initiatedByUser) {
        NSArray *filteredItems = [versionInfos filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]];
        if ([filteredItems count] > 0) {
            quiet = NO;
            
#if USE_NOTIFICATION_CENTER
            _displayAvailbleVersionsFromPreviouslyFinishedOperation = [displayAvailableUpdates copy];

            
            NSUserNotification *notification = [[[NSUserNotification alloc] init] autorelease];
            
            notification.identifier = [NSString stringWithFormat:OSUUserNotificationIdentifierPrefix @"%@", [OFXMLCreateID() autorelease]];

            notification.title = [[OAController sharedController] appName];
            notification.subtitle = NSLocalizedStringFromTableInBundle(@"Update available", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Local notification subtitle text.");
            
            notification.informativeText = NSLocalizedStringFromTableInBundle(@"Click here for details...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Local notification informative text.");
            
            // TODO: This only makes sense if there is a single update?
            notification.actionButtonTitle = NSLocalizedStringFromTableInBundle(@"Details", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Local notification action button title for installing the available update.");
            notification.hasActionButton = YES;
            
            notification.otherButtonTitle = @"qqq";
            
            // If there is exactly one available item, it is on the same track, and isn't a major update, then we can offer to install it.
            // "Other" actions appear only as a long-press on alert-style notifications, and not at all on normal notifications.
            // The 'other button' title replaces "Close" and results in no activation callback
            if ([filteredItems count] == 1) {
                OSUItem *item = [filteredItems lastObject];
                NSURL *downloadURL = item.downloadURL;
                
                if (downloadURL &&
                    [item.track isEqual:checker.applicationTrack] &&
                    [item.marketingVersion componentAtIndex:0] == [checker.applicationMarketingVersion componentAtIndex:0]) {
                    notification.additionalActions = @[[NSUserNotificationAction actionWithIdentifier:OSUUserNotificationInstallActionIdentifier title:NSLocalizedStringFromTableInBundle(@"Install", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Local notification action button title for installing the available update.")]];
                    notification.userInfo = @{OSUUserNotificationInstallURLInfoKey:[downloadURL absoluteString]};
                }
            }
            
            [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:notification];
            return;
#endif
        }
    }
    
    displayAvailableUpdates();
}

#if USE_NOTIFICATION_CENTER

#pragma mark - OFNotificationOwner

- (BOOL)ownsNotification:(NSUserNotification *)notification;
{
    return [notification.identifier hasPrefix:OSUUserNotificationIdentifierPrefix];
}

#pragma mark - NSUserNotificationCenterDelegate (subprotocol of OFNotificationOwner)

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification;
{
    OBPRECONDITION([self ownsNotification:notification]);
    
    NSLog(@"did deliver, presented %d", notification.presented);
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification;
{
    OBPRECONDITION([self ownsNotification:notification]);
    
    // TODO: Return NO if OSUAvailableUpdateController is already visible.
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification;
{
    OBPRECONDITION([self ownsNotification:notification]);
    
    NSLog(@"did activate %@", notification);
    NSLog(@"activationType %ld", notification.activationType);
    NSLog(@"userInfo %@", notification.userInfo);
    NSLog(@"additionalActivationAction %@", notification.additionalActivationAction);
    
    if (_displayAvailbleVersionsFromPreviouslyFinishedOperation) {
        void (^block)(void) = [_displayAvailbleVersionsFromPreviouslyFinishedOperation autorelease];
        _displayAvailbleVersionsFromPreviouslyFinishedOperation = nil;
        
        block();
    } else {
        // Maybe we've been quit and restarted since the notification was registered? Do a "user initiated" check
        [[OSUChecker sharedUpdateChecker] checkSynchronously];
    }
}

#endif

- (void)_showAvailableUpdateWhenActive:(OSUAvailableUpdateController *)availableUpdateController;
{
    _pendingAvailableUpdateController = availableUpdateController;
    [self _showPendingAvailableUpdateIfActive];
}

- (void)_showPendingAvailableUpdateIfActive;
{
    if (_pendingAvailableUpdateController == nil || ![[NSApplication sharedApplication] isActive])
        return;

    [_pendingAvailableUpdateController showWindow:nil];
    _pendingAvailableUpdateController = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification;
{
    [self _showPendingAvailableUpdateIfActive];
}

@end
