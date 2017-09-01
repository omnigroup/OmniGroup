// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDebugURLCommand.h>
#import <OmniUI/UIDevice-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIDebugURLCommand {
@private
    SEL _sel;
    BOOL _hasCompletionHandler;
    NSString *_commandString;
    NSString *_parameterString;
}

- (id)initWithURL:(NSURL *)url;
{
    if (!(self = [super initWithURL:url])) {
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
            controller.shouldPostponeLaunchActions = NO;
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
    
    MFMailComposeViewController *mailController = [(OUIAppController *)[[UIApplication sharedApplication] delegate] mailComposeController];
    
    [mailController setSubject:subject];
    [mailController setMessageBody:body isHTML:NO];
    [(OUIAppController *)[[UIApplication sharedApplication] delegate] sendMailTo:@[address] withComposeController:mailController];
}

@end
