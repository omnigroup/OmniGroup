// Copyright 2003-2008, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUController.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniFoundation/OFMultipleOptionErrorRecovery.h>

#import "OSUChecker.h"
#import "OSUPreferences.h"
#import "OSUDownloadController.h"
#import "OSUAvailableUpdateController.h"
#import "OSUErrors.h"
#import "OSUItem.h"
#import "OSUCheckOperation.h"
#import "OSUSendFeedbackErrorRecovery.h"

RCS_ID("$Id$");


NSString * const OSUReleaseDisplayVersionKey = @"displayVersion";
NSString * const OSUReleaseDownloadPageKey = @"downloadPage";
NSString * const OSUReleaseEarliestCompatibleLicenseKey = @"earliestCompatibleLicense";
NSString * const OSUReleaseRequiredOSVersionKey = @"requiredOSVersion";
NSString * const OSUReleaseVersionKey = @"version";
NSString * const OSUReleaseSpecialNotesKey = @"specialNotes";
NSString * const OSUReleaseMajorSummaryKey = @"majorReleaseSummary";
NSString * const OSUReleaseMinorSummaryKey = @"minorReleaseSummary";
NSString * const OSUReleaseApplicationSummaryKey = @"applicationSummary";  //  Do we really want this, or just the majorReleaseSummary?


@interface OSUController (Private)
- (BOOL)_loadNib:(BOOL)hasSeenPreviousVersion;
@end

@implementation OSUController

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
            NSError *error = nil;
            if (![[OSUController sharedController] beginDownloadAndInstallFromPackageAtURL:packageURL item:nil error:&error])
                [NSApp presentError:error];
        }
    }
    
#ifdef DEBUG
    {
        // Warn developers if they are on a funky track ('sneakpeek' and 'sneakypeak' being the most common typos).
        NSString *runningTrack = [checker applicationTrack];
        
        if (![NSString isEmptyString:runningTrack]) {
            NSDictionary *info = [OSUItem informationForTrack:runningTrack];
            
            if (!info || ![info boolForKey:@"isKnown"]) {
                NSRunAlertPanel(@"Unknown software update track", @"Specified the track '%@' but that isn't a track we know about.  Typo?", @"OK", nil, nil, runningTrack);
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
    if (![self _loadNib:hasSeenPreviousVersion])
        return OSUPrivacyNoticeResultShowPreferences;
    
    // Prepopulate the checkbox with your current setting.
    [enableHardwareCollectionButton setState:[[OSUPreferences includeHardwareDetails] boolValue]];
    
    OSUPrivacyNoticeResult rc = (OSUPrivacyNoticeResult)[NSApp runModalForWindow:privacyNoticePanel];
    [privacyNoticePanel orderOut:nil];
    
    // Store what they said either way
    [[OSUPreferences includeHardwareDetails] setBoolValue:[enableHardwareCollectionButton state]];
    [[NSUserDefaults standardUserDefaults] synchronize]; // Make sure we don't lose this one, espeically if they turn it off!
    
    if (rc != OSUPrivacyNoticeResultOK) {
        OBASSERT(rc == OSUPrivacyNoticeResultShowPreferences);

        OAPreferenceController *prefsController = [OAPreferenceController sharedPreferenceController];
        [prefsController showPreferencesPanel:nil];
        [prefsController setCurrentClientByClassName:NSStringFromClass([OSUPreferences class])];
    }
    
    return rc;
}

- (void)checker:(OSUChecker *)checker check:(OSUCheckOperation *)op failedWithError:(NSError *)error;
{
    // If we get an error that is due to a server-side misconfiguration, go ahead and report it so that we'll know to fix it and users won't get stranded.  But if we simply can't connect to the server, it's presumably a transient error and shouldn't be reported unless the user is specifically checking for updates.
#if 0
    BOOL isNetworkError = NO;
    if ([[error domain] isEqualToString:OSUToolErrorDomain]) {
        int code = [error code];
        if (code == OSUToolRemoteNetworkFailure && code == OSUToolLocalNetworkFailure)
            isNetworkError = YES;
    }
#endif
    
    OSUAvailableUpdateController *availableUpdateController = [OSUAvailableUpdateController availableUpdateController:NO];
    if (availableUpdateController) {
        // If there is a controller, update its status.
        [availableUpdateController setValue:[NSNumber numberWithBool:op.initiatedByUser]
                                     forKey:OSUAvailableUpdateControllerLastCheckUserInitiatedBinding];
        [availableUpdateController setValue:[NSNumber numberWithBool:YES]
                                     forKey:OSUAvailableUpdateControllerLastCheckFailedBinding];
    }
    
    // Disabling the errors from the asynchronous check until the UI is improved.  <bug://bugs/40635> (Warn users if they haven't successfully connected to software update in N days)
    BOOL shouldReport = op.initiatedByUser /*|| !isNetworkError*/;
    
    if (shouldReport) {
        error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:nil options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
        [NSApp presentError:error];
    } else {
#ifdef DEBUG	
        NSLog(@"Error interpreting response from software update server: %@", error);
#endif	    
    }
}

- (void)checker:(OSUChecker *)checker newVersionsAvailable:(NSArray *)versionInfos fromCheck:(OSUCheckOperation *)op;
{
    /* In the common case, there are no new versions available, and we don't want to create the OSUAvailableUpdateController (and all its GUI goo) for nothing. */
    BOOL quiet = YES;
    
    // If this is an asynchronous run (not prompted by the user), and there are no sufficiently interesting items that would be displayed with the default predicate, don't call the target/action.
    if (!op.initiatedByUser) {
        NSArray *filteredItems = [versionInfos filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]];
        if ([filteredItems count] > 0)
            quiet = NO;
    }
    
#if defined(DEBUG)
    if (OSUItemDebug) {
        OFForEachObject([versionInfos objectEnumerator], OSUItem *, item) {
            NSLog(@"  %@ - avail=%d superseded=%d ignored=%d old=%d",
                  [item shortDescription],
                  item.available, item.superseded, item.isIgnored, item.isOldStable);
        };
    }
#endif
    
    OSUAvailableUpdateController *availableUpdateController = [OSUAvailableUpdateController availableUpdateController:!quiet];
    if (availableUpdateController) {
        // If there is a controller, update it even if quiet=YES
        [availableUpdateController setValue:versionInfos
                                     forKey:OSUAvailableUpdateControllerAvailableItemsBinding];
        [availableUpdateController setValue:[NSNumber numberWithBool:op.initiatedByUser]
                                     forKey:OSUAvailableUpdateControllerLastCheckUserInitiatedBinding];
        [availableUpdateController setValue:[NSNumber numberWithBool:NO]
                                     forKey:OSUAvailableUpdateControllerLastCheckFailedBinding];
    }
    
    if (!quiet)
        [availableUpdateController showWindow:nil];
}

#pragma mark -
#pragma mark Actions

- (IBAction)privacyNoticePanelOK:(id)sender;
{
    [NSApp stopModalWithCode:OSUPrivacyNoticeResultOK];
}

- (IBAction)privacyNoticePanelShowPreferences:(id)sender;
{
    [NSApp stopModalWithCode:OSUPrivacyNoticeResultShowPreferences];
}

@end

@implementation OSUController (Private)

- (BOOL)_loadNib:(BOOL)hasSeenPreviousVersion;
{
    if (privacyNoticePanel)
        return YES;

    @try {
        [[OSUController bundle] loadNibNamed:@"OSUController" owner:self];
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
#ifdef DEBUG    
        NSLog(@"Unable to load nib: %@", exc);
#endif	
        return NO;
    }

    // If we *had* seen the panel before, replace the title string
    NSString *titleFormat = [privacyNoticeTitleTextField stringValue];
    if (hasSeenPreviousVersion)
	titleFormat = NSLocalizedStringFromTableInBundle(@"This version of %@ sends additional information using your Internet connection (when active) to check for new and updated versions of itself.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "text of dialog box informing user of change in software update query");
    
    
    NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
    [privacyNoticeTitleTextField setStringValue:[NSString stringWithFormat:titleFormat, bundleName]];
    [privacyNoticeMessageTextField setStringValue:[NSString stringWithFormat:[privacyNoticeMessageTextField stringValue], bundleName]];
    [privacyNoticeAppIconImageView setImage:[NSApp applicationIconImage]];
    
    return YES;
}

@end
