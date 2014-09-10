// Copyright 2007-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUDownloadController.h"

#import "OSUErrors.h"
#import "OSUInstaller.h"
#import "OSUItem.h"
#import "OSUSendFeedbackErrorRecovery.h"
#import "OSUPreferences.h"

#import <AppKit/AppKit.h>

#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniAppKit/NSTextField-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

static BOOL OSUDebugDownload = NO;

#define DEBUG_DOWNLOAD(format, ...) \
do { \
    if (OSUDebugDownload) \
    NSLog((format), ## __VA_ARGS__); \
} while(0)

RCS_ID("$Id$");

static OSUDownloadController *CurrentDownloadController = nil;

@interface OSUDownloadController () <NSURLDownloadDelegate, OSUInstallerDelegate> {
  @private
    // Book-keeping information for swapping views in and out of the panel.
    NSView *_bottomView;
    NSSize _originalBottomViewSize;
    NSSize _originalWindowSize;
    NSSize _originalWarningViewSize;
    CGFloat _originalWarningTextHeight;
    CGFloat _warningTextTopMargin;
    
    // These are the toplevel views we might display in the panel.
    NSView *_plainStatusView;
    NSView *_credentialsView;
    NSView *_progressView;
    NSView *_installBasicView;         // Very basic, nonthreatening dialog text.
    NSView *_installOptionsNoteView;   // View with small note text displayed instead of options view.
    NSView *_installWarningView;       // Warning message and icon.
    NSView *_installButtonsView;       // Box containing the action buttons.
    
    NSTextField *_installViewMessageText;
    NSImageView *_installViewCautionImageView;
    NSTextField *_installViewCautionText;
    NSButton *_installViewInstallButton;
    
    NSURL *_packageURL;
    OSUItem *_item;
    NSURLRequest *_request;
    NSURLDownload *_download;
    NSURLAuthenticationChallenge *_challenge;
    BOOL _didFinishOrFail;
    BOOL _showCautionText;  // Usually describing a verification failure
    BOOL _displayingInstallView;
    
    NSString *_status;
    
    NSString *_userName;
    NSString *_password;
    BOOL _rememberInKeychain;
    
    off_t _currentBytesDownloaded;
    off_t _totalSize;
    
    // Where we're downloading the package to
    NSString *_suggestedDestinationFile;
    NSString *_destinationFile;
    
    // Where we think we'll install the new application
    NSString *_installationDirectory;
    NSAttributedString *_installationDirectoryNote;
    
    // Installer bookkeeping
    OSUInstaller *_installer;
}

@property (nonatomic, retain) IBOutlet NSView *bottomView;
@property (nonatomic, retain) IBOutlet NSView *plainStatusView;
@property (nonatomic, retain) IBOutlet NSView *credentialsView;
@property (nonatomic, retain) IBOutlet NSView *progressView;
@property (nonatomic, retain) IBOutlet NSView *installBasicView;
@property (nonatomic, retain) IBOutlet NSView *installOptionsNoteView;
@property (nonatomic, retain) IBOutlet NSView *installWarningView;
@property (nonatomic, retain) IBOutlet NSView *installButtonsView;

@property (nonatomic, retain) IBOutlet NSView *installViewMessageText;
@property (nonatomic, retain) IBOutlet NSImageView *installViewCautionImageView;
@property (nonatomic, retain) IBOutlet NSView *installViewCautionText;
@property (nonatomic, retain) IBOutlet NSView *installViewInstallButton;

@property (nonatomic, copy) NSString *installationDirectory;
@property (nonatomic, copy) NSAttributedString *installationDirectoryNote;

@property (nonatomic, copy) NSString *status;

@property (nonatomic, copy) NSString *userName;
@property (nonatomic, copy) NSString *password;
@property (nonatomic) BOOL rememberInKeychain;

@property (nonatomic) off_t currentBytesDownloaded;
@property (nonatomic) off_t totalSize;

@property (nonatomic, retain) OSUInstaller *installer;

- (IBAction)cancelAndClose:(id)sender;
- (IBAction)continueDownloadWithCredentials:(id)sender;
- (IBAction)installAndRelaunch:(id)sender;
- (IBAction)chooseDirectory:(id)sender;

- (void)_setInstallViews;
- (void)_setDisplayedView:(NSView *)aView;
- (void)setContentViews:(NSArray *)newContent;
- (void)_cancel;

@end

@implementation OSUDownloadController

+ (void)initialize;
{
    OBINITIALIZE;
    
    OSUDebugDownload = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUDebugDownload"];
}

+ (OSUDownloadController *)currentDownloadController;
{
    return CurrentDownloadController;
}

static void _FillOutDownloadInProgressError(NSError **outError)
{
    // TODO: Add recovery options to cancel the existing download?
    NSString *description = NSLocalizedStringFromTableInBundle(@"A download is already in progress.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description when trying to start a download when one is already in progress");
    NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please cancel the existing download before starting another.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error suggestion when trying to start a download when one is already in progress");
    OSUError(outError, OSUDownloadAlreadyInProgress, description, suggestion);
}

+ (BOOL)beginWithPackageURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;
{
    if (CurrentDownloadController != nil) {
        _FillOutDownloadInProgressError(outError);
        return NO;
    }
    
    CurrentDownloadController = [[self alloc] initWithPackageURL:packageURL item:item error:outError];
    return (CurrentDownloadController != nil);
}

// Item might be nil if all we have is the URL (say, if the debugging support for downloading from a URL at launch is enabled).
// *Usually* we'll have an item, but don't depend on it.

- (id)initWithPackageURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;
{
    self = [super init];
    if (self == nil)
        return nil;
    
    OBASSERT(CurrentDownloadController == nil);
    if (CurrentDownloadController != nil) {
        _FillOutDownloadInProgressError(outError);
        [self release];
        return nil;
    }

    // Display a 'connecting' view here until we know whether we are going to be asked for credentials or not (and to allow cancelling).
    
    _rememberInKeychain = NO;
    _packageURL = [packageURL copy];
    _request = [[NSURLRequest requestWithURL:packageURL] retain];
    _item = [item retain];
    _showCautionText = NO;

    [self setInstallationDirectory:[OSUInstaller suggestAnotherInstallationDirectory:nil trySelf:YES]];
    [self showWindow:nil];
    
    void (^startDownload)(void) = ^{
        // This starts the download
        _download = [[NSURLDownload alloc] initWithRequest:_request delegate:self];
        
        // At least until we support resuming downloads, let's delete them on failure.
        // TODO: This doesn't delete the file when you cancel the download.
        [_download setDeletesFileUponFailure:YES];
        
    };

    NSError *error = nil;
    if (_installationDirectory == nil || ![OSUInstaller validateTargetFilesystem:_installationDirectory error:&error]) {
        // We should only have to prompt the user to pick a directory if both the application's directory and /Applications on the root filesystem both live on read-only filesystems.
        [OSUInstaller chooseInstallationDirectory:_installationDirectory modalForWindow:self.window completionHandler:^(NSError *error, NSString *result) {
            if (result == nil) {
                [[NSApplication sharedApplication] presentError:error];
                [self cancelAndClose:nil];
            } else {
                startDownload();
            }
        }];
    } else {
        startDownload();
    }

    return self;
}

- (void)dealloc;
{    
    // Should have been done in -close, but just in case
    [self _cancel]; 
   
    OBASSERT(_download == nil);
    OBASSERT(_challenge == nil);
    OBASSERT(_request == nil);
    OBASSERT(CurrentDownloadController != self); // cleared in _cancel

    [_bottomView release];
    [_plainStatusView release];
    [_credentialsView release];
    [_progressView release];
    [_installBasicView release];
    [_installOptionsNoteView release];
    [_installWarningView release];
    [_installButtonsView release];
    [_installViewMessageText release];
    [_installViewCautionImageView release];
    [_installViewCautionText release];
    [_installViewInstallButton release];

    [_packageURL release];
    [_item release];
    
    [_status release];

    [_userName release];
    [_password release];

    [_suggestedDestinationFile release];
    [_destinationFile release];

    [_installationDirectory release];
    [_installationDirectoryNote release];
    
    [_installer release];

    [super dealloc];
}

#pragma mark -
#pragma mark NSWindowController subclass

- (NSString *)windowNibName;
{
    return NSStringFromClass([self class]);
}

- (void)windowDidLoad;
{
    [super windowDidLoad];
    
    OBASSERT([_bottomView window] == [self window]);
    
    _originalBottomViewSize = [_bottomView frame].size;
    _originalWindowSize = [[[self window] contentView] frame].size;
    _originalWarningViewSize = [_installWarningView frame].size;
    NSRect warningTextFrame = [_installViewCautionText frame];
    NSRect warningViewBounds = [_installWarningView bounds];
    _originalWarningTextHeight = warningTextFrame.size.height;
    _warningTextTopMargin = NSMaxY(warningViewBounds) - NSMaxY(warningTextFrame);

    OBASSERT([_installViewCautionText superview] == _installWarningView);
    OBASSERT([_installViewInstallButton superview] == _installButtonsView);
    OBASSERT([_installViewMessageText superview] == _installBasicView);

    NSString *name = [[[_request URL] path] lastPathComponent];
    [self setStatus:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Downloading %@ \\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download status - text is filename of update package being downloaded"), name]];
    
    [_installViewCautionText setStringValue:@"---"];
    [self _setDisplayedView:_plainStatusView];
    
    NSString *appDisplayName = [[NSProcessInfo processInfo] processName];
    [[self window] setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ Update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download window title - text is name of the running application"), appDisplayName]];
    
    NSString *basicText = [_installViewMessageText stringValue];
    basicText = [basicText stringByReplacingOccurrencesOfString:@"%@" withString:appDisplayName];
    [_installViewMessageText setStringValue:basicText];
    
    [self _adjustProgressIndiciateAttributesInSubtreeForView:_progressView];
    [self _adjustProgressIndiciateAttributesInSubtreeForView:_plainStatusView];
}

#pragma mark -
#pragma mark NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification;
{
    [self _cancel];
}

#pragma mark -
#pragma mark Actions

- (IBAction)cancelAndClose:(id)sender;
{
    [self close];
}

- (IBAction)continueDownloadWithCredentials:(id)sender;
{
    // We aren't a NSController, so we need to commit the editing...
    NSWindow *window = [self window];
    [window makeFirstResponder:window];
    
    NSURLCredential *credential = [[NSURLCredential alloc] initWithUser:_userName password:_password persistence:(_rememberInKeychain ? NSURLCredentialPersistencePermanent : NSURLCredentialPersistenceForSession)];
    [[_challenge sender] useCredential:credential forAuthenticationChallenge:_challenge];
    [credential release];

    // Switch views so that if we get another credential failure, the user sees that we *tried* to use what they gave us, but failed again.
    [self _setDisplayedView:_progressView];
}

- (IBAction)installAndRelaunch:(id)sender;
{
    OBPRECONDITION(self.installer == nil);
    if (self.installer != nil) {
        return;
    }

    // OSUInstaller will either fail during decode & preflight, and ask us to close and leave us running, or complete (either successfully, or by posting an error and quitting.)
    // In the later case, *it* is responsible for initiating the application termination sequence.

    OSUInstaller *installer = [[OSUInstaller alloc] initWithPackagePath:_destinationFile];
    
    installer.delegate = self;
    installer.installedVersionPath = [[NSBundle mainBundle] bundlePath];
    
    if (_installationDirectory != nil)
        installer.installationDirectory = _installationDirectory;
    
    self.installer = installer;
    [installer autorelease];
    
    [self _setDisplayedView:_plainStatusView];
    [installer run];
}

- (NSString *)status;
{
    return _status;
}

- (void)setStatus:(NSString *)status
{
    if (status != _status) {
        [_status release];
        _status = [status copy];

        [[self window] displayIfNeeded];
    }
}

- (IBAction)chooseDirectory:(id)sender;
{
    NSString *initialDirectory = [OSUInstaller suggestAnotherInstallationDirectory:[self installationDirectory] trySelf:YES];

    [OSUInstaller chooseInstallationDirectory:initialDirectory modalForWindow:[self window] completionHandler:^(NSError *error, NSString *result) {
        if (result != nil) {
            [self setInstallationDirectory:result];
        }
    }];
}

#pragma mark -
#pragma mark KVC/KVO

+ (NSSet *)keyPathsForValuesAffectingSizeKnown;
{
    return [NSSet setWithObject:@"totalSize"];
}

- (BOOL)sizeKnown;
{
    return _totalSize != 0ULL;
}

- (NSString *)installationDirectory;
{
    return _installationDirectory;
}

- (void)setInstallationDirectory:(NSString *)installationDirectory
{
    if (OFISEQUAL(_installationDirectory, installationDirectory))
        return;
    
    [_installationDirectory release];
    _installationDirectory = [installationDirectory copy];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *noteTemplate = nil;
    
    if (installationDirectory && ![installationDirectory isEqualToString:[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent]]) {
        if (noteTemplate == nil) {
            NSString *homeDir = [NSHomeDirectory() stringByExpandingTildeInPath];
            if ([fileManager path:homeDir isAncestorOfPath:installationDirectory relativePath:NULL]) {
                noteTemplate = NSLocalizedStringFromTableInBundle(@"The update will be installed in your @ folder.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Install dialog message - small note indicating that app will be installed in a user directory - @ is replaced with name of directory, eg Applications");
            }
        }
        
        if (noteTemplate == nil) {
            noteTemplate = NSLocalizedStringFromTableInBundle(@"The update will be installed in the @ folder.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Install dialog message - small note indicating that app will be installed in a system or network directory - @ is replaced with name of directory, eg Applications");
        }
    }
    
    if (noteTemplate != nil) {
        CGFloat fontSize = [NSFont smallSystemFontSize];
        
        NSString *displayName = [fileManager displayNameAtPath:installationDirectory];
        if (displayName == nil) {
            displayName = [installationDirectory lastPathComponent];
        }

        NSMutableAttributedString *infix = [[NSMutableAttributedString alloc] initWithString:displayName];
        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:installationDirectory];
        if (icon && [icon isValid]) {
            icon = [icon copy];
            [icon setSize:(NSSize){fontSize, fontSize}];
            [infix replaceCharactersInRange:(NSRange){0, 0} withString:[NSString stringWithCharacter:0x00A0]]; // non-breaking space
            [infix replaceCharactersInRange:(NSRange){0, 0} withAttributedString:[NSAttributedString attributedStringWithImage:icon]];
            [icon release];
        }
        
        [infix addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:fontSize] range:(NSRange){0, [infix length]}];
        
        NSMutableAttributedString *message = [[NSMutableAttributedString alloc] initWithString:noteTemplate attributes:[NSDictionary dictionaryWithObject:[NSFont messageFontOfSize:fontSize] forKey:NSFontAttributeName]];
        [message replaceCharactersInRange:[noteTemplate rangeOfString:@"@"] withAttributedString:infix];
        
        [infix release];
        
        self.installationDirectoryNote = message;
        [message release];
    } else {
        self.installationDirectoryNote = nil;
    }
    
    if (_displayingInstallView) {
        [self queueSelectorOnce:@selector(_setInstallViews)];
    }
}

#pragma mark -
#pragma mark NSURLDownload delegate

- (void)downloadDidBegin:(NSURLDownload *)download;
{
    DEBUG_DOWNLOAD(@"did begin %@", download);
}

- (NSURLRequest *)download:(NSURLDownload *)download willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse;
{
    DEBUG_DOWNLOAD(@"will send request %@ for %@", request, download);
    return request;
}

- (void)download:(NSURLDownload *)download didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    DEBUG_DOWNLOAD(@"didReceiveAuthenticationChallenge %@", challenge);
    
    DEBUG_DOWNLOAD(@"protectionSpace = %@", [challenge protectionSpace]);
    DEBUG_DOWNLOAD(@"  realm = %@", [[challenge protectionSpace] realm]);
    DEBUG_DOWNLOAD(@"  host = %@", [[challenge protectionSpace] host]);
    DEBUG_DOWNLOAD(@"  port = %ld", [[challenge protectionSpace] port]);
    DEBUG_DOWNLOAD(@"  isProxy = %d", [[challenge protectionSpace] isProxy]);
    DEBUG_DOWNLOAD(@"  proxyType = %@", [[challenge protectionSpace] proxyType]);
    DEBUG_DOWNLOAD(@"  protocol = %@", [[challenge protectionSpace] protocol]);
    DEBUG_DOWNLOAD(@"  authenticationMethod = %@", [[challenge protectionSpace] authenticationMethod]);
    DEBUG_DOWNLOAD(@"  receivesCredentialSecurely = %d", [[challenge protectionSpace] receivesCredentialSecurely]);
    
    DEBUG_DOWNLOAD(@"previousFailureCount = %ld", [challenge previousFailureCount]);
    NSURLCredential *proposed = [challenge proposedCredential];
    DEBUG_DOWNLOAD(@"proposed = %@", proposed);
    
    [_challenge autorelease];
    _challenge = [challenge retain];

    if ([challenge previousFailureCount] == 0 && (proposed != nil) && ![NSString isEmptyString:[proposed user]] && ![NSString isEmptyString:[proposed password]]) {
        // Try the proposed credentials, if any, the first time around.  I've gotten a non-nil proposal with a null user name on 10.4 before.
        [[_challenge sender] useCredential:proposed forAuthenticationChallenge:_challenge];
        return;
    }
    
    // Clear our status to stop the animation in the view.  NSProgressIndicator hates getting removed from the view while it is animating, yielding exceptions in the heartbeat thread.
    [self setStatus:nil];
    [self _setDisplayedView:_credentialsView];
    [self showWindow:nil];
    [NSApp requestUserAttention:NSInformationalRequest]; // Let the user know they need to interact with us (else the server will timeout waiting for authentication).
}

- (void)download:(NSURLDownload *)download didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    DEBUG_DOWNLOAD(@"didCancelAuthenticationChallenge %@", challenge);
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response;
{
    DEBUG_DOWNLOAD(@"didReceiveResponse %@", response);
    DEBUG_DOWNLOAD(@"  URL %@", [response URL]);
    DEBUG_DOWNLOAD(@"  MIMEType %@", [response MIMEType]);
    DEBUG_DOWNLOAD(@"  expectedContentLength %qd", [response expectedContentLength]);
    DEBUG_DOWNLOAD(@"  textEncodingName %@", [response textEncodingName]);
    DEBUG_DOWNLOAD(@"  suggestedFilename %@", [response suggestedFilename]);
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        DEBUG_DOWNLOAD(@"  statusCode %ld", [(NSHTTPURLResponse *)response statusCode]);
        DEBUG_DOWNLOAD(@"  allHeaderFields %@", [(NSHTTPURLResponse *)response allHeaderFields]);
    }

    [self setTotalSize:[response expectedContentLength]];
    [self _setDisplayedView:_progressView];
}

- (void)download:(NSURLDownload *)download willResumeWithResponse:(NSURLResponse *)response fromByte:(long long)startingByte;
{
    DEBUG_DOWNLOAD(@"willResumeWithResponse %@ fromByte %qd", response, startingByte);
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length;
{
    off_t newBytesDownloaded = _currentBytesDownloaded + length;
    self.currentBytesDownloaded = newBytesDownloaded;
}

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType;
{
    DEBUG_DOWNLOAD(@"shouldDecodeSourceDataOfMIMEType %@", encodingType);
    return YES;
}

- (void)download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename;
{
    DEBUG_DOWNLOAD(@"decideDestinationWithSuggestedFilename %@", filename);
    
    NSFileManager *manager = [NSFileManager defaultManager];
    
    // Save disk images to the user's downloads folder.
    NSString *folder = nil;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES /* expand tilde */);
    if ([paths count] > 0) {
        NSString *cachePath = [paths objectAtIndex:0];
        folder = [cachePath stringByAppendingPathComponent:OMNI_BUNDLE_IDENTIFIER];
        if (folder != nil && ![manager directoryExistsAtPath:folder]) {
            NSError *error = nil;
            if (![manager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
#ifdef DEBUG		
                NSLog(@"Unable to create download directory at specified location '%@' -- %@", folder, error);
#endif		    
                folder = nil;
            }
        }
    }
    
    // On some people's machines, we'll end up with foo.tbz2.bz2 as the suggested name.  This is not good; it seems to come from having a 3rd party utility instaled that handles bz2 files, registering a set of UTIs that convinces NSURLDownload to suggest the more accurate extension.  So, we ignore the suggestion and use the filename from the URL.
    
    NSString *originalFileName = [[_packageURL path] lastPathComponent];
    OBASSERT([[OSUInstaller supportedPackageFormats] containsObject:[originalFileName pathExtension]]);
    
    _suggestedDestinationFile = [[folder stringByAppendingPathComponent:originalFileName] copy];
    
    DEBUG_DOWNLOAD(@"  destination: %@", _suggestedDestinationFile);
    [download setDestination:_suggestedDestinationFile allowOverwrite:YES];
}

- (void)download:(NSURLDownload *)download didCreateDestination:(NSString *)path;
{
    DEBUG_DOWNLOAD(@"didCreateDestination %@", path);
    
    [_destinationFile autorelease];
    _destinationFile = [path copy];
    
    // Quarantine the file. Later, after we verify its checksum, we can remove the quarantine.
    NSError *qError = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm quarantinePropertiesForItemAtPath:path error:&qError] != nil) {
        // It already has a quarantine (presumably we're running with LSFileQuarantineEnabled in our Info.plist)
        // And apparently it's not possible to change the parameters of an existing quarantine event
        // So just assume that NSURLDownload did something that was good enough
    } else {
        if ( !([[qError domain] isEqualToString:NSOSStatusErrorDomain] && [qError code] == unimpErr) ) {
            
            NSMutableDictionary *qua = [NSMutableDictionary dictionary];
            [qua setObject:(id)kLSQuarantineTypeOtherDownload forKey:(id)kLSQuarantineTypeKey];
            [qua setObject:[[download request] URL] forKey:(id)kLSQuarantineDataURLKey];
            NSString *fromWhere = [_item sourceLocation];
            if (fromWhere) {
                NSURL *parsed = [NSURL URLWithString:fromWhere];
                if (parsed)
                    [qua setObject:parsed forKey:(id)kLSQuarantineOriginURLKey];
            }
            
            [fm setQuarantineProperties:qua forItemAtPath:path error:NULL];
        }
    }
}

- (void)downloadDidFinish:(NSURLDownload *)download;
{
    DEBUG_DOWNLOAD(@"downloadDidFinish %@", download);
    _didFinishOrFail = YES;
    
    [self setStatus:NSLocalizedStringFromTableInBundle(@"Verifying file\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download status")];
    NSString *caution = [_item verifyFile:_destinationFile];
    if (![NSString isEmptyString:caution]) {
        [_installViewCautionText setStringValue:caution];
        _showCautionText = YES;
    }
    
    [self setStatus:NSLocalizedStringFromTableInBundle(@"Ready to Install", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download status - Done downloading, about to prompt the user to let us reinstall and restart the app")];
    
    if (![NSApp isActive])
        [NSApp requestUserAttention:NSInformationalRequest];
    else
        [self showWindow:nil];
    
    [self _setInstallViews];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error;
{
    DEBUG_DOWNLOAD(@"didFailWithError %@", error);
    _didFinishOrFail = YES;
    
    BOOL suggestLocalFileProblem = NO;
    BOOL suggestTransitoryNetworkProblem = NO;
    BOOL shouldDisplayUnderlyingError = YES;
    NSInteger code = [error code];
    
    // Try to specialize the error text based on what happened.
    
    // NB: Apple cleverly returns NSURL error codes in kCFErrorDomainCFNetwork.
    if ([[error domain] isEqualToString:NSURLErrorDomain] || [[error domain] isEqualToString:(NSString *)kCFErrorDomainCFNetwork]) {
        if (code == NSURLErrorCancelled || code == NSURLErrorUserCancelledAuthentication) {
            // Don't display errors thown due to the user cancelling the authentication.
            return;
        }
        
        if (code <= NSURLErrorCannotCreateFile && code >= (NSURLErrorCannotCreateFile - 1000)) {
            // This seems to be the range set aside for local-filesystem-related problems.
            suggestLocalFileProblem = YES;
        }
        
        if (code == NSURLErrorTimedOut ||
            code == NSURLErrorCannotFindHost ||
            code == NSURLErrorCannotConnectToHost ||
            code == NSURLErrorDNSLookupFailed ||
            code == NSURLErrorNotConnectedToInternet) {
            suggestTransitoryNetworkProblem = YES;
        }
        
        // Suppress display of the less-helpful generic error messages
        if (code == NSURLErrorUnknown || code == NSURLErrorCannotLoadFromNetwork)
            shouldDisplayUnderlyingError = NO;
        
    } else if ([[error domain] isEqualToString:NSCocoaErrorDomain]) {
        
        if (code == NSUserCancelledError) {
            // Don't display errors due to user cancelling an operation.
            return;
        }
        
        if (code >= NSFileErrorMinimum && code <= NSFileErrorMaximum) {
            suggestLocalFileProblem = YES;
        }
        
    }
    
        
    NSString *file = _destinationFile ? _destinationFile : _suggestedDestinationFile;
    
    NSString *errorSuggestion;
    
    if (file)
        errorSuggestion = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to download %@ to %@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - unable to download URL to LOCALFILENAME - will often be followed by more detailed explanation"), _packageURL, file];
    else
        errorSuggestion = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to download %@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - unable to download URL (but no LOCALFILENAME was chosen yet) - will often be followed by more detailed explanation"), _packageURL];

    if (suggestTransitoryNetworkProblem)
        errorSuggestion = [NSString stringWithStrings:errorSuggestion, @"\n\n",
                           NSLocalizedStringFromTableInBundle(@"This may be a temporary network problem.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - unable to download URL - extra text if it looks like a transitory network problem"), nil];
    
    if (suggestLocalFileProblem)
        errorSuggestion = [NSString stringWithStrings:errorSuggestion, @"\n\n",
                           NSLocalizedStringFromTableInBundle(@"Please check the permissions and space available in your downloads folder.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error message - unable to download URL - extra text if it looks like a problem with the local filesystem"), nil];

    if (shouldDisplayUnderlyingError) {
        NSString *underly = [error localizedDescription];
        if (![NSString isEmptyString:underly])
            errorSuggestion = [NSString stringWithFormat:@"%@ (%@)", errorSuggestion, underly];
    }
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  NSLocalizedStringFromTableInBundle(@"Download failed", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error title"), NSLocalizedDescriptionKey,
                                  errorSuggestion, NSLocalizedRecoverySuggestionErrorKey,
                                  error, NSUnderlyingErrorKey,
                                  nil];
    error = [NSError errorWithDomain:OSUErrorDomain code:OSUDownloadFailed userInfo:userInfo];
    
    error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:nil options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
    if (![[self window] presentError:error])
        [self close]; // Didn't recover
}

#pragma mark -
#pragma mark Private

- (void)_adjustProgressIndiciateAttributesInSubtreeForView:(NSView *)view;
{
    for (NSView *subview in view.subviews) {
        [self _adjustProgressIndiciateAttributesInSubtreeForView:subview];
        
        // Threaded animation doesn't play nicely with our blocking animation; it causes visual glitches.
        // Probably shoudl move off of blocking animation, but easier to just turn this off for now.
        if ([subview isKindOfClass:[NSProgressIndicator class]]) {
            NSProgressIndicator *progressIndicator = (NSProgressIndicator *)subview;
            [progressIndicator setUsesThreadedAnimation:NO];
        }
    }
}

- (void)_setInstallViews;
{
    NSMutableArray *installViews = [NSMutableArray array];
    [installViews addObject:_installBasicView];

    if (_installationDirectoryNote != nil) {
        [installViews addObject:_installOptionsNoteView];
    }
    
    if (_showCautionText) {
        [installViews addObject:_installWarningView];
        // Resize the warning text, if it's tall, and resize its containing view as well. Unfortunately, just resizing the containing view and telling it to automatically resize its subviews doesn't do the right thing here, so we do the bookkeeping ourselves.
        NSSize textSize = [_installViewCautionText desiredFrameSize:NSViewHeightSizable];
        NSRect textFrame = [_installViewCautionText frame];
        if (textSize.height <= _originalWarningTextHeight) {
            [_installWarningView setFrameSize:_originalWarningViewSize];
            textFrame.size.height = _originalWarningTextHeight;
        } else {
            [_installWarningView setFrameSize:(NSSize){
                .width = _originalWarningViewSize.width,
                .height = ceil(_originalWarningViewSize.height + textSize.height - _originalWarningTextHeight)
            }];
            textFrame.size.height = textSize.height;
        }
        
        textFrame.origin.y = ceil(NSMaxY([_installWarningView bounds]) - _warningTextTopMargin - textFrame.size.height);
        [_installViewCautionText setFrame:textFrame];
        [_installViewCautionText setNeedsDisplay:YES];
        [_installWarningView setNeedsDisplay:YES];
        [_installViewCautionImageView setImage:[NSImage imageNamed:NSImageNameCaution]];
    }

    [installViews addObject:_installButtonsView];
    
    _displayingInstallView = YES;
    [self setContentViews:installViews];
}

- (void)_setDisplayedView:(NSView *)aView;
{
    _displayingInstallView = NO;
    [self setContentViews:[NSArray arrayWithObject:aView]];
}

- (void)setContentViews:(NSArray *)newContent;
{
    NSWindow *window = [self window];
    
    // Get a list of view animations to position all the new content in _bottomView
    // (and to hide the old content)
    NSSize desiredBottomViewFrameSize = _originalBottomViewSize;
    NSMutableArray *animations = [_bottomView animationsToStackSubviews:newContent finalFrameSize:&desiredBottomViewFrameSize];
    
    // Compute the desired size of the window frame.
    // By virtue of the fact that our bottom view is flipped, resizable and the various contents are set to be top-aligned, this is the only resizing we need.
    
    CGFloat desiredWindowContentWidth = _originalWindowSize.width + desiredBottomViewFrameSize.width - _originalBottomViewSize.width;
    CGFloat desiredWindowContentHeight = _originalWindowSize.height + desiredBottomViewFrameSize.height - _originalBottomViewSize.height;
    NSRect oldFrame = [window frame];
    NSRect windowFrame = [window contentRectForFrameRect:oldFrame];
    windowFrame.size.width = desiredWindowContentWidth;
    windowFrame.size.height = desiredWindowContentHeight;
    windowFrame = [window frameRectForContentRect:windowFrame];
    
    // It looks nicest if we keep the window's title bar in approximately the same position when resizing.
    // NSWindow screen coordinates are in a Y-increases-upwards orientation.
    windowFrame.origin.y += ( NSMaxY(oldFrame) - NSMaxY(windowFrame) );

    // If moving horizontally, let's see if keeping a point 1/3 from the left looks good.
    windowFrame.origin.x = floor(oldFrame.origin.x + (oldFrame.size.width - windowFrame.size.width)/3);

    NSScreen *windowScreen = [window screen];
    if (windowScreen) {
        windowFrame = OFConstrainRect(windowFrame, [windowScreen visibleFrame]);
    }
    
    if (!NSEqualRects(oldFrame, windowFrame)) {
        NSDictionary *animationDictionary = @{
            NSViewAnimationTargetKey : window,
            NSViewAnimationStartFrameKey : [NSValue valueWithRect:oldFrame],
            NSViewAnimationEndFrameKey : [NSValue valueWithRect:windowFrame],
        };
        [animations addObject:animationDictionary];
    }

    // Animate if there was anything to do.
    if ([animations count] > 0) {
        NSViewAnimation *animation = [[[NSViewAnimation alloc] initWithViewAnimations:animations] autorelease];
        NSTimeInterval duration = [window isVisible] ? 0.1 : 0.0;
        [animation setDuration:duration];
        [animation setAnimationBlockingMode:NSAnimationBlocking];
        [animation startAnimation];
    }
    
    // Update up the key view loop and first responder if appropriate
    // If there are no animations, assume we don't need to make any changes to the key view loop.
    if ([animations count] > 0) {
       [window recalculateKeyViewLoop];
        
        NSView *nextValidKeyView = [[newContent objectAtIndex:0] nextValidKeyView];
        BOOL shouldAdjustFirstResponder = [window firstResponder] == nil || [window firstResponder] == window;
        if (shouldAdjustFirstResponder && nextValidKeyView != nil) {
            [window makeFirstResponder:nextValidKeyView];
        }
    }
}

- (void)_cancel;
{
    OBPRECONDITION(CurrentDownloadController == self || CurrentDownloadController == nil);
    
    if (CurrentDownloadController == self) {
        [CurrentDownloadController autorelease]; // We own the reference from +beginWithPackageURL:item:error:
        CurrentDownloadController = nil;
    }
    
    [[_challenge sender] cancelAuthenticationChallenge:_challenge];
    [_challenge release];
    _challenge = nil;
    
    if (!_didFinishOrFail) {
        // NSURLDownload will delete the downloaded file if you -cancel it after a successful download!  So, only call -cancel if we didn't finish or fail.
        [_download cancel];
        
        // If we are explictly cancelling, delete the file
        if (![NSString isEmptyString:_destinationFile])
            [[NSFileManager defaultManager] removeItemAtPath:_destinationFile error:NULL];
    }
    
    [_request release];
    _request = nil;
    
    [_download release];
    _download = nil;
}

@end

