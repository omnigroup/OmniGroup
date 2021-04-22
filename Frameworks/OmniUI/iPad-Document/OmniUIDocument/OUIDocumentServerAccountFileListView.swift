// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import SwiftUI

internal struct FileList: View {
    @EnvironmentObject var userData: ServerAccountFileListEnvironment
    var body: some View {
        VStack {
            Header()
            Divider()
            Toolbar()
            Divider()
            List(userData.files, id: \.self) { file in
                OUIDocumentServerAccountFileInfoView(file: file)
            }
        }
    }
}

fileprivate struct HelpButton: View {
    @EnvironmentObject var userData: ServerAccountFileListEnvironment
    var body: some View {
        HStack {
            Spacer()
            Button(action: {
                self.userData.serverAccount.requestHelp()
            }) {
                Image(uiImage: UIImage(systemName: "questionmark.circle")!)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 24.0)
            }
        }
    }
}

fileprivate struct Header: View {
    @EnvironmentObject var userData: ServerAccountFileListEnvironment
    @State var isDownloading = false

    var subheaderText: String {
        let totalFileCount = userData.totalFileCount
        let downloadedFileCount = userData.downloadedFileCount
        let totalFileSizeString = userData.humanReadableString(for: userData.totalFileSize)
        if downloadedFileCount == totalFileCount {
            let format = userData.localizedAccountStatusItemsAndSizeFormat
            return NSString(format: format as NSString, "\(totalFileCount)", totalFileSizeString) as String
        } else {
            let downloadedFileSizeString = userData.humanReadableString(for: userData.downloadedFileSize)
            let format = userData.localizedAccountStatusItemsAndSizeWithDownloadsFormat as NSString
            return NSString(format: format, "\(totalFileCount)", totalFileSizeString, "\(downloadedFileCount)", downloadedFileSizeString) as String
        }
    }

    var body: some View {
        VStack {
            ZStack {
                Image(uiImage: UIImage(named: "OmniPresenceAccountIcon", in: DownloadIcon.bundle, compatibleWith: nil)!)
                    .renderingMode(.template).foregroundColor(.blue)
                HelpButton()
            }

            Text(userData.accountName).font(.title)
            Text(subheaderText).font(.subheadline)
            if userData.hasErrorStatus {
                Text(userData.statusText ?? "").font(.subheadline).foregroundColor(.red)
            } else {
                Text(userData.statusText ?? "").font(.subheadline)
            }
        }.padding()
    }
}

fileprivate let downloadIconSize = CGSize(width: 40.0, height: 36.0)

fileprivate struct Toolbar: View {
    @EnvironmentObject var userData: ServerAccountFileListEnvironment
    @State var isDownloading = false

    var body: some View {
        HStack {
            SortControl().layoutPriority(1)
            Spacer(minLength: 0.0)
            Button(action: {
                self.userData.serverAccount.requestSync()
            }) {
                Image(uiImage: UIImage(named: "OmniPresenceAccountIcon", in: DownloadIcon.bundle, compatibleWith: nil)!)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48.0, height: 24.0)
            }
            Button(action: {
                guard !self.isDownloading else { return }
                self.userData.downloadAllFiles()
                self.isDownloading = true
            }) {
                if userData.hasUnrequestedDownloadsAvailable {
                    DownloadIcon(isDownloading: isDownloading)
                } else {
                    DownloadIcon(isDownloading: isDownloading)
                        .hidden()
                }
            }
        }.padding(.horizontal)
    }
}

fileprivate struct SortControl: View {
    @EnvironmentObject var userData: ServerAccountFileListEnvironment

    var sortOrderString: String {
        switch userData.sortOrder {
        case .path: return userData.localizedSortOrderFolderAndName
        case .size: return userData.localizedSortOrderSize
        case .modificationDate: return userData.localizedSortOrderModificationDate
        case .name: return userData.localizedSortOrderName
        }
    }

    var nextSortOrder: SortOrder {
        switch userData.sortOrder {
        case .path: return .size
        case .size: return .modificationDate
        case .modificationDate: return .name
        case .name: return .path
        }
    }

    var body: some View {
        HStack {
            Text(self.userData.localizedSortLabel)
            Button(action: {
                withAnimation(.easeInOut(duration: 0)) {
                    self.userData.sortOrder = self.nextSortOrder
                }
            }) {
                Text(self.sortOrderString)
            }
        }
        .allowsTightening(true)
        .minimumScaleFactor(1.0)
        .lineLimit(2)
    }
}

#if DEBUG

internal struct FileList_Previews: PreviewProvider {
    static func fileList() -> some View {
        FileList()
            .environmentObject(ServerAccountFileListEnvironment.previewUserData)
    }
    static var previews: some View {
        Group {
            fileList().previewDevice("iPhone SE")
            fileList().previewDevice("iPhone Xs")
            fileList().previewDevice("iPad Pro (11-inch)")
        }
    }
}

#endif

