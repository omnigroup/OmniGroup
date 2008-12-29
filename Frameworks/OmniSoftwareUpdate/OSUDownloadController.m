// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUDownloadController.h"

#import "OSUErrors.h"
#import "OSUInstaller.h"
#import "OSUSendFeedbackErrorRecovery.h"

#import <OmniAppKit/OAInternetConfig.h>
#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/OFVersionNumber.h>

#import <OmniFoundation/OFMultipleOptionErrorRecovery.h>
#import <OmniFoundation/OFCancelErrorRecovery.h>

static BOOL OSUDebugDownload = NO;

#define DEBUG_DOWNLOAD(format, ...) \
do { \
    if (OSUDebugDownload) \
    NSLog((format), ## __VA_ARGS__); \
} while(0)

RCS_ID("$Id$");

static NSString * const OSUDownloadControllerStatusKey = @"status";
static NSString * const OSUDownloadControllerCurrentBytesDownloadedKey = @"currentBytesDownloaded";
static NSString * const OSUDownloadControllerTotalSizeKey = @"totalSize";
static NSString * const OSUDownloadControllerSizeKnownKey = @"sizeKnown";

static OSUDownloadController *CurrentDownloadController = nil;

@interface OSUDownloadController (Private)
- (void)_setBottomViewContentView:(NSView *)view;
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

// Item might be nil if all we have is the URL (say, if the debugging support for downloading from a URL at launch is enabled).  *Usually* we'll have an item, but don't depend on it.
- initWithPackageURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;
{
    if (![super init])
        return nil;

    // Only allow one download at a time for now.
    if (CurrentDownloadController) {
        // TODO: Add recovery options to cancel the existing download?
        NSString *description = NSLocalizedStringFromTableInBundle(@"A download is already in progress.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description when trying to start a download when one is already in progress");
        NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please cancel the existing download before starting another.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error suggestion when trying to start a download when one is already in progress");
        OSUError(outError, OSUDownloadAlreadyInProgress, description, suggestion);
        return NO;
    }
    CurrentDownloadController = self;
    
    // Display a 'connecting' view here until we know whether we are going to be asked for credentials or not (and to allow cancelling).
    
    _rememberInKeychain = NO;
    _packageURL = [packageURL copy];
    _request = [[NSURLRequest requestWithURL:packageURL] retain];
    
    [self showWindow:nil];
    
    // This starts the download
    _download = [[NSURLDownload alloc] initWithRequest:_request delegate:self];
    
    // at least until we support resuming downloads, let's delete them on failure.
    // TODO: This doesn't delete the file when you cancel the download.
    [_download setDeletesFileUponFailure:YES];
    
    return self;
}

- (void)dealloc;
{    
    [self _cancel]; // should have been done in -close, but just in case
    OBASSERT(_download == nil);
    OBASSERT(_challenge == nil);
    OBASSERT(_request == nil);
    
    // _bottomView is embedded in our window and need not be released
    [_credentialsView release];
    [_progressView release];
    [_packageURL release];
    
    [_suggestedDestinationFile release];
    [_destinationFile release];
    
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
    
    NSString *name = [[[_request URL] path] lastPathComponent];
    [self setValue:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Downloading %@ ...", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download status"), name] forKey:OSUDownloadControllerStatusKey];
    
    [self _setBottomViewContentView:_plainStatusView];
    
    [[self window] setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ Update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download window title"), [[NSProcessInfo processInfo] processName]]];
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
    
    NSURLCredential *credential = [[[NSURLCredential alloc] initWithUser:_userName password:_password persistence:(_rememberInKeychain ? NSURLCredentialPersistencePermanent : NSURLCredentialPersistenceForSession)] autorelease];
    [[_challenge sender] useCredential:credential forAuthenticationChallenge:_challenge];

    // Switch views so that if we get another credential failure, the user sees that we *tried* to use what they gave us, but failed again.
    [self _setBottomViewContentView:_progressView];
}

- (void)_documentController:(NSDocumentController *)documentController didCloseAll:(BOOL)didCloseAll contextInfo:(void *)contextInfo;
{
    // Edited document still open.  Leave our 'Update and Relaunch' view up; the user might save and decide to install the update in a little bit.
    if (!didCloseAll)
        return;
    
    [self _setBottomViewContentView:_plainStatusView];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // The code below will eventually call the normal NSApp termination logic (which the app can use to close files and such).
    NSError *error = nil;
    if (![OSUInstaller installAndRelaunchFromPackage:_destinationFile
                              archiveExistingVersion:[defaults boolForKey:@"OSUUpgradeArchivesExistingVersion"]
                            deleteDiskImageOnSuccess:![defaults boolForKey:@"OSUUpgradeKeepsDiskImage"]
                                  statusBindingPoint:(OFBindingPoint){self, OSUDownloadControllerStatusKey}
                                               error:&error]) {
        // Reveal the disk image on failure.
        [[NSWorkspace sharedWorkspace] selectFile:_destinationFile inFileViewerRootedAtPath:nil];
        
        error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:nil options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
        [NSApp presentError:error];
        [self close];
    }
    
    // On success, we should really be dead at this point...
}

- (IBAction)installAndRelaunch:(id)sender;
{
    // Close all the document windows, allowing the user to cancel.
    [[NSDocumentController sharedDocumentController] closeAllDocumentsWithDelegate:self didCloseAllSelector:@selector(_documentController:didCloseAll:contextInfo:) contextInfo:NULL];
}

- (IBAction)revealDownloadInFinder:(id)sender;
{
    [[NSWorkspace sharedWorkspace] selectFile:_destinationFile inFileViewerRootedAtPath:nil];
    [self close];
}

#pragma mark -
#pragma mark KVC/KVO

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key;
{
    if ([key isEqualToString:OSUDownloadControllerSizeKnownKey])
	return [NSSet setWithObject:OSUDownloadControllerTotalSizeKey];
    return [super keyPathsForValuesAffectingValueForKey:key];
}

- (BOOL)sizeKnown;
{
    return _totalSize != 0ULL;
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
    DEBUG_DOWNLOAD(@"  port = %d", [[challenge protectionSpace] port]);
    DEBUG_DOWNLOAD(@"  isProxy = %d", [[challenge protectionSpace] isProxy]);
    DEBUG_DOWNLOAD(@"  proxyType = %@", [[challenge protectionSpace] proxyType]);
    DEBUG_DOWNLOAD(@"  protocol = %@", [[challenge protectionSpace] protocol]);
    DEBUG_DOWNLOAD(@"  authenticationMethod = %@", [[challenge protectionSpace] authenticationMethod]);
    DEBUG_DOWNLOAD(@"  receivesCredentialSecurely = %d", [[challenge protectionSpace] receivesCredentialSecurely]);
    
    DEBUG_DOWNLOAD(@"previousFailureCount = %d", [challenge previousFailureCount]);
    NSURLCredential *proposed = [challenge proposedCredential];
    DEBUG_DOWNLOAD(@"proposed = %@", proposed);
    
    [_challenge autorelease];
    _challenge = [challenge retain];

    if ([challenge previousFailureCount] == 0 && (proposed != nil) && ![NSString isEmptyString:[proposed user]] && ![NSString isEmptyString:[proposed password]]) {
        // Try the proposed credentials, if any, the first time around.  I've gotten a non-nil proposal with a null user name on 10.4 before.
        [[_challenge sender] useCredential:proposed forAuthenticationChallenge:_challenge];
        return;
    }
    
    [self _setBottomViewContentView:_credentialsView];
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
        DEBUG_DOWNLOAD(@"  statusCode %d", [(NSHTTPURLResponse *)response statusCode]);
        DEBUG_DOWNLOAD(@"  allHeaderFields %@", [(NSHTTPURLResponse *)response allHeaderFields]);
    }

    [self setValue:[NSNumber numberWithUnsignedLongLong:[response expectedContentLength]] forKey:OSUDownloadControllerTotalSizeKey];
    [self _setBottomViewContentView:_progressView];
}

- (void)download:(NSURLDownload *)download willResumeWithResponse:(NSURLResponse *)response fromByte:(long long)startingByte;
{
    DEBUG_DOWNLOAD(@"willResumeWithResponse %@ fromByte %d", response, startingByte);
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(unsigned)length;
{
    off_t newBytesDownloaded = _currentBytesDownloaded + length;
    [self setValue:[NSNumber numberWithUnsignedLongLong:newBytesDownloaded] forKey:OSUDownloadControllerCurrentBytesDownloadedKey];
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
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES /* expand tilde */);
    if ([paths count] > 0) {
        folder = [paths objectAtIndex:0];
        if (folder && ![manager directoryExistsAtPath:folder]) {
            NSError *error = nil;
            if (![manager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
#ifdef DEBUG		
                NSLog(@"Unable to create download directory at specified location '%@' -- %@", folder, error);
#endif		    
                folder = nil;
            }
        }
    }
    
    if (!folder) {
        folder = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES/*expandTilde*/) lastObject];
        if ([NSString isEmptyString:folder]) {
            folder = [NSSearchPathForDirectoriesInDomains(NSUserDirectory, NSUserDomainMask, YES/*expandTilde*/) lastObject];
            if ([NSString isEmptyString:folder]) {
                // Terrible news everyone!
#ifdef DEBUG		
                NSLog(@"Couldn't find a directory into which to download.");
#endif		
                [download cancel];
                return;
            }
        }
    }
    
    // On some people's machines, we'll end up with foo.tbz2.bz2 as the suggested name.  This is not good; it seems to come from having a 3rd party utility instaled that handles bz2 files, registering a set of UTIs that convinces NSURLDownload to suggest something strange.  So, we ignore the suggestion and use the filename from the URL.
    
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
}

- (void)downloadDidFinish:(NSURLDownload *)download;
{
    DEBUG_DOWNLOAD(@"downloadDidFinish %@", download);
    _didFinishOrFail = YES;
    if (![NSApp isActive])
        [NSApp requestUserAttention:NSInformationalRequest];
    else
        [self showWindow:nil];
    
    [self _setBottomViewContentView:_installView];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error;
{
    DEBUG_DOWNLOAD(@"didFailWithError %@", error);
    _didFinishOrFail = YES;
    
    if ([[error domain] isEqualToString:NSURLErrorDomain] && [error code] == NSURLErrorUserCancelledAuthentication) {
        // Don't display errors thown due to the user cancelling the authentication.
    } else {
        NSString *file = _destinationFile ? _destinationFile : _suggestedDestinationFile;
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  NSLocalizedStringFromTableInBundle(@"Download failed", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error title"), NSLocalizedDescriptionKey,
                                  [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to download %@ to %@.\n\nPlease check the permissions and space available in your downloads folder.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error suggestion"), _packageURL, file], NSLocalizedRecoverySuggestionErrorKey,
                                  error, NSUnderlyingErrorKey,
                                  nil];
        error = [NSError errorWithDomain:OMNI_BUNDLE_IDENTIFIER code:OSUDownloadFailed userInfo:userInfo];
        
        error = [OFMultipleOptionErrorRecovery errorRecoveryErrorWithError:error object:nil options:[OSUSendFeedbackErrorRecovery class], [OFCancelErrorRecovery class], nil];
        if (![[self window] presentError:error])
            [self close]; // Didn't recover
    }
}

@end

@implementation OSUDownloadController (Private)

- (void)_setBottomViewContentView:(NSView *)view;
{
    if (!view)
        view = _plainStatusView;
    
    NSView *oldBottomView = [[_bottomView subviews] lastObject];
    
    if (view == oldBottomView)
        return;
    
    BOOL wantsStatus = (view == _progressView || view == _plainStatusView || view == _installView);
    
    if (!wantsStatus) {
        // Clear our status to stop the animation in the view.  NSProgressIndicator hates getting removed from the view while it is animating, yielding exceptions in the heartbeat thread.
        [self setValue:nil forKey:OSUDownloadControllerStatusKey];
    }
    
    NSMutableArray *animations = [NSMutableArray array];
    
    NSWindow *window = [self window];
    NSRect oldWindowFrame = [window frame];
    NSRect oldBottomFrame = [_bottomView frame];
    
    float targetBottomContentHeight = NSHeight([view frame]);
    
    float delta = targetBottomContentHeight - NSHeight(oldBottomFrame);
    
    if (delta != 0.0f) {
        NSRect newWindowFrame = oldWindowFrame;
        newWindowFrame.origin.y -= delta;
        newWindowFrame.size.height += delta;

        // By virtue of the fact that our bottom view is flipped, resizable and the various contents are set to be top-aligned, this is the only resizing we need.
        [animations addObject:[NSDictionary dictionaryWithObjectsAndKeys:window, NSViewAnimationTargetKey, [NSValue valueWithRect:oldWindowFrame], NSViewAnimationStartFrameKey, [NSValue valueWithRect:newWindowFrame], NSViewAnimationEndFrameKey, nil]];
    }
    
    
    if (oldBottomView != view) {
        [window makeFirstResponder:window];
        
        if (oldBottomView)
            [animations addObject:[NSDictionary dictionaryWithObjectsAndKeys:oldBottomView, NSViewAnimationTargetKey, NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey, nil]];

        if (view) {
            // Position the view at the top of the bottom view (which is flipped) and mark it hidden (the animation will unhide it).
            NSRect frame = [view bounds];
            frame.origin = NSMakePoint(0, 0);
            frame.size.width = NSWidth(oldBottomFrame);
            
            [view setFrame:frame];
            [view setHidden:YES];
            [_bottomView addSubview:view];
            
            [animations addObject:[NSDictionary dictionaryWithObjectsAndKeys:view, NSViewAnimationTargetKey, NSViewAnimationFadeInEffect, NSViewAnimationEffectKey, nil]];
        }
    }
    
    if ([animations count]) {
        // Animate if there was anything to do.
        NSViewAnimation *animation = [[[NSViewAnimation alloc] initWithViewAnimations:animations] autorelease];
        [animation setDuration:0.1];
        [animation setAnimationBlockingMode:NSAnimationBlocking];
        [animation startAnimation];
    }
    
    // If we switched views, remove the old one so that our oldBottomView calculation above will be accurate next time.  Could add an ivar to track this and just let the view stay there hidden...
    if (oldBottomView != view)
        [oldBottomView removeFromSuperview];
    if (view) {
        NSView *keyView = [view nextKeyView];
        if (keyView)
            [window makeFirstResponder:keyView];
        else
            [window makeFirstResponder:window];
    }
}

- (void)_cancel;
{
    OBPRECONDITION(CurrentDownloadController == self || CurrentDownloadController == nil);
    
    if (CurrentDownloadController == self)
        CurrentDownloadController = nil;
    
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
    
    [_download release];
    _download = nil;
}

@end

