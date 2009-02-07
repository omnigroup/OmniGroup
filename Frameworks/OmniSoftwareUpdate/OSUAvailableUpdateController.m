// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUAvailableUpdateController.h"

#import "OSUChecker.h"
#import "OSUItem.h"
#import "OSUController.h"

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/OFNull.h> // OFISEQUAL
#import <OmniAppKit/NSTextField-OAExtensions.h>
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
- (void)_resizeInterface;
- (void)_refreshSelectedItem;
- (void)_loadReleaseNotes;
@end

@implementation OSUAvailableUpdateController

+ (OSUAvailableUpdateController *)availableUpdateController;
{
    static OSUAvailableUpdateController *availableUpdateController = nil;
    if (!availableUpdateController)
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
    
    // Set the available items binding here, after all the UI has been loaded, so that the final value of -message isn't determined while are partially unarchived from nib.
    // Also have to poke the message binding since its value changes based on the available items in the controller we are setting up.
    // The nicer way to do this would probably be to split part of this class out into an NSArrayController subclass.
    [self willChangeValueForKey:OSUAvailableUpdateControllerMessageBinding];
    [_availableItemController bind:NSContentArrayBinding toObject:self withKeyPath:OSUAvailableUpdateControllerAvailableItemsBinding options:nil];
    [self didChangeValueForKey:OSUAvailableUpdateControllerMessageBinding];

    [self _resizeInterface];
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

+ (NSSet *)keyPathsForValuesAffectingValueForMessage;
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
                format = NSLocalizedStringFromTableInBundle(@"Checking for %1$@ updates.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when in the process of checking for updates");
            else
                format = NSLocalizedStringFromTableInBundle(@"%1$@ is up to date.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when no updates are available");
            break;
        case 1:
            format = NSLocalizedStringFromTableInBundle(@"There is an update available for %1$@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when one update is available");
            break;
        default:
            format = NSLocalizedStringFromTableInBundle(@"There are %2$d updates available for %1$@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when multiple updates are available");
            break;

    }
    
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];

    return [NSString stringWithFormat:format, appName, count];
}

- (NSString *)details;
{
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];

    NSString *name = [bundleInfo objectForKey:(NSString *)kCFBundleNameKey];
    
    // If we are _not_ on the release track, show more detailed release information.  The marketing version might not get updated on every build on other tracks.
    NSString *version = [NSString stringWithFormat:@"%@ %@", name, [bundleInfo objectForKey:@"CFBundleShortVersionString"]];
    
    if (![OSUChecker applicationOnReleaseTrack]) {
        // Append the bundle version
        version = [version stringByAppendingFormat:@" (v%@)", [bundleInfo objectForKey:(NSString *)kCFBundleVersionKey]];
    }
    
    NSString *format;
    if ([[_availableItemController arrangedObjects] count])
        format = NSLocalizedStringFromTableInBundle(@"You are currently running %@.  If you're not ready to update now, you can use the Update preference pane to check for updates later or adjust the frequency of automatic checking.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "message of new versions available dialog");
    else
        format = NSLocalizedStringFromTableInBundle(@"You are currently running %@.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "message of no updates are available dialog");

    return [NSString stringWithFormat:format, version];

}

- (void)setAvailableItems:(NSArray *)items;
{
    if (OFISEQUAL(items, _availableItems))
        return;
    
    [self willChangeValueForKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    [_availableItems release];
    _availableItems = [[NSArray alloc] initWithArray:items];
    [self didChangeValueForKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    
    [self _resizeInterface];
    [self _refreshSelectedItem];
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
#pragma mark NSSplitView delegates

static float minHeightOfItemTableView(NSTableView *itemTableView)
{
    // TODO: This is returning bounds coordinates but the caller is using it as frame coordinates.  Unlikely this will be scaled relative to its superview, but still...
    // We want at least 3 rows shown so that the scroller doesn't get smooshed.
    return 3 * ([itemTableView rowHeight] + [itemTableView intercellSpacing].height);
}

static float minHeightOfItemTableScrollView(NSTableView *itemTableView)
{
    NSScrollView *scrollView = [itemTableView enclosingScrollView];
    float height = minHeightOfItemTableView(itemTableView);
    
    NSSize frame = [NSScrollView frameSizeForContentSize:NSMakeSize(100.0, height) hasHorizontalScroller:[scrollView hasHorizontalScroller] hasVerticalScroller:[scrollView hasVerticalScroller] borderType:[scrollView borderType]];
    return frame.height;
}

- (void)_resizeSplitViewViewsWithTableViewExistingHeight:(float)height;
{
    // Give/take all the side on the web view side, leaving the item list the same height as it was.  Also, constrain the release list height to a minimum value.
    NSRect bounds = [_itemsAndReleaseNotesSplitView bounds];
    
    float dividerHeight = [_itemsAndReleaseNotesSplitView dividerThickness];
    
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
    float tableViewHeight = NSHeight([_itemTableView frame]);
    [self _resizeSplitViewViewsWithTableViewExistingHeight:tableViewHeight];
}

@end

@implementation OSUAvailableUpdateController (Private)

#define INTER_ELEMENT_GAP (12.0f)

- (void)_resizeInterface;
{
    if (![self isWindowLoaded])
        return;
    
    // We have a flipped container view for all these views.  This makes layout easier, but it also means that when we first load the nib, the views will be upside down (since IB archives the view's frames as if the container were not flipped).  So, we have to manually stack the views.
    float yOffset = 0;
    
    //NSRect oldTitleFrame = [_titleTextField frame];
    NSRect oldMessageFrame = [_messageTextField frame];
    NSRect oldSplitViewFrame = [_itemsAndReleaseNotesSplitView frame];
    NSRect oldAppIconImageFrame = [_appIconImageView frame];

    // Title
    [_titleTextField sizeToFitVertically];
    NSRect newTitleFrame = [_titleTextField frame];
    newTitleFrame.origin.y = yOffset;
    [_titleTextField setFrame:newTitleFrame];
    yOffset = NSMaxY(newTitleFrame) + INTER_ELEMENT_GAP;

    NSRect newAppIconImageFrame = (NSRect){NSMakePoint(oldAppIconImageFrame.origin.x, 0), [_appIconImageView frame].size};
    [_appIconImageView setFrame:newAppIconImageFrame];

    // Message
    [_messageTextField sizeToFitVertically];
    NSRect newMessageFrame = (NSRect){NSMakePoint(oldMessageFrame.origin.x, yOffset), [_messageTextField frame].size};
    [_messageTextField setFrame:newMessageFrame];
    yOffset = MAX(NSMaxY(newAppIconImageFrame), NSMaxY(newMessageFrame)) + INTER_ELEMENT_GAP;

    // Splitview -- any extra space gets taking/given here.  We're assuming that the delta between the minimum window size and the growth of the other fields is small enough to make this reasonable.  We could adjust the window size, but we want to allow the user to set it via the frame autosave.  If this becomes a problem, we could look at the resulting size for the split view and it it is too small, force the window to be bigger.        
    NSRect newSplitViewFrame = oldSplitViewFrame;
    newSplitViewFrame.origin.y = yOffset;
    newSplitViewFrame.size.height = NSMaxY([[_itemsAndReleaseNotesSplitView superview] bounds]) - yOffset;
    [_itemsAndReleaseNotesSplitView setFrame:newSplitViewFrame];
    
    // Start with the splitter as tight up against the limit as possible (3 rows currently)
    [self _resizeSplitViewViewsWithTableViewExistingHeight:0.0f];
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
    [self _loadReleaseNotes];
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

@end


