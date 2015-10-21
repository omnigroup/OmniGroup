// Copyright 2005-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OAApplication-OIExtensions.h>

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniInspector/OIInspectorGroup.h>
#import <OmniInspector/OIInspectorRegistry.h>

#import "OIColorInspector.h"

RCS_ID("$Id$")

@implementation OAApplication (OIExtensions)

- (IBAction)toggleInspectorPanel:(id)sender;
{
    // [OIInspectorRegistry toggleAllInspectors] seems inviting, but it makes _all_ inspectors visible, or hides them all if they were already all visible. We, instead, want to toggle between the user's chosen visible set and hiding them all.
    [[OIInspectorRegistry inspectorRegistryForMainWindow] tabShowHidePanels];
}

- (void)revealEmbeddedInspectorFromMenuItem:(id)sender;
{
    [[OIInspectorRegistry inspectorRegistryForMainWindow] revealEmbeddedInspectorFromMenuItem:sender];
}

- (IBAction)toggleFrontColorPanel:(id)sender;
{
    [[NSColorPanel sharedColorPanel] toggleWindow:nil];
}

// NSMenuValidation

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    SEL action = [item action];
    
    if (action == @selector(toggleInspectorPanel:)) {
        NSString *showString = nil;
        NSString *hideString = nil;
        if ([[OIInspectorRegistry inspectorRegistryForMainWindow] hasSingleInspector]) {
            showString = NSLocalizedStringFromTableInBundle(@"Show Inspector", @"OmniInspector", [OIInspectorRegistry bundle], "menu title");
            hideString = NSLocalizedStringFromTableInBundle(@"Hide Inspector", @"OmniInspector", [OIInspectorRegistry bundle], "menu title");
        } else {
            showString = NSLocalizedStringFromTableInBundle(@"Show Inspectors", @"OmniInspector", [OIInspectorRegistry bundle], "menu title");
            hideString = NSLocalizedStringFromTableInBundle(@"Hide Inspectors", @"OmniInspector", [OIInspectorRegistry bundle], "menu title");
        }
	
        if ([[OIInspectorRegistry inspectorRegistryForMainWindow] hasVisibleInspector]) {
            [item setTitle:hideString];
        } else {
            [item setTitle:showString];
        }
        return YES;
    }

    if (action == @selector(revealEmbeddedInspectorFromMenuItem:)) {
        return [[OIInspectorRegistry inspectorRegistryForMainWindow] validateMenuItem:item];
    }

    return [super validateMenuItem:item];
}

@end
