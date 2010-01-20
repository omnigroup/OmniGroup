// Copyright 2003-2008, 2010 Omni Development, Inc.  All rights reserved.
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

#import "OSUChecker.h"
#import "OSUPreferences.h"
#import "OSUDownloadController.h"
#import "OSUAvailableUpdateController.h"
#import "OSUErrors.h"
#import "OSUItem.h"
#import "OSUCheckOperation.h"

RCS_ID("$Id$");


NSString *OSUReleaseDisplayVersionKey = @"displayVersion";
NSString *OSUReleaseDownloadPageKey = @"downloadPage";
NSString *OSUReleaseEarliestCompatibleLicenseKey = @"earliestCompatibleLicense";
NSString *OSUReleaseRequiredOSVersionKey = @"requiredOSVersion";
NSString *OSUReleaseVersionKey = @"version";
NSString *OSUReleaseSpecialNotesKey = @"specialNotes";
NSString *OSUReleaseMajorSummaryKey = @"majorReleaseSummary";
NSString *OSUReleaseMinorSummaryKey = @"minorReleaseSummary";
NSString *OSUReleaseApplicationSummaryKey = @"applicationSummary";  //  Do we really want this, or just the majorReleaseSummary?


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

+ (void)newVersionsAvailable:(NSArray *)versionInfos fromCheck:(OSUCheckOperation *)op;
{
    /* In the common case, there are no new versions available, and we don't want to create the ... for nothing. */
    BOOL quiet = YES;
    
    // If this is an asynchronous run (not prompted by the user), and there are no items that would be displayed with the default predicate, don't call the target/action.
    if (!op.initiatedByUser) {
        NSArray *filteredItems = [versionInfos filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededOrIgnoredPredicate]];
        if ([filteredItems count] > 0)
            quiet = NO;
    }
    
    OSUAvailableUpdateController *availableUpdateController = [OSUAvailableUpdateController availableUpdateController:!quiet];
    if (availableUpdateController) {
        // If there is a controller, update it even if quiet=YES
        [availableUpdateController setValue:versionInfos forKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    }
    
    if (!quiet)
        [availableUpdateController showWindow:nil];
}

+ (void)startingCheckForUpdates;
{
    /* This method is only called for explicit user requests, not for background operations. So go ahead and pop up the window. */
    OSUAvailableUpdateController *availableUpdateController = [OSUAvailableUpdateController availableUpdateController:YES];
    [availableUpdateController setValue:nil forKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    [availableUpdateController showWindow:nil];
}

- (OSUPrivacyNoticeResult)runPrivacyNoticePanelHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;
{
    if (![self _loadNib:hasSeenPreviousVersion])
        return OSUPrivacyNoticeResultShowPreferences;

    // Prepopulate the checkbox with your current setting.
    [enableHardwareCollectionButton setState:[[OSUPreferences includeHardwareDetails] boolValue]];
    
    [privacyNoticePanel center];
    OSUPrivacyNoticeResult rc = (OSUPrivacyNoticeResult)[NSApp runModalForWindow:privacyNoticePanel];
    [privacyNoticePanel orderOut:nil];

    // Store what they said either way
    [[OSUPreferences includeHardwareDetails] setBoolValue:[enableHardwareCollectionButton state]];
    [[NSUserDefaults standardUserDefaults] synchronize]; // Make sure we don't lose this one, espeically if they turn it off!
    
    return rc;
}

- (BOOL)beginDownloadAndInstallFromPackageAtURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;
{
    // As a standard NSWindowController pattern, this will self-destruct when the window closes.  clang scan-build doesn't understand that, though.
    // Under there is a better fix for this, doing this still stuff to make scan-build oblivious.
    // There is an existing clang scan-build bug for this at <http://llvm.org/bugs/show_bug.cgi?id=2633>
    OSUDownloadController *download = [objc_msgSend([OSUDownloadController class], @selector(alloc)) initWithPackageURL:packageURL item:item error:outError];
    return (download != nil);
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

    NS_DURING {
        [[OSUController bundle] loadNibNamed:@"OSUController" owner:self];
    } NS_HANDLER {
#ifdef DEBUG    
        NSLog(@"Unable to load nib: %@", localException);
#endif	
        return NO;
    } NS_ENDHANDLER;

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
