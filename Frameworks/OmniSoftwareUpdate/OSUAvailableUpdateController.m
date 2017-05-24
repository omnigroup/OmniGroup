// Copyright 2007-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUAvailableUpdateController.h"

#import <OmniSoftwareUpdate/OSUChecker.h>
#import "OSUItem.h"
#import <OmniSoftwareUpdate/OSUController.h>
#import "OSUPreferences-Items.h"
#import "OSUFlippedView.h"
#import "OSUThinBorderView.h"

@import OmniBase;
@import OmniFoundation;
@import OmniAppKit;

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


@interface OSUAvailableUpdateControllerMessageTextField : NSTextField
// This text field subclass is required in order to get the vertical resizing behavior we want. Which is nothing special — we just want it to be tall enough to accommodate its content, and no taller. I was unable to accomplish that with a standard text field and layout constraints:
// • When configured appropriately (set to wrap and to not use its initial layout width; no border or background), the field will size vertically as if it were the width it is in the nib: it will clip or leave extraneous vertical space if resized so that the content needs more or less vertical space. This is despite content hugging and compression settings which should cause it to grow vertically and prevent it from clipping vertically. (If the field's content is changed programmatically, it will again resize to the height needed to encompass its content at the field's width in the nib.)
// • When the field is configured to draw its border or a background color (which is inconvenient, but usually not a show-stopper), it *does* grow and shrink as appropriate. Indeed, it almost works correctly: unfortunately, when the string value (and thus length) is changed programmatically at runtime, the field does not resize to reflect this until some other action (such as resizing the window) forces a layout.
@end

@implementation OSUAvailableUpdateControllerMessageTextField

- (void)x_drawRect:(NSRect)rect;
{
    [super drawRect:rect];
    [[NSColor redColor] set];
    NSFrameRect(self.bounds);
}

- (void)setFrame:(NSRect)newValue;
{
    super.frame = newValue;
    // When a text field is not set to draw its background/border, it doesn't update its intrinsicContentSize as it resizes, so we have to tell it to do so.
    [self invalidateIntrinsicContentSize];
}

- (CGFloat)preferredMaxLayoutWidth;
{
    if (self.cell.wraps) {
        // If we're configured to prioritize minimizing vertical compression (vs horizontal compression), use the current bounds width as our preferred content width, so that we will grow/shrink vertically as appropriate for our content.
        NSLayoutPriority horizontalPriority = [self contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal];
        NSLayoutPriority verticalPriority = [self contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationVertical];
        if (verticalPriority >= horizontalPriority) {
            return self.bounds.size.width;
        }
    }
    
    return super.preferredMaxLayoutWidth;
}

@end


@interface OSUAvailableUpdateController ()

@property(nonatomic,strong) IBOutlet NSArrayController *availableItemController;
@property(nonatomic,strong) IBOutlet NSTextField *titleTextField;
@property(nonatomic,strong) IBOutlet NSTextField *messageTextField;
@property(nonatomic,strong) IBOutlet NSProgressIndicator *spinner;
@property(nonatomic,strong) IBOutlet NSTableView *itemTableView;
@property(nonatomic,strong) IBOutlet NSLayoutConstraint *itemTableViewHeightConstraint;
@property(nonatomic,strong) IBOutlet WebView *releaseNotesWebView;
@property(nonatomic,strong) IBOutlet NSImageView *appIconImageView;
@property(nonatomic,strong) IBOutlet NSButton *installButton;
@property(nonatomic,strong) IBOutlet NSButton *cancelButton;

@property(nonatomic,strong) IBOutlet OAConstraintBasedStackView *stackView;
@property(nonatomic,strong) IBOutlet NSView *statusView;
@property(nonatomic,strong) IBOutlet NSView *availableUpdatesView;
@property(nonatomic,strong) IBOutlet NSView *releaseNotesView;
@property(nonatomic,strong) IBOutlet NSView *actionButtonsView;
@property(nonatomic,strong) IBOutlet NSView *okButtonView;

@property(nonatomic,strong) IBOutlet NSView *itemAlertPane;
@property(nonatomic,strong) IBOutlet NSTextField *itemAlertMessage;

@property(nonatomic) BOOL loadingReleaseNotes;
@property(nonatomic) BOOL checkInProgress;
@property(nonatomic) BOOL lastCheckFailed;
@property(nonatomic) BOOL lastCheckExplicit;

- (void)_updateWindowLayout;
- (void)_refreshSelectedItem:(NSNotification *)dummyNotification;
- (void)_refreshDefaultAction;
- (void)_loadReleaseNotes;
@end

@implementation OSUAvailableUpdateController
{
    BOOL _displayingWarningPane;
    
    // KVC
    NSArray *_itemSortDescriptors;
    NSPredicate *_itemFilterPredicate;
    NSArray *_availableItems;
    NSIndexSet *_selectedItemIndexes;
    OSUItem *_selectedItem;
}

+ (OSUAvailableUpdateController *)availableUpdateController:(BOOL)shouldCreate;
{
    static OSUAvailableUpdateController *availableUpdateController = nil;
    if (!availableUpdateController && shouldCreate)
        availableUpdateController = [[self alloc] init];
    return availableUpdateController;
}

- (void)awakeFromNib;
{
    [super awakeFromNib];
    // The stack view's animation works by shrinking the individual subviews to zero height (as appropriate). The autoresizing-mask layout constraints for clip views (or at least those inside scroll views) conflict with this, so we need to turn it off. (And I can't figure out how to do that inside IB.)
    [[(NSScrollView *)self.availableUpdatesView contentView] setTranslatesAutoresizingMaskIntoConstraints:NO];
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
    
    __autoreleasing NSError *error = nil;
    if (![[OSUController sharedController] beginDownloadAndInstallFromPackageAtURL:downloadURL item:item error:&error])
        [[NSApplication sharedApplication] presentError:error];
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
    
    _itemFilterPredicate = [OSUItem availableAndNotSupersededPredicate];
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

    [self _updateWindowLayout];
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
        format = NSLocalizedStringFromTableInBundle(@"Checking for %1$@ updates…", @"OmniSoftwareUpdate", OMNI_BUNDLE, "title of new versions available dialog, when in the process of checking for updates - text is name of application");
        return [NSString stringWithFormat:format, appName];
    } else if (self.lastCheckFailed) {
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
    return [NSSet setWithObjects:OSUAvailableUpdateControllerAvailableItemsBinding, OSUAvailableUpdateControllerLastCheckUserInitiatedBinding, OSUAvailableUpdateControllerCheckInProgressBinding, nil];
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
    
    if (newerVersionsAvailable && !self.lastCheckExplicit) {
        format = NSLocalizedStringFromTableInBundle(@"If you're not ready to update now, you can use the [Update preference pane] to check for updates later or adjust the frequency of automatic checking.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "detail message of new versions available dialog, with [link] to preference pane");
        formatted = [[formatted stringByAppendingString:@"  "] stringByAppendingString:format];
    }
    
    NSMutableAttributedString *detailText = [[NSMutableAttributedString alloc] initWithString:formatted];
    [detailText addAttribute:NSFontAttributeName value:[NSFont messageFontOfSize:[NSFont smallSystemFontSize]] range:(NSRange){0, [detailText length]}];
    NSRange leftBracket = [[detailText string] rangeOfString:@"["];
    NSRange rightBracket = [[detailText string] rangeOfString:@"]"];
    if (leftBracket.length && rightBracket.length && leftBracket.location < rightBracket.location) {
        [detailText beginEditing];
        NSRange between;
        between.location = NSMaxRange(leftBracket);
        between.length = rightBracket.location - between.location;
        OAPreferenceClientRecord *rec = [OAPreferenceController clientRecordWithIdentifier:[[OMNI_BUNDLE bundleIdentifier] stringByAppendingString:@".preferences"]];
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

+ (NSSet *)keyPathsForValuesAffectingDismissButtonTitle;
{
    return [NSSet setWithObjects:OSUAvailableUpdateControllerCheckInProgressBinding, nil];
}

- (NSString *)dismissButtonTitle;
{
    if (self.checkInProgress) {
        return NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniSoftwareUpdate", OMNI_BUNDLE, "button title");
    }
    return OAOK();
}

- (void)setAvailableItems:(NSArray *)items;
{
    if (OFISEQUAL(items, _availableItems))
        return;
    
    [self willChangeValueForKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    if (items)
        _availableItems = [[NSArray alloc] initWithArray:items];
    else
        _availableItems = [[NSArray alloc] init];
    [self didChangeValueForKey:OSUAvailableUpdateControllerAvailableItemsBinding];
    
    /* The code below adjusts some ui state according to _availableItems, so we need to make sure the nib has been loaded. Our callers try not to even create us if our window won't be shown, so this bit of non-laziness shouldn't incur any extra cost. */
    (void)[self window];
    
    /* The price column should be visible only if there's anything in it. */
    BOOL haveAnyPrices = NO;
    OFForEachInArray(_availableItems, OSUItem *, anItem, { if([anItem price] != nil) haveAnyPrices = YES; });
    [[_itemTableView tableColumnWithIdentifier:@"price"] setHidden:([_availableItems count] > 0 && !haveAnyPrices)];
    
    [self _updateWindowLayout];
    
    /* Select the first available update */
    NSArray *nonIgnoredItems = [_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]];
    if ([nonIgnoredItems count] > 0) {
        [_availableItemController setSelectedObjects:@[nonIgnoredItems[0]]];
    } else {
        [_availableItemController setSelectedObjects:@[]];
    }
    
    [self _refreshSelectedItem:nil];
}

+ (NSSet *)keyPathsForValuesAffectingUpdatesAreAvailable;
{
    return [NSSet setWithObjects:OSUAvailableUpdateControllerAvailableItemsBinding, OSUAvailableUpdateControllerCheckInProgressBinding, nil];
}

- (BOOL)updatesAreAvailable;
{
    return (_availableItems.count > 0) && ![[self valueForKey:OSUAvailableUpdateControllerCheckInProgressBinding] boolValue];
}

- (void)setCheckInProgress:(BOOL)yn
{
    if (yn == _checkInProgress)
        return;
    
    [self willChangeValueForKey:OSUAvailableUpdateControllerCheckInProgressBinding];
    _checkInProgress = yn;
    [self didChangeValueForKey:OSUAvailableUpdateControllerCheckInProgressBinding];
    [self _updateWindowLayout];
    [self _refreshDefaultAction];
}

- (void)setSelectedItemIndexes:(NSIndexSet *)indexes;
{
    if (OFISEQUAL(indexes, _selectedItemIndexes))
        return;
    
    [self willChangeValueForKey:OSUAvailableUpdateControllerSelectedItemIndexesBinding];
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
    if (!self.checkInProgress && [[_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]] count] == 0) {
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
    if (!self.checkInProgress && [[_availableItems filteredArrayUsingPredicate:[OSUItem availableAndNotSupersededIgnoredOrOldPredicate]] count] == 0) {
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
    OAPreferenceClientRecord *rec = [OAPreferenceController clientRecordWithIdentifier:[[OMNI_BUNDLE bundleIdentifier] stringByAppendingString:@".preferences"]];
    if (!rec)
        return NO;
    OAPreferenceController *prefController = [OAPreferenceController sharedPreferenceController];
    [prefController setCurrentClientRecord:rec];
    [prefController showPreferencesPanel:aView];
    return YES;
}

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
        } else {
            [cell setStringValue:@""];
        }
    }
}

#pragma mark -
#pragma mark Private

- (NSArray *)_visibleStackedViews;
{
    NSMutableArray *views = [NSMutableArray array];
    [views addObject:self.statusView];
    if (self.updatesAreAvailable) {
        [views addObject:self.availableUpdatesView];
        [views addObject:self.releaseNotesView];
        [views addObject:self.actionButtonsView];
        if (_displayingWarningPane) {
            [views addObject:self.itemAlertPane];
        }
    } else {
        [views addObject:self.okButtonView];
    }
    return views;
}

- (void)_updateWindowLayout;
{
    if (![self isWindowLoaded])
        return;
    
    [self.stackView setUnhiddenSubviews:[self _visibleStackedViews] animated:YES];

    if (self.checkInProgress) {
        self.spinner.hidden = NO;
        [self.spinner startAnimation:nil];
    } else {
        self.spinner.hidden = YES;
        [self.spinner stopAnimation:nil];
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
    
    BOOL shouldUpdateLayout = NO;
    
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
        }
    }
    
    if (shouldDisplayStabilityWarning != _displayingWarningPane) {
        _displayingWarningPane = shouldDisplayStabilityWarning;
        shouldUpdateLayout = YES;
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
    }
    [_installButton setEnabled:installButtonEnable];
    
    if (shouldUpdateLayout)
        [self _updateWindowLayout];
    
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
    
    if ([visibleItems count] == 0 && !self.checkInProgress) {
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
}

@end


