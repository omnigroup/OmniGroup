// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentConflictResolutionViewController.h"

#import <OmniFileStore/OFSFileManager.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIGradientView.h>
#import <OmniUI/OUIDocumentStore.h>

#import "OUIDocumentConflictResolutionTableViewCell.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

/*
 WWDC '11 -- Session 125 @ 19:32 for notes on Automatic Cell Loading
 */

@interface OUIDocumentConflictResolutionViewController () <NSFilePresenter>

@property(nonatomic,retain) IBOutlet UIToolbar *toolbar;
@property(nonatomic,retain) IBOutlet UIImageView *instructionsBackgroundImageView;
@property(nonatomic,retain) IBOutlet UILabel *instructionsTextLabel;
@property(nonatomic,retain) IBOutlet UITableView *tableView;

- (IBAction)cancel:(id)sender;
- (IBAction)keep:(id)sender;

- (void)_reloadVersions;
- (void)_updateToolbar;

@end

@implementation OUIDocumentConflictResolutionViewController
{
    OUIDocumentStore *_documentStore;
    NSArray *_fileVersions;
    
    NSOperationQueue *_notificationQueue;
}

@synthesize fileURL = _fileURL;
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

    if ([_fileVersions count] <= 1) {
        // The conflict has been resolved on another device!
        [self cancel:nil];
        return;
    }
    
    [_tableView reloadData];
}

- initWithDocumentStore:(OUIDocumentStore *)documentStore fileURL:(NSURL *)fileURL delegate:(id <OUIDocumentConflictResolutionViewControllerDelegate>)delegate;
{
    if (!(self = [super initWithNibName:@"OUIDocumentConflictResolutionViewController" bundle:nil]))
        return nil;
    
    OBFinishPortingLater("Register as an NSFilePresenter and watch for gaining/losing conflict versions."); // We should update our table view, and in the case that the last conflicting version goes away, we should simply close as if cancelled.
    
    _documentStore = [documentStore retain];
    _fileURL = [fileURL copy];
    _nonretained_delegate = delegate;
    
    [self _reloadVersions];
    
    _notificationQueue = [[NSOperationQueue alloc] init];
    [_notificationQueue setMaxConcurrentOperationCount:1];
    
    self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    self.modalPresentationStyle = UIModalPresentationFormSheet;

    // We want to find out about additional conflicts that show up after we started, and if another device resolves some (or all) of the conflicting versions, we want to know about that to dismiss ourselves.
    // Our action methods (-cancel: and -keep:) should do -removeFilePresenter: before they start mucking around, so that we don't get feedback on this due to our operations. We could maybe also avoid this by passing ourselves to the NSFileCoordinator, but it isn't that reliable.
    [NSFileCoordinator addFilePresenter:self];

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
    
    _instructionsTextLabel.text = NSLocalizedStringFromTableInBundle(@"Modifications aren't in sync. Choose which documents to keep.", @"OmniUI", OMNI_BUNDLE, @"Instructional text for file conflict resolution view");
    _instructionsTextLabel.textColor = OQPlatformColorFromHSV(kOUIInspectorLabelTextColor);
                                        
    _tableView.rowHeight = 88; // Matches the prototype in the xib
    [_tableView registerNib:[UINib nibWithNibName:@"OUIDocumentConflictResolutionTableViewCell" bundle:nil] forCellReuseIdentifier:kOUIDocumentConflictTableViewCellReuseIdentifier];
    
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
        OBFinishPortingLater("Ignore the new URL if it is in the dead zone");
        
        [_fileURL autorelease];
        _fileURL = [newURL copy];
        
        [self _reloadVersions];
    }];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"Resolution %@ gained version %@", [self shortDescription], version);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _reloadVersions];
    }];
}

- (void)presentedItemDidLoseVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"Resolution %@ lost version %@", [self shortDescription], version);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _reloadVersions];
    }];
}

- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version;
{
    DEBUG_VERSIONS(@"Resolution %@ resolved version %@", [self shortDescription], version);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _reloadVersions];
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
    OUIDocumentConflictResolutionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kOUIDocumentConflictTableViewCellReuseIdentifier];
    
    cell.fileVersion = [_fileVersions objectAtIndex:indexPath.row];
    
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

- (void)_replaceURL:(NSURL *)fileURL withVersion:(NSFileVersion *)version replacing:(BOOL)replacing completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(_documentStore);
    
    [_documentStore performAsynchronousFileAccessUsingBlock:^{
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        NSFileCoordinatorWritingOptions options = replacing ? NSFileCoordinatorWritingForReplacing : 0;
        
        __block BOOL success = NO;
        __block NSError *innerError = nil;
        NSError *error = nil;
        
        [coordinator coordinateWritingItemAtURL:fileURL options:options error:&error byAccessor:^(NSURL *newURL){
            // We don't pass NSFileVersionReplacingByMoving, leaving the version in place. It isn't clear if this is correct. We're going to mark it resolved if this all works, but it is unclear if that will clean it up.
            NSError *replaceError = nil;
            if (![version replaceItemAtURL:newURL options:0 error:&replaceError]) {
                NSLog(@"Error replacing %@ with version %@: %@", fileURL, newURL, [replaceError toPropertyList]);
                innerError = [replaceError retain];
                return;
            }
            
            success = YES;
        }];
        [coordinator release];
        
        if (!success) {
            if (innerError)
                error = [innerError autorelease];
        } else
            error = nil;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(error);
        }];
    }];
}

- (IBAction)cancel:(id)sender;
{
    OBFinishPortingLater("If we have an open document and hit cancel, what should happen? Seems like the sheet should be cancelled.");
    
    // Avoid feedback from NSFileCoordinator -- we are done caring about external resolution anyway.
    [NSFileCoordinator removeFilePresenter:self];
    
    [_nonretained_delegate conflictResolutionCancelled:self];
}

- (IBAction)keep:(id)sender;
{
    // Avoid feedback from NSFileCoordinator -- we are done caring about external resolution anyway.
    // NOTE: Even if there is an error performing resolution, we still dismiss ourselves. If we change that, we'll need to re-add and reload our versions.
    [NSFileCoordinator removeFilePresenter:self];

    NSFileVersion *originalVersion = [_fileVersions objectAtIndex:0];
    OBASSERT(originalVersion.conflict == NO);
    
    NSMutableArray *pickedVersions = [NSMutableArray array];
    for (NSIndexPath *indexPath in [_tableView indexPathsForSelectedRows]) {
        NSUInteger row = indexPath.row;
        NSFileVersion *fileVersion = [_fileVersions objectAtIndex:row];
        
        OBASSERT((row == 0) ^ fileVersion.conflict);

        [pickedVersions addObject:fileVersion];
    }
    OBASSERT([pickedVersions count] >= 1);
    
    NSUInteger pickedVersionCount = [pickedVersions count];
    NSFileVersion *firstPickedVersion = [pickedVersions objectAtIndex:0];
    
    NSMutableArray *errors = [NSMutableArray array];
                              
    if (firstPickedVersion != originalVersion) {
        // This version is going to replace the current version. replacing==YES means that the coordinated write will preserve the identity of the file, rather than looking like a delete of the original and a new file being created in its place.
        [self _replaceURL:_fileURL withVersion:firstPickedVersion replacing:YES completionHandler:^(NSError *errorOrNil){
            OBASSERT([NSThread isMainThread]);
            if (errorOrNil)
                [errors addObject:errorOrNil];
        }];
    }
    
    // Make new files for any other versions to be preserved
    if (pickedVersionCount >= 2) {
        NSString *originalFileName = [_fileURL lastPathComponent];
        NSString *originalBaseName = nil;
        NSUInteger counter;
        OFSFileManagerSplitNameAndCounter([originalFileName stringByDeletingPathExtension], &originalBaseName, &counter);
        NSString *originalPathExtension = [originalFileName pathExtension];
        
        NSURL *originalContainerURL = [_fileURL URLByDeletingLastPathComponent];
        
        OBFinishPortingLater("Make sure that the either our counter parameter is a minimum allowed version to use and increment it each time, or that OUIDocumentStore rescans each time through");
#ifdef OMNI_ASSERTIONS_ON
        NSMutableSet *usedFileNames = [NSMutableSet set];
#endif
        
        for (NSUInteger pickedVersionIndex = 1; pickedVersionIndex < pickedVersionCount; pickedVersionIndex++) {
            NSFileVersion *pickedVersion = [pickedVersions objectAtIndex:pickedVersionIndex];
            NSString *fileName = [_documentStore availableFileNameWithBaseName:originalBaseName extension:originalPathExtension counter:&counter];
#ifdef OMNI_ASSERTIONS_ON
            OBASSERT([usedFileNames member:fileName] == nil);
            [usedFileNames addObject:fileName];
#endif
            
            NSURL *replacementURL = [originalContainerURL URLByAppendingPathComponent:fileName];
            
            [self _replaceURL:replacementURL withVersion:pickedVersion replacing:NO completionHandler:^(NSError *errorOrNil){
                OBASSERT([NSThread isMainThread]);
                if (errorOrNil)
                    [errors addObject:errorOrNil];
            }];
        }
    }
    
    // Now, wait for all the resolution attempts to filter out
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    [_documentStore performAsynchronousFileAccessUsingBlock:^{
        if ([errors count] > 0) {
            for (NSError *error in errors)
                OUI_PRESENT_ERROR(error);
        } else {
            // Only mark versions resolved if we had no errors.
            // The documentation makes no claims about whether this is considered an operation that needs file coordination...
            for (NSFileVersion *fileVersion in _fileVersions) {
                if (fileVersion != originalVersion) {
                    OBASSERT(fileVersion.conflict == YES);
                    fileVersion.resolved = YES;
                }
            }
        }
        
        // NOTE: We dismiss ourselves even on error. See above for why and what would need to change if we don't want to.
        // TODO: In the case that this worked, we should animate the previews off our table view and into the picker (or give enough information to the delegate to do so while we are dismissed). We'll need to hide those previews on our table view, too.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [_nonretained_delegate conflictResolutionFinished:self];
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        }];
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
