// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentConflictResolutionViewController.h"

#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIGradientView.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/OUIDocumentConflictResolutionViewControllerDelegate.h>

#import "OUIDocument-Internal.h"
#import "OUIDocumentConflictResolutionTableViewCell.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_VERSIONS(format, ...) NSLog(@"FILE VERSION: " format, ## __VA_ARGS__)
    #define DEBUG_VERSIONS_ENABLED 1
#else
    #define DEBUG_VERSIONS(format, ...)
    #define DEBUG_VERSIONS_ENABLED 0
#endif

@interface OUIDocumentConflictResolutionViewController () <NSFilePresenter>

@property(nonatomic,retain) IBOutlet UIToolbar *toolbar;
@property(nonatomic,retain) IBOutlet UIImageView *instructionsBackgroundImageView;
@property(nonatomic,retain) IBOutlet UILabel *instructionsTextLabel;
@property(nonatomic,retain) IBOutlet UITableView *tableView;

- (IBAction)cancel:(id)sender;
- (IBAction)keep:(id)sender;

- (void)_reloadVersions;
- (void)_cancelWhenNoConflictExists;
- (void)_documentPreviewsUpdatedForFileItemNotification:(NSNotification *)note;
- (void)_updateToolbar;

@end

@implementation OUIDocumentConflictResolutionViewController
{
    OFSDocumentStore *_documentStore;
    OFSDocumentStoreFileItem *_fileItem;
    
    // We want our -presentedItemURL to be under the our control for changing when we get NSFilePresenter methods (and maybe we'll just cancel ourselves). We don't want it to change out from under us if the file item hears about a presenter notification.
    NSURL *_fileURL;
    
    NSArray *_fileVersions;
    
    NSOperationQueue *_notificationQueue;
}

@synthesize fileItem = _fileItem;
@synthesize delegate = _nonretained_delegate;

@synthesize toolbar = _toolbar;
@synthesize instructionsBackgroundImageView = _instructionsBackgroundImageView;
@synthesize instructionsTextLabel = _instructionsTextLabel;
@synthesize tableView = _tableView;

- (void)_reloadVersions;
{
    [_fileVersions release];
    
    NSMutableArray *fileVersions = [NSMutableArray arrayWithObjects:[NSFileVersion currentVersionOfItemAtURL:_fileURL], nil];
    OBASSERT([fileVersions count] == 1);
    
    // TODO: Sort the conflict versions by their modification date (newest first)?
    // We depend elsewhere on the current version being first, though (which typically should be the newest version anyway).
    [fileVersions addObjectsFromArray:[NSFileVersion unresolvedConflictVersionsOfItemAtURL:_fileURL]];
    
    _fileVersions = [fileVersions copy];
    
#if DEBUG_VERSIONS_ENABLED
    DEBUG_VERSIONS(@"Resolving conflict between versions:");
    for (NSFileVersion *fileVersion in _fileVersions) {
        DEBUG_VERSIONS(@"  id:%@ url:%@ name:%@ computer:%@ date:%@ conflict:%d", fileVersion.persistentIdentifier, fileVersion.URL, fileVersion.localizedName, fileVersion.localizedNameOfSavingComputer, fileVersion.modificationDate, fileVersion.conflict);
    }
#endif

    [_tableView reloadData];
}

- (void)_cancelWhenNoConflictExists;
{
    if ([_fileVersions count] <= 1)
        // The conflict has probably been resolved on another device
        [self cancel:nil];
}

- initWithDocumentStore:(OFSDocumentStore *)documentStore fileItem:(OFSDocumentStoreFileItem *)fileItem delegate:(id <OUIDocumentConflictResolutionViewControllerDelegate>)delegate;
{
    if (!(self = [super initWithNibName:@"OUIDocumentConflictResolutionViewController" bundle:nil]))
        return nil;
        
    _documentStore = [documentStore retain];
    _fileItem = [fileItem retain];
    _nonretained_delegate = delegate;
    
    _fileURL = [_fileItem.fileURL copy];
    
    [self _reloadVersions];
    
    // Can't call cancel if there are no conflicts here, which there can be in some cases with crazy NSMetadataQuery results (which will hopefully sort themselves out).
    if ([_fileVersions count] <= 1) {
        [self release];
        return nil;
    }
    
    _notificationQueue = [[NSOperationQueue alloc] init];
    [_notificationQueue setMaxConcurrentOperationCount:1];
    
    self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    self.modalPresentationStyle = UIModalPresentationFormSheet;

    // We want to find out about additional conflicts that show up after we started, and if another device resolves some (or all) of the conflicting versions, we want to know about that to dismiss ourselves.
    // Our action methods (-cancel: and -keep:) should do -removeFilePresenter: before they start mucking around, so that we don't get feedback on this due to our operations. We could maybe also avoid this by passing ourselves to the NSFileCoordinator, but it isn't that reliable.
    [NSFileCoordinator addFilePresenter:self];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentPreviewsUpdatedForFileItemNotification:) name:OUIDocumentPreviewsUpdatedForFileItemNotification object:_fileItem];
    
    return self;
}

- (void)dealloc;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    [_tableView release];
    
    [_toolbar release];
    [_instructionsBackgroundImageView release];
    [_instructionsTextLabel release];
    
    [_fileVersions release];
    [_fileItem release];
    [_fileURL release];
    [_documentStore release];
    
    [_notificationQueue release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark UIViewController subclass

static NSString * const kOUIDocumentConflictTableViewCellReuseIdentifier = @"conflict";

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    // We can't set the title of an existing bar button item, and I'd prefer to not have this xib be localizable for one bar button item.
    [self _updateToolbar];

    _instructionsBackgroundImageView.image = [UIImage imageNamed:@"OUIDocumentConflictResolutionInstructionsBackground.png"];

    {
        // Add a drop shadow for the instructions
        CGRect frame = _instructionsBackgroundImageView.bounds;
        
        OUIGradientView *shadowView = [OUIGradientView horizontalShadow:YES/*topToBottom*/];
        shadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        shadowView.frame = CGRectMake(CGRectGetMinX(frame), CGRectGetMaxY(frame), CGRectGetWidth(frame), [OUIGradientView dropShadowThickness]);
        
        [_instructionsBackgroundImageView addSubview:shadowView];
        _instructionsBackgroundImageView.autoresizesSubviews = YES;
    }

    NSString *message = [_nonretained_delegate conflictResolutionPromptForFileItem:_fileItem];
    if ([NSString isEmptyString:message])
        message = NSLocalizedStringFromTableInBundle(@"Modifications aren't in sync. Choose which documents to keep.", @"OmniUI", OMNI_BUNDLE, @"Instructional text for file conflict resolution view");
    
    _instructionsTextLabel.text = message;
    _instructionsTextLabel.textColor = OQPlatformColorFromHSV(kOUIInspectorLabelTextColor);
                                        
    _tableView.rowHeight = 88;
    
    [_tableView reloadData];
}

- (void)viewDidUnload;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    self.tableView = nil;
    self.toolbar = nil;
    self.instructionsBackgroundImageView = nil;
    self.instructionsTextLabel = nil;
    
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    // Return YES for supported orientations
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    
    BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
    for (OUIDocumentConflictResolutionTableViewCell *cell in _tableView.visibleCells)
        cell.landscape = landscape;
}

#pragma mark -
#pragma mark NSFilePresenter

- (NSURL *)presentedItemURL;
{
    return _fileURL;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    OBPRECONDITION(_notificationQueue);
    return _notificationQueue;
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    // TODO: Test deleting a file that is open and has become in conflict (so we have the conflict sheet atop the document and both need to go away).
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_nonretained_delegate conflictResolutionCancelled:self];
        
        if (completionHandler)
            completionHandler(nil);
    }];
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    // TODO: Test renaming a document that has conflicts. It isn't clear if we can even do this.
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (OFISEQUAL(_fileURL, newURL))
            return;
        
        OBFinishPortingLater("Ignore the new URL if it is in the dead zone");
        
        [_fileURL autorelease];
        _fileURL = [newURL copy];
        
        [self _reloadVersions];
        [self _cancelWhenNoConflictExists];
    }];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"Resolution %@ gained version %@", [self shortDescription], version);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _reloadVersions];
        [self _cancelWhenNoConflictExists];
    }];
}

- (void)presentedItemDidLoseVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"Resolution %@ lost version %@", [self shortDescription], version);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _reloadVersions];
        [self _cancelWhenNoConflictExists];
    }];
}

- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"Resolution %@ resolved version %@", [self shortDescription], version);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _reloadVersions];
        [self _cancelWhenNoConflictExists];
    }];
}

#pragma mark -
#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    return [_fileVersions count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIDocumentConflictResolutionTableViewCell *cell = nil;//[tableView dequeueReusableCellWithIdentifier:kOUIDocumentConflictTableViewCellReuseIdentifier];
    if (!cell)
        cell = [[[OUIDocumentConflictResolutionTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kOUIDocumentConflictTableViewCellReuseIdentifier] autorelease];

    OBFinishPortingLater("Sign up for preview generation notifications and update our rows if we get a preview update for something we are displaying");
    
    BOOL landscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation);
    
    NSFileVersion *fileVersion = [_fileVersions objectAtIndex:indexPath.row];
    OUIDocumentPreview *preview;
    {
        // iWork doesn't rotate previews in the table cell rows if the device is rotated, but does use the current orientation
        
        // It is possible that different versions of the file are of different file types (convert rtf to rtfd, or the like).
        // In other spots we are a bit more paranoid about NSFileVersion having bogus data and we get the URL/date from the file item. Maybe we should here too.
        NSURL *fileURL = fileVersion.URL;
        NSDate *date = fileVersion.modificationDate;
        
        Class documentClass = [[OUISingleDocumentAppController controller] documentClassForURL:fileURL];

        preview = [OUIDocumentPreview makePreviewForDocumentClass:documentClass fileURL:fileURL date:date withLandscape:landscape];
        if (preview.type == OUIDocumentPreviewTypePlaceholder) {
            DEBUG_VERSIONS(@"Need to build a preview for %@", fileVersion);
        }
    }
    
    cell.landscape = landscape;
    cell.fileVersion = fileVersion;
    cell.preview = preview;
    
    return cell;
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    [self _updateToolbar];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    [self _updateToolbar];
}

#pragma mark -
#pragma mark Private

- (IBAction)cancel:(id)sender;
{
    OBFinishPortingLater("If we have an open document and hit cancel, what should happen? Seems like the sheet should be cancelled.");
    
    // Avoid feedback from NSFileCoordinator -- we are done caring about external resolution anyway.
    [NSFileCoordinator removeFilePresenter:self];
    
    [_nonretained_delegate conflictResolutionCancelled:self];
}

- (IBAction)keep:(id)sender;
{
    OBPRECONDITION(_documentStore);

    // Avoid feedback from NSFileCoordinator -- we are done caring about external resolution anyway.
    // NOTE: Even if there is an error performing resolution, we still dismiss ourselves. If we change that, we'll need to re-add and reload our versions.
    [NSFileCoordinator removeFilePresenter:self];

#ifdef OMNI_ASSERTIONS_ON
    NSFileVersion *originalVersion = [_fileVersions objectAtIndex:0];
    OBASSERT(originalVersion.conflict == NO);
    OBASSERT(originalVersion.resolved == YES);
#endif
    
    NSMutableArray *pickedVersions = [NSMutableArray array];
    for (NSIndexPath *indexPath in [[_tableView indexPathsForSelectedRows] sortedArrayUsingSelector:@selector(compare:)]) {
        NSUInteger row = indexPath.row;
        NSFileVersion *fileVersion = [_fileVersions objectAtIndex:row];
        
        OBASSERT((row == 0) ^ fileVersion.conflict);

        [pickedVersions addObject:fileVersion];
    }
    OBASSERT([pickedVersions count] >= 1);
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    [_documentStore resolveConflictForFileURL:_fileURL keepingFileVersions:pickedVersions completionHandler:^(NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        
        if (errorOrNil)
            OUI_PRESENT_ERROR(errorOrNil);

        // NOTE: We dismiss ourselves even on error. See above for why and what would need to change if we don't want to.
        // TODO: In the case that this worked, we should animate the previews off our table view and into the picker (or give enough information to the delegate to do so while we are dismissed). We'll need to hide those previews on our table view, too.
        [_nonretained_delegate conflictResolutionFinished:self];
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    }];
}

static NSString *_keepTitleForCounts(NSUInteger selected, NSUInteger available)
{
    if (selected <= 1)
        return NSLocalizedStringFromTableInBundle(@"Keep", @"OmniUI", OMNI_BUNDLE, @"Toolbar title for file conflict resolution view");
    
    if (selected == available) {
        if (available == 2)
            return NSLocalizedStringFromTableInBundle(@"Keep Both", @"OmniUI", OMNI_BUNDLE, @"Toolbar title for file conflict resolution view, when there are two possibilities and both are selected");
        else
            return NSLocalizedStringFromTableInBundle(@"Keep All", @"OmniUI", OMNI_BUNDLE, @"Toolbar title for file conflict resolution view, when there are more than two possibilities and all are selected");
    }
    
    NSString *format = NSLocalizedStringFromTableInBundle(@"Keep %d", @"OmniUI", OMNI_BUNDLE, @"Toolbar title for file conflict resolution view, when there are multiple possibilities and some are selected");
    return [NSString stringWithFormat:format, selected];
}

- (void)_documentPreviewsUpdatedForFileItemNotification:(NSNotification *)note;
{
    OBPRECONDITION([note object] == _fileItem);
    [_tableView reloadData]; // Rebuild the cells and thus reload the previews
}

- (void)_updateToolbar;
{
    NSMutableArray *items = [NSMutableArray array];
    
    [items addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)] autorelease]];
    [items addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
    [items addObject:[[[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Resolve Conflict", @"OmniUI", OMNI_BUNDLE, @"Toolbar title for file conflict resolution view") style:UIBarButtonItemStylePlain target:nil action:NULL] autorelease]];
    [items addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
    
    UIBarButtonItem *keepItem;
    {
        NSUInteger selectedItemCount = [[_tableView indexPathsForSelectedRows] count];
        NSUInteger availableItemCount = [_fileVersions count];
        
        keepItem = [[[UIBarButtonItem alloc] initWithTitle:_keepTitleForCounts(selectedItemCount, availableItemCount) style:UIBarButtonItemStyleDone target:self action:@selector(keep:)] autorelease];
        keepItem.enabled = (selectedItemCount > 0);
    }
    [items addObject:keepItem];
    
    [_toolbar setItems:items animated:NO];
}

@end
