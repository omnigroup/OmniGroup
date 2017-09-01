// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIServerAccountValidationViewController.h"

#import <OmniDAV/ODAVErrors.h>
#import <OmniFileExchange/OFXErrors.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXServerAccountValidator.h>
#import <OmniUI/OUICertificateTrustAlert.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIInteractionLock.h>
#import <OmniFoundation/NSObject-OFExtensions.h>

RCS_ID("$Id$")

@interface OUIServerAccountValidationViewController ()

@property(nonatomic,strong) IBOutlet UIView *statusView;
@property(nonatomic,strong) IBOutlet UILabel *serverInfoLabel;
@property(nonatomic,strong) IBOutlet UILabel *stateLabel;
@property(nonatomic,strong) IBOutlet UIProgressView *progressView;

@property(nonatomic,strong) IBOutlet UIView *successView;
@property(nonatomic,strong) IBOutlet UIImageView *successImageView;
@property(nonatomic,strong) IBOutlet UILabel *successLabel;

@end

@implementation OUIServerAccountValidationViewController
{
    OFXServerAccount *_account;
    NSString *_username;
    NSString *_password;
    
    id <OFXServerAccountValidator> _accountValidator;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithAccount:(OFXServerAccount *)account username:(NSString *)username password:(NSString *)password;
{
    if (!(self = [super initWithNibName:NSStringFromClass([self class]) bundle:OMNI_BUNDLE]))
        return nil;
    
    _account = account;
    _username = [username copy];
    _password = [password copy];
    
    return self;
}

- (void)startValidation;
{
    OBPRECONDITION(_accountValidator == nil);
    
    _accountValidator = [_account.type validatorWithAccount:_account username:_username password:_password];
    
    __weak OUIServerAccountValidationViewController *weakSelf = self;
    
    _accountValidator.stateChanged = ^(id <OFXServerAccountValidator> validator){
        OBASSERT([NSThread isMainThread]);
        
        OUIServerAccountValidationViewController *strongSelf = weakSelf;
        if (!strongSelf)
            return;
                
        strongSelf->_stateLabel.text = validator.state;
        [strongSelf->_progressView setProgress:validator.percentDone animated:YES];
    };
    
    OFXServerAccount *account = _accountValidator.account;
    _accountValidator.finished = ^(NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        
        OUIServerAccountValidationViewController *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_accountValidator = nil;
        
        if (errorOrNil) {
            NSError *certFailure = [errorOrNil underlyingErrorWithDomain:ODAVErrorDomain code:ODAVCertificateNotTrusted];
            if (certFailure) {
                NSURLAuthenticationChallenge *challenge = [[certFailure userInfo] objectForKey:ODAVCertificateTrustChallengeErrorKey];
                OUICertificateTrustAlert *certAlert = [[OUICertificateTrustAlert alloc] initForChallenge:challenge];
                certAlert.storeResult = YES;
                certAlert.shouldOfferTrustAlwaysOption = YES;
                certAlert.trustBlock = ^(OFCertificateTrustDuration trustDuration) {
                    [strongSelf startValidation]; // ... and try again!
                };
                certAlert.cancelBlock = ^{
                    // We already posted an alert, don't pass back the certificate failure error here.
                    [strongSelf _finishedAddingAccount:nil withError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
                };
                [certAlert findViewController:^{ return strongSelf; }];
                [[[OUIAppController sharedController] backgroundPromptQueue] addOperation:certAlert];
            } else {
                [strongSelf _finishedAddingAccount:nil withError:errorOrNil];
            }
        } else {
            [strongSelf _finishedAddingAccount:account withError:nil];
        }
    };
    
    _stateLabel.text = NSLocalizedStringFromTableInBundle(@"Validating account...", @"OmniUIDocument", OMNI_BUNDLE, @"Account validation status string.");
    
    [_accountValidator startValidation];
}

#pragma mark - OUIActionViewController

- (void)finishWithError:(NSError *)error;
{
    _accountValidator = nil;
    [super finishWithError:error];
}

#pragma mark - UIViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    _successView.alpha = 0;
    _successView.hidden = YES;
    _successView.transform = CGAffineTransformMakeScale(0.75, 0.75);
    
    _successLabel.text = NSLocalizedStringFromTableInBundle(@"Connected", @"OmniUIDocument", OMNI_BUNDLE, @"Success label when connecting to an OmniPresence or WebDAV server account");
    _successImageView.image = [UIImage imageNamed:@"OUIServerAccountValidationSuccess" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];

    UINavigationItem *navigationItem = self.navigationItem;

    [navigationItem setHidesBackButton:YES];
    navigationItem.title = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Setting up \"%@\"", @"OmniUIDocument", OMNI_BUNDLE, @"Label format when setting up an OmniPresence or WebDAV server account"), _account.displayName];
    _serverInfoLabel.text = @" "; // leave empty for now since we have moved the info to the navigationItem's title while we hide the backButton
    _stateLabel.text = @" "; // Lame; reserve the space to autolayout won't squish us.
    
    // We use white in the xib, but I suppose we could set it to clear. Setting 'Default' makes the background black in Xcode's editor.
//    self.view.backgroundColor = nil;
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];

    if (!_accountValidator)
        [self startValidation];
}

#pragma mark - Private

- (void)_finishedAddingAccount:(OFXServerAccount *)account withError:(NSError *)error;
{
    if (!account) {
        [self finishWithError:error];
        return;
    }
    
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    // +animateKeyframesWithDuration: ... doesn't allow selecting the spring effect, strangely.
    [UIView animateWithDuration:0.15 animations:^{
        // Delay a bit to let the progress bar be triumphantly at 100% for a bit. If we add the account to the registery and *then* delay, our dismissal animation can wedge (possibly due to the animations on the home screen/preview generation)
        [_progressView setProgress:1];
        [_progressView layoutIfNeeded];
    } completion:^(BOOL mainFinished) {
        [UIView animateWithDuration:0.20 animations:^{
            _statusView.alpha = 0;
        }];
        [UIView animateWithDuration:0.3 delay:0.15 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
            _successView.hidden = NO;
            _successView.alpha = 1;
            _successView.transform = CGAffineTransformIdentity;
        } completion:^(BOOL secondFinished) {
            OFAfterDelayPerformBlock(0.8750, ^{
                // Determine if this is a new account or if we are changing the configuration on an existing one. We have to be careful of the case where our first attempt fails (invalid credentials, server down). In this case, _account will be non-nil on entry to this method.
                OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
                if ([[registry allAccounts] containsObject:account] == NO) {
                    __autoreleasing NSError *addError = nil;
                    if (![registry addAccount:account error:&addError]) {
                        [self finishWithError:addError];
                        return;
                    }
                }
                
                [self finishWithError:error];
                [lock unlock];
            });
        }];
    }];
}

@end
