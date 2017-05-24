// Copyright 2005-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  Created by Timothy J. Wood on 11/21/05.

#import <OmniAppKit/OAAboutPanelController.h>

#import <OmniAppKit/NSLayoutManager-OAExtensions.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAController.h>

RCS_ID("$Id$");

static NSString * const OAAboutPanelMainBundleContentVariants = @"OAAboutPanelMainBundleContentVariants";

@interface OAAboutPanelController () <NSTextViewDelegate>
@end

@implementation OAAboutPanelController

- (instancetype)init;
{
    if (!(self = [super init]))
	return nil;
    
    contentVariants = [[NSMutableArray alloc] init];
    currentContentVariantIndex = -1;
    
    return self;
}

#pragma mark -
#pragma mark API

+ (NSString *)fullVersionString;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *cfBundleVers = [infoDictionary objectForKey:@"CFBundleVersion"];
    // The current Omni convention is to append the SVN revision number to the version number at build time, so that we don't have to explicitly increment things for nightlies and so on. This is ugly, though, so let's not display it like that.
    NSRange zeroRange = [cfBundleVers rangeOfString:@".0."];
    if (zeroRange.length > 0) {
        NSString *after = [cfBundleVers substringFromIndex:NSMaxRange(zeroRange)];
        if (![after containsString:@"."] && [after unsignedIntValue] > 1000) {
            cfBundleVers = [NSString stringWithStrings:[cfBundleVers substringToIndex:zeroRange.location], @" r", after, nil];
        }
    }
    
    return [NSString stringWithFormat:@"%@ (v%@)", [infoDictionary objectForKey:@"CFBundleShortVersionString"], cfBundleVers];
}

- (void)_updateFieldsAndWindowSize;
{
    NSString *appName = [[OAController sharedController] appName];
    [applicationNameTextField setStringValue:appName];
    [applicationNameTextField sizeToFit];
    
    [fullReleaseNameButton setTitle:[[self class] fullVersionString]];
    [fullReleaseNameButton sizeToFit];
    
    [creditsTextView setDelegate:self];
    [creditsTextView setEditable:NO];
    [creditsTextView setSelectable:YES];
    [[creditsTextView enclosingScrollView] setDrawsBackground:NO];
    
    NSString *copyright = [[[NSBundle mainBundle] localizedInfoDictionary] objectForKey:@"NSHumanReadableCopyright"];
    if (!copyright) {
        OBASSERT_NOT_REACHED("No entry specified for Info.plist NSHumanReadableCopyright key");
        copyright = OBUnlocalized(@"NSHumanReadableCopyright not set!");
    }
    [copyrightTextField setStringValue:copyright];
    
    // Re-center the top components.  These aren't in a box so that it's easy to resize applicationNameTextField with -sizeToFit.  We ignore the width of the fullReleaseNameButton at the moment.
    {
	NSRect iconFrame = [appIconImageView frame];
	NSRect nameFrame = [applicationNameTextField frame];
	NSRect releaseFrame = [fullReleaseNameButton frame];
	
	NSRect panelFrame = [panel frame];
	
	NSRect totalFrame = NSUnionRect(iconFrame, nameFrame);
	CGFloat minX = (CGFloat)floor((NSWidth(panelFrame) - NSWidth(totalFrame))/2.0);
	
	CGFloat offset = NSMinX(iconFrame) - minX;
	
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
    
    for (NSString *fileName in variantFileNames)
	[self addContentVariantFromMainBundleFile:[fileName stringByDeletingPathExtension] ofType:[fileName pathExtension]];
    
    [self showNextContentVariant:nil];
        
    // Resize the panel so that the default content variant fits exactly (no scroller)
    if ([variantFileNames count]) {
	NSLayoutManager *layoutManager = [creditsTextView layoutManager];
	CGFloat totalHeight = [layoutManager totalHeightUsed];
	
	NSRect scrollFrame = [[creditsTextView enclosingScrollView] frame];
	CGFloat delta = totalHeight - NSHeight(scrollFrame);
	
	NSRect panelFrame = [panel frame];
	panelFrame.size.height += (delta);

	[panel setFrame:panelFrame display:NO];
    }

    [panel center];
}

- (void)awakeFromNib;
{
    [self _updateFieldsAndWindowSize];
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
	NSURL *contentURL = [[NSBundle mainBundle] URLForResource:name withExtension:type];
	if (!contentURL)
	    return;
	
	if ([type isEqualToString:@"txt"]) {
            __autoreleasing NSError *error = nil;
            NSData *utf8Data = [[NSData alloc] initWithContentsOfURL:contentURL options:NSDataReadingUncached error:&error];
            if (!utf8Data) {
                [error log:@"Error reading %@", contentURL];
                return;
            }
	    NSString *string = [[NSString alloc] initWithData:utf8Data encoding:NSUTF8StringEncoding];
            if (!string) {
                OBASSERT(string);
                string = @"";
            }

	    // There is no NSFont class method for the 'mini' size.
	    NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
		[NSFont systemFontOfSize:9.0f], NSFontAttributeName,
		[NSColor whiteColor], NSBackgroundColorAttributeName,
		nil];
	    variant = [[NSAttributedString alloc] initWithString:string attributes:attributes];
	} else {
            __autoreleasing NSError *error = nil;
            variant = [[NSAttributedString alloc] initWithURL:contentURL options:@{} documentAttributes:NULL error:&error];
            if (!variant) {
                [error log:@"Error reading %@", contentURL];
                return;
            }
	}
    } @catch (NSException *exc) {
	NSLog(@"Exception raised while trying to load about panel variant %@.%@ -- %@", name, type, exc);
    }
    
    if (variant) {
	[self addContentVariant:variant];
    }
}

#pragma mark -
#pragma mark Subclass API

- (void)willShowAboutPanel;
{
    NSString *appName = [[OAController sharedController] appName];
    [applicationNameTextField setStringValue:appName];
    [applicationNameTextField sizeToFit];
}

#pragma mark -
#pragma mark Actions

- (IBAction)showAboutPanel:(id)sender;
{
    // <bug:///89031> (Update OAAboutPanelController to use non-deprecated API)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!panel) {
	NSNib *nib = [[NSNib alloc] initWithNibNamed:@"OAAboutPanel" bundle:OMNI_BUNDLE];
	if (!nib || ![nib instantiateNibWithOwner:self topLevelObjects:NULL])
	    NSLog(@"Unable to load OAAboutPanel.nib");
    }
    [self _updateFieldsAndWindowSize];
    [self willShowAboutPanel];
    [panel makeKeyAndOrderFront:self];
    [panel makeFirstResponder:panel];
#pragma clang diagnostic pop
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

#pragma mark - NSTextViewDelegate protocol

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex;
{
    if ([link isKindOfClass:[NSURL class]]) {
        NSURL *linkURL = link;
        if (OFISEQUAL([linkURL scheme], @"help")) {
            [[OAApplication sharedApplication] showHelpURL:[linkURL resourceSpecifier]];
            return YES; // We've handled the link
        }
    }

    return NO; // Hand this off to [NSWorkspace openURL:]
}

@end
