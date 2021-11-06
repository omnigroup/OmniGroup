// Copyright 2002-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAScriptToolbarHelper.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#if defined(MAC_OS_VERSION_11_0) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSToolbar-OAExtensions.h>
#import <OmniAppKit/NSFileManager-OAExtensions.h>
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAToolbarItem.h>
#import <OmniAppKit/OAStrings.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

typedef void (^_RunItemCompletionHandler)(OAToolbarItem *toolbarItem, NSError *error);

@implementation OAScriptToolbarHelper {
  @private
    NSMutableDictionary *_pathForItemDictionary;
}

static BOOL OAScriptToolbarItemsDisabled = NO;

+ (void)setDisabled:(BOOL)disabled;
{
    OAScriptToolbarItemsDisabled = disabled;
}

- (id)init;
{
    if (!(self = [super init]))
        return nil;

    _pathForItemDictionary = [[NSMutableDictionary alloc] init];

    return self;
}

- (NSString *)itemIdentifierExtension;
{
    return @"osascript";
}

- (NSString *)templateItemIdentifier;
{
    return @"OSAScriptTemplate";
}

- (NSArray *)scriptPaths;
{
    BOOL isSandboxed = [[NSProcessInfo processInfo] isSandboxed];
    
    // Applications running on 10.8 and later have access to NSUserScriptTask.
    // Sandboxed applications can only execute items from NSApplicationScriptsDirectory.
    
    if (isSandboxed) {
        NSURL *applicationScriptsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationScriptsDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
        if (applicationScriptsDirectoryURL != nil && [applicationScriptsDirectoryURL checkResourceIsReachableAndReturnError:NULL]) {
            return [NSArray arrayWithObject:[applicationScriptsDirectoryURL path]];
        }
        
        return [NSArray array];
    }
    
    // Unsandboxed applications can execute scripts or workflows from any of the standard locations.

    NSMutableArray *scriptPaths = [NSMutableArray array];
    NSString *applicationSupportDirectoryName = [[OAApplication sharedApplication] applicationSupportDirectoryName];
    NSArray *libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask & ~(NSSystemDomainMask), YES);
    for (NSString *libraryDirectory in libraryDirectories) {
        NSString *scriptDirectory = [libraryDirectory stringByAppendingPathComponent:@"Scripts"];
        scriptDirectory = [scriptDirectory stringByAppendingPathComponent:@"Applications"];
        scriptDirectory = [scriptDirectory stringByAppendingPathComponent:applicationSupportDirectoryName];
        [scriptPaths addObject:scriptDirectory];
    }

    NSString *bundledScriptsPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Scripts"];
    [scriptPaths addObject:bundledScriptsPath];
    
    return scriptPaths;
}

- (NSArray *)allowedItems;
{
    [self _scanItems];
    return [_pathForItemDictionary allKeys];
}

- (NSString *)pathForItem:(NSToolbarItem *)item;
{
    [self _scanItems];
    return [_pathForItemDictionary objectForKey:[item itemIdentifier]];
}

- (nullable OAToolbarItem *)finishSetupForToolbarItem:(OAToolbarItem *)toolbarItem toolbar:(NSToolbar *)toolbar willBeInsertedIntoToolbar:(BOOL)willInsert;
{
    if (OAScriptToolbarItemsDisabled)
        return nil;

    // <bug:///89032> (Update OAScriptToolbarHelper to use non-deprecated API)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSString *path = [self pathForItem:toolbarItem];
    if (path == nil) {
        return nil;
    }
    
    path = [path stringByExpandingTildeInPath];

    [toolbarItem setTarget:self];
    [toolbarItem setAction:@selector(executeScriptItem:)];

    NSString *typename = [[NSWorkspace sharedWorkspace] typeOfFile:path error:NULL];
    OBASSERT_NOTNULL(typename);
    BOOL isAutomatorWorfklow = [[NSWorkspace sharedWorkspace] type:typename conformsToType:@"com.apple.automator-workflow"];

    if (isAutomatorWorfklow) {
        OAToolbarWindowController *windowController = (OAToolbarWindowController *)[toolbar delegate];
        OBASSERT([windowController isKindOfClass:[OAToolbarWindowController class]]);
        NSDictionary *localizedToolbarInfo = [windowController localizedToolbarInfoForItem:@"AutomatorWorkflowTemplate"];
        OBASSERT(localizedToolbarInfo != nil);
        NSArray *keys = @[@"label", @"paletteLabel", @"toolTip"];
        for (NSString *key in keys) {
            NSString *format = [localizedToolbarInfo objectForKey:key];
            if (format == nil) {
                OBASSERT_NOT_REACHED("window controller %@ returned info dictionary that was missing a format for the key \"%@\".", windowController, key);
                continue;
            }
            NSString *value = [NSString stringWithFormat:format, [self _stringByRemovingScriptFilenameExtension:[path lastPathComponent]]];
            [toolbarItem setValue:value forKey:key];
        }
    } else {
        [toolbarItem setLabel:[self _stringByRemovingScriptFilenameExtension:[toolbarItem label]]];
        [toolbarItem setPaletteLabel:[self _stringByRemovingScriptFilenameExtension:[toolbarItem paletteLabel]]];
        [toolbarItem setToolTip:[self _stringByRemovingScriptFilenameExtension:[toolbarItem toolTip]]];
    }
    
    NSImage *customImage = [NSImage customImageForFile:path];
    if (customImage) {
        NSView *view = toolbarItem.view;
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            button.imageScaling = NSImageScaleProportionallyDown;
            button.image = customImage;
        } else {
            [toolbarItem setImage:customImage];
        }
    } else {
        NSString *imageName;

        if (isAutomatorWorfklow) {
            imageName = @"AutomatorWorkflow";
        } else {
            imageName = @"Script";
        }

        if ([NSColor currentControlTint] == NSGraphiteControlTint) {
            imageName = [imageName stringByAppendingString:@"-Graphite"];
        }

        [toolbarItem setImage:[NSImage imageNamed:imageName inBundle:OMNI_BUNDLE]];
    }
#pragma clang diagnostic pop

    return toolbarItem;
}

- (Class)toolbarItemButtonClass;
{
    return [OAUserSuppliedImageToolbarItemButton class];
}

- (void)executeScriptItem:(id)sender;
{
    OBRetainAutorelease(sender);
    OAToolbarItem *toolbarItem = nil;
    
    if ([sender isKindOfClass:[OAToolbarItem class]]) {
        toolbarItem = sender;
    } else if ([sender isKindOfClass:[OAToolbarItemButton class]]) {
        toolbarItem = [sender toolbarItem];
    } else {
        OBASSERT_NOT_REACHED("Unexpected sender class.");
        NSBeep();
        return;
    }

    OAToolbarWindowController *windowController = OB_CHECKED_CAST_OR_NIL(OAToolbarWindowController, [[toolbarItem toolbar] delegate]);
    if (windowController == nil) {
        OBASSERT_NOT_REACHED("How are we activating a script toolbar item w/o a window controller?");
        return;
    }

    OBRetainAutorelease(windowController);  // The script may cause the window to be closed
    if ([windowController respondsToSelector:@selector(scriptToolbarItemShouldExecute:)] && ![windowController scriptToolbarItemShouldExecute:sender]) {
	return;
    }

    _RunItemCompletionHandler completionHandler = ^(OAToolbarItem *toolbarItem_, NSError *error) {
	if ([windowController respondsToSelector:@selector(scriptToolbarItemFinishedExecuting:)]) {
	    [windowController scriptToolbarItemFinishedExecuting:toolbarItem_];
        }
    };
    
    NSString *itemPath = [[self pathForItem:toolbarItem] stringByExpandingTildeInPath];
    if (!itemPath) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedStringFromTableInBundle(@"Script Not Found", @"OmniAppKit", OMNI_BUNDLE, @"error title when a script is missing");

        alert.informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No script found for the toolbar item with identifier \"%@\".", @"OmniAppKit", OMNI_BUNDLE, @"error message when a script is missing"), toolbarItem.itemIdentifier];

        [alert beginSheetModalForWindow:windowController.window completionHandler:nil];
        return;
    }

    UTType *itemType = nil;
    if (![[NSURL fileURLWithPath:itemPath] getResourceValue:&itemType forKey:NSURLContentTypeKey error:NULL]) {
        // Ignore the error; we'll treat this as a script rather than an Automator workflow.
    }

    // This code only supports 10.8 and later so we always use the sandbox savvy APIs, since they also support unsandboxed applications.
    //
    // This also avoids having to deal with new potentially false positive nullability warnings from OSAKit, which still lacks API documentation.

    BOOL conformsToAutomator = [itemType conformsToType:[UTType typeWithIdentifier:@"com.apple.automator-workflow"]];
    if (conformsToAutomator) {
        [self _executeAutomatorWorkflowForToolbarItem:toolbarItem inWindowController:windowController completionHandler:completionHandler];
    } else {
        [self _executeOSAScriptForToolbarItem:toolbarItem inWindowController:windowController completionHandler:completionHandler];
    }
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem;
{
    return !OAScriptToolbarItemsDisabled;
}

#pragma mark -
#pragma mark Private

- (void)_scanItems;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray <UTType *> *scriptTypes = [self _scriptTypes];
    
    // Remove all existing items before rescanning
    [_pathForItemDictionary removeAllObjects];
    
    for (NSString *scriptFolder in [self scriptPaths]) {
        for (NSString *filename in [fileManager directoryContentsAtPath:scriptFolder ofTypes:scriptTypes deep:NO fullPath:NO error:NULL]) {
	    // Don't register more than one script with the same name.
            // This means you won't be able to have toolbar items of different script types with the same name.
            NSString *itemName = [self _stringByRemovingScriptFilenameExtension:filename];
            NSString *itemIdentifier = [itemName stringByAppendingPathExtension:[self itemIdentifierExtension]];
            if ([_pathForItemDictionary objectForKey:itemIdentifier] == nil) {
                NSString *path = [[scriptFolder stringByAppendingPathComponent:filename] stringByAbbreviatingWithTildeInPath];
                [_pathForItemDictionary setObject:path forKey:itemIdentifier];
            }
        }
    }
}

- (NSArray <UTType *> *)_scriptTypes;
{
    static NSArray *scriptTypes = nil;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        // Note that text scripts and compiled scripts do not conform to each other.
        NSMutableArray *result = [NSMutableArray array];
        NSArray <NSString *> *typeIdentifiers = @[@"com.apple.applescript.text", @"com.apple.applescript.script", @"com.apple.applescript.script-bundle", @"com.apple.automator-workflow"];
        [result addObjectsFromArray:[typeIdentifiers arrayByPerformingBlock:^UTType * _Nonnull(NSString *identifier) {
            return [UTType typeWithIdentifier:identifier];
        }]];
        scriptTypes = [result copy];
    });
    
    return scriptTypes;
}

- (NSArray <NSString *> *)_scriptFilenameExtensions;
{
    static NSArray *scriptFilenameExtensions = @[
        @"workflow", @"applescript", @"scptd", @"scpt",
    ];

    return scriptFilenameExtensions;
}

- (NSString *)_stringByRemovingScriptFilenameExtension:(NSString *)string;
{
    NSString *extension = [string pathExtension];
    if ([[self _scriptFilenameExtensions] containsObject:extension]) {
        NSString *suffix = [NSString stringWithFormat:@".%@", extension];
        return [string stringByRemovingSuffix:suffix];
    }
    
    return string;
}

- (void)_executeAutomatorWorkflowForToolbarItem:(OAToolbarItem *)toolbarItem inWindowController:(OAToolbarWindowController *)windowController completionHandler:(_RunItemCompletionHandler)completionHandler;
{
    NSString *path = [[self pathForItem:toolbarItem] stringByExpandingTildeInPath];
    NSURL *url = [NSURL fileURLWithPath:path];
    
    NSError *taskError = nil;
    NSUserAutomatorTask *task = [[NSUserAutomatorTask alloc] initWithURL:url error:&taskError];
    if (task == nil) {
        [self _handleAutomatorWorkflowLoadErrorForToolbarItem:toolbarItem inWindowController:windowController errorText:[taskError localizedDescription]];
        completionHandler(toolbarItem, taskError);
        return;
    }
    
    [task executeWithInput:nil completionHandler:^(id result, NSError *error) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (error != nil) {
                [self _handleAutomatorWorkflowExecutionErrorForToolbarItem:toolbarItem inWindowController:windowController errorText:[error localizedDescription]];
            }
            completionHandler(toolbarItem, error);
        }];
    }];
}

- (void)_executeOSAScriptForToolbarItem:(OAToolbarItem *)toolbarItem inWindowController:(OAToolbarWindowController *)windowController completionHandler:(_RunItemCompletionHandler)completionHandler;
{
    NSString *path = [[self pathForItem:toolbarItem] stringByExpandingTildeInPath];
    if (!path) {
        // This can happen if the user removes a script while the app is running.
        NSLog(@"No script found for toolbar item %@", toolbarItem.itemIdentifier);
        NSBeep();
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    
    NSError *taskError = nil;
    NSUserAppleScriptTask *task = [[NSUserAppleScriptTask alloc] initWithURL:url error:&taskError];
    if (task == nil) {
        [self _handleOSAScriptLoadErrorForToolbarItem:toolbarItem inWindowController:windowController errorText:[taskError localizedDescription]];
        completionHandler(toolbarItem, taskError);
        return;
    }
    
    NSAppleEventDescriptor *event = nil;

    if ([windowController respondsToSelector:@selector(scriptToolbarItemArguments:)]) {
        NSAppleEventDescriptor *arguments = [windowController scriptToolbarItemArguments:toolbarItem];
        if (arguments != nil) {
            if ([arguments descriptorType] != cAEList) {
                arguments = [arguments coerceToDescriptorType:cAEList];
                OBASSERT_NOTNULL(arguments);
            }
        }
        
        if (arguments != nil) {
            event = [NSAppleEventDescriptor appleEventWithEventClass:kCoreEventClass eventID:kAEOpenApplication targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
            [event setParamDescriptor:arguments forKeyword:keyDirectObject];
        }
    }

    [task executeWithAppleEvent:event completionHandler:^(NSAppleEventDescriptor *result, NSError *error) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (error != nil) {
                [self _handleOSAScriptExecutionErrorForToolbarItem:toolbarItem inWindowController:windowController errorText:[error localizedDescription]];
            }
            completionHandler(toolbarItem, error);
        }];
    }];
}

- (void)_handleAutomatorWorkflowLoadErrorForToolbarItem:(OAToolbarItem *)toolbarItem inWindowController:(OAToolbarWindowController *)windowController errorText:(NSString *)errorText;
{
    NSString *path = [[self pathForItem:toolbarItem] stringByExpandingTildeInPath];
    NSString *scriptName = [[NSFileManager defaultManager] displayNameAtPath:path];
    
    NSString *messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The Automator Workflow \"%@\" could not be opened.", @"OmniAppKit", [OAScriptToolbarHelper bundle], "Automator Workflow loading error"), scriptName];
    NSString *informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Automator reported the following error:\n%@", @"OmniAppKit", [OAScriptToolbarHelper bundle], "Automator Workflow error message"), errorText];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = messageText;
    alert.informativeText = informativeText;
    [alert addButtonWithTitle:OAOK()];
    [alert beginSheetModalForWindow:[windowController window] completionHandler:nil];
}

- (void)_handleAutomatorWorkflowExecutionErrorForToolbarItem:(OAToolbarItem *)toolbarItem inWindowController:(OAToolbarWindowController *)windowController errorText:(NSString *)errorText;
{
    NSString *path = [[self pathForItem:toolbarItem] stringByExpandingTildeInPath];
    NSString *scriptName = [[NSFileManager defaultManager] displayNameAtPath:path];
    
    NSString *messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The Automator Workflow \"%@\" could not complete.", @"OmniAppKit", [OAScriptToolbarHelper bundle], "Automator Workflow execute error"), scriptName];
    NSString *informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Automator reported the following error:\n\n%@", @"OmniAppKit", [OAScriptToolbarHelper bundle], "Automator Workflow execute error message"), errorText];
    NSString *OKButtonTitle = OAOK();
    NSString *editButtonTitle = NSLocalizedStringFromTableInBundle(@"Edit Workflow", @"OmniAppKit", [OAScriptToolbarHelper bundle], "Automatork workflow error panel button");
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = messageText;
    alert.informativeText = informativeText;
    [alert addButtonWithTitle:OKButtonTitle];
    [alert addButtonWithTitle:editButtonTitle];

    [alert beginSheetModalForWindow:[windowController window] completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
        }
    }];
}

- (void)_handleOSAScriptLoadErrorForToolbarItem:(OAToolbarItem *)toolbarItem inWindowController:(OAToolbarWindowController *)windowController errorText:(NSString *)errorText;
{
    NSString *path = [[self pathForItem:toolbarItem] stringByExpandingTildeInPath];
    NSString *scriptName = [[NSFileManager defaultManager] displayNameAtPath:path];

    NSString *messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The script file \"%@\" could not be opened.", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script loading error"), scriptName];
    NSString *informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"AppleScript reported the following error:\n%@", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script loading error message"), errorText];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = messageText;
    alert.informativeText = informativeText;
    [alert addButtonWithTitle:OAOK()];
    [alert beginSheetModalForWindow:[windowController window] completionHandler:nil];
}

- (void)_handleOSAScriptExecutionErrorForToolbarItem:(OAToolbarItem *)toolbarItem inWindowController:(OAToolbarWindowController *)windowController errorText:(NSString *)errorText;
{
    NSString *path = [[self pathForItem:toolbarItem] stringByExpandingTildeInPath];
    NSString *scriptName = [[NSFileManager defaultManager] displayNameAtPath:path];

    NSString *messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The script \"%@\" could not complete.", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script execute error"), scriptName];
    NSString *informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"AppleScript reported the following error:\n\n%@", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script execute error message"), errorText];
    NSString *editButtonTitle = NSLocalizedStringFromTableInBundle(@"Edit Script", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script error panel button");
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = messageText;
    alert.informativeText = informativeText;
    [alert addButtonWithTitle:OAOK()];
    [alert addButtonWithTitle:editButtonTitle];

    [alert beginSheetModalForWindow:[windowController window] completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
        }
    }];
}

@end

@implementation OAToolbarWindowController (OAScriptToolbarHelperExtensions)

- (NSAppleEventDescriptor *)scriptToolbarItemArguments:(OAToolbarItem *)item;
{
    NSAppleEventDescriptor *descriptor = [NSAppleEventDescriptor listDescriptor];
    [descriptor insertDescriptor:[[[self window] objectSpecifier] descriptor] atIndex:0]; // 0 means "at the end"
    return descriptor;
}

@end

NS_ASSUME_NONNULL_END
