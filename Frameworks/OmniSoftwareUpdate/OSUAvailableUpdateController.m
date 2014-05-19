// Copyright 2007-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUAvailableUpdateController.h"

#import "OSUChecker.h"
#import "OSUItem.h"
#import "OSUController.h"
#import "OSUPreferences-Items.h"
#import "OSUFlippedView.h"
#import "OSUThinBorderView.h"

#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSPopUpButton-OAExtensions.h>
#import <OmniAppKit/NSTextField-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniAppKit/OAPreferenceClientRecord.h>
#import <OmniAppKit/OAVersion.h>
#import <OmniBase/OmniBase.h>

#import <AppKit/AppKit.h>
#import <WebKit/WebDataSource.h>
#import <WebKit/WebFrame.h>
#import <WebKit/WebPolicyDelegate.h>
#import <WebKit/WebView.h>

NSString * const OSUAvailableUpdateControllerAvailableItemsBinding = @"availableItems";
NSString * const OSUAvailableUpdateControllerCheckInProgressBinding = @"checkInProgress";
NSString * const OSUAvailableUpdateControllerSelectedItemIndexesBinding = @"selectedItemIndexes";
NSString * const OSUAvailableUpdateControllerSelectedItemBinding = @"selectedItem";
NSString * const OSUAvailableUpdateControllerMessageBinding = @"message";
NSString * const OSUAvailableUpdateControllerDetailsBinding = @"details";
NSString * const OSUAvailableUpdateControllerLoadingReleaseNotesBinding = @"loadingReleaseNotes";
NSString * const OSUAvailableUpdateControllerLastCheckFailedBinding = @"lastCheckFailed";
NSString * const OSUAvailableUpdateControllerLastCheckUserInitiatedBinding = @"lastCheckExplicit";


RCS_ID("$Id$");

@interface OSUAvailableUpdateController ()
- (void)_resizeInterface:(BOOL)resetDividerPosition;
- (void)_refreshSelectedItem:(NSNotification *)dummyNotification;
- (void)_refreshDefaultAction;
- (void)_loadReleaseNotes;
@end

@implementation OSUAvailableUpdateController

+ (OSUAvailableUpdateController *)availableUpdateController:(BOOL)shouldCreate;
{
    static OSUAvailableUpdateController *availableUpdateController = nil;
    if (!availableUpdateController && shouldCreate)
        availableUpdateController = [[self alloc] init];
    return availableUpdateController;
}

#pragma mark -
#pragma mark Actions

- (IBAction)installSelectedItem:(id)sender;
{
    OSUItem *item = [self selectedItem];
    NSURL *downloadURL = [item downloadURL];
    if (!downloadURL) {
        NSBeep();
        return;
    }
    
    NSError *error = nil;
    if (![[OSUController sharedController] beginDownloadAndInstallFromPackageAtURL:downloadURL item:item error:&error])
        [NSApp presentError:error];
    else
        [self close];
}

- (IBAction)showMoreInformation:(id)sender;
{
    OSUItem *item = [self selectedItem];
    NSString *sourceWebPage = [item sourceLocation];
    NSURL *infoURL;
    
    if ([NSString isEmptyString:sourceWebPage] || !(infoURL = [NSURL URLWithString:sourceWebPage])) {
        NSBeep();
        return;  // Shouldn't happen; button should be disabled.
    }
    
    [[NSWorkspace sharedWorkspace] openURL:infoURL];
}

#pragma mark -
#pragma mark NSWindowController subclass

- (void)dealloc
{
    [self unbind:OSUAvailableUpdateControllerCheckInProgressBinding];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
    [super dealloc];
}

- (NSString *)windowNibName;
{
    return NSStringFromClass([self class]);
}

- (void)windowWillLoad;
{
    [super windowWillLoad];
    
    // Most recent version should be at the top so the user doesn't have to scroll down if a bunch of versions are shown.
    NSSortDescriptor *byVersion = [[NSSortDescriptor alloc] initWithKey:@"buildVersion" ascending:NO selector:@selector(compareToVersionNumber:)];
    _itemSortDescriptors = [[NSArray alloc] initWithObjects:byVersion, nil];
    [byVersion release];
    
    _itemFilterPredicate = [[OSUItem availableAndNotSupersededPredicate] retain];
}

- (void)windowDidLoad;
{
    [super windowDidLoad];

    _minimumAlertPaneHeight = [_itemAlertPane frame].size.height;
    
    {
        NSRect oldFrame = [_installButton frame];
        [_installButton sizeToFit];
        NSRect newFrame = [_installButton frame];
        _buttonExtraSize.width = oldFrame.size.width - newFrame.size.width;
        _buttonExtraSize.height = oldFrame.size.height - newFrame.size.height;
        [_installButton setFrame:oldFrame];
    }
        
    // If running on 10.6+, use the "pane splitter" style instead of the "thick divider" style (they're *almost* identical...)
    [_itemsAndReleaseNotesSplitView setDividerStyle:NSSplitViewDividerStylePaneSplitter];
    
    // Allow @media {...} in the release notes to display differently when we are showing the content
    [_releaseNotesWebView setMediaStyle:@"osu-available-updates"];
    
    [self bind:OSUAvailableUpdateControllerCheckInProgressBinding
      toObject:[OSUChecker sharedUpdateChecker]
   withKeyPath:OSUCheckerCheckInProgressBinding
       options:nil];
    
    // Set the available items binding here, after all the UI has been loaded, so that the final value of -message isn't determined while are partially unarchived from nib.
    // Also have to poke the message binding since its value changes based on the available items in the controller we are setting up.
    // The nicer way to do this would probably be to split part of this class out into an NSArrayController subclass.
    [self willChangeValueForKey:OSUAvailableUpdateControllerMessageBinding];
    [_availableItemController bind:NSContentArrayBinding toObject:self withKeyPath:OSUAvailableUpdateControllerAvailableItemsBinding options:nil];
    [self didChangeValueForKey:OSUAvailableUpdateControllerMessageBinding];

    [self _resizeInterface:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_adjustViewLayout:) name:NSViewFrameDidChangeNotification object:[_messageTextField superview]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshSelectedItem:) name:OSUTrackInformationChangedNotification object:nil];
    [self _refreshDefaultAction];
    [self _loadReleaseNotes];
}

#pragma mark -
#pragma mark KVC

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;
{
    if ([key isEqualToString:OSUAvailableUpdateControllerAvailableItemsBinding])
        return NO;
    
    return [super automaticallyNotifiesObserversForKey:key];
}

+ (NSSet *)keyPathsForValuesAffectingMessage;
{
    return [NSSet setWithObjects:OSUAvailableUpdateControllerAvailableItemsBinding, OSUAvailableUpdateControllerCheckInProgressBinding, OSUAvailableUpdateControllerLastCheckFailedBinding, nil];
}

- (NSString *)message;
{
    NSString *format; // All format strings should take the app name and then the update count.
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];
    
    if ([[self valueForKey:OSUAvailableUpdateControllerCheckInProgressBinding] boolValue]) {
        format = NSLocalizedStringFromTableInBundle(@"Checking for %1$@ updates.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when in the process of checking for updates - text is name of application");
        return [NSString stringWithFormat:format, appName];
    } else if (_lastCheckFailed) {
        format = NSLocalizedStringFromTableInBundle(@"Unable to check for updates.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when check failed");
        return [NSString stringWithFormat:format, appName];
    } else {
        NSUInteger count = [[_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]] count];
        
        if (count == 0) {
            format = NSLocalizedStringFromTableInBundle(@"%1$@ is up to date.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when no updates are available - text is name of application");
        } else if (count == 1) {
            format = NSLocalizedStringFromTableInBundle(@"There is an update available for %1$@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when one update is available - text is name of application");
        } else {
            format = NSLocalizedStringFromTableInBundle(@"There are %2$d updates available for %1$@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when more than one update is available - text is name of application");
        }
        return [NSString stringWithFormat:format, appName, (int)count]; // Format string has hard coded 'd'.
    }
}

+ (NSSet *)keyPathsForValuesAffectingDetails;
{
    return [NSSet setWithObjects:OSUAvailableUpdateControllerAvailableItemsBinding, OSUAvailableUpdateControllerLastCheckUserInitiatedBinding, nil];
}

- (NSAttributedString *)details;
{
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];

    NSString *name = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];
    
    // If we are _not_ on the release track, show more detailed release information.  The marketing version might not get updated on every build on other tracks.
    NSString *version = [NSString stringWithFormat:@"%@ %@", name, [bundleInfo objectForKey:@"CFBundleShortVersionString"]];
    
    if (![[OSUChecker sharedUpdateChecker] applicationOnReleaseTrack]) {
        // Append the bundle version
        OFVersionNumber *versionNumber = [[OFVersionNumber alloc] initWithVersionString:[bundleInfo objectForKey:(id)kCFBundleVersionKey]];
        version = [version stringByAppendingFormat:@" (v%@ built %s)", [versionNumber prettyVersionString], __DATE__];
        [versionNumber release];
    }

    NSArray *displayedItems = [_availableItemController arrangedObjects];
    
    NSUInteger knownCount = [[_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededPredicate]] count];
    NSUInteger downgradesCount = [[displayedItems filteredArrayUsingPredicate:[OSUItem availableOldStablePredicate]] count];
    
    BOOL newerVersionsAvailable = (knownCount > downgradesCount);
    
    NSString *format, *formatted;
    if (!newerVersionsAvailable && ![[self valueForKey:OSUAvailableUpdateControllerCheckInProgressBinding] boolValue]) {
        format = NSLocalizedStringFromTableInBundle(@"You are currently running %@, which is the newest version.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "detail message of new versions available dialog. placeholder is application version number. further text may be appended");
    } else {
        format = NSLocalizedStringFromTableInBundle(@"You are currently running %@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "detail message of new versions available dialog. placeholder is application version number. further text may be appended");
    }
    formatted = [NSString stringWithFormat:format, version];
    
    if (downgradesCount > 0) {
        format = NSLocalizedStringFromTableInBundle(@"If you wish, you can downgrade to an older, but possibly more stable, version.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "detail message of new versions available dialog: appended when it is possible to downgrade to an older version");
        formatted = [[formatted stringByAppendingString:@"  "] stringByAppendingString:format];
    }
    
    if (newerVersionsAvailable && !_lastCheckExplicit) {
        format = NSLocalizedStringFromTableInBundle(@"If you're not ready to update now, you can use the [Update preference pane] to check for updates later or adjust the frequency of automatic checking.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "detail message of new versions available dialog, with [link] to preference pane");
        formatted = [[formatted stringByAppendingString:@"  "] stringByAppendingString:format];
    }
    
    NSMutableAttributedString *detailText = [[[NSMutableAttributedString alloc] initWithString:formatted] autorelease];
    [detailText addAttribute:NSFontAttributeName value:[NSFont messageFontOfSize:[NSFont smallSystemFontSize]] range:(NSRange){0, [detailText length]}];
    NSRange leftBracket = [[detailText string] rangeOfString:@"["];
    NSRange rightBracket = [[detailText string] rangeOfString:@"]"];
    if (leftBracket.length && rightBracket.length && leftBracket.location < rightBracket.location) {
        [detailText beginEditing];
        NSRange between;
        between.location = NSMaxRange(leftBracket);
        between.length = rightBracket.location - between.location;
        OAPreferenceClientRecord *rec = [OAPreferenceController clientRecordWithIdentifier:[OMNI_BUNDLE_IDENTIFIER stringByAppendingString:@".preferences"]];
        OBASSERT(rec != nil);
        if (rec) {
            // The link URL doesn't actually matter; we'll always just display the prefs pane if we get a click.
            [detailText addAttribute:NSLinkAttributeName value:[rec title] range:between];
            [detailText addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSUnderlineStyleSingle] range:between];
            [detailText addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:between];
        }
        
        [detailText deleteCharactersInRange:rightBracket];
        [detailText deleteCharactersInRange:leftBracket];
        [detailText endEditing];
    }
    
    return detailText;
}

- (void)setAvailableItems:(NSArray *)items;
{
    if (OFISEQUAL(items, _availableItems))
        return;
    
    [self willChangeValueForKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    [_availableItems release];
    _availableItems = [[NSArray alloc] initWithArray:items];
    [self didChangeValueForKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    
    /* The code below adjusts some ui state according to _availableItems, so we need to make sure the nib has been loaded. Our callers try not to even create us if our window won't be shown, so this bit of non-laziness shouldn't incur any extra cost. */
    [self window];
    
    /* The price column should be visible only if there's anything in it. */
    BOOL haveAnyPrices = NO;
    OFForEachInArray(_availableItems, OSUItem *, anItem, { if([anItem price] != nil) haveAnyPrices = YES; });
    [[_itemTableView tableColumnWithIdentifier:@"price"] setHidden:([_availableItems count] > 0 && !haveAnyPrices)];
    
    [self _resizeInterface:YES];
    
    /* Select the first available update */
    NSArray *nonIgnoredItems = [_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]];
    if ([nonIgnoredItems count] > 0) {
        [_availableItemController setSelectedObjects:@[nonIgnoredItems[0]]];
    } else {
        [_availableItemController setSelectedObjects:@[]];
    }
    
    [self _refreshSelectedItem:nil];
}

- (void)setCheckInProgress:(BOOL)yn
{
    if (yn == _checkInProgress)
        return;
    
    [self willChangeValueForKey:OSUAvailableUpdateControllerCheckInProgressBinding];
    _checkInProgress = yn;
    [self didChangeValueForKey:OSUAvailableUpdateControllerCheckInProgressBinding];
    [self _resizeInterface:NO];
    [self _refreshDefaultAction];
}

- (void)setSelectedItemIndexes:(NSIndexSet *)indexes;
{
    if (OFISEQUAL(indexes, _selectedItemIndexes))
        return;
    
    [self willChangeValueForKey:OSUAvailableUpdateControllerSelectedItemIndexesBinding];
    [_selectedItemIndexes release];
    _selectedItemIndexes = [indexes copy];
    [self didChangeValueForKey:OSUAvailableUpdateControllerSelectedItemIndexesBinding];
    [self _refreshSelectedItem:nil];
}

- (IBAction)ignoreSelectedItem:(id)sender;
{
#if OSU_FULL
    OSUItem *anItem = [self selectedItem];
    if (!anItem)
        return;  // Shouldn't happen; button should be disabled.
    BOOL shouldIgnore = ![OSUPreferences itemIsIgnored:anItem];
    [OSUPreferences setItem:anItem isIgnored:shouldIgnore];
    
    // Deselect ignored items
    if (shouldIgnore) {
        [_availableItemController removeSelectedObjects:[NSArray arrayWithObject:anItem]];
    }
    
    // If the user just ignored the last non-ignored item, then assume they're not interested in upgrading and close the window
    if (!_checkInProgress && [[_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]] count] == 0) {
        [[self window] performClose:nil];
    }
#else
    OBASSERT_NOT_REACHED("This code gets compiled when building from the workspace for MAS builds, but should never be linked/executed");
#endif
}

#define itemAlertPane_IgnoreOneTrackTag  2
#define itemAlertPane_IgnoreAllTracksTag 3

- (IBAction)ignoreCertainTracks:(id)sender;
{
    NSInteger tag = [sender tag];
    
    NSArray *newValue = nil;
    
    if (tag == itemAlertPane_IgnoreOneTrackTag) {
        NSString *track = [[self selectedItem] track];
        if (![NSString isEmptyString:track]) {
            NSMutableSet *newTracks = [NSMutableSet set];
            OFForEachInArray([OSUItem elaboratedTracks:[OSUPreferences visibleTracks]], NSString *, aTrack, {
                if ([NSString isEmptyString:aTrack])
                    continue;
                enum OSUTrackComparison order = [OSUItem compareTrack:aTrack toTrack:track];
                if (!(order == OSUTrackOrderedSame || order == OSUTrackLessStable))
                    [newTracks addObject:aTrack];
                else
                    NSLog(@"dropping track \"%@\" <= \"%@\"", aTrack, track);
            });
            newValue = [OSUItem dominantTracks:newTracks];
        }
    } else if (tag == itemAlertPane_IgnoreAllTracksTag) {
        newValue = [NSArray array];
    }
    
    if (!newValue) {
        // Shouldn't happen.
        OBASSERT_NOT_REACHED("unexpected tag or state");
        return;
    }
    
    [OSUPreferences setVisibleTracks:newValue];
    
    // Deselect ignored items
    OSUItem *curSelection = [self selectedItem];
    if (curSelection && [curSelection isIgnored])
        [_availableItemController removeSelectedObjects:[NSArray arrayWithObject:curSelection]];
    
    // If the user just ignored the last non-ignored item, then assume they're not interested in upgrading and close the window
    if (!_checkInProgress && [[_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]] count] == 0) {
        [[self window] performClose:nil];
    }
}

- (OSUItem *)selectedItem;
{
    return _selectedItem;
}

+ (NSSet *)keyPathsForValuesAffectingIgnoreTrackItemTitle;
{
    return [NSSet setWithObject:OSUAvailableUpdateControllerSelectedItemBinding];
}

- (NSString *)ignoreTrackItemTitle
{
    OSUItem *it = [self selectedItem];
    if (!it)
        return nil;
    NSString *track = [it track];
    if ([NSString isEmptyString:track])
        return nil;
    
    NSDictionary *localizations = [OSUItem informationForTrack:track];
    NSString *trackDisplayName = [localizations objectForKey:@"name"];
    if (!trackDisplayName)
        trackDisplayName = [track capitalizedString];
    
    return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Ignore \\U201C%@\\U201D Releases", @"OmniSoftwareUpdate", OMNI_BUNDLE, "button title to allow user to stop being notified of releases on a particular track (eg, 'rc', 'beta', 'sneakypeek') - used in stability downgrade warning pane"), trackDisplayName];
}

#pragma mark -
#pragma mark WebView delegates

+ (BOOL)_isURL:(NSURL *)requestedURL onSamePageAsURL:(NSURL *)pageURL;
{
    NSURL *baseRequestedURL = [[[NSURL URLWithString:@"#" relativeToURL:requestedURL] absoluteURL] standardizedURL];
    NSURL *basePageURL = [[[NSURL URLWithString:@"#" relativeToURL:pageURL] absoluteURL] standardizedURL];
    return baseRequestedURL != nil && basePageURL != nil && [baseRequestedURL isEqual:basePageURL];
}

- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener;
{
    WebNavigationType navigation = [actionInformation intForKey:WebActionNavigationTypeKey defaultValue:WebNavigationTypeOther];
    switch (navigation) {
        default:
            [listener use];
            break;
        case WebNavigationTypeLinkClicked:
            if ([OSUAvailableUpdateController _isURL:[request URL] onSamePageAsURL:[[[frame dataSource] initialRequest] URL]]) {
                [listener use];
            } else {
                [listener ignore];
                [[NSWorkspace sharedWorkspace] openURL:[request URL]];
            }
            break;
    }
}

- (void)webView:(WebView *)webView decidePolicyForNewWindowAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request
   newFrameName:(NSString *)frameName
decisionListener:(id<WebPolicyDecisionListener>)listener;
{
    [listener ignore];
    [[NSWorkspace sharedWorkspace] openURL:[request URL]];
}

- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame;
{
    [self setValue:[NSNumber numberWithBool:YES] forKey:OSUAvailableUpdateControllerLoadingReleaseNotesBinding];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
{
    [self setValue:[NSNumber numberWithBool:NO] forKey:OSUAvailableUpdateControllerLoadingReleaseNotesBinding];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
{
    [self setValue:[NSNumber numberWithBool:NO] forKey:OSUAvailableUpdateControllerLoadingReleaseNotesBinding];

    if ([error hasUnderlyingErrorDomain:NSURLErrorDomain code:NSURLErrorCancelled])
        return;

    NSLog(@"Load failed for software update release notes: %@", [error toPropertyList]);
}

#pragma mark OSUTextField / NSTextView delegates

- (BOOL)textView:(NSTextView *)aView clickedOnLink:(id)aLink atIndex:(NSUInteger)idx
{
    // The only time we're interested in this is when the user clicks on the hyperlink we set up in -details
    OAPreferenceClientRecord *rec = [OAPreferenceController clientRecordWithIdentifier:[OMNI_BUNDLE_IDENTIFIER stringByAppendingString:@".preferences"]];
    if (!rec)
        return NO;
    OAPreferenceController *prefController = [OAPreferenceController sharedPreferenceController];
    [prefController setCurrentClientRecord:rec];
    [prefController showPreferencesPanel:aView];
    return YES;
}

#pragma mark NSSplitView delegates

static CGFloat minHeightOfItemTableView(NSTableView *itemTableView)
{
    // Note- This is returning bounds coordinates but the caller is using it as frame coordinates.  Unlikely this will be scaled relative to its superview, but still...
    CGFloat rowsHigh = [itemTableView numberOfRows];
    // We want at least 3 rows shown so that the scroller doesn't get smooshed.
    // We include a half-row to make it super extra obvious that there's something there if you scroll down.
    if (rowsHigh > 3)
        rowsHigh = (CGFloat)3.5;
    if (rowsHigh < 1)
        rowsHigh = 1;
    return rowsHigh * ([itemTableView rowHeight] + [itemTableView intercellSpacing].height);
}

static CGFloat minHeightOfItemTableScrollView(NSTableView *itemTableView)
{
    NSScrollView *scrollView = [itemTableView enclosingScrollView];
    NSSize contentSize;
    contentSize.width = 100;
    contentSize.height = ceil(minHeightOfItemTableView(itemTableView));
    
    NSSize frame = [NSScrollView frameSizeForContentSize:contentSize hasHorizontalScroller:[scrollView hasHorizontalScroller] hasVerticalScroller:[scrollView hasVerticalScroller] borderType:[scrollView borderType]];
    return frame.height;
}

- (void)_resizeSplitViewViewsWithTablePaneExistingHeight:(CGFloat)height;
{
    // Give/take all the side on the web view side, leaving the item list the same height as it was.  Also, constrain the release list height to a minimum value.
    NSRect bounds = [_itemsAndReleaseNotesSplitView bounds];
    
    CGFloat dividerHeight = [_itemsAndReleaseNotesSplitView dividerThickness];
    
    NSScrollView *scrollView = [_itemTableView enclosingScrollView];
    NSView *borderView = [_itemsAndReleaseNotesSplitView subviewContainingView:_releaseNotesWebView];
    if (!borderView) {
        // We're in the middle of rejiggering subviews. Punt.
        [_itemsAndReleaseNotesSplitView adjustSubviews];
        return;
    }
    
    NSRect scrollViewFrame = [scrollView frame];
    NSRect borderViewFrame = [borderView frame];
    
    scrollViewFrame.origin = bounds.origin;
    scrollViewFrame.size.height = MAX(height, minHeightOfItemTableScrollView(_itemTableView));
    scrollViewFrame.size.width = NSWidth(bounds);
    
    borderViewFrame.origin.x = NSMinX(bounds);
    borderViewFrame.origin.y = NSMaxY(scrollViewFrame) + dividerHeight;
    borderViewFrame.size.width = NSWidth(bounds);
    borderViewFrame.size.height = MAX(0.0f, NSMaxY(bounds) - borderViewFrame.origin.y);
    
    [scrollView setFrame:scrollViewFrame];
    [borderView setFrame:borderViewFrame];
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex;
{
    CGFloat myMinimum = proposedMinimumPosition;
    if (dividerIndex == 0)
        myMinimum = minHeightOfItemTableScrollView(_itemTableView);
    // NSLog(@"splitView constrainMinCoordinate:%.1f ofSubviewAt:%d  -->  %.1f", proposedMinimumPosition, (int)dividerIndex, MAX(myMinimum, proposedMinimumPosition));
    return MAX(myMinimum, proposedMinimumPosition);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex;
{
    CGFloat constrained;
    
    if (dividerIndex == 0) {
        CGFloat minimumHeight = 10; // Don't let them completely hide the release-notes pane
        if (_displayingWarningPane)
            minimumHeight += NSHeight([_itemAlertPane frame]);
        constrained = proposedMaximumPosition - minimumHeight;
    } else {
        constrained = proposedMaximumPosition;
    }
    // NSLog(@"splitView constrainMaxCoordinate:%.1f ofSubviewAt:%d  -->  %.1f", proposedMaximumPosition, (int)dividerIndex, constrained);
    return constrained;
}

/*
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex;
{
    if (dividerIndex == 0)
        return MAX(proposedPosition, minHeightOfItemTableScrollView(_itemTableView));
    return proposedPosition;
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize;
{
    CGFloat tableViewHeight = NSHeight([[_itemTableView enclosingScrollView] frame]);
    [self _resizeSplitViewViewsWithTablePaneExistingHeight:tableViewHeight];
}
*/

#pragma mark NSTableView Delegate

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell_ forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    NSTextFieldCell *cell = cell_;
    
    if (tableView == _itemTableView && [[tableColumn identifier] isEqualToString:@"price"]) {
        OSUItem *rowItem = [[_availableItemController arrangedObjects] objectAtIndex:row];
        NSString *priceString = [rowItem priceString];
        if (priceString != nil) {
            NSAttributedString *s = [[NSAttributedString alloc] initWithString:[rowItem priceString] attributes:[rowItem priceAttributesForStyle:[cell backgroundStyle]]];
            [cell setAttributedStringValue:s];
            [s release];
        } else {
            [cell setStringValue:@""];
        }
    }
}

#pragma mark -
#pragma mark Private

#define INTER_ELEMENT_GAP (12.0f)

#define TEXT_BUTTONS_GAP (6.0f)

- (void)_resizeInterface:(BOOL)resetDividerPosition;
{
    if (![self isWindowLoaded])
        return;
    
    // We have a flipped container view for all these views.  This makes layout easier, but it also means that when we first load the nib, the views will be upside down (since IB archives the view's frames as if the container were not flipped).  So, we have to manually stack the views.
    CGFloat yOffset = 0;
    
    NSRect oldSplitViewFrame = [_itemsAndReleaseNotesSplitView frame];
    NSRect oldAppIconImageFrame = [_appIconImageView frame];
    NSRect containerBounds = [[_appIconImageView superview] bounds];
    
    // Icon on the left
    NSRect newAppIconImageFrame = (NSRect){NSMakePoint(oldAppIconImageFrame.origin.x, 0), [_appIconImageView frame].size};
    [_appIconImageView setFrame:newAppIconImageFrame];
    
    // Progress indicator
    NSRect spinnerFrame = [_spinner frame];
    // Put its centerline on the same line as the app icon
    spinnerFrame.origin.y = newAppIconImageFrame.origin.y - (spinnerFrame.size.height - newAppIconImageFrame.size.height)/2;
    spinnerFrame.origin.x = NSMaxX(containerBounds) - (CGFloat)1.5 * NSWidth(spinnerFrame);
    spinnerFrame = [[_spinner superview] centerScanRect:spinnerFrame];
    [_spinner setFrame:spinnerFrame];
    
    NSRect oldTitleFrame = [_titleTextField frame];
    NSRect oldMessageFrame = [_messageTextField frame];

    // Title
    NSRect newTitleFrame;
    newTitleFrame.origin.x = oldTitleFrame.origin.x;
    newTitleFrame.origin.y = yOffset;
    newTitleFrame.size.height = oldTitleFrame.size.height;
    newTitleFrame.size.width = NSMaxX(spinnerFrame) - NSMinX(oldTitleFrame);
    [_titleTextField setFrame:newTitleFrame];
    newTitleFrame.size = [_titleTextField desiredFrameSize:NSViewHeightSizable];
    [_titleTextField setFrame:newTitleFrame];
    yOffset = NSMaxY(newTitleFrame) + INTER_ELEMENT_GAP;

    // Message
    NSRect newMessageFrame;
    newMessageFrame = oldMessageFrame;
    if ([_spinner isHiddenOrHasHiddenAncestor])
        newMessageFrame.size.width = NSMaxX(spinnerFrame) - NSMinX(oldMessageFrame);
    else
        newMessageFrame.size.width = NSMinX(spinnerFrame) - INTER_ELEMENT_GAP - NSMinX(oldMessageFrame);
    [_messageTextField setFrameSize:newMessageFrame.size];
    newMessageFrame.size = [_messageTextField desiredFrameSize:NSViewHeightSizable];
    newMessageFrame.origin.y = yOffset;
    [_messageTextField setFrame:newMessageFrame];
    yOffset = MAX(NSMaxY(newAppIconImageFrame), NSMaxY(newMessageFrame)) + INTER_ELEMENT_GAP;

    CGFloat oldTablePaneHeight = [[_itemTableView enclosingScrollView] frame].size.height;
    
    // Splitview -- any extra space gets taking/given here.  We're assuming that the delta between the minimum window size and the growth of the other fields is small enough to make this reasonable.  We could adjust the window size, but we want to allow the user to set it via the frame autosave.  If this becomes a problem, we could look at the resulting size for the split view and it it is too small, force the window to be bigger.        
    NSRect newSplitViewFrame = oldSplitViewFrame;
    newSplitViewFrame.origin.y = yOffset;
    newSplitViewFrame.size.height = NSMaxY([[_itemsAndReleaseNotesSplitView superview] bounds]) - yOffset;
    [_itemsAndReleaseNotesSplitView setFrame:newSplitViewFrame];
    
    [[_messageTextField superview] setNeedsDisplay:YES];
    
    if (!_selectedItem)
        _displayingWarningPane = NO;
    if (_displayingWarningPane) {
        NSView *interView = [_itemsAndReleaseNotesSplitView subviewContainingView:_itemAlertPane];
        NSView *borderView = [interView subviewContainingView:_releaseNotesWebView];
        NSButton *ignoreMostTracks = [_itemAlertPane viewWithTag:itemAlertPane_IgnoreAllTracksTag];
        
        if (!interView || !borderView) {
            NSLog(@"Can't find child of splitview.");
            return;
        }
        
        NSRect alertFrame = [_itemAlertPane frame];
        NSRect notesFrame = [borderView frame];
        NSRect boundary = [interView bounds];
        alertFrame.origin = boundary.origin;
        alertFrame.size.width = boundary.size.width;
        
        [_itemAlertPane setFrame:alertFrame]; // Resize the alert pane, and therefore its content views
        NSRect textFrame = [_itemAlertMessage frame];
        NSSize textFullSize = [_itemAlertMessage desiredFrameSize:NSViewHeightSizable];
        // Consider adjusting the alert pane to make the message text meet the tops of the buttons
        NSRect buttonFrame = [ignoreMostTracks frame];
        CGFloat newAlertPaneHeight = ceil(alertFrame.size.height + ( NSMaxY(buttonFrame) - floor(NSMaxY(textFrame) - textFullSize.height- TEXT_BUTTONS_GAP) ));
        if(newAlertPaneHeight < _minimumAlertPaneHeight)
            newAlertPaneHeight = _minimumAlertPaneHeight;
        if (newAlertPaneHeight != alertFrame.size.height) {
            alertFrame.size.height = newAlertPaneHeight;
            [_itemAlertPane setFrame:alertFrame];
        }
        
        notesFrame.origin.x = boundary.origin.x;
        notesFrame.origin.y = NSMaxY(alertFrame);
        notesFrame.size.width = boundary.size.width;
        notesFrame.size.height = NSMaxY(boundary) - notesFrame.origin.y;
        
        [borderView setFrame:notesFrame];
        
        [_itemAlertPane setHidden:NO];
        
        NSButton *ignoreSelectedTrack = [_itemAlertPane viewWithTag:itemAlertPane_IgnoreOneTrackTag];
        if (ignoreSelectedTrack) {
            NSRect oldFrame = [ignoreSelectedTrack frame];
            [ignoreSelectedTrack sizeToFit];
            NSRect newFrame = [ignoreSelectedTrack frame];
            if (fabs(NSMaxX(oldFrame) - NSMaxX(newFrame)) > 0.1) {
                newFrame.origin.x = NSMaxX(oldFrame) - newFrame.size.width;
                [[ignoreSelectedTrack superview] centerScanRect:newFrame];
                [ignoreSelectedTrack setFrame:newFrame];
            }
        }
    } else {
        [_itemAlertPane setHidden:YES];
        NSView *interView = [_releaseNotesWebView ancestorSharedWithView:_itemAlertPane];
        NSView *borderView = [interView subviewContainingView:_releaseNotesWebView];
        [borderView setFrame:[interView bounds]];
    }
    
    if (resetDividerPosition) {
        // Start with the splitter as tight up against the limit as possible (3 rows currently)
        [self _resizeSplitViewViewsWithTablePaneExistingHeight:0.0f];
    } else {
        [self _resizeSplitViewViewsWithTablePaneExistingHeight:oldTablePaneHeight];
    }
    
    // Make room for title of install/info button
    {
        NSRect oldFrame = [_installButton frame];
        [_installButton sizeToFit];
        NSRect newFrame = [_installButton frame];
        newFrame.size.width += _buttonExtraSize.width;
        newFrame.size.height += _buttonExtraSize.height;
        newFrame.origin.x = NSMaxX(oldFrame) - newFrame.size.width;
        [_installButton setFrame:newFrame];
        CGFloat delta = newFrame.origin.x - oldFrame.origin.x;
        if (fabs(delta) > 0.25) {
            NSRect oldCancelFrame = [_cancelButton frame];
            oldCancelFrame.origin.x += delta;
            [_cancelButton setFrameOrigin:oldCancelFrame.origin];
            [_cancelButton setNeedsDisplay:YES];
        }
        [_installButton setNeedsDisplay:YES];
    }
}

- (void)_refreshSelectedItem:(NSNotification *)dummyNotification;
{
    OSUItem *item = nil;
    if ([_selectedItemIndexes count] == 1) {
        NSArray *visibleItems = [_availableItemController arrangedObjects];
        NSUInteger selectedIndex = [_selectedItemIndexes firstIndex];
        if (selectedIndex < [visibleItems count])
            item = [visibleItems objectAtIndex:selectedIndex];
    }
    
    [self setValue:item forKey:OSUAvailableUpdateControllerSelectedItemBinding];
    
    BOOL shouldResizeUI = NO;
    
    BOOL shouldDisplayStabilityWarning;
    if (!item)
        shouldDisplayStabilityWarning = NO;
    else {
        enum OSUTrackComparison c = [OSUItem compareTrack:[item track] toTrack:[[OSUChecker sharedUpdateChecker] applicationTrack]];
        if (c == OSUTrackLessStable || c == OSUTrackNotOrdered)
            shouldDisplayStabilityWarning = YES;
        else
            shouldDisplayStabilityWarning = NO;
    }
    
    if (shouldDisplayStabilityWarning) {
        NSDictionary *msgs = [OSUItem informationForTrack:[[self selectedItem] track]];
        NSString *msgText = [msgs objectForKey:@"warning"];
        if (!msgText)
            msgText = NSLocalizedStringWithDefaultValue(@"Stability downgrade warning",
                                                        @"OmniSoftwareUpdate", OMNI_BUNDLE,
                                                        @"The version you have selected may be less stable than the version you are running.",
                                                        "title of new versions available dialog, when in the process of checking for updates - text is name of application - only used if this downgrade does not have a more specific warning message available");
        if (![[_itemAlertMessage stringValue] isEqual:msgText]) {
            [_itemAlertMessage setStringValue:msgText];
            shouldResizeUI = YES;
        }
    }
    
    if (shouldDisplayStabilityWarning != _displayingWarningPane) {
        _displayingWarningPane = shouldDisplayStabilityWarning;
        shouldResizeUI = YES;
    }
    
    NSString *installButtonTitle;
    SEL installButtonAction;
    BOOL installButtonEnable;
    if (item && ![item downloadURL] && ![NSString isEmptyString:[item sourceLocation]]) {
        installButtonTitle = NSLocalizedStringWithDefaultValue(@"More Information...",
                                                               @"OmniSoftwareUpdate", OMNI_BUNDLE,
                                                               @"More Information\\U2026",
                                                               "button title - go to a webpage with more information about the selected update, from which it can probably be downloaded");
        installButtonAction = @selector(showMoreInformation:);
        installButtonEnable = YES;
    } else {
        installButtonTitle = NSLocalizedStringWithDefaultValue(@"Install",
                                                               @"OmniSoftwareUpdate", OMNI_BUNDLE,
                                                               @"Install",
                                                               "button title - (download and) install the selected update");
        installButtonAction = @selector(installSelectedItem:);
        installButtonEnable = ( [item downloadURL] != nil )? YES : NO;
    }
    if (![installButtonTitle isEqual:[_installButton title]] || !sel_isEqual(installButtonAction, [_installButton action])) {
        [_installButton setTitle:installButtonTitle];
        [_installButton setAction:installButtonAction];
        shouldResizeUI = YES;
    }
    [_installButton setEnabled:installButtonEnable];
    
    if (shouldResizeUI)
        [self _resizeInterface:NO];
    
    [self _refreshDefaultAction];
    [self _loadReleaseNotes];
}

- (void)_refreshDefaultAction
{
    if (![self isWindowLoaded])
        return;
    
    NSArray *visibleItems = [_availableItemController arrangedObjects];
    
    // The cancel button's key equivalent is set to ESC in the nib, but making it be the default button cell (as happens in some branches of this if) clobbers the key equivalent. So we set it back in the other branches.
    // (Note that ESC is also documented to catch cmd-period, as a special case in NSWindow.)
    
    if ([visibleItems count] == 0 && !_checkInProgress) {
        [[self window] setDefaultButtonCell:[_cancelButton cell]];
    } else if (_displayingWarningPane && !sel_isEqual([_installButton action], @selector(showMoreInformation:))) {
        [[self window] setDefaultButtonCell:nil];
        [_cancelButton setKeyEquivalent:@"\x1B"];
    } else {
        [[self window] setDefaultButtonCell:[_installButton cell]];
        [_cancelButton setKeyEquivalent:@"\x1B"];
    }
}

- (void)_loadReleaseNotes;
{
    if (![self isWindowLoaded])
        return;

    if (!_selectedItem) {
         // Clear out the web view
         [[_releaseNotesWebView mainFrame] loadHTMLString:@"" baseURL:nil];
        return;
    }
    
    NSURL *releaseNotesURL = [_selectedItem releaseNotesURL];
    if (OFURLEqualsURL([[[[_releaseNotesWebView mainFrame] provisionalDataSource] initialRequest] URL], releaseNotesURL))
        return;

    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:releaseNotesURL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:120.0];
    [[_releaseNotesWebView mainFrame] loadRequest:request];
    [request release];
}

- (void)_adjustViewLayout:(NSNotification *)note
{
    [self _resizeInterface:NO];
}

@end


