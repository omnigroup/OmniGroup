// Copyright 2001-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if OSU_FULL
#import <OmniSoftwareUpdate/OSUSystemConfigurationController.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSUCheckOperation.h>
#import <OmniSoftwareUpdate/OSUProbe.h>
#else
#import <OmniSystemInfo/OSUSystemConfigurationController.h>
#import <OmniSystemInfo/OSUChecker.h>
#import <OmniSystemInfo/OSUCheckOperation.h>
#import <OmniSystemInfo/OSUProbe.h>
#import "OSUPreferences.h" // Not public in this version
#endif

#if OSU_FULL
#import <OmniSoftwareUpdate/OSUReportKeys.h>
#elif defined(OMNI_BUILDING_FRAMEWORK_OR_BUNDLE)
#import <OmniSystemInfo/OSUReportKeys.h>
#else
#import "OSUReportKeys.h" // Non-framework import intentional. Building the OSUCheckService; hopefully avoids a dependency cycle in Xcode 10.
#endif

#import <mach-o/arch.h>

@import OmniAppKit;
@import OmniFoundation;
@import WebKit;

#import "OSURunOperation.h"

RCS_ID("$Id$");

@interface OSUSystemHTMLReport () <WKNavigationDelegate>
@property (nonatomic, strong) NSMutableString *body;
@end

@implementation OSUSystemHTMLReport

- (id)init;
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _body = [NSMutableString string];
    
    __weak typeof(self) weakSelf = self;
    
    _str = ^(NSString *text) {
        [weakSelf.body appendString:text];
    };
    _p = ^(NSString *line){
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.body appendString:@"<p>"];
        [strongSelf.body appendString:line];
        [strongSelf.body appendString:@"</p>"];
    };
    
    _table = ^(void (^guts)(void)) {
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.body appendString:@"<table class=\"toptable\">"];
        guts();
        [strongSelf.body appendString:@"</table>"];
    };
    _tr = ^(void (^guts)(void)) {
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.body appendString:@"<tr>"];
        guts();
        [strongSelf.body appendString:@"</tr>"];
    };
    _th_section = ^(void (^guts)(void)) {
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.body appendString:@"<th colspan=2 class=\"section\">"];
        guts();
        [strongSelf.body appendString:@"</th>"];
    };
    _th = ^(void (^guts)(void)) {
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.body appendString:@"<th>"];
        guts();
        [strongSelf.body appendString:@"</th>"];
    };
    _td = ^(void (^guts)(void)) {
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.body appendString:@"<td>"];
        guts();
        [strongSelf.body appendString:@"</td>"];
    };
    _td_right = ^(void (^guts)(void)) {
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.body appendString:@"<td align=\"right\">"];
        guts();
        [strongSelf.body appendString:@"</td>"];
    };
    
    _infoRow = ^(NSString *title, NSString *value){
        __strong typeof(self) strongSelf = weakSelf;
        strongSelf.tr(^{
            strongSelf.th(^{
                [strongSelf.body appendString:title];
            });
            strongSelf.td(^{
                [strongSelf.body appendString:value];
            });
        });
    };
    
    return self;
}

@end

@interface OSUSystemConfigurationController ()
@property(nonatomic,strong) IBOutlet WKWebView *systemConfigurationWebView;
@property(assign) IBOutlet NSButton *okButton;
@end

@implementation OSUSystemConfigurationController

static NSMapTable<NSString *, id<OSUProbeDataFormatter>> *OSUProbeDataFormatters;

+ (void)setFormatter:(id<OSUProbeDataFormatter>)formatter forProbeKey:(NSString *)probeKey;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OSUProbeDataFormatters = [NSMapTable strongToWeakObjectsMapTable];
    });
    
    [OSUProbeDataFormatters setObject:formatter forKey:probeKey];
}

- (NSString *)frameworkDisplayName;
{
#if OSU_FULL
    return NSLocalizedStringFromTableInBundle(@"Omni Software Update", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"framework name when building the full OmniSoftwareUpdate");
#else
    return NSLocalizedStringFromTableInBundle(@"Omni System Info", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"framework name when building the mini OmniSoftwareInfo framework");
#endif
}

- (NSString *)htmlString;
{
    NSString *path = [OMNI_BUNDLE pathForResource:@"OSUHardwareDescriptionTemplate" ofType:@"html"];
    if (!path) {
#ifdef DEBUG
        NSLog(@"Cannot find OSUHardwareDescriptionTemplate.html");
#endif
        return nil;
    }
    
    NSData *templateData = [[NSData alloc] initWithContentsOfFile:path];
    if (!templateData) {
#ifdef DEBUG
        NSLog(@"Cannot load OSUHardwareDescriptionTemplate.html");
#endif
        return nil;
    }
    
    // We have to do the variable replacement on the string since the tables in the HTML will get replaced with attachment cells
    NSString *htmlTemplate = [[NSMutableString alloc] initWithData:templateData encoding:NSUTF8StringEncoding];
    
    // Get the system configuration report
    OSUChecker *checker = [OSUChecker sharedUpdateChecker];
    NSMutableDictionary *report = [[checker generateReport][OSUReportResultsInfoKey] mutableCopy];
    if (!report) {
#ifdef DEBUG
        NSLog(@"Couldn't generate report");
#endif
        return nil;
    }
    
    
    NSString *appName = [[OAController sharedController] applicationName];
    OSUSystemHTMLReport *html = [[OSUSystemHTMLReport alloc] init];

    void (^infoRow_b)(NSString *title, NSString *(^value)(void)) = ^(NSString *title, NSString *(^value)(void)){
        html.infoRow(title, value());
    };

    NSString *(^getValue)(NSString *) = ^(NSString *key){
        NSString *value = report[key];
        [report removeObjectForKey:key];
        return value;
    };
    
    // Intro.
    {
        NSString *line;
        
        html.p([NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ can optionally send us some basic information about your system configuration. We use this data to determine what systems our customers are using and therefore what systems are most important to support.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update hardware description page intro line one."), appName]);
        html.p(NSLocalizedStringFromTableInBundle(@"Omni will <b>never</b> release information about an individual’s computer configuration — only statistical information about all collected configurations. We honestly respect your privacy.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update hardware description page intro line two. Note the <b> HTML tag around 'never'."));
        html.p(NSLocalizedStringFromTableInBundle(@"If you prefer not to submit your system info, no problem — simply disable this option in the preference pane.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update hardware description page intro line two."));

        NSString *linkString = [NSString stringWithFormat:@"<a href=\"https://update.omnigroup.com/\">%@</a>", self.frameworkDisplayName];
        
        line = NSLocalizedStringFromTableInBundle(@"We do make the statistics we gather public so that other developers can also benefit from this knowledge. You can see the information we release at the LINK_PLACEHOLDER page.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update hardware description page intro line four. Do not localized LINK_PLACEHOLDER; it will be replaced at runtime.");
        
        html.p([line stringByReplacingOccurrencesOfString:@"LINK_PLACEHOLDER" withString:linkString options:0 range:NSMakeRange(0, [line length])]);
    }
    
    html.table(^{
        html.tr(^{
            html.th_section(^{
#if OSU_FULL
                NSString *format = NSLocalizedStringFromTableInBundle(@"When you check for updates, the following information about your copy of %@ is always sent.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Format string for the information sent header when using the full framework.");
#else
                NSString *format = NSLocalizedStringFromTableInBundle(@"When you check for updates, the following information about your copy of %@ is sent.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Format string for the information sent header when using the mini framework.");
#endif
                [html.body appendFormat:format, appName];
            });
        });
        
#if OSU_FULL
        NSString *versionTitle = NSLocalizedStringFromTableInBundle(@"OmniSoftwareUpdate version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for framework version in info table, when using the full framework.");
#else
        NSString *versionTitle = NSLocalizedStringFromTableInBundle(@"OmniSystemInfo version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for framework version in info table, when using the mini framework.");
#endif
        
        html.infoRow(versionTitle, [[OSUChecker OSUVersionNumber] originalVersionString]);

    
        html.infoRow(NSLocalizedStringFromTableInBundle(@"Application ID", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for application identifier in the info table."),
                [checker applicationIdentifier]);

        html.infoRow(NSLocalizedStringFromTableInBundle(@"Application Version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for application version in the info table."),
                [checker applicationEngineeringVersion]);
        
        html.infoRow(NSLocalizedStringFromTableInBundle(@"Update Track", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for application current update track in the info table."),
                [checker applicationTrack]);
        html.infoRow(NSLocalizedStringFromTableInBundle(@"Visible Update Tracks", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for application visible update tracks in the info table."),
                [[OSUPreferences visibleTracks] componentsJoinedByString:@", "]);
        
#if OSU_FULL
        html.tr(^{
            html.th_section(^{
                [html.body appendFormat:NSLocalizedStringFromTableInBundle(@"If you choose in %@ preferences to provide it, the following information is also sent.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Software update hardware description page intro line one."), appName];
            });
        });
#endif
        
        html.tr(^{
            html.th(^{
                [html.body appendString:@"UUID"]; // Probably doesn't need localizing.
            });
            html.td(^{
                NSString *explain = NSLocalizedStringFromTableInBundle(@"A random string that anonymously identifies your computer. This allows us to keep our database up to date when your system configuration changes. This is not associated with your name or any other personal information.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Explanatory text for the UUID in the info table.");
                [html.body appendFormat:@"%@<br><span class=\"explain\">%@</span>", getValue(@"uuid"), explain];
            });
        });
        
        html.tr(^{
            html.th(^{
                [html.body appendString:NSLocalizedStringFromTableInBundle(@"License Type", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for license type row in the info table.")];
            });
            html.td(^{
                [html.body appendFormat:@"%@", getValue(@"license-type")];
#if OSU_FULL
                NSString *explain = NSLocalizedStringFromTableInBundle(@"Your license key itself will never be sent.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Explanatory text for the license type row in the info table.");
                [html.body appendFormat:@"<br><span class=\"explain\">%@</span>", explain];
#endif
            });
        });

        html.infoRow(NSLocalizedStringFromTableInBundle(@"OS Version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the OS version row in the info table."),
                getValue(@"os"));

        infoRow_b(NSLocalizedStringFromTableInBundle(@"Preferred Language", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the preferred language row in the info table."), ^{
            NSString *value = getValue(@"lang");
            NSString *localizedName = OFLocalizedNameForISOLanguageCode(value);
            return localizedName ? localizedName : value;
        });

    
        infoRow_b(NSLocalizedStringFromTableInBundle(@"Computer Model", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the computer model row in the info table."), ^{
            return [NSString stringWithFormat:@"%@ (%@)", getValue(@"machine_name"), getValue(@"hw-model")];
        });
        
        html.infoRow(NSLocalizedStringFromTableInBundle(@"CPU Count", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the CPU count row in the info table."),
                getValue(@"ncpu"));
        
        infoRow_b(NSLocalizedStringFromTableInBundle(@"CPU Type", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the CPU type row in the info table."), ^{
            return [NSString stringWithFormat:@"%@ (%@)", getValue(@"cpu_type"), getValue(@"cpu")];
        });
        
        
        infoRow_b(NSLocalizedStringFromTableInBundle(@"CPU Speed", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the CPU speed row in the info table."), ^{
            NSDecimalNumber *bytes = [NSDecimalNumber decimalNumberWithString:getValue(@"cpuhz")];
            return [NSString abbreviatedStringForHertz:[bytes unsignedLongLongValue]];
        });

        infoRow_b(NSLocalizedStringFromTableInBundle(@"Bus Speed", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the bus speed row in the info table."), ^{
            NSDecimalNumber *bytes = [NSDecimalNumber decimalNumberWithString:getValue(@"bushz")];
            return [NSString abbreviatedStringForHertz:[bytes unsignedLongLongValue]];
        });
        
        infoRow_b(NSLocalizedStringFromTableInBundle(@"Memory", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the memory row in the info table."), ^{
            NSString *mem = getValue(@"mem");
            if ([mem isEqualToString:@"-2147483648"]) {
                // See the check tool -- sysctl blow up here.
                return @">= 2GB";
            }
            
            return [NSByteCountFormatter stringFromByteCount:[mem longLongValue] countStyle:NSByteCountFormatterCountStyleMemory];
        });
        
        infoRow_b(NSLocalizedStringFromTableInBundle(@"Display Settings", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the display settings row in the info table."), ^{
            NSMutableString *displays = [NSMutableString string];
            
            unsigned int displayIndex = 0;
            while (YES) {
                NSString *displayKey = [NSString stringWithFormat:@"display%d", displayIndex];
                NSString *displayInfo = [report objectForKey:displayKey];
                if (!displayInfo)
                    break;
                if ([displays length])
                    [displays appendString:@"<br>"];
                [displays appendString:displayInfo];
                if ([displays length])
                    [displays appendString:@"<br>"];
                [report removeObjectForKey:displayKey];

                if (displayIndex == 0) {
                    NSString *dpi = report[@"dpi"];
                    if (dpi) {
                        [displays appendString:dpi];
                        [displays appendString:@"<br>"];
                        [report removeObjectForKey:@"dpi"];
                    }
                    NSString *bps = report[@"bps"];
                    if (bps) {
                        [displays appendString:bps];
                        [displays appendString:@"<br>"];
                        [report removeObjectForKey:@"bps"];
                    }

                    NSString *sRGB = report[@"sRGB"];
                    if (sRGB) {
                        if ([sRGB isEqual:@"1"]) {
                            [displays appendString:NSLocalizedStringFromTableInBundle(@"sRGB color space supported", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"details panel value - shown if the sRGB colorspace is supported on the deepest display")];
                            [displays appendString:@"<br>"];
                        }
                        [report removeObjectForKey:@"sRGB"];
                    }

                    NSString *p3 = report[@"p3"];
                    if (p3) {
                        if ([p3 isEqual:@"1"]) {
                            [displays appendString:NSLocalizedStringFromTableInBundle(@"P3 color space supported", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"details panel value - shown if the sRGB colorspace is supported on the deepest display")];
                            [displays appendString:@"<br>"];
                        }
                        [report removeObjectForKey:@"p3"];
                    }

                }
                
                displayIndex++;
            }
            return displays;
        });

        infoRow_b(NSLocalizedStringFromTableInBundle(@"Video Cards", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Title for the video cards row in the info table."), ^{
            NSMutableString *adaptors = [NSMutableString string];
            
            // We only record the name of the first adaptor for now
            NSString *adaptorName = [report objectForKey:@"adaptor0_name"];
            if (adaptorName) {
                static BOOL firstTime = YES;
                static NSBundle *displayNamesBundle = nil;
                if (firstTime) {
                    firstTime = NO;
                    displayNamesBundle = [NSBundle bundleWithPath:@"/System/Library/SystemProfiler/SPDisplaysReporter.spreporter"];
                }
                
                if (displayNamesBundle)
                    adaptorName = [displayNamesBundle localizedStringForKey:adaptorName value:adaptorName table:@"Localizable"];
                [adaptors appendFormat:@"%@", adaptorName];
                [report removeObjectForKey:@"adaptor0_name"];
            }
            
            unsigned int adaptorIndex = 0;
            while (YES) {
                NSString *pciKey   = [NSString stringWithFormat:@"accel%d_pci", adaptorIndex];
                NSString *identKey = [NSString stringWithFormat:@"accel%d_id", adaptorIndex];
                NSString *verKey   = [NSString stringWithFormat:@"accel%d_ver", adaptorIndex];
                
                NSString *pci, *ident, *ver;
                pci   = [report objectForKey:pciKey];
                ident = [report objectForKey:identKey];
                ver   = [report objectForKey:verKey];
                
                if (!pci && !ident && !ver)
                    break;
                
                if ([adaptors length])
                    [adaptors appendString:@"<br><br>"];
                
                [adaptors appendString:NSLocalizedStringFromTableInBundle(@"PCI ID", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"details panel string - PCI bus ID of video card")];
                [adaptors appendFormat:@": %@<br>", pci ?: @""];
                [adaptors appendString:NSLocalizedStringFromTableInBundle(@"Hardware Driver", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"details panel string - name of video card driver")];
                [adaptors appendFormat:@": %@<br>", ident ?: @""];
                [adaptors appendString:NSLocalizedStringFromTableInBundle(@"Driver Version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"details panel string - version of video card driver")];
                [adaptors appendFormat:@": %@", ver ?: @""];
                
                [report removeObjectForKey:pciKey];
                [report removeObjectForKey:identKey];
                [report removeObjectForKey:verKey];
                adaptorIndex++;
            }
            
            NSString *memString = [report objectForKey:@"accel_mem"];
            if (memString) {
                [adaptors appendString:@"<br>"];
                if (adaptorIndex == 1) {
                    [adaptors appendString:NSLocalizedStringFromTableInBundle(@"Memory", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"details panel string - amount of video memory installed")];
                    [adaptors appendString:@": "];
                } else
                    [adaptors appendString:@"<br>"];
                
                NSArray *mems = [memString componentsSeparatedByString:@","];
                NSUInteger memIndex, memCount = [mems count];
                for (memIndex = 0; memIndex < memCount; memIndex++) {
                    if (memIndex)
                        [adaptors appendString:@", "];
                    [adaptors appendString:[NSString abbreviatedStringForBytes:[[mems objectAtIndex:memIndex] intValue]]];
                }
                [report removeObjectForKey:@"accel_mem"];
            }
            
            return adaptors;
        });

    });
    
    
    html.table(^{
        html.tr(^{
            [html.body appendString:@"<th colspan=3 class=\"section\">"];
            [html.body appendString:NSLocalizedStringFromTableInBundle(@"Run Count and Times", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Section header for the application run/count table in the info table.")];
            [html.body appendString:@"</th>"];
        });
        
        html.tr(^{
            html.th(^{});
            html.th(^{
                [html.body appendString:NSLocalizedStringFromTableInBundle(@"Current Version", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Header for current version section in the run/count table of the info sheet")];
            });
            html.th(^{
                [html.body appendString:NSLocalizedStringFromTableInBundle(@"All Versions", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Header for all versions section in the run/count table of the info sheet")];
            });
            
            html.tr(^{
                html.th(^{
                    [html.body appendString:NSLocalizedStringFromTableInBundle(@"Hours Run", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Header for number of hours row in the run/count table of the info sheet")];
                });
                html.td_right(^{
                    NSString *value = [NSString stringWithFormat:@"%.1f", [getValue(@"runmin") unsignedIntValue]/60.0];
                    [html.body appendString:value];
                });
                html.td_right(^{
                    NSString *value = [NSString stringWithFormat:@"%.1f", [getValue(@"trunmin") unsignedIntValue]/60.0];
                    [html.body appendString:value];
                });
            });
            
            html.tr(^{
                html.th(^{
                    [html.body appendString:NSLocalizedStringFromTableInBundle(@"# of Launches", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Header for number of launches row in the run/count table of the info sheet")];
                });
                html.td_right(^{
                    [html.body appendString:getValue(@"nrun")];
                });
                html.td_right(^{
                    [html.body appendString:getValue(@"tnrun")];
                });
            });

            html.tr(^{
                html.th(^{
                    [html.body appendString:NSLocalizedStringFromTableInBundle(@"# of Crashes", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Header for number of crashes row in the run/count table of the info sheet")];
                });
                html.td_right(^{
                    [html.body appendString:getValue(@"ndie")];
                });
                html.td_right(^{
                    [html.body appendString:getValue(@"tndie")];
                });
            });

        });
    });

    NSMutableArray *probes = [[OSUProbe allProbes] mutableCopy];
    [[probes copy] enumerateObjectsUsingBlock:^(OSUProbe * _Nonnull probe, NSUInteger idx, BOOL * _Nonnull stop) {
        if (probe.options & OSUProbeOptionHasAppSpecificDisplay) {
            NSString *key = probe.key;
            id<OSUProbeDataFormatter> formatter = [OSUProbeDataFormatters objectForKey:key];
            OBASSERT(formatter != nil, @"Probe %@ is marked for app-specific display, but does not have a registered formatter", key);
            if (formatter == nil) {
                return;
            }
            
            [formatter formatProbeWithKey:key forReport:html];
            [probes removeObjectAtIndex:idx];
            [report removeObjectForKey:key];
        }
    }];
    
    // Append a generic table for application-specific probes. We include these here even if the values are currently zero (and we won't send the zeros) so that there is no surprise if we start sending non-zero data later. We also include any probes that were marked for app-specific reports, but then didn't actually get included yet.
    if ([probes count] > 0) {
        html.table(^{
            html.tr(^{
                html.th_section(^{
                    [html.body appendString:NSLocalizedStringFromTableInBundle(@"Application Usage", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"details panel string - header for application feature usage table")];
                });
            });
            for (OSUProbe *probe in probes) {
                html.tr(^{
                    html.th(^{
                        [html.body appendString:probe.title];
                    });
                    html.td_right(^{
                        [html.body appendString:probe.displayString];
                    });
                });
                [report removeObjectForKey:probe.key];
            }
        });
    }
    
    // Append a table for unknown key/value pairs
    if ([report count] > 0) {
        OBASSERT_NOT_REACHED("Unknown keys in software update report: %@", report);
        
        html.table(^{
            html.tr(^{
                html.th_section(^{
                    [html.body appendString:@"Unknown Keys"]; // Not localized since this is a bug if it is hit anyway.
                });
            });

            [report enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
                html.tr(^{
                    html.th(^{
                        [html.body appendString:key];
                    });
                    html.td_right(^{
                        [html.body appendString:value];
                    });
                });
            }];
        });
    }

    return [htmlTemplate stringByReplacingKeysWithStartingDelimiter:@"${" endingDelimiter:@"}" usingBlock:^NSString *(NSString *key) {
        if ([key isEqualToString:@"OSU_FRAMEWORK"]) {
            return self.frameworkDisplayName;
        }

        if ([key isEqualToString:@"OSU_PANE_TITLE"]) {
            return NSLocalizedStringFromTableInBundle(@"Hardware Description", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"system preferences hardware description page title");
        }

        if ([key isEqual:@"OSU_BODY"]) {
            return html.body;
        }

        if ([key isEqual:@"OSU_BODY_CLASS"]) {
            return self.window.effectiveAppearance.OA_isDarkAppearance ? @"dark-mode" : @"";
        }
        
        OBASSERT_NOT_REACHED("Unknown template key %@", key);
        return @"";
    }];
}

- (void)runModalSheetInWindow:(NSWindow *)parentWindow;
{
    NSWindow *sheetWindow = self.window;
    
    NSString *htmlString = [self htmlString];
    if (!htmlString) {
        return;
    }
    
    [_systemConfigurationWebView loadHTMLString:htmlString baseURL:nil];
    
    OBStrongRetain(self); // stay alive while we are on screen.
    
    [parentWindow beginSheet:sheetWindow completionHandler:nil];
}

- (IBAction)dismissSystemConfigurationDetailsSheet:(id)sender;
{
    NSWindow *sheetWindow = self.window;
    NSWindow *parentWindow = sheetWindow.sheetParent;
    OBASSERT(parentWindow);
    [parentWindow endSheet:sheetWindow];
    
    OBAutorelease(self); // Matching the strong retain in -runModalSheetInWindow:
}

#pragma mark - NSWindowController subclass

- (NSString *)windowNibName;
{
    return @"OSUSystemConfiguration";
}

- (id)owner;
{
    return self; // Used to find the nib
}

#pragma mark - NSNibAwaking

- (void)awakeFromNib;
{
    [super awakeFromNib];
    self.okButton.title = OAOK();
}

// MARK:- WKNavigationDelegate


#pragma mark - WebPolicyDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler;
{
    NSURL *url = navigationAction.request.URL;

    // about:blank is passed when loading the initial content
    if ([[url absoluteString] isEqualToString:@"about:blank"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
	return;
    }
    
    // when a link is clicked reject it locally and open it in an external browser
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
	[[NSWorkspace sharedWorkspace] openURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
	return;
    }
    
#ifdef DEBUG
    NSLog(@"action %@, request %@", navigationAction, navigationAction.request);
#endif
}

- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error;
{
#ifdef DEBUG
    NSLog(@"error %@", error);
#endif
}

@end
