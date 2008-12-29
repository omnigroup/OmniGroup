// Copyright 2002-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAScriptToolbarHelper.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSImage-OAExtensions.h"
#import "NSToolbar-OAExtensions.h"
#import "NSFileManager-OAExtensions.h"
#import "OAApplication.h"
#import "OAWorkflow.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OAScriptToolbarHelper.m 104581 2008-09-06 21:18:23Z kc $")

@interface OAScriptToolbarHelper (Private)
- (void)_scanItems;
@end

@implementation OAScriptToolbarHelper

- (id)init;
{
    if ([super init] == nil)
        return nil;

    _pathForItemDictionary = [[NSMutableDictionary alloc] init];

    return self;
}

- (void)dealloc;
{
    [_pathForItemDictionary release];
    [super dealloc];
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
    NSMutableArray *result = [NSMutableArray array];

    NSEnumerator *libraryDirectories = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask & ~(NSSystemDomainMask), YES) objectEnumerator];
    NSString *libraryDirectory;
    NSString *appSupportDirectory = [NSApp applicationSupportDirectoryName];
    while( (libraryDirectory = [libraryDirectories nextObject]) != nil ) {
        [result addObject:[[[libraryDirectory stringByAppendingPathComponent:@"Scripts"] stringByAppendingPathComponent:@"Applications"] stringByAppendingPathComponent:appSupportDirectory]];
    }
    
    [result addObject:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Scripts"]];
    
    return result;
}

static NSString *removeScriptSuffix(NSString *string)
{
    if ([string hasSuffix:@".scpt"])
        return [string stringByRemovingSuffix:@".scpt"];
    if ([string hasSuffix:@".scptd"])
        return [string stringByRemovingSuffix:@".scptd"];
    if ([string hasSuffix:@".applescript"])
        return [string stringByRemovingSuffix:@".applescript"];
    if ([string hasSuffix:@".workflow"])
        return [string stringByRemovingSuffix:@".workflow"];
    return string;
}

- (NSArray *)allowedItems;
{
    [self _scanItems];
    return [_pathForItemDictionary allKeys];
}

- (NSString *)pathForItem:(NSToolbarItem *)anItem;
{
    [self _scanItems];
    return [_pathForItemDictionary objectForKey:[anItem itemIdentifier]];
}

- (void)finishSetupForItem:(NSToolbarItem *)item;
{
    NSString *path = [self pathForItem:item];
    if (path == nil)
        return;
    
    [item setTarget:self];
    [item setAction:@selector(executeScriptItem:)];
    [item setLabel:removeScriptSuffix([item label])];
    [item setPaletteLabel:removeScriptSuffix([item paletteLabel])];

    path = [path stringByExpandingTildeInPath];
    [item setImage:[[NSWorkspace sharedWorkspace] iconForFile:path]];

    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    
    FSRef myFSRef;
    if (CFURLGetFSRef(url, &myFSRef)) {
        FSCatalogInfo catalogInfo;
        if (FSGetCatalogInfo(&myFSRef, kFSCatInfoFinderInfo, &catalogInfo, NULL, NULL, NULL) == noErr) {
            if ((((FileInfo *)(&catalogInfo.finderInfo))->finderFlags & kHasCustomIcon) == 0)
                [item setImage:[NSImage imageNamed:@"OAScriptIcon" inBundleForClass:[OAScriptToolbarHelper class]]];
        }
    }
    
    CFRelease(url);
}

- (void)executeScriptItem:sender;
{
    OAToolbarWindowController *controller = [[sender toolbar] delegate];
    
    if ([controller respondsToSelector:@selector(scriptToolbarItemShouldExecute:)] &&
	![controller scriptToolbarItemShouldExecute:sender])
	return;
    
    @try {
	NSString *scriptFilename = [[self pathForItem:sender] stringByExpandingTildeInPath];

	if ([@"workflow" isEqualToString:[scriptFilename pathExtension]]) {
	    OAWorkflow *workflow = [OAWorkflow workflowWithContentsOfFile:scriptFilename];
	    if (!workflow) {
		NSBundle *frameworkBundle = [OAScriptToolbarHelper bundle];
		NSString *errorText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to run workflow.", @"OmniAppKit", frameworkBundle, "workflow execution error")];
		NSString *messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"workflow not found at %@", @"OmniAppKit", frameworkBundle, "script loading error message"), scriptFilename];
		NSString *okButton = NSLocalizedStringFromTableInBundle(@"OK", @"OmniAppKit", frameworkBundle, "script error panel button");
		NSBeginAlertSheet(errorText, okButton, nil, nil, [[sender toolbar] window], self, NULL, NULL, NULL, messageText);                                     
		return;
	    }
	    NSException   *raisedException = nil;
	    NS_DURING {
		[workflow executeWithFiles:nil];
	    } NS_HANDLER {
		raisedException = localException;
	    } NS_ENDHANDLER;
	    if (raisedException) {
		NSBundle *frameworkBundle = [OAScriptToolbarHelper bundle];
		NSString *errorText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to run workflow.", @"OmniAppKit", frameworkBundle, "workflow execution error")];
		NSString *messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The following error was reported:\n%@", @"OmniAppKit", frameworkBundle, "script loading error message"), [raisedException reason]];
		NSString *okButton = NSLocalizedStringFromTableInBundle(@"OK", @"OmniAppKit", frameworkBundle, "script error panel button");
		NSBeginAlertSheet(errorText, okButton, nil, nil, [[sender toolbar] window], self, NULL, NULL, NULL, messageText);                                     
	    }
	} else {
	    NSDictionary *errorDictionary;
	    NSString *scriptName = [[NSFileManager defaultManager] displayNameAtPath:scriptFilename];
	    NSAppleScript *script = [[[NSAppleScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:scriptFilename] error:&errorDictionary] autorelease];
	    NSAppleEventDescriptor *result;
	    if (script == nil) {
		NSString *errorText, *messageText, *okButton;
		
		errorText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The script file '%@' could not be opened.", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script loading error"), scriptName];
		messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"AppleScript reported the following error:\n%@", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script loading error message"), [errorDictionary objectForKey:NSAppleScriptErrorMessage]];
		okButton = NSLocalizedStringFromTableInBundle(@"OK", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script error panel button");
		NSBeginAlertSheet(errorText, okButton, nil, nil, [[sender toolbar] window], self, NULL, NULL, NULL, messageText);                                     
		return;
	    }
	    result = [script executeAndReturnError:&errorDictionary];
	    if (result == nil) {
		NSString *errorText, *messageText, *okButton, *editButton;
		
		errorText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The script '%@' could not complete.", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script execute error"), scriptName];
		messageText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"AppleScript reported the following error:\n%@", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script execute error message"), [errorDictionary objectForKey:NSAppleScriptErrorMessage]];
		okButton = NSLocalizedStringFromTableInBundle(@"OK", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script error panel button");
		editButton = NSLocalizedStringFromTableInBundle(@"Edit Script", @"OmniAppKit", [OAScriptToolbarHelper bundle], "script error panel button");
		NSBeginAlertSheet(errorText, okButton, editButton, nil, [[sender toolbar] window], self, @selector(errorSheetDidEnd:returnCode:contextInfo:), NULL, [scriptFilename retain], messageText);                                     
		
		return;
	    }
	}
    } @finally {
	if ([controller respondsToSelector:@selector(scriptToolbarItemFinishedExecuting:)])
	    [controller scriptToolbarItemFinishedExecuting:sender];
    }
}

- (void)errorSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode == NSAlertAlternateReturn)
        [[NSWorkspace sharedWorkspace] openFile:[(NSString *)contextInfo autorelease]];
}

@end

@implementation OAScriptToolbarHelper (Private)

- (void)_scanItems;
{
    [_pathForItemDictionary removeAllObjects];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSEnumerator *folderEnumerator = [[self scriptPaths] objectEnumerator];
    NSString *scriptFolder;
    
    NSMutableArray *scriptTypes = [NSMutableArray array];
    /* Note that text scripts and compiled scripts do not conform to each other */
    [scriptTypes addObjects:@"com.apple.applescript.text", @"com.apple.applescript.script", @"com.apple.automator-workflow", nil];
    CFArrayRef scriptBundles = UTTypeCreateAllIdentifiersForTag(kUTTagClassFilenameExtension, CFSTR("scptd"), NULL);
    if (scriptBundles) {
        [scriptTypes addObjectsFromArray:(NSArray *)scriptBundles];
        CFRelease(scriptBundles);
    }
    
    while ((scriptFolder = [folderEnumerator nextObject])) {
        for(NSString *filename in [fileManager directoryContentsAtPath:scriptFolder
                                                               ofTypes:scriptTypes
                                                                  deep:YES
                                                              fullPath:NO
                                                                 error:NULL]) {
	    
	    NSString *itemIdentifier = [removeScriptSuffix(filename) stringByAppendingPathExtension:@"osascript"];
            if ([_pathForItemDictionary objectForKey:itemIdentifier] != nil)
                continue; // Don't register more than one script with the same name

	    NSString *path = [[scriptFolder stringByAppendingPathComponent:filename] stringByAbbreviatingWithTildeInPath];
            [_pathForItemDictionary setObject:path forKey:itemIdentifier];
        } 
    }
}

@end
