// Copyright 2006-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUTAController.h"

#import <OmniSoftwareUpdate/OSUChecker.h>
#import "OSUTAChecker.h"
#import "OSUItem.h"
#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/NSApplication-OSUSupport.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/OmniAppKit.h>
#import <OmniSoftwareUpdate/OSUDownloadController.h>

RCS_ID("$Id$");

@class OSUInstaller;

// Preferences keys
static NSString * const OSUInstallFromURLKey = @"installFrom";
static NSString * const OSULicenseTypeKey = @"targetLicenseType";

@interface OSUTAController (/*Private*/)
- (void)_noteVisibleTracks:(NSNotification *)notification;
@end

@implementation OSUTAController

// Bring up a sheet to prompt for a URL, then install from it
- (IBAction)forceInstall:sender;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUInstallFromURLKey];
    if (![NSString isEmptyString:value])
        [urlPromptField setStringValue:value];
    
    [[NSApplication sharedApplication] beginSheet:[urlPromptField window] modalForWindow:window modalDelegate:self didEndSelector:@selector(urlSheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

// Target of the buttons on the URL prompt sheet
- (IBAction)acceptURL:sender;
{
    NSString *value = [urlPromptField stringValue];
    if ([NSString isEmptyString:value])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:OSUInstallFromURLKey];
    else
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:OSUInstallFromURLKey];

    if ([sender tag] == 0 && ![NSString isEmptyString:[urlPromptField stringValue]])
        [[NSApplication sharedApplication] endSheet:[urlPromptField window] returnCode:NSRunStoppedResponse];
    else
        [[NSApplication sharedApplication] endSheet:[urlPromptField window] returnCode:NSRunAbortedResponse];
}

- (IBAction)changeLicenseState:sender;
{
//    [[OSUChecker sharedUpdateChecker] setLicenseType:[[licenseStatePopUp selectedItem] representedObject]];
}

- (IBAction)fakeTimedCheck:sender;
{
    [(OSUTAChecker *)[OSUChecker sharedUpdateChecker] fakeTimedCheck:sender];
}

- (void)awakeFromNib
{
    [licenseStatePopUp removeAllItems];
    NSString *states[] = {
        OSULicenseTypeUnset,
        OSULicenseTypeNone,
        OSULicenseTypeRegistered,
        OSULicenseTypeRetail,
        OSULicenseTypeBundle,
        OSULicenseTypeTrial,
        OSULicenseTypeExpiring,
        nil
    };
    
    for(int i = 0; states[i]; i++) {
        [licenseStatePopUp addItemWithTitle:states[i]];
        if (i != 0) {
            // Leave 'unset' == nil
            [[licenseStatePopUp lastItem] setRepresentedObject:states[i]];
        }
    }
    
    [licenseStatePopUp selectItemWithTitle:OSULicenseTypeUnset];
    [licenseStatePopUp bind:NSSelectedObjectBinding toObject:[NSUserDefaults standardUserDefaults] withKeyPath:OSULicenseTypeKey options:nil];
    [[OSUChecker sharedUpdateChecker] bind:OSUCheckerLicenseTypeBinding toObject:[NSUserDefaults standardUserDefaults] withKeyPath:OSULicenseTypeKey options:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_noteVisibleTracks:) name:OSUTrackVisibilityChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_noteVisibleTracks:) name:NSUserDefaultsDidChangeNotification object:nil];

    [self _noteVisibleTracks:nil];
}

#pragma mark --
#pragma mark NSApplication delegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;
{
    [[OFController sharedController] didInitialize];
    [[OFController sharedController] startedRunning];
    
    OSUTAChecker *checker = (OSUTAChecker *)[OSUChecker sharedUpdateChecker];
    OBASSERT([checker isKindOfClass:[OSUTAChecker class]]);
    
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    
    [[bundleIdentifierField cell] setPlaceholderString:[[NSBundle mainBundle] bundleIdentifier]];
    [[marketingVersionField cell] setPlaceholderString:[infoDict objectForKey:@"CFBundleShortVersionString"]];
    [[buildVersionField cell] setPlaceholderString:[infoDict objectForKey:@"CFBundleVersion"]];
}

- (void)urlSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    [sheet orderOut:nil];
    
    if (returnCode == NSRunStoppedResponse) {
        NSURL *u = [NSURL URLWithString:[urlPromptField stringValue]];
        if (!u) {
            NSBeep();
            return;
        }
        
        NSError *err = nil;
        OSUDownloadController *dl = [[OSUDownloadController alloc] initWithPackageURL:u item:nil error:&err];
        if (err)
            [[NSApplication sharedApplication] presentError:err modalForWindow:window];
        (void)dl;
    }
}

extern NSDictionary *knownTrackOrderings;

- (void)textDidEndEditing:(NSNotification *)notification;
{
    NSArray *trax = [OSUItem dominantTracks:[[visibleTracksTextView string] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];

    OFInvocation *queueEntry = [[OFInvocation alloc] initForObject:[OSUPreferences self] selector:@selector(setVisibleTracks:) withObject:trax];
    [[OFMessageQueue mainQueue] addQueueEntry:queueEntry];
    [queueEntry release];
}

#pragma mark -
#pragma mark Private

- (void)_noteVisibleTracks:(NSNotification *)notification;
{
    NSArray *trax = [OSUPreferences visibleTracks];
    NSMutableSet *more = [NSMutableSet setWithArray:trax];
    NSMutableAttributedString *txt = [[NSMutableAttributedString alloc] init];
    NSDictionary *normAttrs = [NSDictionary dictionaryWithObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];
    NSDictionary *impliedAttrs = [NSDictionary dictionaryWithObject:[NSColor grayColor] forKey:NSForegroundColorAttributeName];
    NSDictionary *unkAttrs = [NSDictionary dictionaryWithObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];

    // tickle OSUItem so that its private static variable knownTrackOrderings becomes valid
    [OSUItem compareTrack:@"beta" toTrack:@"rc"];
    
    for(NSString *track in trax) {
        if ([NSString isEmptyString:track])
            continue;
        if ([txt length])
            [txt appendString:@" " attributes:normAttrs];
        
        NSSet *sup = [knownTrackOrderings objectForKey:track];
        if (sup) {
            [txt appendString:track attributes:normAttrs];
            for(NSString *aSup in sup) {
                if (![NSString isEmptyString:aSup] && ![more containsObject:aSup]) {
                    [txt appendString:@" " attributes:normAttrs];
                    [txt appendString:aSup attributes:impliedAttrs];
                    [more addObject:aSup];
                }
            }
        } else {
            [txt appendString:track attributes:unkAttrs];
        }
    }

    [[visibleTracksTextView textStorage] setAttributedString:txt];
    [txt release];
    
    NSArray *rTs = [OSUPreferences visibleTracks];
    NSString *rT = (rTs && [rTs count])? [rTs objectAtIndex:0] : [[OSUChecker sharedUpdateChecker] applicationTrack];
    // NSLog(@" %@ , \"%@\" -> \"%@\"", rTs, [[OSUChecker sharedUpdateChecker] applicationTrack], rT);
    [requestedTrackField setStringValue: [NSString isEmptyString:rT]? @"<final>" : rT];
}

@end
