// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import SwiftUI
import Combine

internal struct OUIDocumentServerAccountFileInfoView: View {
    @EnvironmentObject var userData: ServerAccountFileListEnvironment
    @ObservedObject var file: File

    var body: some View {
        let file = self.file
        return Button(action: {
            self.userData.open(file: file)
        }) {
            HStack(alignment: .top) {
                ThumbnailFileIcon(imageProvider: userData.thumbnailImageProviderCache.thumbnailImage(for: file.fileURL))
                VStack(alignment: .leading) {
                    Text(file.filename).font(.headline).layoutPriority(2.0)
                    Text(userData.sizeAndDate(for: file)).font(.caption).layoutPriority(3.0)
                    Text(file.folder).font(.caption).layoutPriority(3.0)
                }
                Spacer().layoutPriority(-100.0)
                if !file.isDownloaded {
                    DownloadIcon(isDownloading: file.isDownloading)
                }
            }
        }
    }
}

fileprivate struct ThumbnailFileIcon: View {
    @ObservedObject var imageProvider: DynamicImageProvider

    var body: some View {
        // print("ThumbnailFileIcon: previewImage = \(String(describing: imageProvider.dynamicImage))")
        return FileIcon(optionalImage: imageProvider.dynamicImage)
    }
}

fileprivate let fileIconSize = CGSize(width: 50.0, height: 50.0)

fileprivate struct FileIcon: View {
    var optionalImage: UIImage?

    var body: some View {
        // print("FileIcon: optionalImage = \(String(describing: optionalImage)): \(optionalImage?.pngData()?.base64EncodedString() ?? "")")
        return VStack {
            if optionalImage != nil {
                Image(uiImage: optionalImage!)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }.frame(width: fileIconSize.width, height: fileIconSize.height)
            .cornerRadius(8.0)
            .shadow(radius: 4.0)
    }
}

fileprivate let downloadIconSize = CGSize(width: 35, height: 38.0)

internal struct DownloadIcon: View {
    internal static var bundle: Bundle?

    var isDownloading = false

    var currentImage: UIImage {
        return UIImage(named: isDownloading ? "OmniPresenceDownloadInProgress" : "OmniPresenceDownload", in: DownloadIcon.bundle, compatibleWith: nil)!
    }

    var currentColor: SwiftUI.Color {
        return self.isDownloading ? .secondary : .accentColor
    }

    var body: some View {
        Image(uiImage: currentImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: downloadIconSize.width, height: downloadIconSize.height)
            .foregroundColor(self.currentColor)
    }
}

#if DEBUG
internal struct OUIDocumentServerAccountFileInfoView_Previews: PreviewProvider {
    static var previews: some View {
        let baseURL = URL(fileURLWithPath: NSHomeDirectory())
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAGAAAACACAYAAAD03Gy6AAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAYKADAAQAAAABAAAAgAAAAACiL7qrAAAAHGlET1QAAAACAAAAAAAAAEAAAAAoAAAAQAAAAEAAAAIzbcyKOwAAAf9JREFUeAHsmNFtwzAMRLNpVuhO/c4q3aFrOEBd6EOFI8gyBVI513ofhmGZYc53OlLSbVmWlUvHwQ3ydeQn7hFAXAEQAAG0JUBdgnEADsABLEOFLqAECclnGSomHwEQYO4GjANwAA5gFSR2AQIgwNxlCAfgABzAWZDQBZQgIflsxMTkIwACzN2AcQAOwAGsgsQuQAAEmLsM4QAcgAM4CxK6gBIkJJ+NmJh8BLiaAM/vr/Xn8bGun/fqld6lmKR8uo7i9/Koxkv8+Ts899Ae0CI/k5ZiMmBLfP7dWe5b/Pk7PPdQAawkZcDW+LPFZfwRdwTYKZct0SOIzzkQAAHqDbs1A9Xv8uyNuOMAHIAD/paFXktZlpXbZZwlXl1uyv/f4vfylX4fWoKONlYJPBux19PfUAEiZsRsORBAfB4UKkBvCeqd7Uf5y3od/VyW0F78tfhQASxN1dPELPmjSS/zefAPF6AEu/dcA2IZ28v37nELVmtMqAOsRFjBlXHW/KPjSlyeZwSYeSfcO3NGz2xr/l7crXgcgANed4at2WKdoaPjWhh734U6wLJM9CzjLPlHk+/BXxMnVICjjVICvz0LqgFqjR3lfwf5Hvy1bwsVoPYHjLVLLAJc6SzobLM9umR5S2iNn0s7YETTPnUTrimsHBvVlCO/6dIOQABxg/sPAvwCAAD//0TX0wkAAAHxSURBVO2aQW4DIQxFc9NcoXfqOlfpHXqNqdSprIqKsMExxp7CW0STKMYYf/+PIbkdx3Gu+jrf7+eMl2e+bp7OruZrRvLFp+c6AcDAEgBQyub3481dgsQnACgB+Pr8OD1BEF/iEwCUAHgmapavpfeAWUnz9OsKQI/yoxTu+bd2PaNxjQDiCoBGb8XGGrDG/wgI1rhGxrkCoF28NWCtf6udNa6RcQBQnQNGEmkdCwAAoL+LskqLdpy1ikfGwQAYAAPMbWFLPU2bSBv6XHCuEtQ7KEnyR+5Sev61Wt/ajcbVFuIrn10BeGVibH+ZAADJF3uuAPQkoqV6z76Vilmf27gi2ekKgCyklySxKQvU2Pf8eX1fx1Xii3i6AqBNRlmY1j7KrsQV+QSAnQ9iUZWtnSey8stcMAAGzPnzlLbqa7tSlZFPGLASAzRtZd3uaezrCp35vo7r3zKgd7CSRYpNWWDPfmbCa99tXCW+iKerBEUEvNocALDSXdBq1RmxHhgAA55/IYqouivNAQNgAAz468uvRM1dYkGCkCAkCAlKZAESlJh82ecAAADYA9gDElmABCUmnz0gOfkAAAB7b8AwAAbAALqgZBYAAADsLUMwAAbAAO6CElmABCUmn4NYcvIBAAD23oBhAAyAAXRBySwAgGQAfgCYOUuc4EVCuAAAAABJRU5ErkJggg==")!

        var testFiles: [File] {
            let file1 = File(baseURL: baseURL, fileURL: baseURL.appendingPathComponent("somewhere/whatever1.txt"))
            let file2 = File(baseURL: baseURL, fileURL: baseURL.appendingPathComponent("somewhere/whatever2.txt"))
            file2.isDownloading = true
            let file3 = File(baseURL: baseURL, fileURL: baseURL.appendingPathComponent("some/other/folder/A Very Long Filename That Might Even Want To Wrap To Another Line Of Text Because There Is No Room On This One.txt"))
            return [file1, file2, file3]
        }

        let stack = VStack {
            FileIcon(optionalImage: UIImage(data: pngData)!)
            FileIcon(optionalImage: UIImage(named: "OmniPresenceDownload"))
            ThumbnailFileIcon(imageProvider: TestImageProvider())
            List(testFiles, id: \.self) { testFile in
                OUIDocumentServerAccountFileInfoView(file: testFile)
            }
        }
        return stack
            .environmentObject(ServerAccountFileListEnvironment.previewUserData)
    }
}
#endif

