// Copyright 2005-2006, 2012, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAApplication-OIExtensions.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OIColorInspector.h"
#import "OIInspectorGroup.h"
#import "OIInspectorRegistry.h"

RCS_ID("$Id$")

@implementation OAApplication (OIExtensions)

- (IBAction)toggleInspectorPanel:(id)sender;
{
    // [OIInspectorRegistry toggleAllInspectors] seems inviting, but it makes _all_ inspectors visible, or hides them all if they were already all visible. We, instead, want to toggle between the user's chosen visible set and hiding them all.
    [[OIInspectorRegistry inspectorRegistryForMainWindow] tabShowHidePanels];
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
	
        if ([[[OIInspectorRegistry inspectorRegistryForMainWindow] visibleGroups] count] > 0) {
            [item setTitle:hideString];
        } else {
            [item setTitle:showString];
        }
        return YES;
    }
    
    return [super validateMenuItem:item];
}

@end
