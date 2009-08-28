// Copyright 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUAvailableUpdateController.h"

#import "OSUChecker.h"
#import "OSUItem.h"
#import "OSUController.h"
#import "OSUPreferences.h"

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/OFNull.h> // OFISEQUAL
#import <OmniAppKit/NSTextField-OAExtensions.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniAppKit/OAPreferenceClientRecord.h>
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


RCS_ID("$Id$");

@interface OSUAvailableUpdateController (Private)
- (void)_resizeInterface:(BOOL)resetDividerPosition;
- (void)_refreshSelectedItem;
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
    return [NSSet setWithObjects:OSUAvailableUpdateControllerAvailableItemsBinding, OSUAvailableUpdateControllerCheckInProgressBinding, nil];
}

- (NSString *)message;
{
    NSArray *visibleItems = [_availableItemController arrangedObjects];
    unsigned int count = [visibleItems count];
    
    NSString *format; // All format strings should take the app name and then the update count.
    switch (count) {
        case 0:
            if ([[self valueForKey:OSUAvailableUpdateControllerCheckInProgressBinding] boolValue])
                format = NSLocalizedStringFromTableInBundle(@"Checking for %1$@ updates.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when in the process of checking for updates - text is name of application");
            else
                format = NSLocalizedStringFromTableInBundle(@"%1$@ is up to date.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when no updates are available - text is name of application");
            break;
        case 1:
            format = NSLocalizedStringFromTableInBundle(@"There is an update available for %1$@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when one update is available - text is name of application");
            break;
        default:
            format = NSLocalizedStringFromTableInBundle(@"There are %2$d updates available for %1$@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when multiple updates are available - text is name of application");
            break;

    }
    
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];

    return [NSString stringWithFormat:format, appName, count];
}

+ (NSSet *)keyPathsForValuesAffectingDetails;
{
    return [NSSet setWithObjects:OSUAvailableUpdateControllerAvailableItemsBinding, nil];
}

- (NSAttributedString *)details;
{
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];

    NSString *name = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];
    
    // If we are _not_ on the release track, show more detailed release information.  The marketing version might not get updated on every build on other tracks.
    NSString *version = [NSString stringWithFormat:@"%@ %@", name, [bundleInfo objectForKey:@"CFBundleShortVersionString"]];
    
    if (![[OSUChecker sharedUpdateChecker] applicationOnReleaseTrack]) {
        // Append the bundle version
        version = [version stringByAppendingFormat:@" (v%@)", [bundleInfo objectForKey:(NSString *)kCFBundleVersionKey]];
    }
    
    NSString *format;
    if ([[_availableItemController arrangedObjects] count])
        format = NSLocalizedStringFromTableInBundle(@"You are currently running %@.  If you're not ready to update now, you can use the [Update preference pane] to check for updates later or adjust the frequency of automatic checking.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "message of new versions available dialog");
    else
        format = NSLocalizedStringFromTableInBundle(@"You are currently running %@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "message of no updates are available dialog");
    
    NSMutableAttributedString *detailText = [[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:format, version]] autorelease];
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
    
    [self _resizeInterface:NO];
    
    /* In the special (but common) case that there's exactly one update available, and it's free, go ahead and select it by default */
    NSArray *nonIgnoredItems = [_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededOrIgnoredPredicate]];
    if ([nonIgnoredItems count] == 1) {
        OSUItem *theItem = [nonIgnoredItems objectAtIndex:0];
        if ([theItem isFree] && [theItem available] && ![theItem superseded])
            [_availableItemController setSelectedObjects:nonIgnoredItems];
    }
    
    [self _refreshSelectedItem];
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
    [self _refreshSelectedItem];
}

- (IBAction)ignoreSelectedItem:(id)sender;
{
    OSUItem *anItem = [self selectedItem];
    BOOL shouldIgnore = ![OSUPreferences itemIsIgnored:anItem];
    [OSUPreferences setItem:anItem isIgnored:shouldIgnore];
    
    // Deselect ignored items
    if (shouldIgnore) {
        [_availableItemController removeSelectedObjects:[NSArray arrayWithObject:anItem]];
    }
    
    // If the user just ignored the last non-ignored item, then assume they're not interested in upgrading and close the window
    if (!_checkInProgress && [[_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededOrIgnoredPredicate]] count] == 0) {
        [[self window] performClose:nil];
    }
}

- (OSUItem *)selectedItem;
{
    return _selectedItem;
}

#pragma mark -
#pragma mark WebView delegates

- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request
          frame:(WebFrame *)frame
decisionListener:(id<WebPolicyDecisionListener>)listener;
{
    WebNavigationType navigation = [actionInformation intForKey:WebActionNavigationTypeKey defaultValue:WebNavigationTypeOther];
    switch (navigation) {
        default:
            [listener use];
            break;
        case WebNavigationTypeLinkClicked:
            [listener ignore];
            [[NSWorkspace sharedWorkspace] openURL:[request URL]];
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
    [sender presentError:error];
}

#pragma mark -
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

#pragma mark -
#pragma mark NSSplitView delegates

static CGFloat minHeightOfItemTableView(NSTableView *itemTableView)
{
    // TODO: This is returning bounds coordinates but the caller is using it as frame coordinates.  Unlikely this will be scaled relative to its superview, but still...
    // We want at least 3 rows shown so that the scroller doesn't get smooshed.
    return 3 * ([itemTableView rowHeight] + [itemTableView intercellSpacing].height);
}

static CGFloat minHeightOfItemTableScrollView(NSTableView *itemTableView)
{
    NSScrollView *scrollView = [itemTableView enclosingScrollView];
    NSSize contentSize;
    contentSize.width = 100;
    contentSize.height = minHeightOfItemTableView(itemTableView);
    
    NSSize frame = [NSScrollView frameSizeForContentSize:contentSize hasHorizontalScroller:[scrollView hasHorizontalScroller] hasVerticalScroller:[scrollView hasVerticalScroller] borderType:[scrollView borderType]];
    return frame.height;
}

- (void)_resizeSplitViewViewsWithTableViewExistingHeight:(CGFloat)height;
{
    // Give/take all the side on the web view side, leaving the item list the same height as it was.  Also, constrain the release list height to a minimum value.
    NSRect bounds = [_itemsAndReleaseNotesSplitView bounds];
    
    CGFloat dividerHeight = [_itemsAndReleaseNotesSplitView dividerThickness];
    
    NSScrollView *scrollView = [_itemTableView enclosingScrollView];
    NSView *borderView = [_releaseNotesWebView superview];
    
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
    if (dividerIndex == 0)
        return MAX(proposedMinimumPosition, minHeightOfItemTableScrollView(_itemTableView));
    return proposedMinimumPosition;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex;
{
    if (dividerIndex == 0)
        return MAX(proposedPosition, minHeightOfItemTableScrollView(_itemTableView));
    
    return proposedPosition;
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize;
{
    CGFloat tableViewHeight = NSHeight([_itemTableView frame]);
    [self _resizeSplitViewViewsWithTableViewExistingHeight:tableViewHeight];
}

@end

@implementation OSUAvailableUpdateController (Private)

#define INTER_ELEMENT_GAP (12.0f)

- (void)_resizeInterface:(BOOL)resetDividerPosition;
{
    if (![self isWindowLoaded])
        return;
    
    // We have a flipped container view for all these views.  This makes layout easier, but it also means that when we first load the nib, the views will be upside down (since IB archives the view's frames as if the container were not flipped).  So, we have to manually stack the views.
    float yOffset = 0;
    
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
    spinnerFrame.origin.x = NSMaxX(containerBounds) - 1.5 * NSWidth(spinnerFrame);
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
    
    if (resetDividerPosition) {
        // Start with the splitter as tight up against the limit as possible (3 rows currently)
        [self _resizeSplitViewViewsWithTableViewExistingHeight:0.0f];
    } else {
        [self _resizeSplitViewViewsWithTableViewExistingHeight:oldTablePaneHeight];
    }
}

- (void)_refreshSelectedItem;
{
    OSUItem *item = nil;
    if ([_selectedItemIndexes count] == 1) {
        NSArray *visibleItems = [_availableItemController arrangedObjects];
        unsigned int selectedIndex = [_selectedItemIndexes firstIndex];
        if (selectedIndex < [visibleItems count])
            item = [visibleItems objectAtIndex:selectedIndex];
    }
    
    [self setValue:item forKey:OSUAvailableUpdateControllerSelectedItemBinding];
    [self _refreshDefaultAction];
    [self _loadReleaseNotes];
}

- (void)_refreshDefaultAction
{
    if (![self isWindowLoaded])
        return;
    
    NSArray *visibleItems = [_availableItemController arrangedObjects];

    if ([visibleItems count] == 0 && !_checkInProgress) {
        [[self window] setDefaultButtonCell:[_cancelButton cell]];
    } else {
        [[self window] setDefaultButtonCell:[_installButton cell]];
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
    if ([[[[[_releaseNotesWebView mainFrame] provisionalDataSource] initialRequest] URL] isEqualTo:releaseNotesURL])
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


