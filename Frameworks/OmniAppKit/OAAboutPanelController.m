// Copyright 2005-2006,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  Created by Timothy J. Wood on 11/21/05.

#import "OAAboutPanelController.h"

#import "NSLayoutManager-OAExtensions.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

static NSString *OAAboutPanelMainBundleContentVariants = @"OAAboutPanelMainBundleContentVariants";

@implementation OAAboutPanelController

- init;
{
    if (!(self = [super init]))
	return nil;
    
    contentVariants = [[NSMutableArray alloc] init];
    currentContentVariantIndex = -1;
    
    return self;
}

- (void)dealloc;
{
    [panel release];
    [contentVariants release];
    [super dealloc];
}

#pragma mark -
#pragma mark API

- (void)awakeFromNib;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    
    NSString *appName = [infoDictionary objectForKey:@"CFBundleName"];
    appName = appName ? appName : @"CFBundleName not set!";
    [applicationNameTextField setStringValue:appName];
    [applicationNameTextField sizeToFit];
    
    NSString *cfBundleVers = [infoDictionary objectForKey:@"CFBundleVersion"];
    // The current Omni convention is to append the SVN revision number to the version number at build time, so that we don't have to explicitly increment things for nighlies and so on. This is ugly, though, so let's not display it like that.
    NSRange zeroRange = [cfBundleVers rangeOfString:@".0."];
    if (zeroRange.length > 0) {
        NSString *after = [cfBundleVers substringFromIndex:NSMaxRange(zeroRange)];
        if (![after containsString:@"."] && [after unsignedIntValue] > 1000) {
            cfBundleVers = [NSString stringWithStrings:[cfBundleVers substringToIndex:zeroRange.location], @" r", after, nil];
        }
    }
    
    [fullReleaseNameButton setTitle:[NSString stringWithFormat:@"%@ (v%@)", [infoDictionary objectForKey:@"CFBundleShortVersionString"], cfBundleVers]];
    [fullReleaseNameButton sizeToFit];
    
    [creditsTextView setEditable:NO];
    [creditsTextView setSelectable:YES];
    [[creditsTextView enclosingScrollView] setDrawsBackground:NO];
    
    NSString *copyright = [infoDictionary objectForKey:@"NSHumanReadableCopyright"];
    copyright = copyright ? copyright : @"NSHumanReadableCopyright not set!";
    [copyrightTextField setStringValue:copyright];
    
    // Re-center the top components.  These aren't in a box so that it's easy to resize applicationNameTextField with -sizeToFit.  We ignore the width of the fullReleaseNameButton at the moment.
    {
	NSRect iconFrame = [appIconImageView frame];
	NSRect nameFrame = [applicationNameTextField frame];
	NSRect releaseFrame = [fullReleaseNameButton frame];
	
	NSRect panelFrame = [panel frame];
	
	NSRect totalFrame = NSUnionRect(iconFrame, nameFrame);
	float minX = floor((NSWidth(panelFrame) - NSWidth(totalFrame))/2.0);
	
	float offset = NSMinX(iconFrame) - minX;
	
	iconFrame.origin.x -= offset;
	nameFrame.origin.x -= offset;
	releaseFrame.origin.x -= offset;
	
	[appIconImageView setFrame:iconFrame];
	[applicationNameTextField setFrame:nameFrame];
	[fullReleaseNameButton setFrame:releaseFrame];
    }
    
    // Look in the main bundle for the list of stuff to put in the about panel content area.  If the main bundle doesn't override the list, then provide a default list here (for which the main bundle still needs to provide the resources).
    NSArray *variantFileNames = [[[NSBundle mainBundle] infoDictionary] objectForKey:OAAboutPanelMainBundleContentVariants];
    if (!variantFileNames)
	variantFileNames = [[OMNI_BUNDLE infoDictionary] objectForKey:OAAboutPanelMainBundleContentVariants];
    
    unsigned int variantIndex, variantCount = [variantFileNames count];
    for (variantIndex = 0; variantIndex < variantCount; variantIndex++) {
	NSString *fileName = [variantFileNames objectAtIndex:variantIndex];
	[self addContentVariantFromMainBundleFile:[fileName stringByDeletingPathExtension] ofType:[fileName pathExtension]];
    }
    
    [self showNextContentVariant:nil];
        
    // Resize the panel so that the default content variant fits exactly (no scroller)
    if (variantCount) {
	NSLayoutManager *layoutManager = [creditsTextView layoutManager];
	float totalHeight = [layoutManager totalHeightUsed];
	
	NSRect scrollFrame = [[creditsTextView enclosingScrollView] frame];
	float delta = totalHeight - NSHeight(scrollFrame);
	
	NSRect panelFrame = [panel frame];
	panelFrame.size.height += (delta);

	[panel setFrame:panelFrame display:NO];
    }
}

- (NSArray *)contentVariants;
{
    return contentVariants;
}

- (void)addContentVariant:(NSAttributedString *)content;
{
    [contentVariants addObject:content];
}

- (void)addContentVariantFromMainBundleFile:(NSString *)name ofType:(NSString *)type;
{
    NSAttributedString *variant = nil;
    
    @try {
	NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:type];
	if (!path)
	    return;
	
	if ([type isEqualToString:@"txt"]) {
	    NSData *utf8Data = [[NSData alloc] initWithContentsOfFile:path];
	    NSString *string = [[NSString alloc] initWithData:utf8Data encoding:NSUTF8StringEncoding];
	    [utf8Data release];
	    
	    // There is no NSFont class method for the 'mini' size.
	    NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
		[NSFont systemFontOfSize:9.0f], NSFontAttributeName,
		[NSColor whiteColor], NSBackgroundColorAttributeName,
		nil];
	    variant = [[NSAttributedString alloc] initWithString:string attributes:attributes];
            [string release];
	    [attributes release];
	} else {
	    variant = [[NSAttributedString alloc] initWithPath:path documentAttributes:NULL];
	    
#if 0 // Looks too tight in OmniGraffle
	    // For some reason, HTML files seem to get a newline appended to their end even if we try to avoid it in the source.  Strip any trailing newlines.
	    NSRange whitespaceRange = [[variant string] rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] options:NSBackwardsSearch];
	    if (whitespaceRange.length) {
		[variant autorelease];
		variant = [[variant attributedSubstringFromRange:NSMakeRange(0, whitespaceRange.location)] retain];
	    }
#endif
	}
    } @catch (NSException *exc) {
	NSLog(@"Exception raised while trying to load about panel variant %@.%@ -- %@", name, type, exc);
    }
    
    if (variant) {
	[self addContentVariant:variant];
	[variant release];
    }
}

#pragma mark -
#pragma mark Subclass API

- (void)willShowAboutPanel;
{
}

#pragma mark -
#pragma mark Actions

- (IBAction)showAboutPanel:(id)sender;
{
    if (!panel) {
	NSNib *nib = [[NSNib alloc] initWithNibNamed:@"OAAboutPanel" bundle:OMNI_BUNDLE];
	if (!nib || ![nib instantiateNibWithOwner:self topLevelObjects:NULL])
	    NSLog(@"Unable to load OAAboutPanel.nib");
	[nib release];
    }
    [panel center];
    [self willShowAboutPanel];
    [panel makeKeyAndOrderFront:self];
    [panel makeFirstResponder:panel];
}

- (IBAction)hideAboutPanel:(id)sender;
{
    [panel close];
}

- (IBAction)showNextContentVariant:(id)sender;
{
    NSInteger contentVariantCount = [contentVariants count];
    if (contentVariantCount == 0)
	return;
    
    if (currentContentVariantIndex < 0 || (++currentContentVariantIndex >= contentVariantCount))
	currentContentVariantIndex = 0;
    
    // If showing the default variant, turn off the scrollers (since we want to set the panel to the exact height such that the scrollers wouldn't be present and since figuring out this height would require some iterative algorithm otherwise)
    [[creditsTextView enclosingScrollView] setHasVerticalScroller:(currentContentVariantIndex != 0)];
    
    NSAttributedString *variant = [contentVariants objectAtIndex:currentContentVariantIndex];
    [[creditsTextView textStorage] setAttributedString:variant];
    
    // We assume the whole attributed string has the same background color
    BOOL drawBackground = NO;
    if ([variant length]) {
	NSColor *background = [variant attribute:NSBackgroundColorAttributeName atIndex:0 longestEffectiveRange:NULL inRange:NSMakeRange(0, [variant length])];
	drawBackground = (background != nil) && ![background isEqual:[NSColor clearColor]]; // not really correct since we could be (1,0,0,0)
    }
    [creditsTextView setDrawsBackground:drawBackground];
}

@end
