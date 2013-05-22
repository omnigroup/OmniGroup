// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIServerAccountValidationViewController.h"

#import <OmniFileExchange/OFXErrors.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXServerAccountValidator.h>
#import <OmniFileStore/Errors.h>
#import <OmniUI/OUICertificateTrustAlert.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$")

@interface OUIServerAccountValidationViewController ()
@property(nonatomic,strong) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property(nonatomic,strong) IBOutlet UILabel *stateLabel;
@property(nonatomic,strong) IBOutlet UIImageView *stateImageView;
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
    };
    
    OFXServerAccount *account = _accountValidator.account;
    _accountValidator.finished = ^(NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        
        OUIServerAccountValidationViewController *strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        strongSelf->_accountValidator = nil;
        
        if (errorOrNil) {
            if ([errorOrNil hasUnderlyingErrorDomain:OFSErrorDomain code:OFSCertificateNotTrusted]) {
                NSURLAuthenticationChallenge *challenge = [[errorOrNil userInfo] objectForKey:OFSCertificateTrustChallengeErrorKey];
                OUICertificateTrustAlert *certAlert = [[OUICertificateTrustAlert alloc] initForChallenge:challenge];
                certAlert.trustBlock = ^(OFCertificateTrustDuration trustDuration) {
                    OFAddTrustForChallenge(challenge, trustDuration);
                    [strongSelf startValidation]; // ... and try again!
                };
                certAlert.cancelBlock = ^{
                    // We already posted an alert, don't pass back the certificate failure error here.
                    [strongSelf finishWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
                };
                [certAlert show];
            } else {
                [strongSelf finishWithError:errorOrNil];
            }
        } else {
            
            // Determine if this is a new account or if we are changing the configuration on an existing one. We have to be careful of the case where our first attempt fails (invalid credentials, server down). In this case, _account will be non-nil on entry to this method.
            OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
            if ([[registry allAccounts] containsObject:account] == NO) {
                __autoreleasing NSError *addError = nil;
                if (![registry addAccount:account error:&addError]) {
                    [strongSelf finishWithError:addError];
                    return;
                }
            }
            [strongSelf finishWithError:nil];
        }
    };
    
    _stateLabel.text = NSLocalizedStringFromTableInBundle(@"Validating account...", @"OmniUIDocument", OMNI_BUNDLE, @"Account validation status string.");
    [_activityIndicatorView startAnimating];
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
    
    // We use white in the xib, but I suppose we could set it to clear. Setting 'Default' makes the background black in Xcode's editor.
    self.view.backgroundColor = nil;
}

- (void)viewDidAppear:(BOOL)animated;
{
    OBPRECONDITION(_activityIndicatorView);
    OBPRECONDITION(_stateImageView);
    
    [super viewDidAppear:animated];
    
    if (!_accountValidator)
        [self startValidation];
}

@end
