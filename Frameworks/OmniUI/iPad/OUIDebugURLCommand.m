// Copyright 2014-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDebugURLCommand.h>
#import <OmniUI/UIDevice-OUIExtensions.h>
#import <OmniUI/UIViewController-OUIExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <UniformTypeIdentifiers/UTCoreTypes.h>
@import OmniUnzip

RCS_ID("$Id$");

@interface OUIDebugURLCommand ()
// Radar 37952455: Regression: Spurious "implementing unavailable method" warning when subclassing
- (id)initWithURL:(NSURL *)url NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (NSString *)commandDescription NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (NSString *)confirmationMessage NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (NSString *)confirmButtonTitle NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
- (void)invoke NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
@end

@interface OUIDebugURLCommand (OmniFocusDebugMailDelegate) <MFMailComposeViewControllerDelegate>
@end


@implementation OUIDebugURLCommand {
@private
    SEL _sel;
    BOOL _hasCompletionHandler;
    NSString *_commandString;
    NSString *_parameterString;
}

- (id)initWithURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier;
{
    if (!(self = [super initWithURL:url senderBundleIdentifier:senderBundleIdentifier])) {
        return nil;
    }
    
    NSString *commandAndArguments = nil;
    
    NSString *path = [url path];
    if (path != nil) {
        commandAndArguments = [url query]; // omnifocus:///debug?set-default:EnableSyncDetailsLogging:1
    } else {
        commandAndArguments = [url resourceSpecifier]; // x-omnifocus-debug:set-default:EnableSyncDetailsLogging:1
    }
    
    NSRange parameterRange = [commandAndArguments rangeOfString:@":"];
    if (parameterRange.length > 0) {
        _parameterString = [commandAndArguments substringFromIndex:NSMaxRange(parameterRange)];
        _commandString = [commandAndArguments substringToIndex:parameterRange.location];
    } else {
        _commandString = commandAndArguments;
    }
    
    NSString *camelCommand = [[[_commandString componentsSeparatedByString:@"-"] arrayByPerformingSelector:@selector(capitalizedString)] componentsJoinedByString:@""];
    SEL selectorWithCompletionHandler = NSSelectorFromString([NSString stringWithFormat:@"command_%@_completionHandler:", camelCommand]);
    SEL selectorWithoutCompletionHandler = NSSelectorFromString([NSString stringWithFormat:@"command_%@", camelCommand]);
    if ([self respondsToSelector:selectorWithCompletionHandler]) {
        _hasCompletionHandler = YES;
        _sel = selectorWithCompletionHandler;
    } else if ([self respondsToSelector:selectorWithoutCompletionHandler]) {
        _sel = selectorWithoutCompletionHandler;
    } else {
#ifdef DEBUG
        NSLog(@"%@ does not respond to %@", NSStringFromClass([self class]), NSStringFromSelector(_sel));
#endif
        return nil;
    }

    return self;
}

- (NSArray *)parameters;
{
    NSArray *encodedParameters = [_parameterString componentsSeparatedByString:@":"];
    NSMutableArray *decodedParameters = [NSMutableArray array];
    for (NSString *encodedParameter in encodedParameters) {
        NSString *decodedParameter = [encodedParameter stringByRemovingPercentEncoding];
        [decodedParameters addObject:decodedParameter];
    }
    return decodedParameters;
}

- (NSString *)commandDescription;
{
    if (_parameterString != nil)
        return [NSString stringWithFormat:@"%@:%@", _commandString, _parameterString];
    else
        return _commandString;
}

- (NSString *)confirmationMessage;
{
    NSString *messageFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on a link which will run the following debugging command:\n\n\"%@\"\n\nIf you weren’t instructed to do this by Omni Support Humans, please don’t.\nDo you wish to run this command?", @"OmniUI", OMNI_BUNDLE, @"debug setting alert message");
    NSString *message = [NSString stringWithFormat:messageFormat, [self commandDescription]];
    return message;
}

- (NSString *)confirmButtonTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Invoke and Quit", @"OmniUI", OMNI_BUNDLE, @"button title");
}

- (void)invoke;
{
    typedef void (^InvokeCompletionBlock)(BOOL success);
    InvokeCompletionBlock completionBlock = ^void(BOOL success) {
        if (success) {
            // Successful debug commands quit and require relaunch.  Otherwise, they'd be much harder to implement and test.
            if ([self respondsToSelector:@selector(prepareForTermination)]) {
                [self prepareForTermination];
            }
            
            exit(0);
        } else {
            // Finish starting up if we postponed to handle the DEBUG url
            OUIAppController *controller = [OUIAppController controller];
            if (controller.shouldPostponeLaunchActions) {
                controller.shouldPostponeLaunchActions = NO;
            }
        }
    };

    if (_hasCompletionHandler) {
        void (*command)(id self, SEL _cmd, InvokeCompletionBlock completionBlock) = (typeof(command))[self methodForSelector:_sel];
        command(self, _cmd, completionBlock);
    } else {
        BOOL (*command)(id self, SEL _cmd) = (typeof(command))[self methodForSelector:_sel];
        BOOL success = command(self, _cmd);
        completionBlock(success);
    }
}

- (void)command_EmailDebugInfo_completionHandler:(void (^)(BOOL success))completion  NS_EXTENSION_UNAVAILABLE_IOS("sharedApplication is not available in extensions")
{
    NSString *address = [[NSBundle mainBundle] infoDictionary][@"OUIFeedbackAddress"];
    OBASSERT(address != nil);
    
    NSMutableString *body;
    {
        body = [NSMutableString string];
        
        // Only include generic info (not the device's name or uuid), though the user defaults will if they are syncing (since we cache client info).
        UIDevice *device = [UIDevice currentDevice];
        [body appendString:@"\n\nHardware:\n"];
        [body appendFormat:@"\tModel: %@\n", [device hardwareModel]];
        [body appendFormat:@"\tSystem: %@\n", [device systemName]];
        [body appendFormat:@"\tVersion: %@\n", [device systemVersion]];
        // TODO: Available disk space?
        
        [body appendFormat:@"\n\nDefaults:\n%@\n\n", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
        NSString *additionalAppInfo = [(OUIAppController *)[[UIApplication sharedApplication] delegate] appSpecificDebugInfo];
        if (additionalAppInfo.length > 0) {
            [body appendFormat:@"\n\n%@", additionalAppInfo];
        }
    }
    
    // TODO: While scanning the filesystem, collect "*.log" and then append them here?  They might be too bid to do in memory, though.
    NSString *subject;
    {
        NSString *appName = [[NSProcessInfo processInfo] processName];
        
        // TODO: These versions (and the date below) are approximate.  If the app crashed and the user installed and update, we'll be sending the NEW version for an old crash.
        NSString *bundleVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleVersionKey];
        OBASSERT(bundleVersion); // Configure your Info.plist correctly
        NSString *marketingVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)@"CFBundleShortVersionString"];
        OBASSERT(marketingVersion); // Configure your Info.plist correctly
        
        subject = [NSString stringWithFormat:@"Debug Info for %@ (%@, %@, %s)", appName, marketingVersion, bundleVersion, __DATE__];
    }
    
    MFMailComposeViewController *mailController = [(OUIAppController *)[[UIApplication sharedApplication] delegate] newMailComposeController];
    
    [mailController setSubject:subject];
    [mailController setMessageBody:body isHTML:NO];
    
    [[OUIAppController controller] addFilesToAppDebugInfoWithHandler:^(NSURL * _Nonnull url) {
            NSData *data = [NSData dataWithContentsOfURL:url];
            NSString *mimeType = [UTTypePlainText preferredMIMEType];
            [mailController addAttachmentData:data mimeType:mimeType fileName:url.path.lastPathComponent];
    }];
    
    [[OUIAppController controller] sendMailTo:@[address] withComposeController:mailController inScene:self.viewControllerForPresentation.containingScene];
}

- (BOOL)command_EmailReceipt NS_EXTENSION_UNAVAILABLE_IOS("This depends on UIApplication, which isn't available in application extensions");
{
    NSError *error = nil;
    NSArray *urls = @[ [[NSBundle mainBundle] appStoreReceiptURL] ];
    NSString *address = [[NSBundle mainBundle] infoDictionary][@"OUIFeedbackAddress"];
    NSString *appName = [[NSBundle mainBundle] infoDictionary][@"OUIApplicationName"];
    NSString *subject = [NSString stringWithFormat:@"%@ App Store receipt", appName];

    [self emailURLs:urls toAddress:address subject:subject error:&error];
    return NO; // Don't quit the app after running this command
}

- (BOOL)command_TestCrash;
{
    NSLog(@"Crash requested by %@", self.url.absoluteString);
    assert(0);
    return NO; // Don't quit the app if the crash doesn't actually crash
}

- (BOOL)command_TestBackgroundAlertPresentationInFiveSeconds NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    return [self _createAndPostDebugQueueAlertsInScene:self.viewControllerForPresentation.containingScene requiringPresentationInScene:NO];
}

- (BOOL)command_TestBackgroundAlertPresentationInFiveSecondsRequiringThisScene NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    return [self _createAndPostDebugQueueAlertsInScene:self.viewControllerForPresentation.containingScene requiringPresentationInScene:YES];
}

- (BOOL)_createAndPostDebugQueueAlertsInScene:(UIScene *)scene requiringPresentationInScene:(BOOL)requireGivenScene NS_EXTENSION_UNAVAILABLE_IOS("");
{
    OUIEnqueueableAlertController *controller1 = [OUIEnqueueableAlertController alertControllerWithTitle:@"Alert 1 of 4 (nil handler)" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [controller1 addActionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    
    OUIEnqueueableAlertController *controller2 = [OUIEnqueueableAlertController alertControllerWithTitle:@"Alert 2 of 4 (non-nil handler)" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [controller2 addActionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {}];
    
    OUIEnqueueableAlertController *controller3 = [OUIEnqueueableAlertController alertControllerWithTitle:@"Alert 3 of 4 (extended alert)" message:nil preferredStyle:UIAlertControllerStyleAlert];
    OUIExtendedAlertAction *extendedAction = [OUIExtendedAlertAction extendedActionWithTitle:@"Show intermediate alert for 3 seconds" style:UIAlertActionStyleDefault handler:^(OUIExtendedAlertAction * _Nonnull action) {
        UIAlertController *intermediateController = [UIAlertController alertControllerWithTitle:@"Intermediate" message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIViewController *presentingController = [[OUIAppController windowForScene:scene options:0] rootViewController];
        while (presentingController.presentedViewController != nil) {
            presentingController = presentingController.presentedViewController;
        }
        [presentingController presentViewController:intermediateController animated:YES completion:nil];
        OFAfterDelayPerformBlock(3, ^{
            [intermediateController dismissViewControllerAnimated:YES completion:^{
                [action extendedActionComplete];
            }];
        });
    }];
    [controller3 addExtendedAction:extendedAction];
    
    OUIEnqueueableAlertController *controller4 = [OUIEnqueueableAlertController alertControllerWithTitle:@"Alert 4 of 4 (nil handler, test complete)" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [controller4 addActionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    
    OFAfterDelayPerformBlock(5, ^{
        if (requireGivenScene) {
            [OUIAppController enqueueInteractionController:controller1 forPresentationInScene:scene withActivityContextTitle:@"Debug URL" activityContinuationButtonTitle:@"Continue in other scene" postponeActivityButtonTitle:@"Postpone"];
            [OUIAppController enqueueInteractionController:controller2 forPresentationInScene:scene withActivityContextTitle:@"Debug URL" activityContinuationButtonTitle:@"Continue in other scene" postponeActivityButtonTitle:@"Postpone"];
            [OUIAppController enqueueInteractionController:controller3 forPresentationInScene:scene withActivityContextTitle:@"Debug URL" activityContinuationButtonTitle:@"Continue in other scene" postponeActivityButtonTitle:@"Postpone"];
            [OUIAppController enqueueInteractionController:controller4 forPresentationInScene:scene withActivityContextTitle:@"Debug URL" activityContinuationButtonTitle:@"Continue in other scene" postponeActivityButtonTitle:@"Postpone"];
        } else {
            [OUIAppController enqueueInteractionControllerPresentationForAnyForegroundScene:controller1];
            [OUIAppController enqueueInteractionControllerPresentationForAnyForegroundScene:controller2];
            [OUIAppController enqueueInteractionControllerPresentationForAnyForegroundScene:controller3];
            [OUIAppController enqueueInteractionControllerPresentationForAnyForegroundScene:controller4];
        }
    });
    
    // No need to quit the app after running this command
    return NO;
}

- (BOOL)emailURLs:(NSArray *)URLs toAddress:(NSString *)address subject:(NSString *)subject error:(NSError **)outError;
{
    NSString *appName = [[NSBundle mainBundle] infoDictionary][@"OUIApplicationName"];
    NSString *zipName = [NSString stringWithFormat:@"%@Data.zip", appName];
    NSString *zipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:zipName];

    BOOL success = NO;
    NSError *strongError = nil;
    @autoreleasepool {
        __autoreleasing NSError *error;
        success = [self _createZipFile:zipPath fromURLs:URLs includingFailureList:YES error:&error];
        if (!success) {
            strongError = error; // keep the error alive
        }
    };

    if (!success) {
        if (outError != NULL) {
            *outError = strongError; // propagate the error upwards
        }
        return NO;
    }

    NSData *zipData = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:zipPath] options:NSDataReadingMappedIfSafe error:outError];
    if (zipData == nil) {
        return NO;
    }

    if ([MFMailComposeViewController canSendMail]) {
        OUIAppController *appController = (OUIAppController *)[[UIApplication sharedApplication] delegate];
        MFMailComposeViewController *controller = [appController newMailComposeController];


        /* Seems like we don't need this anymore if we let the appController wrangle the mailComposeController?
        // <bug:///115661> (Bug: Mail Controller's buttons are unresponsive or OF crashes after using omnifocus:///debug?send-database URL)
        // Strong-retain this command so that the MFMailComposeViewController can send delegate messages to it even after the command is done being invoked. This is unbalanced, because we expect the app to be terminated shortly; even if it's not, we'll only leak a tiny little bit of data, and the associated compose controller should disappear so we won't get too many delegate messages.
        controller.mailComposeDelegate = self;
        OBStrongRetain(self);
         */

        [controller setToRecipients:[NSArray arrayWithObject:address]];
        [controller setSubject:subject];
        [controller addAttachmentData:zipData mimeType:@"application/zip" fileName:[zipPath lastPathComponent]];
        [appController sendMailTo:@[address] withComposeController:controller inScene:nil];
    } else {
        NSString *title = NSLocalizedStringFromTableInBundle(@"Cannot Email Diagnostics", @"OmniUI", OMNI_BUNDLE, @"alert title");
        NSString *message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Mail has not been set up on this %@.",@"OmniUI", OMNI_BUNDLE, @"message format"), [[UIDevice currentDevice] model]];
        [self presentAlertWithTitle: title message:message terminateOnCompletion:YES];
        return NO;
    }

    return NO;
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message terminateOnCompletion:(BOOL)terminate;
{
    NSString *quitLabel = NSLocalizedStringFromTableInBundle(@"Quit", @"OmniUI", OMNI_BUNDLE, @"button title");
    NSString *buttonLabel = terminate ? quitLabel : @"OK";
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:buttonLabel style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (terminate) {
            [self prepareForTermination];
            exit(0);
        }
    }]];
    [self.viewControllerForPresentation presentViewController:alertController animated:YES completion:nil];
}


/*!
 Create a zip archive containing the files at as many of the specified URLs as possible.

 @param zipPath The path at which to create the resulting zip archive.
 @param URLs A list of URLs specifying files to include in the zip archive, if possible. This array must contain all NSURL instances, and each NSURL instance must be a file URL.
 @param includeFailureList Whether to write a text file into the zip archive listing all of the files that could not be added to the archive for any reason. If YES, the zip archive will always include at least one file named "failures.log" which will list each failed path on its own line.
 @param outError If the method returns NO, will be populated with more information about the failure.
 @return YES if the zip archive could be created at all, regardless of how many files were actually compressed. NO otherwise.
 */
- (BOOL)_createZipFile:(NSString *)zipPath fromURLs:(NSArray *)URLs includingFailureList:(BOOL)includeFailureList error:(NSError **)outError;
{
    OUZipArchive *zip = [[OUZipArchive alloc] initWithPath:zipPath error:outError];
    if (!zip) {
        OBASSERT(outError == NULL || *outError != nil);
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray <NSString *> *failureMessages = [NSMutableArray array];

    for (NSURL *URL in URLs) {
        OBASSERT([URL isFileURL]);
        NSString *path = URL.path;
        NSError *error = nil;

        OUZipMember *zipMember = [[OUZipMember alloc] initWithPath:path fileManager:fileManager outError:&error];
        if (zipMember == nil) {
            [failureMessages addObject:[NSString stringWithFormat:@"Unable to open file %@: %@", path, [error toPropertyList]]];
            continue;
        }

        if (![zipMember appendToZipArchive:zip fileNamePrefix:@"" error:&error]) {
            // Unable to add one of the files to the zip archive.  Just skipping it for now.
            [failureMessages addObject:[NSString stringWithFormat:@"Unable to append file %@: %@", path, [error toPropertyList]]];
        }
    }

    if ([failureMessages count] > 0) {
        NSString *contents = [failureMessages componentsJoinedByString:@"\n"];
        OUZipMember *failuresMember = [[OUZipFileMember alloc] initWithName:@"failures.log" date:[NSDate date] contents:[contents dataUsingEncoding:NSUTF8StringEncoding]];
        NSError *error = nil;
        if (![failuresMember appendToZipArchive:zip fileNamePrefix:@"" error:&error]) {
            // Couldn't even add the failure log to the zip archive? Something is seriously wrong.
            NSLog(@"Unable to add failures.log to %@: %@\nFailures:\n%@", zipPath, [error toPropertyList], contents);
        }
    }

    return [zip close:outError];
}

- (void)prepareForTermination;
{
    // Subclasses might have something to do here.
}


@end
