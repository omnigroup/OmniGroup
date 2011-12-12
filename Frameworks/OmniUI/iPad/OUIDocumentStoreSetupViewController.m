// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentStoreSetupViewController.h"

RCS_ID("$Id$");

@interface OUIDocumentStoreSetupViewController ()
@property(nonatomic,retain) IBOutlet UIToolbar *toolbar;
@property(nonatomic,retain) IBOutlet UILabel *infoLabel;
@property(nonatomic,retain) IBOutlet UITableView *tableView;
@property(nonatomic,retain) IBOutlet UIImageView *backgroundImageView;

- (void)done:(id)sender;
- (void)switchChanged:(id)sender;

@end

enum {
    UseICloudOption,
    MoveExistingDocumentsToICloudOption,
    OptionCount,
} Options;

@implementation OUIDocumentStoreSetupViewController
{
    void (^_dismissAction)(BOOL cancelled);
    BOOL _useICloud;
    BOOL _moveExistingDocumentsToICloud;
    
    UIImage *_optionBackgroundImage;
}

@synthesize toolbar = _toolbar;
@synthesize infoLabel = _infoLabel;
@synthesize tableView = _tableView;
@synthesize backgroundImageView = _backgroundImageView;
@synthesize useICloud = _useICloud;
@synthesize moveExistingDocumentsToICloud = _moveExistingDocumentsToICloud;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    OBRejectUnusedImplementation(self, _cmd);
    [self release];
    return nil;
}

- initWithDismissAction:(void (^)(BOOL cancelled))dismissAction;
{    
    if (!(self = [super initWithNibName:@"OUIDocumentStoreSetupViewController" bundle:OMNI_BUNDLE]))
        return nil;

    _dismissAction = [dismissAction copy];
    
    // Good default choices.
    _useICloud = YES;
    _moveExistingDocumentsToICloud = YES;
    
    self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    self.modalPresentationStyle = UIModalPresentationFormSheet;

    return self;
}

- (void)dealloc;
{
    OBASSERT(_dismissAction == nil); // should have been cleared in -done:

    [_toolbar release];
    [_infoLabel release];
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    [_tableView release];
    [_backgroundImageView release];
    [_optionBackgroundImage release];
    
    [super dealloc];
}

- (void)done:(id)sender;
{
    //  The dismiss action is presumed to look at our properties and do something with the settings.
    if (_dismissAction) {
        // break possible retain cycle
        void (^dismissAction)(BOOL cancelled) = [_dismissAction autorelease];
        _dismissAction = nil;
        dismissAction(NO/*cancelled*/);
    }
}

- (void)cancel;
{
    if (_dismissAction) {
        // break possible retain cycle
        void (^dismissAction)(BOOL cancelled) = [_dismissAction autorelease];
        _dismissAction = nil;
        dismissAction(YES/*cancelled*/);
    }
}

- (IBAction)switchChanged:(id)sender;
{
    UISwitch *switchView = sender;
    
    switch (switchView.tag) {
        case UseICloudOption: {
            BOOL on = switchView.on;
            if (_useICloud ^ on) {
                _useICloud = on;
                
                [_tableView beginUpdates];
                if (_useICloud) {
                    _moveExistingDocumentsToICloud = YES;
                    [_tableView insertSections:[NSIndexSet indexSetWithIndex:MoveExistingDocumentsToICloudOption] withRowAnimation:UITableViewRowAnimationAutomatic];
                } else
                    [_tableView deleteSections:[NSIndexSet indexSetWithIndex:MoveExistingDocumentsToICloudOption] withRowAnimation:UITableViewRowAnimationAutomatic];
                [_tableView endUpdates];
            }
            break;
        }
        case MoveExistingDocumentsToICloudOption:
            _moveExistingDocumentsToICloud = switchView.on;
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown option");
            break;
    }
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    NSMutableArray *toolbarItems = [NSMutableArray array];
    {
        NSString *title = NSLocalizedStringFromTableInBundle(@"Set Up iCloud", @"OmniUI", OMNI_BUNDLE, @"Title for iCloud setup sheet");
        
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain target:nil action:NULL] autorelease]];
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)] autorelease]];
    }
    [_toolbar setItems:toolbarItems animated:NO];


    NSString *infoFormat = NSLocalizedStringFromTableInBundle(@"You can store your %@ documents on iCloud,\nso that they stay up to date on all your devices.", @"OmniUI", OMNI_BUNDLE, @"Informational text in iCloud setup sheet");
    NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    OBASSERT(![NSString isEmptyString:appName]);
    _infoLabel.text = [NSString stringWithFormat:infoFormat, appName];

    {
        UIImage *image = [UIImage imageNamed:@"OUIDocumentStoreSetupOptionBackground.png"];
        
        _optionBackgroundImage = [[image stretchableImageWithLeftCapWidth:10 topCapHeight:0] retain];
        OBASSERT(_optionBackgroundImage);
    }
    
    _tableView.backgroundView = nil;
    _tableView.backgroundColor = nil;
    _tableView.rowHeight = _optionBackgroundImage.size.height;
    _tableView.scrollEnabled = NO;
    _tableView.allowsSelection = NO;
    
    _backgroundImageView.image = [UIImage imageNamed:@"OUIDocumentStoreSetupBackground.jpg"];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    
    self.toolbar = nil;
    self.infoLabel = nil;
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    self.tableView = nil;
    self.backgroundImageView = nil;
    
    [_optionBackgroundImage release];
    _optionBackgroundImage = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    if (_useICloud)
        return OptionCount;
    else
        return OptionCount - 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    OBPRECONDITION(section < OptionCount);
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(indexPath.section < OptionCount);
    OBPRECONDITION(indexPath.row == 0);
    
    static NSString * const SwitchCellIdentifier = @"switch";
    
    UITableViewCell *cell = [_tableView dequeueReusableCellWithIdentifier:SwitchCellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:SwitchCellIdentifier] autorelease];
        
        UISwitch *switchView = [[[UISwitch alloc] init] autorelease];
        [switchView addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        
        cell.accessoryView = switchView;
        
        UIImageView *backgroundView = [[[UIImageView alloc] initWithImage:_optionBackgroundImage] autorelease];
        backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        cell.backgroundView = backgroundView;
        
    }
    
    NSString *title, *subtitle;
    BOOL state;
    
    switch (indexPath.section) {
        case UseICloudOption:
            title = NSLocalizedStringFromTableInBundle(@"Use iCloud", @"OmniUI", OMNI_BUNDLE, @"Option title for iCloud setup sheet.");
            subtitle = NSLocalizedStringFromTableInBundle(@"New documents will be automatically added to iCloud.", @"OmniUI", OMNI_BUNDLE, @"Option subtitle for iCloud setup sheet.");
            state = _useICloud;
            break;
        case MoveExistingDocumentsToICloudOption:
            title = NSLocalizedStringFromTableInBundle(@"Move Existing Documents to iCloud", @"OmniUI", OMNI_BUNDLE, @"Option title for iCloud setup sheet.");
            subtitle = NSLocalizedStringFromTableInBundle(@"You can also manually move your documents one by one.", @"OmniUI", OMNI_BUNDLE, @"Option subtitle for iCloud setup sheet.");
            state = _moveExistingDocumentsToICloud;
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown option");
            return nil;
    }
    
    cell.textLabel.text = title;
    cell.detailTextLabel.text = subtitle;
    
    UISwitch *switchView = (UISwitch *)cell.accessoryView;
    switchView.on = state;
    switchView.tag = indexPath.section;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(indexPath.section < OptionCount);
    OBPRECONDITION(indexPath.row == 0);

    cell.textLabel.backgroundColor = nil;
    cell.textLabel.opaque = NO;
    
    cell.detailTextLabel.backgroundColor = nil;        
    cell.detailTextLabel.opaque = NO;
}

@end
