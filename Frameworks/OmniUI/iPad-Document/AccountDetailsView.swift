// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import SwiftUI

import OmniFileExchange

protocol AccountDetails {
    var displayName: String { get }
    var remoteBaseURL: URL { get }
    
    func startMigration() throws
}

@objc(OUIAccountConfiguration) public class AccountConfiguration : NSObject, AccountDetails {
    let activity: OFXAgentActivity
    let account: OFXServerAccount
    
    init(activity: OFXAgentActivity, account: OFXServerAccount) {
        self.activity = activity
        self.account = account
    }
    
    var displayName: String {
        return account.displayName
    }
    var remoteBaseURL: URL {
        return account.remoteBaseURL
    }
    
    func startMigration() throws {
        try activity.agent.startMigratingAccount(account, activity: activity) { error in
            print("error \(error)")
            fatalError("finish")
        }
    }
}

struct AccountDetailsView : View {
    
    private let account: AccountDetails
    
    init(account: AccountDetails) {
        self.account = account
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Account Name:")
                Text(account.displayName)
            }
            HStack {
                Text("URL:")
                Text(account.remoteBaseURL.absoluteString)
            }
            Button("Migrate") {
                do {
                    try self.account.startMigration()
                } catch let err {
                    fatalError("finish") // present the error somehow.
                }
            }
        }
    }
}

#if DEBUG

struct PreviewAccountDetails : AccountDetails {
    let displayName = "My Account"
    let remoteBaseURL = URL(string: "https://www.example.com/myaccount/")!
    
    func startMigration() {
        print("migrate!")
    }
}

struct AccountDetailsView_Previews : PreviewProvider {
    static var previews: some View {
        AccountDetailsView(account: PreviewAccountDetails())
    }
}
#endif
