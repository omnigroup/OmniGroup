// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ViewController.h"

#import <OmniFoundation/OFNetStateNotifier.h>
#import <OmniFoundation/OFNetStateRegistration.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFRandom.h>

RCS_ID("$Id$")

static NSString * GroupIdentifier = @"OFNetStateSet";

@interface ViewController () <OFNetStateNotifierDelegate>

@end

@implementation ViewController
{
    NSString *_memberIdentifier;
    OFNetStateNotifier *_notifier;
    OFNetStateRegistration *_registration;
    NSTimer *_resetTimer;
}

+ (void)initialize;
{
    if (self == [ViewController class]) {
        static NSOperationQueue *allocationQueue;
        
        allocationQueue = [[NSOperationQueue alloc] init];
        for (NSUInteger i = 0; i < 5; i++) {
            [allocationQueue addOperationWithBlock:^{
                while (YES) {
                    void *ptr = malloc(arc4random() % 2048);
                    if (ptr)
                        free(ptr);
                }
            }];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    if (!_memberIdentifier) {
        
        _memberIdentifier = OFXMLCreateID();
        
        [self _resetTimerFired:nil];
        
        NSString *name = [[UIDevice currentDevice] name];
        _registration = [[OFNetStateRegistration alloc] initWithGroupIdentifier:GroupIdentifier memberIdentifier:_memberIdentifier name:[NSString stringWithFormat:@"%@.%d", name, getpid()] state:OFRandomCreateDataOfLength(12)];
        
        _resetTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(_resetTimerFired:) userInfo:Nil repeats:YES];
    }
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    
    [_registration invalidate];
    _registration = nil;
    
    [_resetTimer invalidate];
    _resetTimer = nil;
    
    [_notifier invalidate];
    _notifier = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - OFNetStateNotifierDelegate

- (void)netStateNotifierStateChanged:(OFNetStateNotifier *)notifier;
{
    NSLog(@"state changed");
}

#pragma mark - Private

- (void)_resetTimerFired:(NSTimer *)timer;
{
    [_notifier invalidate];
    
    _notifier = [[OFNetStateNotifier alloc] initWithMemberIdentifier:_memberIdentifier];
    _notifier.monitoredGroupIdentifiers = [NSSet setWithObject:GroupIdentifier];
    _notifier.delegate = self;
}


@end
