// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUPreferencesViewController.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/OUIAppController.h>

#import "OSUPreferences.h"
#import "OSUChecker.h"
#import "OSUCheckOperation.h"
#import "OSUHardwareInfo.h"
#import <mach-o/arch.h>

RCS_ID("$Id$");

enum {
    EnabledSection,
    InfoSection,
    SectionCount,
};

/* Adding a UIView containing a UILabel with constraints results in 'Auto Layout still required after executing -layoutSubviews. UITableView's implementation of -layoutSubviews needs to call super.' */
@interface OSUPreferencesTableViewLabel : UIView

- initWithText:(NSString *)text paddingOnTop:(BOOL)paddingOnTop;
@property(nonatomic) CGFloat tableViewWidth;
@property(nonatomic) CGFloat tableViewSeparatorInset;
@property(nonatomic) NSTextAlignment textAlignment;
@end

@implementation OSUPreferencesTableViewLabel
{
    UILabel *_label;
    UIEdgeInsets _edgeInsets;
}

- initWithText:(NSString *)text paddingOnTop:(BOOL)paddingOnTop;
{
    if (!(self = [super init]))
        return nil;
    
    _label = [[UILabel alloc] init];
    _label.text = text;
    _label.numberOfLines = 0; // as many as needed
    _label.textColor = [OUIInspector disabledLabelTextColor];
    _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _label.lineBreakMode = NSLineBreakByWordWrapping;
    
    _edgeInsets.top = paddingOnTop ? 10 : 5;
    _edgeInsets.bottom = paddingOnTop ? 5 : 10;
    
    [self addSubview:_label];
    
    return self;
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    _label.frame = UIEdgeInsetsInsetRect(self.bounds, _edgeInsets);
}

- (CGSize)sizeThatFits:(CGSize)size;
{
    CGSize labelSize = CGSizeMake(MAX(0, _tableViewWidth - _edgeInsets.left - _edgeInsets.right), 0);
    labelSize = [_label sizeThatFits:labelSize];
    return CGSizeMake(_tableViewWidth, ceil(labelSize.height) + _edgeInsets.top + _edgeInsets.bottom);
}

- (void)sizeToFit;
{
    [super sizeToFit];
}

- (void)setTableViewWidth:(CGFloat)width;
{
    if (_tableViewWidth == width)
        return;
    _tableViewWidth = width;
    [self setNeedsLayout]; // Not that this does any good since UITableView doesn't lay out in response to header/footer view changes.
}

- (CGFloat)tableViewSeparatorInset;
{
    return _edgeInsets.left;
}

- (void)setTableViewSeparatorInset:(CGFloat)inset;
{
    if (_edgeInsets.left == inset)
        return;
    _edgeInsets.left = inset;
    _edgeInsets.right = inset;

    [self setNeedsLayout]; // Not that this does any good since UITableView doesn't lay out in response to header/footer view changes.
}

- (NSTextAlignment)textAlignment;
{
    return _label.textAlignment;
}
- (void)setTextAlignment:(NSTextAlignment)textAlignment;
{
    _label.textAlignment = textAlignment;
}

@end

@interface OSUPreferencesInfoEntry : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *value;
@end
@implementation OSUPreferencesInfoEntry
@end

@implementation OSUPreferencesViewController
{
    NSArray *_entries;
    OSUPreferencesTableViewLabel *_settingFooterView;
    OSUPreferencesTableViewLabel *_infoHeaderView;
}

+ (NSString *)localizedSectionTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Device Information", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"software update settings section title");
}

+ (NSString *)localizedDisplayName;
{
    return NSLocalizedStringFromTableInBundle(@"Send Anonymous Data", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"software update settings cell title");
}

+ (NSString *)localizedDetailDescription;
{
    return NSLocalizedStringFromTableInBundle(@"Help The Omni Group decide which devices and iOS versions to support", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"software update settings cell detail text");
}

// Convenience to run w/o a parent navigation controller.
+ (OUIMenuOption *)menuOption;
{
    UIImage *settingsImage = [[OUIAppController controller] settingsMenuImage];
    
    return [OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Settings", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"software update settings menu title") image:settingsImage action:^{
        UIViewController *settingsViewController = [[self alloc] init];
        
        settingsViewController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:settingsViewController action:@selector(_dismissStandaloneViewController:)];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:settingsViewController];
        navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
        
        UIWindow *window = [[OUIAppController controller] window];
        [window.rootViewController presentViewController:navController animated:YES completion:nil];
    }];
}

+ (BOOL)sendAnonymousDeviceInformationEnabled;
{
    return [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue] && [[OSUPreferences includeHardwareDetails] boolValue];
}

- init;
{
    return [self initWithStyle:UITableViewStyleGrouped];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    self.title = NSLocalizedStringFromTableInBundle(@"Device Information", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"software update settings title");
    
    _settingFooterView = [[OSUPreferencesTableViewLabel alloc] initWithText:NSLocalizedStringFromTableInBundle(@"If you choose to share this information, you'll be helping keep us informed of which devices and iOS versions our software should support.\nThis information is kept entirely anonymous.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Settings preferences detail text") paddingOnTop:NO];
    _settingFooterView.textAlignment = NSTextAlignmentLeft;
    
    _infoHeaderView = [[OSUPreferencesTableViewLabel alloc] initWithText:NSLocalizedStringFromTableInBundle(@"The following information will be sent:", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Settings option title") paddingOnTop:YES];

    return self;
}

#pragma mark - UIViewController

- (void)viewWillAppear:(BOOL)animated;
{
    
    OSUChecker *checker = [OSUChecker sharedUpdateChecker];
    NSDictionary *_report = [checker generateReport];
    if (!_report) {
#ifdef DEBUG
        NSLog(@"Couldn't generate report");
#endif
        return;
    }
    
    NSMutableArray *entries = [NSMutableArray array];
    
    NSMutableDictionary *report = [[_report objectForKey:OSUReportResultsInfoKey] mutableCopy];
    
    [report removeObjectForKey:OSUReportInfoLicenseTypeKey]; // Only one option on iOS
    
    // Some non-hardware entries
    {
        void (^addEntry)(NSString *name, NSString *value) = ^(NSString *name, NSString *value){
            OSUPreferencesInfoEntry *entry = [OSUPreferencesInfoEntry new];
            entry.name = name;
            entry.value = value;
            [entries addObject:entry];
        };

        addEntry(NSLocalizedStringFromTableInBundle(@"Report version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), [[OSUChecker OSUVersionNumber] originalVersionString]);
        addEntry(NSLocalizedStringFromTableInBundle(@"App ID", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), [checker applicationIdentifier]);
        addEntry(NSLocalizedStringFromTableInBundle(@"App version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), [checker applicationEngineeringVersion]);
    }
    
    // Entries from the report itself
    {
        void (^addEntry)(NSString *key, NSString *name, NSString *(^transformValue)(NSString *)) = ^(NSString *key, NSString *name, NSString *(^transformValue)(NSString *)){
            NSString *value = report[key];
            if (!value)
                return;
            
            if (transformValue)
                value = transformValue(value);
            
            OSUPreferencesInfoEntry *entry = [OSUPreferencesInfoEntry new];
            entry.name = name;
            entry.value = value;
            [entries addObject:entry];
            
            [report removeObjectForKey:key];
        };
        
        addEntry(OSUReportInfoOSVersionKey, NSLocalizedStringFromTableInBundle(@"iOS version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), nil);
        addEntry(OSUReportInfoLanguageKey, NSLocalizedStringFromTableInBundle(@"Language", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), ^NSString *(NSString *value){
            NSString *localizedName = value; //OFLocalizedNameForISOLanguageCode(value);
            if (localizedName)
                return localizedName;
            return value;
        });
        
        addEntry(OSUReportInfoMachineNameKey, NSLocalizedStringFromTableInBundle(@"Device", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"),  ^NSString *(NSString *value){
            NSString *model = report[OSUReportInfoHardwareModelKey];
            if (model)
                value = [value stringByAppendingFormat:@" (%@)", model];
            [report removeObjectForKey:OSUReportInfoHardwareModelKey];
            return value;
        });

        addEntry(OSUReportInfoCPUTypeKey, NSLocalizedStringFromTableInBundle(@"CPU", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), ^NSString *(NSString *value){
            NSArray *elements = [value componentsSeparatedByString:@","];
            if ([elements count] == 2) {
                const NXArchInfo *archInfo = NXGetArchInfoFromCpuType([elements[0] intValue], [elements[1] intValue]);
                if (archInfo)
                    value = [NSString stringWithCString:archInfo->description encoding:NSASCIIStringEncoding];
            }
            
            NSString *cpuCount = report[OSUReportInfoCPUCountKey];
            if (cpuCount) {
                value = [value stringByAppendingFormat:@", %@", [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ cores", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report format for number of cores in the CPU"), cpuCount]];
                [report removeObjectForKey:OSUReportInfoCPUCountKey];
            }
            
            return value;
        });

        addEntry(OSUReportInfoMemorySizeKey, NSLocalizedStringFromTableInBundle(@"Memory", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), ^NSString *(NSString *value){
            NSDecimalNumber *bytes = [NSDecimalNumber decimalNumberWithString:value];
            return [NSString abbreviatedStringForBytes:[bytes unsignedLongLongValue]];
        });
        addEntry(OSUReportInfoVolumeSizeKey, NSLocalizedStringFromTableInBundle(@"Storage", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), ^NSString *(NSString *value){
            NSDecimalNumber *bytes = [NSDecimalNumber decimalNumberWithString:value];
            return [NSString abbreviatedStringForBytes:[bytes unsignedLongLongValue]];
        });
        
        addEntry(OSUReportInfoUUIDKey, NSLocalizedStringFromTableInBundle(@"Report ID", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name"), nil);

        void (^addRun)(NSString *name, NSString *numberOfRunsKey, NSString *minutesRunKey, NSString *crashCountKey) = ^(NSString *name, NSString *numberOfRunsKey, NSString *minutesRunKey, NSString *crashCountKey){
            NSString *numberOfRuns = report[numberOfRunsKey];
            NSString *minutesRun = report[minutesRunKey];
            NSString *crashCount = report[crashCountKey];

            NSMutableArray *components = [NSMutableArray array];

            if (numberOfRuns) {
                NSInteger launches = [numberOfRuns integerValue];
                if (launches == 1)
                    [components addObject:NSLocalizedStringFromTableInBundle(@"One launch", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for a single launch")];
                else if (launches > 0)
                    [components addObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld launches", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for a single launch"), launches]]; // TODO: Use the new string formatting goop for localized count stuff
            }
            if (minutesRun) {
                NSInteger minutes = [minutesRun integerValue];
                if (minutes >= 60) {
                    NSInteger hours = minutes / 60;
                    if (hours == 1)
                        [components addObject:NSLocalizedStringFromTableInBundle(@"One hour", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for a single hour of use")];
                    else if (hours > 0)
                        [components addObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld hours", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for a multiple hours of use"), hours]]; // TODO: Use the new string formatting goop for localized count stuff
                } else if (minutes > 0) {
                    if (minutes == 1)
                        [components addObject:NSLocalizedStringFromTableInBundle(@"One minute", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for a single minute of use")];
                    else if (minutes > 0)
                        [components addObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld minutes", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for a multiple minutes of use"), minutes]]; // TODO: Use the new string formatting goop for localized count stuff
                }
            }
            if (crashCount) {
                NSInteger crashes = [crashCount integerValue];
                if (crashes == 1)
                    [components addObject:NSLocalizedStringFromTableInBundle(@"One crash", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for a single crash")];
                else if (crashes > 0)
                    [components addObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld crashes", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry string for multiple crashes"), crashes]]; // TODO: Use the new string formatting goop for localized count stuff
            }
            
            OSUPreferencesInfoEntry *entry = [OSUPreferencesInfoEntry new];
            entry.name = name;
            entry.value = [components componentsJoinedByString:@", "];
            [entries addObject:entry];

            [report removeObjectForKey:numberOfRunsKey];
            [report removeObjectForKey:minutesRunKey];
            [report removeObjectForKey:crashCountKey];
        };
        
        addRun(NSLocalizedStringFromTableInBundle(@"This version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name for information about the runs of the current version of the app"), @"nrun", @"runmin", @"ndie");
        addRun(NSLocalizedStringFromTableInBundle(@"All versions", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update report entry name for information about the runs of all versions of the app"), @"tnrun", @"trunmin", @"tndie");
        
        // Handle any remaining entries
        for (NSString *key in [report allKeys]) {
            addEntry(key, key, nil);
        }
    }
    
    _entries = [entries copy];
    
    // It would be nice to do this in -viewWillLayoutSubviews, but that is too late, it seems.
    [self _adjustHeaderAndFooterViews];
    
    // Do this after collecting our info so that the superclass will reload the right data
    [super viewWillAppear:animated];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section;
{
    if (section == InfoSection)
        return _infoHeaderView.frame.size.height;
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
{
    if (section == EnabledSection)
        return _settingFooterView.frame.size.height;
    return 0;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return SectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    switch (section) {
        case EnabledSection:
            return 1;
        case InfoSection:
            return [_entries count];
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            return 0;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;   // custom view for header. will be adjusted to default or specified header height
{
    if (section == InfoSection)
        return _infoHeaderView;

    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section;   // custom view for footer. will be adjusted to default or specified footer height
{
    if (section == EnabledSection)
        return _settingFooterView;

    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case EnabledSection: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"enabled"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"enabled"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                
                UISwitch *accessorySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
                [accessorySwitch addTarget:self action:@selector(_toggleEnabled:) forControlEvents:UIControlEventValueChanged];
                [accessorySwitch sizeToFit];
                cell.accessoryView = accessorySwitch;

                cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Send Anonymous Data", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Settings option title");
                cell.detailTextLabel.textColor = [OUIInspector disabledLabelTextColor];
            }
            
            BOOL enabled = [[self class] sendAnonymousDeviceInformationEnabled];
            ((UISwitch *)cell.accessoryView).on = enabled;

            return cell;
        }
        case InfoSection: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"info"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"info"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            
            OSUPreferencesInfoEntry *entry = _entries[indexPath.row];
            cell.textLabel.text = entry.name;
            cell.detailTextLabel.text = entry.value;
            
            return cell;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            return 0;
    }
}

#pragma mark - Private

- (void)_adjustHeaderAndFooterViews;
{
    UITableView *tableView = (UITableView *)self.view;
    
    UIEdgeInsets separatorInsets = tableView.separatorInset;
    CGFloat seperatorInset = separatorInsets.left + 6; // the separator inset LIES in iOS 8. (by lies, I mean that it does not measure the distance between the edge of the cell and the seperator. I'm not clear on what it IS measuring.) This is a fudge-factor to get it to line up. Sorry.

    _settingFooterView.tableViewSeparatorInset = seperatorInset;
    _infoHeaderView.tableViewSeparatorInset = seperatorInset;

    
    // UITableView doesn't call -sizeThatFits: on the header/footer views.
    CGFloat width = tableView.bounds.size.width;
    _settingFooterView.tableViewWidth = width;
    _infoHeaderView.tableViewWidth = width;
    
    [_settingFooterView sizeToFit];
    [_infoHeaderView sizeToFit];
}

- (void)_toggleEnabled:(UISwitch *)sender;
{
    BOOL enabled = [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue] && [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue];
    
    enabled = !enabled;
    [[OSUPreferences automaticSoftwareUpdateCheckEnabled] setBoolValue:enabled];
    [[OSUPreferences includeHardwareDetails] setBoolValue:enabled];
    [[OSUPreferences checkInterval] restoreDefaultValue];
}

- (void)_dismissStandaloneViewController:(id)sender;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
