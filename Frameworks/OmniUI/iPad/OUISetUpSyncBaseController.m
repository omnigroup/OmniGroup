// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISetUpSyncBaseController.h"

#import "OUIEditableLabeledValueCell.h"

RCS_ID("$Id$");

static NSString * const SetUpSyncBaseNibName = @"OUISetUpSyncBase";

@interface OUISetUpSyncBaseController ()

+ (UIImage *)clearCheckImage;

@property (nonatomic, retain) UIBarButtonItem *syncBarButtonItem;

- (void)_base_textFieldTextDidChange:(NSNotification *)notification;
- (void)_updateLastSyncSettings;

- (BOOL)_shouldUseFooterButtons;

@end

@implementation OUISetUpSyncBaseController

+ (UIImage *)clearCheckImage;
{
    // A clear image to use up space (lame) so that we align cells with those which are currently checked;
    static UIImage *_clearCheckImage;
    
    if (_clearCheckImage == nil) {
        UIImage *blueCheckImage = [UIImage imageNamed:@"BlueCheck.png"];
        OBASSERT(blueCheckImage != nil);
        
        CGSize size = blueCheckImage.size;
        
        UIGraphicsBeginImageContext(size);
        [[UIColor clearColor] set];
        UIRectFill(CGRectMake(0, 0, size.height, size.width));
        _clearCheckImage = [UIGraphicsGetImageFromCurrentImageContext() retain];
        UIGraphicsEndImageContext();
    }

    return _clearCheckImage;
}

+ (UIView *)informativeViewWithText:(NSString *)text;
{
    return [self informativeViewWithText:text topMargin:0 bottomMargin:0];
}

+ (UIView *)informativeViewWithText:(NSString *)text topMargin:(CGFloat)topMargin bottomMargin:(CGFloat)bottomMargin;
{
    OBPRECONDITION(text);
    OBPRECONDITION(topMargin >= 0);
    OBPRECONDITION(bottomMargin >= 0);
    
    const CGFloat VIEW_WIDTH = 500;
    const CGFloat HORIZONTAL_MARGIN = 60;
    const CGFloat VERTICAL_MARGIN = 10;

    topMargin += VERTICAL_MARGIN;
    bottomMargin += VERTICAL_MARGIN;

    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(HORIZONTAL_MARGIN, topMargin, VIEW_WIDTH - 2 * HORIZONTAL_MARGIN, 0)] autorelease];
    [label setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [label setLineBreakMode:UILineBreakModeWordWrap];
    [label setNumberOfLines:0];
    [label setText:text];
    [label setFont:[UIFont systemFontOfSize:12]];
    [label setShadowColor:[UIColor whiteColor]];
    [label setShadowOffset:CGSizeMake(0, 1)];
    [label setBackgroundColor:[UIColor clearColor]];
    [label setOpaque:NO];
    [label sizeToFit];

    UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, VIEW_WIDTH, CGRectGetHeight(label.frame) + topMargin + bottomMargin)] autorelease];
    [view setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [view addSubview:label];

    return view;
}

- (id)init;
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (!self)
        return nil;
        
    _showsSelectedModeCheckmark = YES;

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [_titleLabel release];
    [_syncButton release];
    [_syncBarButtonItem release];
    [_cancelButton release];
    [_tableHeaderView release];
    [_tableFooterView release];
    [_footerView release];
    [_syncMethodText release];
    [_syncMethodDetailText release];

    [super dealloc];
}

@synthesize syncBarButtonItem = _syncBarButtonItem;
@synthesize titleLabel = _titleLabel;
@synthesize syncButton = _syncButton;
@synthesize cancelButton = _cancelButton;

@synthesize tableHeaderView = _tableHeaderView;
@synthesize tableFooterView = _tableFooterView;

@synthesize footerView = _footerView;

- (void)loadView;
{
    [super loadView];

    [[NSBundle mainBundle] loadNibNamed:SetUpSyncBaseNibName owner:self options:nil];
    
    NSString *auxillaryNibName = self.auxillaryNibName;
    if (auxillaryNibName)
        [[NSBundle mainBundle] loadNibNamed:auxillaryNibName owner:self options:nil];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];

    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Sync Setup", @"OmniUI", OMNI_BUNDLE, @"Sync Setup title");
    self.navigationItem.hidesBackButton = [self _shouldUseFooterButtons];
    
    if (!self.navigationController.navigationBarHidden)
        self.tableHeaderView = nil;

    self.tableView.tableHeaderView = self.tableHeaderView;
    self.tableView.tableFooterView = self.tableFooterView;
    self.tableView.alwaysBounceVertical = NO;
  
    if ([self _shouldUseFooterButtons]) {  
        OBASSERT(self.footerView);
    
        CGFloat footerHeight = self.footerView.frame.size.height;
        UIEdgeInsets edgeInsets = UIEdgeInsetsMake(0, 0, footerHeight, 0);
        self.tableView.contentInset = edgeInsets;
        
        CGRect frame = self.footerView.frame;
        frame.origin.y = self.tableView.bounds.size.height - frame.size.height;
        frame.size.width = self.tableView.bounds.size.width;
        
        self.footerView.frame = frame;
        [self.tableView addSubview:self.footerView];
        
        [self.syncButton setTitle:NSLocalizedStringFromTableInBundle(@"Sync", @"OmniUI", OMNI_BUNDLE, @"button title") forState:UIControlStateNormal];
        [self.cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") forState:UIControlStateNormal];
        
        self.titleLabel.text = NSLocalizedStringFromTableInBundle(@"OmniFocus Sync Setup", @"OmniUI", OMNI_BUNDLE, @"Sync setup title");
    } else {
        NSString *syncButtonTitle = NSLocalizedStringFromTableInBundle(@"Sync", @"OmniUI", OMNI_BUNDLE, @"button title");
        UIBarButtonItem *syncBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleDone target:self action:@selector(saveSettingsAndSync)];
        self.navigationItem.rightBarButtonItem = syncBarButtonItem;
        self.syncBarButtonItem = syncBarButtonItem;
        [syncBarButtonItem release];
    }

    [self validateSyncButton];
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    self.syncButton = nil;
    self.cancelButton = nil;
    
    self.tableHeaderView = nil;
    self.footerView = nil;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    [self _updateLastSyncSettings];
    [self validateSyncButton];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_base_textFieldTextDidChange:) name:UITextFieldTextDidChangeNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated;
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    return YES;
}

#pragma mark -
#pragma mark IBActions

- (IBAction)cancel;
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)saveSettingsAndSync;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark Subclass Hooks

- (NSString *)auxillaryNibName;
{
    return nil;
}

@synthesize syncMethodText = _syncMethodText;
@synthesize syncMethodDetailText = _syncMethodDetailText;
@synthesize showsSelectedModeCheckmark = _showsSelectedModeCheckmark;

// Subclasses should override this to return the union of super's return value, and all of their own text fields which must be non-empty for the sync button to be enabled.
- (NSSet *)textFieldsAffectingSyncButtonEnabledState;
{
    return [NSSet set];
}

- (void)validateSyncButton;
{
    BOOL enabled = [self canSaveSettingsAndSync];
    self.syncButton.enabled = enabled;
    self.syncBarButtonItem.enabled = enabled;
}

// The default implementation enableds the sync button if every field in editFieldsAffectingSyncButtonEnabledState is non-empty. Subclasses should take over this implementation if they need to supplement the logic.
- (BOOL)canSaveSettingsAndSync;
{
    NSSet *editFields = [self textFieldsAffectingSyncButtonEnabledState];
    if ([editFields count] == 0) {
        return YES;
    }
    
    for (UITextField *textField in [self textFieldsAffectingSyncButtonEnabledState]) {
        if ([textField.text length] == 0) {
            return NO;
        }
    }

    return YES;
}

#pragma mark -
#pragma mark Table View Data Source

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    if (section == SetUpSyncControllerHeadingSection)
        return 1;

    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == SetUpSyncControllerHeadingSection && indexPath.row == 0) {
        UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];

         cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (self.showsSelectedModeCheckmark) {
            cell.imageView.image = [UIImage imageNamed:@"BlueCheck.png"];
            cell.imageView.highlightedImage = [UIImage imageNamed:@"WhiteCheck.png"];
            /* cell.textLabel.textColor = [UIColor selectedOptionColor]; */
        } else {
            cell.imageView.image = [[self class] clearCheckImage];
            cell.textLabel.textColor = [UIColor blackColor];
        }
        cell.textLabel.text = self.syncMethodText;
        cell.detailTextLabel.text = self.syncMethodDetailText;

        return cell;
    }

    OBASSERT_NOT_REACHED("Unknown section/row.");
    return nil;
}

#pragma mark -
#pragma mark Table View Delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == SetUpSyncControllerHeadingSection && indexPath.row == 0) {
        return [self.syncMethodDetailText length] > 0 ? 64 : tableView.rowHeight;
    }

    return tableView.rowHeight;
}

#pragma mark -
#pragma mark Private

- (void)_base_textFieldTextDidChange:(NSNotification *)notification;
{
    if ([[self textFieldsAffectingSyncButtonEnabledState] containsObject:[notification object]])
        [self validateSyncButton];
}

- (void)_updateLastSyncSettings;
{
    /*
    switch ([XMLSyncManager syncType]) {
	case XMLSyncTypeMobileMe: {
            [[OFPreference preferenceForKey:@"LastSyncMobileMeUser"] setStringValue:[XMLSyncManager mobileMeUser]];
            [[OFPreference preferenceForKey:@"LastSyncMobileMePath"] setStringValue:[XMLSyncManager mobileMePath]];
	    break;
        }
        
	case XMLSyncTypeLocalWebServer: {
	    [[OFPreference preferenceForKey:@"LastSyncLocalWebServerIdentifier"] setStringValue:[XMLSyncManager bonjourSyncServerIdentifier]];
	    break;
        }

	case XMLSyncTypeWebDAV: {
            [[OFPreference preferenceForKey:@"LastSyncWebDAVURL"] setStringValue:[XMLSyncManager syncURIDisplayString]];
            break;
        }
        
        case XMLSyncTypeOmniSyncServer: {
            [[OFPreference preferenceForKey:@"LastSyncOmniSyncUser"] setStringValue:[XMLSyncManager omniSyncUser]];
            break;
        }
        
        default: {
            break;
        }
    }
     */
}

- (BOOL)_shouldUseFooterButtons;
{
    /* return [FirstRunController isPerformingFirstRunSetup]; */
    return NO;
}

@end

@implementation OUISetUpSyncBaseController (SubclassUtilities)

- (UITextField *)textFieldForEditableLabeledValueCellWithTag:(NSInteger)tag inRowAtIndexPath:(NSIndexPath *)indexPath;
{
    UITableViewCell *tableCell = [self.tableView cellForRowAtIndexPath:indexPath];
    OUIEditableLabeledValueCell *valueCell = (id)[tableCell.contentView viewWithTag:tag];
    OBASSERT([valueCell isKindOfClass:[OUIEditableLabeledValueCell class]]);
    return valueCell.valueField;
}

@end

#pragma mark -

#define BADGE_VIEW_TAG 1000

void SetUpSyncBadgeTableViewCellWithImage(UITableViewCell *cell, UIImage *image)
{
    OBPRECONDITION(cell);
    
    if (image) {
        UIImageView *imageView = (UIImageView *)[cell viewWithTag:BADGE_VIEW_TAG];
        if (!imageView) {
            imageView = [[[UIImageView alloc] initWithImage:image] autorelease];
            imageView.tag = BADGE_VIEW_TAG;
        }
        
        CGRect frame = imageView.frame;
        frame.origin.x = 35 + [cell.textLabel.text sizeWithFont:[UIFont boldSystemFontOfSize:18]].width;
        frame.origin.y = 10;
        imageView.frame = frame;
        [cell.contentView addSubview:imageView];
    } else {
        UIView *imageView = [cell viewWithTag:BADGE_VIEW_TAG];
        if (imageView)
            [imageView removeFromSuperview];
    }
}
