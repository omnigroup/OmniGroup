// Copyright 2007-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUDownloadController.h>

#import "OSUErrors.h"
#import "OSUInstaller.h"
#import "OSUItem.h"
#import "OSUSendFeedbackErrorRecovery.h"
#import <OmniSoftwareUpdate/OSUPreferences.h>

#import <AppKit/AppKit.h>

#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniAppKit/NSTextField-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAConstraintBasedStackView.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

#ifdef DEBUG
static NSString *OSUInstallationDirectoryOverride = nil;
#endif

static BOOL OSUDebugDownload = YES;
#define DEBUG_DOWNLOAD(format, ...) \
do { \
    if (OSUDebugDownload) \
    NSLog((format), ## __VA_ARGS__); \
} while(0)

RCS_ID("$Id$");

static OSUDownloadController *CurrentDownloadController = nil;

@interface OSUDownloadController () <OSUInstallerDelegate, NSURLSessionDownloadDelegate>
{
    NSURL *_packageURL;
    OSUItem *_item;
    NSURLRequest *_request;
    NSURLSession *_session;
    NSURLSessionDownloadTask *_downloadTask;

    void (^_challengeCompletionHandler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential);

    BOOL _showCautionText;  // Usually describing a verification failure
    BOOL _displayingInstallView;
    
    NSURL *_downloadedURL;
}

@property (nonatomic, retain) IBOutlet OAConstraintBasedStackView *contentView;

// These are the toplevel views we might display in the contentView.
@property (nonatomic, retain) IBOutlet NSView *downloadProgressView;
@property (nonatomic, retain) IBOutlet NSView *installProgressView;

// These are the views we might display in the downloadProgressView
@property (nonatomic, retain) IBOutlet NSView *credentialsView;

// These are the views we might display in the installView
@property (nonatomic, retain) IBOutlet NSView *installBasicView;
@property (nonatomic, retain) IBOutlet NSView *installOptionsNoteView;
@property (nonatomic, retain) IBOutlet NSView *installWarningView;
@property (nonatomic, retain) IBOutlet NSView *installButtonsView;

@property (nonatomic, retain) IBOutlet NSTextField *installViewMessageText;
@property (nonatomic, retain) IBOutlet NSImageView *installViewCautionImageView;
@property (nonatomic, retain) IBOutlet NSTextField *installViewCautionText;
@property (nonatomic, retain) IBOutlet NSButton *installViewInstallButton;

@property (nonatomic, copy) NSString *installationDirectory;
@property (nonatomic, copy) NSAttributedString *installationDirectoryNote;

@property (nonatomic, copy) NSString *status;

@property (nonatomic, copy) NSString *userName;
@property (nonatomic, copy) NSString *password;
@property (nonatomic) BOOL rememberInKeychain;

@property (nonatomic) off_t currentBytesDownloaded;
@property (nonatomic) off_t totalSize;

// Installer bookkeeping
@property (nonatomic, retain) OSUInstaller *installer;

@end

@implementation OSUDownloadController

+ (void)initialize;
{
    OBINITIALIZE;
    
    OSUDebugDownload = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUDebugDownload"];
#ifdef DEBUG
    OSUInstallationDirectoryOverride = [[NSUserDefaults standardUserDefaults] stringForKey:@"OSUInstallationDirectoryOverride"];
#endif
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
        return nil;
    }

    // Display a 'connecting' view here until we know whether we are going to be asked for credentials or not (and to allow cancelling).
    
    _rememberInKeychain = NO;
    _packageURL = [packageURL copy];
    _request = [NSURLRequest requestWithURL:packageURL];
    _item = item;
    _showCautionText = NO;

    [self setInstallationDirectory:[OSUInstaller suggestAnotherInstallationDirectory:nil trySelf:YES]];
    [self showWindow:nil];
    
    void (^startDownload)(void) = ^{
        // This starts the download
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];

        _downloadTask = [_session downloadTaskWithRequest:_request];
        [_downloadTask resume];
    };

    __autoreleasing NSError *validateError = nil;
    if (self.installationDirectory == nil || ![OSUInstaller validateTargetFilesystem:self.installationDirectory error:&validateError]) {
        // We should only have to prompt the user to pick a directory if both the application's directory and /Applications on the root filesystem both live on read-only filesystems.
        [OSUInstaller chooseInstallationDirectory:self.installationDirectory modalForWindow:self.window completionHandler:^(NSError *error, NSString *result) {
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
   
    OBASSERT(_session == nil);
    OBASSERT(_downloadTask == nil);
    OBASSERT(_challengeCompletionHandler == nil);
    OBASSERT(_request == nil);
    OBASSERT(CurrentDownloadController != self); // cleared in _cancel
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
    
    OBASSERT([self.contentView window] == [self window]);
    
    OBASSERT([self.installViewCautionText superview] == self.installWarningView);
    OBASSERT([self.installViewInstallButton superview] == self.installButtonsView);
    OBASSERT([self.installViewMessageText superview] == self.installBasicView);
    
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSString *name = [[[_request URL] path] lastPathComponent];
    [self setStatus:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Downloading %@ \\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download status - text is filename of update package being downloaded"), name]];
    
    [self.installViewCautionText setStringValue:@"---"];
    [self _setDisplayedView:self.downloadProgressView];
    [self.window layoutIfNeeded];
    
    NSString *appDisplayName = [[NSProcessInfo processInfo] processName];
    [[self window] setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ Update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download window title - text is name of the running application"), appDisplayName]];
    
    NSString *basicText = [self.installViewMessageText stringValue];
     basicText = [basicText stringByReplacingOccurrencesOfString:@"%@" withString:appDisplayName];
    [self.installViewMessageText setStringValue:basicText];
    
    [self _adjustProgressIndicatorAttributesInSubtreeForView:self.downloadProgressView];
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
    OBPRECONDITION(_challengeCompletionHandler);

    // We aren't a NSController, so we need to commit the editing...
    NSWindow *window = [self window];
    [window makeFirstResponder:window];

    if (_challengeCompletionHandler) {
        NSURLCredential *credential = [[NSURLCredential alloc] initWithUser:self.userName password:self.password persistence:(self.rememberInKeychain ? NSURLCredentialPersistencePermanent : NSURLCredentialPersistenceForSession)];

        typeof(_challengeCompletionHandler) handler = [_challengeCompletionHandler copy];
        OBRetainAutorelease(handler);
        _challengeCompletionHandler = nil;

        handler(NSURLSessionAuthChallengeUseCredential, credential);
    }

    // Switch views so that if we get another credential failure, the user sees that we *tried* to use what they gave us, but failed again.
    [self _setDisplayedView:self.downloadProgressView];
}

- (IBAction)installAndRelaunch:(id)sender;
{
    OBPRECONDITION(self.installer == nil);
    if (self.installer != nil) {
        return;
    }

    // OSUInstaller will either fail during decode & preflight, and ask us to close and leave us running, or complete (either successfully, or by posting an error and quitting.)
    // In the later case, *it* is responsible for initiating the application termination sequence.

    OSUInstaller *installer = [[OSUInstaller alloc] initWithPackagePath:[[_downloadedURL absoluteURL] path]];
    
    installer.delegate = self;
    installer.installedVersionPath = [[NSBundle mainBundle] bundlePath];
    
    if (self.installationDirectory != nil)
        installer.installationDirectory = self.installationDirectory;
    
    self.installer = installer;
    
    [self _setDisplayedView:self.installProgressView];
    [installer run];
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
    return self.totalSize != 0ULL;
}

+ (NSSet *)keyPathsForValuesAffectingIsInstalling;
{
    return [NSSet setWithObject:@"installer"];
}

- (BOOL)isInstalling;
{
    return (self.installer != nil);
}

- (void)setStatus:(NSString *)status
{
    if (status != _status) {
        _status = [status copy];
        
        [[self window] displayIfNeeded];
    }
}

- (void)setInstallationDirectory:(NSString *)installationDirectory
{
#ifdef DEBUG
    if (OSUInstallationDirectoryOverride != nil) {
        installationDirectory = OSUInstallationDirectoryOverride;
    }
#endif
    
    if (OFISEQUAL(_installationDirectory, installationDirectory))
        return;
    
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
        }
        
        [infix addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:fontSize] range:(NSRange){0, [infix length]}];
        
        NSMutableAttributedString *message = [[NSMutableAttributedString alloc] initWithString:noteTemplate attributes:[NSDictionary dictionaryWithObject:[NSFont messageFontOfSize:fontSize] forKey:NSFontAttributeName]];
        [message replaceCharactersInRange:[noteTemplate rangeOfString:@"@"] withAttributedString:infix];
        
        self.installationDirectoryNote = message;
    } else {
        self.installationDirectoryNote = nil;
    }
    
    if (_displayingInstallView) {
        [self queueSelectorOnce:@selector(_setInstallViews)];
    }
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler;
{
    DEBUG_DOWNLOAD(@"will send redirect request %@", request);
    completionHandler(request);
}

#pragma mark - NSURLSessionDelegate delegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler;
{
    [self _handleAuthenticationChallenge:challenge completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
{
    self.totalSize = totalBytesExpectedToWrite;
    self.currentBytesDownloaded = totalBytesWritten;
}

+ (void)_quarantineDownloadAtURL:(NSURL *)downloadURL requestURL:(NSURL *)requestURL item:(OSUItem *)item;
{
    DEBUG_DOWNLOAD(@"_quarantineDownloadAtURL %@", downloadURL);
    
    // Quarantine the file. Later, after we verify its checksum, we can remove the quarantine.
    __autoreleasing NSError *qError = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm quarantinePropertiesForItemAtURL:downloadURL error:&qError] != nil) {
        // It already has a quarantine (presumably we're running with LSFileQuarantineEnabled in our Info.plist)
        // And apparently it's not possible to change the parameters of an existing quarantine event
        // So just assume that NSURLDownload did something that was good enough
    } else {
        if ( !([[qError domain] isEqualToString:NSOSStatusErrorDomain] && [qError code] == unimpErr) ) {
            
            NSMutableDictionary *qua = [NSMutableDictionary dictionary];
            [qua setObject:(id)kLSQuarantineTypeOtherDownload forKey:(id)kLSQuarantineTypeKey];
            [qua setObject:requestURL forKey:(id)kLSQuarantineDataURLKey];
            NSString *fromWhere = [item sourceLocation];
            if (fromWhere) {
                NSURL *parsed = [NSURL URLWithString:fromWhere];
                if (parsed)
                    [qua setObject:parsed forKey:(id)kLSQuarantineOriginURLKey];
            }
            
            [fm setQuarantineProperties:qua forItemAtURL:downloadURL error:NULL];
        }
    }
}

+ (NSURL *)_storeDownloadURL:(NSURL *)downloadURL originalRequestURL:(NSURL *)originalRequestURL error:(NSError **)outError;
{
    DEBUG_DOWNLOAD(@"_storeDownloadURL %@", downloadURL);

    NSFileManager *manager = [NSFileManager defaultManager];

    NSURL *cacheDirectoryURL = [manager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:downloadURL create:YES error:outError];
    if (!cacheDirectoryURL) {
        return nil;
    }

    cacheDirectoryURL = [cacheDirectoryURL URLByAppendingPathComponent:[OMNI_BUNDLE bundleIdentifier] isDirectory:YES];
    if (![manager createDirectoryAtURL:cacheDirectoryURL withIntermediateDirectories:YES attributes:nil error:outError]) {
        return nil;
    }

    // When we used to use NSURLDownload, on some people's machines, we'll end up with foo.tbz2.bz2 as the suggested name.  This is not good; it seems to come from having a 3rd party utility instaled that handles bz2 files, registering a set of UTIs that convinces NSURLDownload to suggest the more accurate extension. So, we ignore the suggestion and use the filename from the URL.

    NSString *originalFileName = [originalRequestURL lastPathComponent];
    OBASSERT([[OSUInstaller supportedPackageFormats] containsObject:[originalFileName pathExtension]]);

    NSURL *destinationURL = [cacheDirectoryURL URLByAppendingPathComponent:originalFileName];

    // NSFileManager won't remove a previous download, if there is one (maybe the user downloaded the package, and then terminated the app before installing or cancelling).
    __autoreleasing NSError *removeError = nil;
    if (![manager removeItemAtURL:destinationURL error:&removeError]) {
        if (![removeError causedByMissingFile]) {
            if (outError)
                *outError = removeError;
            return nil;
        }
    }

    DEBUG_DOWNLOAD(@"  destination: %@", destinationURL);
    if (![manager moveItemAtURL:downloadURL toURL:destinationURL error:outError])
        return nil;
    return destinationURL;
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location;
{
    // The passed in URL will be somewhere in $TMPDIR and will removed after this method returns, so we have to move/save it (and we don't need to clean it up on error).
    [[self class] _quarantineDownloadAtURL:location requestURL:downloadTask.currentRequest.URL item:_item];

    __autoreleasing NSError *error = nil;
    _downloadedURL = [[self class] _storeDownloadURL:location originalRequestURL:downloadTask.originalRequest.URL error:&error];
    if (!_downloadedURL) {
        [[self window] presentError:error];
        return;
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error;
{
    if (!error) {
        OBASSERT(_downloadedURL);

        // TODO: Perform verification on a background queue and leave the UI disabled until that is done?
        [self setStatus:NSLocalizedStringFromTableInBundle(@"Verifying file\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download status")];
        NSString *caution = [_item verifyFile:[[_downloadedURL absoluteURL] path]];
        if (![NSString isEmptyString:caution]) {
            [self.installViewCautionText setStringValue:caution];
            _showCautionText = YES;
        }

        [self setStatus:NSLocalizedStringFromTableInBundle(@"Ready to Install", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Download status - Done downloading, about to prompt the user to let us reinstall and restart the app")];

        if (![[NSApplication sharedApplication] isActive])
            [[NSApplication sharedApplication] requestUserAttention:NSInformationalRequest];
        else
            [self showWindow:nil];
        
        [self _setInstallViews];

        return;
    }

    DEBUG_DOWNLOAD(@"didFailWithError %@", error);

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
    

    NSString *errorSuggestion;
    
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

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler;
{
    // We seem to get this for authenticated feeds, at least in some cases
    [self _handleAuthenticationChallenge:challenge completionHandler:completionHandler];
}

#pragma mark - Private

- (void)_handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler;
{
    OBPRECONDITION(completionHandler); // Not using the challenge's -sender to reply
    
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
    
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    if ([[protectionSpace authenticationMethod] isEqual:NSURLAuthenticationMethodServerTrust]) {
        // If we "continue without credential", NSURLConnection will consult certificate trust roots and per-cert trust overrides in the normal way. If we cancel the "challenge", NSURLConnection will drop the connection, even if it would have succeeded without our meddling (that is, we can force failure as well as forcing success).
        if (completionHandler) {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
        //[[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
        return;
    }
    
    DEBUG_DOWNLOAD(@"previousFailureCount = %ld", [challenge previousFailureCount]);
    NSURLCredential *proposed = [challenge proposedCredential];
    DEBUG_DOWNLOAD(@"proposed = %@", proposed);
    
    if ([challenge previousFailureCount] == 0 && (proposed != nil) && ![NSString isEmptyString:[proposed user]] && ![NSString isEmptyString:[proposed password]]) {
        // Try the proposed credentials, if any, the first time around.  I've gotten a non-nil proposal with a null user name on 10.4 before.
        completionHandler(NSURLSessionAuthChallengeUseCredential, proposed);
        return;
    }
    
    // If we somehow had a pending challenge, answer it negatively...
    if (_challengeCompletionHandler) {
        OBASSERT_NOT_REACHED("Not planning on having two oustanding challenged... how are we getting here?");
        _challengeCompletionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        _challengeCompletionHandler = nil;
    }
    _challengeCompletionHandler = [completionHandler copy];
    
    [self _setDisplayedView:self.credentialsView];
    [self showWindow:nil];
    [[NSApplication sharedApplication] requestUserAttention:NSInformationalRequest]; // Let the user know they need to interact with us (else the server will timeout waiting for authentication).
}

- (void)_adjustProgressIndicatorAttributesInSubtreeForView:(NSView *)view;
{
    for (NSView *subview in view.subviews) {
        [self _adjustProgressIndicatorAttributesInSubtreeForView:subview];
        
        // Threaded animation doesn't play nicely with our blocking animation; it causes visual glitches.
        // Probably should move off of blocking animation, but easier to just turn this off for now.
        if ([subview isKindOfClass:[NSProgressIndicator class]]) {
            NSProgressIndicator *progressIndicator = (NSProgressIndicator *)subview;
            [progressIndicator setUsesThreadedAnimation:NO];
        }
    }
}

- (void)_setInstallViews;
{
    NSMutableArray *installViews = [NSMutableArray array];

    [installViews addObject:self.installBasicView];
    
    if (self.installationDirectoryNote != nil) {
        [installViews addObject:self.installOptionsNoteView];
    }
    
    if (_showCautionText) {
        [installViews addObject:self.installWarningView];
        [self.installViewCautionImageView setImage:[NSImage imageNamed:NSImageNameCaution]];
    }

    [installViews addObject:self.installButtonsView];

    _displayingInstallView = YES;
    [self setContentViews:installViews];
}

- (void)_setDisplayedView:(NSView *)aView;
{
    _displayingInstallView = NO;
    [self setContentViews:(aView != nil ? [NSArray arrayWithObject:aView] : nil)];
}

- (void)setContentViews:(NSArray *)newContent;
{
    NSWindow *window = [self window];
    [self.contentView crossfadeToViews:newContent completionBlock:^{
        // Update up the key view loop and first responder if appropriate
        [window recalculateKeyViewLoop];
        
        NSView *nextValidKeyView = [[newContent firstObject] nextValidKeyView];
        BOOL shouldAdjustFirstResponder = [window firstResponder] == nil || [window firstResponder] == window;
        if (shouldAdjustFirstResponder && nextValidKeyView != nil) {
            [window makeFirstResponder:nextValidKeyView];
        }
    }];
}

- (void)_cancel;
{
    OBPRECONDITION(CurrentDownloadController == self || CurrentDownloadController == nil);
    
    if (CurrentDownloadController == self) {
        OBRetainAutorelease(self); // Don't get deallocated immediately
        CurrentDownloadController = nil;
    }

    if (_challengeCompletionHandler) {
        _challengeCompletionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        _challengeCompletionHandler = nil;
    }

    // If we are explictly cancelling, delete the file
    if (_downloadedURL) {
        [[NSFileManager defaultManager] removeItemAtURL:_downloadedURL error:NULL];
        _downloadedURL = nil;
    }

    _request = nil;

    [_downloadTask cancel];
    _downloadTask = nil;
}

@end

